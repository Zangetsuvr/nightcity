#!/usr/bin/env bash
# Sets up the Night City server on an Ubuntu 22.04 / 24.04 VPS.
#
# Run from the project folder (the unzipped CyberpunkMP folder):
#   sudo bash deploy/setup-ubuntu.sh
#
# Safe to run again: it skips what's already done and rebuilds the server.
#
# What it does:
#   1. Updates Ubuntu and turns on automatic security updates
#   2. Installs the build tools and .NET 8
#   3. Opens the firewall: SSH, and the game port (TCP for the launcher, UDP for the game)
#   4. Builds the server (20-40 minutes the first time)
#   5. Installs it as a service that starts with the VPS and restarts after a crash
#   6. Schedules a nightly backup of the databases (kept 14 days)
#
# Layout:
#   /srv/nightcity/server    the server program (replaced on every update)
#   /srv/nightcity/config    settings        (kept)
#   /srv/nightcity/data      databases, modpack, flags log (kept)
#   /srv/nightcity/backups   nightly backups
#
# The server runs as your login user (e.g. ubuntu), so you can edit settings
# and upload the modpack with FileZilla or WinSCP without permission problems.

set -euo pipefail

PORT="${PORT:-11778}"
XMAKE_VERSION="3.1.2"
ROOT="/srv/nightcity"
SERVICE="nightcity"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_AS="${SUDO_USER:-}"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "Run this with sudo:  sudo bash deploy/setup-ubuntu.sh"
[[ -n "$RUN_AS" && "$RUN_AS" != "root" ]] || fail "Run this with sudo from your normal login (e.g. ubuntu), not as root."
[[ -f "$PROJECT_DIR/xmake.lua" ]] || fail "Run this from inside the unzipped CyberpunkMP folder."
[[ -d "$PROJECT_DIR/.git" ]] || fail "The project's .git folder is missing, so its dependencies can't be downloaded. Upload the full zip again."
grep -qi ubuntu /etc/os-release || fail "This script is for Ubuntu."

as_user() { sudo -u "$RUN_AS" -H env PATH="/usr/local/bin:$PATH" DOTNET_ROOT=/usr/lib/dotnet DOTNET_CLI_TELEMETRY_OPTOUT=1 "$@"; }

# Stop the old Docker-based server if an earlier version of this script made one.
if command -v docker >/dev/null 2>&1 && docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx nightcity; then
  docker rm -f nightcity >/dev/null || true
fi

step "1/6 Updating Ubuntu (a few minutes)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get upgrade -yq
apt-get install -yq unattended-upgrades
dpkg-reconfigure -f noninteractive unattended-upgrades

step "2/6 Installing build tools, .NET 8 and Node.js"
apt-get install -yq g++ make cmake ninja-build pkg-config perl python3 autoconf automake libtool \
  git curl unzip zip sqlite3 ufw ca-certificates libicu-dev

# .NET 8 from Microsoft's own installer: works on every Ubuntu version,
# including ones whose package lists don't carry .NET 8.
if ! /usr/lib/dotnet/dotnet --list-sdks 2>/dev/null | grep -q '^8\.'; then
  echo "    Installing .NET 8 SDK"
  curl -fsSL -o /tmp/dotnet-install.sh https://dot.net/v1/dotnet-install.sh
  bash /tmp/dotnet-install.sh --channel 8.0 --install-dir /usr/lib/dotnet >/dev/null
  rm -f /tmp/dotnet-install.sh
fi
ln -sf /usr/lib/dotnet/dotnet /usr/local/bin/dotnet
export DOTNET_ROOT=/usr/lib/dotnet DOTNET_CLI_TELEMETRY_OPTOUT=1
dotnet --version | sed 's/^/    .NET SDK /'

# Node.js 22 and pnpm 9: some plugins build a small web admin page.
# (pnpm 9 rather than 10, which stops builds over packages' setup scripts.)
if ! command -v node >/dev/null 2>&1 || [[ "$(node -v | sed 's/^v//; s/\..*//')" -lt 20 ]]; then
  echo "    Installing Node.js 22"
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null
  apt-get install -yq nodejs
fi
npm install -g pnpm@9 >/dev/null
echo "    Node.js $(node -v), pnpm $(pnpm -v)"

# xmake refuses to run as root, so version checks run as your login user.
if ! command -v xmake >/dev/null 2>&1 || ! as_user xmake --version 2>/dev/null | grep -q "v$XMAKE_VERSION"; then
  echo "    Building xmake $XMAKE_VERSION (a few minutes)"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/xmake.tar.gz" \
    "https://github.com/xmake-io/xmake/releases/download/v$XMAKE_VERSION/xmake-v$XMAKE_VERSION.tar.gz"
  tar xzf "$tmp/xmake.tar.gz" -C "$tmp" --strip-components=1
  (cd "$tmp" && ./configure >/dev/null && make -j"$(nproc)" >/dev/null && make install >/dev/null)
  rm -rf "$tmp"
fi
as_user xmake --version | head -1 | sed 's/^/    /'

step "3/6 Opening the firewall (SSH and port $PORT)"
ufw allow OpenSSH >/dev/null
ufw allow "$PORT/tcp" >/dev/null   # launcher: login, modpack, server info
ufw allow "$PORT/udp" >/dev/null   # the game connection
ufw --force enable >/dev/null
ufw status | sed 's/^/    /'

step "4/6 Building the server (20-40 minutes the first time)"
chown -R "$RUN_AS:$RUN_AS" "$PROJECT_DIR"
cd "$PROJECT_DIR"
as_user git submodule update --init --recursive
as_user xmake f -y -m release
as_user xmake -y -v

BUILD_OUT="$PROJECT_DIR/build/linux/x86_64/release"
[[ -x "$BUILD_OUT/Server.Loader" ]] || fail "The build finished but Server.Loader is missing from $BUILD_OUT."

step "5/6 Installing the server as a service"
mkdir -p "$ROOT/server" "$ROOT/config" "$ROOT/data/modpack" "$ROOT/backups"
systemctl stop "$SERVICE" 2>/dev/null || true
rm -rf "$ROOT/server"
cp -a "$BUILD_OUT" "$ROOT/server"
# The server reads config/ and writes data/ next to itself; point those at the kept folders.
rm -rf "$ROOT/server/config" "$ROOT/server/data"
ln -s "$ROOT/config" "$ROOT/server/config"
ln -s "$ROOT/data" "$ROOT/server/data"
chown -R "$RUN_AS:$RUN_AS" "$ROOT"

# Login for the server's admin web pages (browser asks for it). Made once with a
# random password; change it by editing this file and restarting the service.
ADMIN_ENV="$ROOT/config/admin.env"
if [[ ! -f "$ADMIN_ENV" ]]; then
  cat > "$ADMIN_ENV" <<EOF
CYBERPUNKMP_ADMIN_USERNAME=admin
CYBERPUNKMP_ADMIN_PASSWORD=$(head -c 18 /dev/urandom | base64 | tr -d '/+=')
EOF
fi
chown "$RUN_AS:$RUN_AS" "$ADMIN_ENV"
chmod 600 "$ADMIN_ENV"

cat > "/etc/systemd/system/$SERVICE.service" <<EOF
[Unit]
Description=Night City roleplay server
After=network-online.target
Wants=network-online.target

[Service]
User=$RUN_AS
WorkingDirectory=$ROOT/server
ExecStart=$ROOT/server/Server.Loader
Environment=DOTNET_ROOT=/usr/lib/dotnet
EnvironmentFile=$ROOT/config/admin.env
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now "$SERVICE"

# Give it a moment to create its settings files on first start.
for _ in $(seq 1 30); do
  [[ -f "$ROOT/config/account.json" ]] && break
  sleep 2
done

step "6/6 Scheduling nightly backups"
install -m 755 "$PROJECT_DIR/deploy/backup.sh" /usr/local/bin/nightcity-backup
cat > /etc/cron.d/nightcity-backup <<EOF
# Night City databases, every night at 4:15 (server time)
15 4 * * * root /usr/local/bin/nightcity-backup >> /var/log/nightcity-backup.log 2>&1
EOF

IP="$(curl -s -4 --max-time 5 https://api.ipify.org || hostname -I | awk '{print $1}')"

step "Done"
if systemctl is-active --quiet "$SERVICE"; then
  echo "    The server is running."
else
  echo "    The server isn't running. See what went wrong with:  sudo journalctl -u $SERVICE -n 80"
fi
cat <<EOF

    Settings:  $ROOT/config   (server.json, account.json, character.json)
    Admin web login:  see $ROOT/config/admin.env
    Data:      $ROOT/data     (databases, flags log, modpack/)
    Backups:   $ROOT/backups

    Check it from your browser:
      http://$IP:$PORT/api/v1/plugins/account/info

    Next: fill in the settings (see the setup guide), then restart:
      sudo systemctl restart $SERVICE
EOF
