#!/usr/bin/env bash
# Builds the Flutter web release for Vercel.
# Vercel hosts this static bundle only. PocketBase stays on PocketHost.
# Local loopback databases are not enabled in this build.
#
# Always uses the pinned Flutter SDK. A flutter binary already on PATH is ignored,
# including any SDK preinstalled in a cloud image.
set -euo pipefail
cd "$(dirname "$0")/.."

FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.9}"
FLUTTER_ROOT="${FLUTTER_ROOT:-"$HOME/flutter-$FLUTTER_VERSION"}"
# SHA-256 of the official stable Linux archive in releases_linux.json.
FLUTTER_SHA256="${FLUTTER_SHA256:-25ed8c3c29d51a7353f2a944310b478af8214920639524b19c50a19e6c044c5a}"

case "$FLUTTER_ROOT" in
  /|""|"$HOME")
    echo "Refusing FLUTTER_ROOT=$FLUTTER_ROOT" >&2
    exit 1
    ;;
esac

ensure_tool() {
  local cmd="$1"
  local pkg="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi
  if ! command -v dnf >/dev/null 2>&1; then
    echo "Missing $cmd and dnf is not available to install $pkg" >&2
    exit 1
  fi
  dnf install -y "$pkg"
}

# Vercel’s build image is Amazon Linux 2023. git, curl, xz, and unzip are not
# guaranteed by the Flutter SDK tarball itself.
ensure_tool curl curl
ensure_tool git git
ensure_tool xz xz
ensure_tool unzip unzip
ensure_tool sha256sum coreutils

if [[ ! -x "$FLUTTER_ROOT/bin/flutter" ]]; then
  parent="$(dirname "$FLUTTER_ROOT")"
  mkdir -p "$parent"
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  curl -fL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" -o "$tmp"
  echo "${FLUTTER_SHA256}  ${tmp}" | sha256sum -c -
  stage="${parent}/flutter"
  if [[ "$stage" != "$FLUTTER_ROOT" ]]; then
    rm -rf "$stage"
  fi
  rm -rf "$FLUTTER_ROOT"
  # Do not keep archive ownership. Vercel builds as root, and Flutter’s git
  # checkout refuses a repository owned by another user.
  tar --no-same-owner -C "$parent" -xf "$tmp"
  rm -f "$tmp"
  trap - EXIT
  if [[ "$stage" != "$FLUTTER_ROOT" ]]; then
    mv "$stage" "$FLUTTER_ROOT"
  fi
fi

if ! git config --global --get-all safe.directory 2>/dev/null | grep -Fxq "$FLUTTER_ROOT"; then
  git config --global --add safe.directory "$FLUTTER_ROOT"
fi

export PATH="$FLUTTER_ROOT/bin:${PATH:-}"
hash -r
export FLUTTER_SUPPRESS_ANALYTICS=1

echo "Using $(command -v flutter)"
flutter config --enable-web --no-analytics
got="$(flutter --version 2>/dev/null | awk '/^Flutter / { print $2; exit }')"
if [[ "$got" != "$FLUTTER_VERSION" ]]; then
  echo "Pinned Flutter ${FLUTTER_VERSION} required, found ${got:-none}" >&2
  exit 1
fi

flutter pub get
flutter build web --release --base-href /
