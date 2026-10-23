#!/usr/bin/env bash
# Backs up the Night City databases safely while the server runs.
# Installed by setup-ubuntu.sh as /usr/local/bin/nightcity-backup and run nightly.
# Run it by hand any time:  sudo nightcity-backup
set -euo pipefail

DATA="/srv/nightcity/data"
DEST="/srv/nightcity/backups/$(date +%Y-%m-%d_%H%M)"
KEEP_DAYS="${KEEP_DAYS:-14}"

mkdir -p "$DEST"
for db in characters accounts; do
  if [[ -f "$DATA/$db.db" ]]; then
    # ".backup" copies a consistent snapshot even while the server is writing.
    sqlite3 "$DATA/$db.db" ".backup '$DEST/$db.db'"
  fi
done
[[ -f "$DATA/flags.jsonl" ]] && cp "$DATA/flags.jsonl" "$DEST/"
cp -r /srv/nightcity/config "$DEST/config"

find /srv/nightcity/backups -mindepth 1 -maxdepth 1 -type d -mtime "+$KEEP_DAYS" -exec rm -rf {} +
echo "$(date '+%F %T') backup saved to $DEST"
