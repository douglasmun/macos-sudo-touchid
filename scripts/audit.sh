#!/bin/sh
set -u

SUDO_PAM="/etc/pam.d/sudo"
SUDO_LOCAL="/etc/pam.d/sudo_local"
TARGET_MODULE="/usr/local/lib/pam/pam_reattach.so"
EXPECTED_REATTACH="auth       optional       ${TARGET_MODULE} ignore_ssh"
EXPECTED_TID="auth       sufficient     pam_tid.so"
failures=0

pass() {
  echo "PASS: $*"
}

fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

check_not_symlink() {
  path="$1"
  if [ -L "$path" ]; then
    fail "$path must not be a symlink"
  else
    pass "$path is not a symlink"
  fi
}

check_root_safe() {
  path="$1"
  if [ ! -e "$path" ]; then
    fail "$path does not exist"
    return
  fi

  check_not_symlink "$path"
  owner_group="$(stat -f '%Su:%Sg' "$path" 2>/dev/null || echo unknown)"
  perms="$(stat -f '%OLp' "$path" 2>/dev/null || echo 000)"

  if [ "$owner_group" = "root:wheel" ]; then
    pass "$path owner is root:wheel"
  else
    fail "$path owner is $owner_group, expected root:wheel"
  fi

  group_digit="$(printf '%s' "$perms" | awk '{print substr($0,length($0)-1,1)}')"
  other_digit="$(printf '%s' "$perms" | awk '{print substr($0,length($0),1)}')"

  if [ $((group_digit & 2)) -eq 0 ] && [ $((other_digit & 2)) -eq 0 ]; then
    pass "$path is not group/other writable"
  else
    fail "$path has unsafe permissions: $perms"
  fi
}

if grep -Eq '^[[:space:]]*auth[[:space:]]+include[[:space:]]+sudo_local([[:space:]]|$)' "$SUDO_PAM" 2>/dev/null; then
  pass "$SUDO_PAM includes sudo_local"
else
  fail "$SUDO_PAM does not include sudo_local"
fi

check_root_safe /etc/pam.d
check_root_safe "$SUDO_PAM"
check_root_safe /usr/local
check_root_safe /usr/local/lib
check_root_safe /usr/local/lib/pam
check_root_safe "$TARGET_MODULE"
check_root_safe "$SUDO_LOCAL"

active="$(sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$SUDO_LOCAL" 2>/dev/null || true)"
expected="$(printf '%s\n%s' "$EXPECTED_REATTACH" "$EXPECTED_TID")"
if [ "$active" = "$expected" ]; then
  pass "$SUDO_LOCAL active rules are exactly pam_reattach (optional, ignore_ssh) then pam_tid (sufficient)"
else
  fail "$SUDO_LOCAL active rules differ from the expected two lines:"
  printf '%s\n' "$active" | sed 's/^/  /' >&2
fi

if grep -Eq '/opt/homebrew|/Cellar/' "$SUDO_LOCAL" 2>/dev/null; then
  fail "$SUDO_LOCAL references Homebrew-owned paths"
else
  pass "$SUDO_LOCAL does not reference Homebrew-owned paths"
fi

if command -v otool >/dev/null 2>&1 && [ -e "$TARGET_MODULE" ]; then
  deps="$(otool -L "$TARGET_MODULE" 2>/dev/null | awk 'NR > 1 {print $1}')"
  unsafe="$(printf '%s\n' "$deps" | grep -Ev '^/usr/lib/|^/System/Library/' || true)"
  if [ -z "$unsafe" ]; then
    pass "$TARGET_MODULE links only system libraries"
  else
    fail "$TARGET_MODULE has non-system library dependencies: $unsafe"
  fi
else
  echo "SKIP: otool not available or $TARGET_MODULE missing; library dependency check not run"
fi

if [ "$failures" -eq 0 ]; then
  echo "audit passed"
  exit 0
fi

echo "audit failed with $failures issue(s)" >&2
exit 1
