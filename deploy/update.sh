#!/usr/bin/env bash
# Updates the server to a new version of the project.
#
# 1. Upload the new zip and unzip it (replacing the old project folder).
# 2. From inside the new folder:  sudo bash deploy/update.sh
#
# Backs up first, builds while the old server keeps running, then swaps them.
# Settings, databases and the modpack in /srv/nightcity are kept as they are.
set -euo pipefail

ROOT="/srv/nightcity"
SERVICE="nightcity"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_AS="${SUDO_USER:-}"

[[ $EUID -eq 0 ]] || { echo "Run this with sudo:  sudo bash deploy/update.sh" >&2; exit 1; }
[[ -n "$RUN_AS" && "$RUN_AS" != "root" ]] || { echo "Run this with sudo from your normal login (e.g. ubuntu)." >&2; exit 1; }
as_user() { sudo -u "$RUN_AS" -H env PATH="/usr/local/bin:$PATH" DOTNET_ROOT=/usr/lib/dotnet DOTNET_CLI_TELEMETRY_OPTOUT=1 "$@"; }

echo "==> Backing up first"
/usr/local/bin/nightcity-backup

echo "==> Building the new version (the old one keeps running meanwhile)"
chown -R "$RUN_AS:$RUN_AS" "$PROJECT_DIR"
cd "$PROJECT_DIR"
as_user git submodule update --init --recursive
as_user xmake f -y -m release
as_user xmake -y

BUILD_OUT="$PROJECT_DIR/build/linux/x86_64/release"
[[ -x "$BUILD_OUT/Server.Loader" ]] || { echo "Build output is missing Server.Loader; nothing was changed." >&2; exit 1; }

echo "==> Swapping in the new version"
systemctl stop "$SERVICE"
rm -rf "$ROOT/server.old"
mv "$ROOT/server" "$ROOT/server.old"
cp -a "$BUILD_OUT" "$ROOT/server"
rm -rf "$ROOT/server/config" "$ROOT/server/data"
ln -s "$ROOT/config" "$ROOT/server/config"
ln -s "$ROOT/data" "$ROOT/server/data"
chown -R "$RUN_AS:$RUN_AS" "$ROOT/server"
systemctl start "$SERVICE"

sleep 5
if systemctl is-active --quiet "$SERVICE"; then
  echo "==> Updated and running. The previous version is kept in $ROOT/server.old."
else
  echo "==> The new version didn't start; going back to the previous one." >&2
  systemctl stop "$SERVICE" || true
  rm -rf "$ROOT/server"
  mv "$ROOT/server.old" "$ROOT/server"
  systemctl start "$SERVICE"
  echo "    See what went wrong:  sudo journalctl -u $SERVICE -n 80" >&2
  exit 1
fi
