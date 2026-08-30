#!/usr/bin/env bash
#
# Builds GlassDeck.app from the SwiftPM executable.
#
# Usage:
#   Scripts/bundle.sh [--debug] [--universal] [--version X.Y.Z]
#
# The app is written to .build/bundle/GlassDeck.app and signed ad hoc, which is
# enough to run locally and to hand out in a release archive.
#
set -euo pipefail

CONFIGURATION="release"
ARCH_FLAGS=()
VERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug) CONFIGURATION="debug"; shift ;;
        --universal) ARCH_FLAGS=(--arch arm64 --arch x86_64); shift ;;
        --version) VERSION="$2"; shift 2 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -z "$VERSION" ]]; then
    VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
    VERSION="${VERSION:-0.0.0}"
fi
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

echo "▸ Building GlassDeck $VERSION ($CONFIGURATION)"
# `${a[@]}` on an empty array trips `set -u` under the bash 3.2 that ships with
# macOS, so the expansion is guarded.
ARCHS=(${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"})

swift build -c "$CONFIGURATION" ${ARCHS[@]+"${ARCHS[@]}"}

BINARY="$(swift build -c "$CONFIGURATION" ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/GlassDeck"
APP=".build/bundle/GlassDeck.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/GlassDeck"
cp Resources/GlassDeck.icns "$APP/Contents/Resources/GlassDeck.icns"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" \
    Resources/Info.plist > "$APP/Contents/Info.plist"

# Ad-hoc signature: no developer account required, and it keeps the Touch Bar
# and login-item APIs happy on the machine that built it.
codesign --force --sign - --options runtime --timestamp=none "$APP" >/dev/null 2>&1 || \
    codesign --force --sign - "$APP" >/dev/null

echo "▸ Bundled $APP"
