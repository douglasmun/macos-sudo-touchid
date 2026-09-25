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

tmp=""
cleanup() {
  [ -z "$tmp" ] || rm -f "$tmp"
}
trap cleanup EXIT
trap 'exit 1' INT TERM

die() {
  echo "error: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

assert_not_symlink() {
  [ ! -L "$1" ] || die "$1 must not be a symlink"
}

assert_root_safe_path() {
  path="$1"
  assert_not_symlink "$path"
  [ -e "$path" ] || die "$path does not exist"
  owner_group="$(stat -f '%Su:%Sg' "$path")"
  [ "$owner_group" = "root:wheel" ] || die "$path must be root:wheel; found $owner_group"
  perms="$(stat -f '%OLp' "$path")"
  group_digit="$(printf '%s' "$perms" | awk '{print substr($0,length($0)-1,1)}')"
  other_digit="$(printf '%s' "$perms" | awk '{print substr($0,length($0),1)}')"
  [ $((group_digit & 2)) -eq 0 ] || die "$path must not be group-writable"
  [ $((other_digit & 2)) -eq 0 ] || die "$path must not be other-writable"
}

# Print non-comment, non-blank lines of a PAM file.
active_lines() {
  sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$1"
}

expected_lines() {
  printf '%s\n%s' "$EXPECTED_REATTACH" "$EXPECTED_TID"
}

find_source_module() {
  if [ -e "$TARGET_MODULE" ] || [ -L "$TARGET_MODULE" ]; then
    # Reuse only a module that is already root-owned; never adopt a file someone else placed.
    assert_root_safe_path "$TARGET_MODULE"
    printf '%s\n' "$TARGET_MODULE"
    return
  fi

  if command -v brew >/dev/null 2>&1; then
    brew_prefix="$(brew --prefix pam-reattach 2>/dev/null || true)"
    if [ -n "$brew_prefix" ] && [ -f "${brew_prefix}/lib/pam/pam_reattach.so" ]; then
      printf '%s\n' "${brew_prefix}/lib/pam/pam_reattach.so"
      return
    fi
  fi

  die "could not find pam_reattach.so; run: brew install pam-reattach OR ./scripts/build-pam-reattach.sh"
}

assert_safe_existing_sudo_local() {
  [ -e "$SUDO_LOCAL" ] || [ -L "$SUDO_LOCAL" ] || return 0
  assert_not_symlink "$SUDO_LOCAL"

  if grep -Fxq "$MANAGED_MARKER" "$SUDO_LOCAL"; then
    return 0
  fi

  current="$(active_lines "$SUDO_LOCAL")"
  if [ -z "$current" ] || [ "$current" = "$(expected_lines)" ]; then
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

# Check parent directories before any privileged write. On Intel Macs, Homebrew
# usually owns /usr/local/lib, which makes the root-owned module path unsafe.
assert_root_safe_path "$PAM_DIR"
assert_root_safe_path /usr/local
assert_root_safe_path /usr/local/lib
if [ -e "$TARGET_DIR" ] || [ -L "$TARGET_DIR" ]; then
  assert_root_safe_path "$TARGET_DIR"
fi

source_module="$(find_source_module)"
assert_safe_existing_sudo_local

case "$source_module" in
  "$TARGET_MODULE")
    echo "using existing root-owned PAM module"
    ;;
  */Cellar/*|/opt/homebrew/*|/usr/local/*)
    echo "copying pam_reattach from Homebrew into root-owned PAM path"
    ;;
  *)
    echo "copying pam_reattach from $source_module into root-owned PAM path"
    ;;
esac

sudo /usr/bin/install -d -o root -g wheel -m 0755 "$TARGET_DIR"
assert_root_safe_path "$TARGET_DIR"
if [ "$source_module" = "$TARGET_MODULE" ]; then
  sudo /bin/chmod -h 0444 "$TARGET_MODULE"
else
  sudo /usr/bin/install -o root -g wheel -m 0444 "$source_module" "$TARGET_MODULE"
fi
assert_root_safe_path "$TARGET_MODULE"

tmp="$(mktemp)"
cat >"$tmp" <<EOF
# sudo_local: local config file which survives system update and is included for sudo
${MANAGED_MARKER}
# pam_reattach: reattach to the GUI session so Touch ID works inside tmux/screen; skip SSH-originated sessions.
# 'optional' so a runtime failure falls through to pam_tid. The module file must exist:
# OpenPAM rejects the whole sudo policy if it cannot load a listed module.
${EXPECTED_REATTACH}
${EXPECTED_TID}
EOF

backup=""
if [ -e "$SUDO_LOCAL" ]; then
  assert_not_symlink "$SUDO_LOCAL"
  backup="${SUDO_LOCAL}.backup.$(date +%Y%m%d-%H%M%S)"
  sudo /bin/cp -p "$SUDO_LOCAL" "$backup"
  echo "backup written: $backup"
fi

sudo /usr/bin/install -o root -g wheel -m 0444 "$tmp" "$SUDO_LOCAL"

assert_root_safe_path "$SUDO_LOCAL"
[ "$(active_lines "$SUDO_LOCAL")" = "$(expected_lines)" ] || die "install verification failed"

echo "installed Touch ID sudo PAM config"
echo "validating the new sudo PAM stack; approve the Touch ID prompt or enter your password"
# -k with a command re-authenticates through the new stack without discarding the
# cached credentials, so a failed check can still be rolled back below.
if sudo -k /usr/bin/true; then
  echo "sudo validation passed"
  exit 0
fi

echo "error: sudo validation failed; restoring previous $SUDO_LOCAL" >&2
if [ -n "$backup" ]; then
  sudo -n /usr/bin/install -o root -g wheel -m 0444 "$backup" "$SUDO_LOCAL" \
    || die "rollback failed; restore $backup manually (see README: Recovery)"
else
  sudo -n /bin/rm -f "$SUDO_LOCAL" \
    || die "rollback failed; remove $SUDO_LOCAL manually (see README: Recovery)"
fi
die "rolled back; sudo_local restored to its previous state"
