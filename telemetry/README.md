# Rephraze usage backend

An ingest endpoint and a dashboard, in one standard-library Python file. No pip,
no virtualenv, no build step.

```sh
export REPHRAZE_DASHBOARD_TOKEN="$(python3 -c 'import secrets;print(secrets.token_urlsafe(32))')"
python3 telemetry/server.py
```

Then open `http://127.0.0.1:8787/?token=$REPHRAZE_DASHBOARD_TOKEN`.

| Route | What it does |
|---|---|
| `POST /v1/events` | where the app posts batches. No auth — see below |
| `GET /` | the dashboard. Token required |
| `GET /healthz` | liveness |

| Environment variable | Default | |
|---|---|---|
| `REPHRAZE_DASHBOARD_TOKEN` | *(none)* | **required**; without it the dashboard refuses every request |
| `REPHRAZE_DB` | `usage.db` | SQLite file |
| `REPHRAZE_HOST` | `127.0.0.1` | bind address — set to `0.0.0.0` behind a proxy |
| `REPHRAZE_PORT` | `8787` | |

## Connecting the app to it

Nothing is collected until two separate things are true, and they are separate on
purpose:

1. **The build has an address.** Set `AppInfo.usageEndpoint` in
   `Sources/RephrazeKit/Support/AppInfo.swift` to your `/v1/events` URL. While it
   is `nil`, the app records nothing at all — the Usage settings section says so
   and the toggle is disabled.
2. **The user has opted in.** Settings › Usage, off by default.

## Why the ingest endpoint has no auth

The clients are anonymous, so there is no credential to give them that would not
immediately be public in a distributed binary — a shared secret in an app bundle
is a secret in name only. What protects the endpoint instead is that it accepts
so little: a per-IP rate limit, a 256 KB body cap, 100 events per batch, and a
schema that drops anything it was not told about in advance.

Put it behind TLS. Everything else here assumes a proxy in front.

## What the server can and cannot store

Event properties are flattened into typed columns rather than kept as a JSON
blob. That keeps every dashboard query plain SQL, and it means **the server
physically cannot store a field it was not told about**. A future client that
sent something new — by accident or by a bug — would have it land nowhere.

The complete accepted schema is `EVENT_SCHEMA` and `ENUMS` near the top of
`server.py`:

| Event | Properties |
|---|---|
| `launched` | *(none)* |
| `rephrased` | `outcome` (accepted/dismissed) · `personalised` (bool) · `milliseconds` (0–120000) |
| `translated` | `language` (one of the ten) |
| `failed` | `reason` (rephrase/write) |

Values outside those enums are stored as `NULL`, not as themselves, so a
grouping on the dashboard can never be polluted by junk — or by text.

## Deploying — making it the central database

Nothing here installs SQLite. There is nothing to install: it is already inside
Python, and the database is a file that appears on its own the first time the
server runs. What you are deploying is one Python file onto one computer with a
public address. The database is central because that is the only copy, and only
your server ever opens it.

Everything below assumes a fresh Ubuntu box. `deploy/` has the files.

**1. Rent a small Linux box and point a name at it.** Any provider; the cheapest
tier is plenty. Add a DNS `A` record for `usage.yourapp.com` pointing at its IP.

**2. Make a user and the two directories.** The server runs as nobody important
and can write to exactly one place.

```sh
sudo useradd --system --home /opt/rephraze --shell /usr/sbin/nologin rephraze
sudo mkdir -p /opt/rephraze /var/lib/rephraze /var/backups/rephraze /etc/rephraze
sudo chown -R rephraze:rephraze /opt/rephraze /var/lib/rephraze /var/backups/rephraze
sudo chmod 700 /var/lib/rephraze
```

**3. Copy the code up.**

```sh
scp -r telemetry/server.py telemetry/deploy you@your-box:/tmp/
sudo mv /tmp/server.py /tmp/deploy /opt/rephraze/
sudo chown -R rephraze:rephraze /opt/rephraze
```

**4. Make the dashboard password.** It lives in its own file, not in the unit
file, because unit files are readable by everyone on the machine.

```sh
printf 'REPHRAZE_DASHBOARD_TOKEN=%s\n' \
  "$(python3 -c 'import secrets;print(secrets.token_urlsafe(32))')" \
  | sudo tee /etc/rephraze/usage.env >/dev/null
sudo chmod 600 /etc/rephraze/usage.env
```

**5. Start it, and keep it started.**

```sh
sudo cp /opt/rephraze/deploy/rephraze-usage.service /etc/systemd/system/
sudo systemctl enable --now rephraze-usage
systemctl status rephraze-usage
```

**6. Put HTTPS in front.** Caddy gets a certificate by itself and renews it
forever. Edit the domain in the Caddyfile first.

```sh
sudo apt install caddy
sudo cp /opt/rephraze/deploy/Caddyfile /etc/caddy/Caddyfile
sudo systemctl reload caddy
curl https://usage.yourapp.com/healthz     # {"ok": true}
```

**7. Turn on the nightly backup.**

```sh
sudo cp /opt/rephraze/deploy/rephraze-backup.{service,timer} /etc/systemd/system/
sudo systemctl enable --now rephraze-backup.timer
sudo systemctl start rephraze-backup       # prove it works now, not in a month
```

Then add an off-box copy at the bottom of `deploy/backup.sh`. A backup sitting
on the disk it is protecting against is not a backup.

**8. Point the app at it.** In `Sources/RephrazeKit/Support/AppInfo.swift`:

```swift
public static let usageEndpoint = URL(string: "https://usage.yourapp.com/v1/events")
```

Ship that build, and reports start arriving from whoever opts in.

## Backups

Use SQLite's own `.backup`, never `cp`. Copying the file while the server is
mid-write can catch it halfway and give you a database that looks fine until the
day you need it. `deploy/backup.sh` does it correctly and does not stop the
server; it keeps 30 days and prunes the rest.

To restore: stop the server, gunzip the snapshot over `usage.db`, delete any
leftover `usage.db-wal` and `usage.db-shm`, start the server.

## One machine only

SQLite is one file with one writer. Do not run two copies of this server against
the same database, and do not put the database on a network disk (NFS, EFS, an
S3 mount) -- the file locking those provide is incomplete, and the failure mode
is a quietly corrupted database rather than an error. A plain disk on one box is
the supported arrangement, and at a few events per user per day it will be
bored.

## Retention of the data itself

There is no expiry job. Add one if you want a retention policy — a
`DELETE FROM events WHERE day < date('now','-180 days')` on a timer is the whole
implementation.
