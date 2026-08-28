#!/usr/bin/env python3
"""Rephraze usage backend: an ingest endpoint and a dashboard, in one file.

Standard library only -- no pip, no virtualenv, no build. `python3 server.py`
and it runs; the same command works on a VPS behind nginx or in a container.

    POST /v1/events    the app posts batches here. No auth: clients are
                       anonymous by design, so there is no credential to give
                       them that would not immediately be public.
    POST /v1/tickets   one support report, sent straight on as an email. The
                       Resend key lives here rather than in the app, because a
                       key inside a distributed binary is not a key.
    GET  /             the dashboard. Token required.
    GET  /healthz      liveness, for whatever is watching the process.

Storage is SQLite, which is the right size for this: a few events per user per
day, one writer, read-mostly. It is a single file you can copy, and if this ever
outgrows it the queries below are ordinary SQL that Postgres will run unchanged.

Configuration, all through the environment:

    REPHRAZE_DASHBOARD_TOKEN   required to view the dashboard; no default
    REPHRAZE_DB                path to the SQLite file (default ./usage.db)
    REPHRAZE_PORT              default 8787
    REPHRAZE_HOST              default 127.0.0.1

Support email has three more, all read by `tickets.py`: RESEND_API_KEY,
REPHRAZE_TICKET_FROM and REPHRAZE_TICKET_TO. Without them /v1/tickets answers
503 and the app falls back to the user's own mail client.
"""

from __future__ import annotations

import hmac
import json
import os
import re
import sqlite3
import threading
import time
from collections import defaultdict, deque
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

import tickets

# --- Configuration -----------------------------------------------------------

DB_PATH = os.environ.get("REPHRAZE_DB", "usage.db")
PORT = int(os.environ.get("REPHRAZE_PORT", "8787"))
HOST = os.environ.get("REPHRAZE_HOST", "127.0.0.1")
DASHBOARD_TOKEN = os.environ.get("REPHRAZE_DASHBOARD_TOKEN", "")

# A batch is at most 100 events of a handful of small fields. Anything near this
# is not one of our clients.
MAX_BODY_BYTES = 256 * 1024
MAX_EVENTS_PER_BATCH = 100

# Per-IP ingest ceiling. The endpoint is necessarily public, so it needs some
# floor under it; this is generous for a real client (a batch every 5 minutes)
# and useless to anyone trying to fill the disk.
RATE_LIMIT_REQUESTS = 60
RATE_LIMIT_WINDOW_SECONDS = 60

# A report is a few paragraphs and a short table of settings, so it gets a much
# smaller ceiling than a batch of events.
MAX_TICKET_BYTES = 64 * 1024

# Every accepted report becomes an email in a real inbox, so this ceiling is
# about what one person can plausibly write rather than about bandwidth: room
# to send a report, notice a typo and send it again, and no use at all to
# anyone hoping to flood the inbox.
TICKET_RATE_LIMIT = 5
TICKET_RATE_WINDOW_SECONDS = 3600

UUID_RE = re.compile(r"^[0-9A-Fa-f-]{36}$")

# --- The schema the server is willing to accept ------------------------------
#
# Properties are flattened into typed columns rather than stored as a JSON blob.
# That keeps the dashboard queries plain SQL, and it has a second property worth
# more than that: the server physically cannot store a field it was not told
# about in advance. If a future client sends something new -- by accident or by
# a bug -- it lands nowhere. The privacy promise on the client is enforced again
# here rather than trusted.

EVENT_SCHEMA: dict[str, dict[str, type]] = {
    "launched": {},
    "rephrased": {"outcome": str, "personalised": bool, "milliseconds": int},
    "translated": {"language": str},
    "failed": {"reason": str},
}

# Values the client can legitimately send. Anything else is dropped, so a
# dashboard grouping can never be polluted by junk.
ENUMS = {
    "outcome": {"accepted", "dismissed"},
    "reason": {"rephrase", "write"},
    "language": {
        "english", "spanish", "chinese", "hindi", "arabic",
        "french", "portuguese", "russian", "german", "japanese",
    },
}

PROPERTY_COLUMNS = ("outcome", "personalised", "milliseconds", "language", "reason")

SCHEMA = """
CREATE TABLE IF NOT EXISTS events (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    install_id   TEXT    NOT NULL,
    name         TEXT    NOT NULL,
    at           TEXT    NOT NULL,
    day          TEXT    NOT NULL,
    app_version  TEXT    NOT NULL,
    system       TEXT    NOT NULL,
    outcome      TEXT,
    personalised INTEGER,
    milliseconds INTEGER,
    language     TEXT,
    reason       TEXT,
    received_at  TEXT    NOT NULL
);
CREATE INDEX IF NOT EXISTS events_day  ON events (day);
CREATE INDEX IF NOT EXISTS events_name ON events (name, day);
CREATE INDEX IF NOT EXISTS events_inst ON events (install_id);

CREATE TABLE IF NOT EXISTS installs (
    install_id  TEXT PRIMARY KEY,
    first_seen  TEXT NOT NULL,
    last_seen   TEXT NOT NULL,
    app_version TEXT NOT NULL,
    system      TEXT NOT NULL
);
"""

_db_lock = threading.Lock()
_db: sqlite3.Connection | None = None


def db() -> sqlite3.Connection:
    global _db
    if _db is None:
        _db = sqlite3.connect(DB_PATH, check_same_thread=False)
        _db.row_factory = sqlite3.Row
        # WAL: new writes go to a side file and are folded in later, so a power
        # cut takes the last write rather than the database, and the dashboard
        # can read while events are still arriving. NORMAL trades a fsync per
        # commit for the tiny risk of losing the last moment of events on a
        # hard crash -- the right trade for telemetry, not for money.
        _db.execute("PRAGMA journal_mode=WAL")
        _db.execute("PRAGMA synchronous=NORMAL")
        _db.execute("PRAGMA busy_timeout=5000")
        _db.executescript(SCHEMA)
        _db.commit()
    return _db


# --- Ingest ------------------------------------------------------------------

def parse_timestamp(raw: str) -> datetime | None:
    """Read the client's ISO-8601 stamp, or give up on this event."""
    try:
        value = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def clean_event(raw: object) -> dict | None:
    """Return a row's worth of columns, or None if this is not one of ours."""
    if not isinstance(raw, dict):
        return None

    name = raw.get("name")
    if name not in EVENT_SCHEMA:
        return None

    at = parse_timestamp(raw.get("at", ""))
    if at is None:
        return None

    # A clock skewed into next year would stretch every chart's axis.
    now = datetime.now(timezone.utc)
    if at > now + timedelta(days=1) or at < now - timedelta(days=90):
        return None

    row = {"name": name, "at": at.isoformat(), "day": at.date().isoformat()}
    for column in PROPERTY_COLUMNS:
        row[column] = None

    properties = raw.get("properties") or {}
    if not isinstance(properties, dict):
        return None

    for key, expected in EVENT_SCHEMA[name].items():
        value = properties.get(key)
        if expected is bool:
            if isinstance(value, bool):
                row[key] = 1 if value else 0
        elif expected is int:
            # bool is a subclass of int in Python; reject it explicitly.
            if isinstance(value, int) and not isinstance(value, bool):
                row[key] = max(0, min(value, 120_000))
        elif expected is str:
            if isinstance(value, str) and value in ENUMS.get(key, {value}):
                row[key] = value
    return row


def store(batch: dict) -> int:
    install_id = batch.get("installID", "")
    if not isinstance(install_id, str) or not UUID_RE.match(install_id):
        raise ValueError("bad install id")

    app_version = str(batch.get("appVersion", ""))[:32]
    system = str(batch.get("system", ""))[:120]

    events = batch.get("events")
    if not isinstance(events, list) or len(events) > MAX_EVENTS_PER_BATCH:
        raise ValueError("bad events")

    rows = [event for event in (clean_event(item) for item in events) if event]
    if not rows:
        return 0

    received = datetime.now(timezone.utc).isoformat()
    # Both ends, from this batch's own events. Batches arrive out of order and a
    # backlog can carry a week of them at once, so neither bound can be assumed
    # from arrival time.
    earliest = min(row["at"] for row in rows)
    latest = max(row["at"] for row in rows)

    with _db_lock:
        connection = db()
        connection.executemany(
            """INSERT INTO events
               (install_id, name, at, day, app_version, system,
                outcome, personalised, milliseconds, language, reason, received_at)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?)""",
            [
                (
                    install_id, row["name"], row["at"], row["day"], app_version, system,
                    row["outcome"], row["personalised"], row["milliseconds"],
                    row["language"], row["reason"], received,
                )
                for row in rows
            ],
        )
        connection.execute(
            """INSERT INTO installs (install_id, first_seen, last_seen, app_version, system)
               VALUES (?,?,?,?,?)
               ON CONFLICT(install_id) DO UPDATE SET
                   first_seen  = MIN(first_seen, excluded.first_seen),
                   last_seen   = MAX(last_seen, excluded.last_seen),
                   app_version = excluded.app_version,
                   system      = excluded.system""",
            (install_id, earliest, latest, app_version, system),
        )
        connection.commit()
    return len(rows)


# --- Metrics -----------------------------------------------------------------

def query(sql: str, args: tuple = ()) -> list[sqlite3.Row]:
    with _db_lock:
        return db().execute(sql, args).fetchall()


def scalar(sql: str, args: tuple = (), default=0):
    rows = query(sql, args)
    if not rows or rows[0][0] is None:
        return default
    return rows[0][0]


def active_since(days: int) -> int:
    since = (datetime.now(timezone.utc) - timedelta(days=days)).date().isoformat()
    return scalar(
        "SELECT COUNT(DISTINCT install_id) FROM events WHERE day >= ?", (since,)
    )


def daily_series(days: int = 30) -> list[tuple[str, int]]:
    """One entry per calendar day, zeros included -- a chart with missing days
    silently redraws its own x-axis and lies about the shape."""
    today = datetime.now(timezone.utc).date()
    start = today - timedelta(days=days - 1)
    counts = {
        row["day"]: row["n"]
        for row in query(
            "SELECT day, COUNT(*) AS n FROM events "
            "WHERE name = 'rephrased' AND day >= ? GROUP BY day",
            (start.isoformat(),),
        )
    }
    return [
        ((start + timedelta(days=offset)).isoformat(),
         counts.get((start + timedelta(days=offset)).isoformat(), 0))
        for offset in range(days)
    ]


def breakdown(column: str, where: str, limit: int = 10) -> list[tuple[str, int]]:
    rows = query(
        f"SELECT {column} AS k, COUNT(*) AS n FROM events "
        f"WHERE {where} AND {column} IS NOT NULL "
        f"GROUP BY {column} ORDER BY n DESC LIMIT ?",
        (limit,),
    )
    return [(row["k"], row["n"]) for row in rows]


def retention_d7() -> tuple[int, int]:
    """Of the installs old enough to have had the chance, how many were still
    here a week later. Returns (retained, eligible)."""
    rows = query(
        "SELECT install_id, first_seen, last_seen FROM installs "
        "WHERE first_seen <= ?",
        ((datetime.now(timezone.utc) - timedelta(days=8)).isoformat(),),
    )
    eligible = retained = 0
    for row in rows:
        first, last = parse_timestamp(row["first_seen"]), parse_timestamp(row["last_seen"])
        if not first or not last:
            continue
        eligible += 1
        if last - first >= timedelta(days=7):
            retained += 1
    return retained, eligible


def metrics() -> dict:
    thirty_days = (datetime.now(timezone.utc) - timedelta(days=30)).date().isoformat()

    accepted = scalar(
        "SELECT COUNT(*) FROM events WHERE name='rephrased' AND outcome='accepted' AND day >= ?",
        (thirty_days,),
    )
    concluded = scalar(
        "SELECT COUNT(*) FROM events WHERE name='rephrased' AND day >= ?", (thirty_days,)
    )
    personalised = scalar(
        "SELECT COUNT(*) FROM events WHERE name='rephrased' AND personalised=1 AND day >= ?",
        (thirty_days,),
    )
    retained, eligible = retention_d7()

    return {
        "installs": scalar("SELECT COUNT(*) FROM installs"),
        "active_1": active_since(1),
        "active_7": active_since(7),
        "active_30": active_since(30),
        "rephrases_30": concluded,
        "accepted": accepted,
        "concluded": concluded,
        "personalised": personalised,
        "median_ms": scalar(
            "SELECT milliseconds FROM events WHERE name='rephrased' AND milliseconds > 0 "
            "AND day >= ? ORDER BY milliseconds LIMIT 1 "
            "OFFSET (SELECT COUNT(*)/2 FROM events WHERE name='rephrased' "
            "AND milliseconds > 0 AND day >= ?)",
            (thirty_days, thirty_days),
        ),
        "failures": scalar(
            "SELECT COUNT(*) FROM events WHERE name='failed' AND day >= ?", (thirty_days,)
        ),
        "retained": retained,
        "eligible": eligible,
        "series": daily_series(30),
        "languages": breakdown("language", "name='translated'"),
        "failure_reasons": breakdown("reason", "name='failed'"),
        "versions": breakdown("app_version", "1=1", limit=6),
    }


# --- Dashboard ---------------------------------------------------------------
#
# One hue, because every chart here is a single series -- a second colour would
# be decoration claiming to be information. Bars carry the colour; every piece
# of text stays in an ink token.

CSS = """
:root {
  color-scheme: light;
  --surface: #fcfcfb; --raised: #ffffff; --line: #e6e4df;
  --ink: #0b0b0b; --ink-2: #52514e; --ink-3: #8a8880;
  --series: #2a78d6; --track: #ecebe7;
}
@media (prefers-color-scheme: dark) {
  :root {
    color-scheme: dark;
    --surface: #1a1a19; --raised: #212120; --line: #34342f;
    --ink: #ffffff; --ink-2: #c3c2b7; --ink-3: #8d8c83;
    --series: #3987e5; --track: #2b2b28;
  }
}
* { box-sizing: border-box; }
body {
  margin: 0; padding: 32px 24px 64px;
  background: var(--surface); color: var(--ink);
  font: 14px/1.5 ui-sans-serif, -apple-system, "Helvetica Neue", Arial, sans-serif;
  -webkit-font-smoothing: antialiased;
}
.wrap { max-width: 1040px; margin: 0 auto; }
h1 { font-size: 19px; font-weight: 600; margin: 0 0 2px; letter-spacing: -0.01em; }
.sub { color: var(--ink-3); font-size: 12.5px; margin: 0 0 28px; }
h2 {
  font-size: 12px; font-weight: 600; text-transform: uppercase;
  letter-spacing: 0.07em; color: var(--ink-3); margin: 34px 0 12px;
}
.hero { margin: 0 0 26px; }
.hero .n {
  font-size: 52px; font-weight: 600; letter-spacing: -0.03em;
  line-height: 1.05; font-variant-numeric: tabular-nums;
}
.hero .l { color: var(--ink-2); font-size: 13px; margin-top: 2px; }
.tiles { display: grid; grid-template-columns: repeat(auto-fit, minmax(148px, 1fr)); gap: 10px; }
.tile { background: var(--raised); border: 1px solid var(--line); border-radius: 10px; padding: 13px 14px; }
.tile .l { color: var(--ink-2); font-size: 11.5px; }
.tile .n {
  font-size: 23px; font-weight: 600; letter-spacing: -0.02em;
  margin-top: 3px; font-variant-numeric: tabular-nums;
}
.tile .m { color: var(--ink-3); font-size: 11px; margin-top: 1px; }
.card { background: var(--raised); border: 1px solid var(--line); border-radius: 10px; padding: 16px 18px 12px; }

/* Column chart. Gridlines sit behind; the 2px gap between columns is surface,
   not a stroke. */
.chart { position: relative; height: 168px; margin: 6px 0 0; }
.grid { position: absolute; inset: 0; display: flex; flex-direction: column; justify-content: space-between; }
.grid div { border-top: 1px solid var(--line); height: 0; }
.cols { position: absolute; inset: 0; display: flex; align-items: flex-end; gap: 2px; }
.col { flex: 1; position: relative; height: 100%; display: flex; align-items: flex-end; justify-content: center; }
.col i { display: block; width: 100%; max-width: 24px; background: var(--series); border-radius: 4px 4px 0 0; min-height: 1px; }
.col.zero i { background: var(--track); }
.col b {
  position: absolute; bottom: 100%; left: 50%; transform: translateX(-50%);
  margin-bottom: 5px; font-size: 11px; font-weight: 600; white-space: nowrap;
  color: var(--ink-2); font-variant-numeric: tabular-nums;
}
.col span {
  position: absolute; bottom: 100%; left: 50%; transform: translateX(-50%);
  margin-bottom: 6px; background: var(--ink); color: var(--surface);
  font-size: 11px; padding: 4px 7px; border-radius: 6px; white-space: nowrap;
  opacity: 0; pointer-events: none; transition: opacity .1s; z-index: 3;
}
.col:hover span { opacity: 1; }
.axis { display: flex; justify-content: space-between; color: var(--ink-3); font-size: 11px; margin-top: 7px; }
.yaxis { position: absolute; inset: 0 auto 0 -34px; width: 30px; display: flex;
  flex-direction: column; justify-content: space-between; text-align: right;
  color: var(--ink-3); font-size: 10.5px; font-variant-numeric: tabular-nums; }

/* Horizontal bars: label outside the bar end, never inside it. */
.rows { display: flex; flex-direction: column; gap: 7px; }
.row { display: grid; grid-template-columns: 116px 1fr 48px; align-items: center; gap: 10px; }
.row .k { color: var(--ink-2); font-size: 12.5px; text-transform: capitalize;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.row .t { background: var(--track); border-radius: 4px; height: 14px; }
.row .t i { display: block; height: 100%; background: var(--series); border-radius: 4px; min-width: 2px; }
.row .v { text-align: right; font-size: 12.5px; color: var(--ink-2); font-variant-numeric: tabular-nums; }
.grids { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 16px; }
.empty { color: var(--ink-3); font-size: 12.5px; padding: 8px 0 14px; }
details { margin-top: 14px; }
summary { color: var(--ink-3); font-size: 12px; cursor: pointer; }
table { border-collapse: collapse; margin-top: 10px; font-size: 12.5px; width: 100%; }
th, td { text-align: left; padding: 4px 12px 4px 0; border-bottom: 1px solid var(--line); }
th { color: var(--ink-3); font-weight: 500; }
td:last-child, th:last-child { text-align: right; font-variant-numeric: tabular-nums; }
"""


def esc(value: object) -> str:
    return (
        str(value).replace("&", "&amp;").replace("<", "&lt;")
        .replace(">", "&gt;").replace('"', "&quot;")
    )


def compact(n: int) -> str:
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M".replace(".0M", "M")
    if n >= 10_000:
        return f"{n / 1000:.1f}K".replace(".0K", "K")
    return f"{n:,}"


def percent(part: int, whole: int) -> str:
    return "--" if not whole else f"{round(100 * part / whole)}%"


def tile(label: str, value: str, note: str = "") -> str:
    meta = f'<div class="m">{esc(note)}</div>' if note else ""
    return (
        f'<div class="tile"><div class="l">{esc(label)}</div>'
        f'<div class="n">{esc(value)}</div>{meta}</div>'
    )


def nice_ceiling(peak: int) -> int:
    """Round the axis up to a number a person would have chosen: 1, 2 or 5 times
    a power of ten. An axis topped at the exact peak reads as a measurement
    rather than a scale."""
    if peak <= 4:
        return 4
    magnitude = 10 ** (len(str(peak)) - 1)
    for step in (1, 1.5, 2, 3, 4, 5, 6, 8, 10):
        candidate = int(step * magnitude)
        if candidate >= peak:
            return candidate
    return peak


def column_chart(series: list[tuple[str, int]]) -> str:
    peak = max((n for _, n in series), default=0)
    ceiling = nice_ceiling(peak)

    columns = []
    for day, count in series:
        height = 100 * count / ceiling
        # Only the peak is labelled. A number over every column is unreadable
        # and goes unread; the axis and the tooltip carry the rest.
        label = f"<b>{count:,}</b>" if count == peak and peak > 0 else ""
        columns.append(
            f'<div class="col{" zero" if count == 0 else ""}">{label}'
            f'<span>{esc(day)} · {count:,}</span>'
            f'<i style="height:{height:.2f}%"></i></div>'
        )

    ticks = "".join(
        f"<div>{compact(ceiling * step // 2)}</div>" for step in (2, 1, 0)
    )
    table_rows = "".join(
        f"<tr><td>{esc(day)}</td><td>{count:,}</td></tr>" for day, count in reversed(series)
    )

    return f"""
    <div class="card">
      <div class="chart">
        <div class="yaxis">{ticks}</div>
        <div class="grid"><div></div><div></div><div></div></div>
        <div class="cols">{''.join(columns)}</div>
      </div>
      <div class="axis"><span>{esc(series[0][0])}</span><span>{esc(series[-1][0])}</span></div>
      <details>
        <summary>Show as a table</summary>
        <table><tr><th>Day</th><th>Rephrases</th></tr>{table_rows}</table>
      </details>
    </div>"""


def bar_rows(title: str, rows: list[tuple[str, int]], empty: str) -> str:
    if not rows:
        body = f'<div class="empty">{esc(empty)}</div>'
    else:
        ceiling = max(n for _, n in rows)
        body = '<div class="rows">' + "".join(
            f'<div class="row"><div class="k">{esc(key)}</div>'
            f'<div class="t"><i style="width:{100 * n / ceiling:.1f}%"></i></div>'
            f'<div class="v">{n:,}</div></div>'
            for key, n in rows
        ) + "</div>"
    return f'<div><h2>{esc(title)}</h2><div class="card">{body}</div></div>'


def dashboard_html(m: dict) -> str:
    generated = datetime.now(timezone.utc).strftime("%d %b %Y, %H:%M UTC")

    tiles = "".join([
        tile("Installs seen", compact(m["installs"]), "all time"),
        tile("Active today", compact(m["active_1"])),
        tile("Active this week", compact(m["active_7"])),
        tile("Active this month", compact(m["active_30"])),
        tile("Accepted", percent(m["accepted"], m["concluded"]),
             f'{m["accepted"]:,} of {m["concluded"]:,}'),
        tile("Used your style", percent(m["personalised"], m["concluded"])),
        tile("Median rephrase", f'{m["median_ms"] / 1000:.1f}s' if m["median_ms"] else "--"),
        tile("Kept after a week", percent(m["retained"], m["eligible"]),
             f'{m["eligible"]:,} old enough to count'),
        tile("Failures", compact(m["failures"]), "last 30 days"),
    ])

    return f"""<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>Rephraze usage</title>
<style>{CSS}</style>
</head><body><div class="wrap">
  <h1>Rephraze usage</h1>
  <p class="sub">Anonymous, opt-in. Generated {esc(generated)}.</p>

  <div class="hero">
    <div class="n">{compact(m["rephrases_30"])}</div>
    <div class="l">rephrases in the last 30 days</div>
  </div>

  <div class="tiles">{tiles}</div>

  <h2>Rephrases per day</h2>
  {column_chart(m["series"])}

  <div class="grids" style="margin-top:16px">
    {bar_rows("Translated into", m["languages"], "No translations reported yet.")}
    {bar_rows("App versions", m["versions"], "Nothing reported yet.")}
    {bar_rows("Failures by kind", m["failure_reasons"], "No failures reported.")}
  </div>
</div></body></html>"""


# --- HTTP --------------------------------------------------------------------

_hits: dict[tuple[str, str], deque] = defaultdict(deque)
_hits_lock = threading.Lock()


def recent(bucket: str, client: str, window: int) -> deque:
    """What this address has done lately, with anything older than the window
    forgotten. The caller holds `_hits_lock`."""
    seen = _hits[(bucket, client)]
    now = time.monotonic()
    while seen and now - seen[0] > window:
        seen.popleft()
    return seen


def rate_limited(
    client: str,
    limit: int = RATE_LIMIT_REQUESTS,
    window: int = RATE_LIMIT_WINDOW_SECONDS,
    bucket: str = "requests",
) -> bool:
    """Has this address used up its allowance? If not, this counts as one."""
    with _hits_lock:
        seen = recent(bucket, client, window)
        if len(seen) >= limit:
            return True
        seen.append(time.monotonic())
        return False


# Support reports get a second, much stricter allowance than the one every
# request passes through -- and it is counted separately, in emails rather
# than requests. Someone who mistypes their address, is told so, and sends
# again has cost the inbox nothing, and should not be turned away for it.

def over_ticket_allowance(client: str) -> bool:
    with _hits_lock:
        return len(recent("tickets", client, TICKET_RATE_WINDOW_SECONDS)) >= TICKET_RATE_LIMIT


def note_ticket_sent(client: str) -> None:
    with _hits_lock:
        _hits[("tickets", client)].append(time.monotonic())


class Handler(BaseHTTPRequestHandler):
    server_version = "rephraze-usage"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} {fmt % args}", flush=True)

    def reply(self, code: int, body: bytes, content_type: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def json(self, code: int, payload: dict) -> None:
        self.reply(code, json.dumps(payload).encode(), "application/json")

    # -- POST

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        if path not in ("/v1/events", "/v1/tickets"):
            return self.json(404, {"error": "not found"})

        # The flood ceiling, ahead of any work: it is about how often this
        # address may knock, whatever it is asking for.
        if rate_limited(self.client_address[0]):
            return self.json(429, {"error": "slow down"})

        if path == "/v1/events":
            return self.ingest_events()
        self.ingest_ticket()

    def read_body(self, limit: int) -> bytes | None:
        """The request body, or None having already answered the client."""
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self.json(400, {"error": "bad length"})
            return None

        if length <= 0 or length > limit:
            self.json(413, {"error": "body too large"})
            return None

        return self.rfile.read(length)

    def ingest_events(self) -> None:
        body = self.read_body(MAX_BODY_BYTES)
        if body is None:
            return

        try:
            stored = store(json.loads(body))
        except (ValueError, TypeError, json.JSONDecodeError):
            # A 4xx tells the client this batch will never be accepted, so it
            # drops it instead of retrying a malformed payload forever.
            return self.json(400, {"error": "bad batch"})
        except sqlite3.Error as error:
            print(f"store failed: {error}", flush=True)
            return self.json(503, {"error": "unavailable"})

        self.json(200, {"stored": stored})

    def ingest_ticket(self) -> None:
        """One support report, on its way to the inbox before this returns.

        Sent inline rather than queued. The sender is watching a spinner and
        the only honest thing to show them is whether it actually went, which
        means waiting for the mail service to say so.
        """
        client = self.client_address[0]
        if over_ticket_allowance(client):
            return self.json(429, {"error": "that is a lot of reports at once"})

        body = self.read_body(MAX_TICKET_BYTES)
        if body is None:
            return

        try:
            ticket = tickets.clean_ticket(json.loads(body))
            message_id = tickets.send(ticket)
        except (ValueError, TypeError, json.JSONDecodeError):
            return self.json(400, {"error": "bad report"})
        except tickets.TicketError as error:
            return self.json(error.status, {"error": error.message})

        note_ticket_sent(client)
        print(f"ticket sent: {tickets.subject_for(ticket)} [{message_id}]", flush=True)
        self.json(200, {"sent": True})

    # -- GET

    def do_GET(self) -> None:
        parsed = urlparse(self.path)

        if parsed.path == "/healthz":
            return self.json(200, {"ok": True})

        if parsed.path != "/":
            return self.json(404, {"error": "not found"})

        if not self.authorised(parsed.query):
            self.send_response(401)
            self.send_header("WWW-Authenticate", 'Bearer realm="rephraze"')
            self.send_header("Content-Length", "0")
            self.end_headers()
            return

        self.reply(200, dashboard_html(metrics()).encode(), "text/html; charset=utf-8")

    def authorised(self, raw_query: str) -> bool:
        if not DASHBOARD_TOKEN:
            return False
        header = self.headers.get("Authorization", "")
        offered = header[7:] if header.startswith("Bearer ") else ""
        if not offered:
            offered = (parse_qs(raw_query).get("token") or [""])[0]
        return hmac.compare_digest(offered, DASHBOARD_TOKEN)


def main() -> None:
    db()
    if not DASHBOARD_TOKEN:
        print("REPHRAZE_DASHBOARD_TOKEN is not set -- the dashboard will refuse "
              "every request. Ingest still works.", flush=True)
    if not tickets.configured():
        print("RESEND_API_KEY, REPHRAZE_TICKET_FROM or REPHRAZE_TICKET_TO is not "
              "set -- support reports will be turned away. See telemetry/README.md.",
              flush=True)
    print(f"Rephraze usage on http://{HOST}:{PORT}  (db: {DB_PATH})", flush=True)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
