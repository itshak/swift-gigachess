## Why

The `gigachess` Rust chess engine is the fastest JS/TS chess engine (via WASM), but there is no way to use it from native Swift apps on iOS/macOS. Swift developers currently must choose between slower pure-Swift chess libraries or manually wrapping C/Rust code. A first-class Swift Package wrapping `gigachess` via raw C-ABI FFI (~1ns call overhead) would bring Rust-level move generation performance to the Apple ecosystem with zero ergonomic compromise.

## What Changes

- New Swift Package `GigaChess` published via SPM (Git URL-based distribution)
- Rust `gigachess` crate compiled as `staticlib` for Apple targets (iOS arm64, iOS Simulator arm64, macOS arm64)
- C bridging header and `module.modulemap` exposing the Rust FFI surface to Swift
- XCFramework packaging (`CGigaChessFFI.xcframework`) as SPM `binaryTarget`
- Idiomatic Swift wrapper layer: `Position` (final class, opaque pointer handle), `Move` (struct, packed UInt16), game state queries
- Build automation script for cross-compiling Rust and creating the XCFramework
- Test suite covering all public API, FFI boundary safety, and thread safety

## Capabilities

### New Capabilities
- `position-management`: Create, query, and mutate chess positions (from FEN, starting position, copy). Wraps Rust `ChessPosition` lifecycle via opaque pointer with automatic cleanup in `deinit`.
- `move-generation`: Generate and apply legal moves. Moves are packed as `UInt16` value types for zero-copy FFI transfer. Includes validation, check/checkmate/stalemate detection.
- `notation`: FEN string import/export across the FFI boundary. String data is copied into caller-owned buffers (no shared pointers).
- `build-pipeline`: Cross-compilation of Rust `staticlib` for Apple targets, XCFramework creation, and SPM package structure with `binaryTarget`.

### Modified Capabilities
_(none — this is a new project)_

## Impact

- **New SPM package**: `GigaChess` importable via `https://github.com/itshak/swift-gigachess.git`
- **Rust dependency**: requires Rust toolchain with Apple targets for building the xcframework
- **Binary size**: ~1-2MB per architecture for the static library
- **Downstream**: `swift-gigaboard` will depend on this package for chess logic
