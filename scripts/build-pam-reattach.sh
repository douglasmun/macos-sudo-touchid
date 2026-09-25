#!/bin/sh
set -eu

VERSION="1.3"
TARBALL_URL="https://github.com/fabianishere/pam_reattach/archive/refs/tags/v${VERSION}.tar.gz"
TARBALL_SHA256="b1b735fa7832350a23457f7d36feb6ec939e5e1de987b456b6c28f5738216570"
TARGET_DIR="/usr/local/lib/pam"
TARGET_MODULE="${TARGET_DIR}/pam_reattach.so"

workdir=""
cleanup() {
  [ -z "$workdir" ] || rm -rf "$workdir"
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

assert_root_safe_path() {
  path="$1"
  [ ! -L "$path" ] || die "$path must not be a symlink"
  [ -e "$path" ] || die "$path does not exist"
  owner_group="$(stat -f '%Su:%Sg' "$path")"
  [ "$owner_group" = "root:wheel" ] || die "$path must be root:wheel; found $owner_group"
  perms="$(stat -f '%OLp' "$path")"
  group_digit="$(printf '%s' "$perms" | awk '{print substr($0,length($0)-1,1)}')"
  other_digit="$(printf '%s' "$perms" | awk '{print substr($0,length($0),1)}')"
  [ $((group_digit & 2)) -eq 0 ] || die "$path must not be group-writable"
  [ $((other_digit & 2)) -eq 0 ] || die "$path must not be other-writable"
}

[ "$(uname -s)" = "Darwin" ] || die "this script only supports macOS"
need_cmd curl
need_cmd cmake
need_cmd shasum
need_cmd tar
need_cmd sudo

# Fail before downloading if the root-owned install path cannot be made safe.
assert_root_safe_path /usr/local
assert_root_safe_path /usr/local/lib
if [ -e "$TARGET_DIR" ] || [ -L "$TARGET_DIR" ]; then
  assert_root_safe_path "$TARGET_DIR"
fi
[ ! -L "$TARGET_MODULE" ] || die "$TARGET_MODULE must not be a symlink"

workdir="$(mktemp -d "${TMPDIR:-/tmp}/pam-reattach-build.XXXXXX")"
archive="${workdir}/pam_reattach-v${VERSION}.tar.gz"
src="${workdir}/pam_reattach-${VERSION}"
stage="${workdir}/stage"

echo "downloading pam_reattach v${VERSION}"
curl -fsSL --proto '=https' --tlsv1.2 "$TARBALL_URL" -o "$archive"

actual_sha="$(shasum -a 256 "$archive" | awk '{print $1}')"
[ "$actual_sha" = "$TARBALL_SHA256" ] || die "checksum mismatch for $archive"

tar -xzf "$archive" -C "$workdir"
[ -d "$src" ] || die "unexpected tarball layout; $src not found"

# Upstream v1.3 loops sizeof(ssh_env_vars) times (the array's size in bytes)
# over a 3-element array, reading past its end on every non-SSH sudo call.
# Patch it to iterate over the element count.
pam_c="${src}/src/pam.c"
buggy='for (i = 0; i < sizeof(ssh_env_vars); i++) {'
fixed='for (i = 0; i < sizeof(ssh_env_vars) / sizeof(ssh_env_vars[0]); i++) {'
[ "$(grep -Fc "$buggy" "$pam_c")" -eq 1 ] || die "upstream source changed; review the ssh_env_vars patch"
sed "s|sizeof(ssh_env_vars); i++|sizeof(ssh_env_vars) / sizeof(ssh_env_vars[0]); i++|" "$pam_c" >"${pam_c}.patched"
mv "${pam_c}.patched" "$pam_c"
[ "$(grep -Fc "$fixed" "$pam_c")" -eq 1 ] || die "failed to apply ssh_env_vars patch"

cmake -S "$src" -B "${src}/build" \
  -DENABLE_PAM=ON \
  -DENABLE_CLI=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$stage"
cmake --build "${src}/build"
cmake --install "${src}/build"

module="$(find "$stage" -type f -name pam_reattach.so -print | head -1)"
[ -n "$module" ] || die "build completed but pam_reattach.so was not found"

echo "installing pam_reattach.so to root-owned PAM path"
sudo /usr/bin/install -d -o root -g wheel -m 0755 "$TARGET_DIR"
assert_root_safe_path "$TARGET_DIR"
sudo /usr/bin/install -o root -g wheel -m 0444 "$module" "$TARGET_MODULE"
assert_root_safe_path "$TARGET_MODULE"

echo "installed $TARGET_MODULE"
echo "next: ./scripts/install.sh"
