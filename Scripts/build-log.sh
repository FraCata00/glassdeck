#!/usr/bin/env bash
# Thin wrapper that keeps SwiftPM output readable: diagnostics only, no frontend dumps.
set -uo pipefail
# `awk` rather than `head`: `head` exits at the sixtieth line, and the SIGPIPE
# that follows killed the build half way and reported it as failed.
swift "$@" 2>&1 | grep -E "^(/|error|warning|\*\*)" | grep -vE "^warning: 'glassdeck'" | awk 'NR <= 60'
exit "${PIPESTATUS[0]}"
