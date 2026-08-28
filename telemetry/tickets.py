#!/usr/bin/env python3
"""Support reports: validate one, render it as an email, hand it to Resend.

Standard library only, like the rest of this backend. Lives beside `server.py`
rather than inside it because a support inbox and a usage dashboard have
nothing to do with each other beyond sharing a machine.

Why the app posts here at all, rather than sending the mail itself: an API key
inside a distributed binary is not a secret. Anyone with the app has the key,
and a key that can send mail as you is a key that can send mail as you to
anyone. So the key lives on one server you control, and the app posts a report
to it -- carrying nothing that could not already be shown on screen.

Configuration, all through the environment:

    RESEND_API_KEY           required; without it the endpoint returns 503
    REPHRAZE_TICKET_FROM     the From: address. Must be on a domain verified
                             with Resend, e.g. "Rephraze <support@yourapp.com>"
    REPHRAZE_TICKET_TO       where reports land (your own inbox)
"""

from __future__ import annotations

import json
import os
import re
import urllib.error
import urllib.request
from datetime import datetime, timezone
from html import escape

# --- Configuration -----------------------------------------------------------

RESEND_API_KEY = os.environ.get("RESEND_API_KEY", "")
RESEND_ENDPOINT = "https://api.resend.com/emails"
TICKET_FROM = os.environ.get("REPHRAZE_TICKET_FROM", "")
TICKET_TO = os.environ.get("REPHRAZE_TICKET_TO", "")

# Resend is a normal HTTPS API on a good day and a hung socket on a bad one.
# The sender is watching a spinner, so give up while they are still waiting.
SEND_TIMEOUT_SECONDS = 15

# A report is a few paragraphs and a short table of settings. These are the
# lengths past which text is cut, not the lengths at which it is rejected --
# a long report should arrive trimmed, never vanish.
MAX_SUMMARY = 200
MAX_DETAIL = 8000
MAX_REPLY_TO = 254
MAX_FIELDS = 24
MAX_LABEL = 48
MAX_VALUE = 160

# The three kinds the app offers, and the word that leads the subject line.
KINDS = {"bug": "Bug", "idea": "Idea", "question": "Question"}

# The pill colour behind the kind, matching how the app itself tints things.
KIND_COLOURS = {
    "bug": "#cf3b3a",
    "idea": "#4a3aa7",
    "question": "#2a78d6",
}

# Deliberately conservative: this only has to admit the addresses people
# actually type. Anything exotic is rejected while they can still fix it,
# which is better than a report whose reply bounces a day later.
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s.]+(\.[^@\s.]+)+$")

# Tabs and newlines are legitimate inside the detail; everywhere else they only
# arrive by paste accident or on purpose, and a subject line holding a newline
# is the oldest trick in mail injection.
CONTROL_RE = re.compile(r"[\x00-\x1f\x7f]")


class TicketError(Exception):
    """A report that cannot be sent, and what to tell the client about it."""

    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


# --- What the server is willing to accept ------------------------------------

def one_line(raw: object, limit: int) -> str:
    text = raw if isinstance(raw, str) else ""
    return CONTROL_RE.sub(" ", text).strip()[:limit]


def many_lines(raw: object, limit: int) -> str:
    text = raw if isinstance(raw, str) else ""
    # Keep newlines and tabs; drop the rest of the control range.
    text = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", "", text).replace("\r\n", "\n")
    if len(text) > limit:
        text = text[:limit].rstrip() + "\n\n[cut here — the report was longer than this]"
    return text.strip()


def clean_ticket(raw: object) -> dict:
    """Return the report this server is prepared to send, or raise.

    Every field is named here. A client that grew a new one -- by accident or
    by a bug -- would have it land nowhere, which is the same promise the event
    ingest makes and for the same reason: the app's privacy claim is enforced
    again on this side rather than trusted.
    """
    if not isinstance(raw, dict):
        raise TicketError(400, "not a report")

    kind = raw.get("kind")
    if kind not in KINDS:
        raise TicketError(400, "unknown kind")

    summary = one_line(raw.get("summary"), MAX_SUMMARY)
    if not summary:
        raise TicketError(400, "a summary is required")

    reply_to = one_line(raw.get("replyTo"), MAX_REPLY_TO)
    if reply_to and not EMAIL_RE.match(reply_to):
        # Not dropped quietly: someone who typed an address is expecting an
        # answer, and silently discarding it promises one that never comes.
        raise TicketError(400, "that reply address does not look like an address")

    fields = []
    for item in (raw.get("diagnostics") or [])[:MAX_FIELDS]:
        if not isinstance(item, dict):
            continue
        label = one_line(item.get("label"), MAX_LABEL)
        value = one_line(item.get("value"), MAX_VALUE)
        if label:
            fields.append((label, value))

    return {
        "kind": kind,
        "summary": summary,
        "detail": many_lines(raw.get("detail"), MAX_DETAIL),
        "reply_to": reply_to,
        "fields": fields,
        "received": datetime.now(timezone.utc),
    }


# --- The email ---------------------------------------------------------------

def subject_for(ticket: dict) -> str:
    """Leads with the app and the kind, so a full inbox sorts itself and a
    report can be triaged without being opened."""
    return f"Rephraze {KINDS[ticket['kind']]}: {ticket['summary']}"


def render_text(ticket: dict) -> str:
    """The plain-text half. Not a formality -- it is what shows in a
    notification, a watch, and any client set to prefer text."""
    lines = [
        subject_for(ticket),
        "",
        f"From:     {ticket['reply_to'] or 'no reply address given'}",
        f"Received: {stamp(ticket['received'])}",
        "",
        ticket["detail"] or "(no details written)",
    ]
    if ticket["fields"]:
        width = max(len(label) for label, _ in ticket["fields"])
        lines += ["", "---"]
        lines += [f"{label.ljust(width)}  {value}" for label, value in ticket["fields"]]
    return "\n".join(lines)


def stamp(when: datetime) -> str:
    return when.strftime("%d %b %Y, %H:%M UTC")


def paragraphs(text: str) -> str:
    """Escaped, with the sender's line breaks kept.

    `<br>` rather than `white-space: pre-wrap`, which several mail clients drop
    on the floor along with the shape of what someone wrote.
    """
    if not text:
        return '<span style="color:#8a8f98">No details written.</span>'
    return escape(text).replace("\n", "<br>")


def render_html(ticket: dict) -> str:
    """A ticket, as an email.

    Tables and inline styles, because mail clients are a decade behind and
    Gmail strips a `<style>` block without asking. Everything here degrades to
    readable text if even that fails.
    """
    kind = ticket["kind"]
    colour = KIND_COLOURS[kind]
    reply_to = ticket["reply_to"]

    if reply_to:
        sender = (
            f'<a href="mailto:{escape(reply_to, quote=True)}" '
            f'style="color:#2a78d6;text-decoration:none">{escape(reply_to)}</a>'
            '<span style="color:#8a8f98"> · just hit reply</span>'
        )
    else:
        sender = '<span style="color:#8a8f98">No reply address given</span>'

    if ticket["fields"]:
        rows = "".join(
            f'<tr>'
            f'<td style="padding:4px 14px 4px 0;color:#6b7280;white-space:nowrap;'
            f'vertical-align:top">{escape(label)}</td>'
            f'<td style="padding:4px 0;color:#111827">{escape(value)}</td>'
            f'</tr>'
            for label, value in ticket["fields"]
        )
        diagnostics = f"""
      <tr><td style="padding:0 28px">
        <div style="border-top:1px solid #e6e8eb;margin:26px 0 18px"></div>
        <div style="font:600 11px/1.4 -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
                    letter-spacing:.08em;text-transform:uppercase;color:#8a8f98;
                    margin-bottom:10px">Their setup</div>
        <table cellpadding="0" cellspacing="0" border="0" role="presentation"
               style="width:100%;font:13px/1.5 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace">
          {rows}
        </table>
      </td></tr>"""
    else:
        diagnostics = """
      <tr><td style="padding:0 28px">
        <div style="border-top:1px solid #e6e8eb;margin:26px 0 18px"></div>
        <div style="font:13px/1.5 -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
                    color:#8a8f98">They chose not to attach their setup.</div>
      </td></tr>"""

    return f"""\
<!doctype html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{escape(subject_for(ticket))}</title></head>
<body style="margin:0;padding:0;background:#f4f5f7">
<!-- The line the inbox shows next to the subject, before anything is opened. -->
<div style="display:none;max-height:0;overflow:hidden;opacity:0">
  {escape(ticket['detail'][:140] or ticket['summary'])}
</div>

<table cellpadding="0" cellspacing="0" border="0" role="presentation"
       style="width:100%;background:#f4f5f7">
<tr><td align="center" style="padding:28px 12px">

  <table cellpadding="0" cellspacing="0" border="0" role="presentation"
         style="width:100%;max-width:600px;background:#ffffff;border-radius:14px;
                border:1px solid #e6e8eb;overflow:hidden">

    <tr><td style="padding:22px 28px 0">
      <table cellpadding="0" cellspacing="0" border="0" role="presentation" style="width:100%">
      <tr>
        <td style="font:600 14px/1 -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
                   color:#111827;letter-spacing:-.01em">Rephraze</td>
        <td align="right">
          <span style="display:inline-block;padding:4px 10px;border-radius:999px;
                       background:{colour};color:#ffffff;
                       font:600 11px/1 -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
                       letter-spacing:.06em;text-transform:uppercase">{KINDS[kind]}</span>
        </td>
      </tr>
      </table>
    </td></tr>

    <tr><td style="padding:16px 28px 0">
      <h1 style="margin:0;font:600 21px/1.32 -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
                 color:#111827;letter-spacing:-.02em">{escape(ticket['summary'])}</h1>
      <div style="margin-top:7px;font:13px/1.5 -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
                  color:#6b7280">{sender} · {stamp(ticket['received'])}</div>
    </td></tr>

    <tr><td style="padding:20px 28px 0">
      <div style="padding:16px 18px;background:#f8f9fa;border:1px solid #eceef0;
                  border-radius:10px;
                  font:15px/1.62 -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
                  color:#111827">{paragraphs(ticket['detail'])}</div>
    </td></tr>
{diagnostics}
    <tr><td style="padding:22px 28px 24px">
      <div style="border-top:1px solid #e6e8eb;padding-top:14px;
                  font:12px/1.55 -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
                  color:#8a8f98">
        Sent from the Support section inside Rephraze. Versions, settings and
        counts only — never what anyone typed, never their history, never their
        API key.
      </div>
    </td></tr>

  </table>
</td></tr>
</table>
</body></html>"""


# --- Sending -----------------------------------------------------------------

def configured() -> bool:
    return bool(RESEND_API_KEY and TICKET_FROM and TICKET_TO)


def send(ticket: dict) -> str:
    """Hand the report to Resend. Returns its message id.

    Raises `TicketError` on anything short of accepted, because the sender is
    waiting on the answer: a report that did not go anywhere must not be shown
    to them as sent.
    """
    if not configured():
        raise TicketError(503, "support email is not configured on this server")

    payload = {
        "from": TICKET_FROM,
        "to": [TICKET_TO],
        "subject": subject_for(ticket),
        "html": render_html(ticket),
        "text": render_text(ticket),
    }
    # So that replying in the mail client answers the person who wrote in,
    # rather than the address the server sends as.
    if ticket["reply_to"]:
        payload["reply_to"] = [ticket["reply_to"]]

    request = urllib.request.Request(
        RESEND_ENDPOINT,
        data=json.dumps(payload).encode(),
        headers={
            "Authorization": f"Bearer {RESEND_API_KEY}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=SEND_TIMEOUT_SECONDS) as response:
            body = json.loads(response.read() or b"{}")
            return str(body.get("id", ""))
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace")[:400]
        # Print rather than return: a rejection here is almost always a
        # misconfigured From: domain, and it needs to be visible in the log
        # even though the sender is told something kinder.
        print(f"resend rejected the ticket: {error.code} {detail}", flush=True)
        raise TicketError(502, "the mail service would not take it") from error
    except (urllib.error.URLError, TimeoutError, ValueError, OSError) as error:
        print(f"resend unreachable: {error}", flush=True)
        raise TicketError(502, "could not reach the mail service") from error
