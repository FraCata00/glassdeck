#!/usr/bin/env bash
#
# Checks that every string table has an Italian twin with the same keys and
# the same placeholders.
#
# Usage: Scripts/check-strings.sh
#
# CI already asserts that four tables reach the bundle, but a table can arrive
# with a key missing, and the only sign is an English sentence in the middle
# of an Italian window. A placeholder that differs between the two — `%@`
# against `%lld` — is worse: `String(format:)` reads the wrong type off the
# argument list.
#
set -euo pipefail

cd "$(dirname "$0")/.."

/usr/bin/python3 -I - <<'EOF'
import json
import re
import subprocess
import sys

TABLES = [
    ("app", "Resources/Localizations"),
    ("kit", "Sources/GlassDeckKit/Resources"),
]
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|f|\.\d+f|%)")


def load(path):
    output = subprocess.check_output(["plutil", "-convert", "json", "-o", "-", path])
    return json.loads(output)


def placeholders(text):
    # Positional arguments may legitimately be reordered by a translation, so
    # the comparison is of the multiset, not the sequence.
    return sorted(PLACEHOLDER.findall(text))


failures = []
for name, base in TABLES:
    english = load(f"{base}/en.lproj/Localizable.strings")
    italian = load(f"{base}/it.lproj/Localizable.strings")
    for key in sorted(english.keys() - italian.keys()):
        failures.append(f"{name}: missing in it: {key!r}")
    for key in sorted(italian.keys() - english.keys()):
        failures.append(f"{name}: missing in en: {key!r}")
    for key in sorted(english.keys() & italian.keys()):
        if placeholders(english[key]) != placeholders(italian[key]):
            failures.append(f"{name}: placeholders differ: {key!r} → {italian[key]!r}")
    print(f"▸ {name}: {len(english)} strings in en, {len(italian)} in it")

for failure in failures:
    print(f"error: {failure}", file=sys.stderr)
sys.exit(1 if failures else 0)
EOF
