#!/bin/sh
set -eu

PAM_DIR="/etc/pam.d"
SUDO_PAM="${PAM_DIR}/sudo"
SUDO_LOCAL="${PAM_DIR}/sudo_local"
TARGET_DIR="/usr/local/lib/pam"
TARGET_MODULE="${TARGET_DIR}/pam_reattach.so"
MANAGED_MARKER="# managed by macos-sudo-touchid"
EXPECTED_REATTACH="auth       optional       ${TARGET_MODULE} ignore_ssh"
EXPECTED_TID="auth       sufficient     pam_tid.so"

die() {
  echo "error: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

mode_owner_group() {
  stat -f '%Su:%Sg %OLp' "$1"
}

assert_not_symlink() {
  [ ! -L "$1" ] || die "$1 must not be a symlink"
}

assert_root_safe_path() {
  path="$1"
  assert_not_symlink "$path"
  owner_mode="$(mode_owner_group "$path")"
  case "$owner_mode" in
    root:wheel\ 7??|root:wheel\ 6??|root:wheel\ 5??|root:wheel\ 4??) ;;
    *) die "$path must be root:wheel; found $owner_mode" ;;
  esac
  perms="$(stat -f '%OLp' "$path")"
  group_digit="$(printf '%s' "$perms" | awk '{print substr($0,length($0)-1,1)}')"
  other_digit="$(printf '%s' "$perms" | awk '{print substr($0,length($0),1)}')"
  [ $((group_digit & 2)) -eq 0 ] || die "$path must not be group-writable"
  [ $((other_digit & 2)) -eq 0 ] || die "$path must not be other-writable"
}

find_source_module() {
  if [ -r "$TARGET_MODULE" ]; then
    printf '%s\n' "$TARGET_MODULE"
    return
  fi

  if command -v brew >/dev/null 2>&1; then
    brew_prefix="$(brew --prefix pam-reattach 2>/dev/null || true)"
    if [ -n "$brew_prefix" ] && [ -r "${brew_prefix}/lib/pam/pam_reattach.so" ]; then
      printf '%s\n' "${brew_prefix}/lib/pam/pam_reattach.so"
      return
    fi
  fi

  die "could not find pam_reattach.so; run: brew install pam-reattach OR ./scripts/build-pam-reattach.sh"
}

assert_safe_existing_sudo_local() {
  [ -e "$SUDO_LOCAL" ] || return 0
  assert_not_symlink "$SUDO_LOCAL"

  if grep -Fq "$MANAGED_MARKER" "$SUDO_LOCAL"; then
    return 0
  fi

  active_lines="$(sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$SUDO_LOCAL")"
  expected_lines="$(printf '%s\n%s' "$EXPECTED_REATTACH" "$EXPECTED_TID")"

  if [ -z "$active_lines" ] || [ "$active_lines" = "$expected_lines" ]; then
    return 0
  fi

  die "$SUDO_LOCAL contains unmanaged active PAM rules; refusing to overwrite them"
}

[ "$(uname -s)" = "Darwin" ] || die "this installer only supports macOS"
need_cmd sudo
need_cmd stat
need_cmd install
need_cmd mktemp

[ -r "$SUDO_PAM" ] || die "$SUDO_PAM is not readable"
grep -Eq '^[[:space:]]*auth[[:space:]]+include[[:space:]]+sudo_local([[:space:]]|$)' "$SUDO_PAM" \
  || die "$SUDO_PAM does not include sudo_local; refusing to edit Apple-managed sudo PAM config"

source_module="$(find_source_module)"
assert_safe_existing_sudo_local

case "$source_module" in
  /opt/homebrew/*|*/Cellar/*)
    echo "copying pam_reattach from Homebrew into root-owned PAM path"
    ;;
  "$TARGET_MODULE")
    echo "using existing root-owned PAM module"
    ;;
  *)
    echo "copying pam_reattach from $source_module into root-owned PAM path"
    ;;
esac

sudo /usr/bin/install -d -o root -g wheel -m 0755 "$TARGET_DIR"
if [ "$source_module" = "$TARGET_MODULE" ]; then
  sudo /usr/sbin/chown root:wheel "$TARGET_MODULE"
  sudo /bin/chmod 0444 "$TARGET_MODULE"
else
  sudo /usr/bin/install -o root -g wheel -m 0444 "$source_module" "$TARGET_MODULE"
fi

assert_root_safe_path /usr/local
assert_root_safe_path /usr/local/lib
assert_root_safe_path "$TARGET_DIR"
assert_root_safe_path "$TARGET_MODULE"

tmp="$(mktemp)"
cat >"$tmp" <<EOF
# sudo_local: local config file which survives system update and is included for sudo
${MANAGED_MARKER}
# pam_reattach: reattach to the GUI session so Touch ID works inside tmux/screen; ignore SSH-originated sessions.
# 'optional' so a missing/broken module falls through to pam_tid rather than blocking sudo.
auth       optional       ${TARGET_MODULE} ignore_ssh
auth       sufficient     pam_tid.so
EOF

if [ -e "$SUDO_LOCAL" ]; then
  assert_not_symlink "$SUDO_LOCAL"
  backup="${SUDO_LOCAL}.backup.$(date +%Y%m%d-%H%M%S)"
  sudo /bin/cp -p "$SUDO_LOCAL" "$backup"
  echo "backup written: $backup"
fi

sudo /usr/bin/install -o root -g wheel -m 0444 "$tmp" "$SUDO_LOCAL"
rm -f "$tmp"

assert_root_safe_path "$SUDO_LOCAL"
grep -Fq "${TARGET_MODULE} ignore_ssh" "$SUDO_LOCAL" || die "install verification failed"
grep -Fq "auth       sufficient     pam_tid.so" "$SUDO_LOCAL" || die "install verification failed"

echo "installed Touch ID sudo PAM config"
echo "validating sudo now; approve the expected macOS prompt if shown"
sudo -v
sudo -n true
echo "sudo validation passed"
