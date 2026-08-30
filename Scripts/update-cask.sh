#!/usr/bin/env bash
#
# Points the Homebrew cask at a published release.
#
# Usage: Scripts/update-cask.sh 1.2.0 [path-to-tap-checkout]
#
# With no path, the tap is located through Homebrew itself.
#
# Reads the checksum GitHub already publishes beside the archive, rewrites the
# cask, and commits it. Run it after the release workflow has finished.
#
set -euo pipefail

VERSION="${1:?usage: update-cask.sh <version> [tap-path]}"

# The tap normally lives where Homebrew keeps it, which is under /opt/homebrew on
# Apple silicon and /usr/local on Intel, so ask brew instead of guessing. An
# explicit second argument still wins, for a checkout kept somewhere else.
TAP="${2:-$(brew --repository fracata00/tap 2>/dev/null || true)}"
CASK="$TAP/Casks/glassdeck.rb"

if [[ -z "$TAP" || ! -f "$CASK" ]]; then
    echo "cask not found${TAP:+ at $CASK}" >&2
    echo "pass the tap checkout explicitly: update-cask.sh $VERSION <tap-path>" >&2
    exit 1
fi

CHECKSUM_URL="https://github.com/FraCata00/glassdeck/releases/download/v$VERSION/GlassDeck.zip.sha256"
SHA="$(curl -fsSL "$CHECKSUM_URL" | awk '{print $1}')"
[[ -n "$SHA" ]] || { echo "no checksum published for v$VERSION" >&2; exit 1; }

/usr/bin/sed -i '' \
    -e "s/^  version \".*\"$/  version \"$VERSION\"/" \
    -e "s/^  sha256 \".*\"$/  sha256 \"$SHA\"/" \
    "$CASK"

# Re-running for a version already pointed at is a no-op, not a failed commit.
if git -C "$TAP" diff --quiet -- Casks/glassdeck.rb; then
    echo "▸ Cask already at $VERSION ($SHA)"
    exit 0
fi

git -C "$TAP" add Casks/glassdeck.rb
git -C "$TAP" commit -m "chore: point the glassdeck cask at $VERSION"

echo "▸ Cask updated to $VERSION ($SHA)"
echo "▸ Push the tap to publish it: git -C \"$TAP\" push"
