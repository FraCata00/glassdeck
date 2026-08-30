#!/usr/bin/env bash
#
# Points the Homebrew cask at a published release.
#
# Usage: Scripts/update-cask.sh 1.2.0 [path-to-tap-checkout]
#
# Reads the checksum GitHub already publishes beside the archive, rewrites the
# cask, and commits it. Run it after the release workflow has finished.
#
set -euo pipefail

VERSION="${1:?usage: update-cask.sh <version> [tap-path]}"
TAP="${2:-$HOME/Documents/Projects/homebrew-tap}"
CASK="$TAP/Casks/glassdeck.rb"

[[ -f "$CASK" ]] || { echo "cask not found at $CASK" >&2; exit 1; }

CHECKSUM_URL="https://github.com/FraCata00/glassdeck/releases/download/v$VERSION/GlassDeck.zip.sha256"
SHA="$(curl -fsSL "$CHECKSUM_URL" | awk '{print $1}')"
[[ -n "$SHA" ]] || { echo "no checksum published for v$VERSION" >&2; exit 1; }

/usr/bin/sed -i '' \
    -e "s/^  version \".*\"$/  version \"$VERSION\"/" \
    -e "s/^  sha256 \".*\"$/  sha256 \"$SHA\"/" \
    "$CASK"

git -C "$TAP" add Casks/glassdeck.rb
git -C "$TAP" commit -m "chore: point the glassdeck cask at $VERSION"

echo "▸ Cask updated to $VERSION ($SHA)"
echo "▸ Push the tap to publish it: git -C \"$TAP\" push"
