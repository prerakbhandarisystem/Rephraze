#!/bin/sh
# Nightly snapshot of the usage database.
#
# Uses SQLite's own backup command rather than `cp`. Copying the file while the
# server is mid-write can catch it halfway and produce a database that looks
# fine until the day you need it; `.backup` waits for a consistent moment and
# does not stop the server.

set -eu

DB="${REPHRAZE_DB:-/var/lib/rephraze/usage.db}"
OUT="${1:-/var/backups/rephraze}"
KEEP_DAYS="${KEEP_DAYS:-30}"

mkdir -p "$OUT"
STAMP="$(date +%F)"
SNAPSHOT="$OUT/usage-$STAMP.db"

sqlite3 "$DB" ".backup '$SNAPSHOT'"
gzip -f "$SNAPSHOT"

find "$OUT" -name 'usage-*.db.gz' -mtime "+$KEEP_DAYS" -delete

echo "backed up to $SNAPSHOT.gz"

# A backup that has never left the machine is not a backup -- the disk it is
# protecting against is the disk it is sitting on. Add your off-box copy here,
# e.g.  rclone copy "$SNAPSHOT.gz" remote:rephraze-backups/
