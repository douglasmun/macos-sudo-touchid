#!/bin/sh
set -eu

SUDO_LOCAL="/etc/pam.d/sudo_local"
MANAGED_MARKER="# managed by macos-sudo-touchid"

die() {
  echo "error: $*" >&2
  exit 1
}

[ "$(uname -s)" = "Darwin" ] || die "this script only supports macOS"

if [ ! -e "$SUDO_LOCAL" ]; then
  echo "$SUDO_LOCAL does not exist; nothing to remove"
  exit 0
fi

[ ! -L "$SUDO_LOCAL" ] || die "$SUDO_LOCAL is a symlink; refusing"

if ! grep -Fq "$MANAGED_MARKER" "$SUDO_LOCAL"; then
  die "$SUDO_LOCAL is not marked as managed by this project; refusing to remove it"
fi

backup="${SUDO_LOCAL}.removed.$(date +%Y%m%d-%H%M%S)"
sudo /bin/cp -p "$SUDO_LOCAL" "$backup"

tmp="$(mktemp)"
cat >"$tmp" <<EOF
# sudo_local: local config file which survives system update and is included for sudo
# Touch ID for sudo was removed by macos-sudo-touchid.
# Uncomment the following line manually to enable Apple's built-in Touch ID behavior without pam_reattach:
#auth       sufficient     pam_tid.so
EOF

sudo /usr/bin/install -o root -g wheel -m 0444 "$tmp" "$SUDO_LOCAL"
rm -f "$tmp"

echo "disabled Touch ID sudo config in $SUDO_LOCAL"
echo "backup written: $backup"
echo "note: reinstall from an interactive Terminal session; sudo will require a password after uninstall"
echo "validating sudo now; approve the expected macOS prompt if shown"
sudo -v
sudo -n true
echo "sudo validation passed"
