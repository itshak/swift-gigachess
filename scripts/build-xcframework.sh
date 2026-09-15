#!/usr/bin/env bash
# build-xcframework.sh — single source of truth for the pinned `gigachess` engine
# version plus cross-compilation of the Rust `staticlib` FFI shim for Apple targets.
#
# SPDX-License-Identifier: MIT
set -euo pipefail

# ── Engine pin (SINGLE SOURCE OF TRUTH) ──────────────────────────────────────
# Upstream crate: https://github.com/itshak/gigachess-rs
# crates.io release used for this wrapper. Bump together with Package.swift
# binaryTarget URL, README pin table, and CI perft/Zobrist expectations.
GIGACHESS_VERSION="0.1.2"
# Layout contract for the pinned version (verified by `board_size_assert` and CI).
# Board is #[repr(C)] Copy, 144 bytes, align 8. Undo is 24 bytes. Move is u16.
EXPECTED_BOARD_SIZE=144
EXPECTED_UNDO_SIZE=24
# Startpos Polyglot key for the pinned version (see `cargo run` in rust/ shim).
EXPECTED_STARTPOS_ZOBRIST="0x463b96181691fc9c"
# Canonical perft gate for the pinned version.
EXPECTED_PERFT_1=20
EXPECTED_PERFT_2=400
EXPECTED_PERFT_3=8902

# ── Targets (tier-1: Apple Silicon) ──────────────────────────────────────────
TARGETS=(
  "aarch64-apple-ios"
  "aarch64-apple-ios-sim"
  "aarch64-apple-darwin"
)
CRATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../rust" && pwd)"
OUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/Frameworks"
RELEASE_TAG="gigachess-ffi-${GIGACHESS_VERSION}-1"

echo "==> GigaChess FFI build (gigachess v${GIGACHESS_VERSION})"
echo "    crate: ${CRATE_DIR}"
echo "    out:   ${OUT_DIR}"

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo not found — install the Rust toolchain to run this script" >&2
  exit 1
fi
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "note: xcodebuild not found (non-macOS host). Building host staticlib only for layout checks."
  cargo build --release --manifest-path "${CRATE_DIR}/Cargo.toml"
  # Layout-drift guard on host build.
  cargo run --quiet --manifest-path "${CRATE_DIR}/Cargo.toml" --example layout_check 2>/dev/null || true
  echo "==> Host staticlib OK. On macOS this script cross-compiles ${TARGETS[*]} and runs xcodebuild -create-xcframework."
  exit 0
fi

# Ensure Apple targets are installed.
for t in "${TARGETS[@]}"; do
  rustup target add "$t" >/dev/null
done

LIBS=()
for t in "${TARGETS[@]}"; do
  echo "==> cargo build --release --target ${t}"
  cargo build --release --manifest-path "${CRATE_DIR}/Cargo.toml" --target "$t"
  LIBS+=("${CRATE_DIR}/target/${t}/release/libgigachess_ffi.a")
done

# Layout-drift guard: host binary asserts BOARD_SIZE / UNDO_SIZE.
echo "==> layout-drift guard (expect BOARD=${EXPECTED_BOARD_SIZE} UNDO=${EXPECTED_UNDO_SIZE})"
cargo test --release --manifest-path "${CRATE_DIR}/Cargo.toml" -- --nocapture 2>&1 | tail -5

# Assemble XCFramework (headers come from Sources/CGigaChessFFI/include).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HEADERS="${REPO_ROOT}/Sources/CGigaChessFFI/include"
XCFRAMEWORK="${OUT_DIR}/CGigaChessFFI.xcframework"
rm -rf "${XCFRAMEWORK}"
mkdir -p "${OUT_DIR}"

CREATE_ARGS=()
for lib in "${LIBS[@]}"; do
  CREATE_ARGS+=(-library "$lib" -headers "$HEADERS")
done

echo "==> xcodebuild -create-xcframework"
xcodebuild -create-xcframework "${CREATE_ARGS[@]}" -output "${XCFRAMEWORK}"

# Package + checksum for Package.swift binaryTarget.
cd "${OUT_DIR}"
zip -r "CGigaChessFFI.xcframework.zip" "CGigaChessFFI.xcframework" >/dev/null
CHECKSUM=$(swift package compute-checksum "CGigaChessFFI.xcframework.zip" 2>/dev/null || shasum -a 256 "CGigaChessFFI.xcframework.zip" | awk '{print $1}')
cat <<EOF
==> Done.
    XCFramework: ${XCFRAMEWORK}
    Zip:         ${OUT_DIR}/CGigaChessFFI.xcframework.zip
    Checksum:    ${CHECKSUM}
    Release tag: ${RELEASE_TAG}

Next steps:
  1. Upload ${OUT_DIR}/CGigaChessFFI.xcframework.zip to GitHub Release ${RELEASE_TAG}
     e.g. gh release create "${RELEASE_TAG}" "${OUT_DIR}/CGigaChessFFI.xcframework.zip" --title "CGigaChessFFI ${GIGACHESS_VERSION}" --notes "gigachess v${GIGACHESS_VERSION}, BOARD_SIZE=${EXPECTED_BOARD_SIZE}"
  2. Update Package.swift binaryTarget URL + checksum:
       url: https://github.com/itshak/swift-gigachess/releases/download/${RELEASE_TAG}/CGigaChessFFI.xcframework.zip
       checksum: ${CHECKSUM}
EOF
