#!/usr/bin/env bash
# use-local-xcframework.sh — bootstrap helper for CI / local dev before the
# first Release asset is published.
#
# While Package.swift carries the zero placeholder checksum (Release asset
# unpublished, so URL resolution 404s), rewrite the CGigaChessFFI binary
# target to the locally-built Frameworks/CGigaChessFFI.xcframework path.
# Once the real checksum is committed, this script is a no-op and CI
# exercises the exact consumer URL path.
#
# SPDX-License-Identifier: MIT
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${REPO_ROOT}/Package.swift"
XCFRAMEWORK="${REPO_ROOT}/Frameworks/CGigaChessFFI.xcframework"
PLACEHOLDER="0000000000000000000000000000000000000000000000000000000000000000"

if ! grep -q "let ffiChecksum = \"${PLACEHOLDER}\"" "${MANIFEST}"; then
  echo "==> Release checksum present — keeping URL binary target (consumer path)."
  exit 0
fi

if [ ! -d "${XCFRAMEWORK}" ]; then
  echo "error: ${XCFRAMEWORK} not found — run scripts/build-xcframework.sh first" >&2
  exit 1
fi

python3 - "${MANIFEST}" <<'PYEOF'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()

old = '''        .binaryTarget(
            name: "CGigaChessFFI",
            url: "https://github.com/itshak/swift-gigachess/releases/download/\\(ffiReleaseTag)/CGigaChessFFI.xcframework.zip",
            checksum: ffiChecksum
        ),'''
new = '''        .binaryTarget(
            name: "CGigaChessFFI",
            path: "Frameworks/CGigaChessFFI.xcframework"
        ),'''

if old not in text:
    print("error: binaryTarget stanza not found — Package.swift drifted", file=sys.stderr)
    sys.exit(1)
path.write_text(text.replace(old, new, 1))
print("==> Package.swift now uses local Frameworks/CGigaChessFFI.xcframework (bootstrap).")
PYEOF
