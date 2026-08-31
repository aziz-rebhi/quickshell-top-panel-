#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "run with: sudo $0" >&2
  exit 1
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$DIR/bin/performance-mode"
TARGET_USER="${SUDO_USER:-${USER:-root}}"

echo "[1/5] state dir"
mkdir -p /var/lib/performance-mode

echo "[2/5] symlink /usr/local/bin/performance-mode"
ln -sf "$BIN" /usr/local/bin/performance-mode

echo "[3/5] sudoers NOPASSWD entry (scoped to this script)"
cat > /etc/sudoers.d/performance-mode <<SUDOERS
$TARGET_USER ALL=(root) NOPASSWD: $BIN set *, $BIN toggle, $BIN watch
SUDOERS
chmod 0440 /etc/sudoers.d/performance-mode
visudo -c

echo "[4/5] systemd service (state restore + thermal watchdog)"
cp "$DIR/systemd/performance-mode.service" /etc/systemd/system/performance-mode.service
systemctl daemon-reload
systemctl enable --now performance-mode.service

echo "[5/5] verify"
sudo -n "$BIN" current
echo "modes:"
"$BIN" list | tr '\n' ' '
echo
echo
echo "done. run \`performance-mode set balanced\` once, then \`performance-mode doctor\`."
echo "security note: the sudoers entry grants passwordless root ONLY for"
echo "  '$BIN set <mode>' and '$BIN toggle' on this user-owned script."