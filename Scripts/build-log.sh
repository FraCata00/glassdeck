#!/usr/bin/env bash
# Thin wrapper that keeps SwiftPM output readable: diagnostics only, no frontend dumps.
set -uo pipefail
swift "$@" 2>&1 | grep -E "^(/|error|warning|\*\*)" | grep -vE "^warning: 'glassdeck'" | head -60
exit "${PIPESTATUS[0]}"
