#!/bin/sh
set -eu

VERSION="1.3"
TARBALL_URL="https://github.com/fabianishere/pam_reattach/archive/refs/tags/v${VERSION}.tar.gz"
TARBALL_SHA256="b1b735fa7832350a23457f7d36feb6ec939e5e1de987b456b6c28f5738216570"
TARGET_DIR="/usr/local/lib/pam"
TARGET_MODULE="${TARGET_DIR}/pam_reattach.so"

die() {
  echo "error: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

[ "$(uname -s)" = "Darwin" ] || die "this script only supports macOS"
need_cmd curl
need_cmd cmake
need_cmd shasum
need_cmd tar
need_cmd sudo

workdir="$(mktemp -d "${TMPDIR:-/tmp}/pam-reattach-build.XXXXXX")"
trap 'rm -rf "$workdir"' EXIT INT TERM

archive="${workdir}/pam_reattach-v${VERSION}.tar.gz"
src="${workdir}/pam_reattach-${VERSION}"
stage="${workdir}/stage"

echo "downloading pam_reattach v${VERSION}"
curl -fL "$TARBALL_URL" -o "$archive"

actual_sha="$(shasum -a 256 "$archive" | awk '{print $1}')"
[ "$actual_sha" = "$TARBALL_SHA256" ] || die "checksum mismatch for $archive"

tar -xzf "$archive" -C "$workdir"

cmake -S "$src" -B "${src}/build" \
  -DENABLE_CLI=ON \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$stage"
cmake --build "${src}/build"
cmake --install "${src}/build"

module="$(find "$stage" -type f -name pam_reattach.so -print | head -1)"
[ -n "$module" ] || die "build completed but pam_reattach.so was not found"

echo "installing pam_reattach.so to root-owned PAM path"
sudo /usr/bin/install -d -o root -g wheel -m 0755 "$TARGET_DIR"
sudo /usr/bin/install -o root -g wheel -m 0444 "$module" "$TARGET_MODULE"

owner_mode="$(stat -f '%Su:%Sg %OLp' "$TARGET_MODULE")"
case "$owner_mode" in
  root:wheel\ 4??|root:wheel\ 5??) ;;
  *) die "$TARGET_MODULE has unexpected owner/mode: $owner_mode" ;;
esac

echo "installed $TARGET_MODULE"
echo "next: ./scripts/install.sh"
