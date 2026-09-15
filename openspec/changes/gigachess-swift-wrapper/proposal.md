## Why

The `gigachess` Rust engine (bitboard movegen, 16-bit Move2 codec, incremental Polyglot Zobrist) is the shared chess foundation of BlindBase (ADR-012), but there is no way to use it from native Swift apps on iOS/macOS. Swift developers must choose between slower pure-Swift libraries or hand-rolled wrappers.

This package is a **thin, lightweight wrapper around the actual native `gigachess` API** — it exposes the same functions Swift-side that Rust consumers get (`Board`, `Move`, SAN, FEN, Zobrist, moves2 codec, replay), with zero reimplementation of engine logic. Following ADR-015 (native-only API), the `shakmaty` compatibility facade is **explicitly out of scope**: one engine API to learn, test, benchmark, and keep in sync.

Future direction (see `swift-gigaboard` proposal): a native Swift GUI for BlindBase will keep the Rust backend (carved into a Tauri-free staticlib with C-ABI) and use Swift only for UI. This package proves that pattern on the engine slice first.

## What Changes

- New Swift Package `GigaChess` published via SPM (Git URL-based distribution)
- Rust `gigachess` crate compiled as `staticlib` for Apple targets (iOS arm64, iOS Simulator arm64, macOS arm64)
- C bridging header and `module.modulemap` exposing the native engine surface (1:1 with Rust `pub` API, no compat shims)
- XCFramework packaging (`CGigaChessFFI.xcframework`) distributed as a GitHub Release asset + checksum in SPM `binaryTarget`
- Idiomatic Swift wrapper layer with **value semantics**: `Board` (struct wrapping the 144-byte `Copy` Rust board by value), `Move` (struct, packed `UInt16`), `Undo`, SAN/FEN/Zobrist/moves2 APIs
- Zero-allocation policy in hot paths: stack buffers, visitor/batch enumeration, no per-call heap allocation
- Build automation script for cross-compiling Rust and creating the XCFramework, plus CI that rebuilds on `gigachess` version bumps
- Test suite covering full public API parity, perft parity with Rust, FFI boundary safety, and Swift 6 strict concurrency

## Capabilities

### New Capabilities
- `position-management`: Create, copy, and query chess positions (startpos, empty, from FEN). `Board` is a Swift `struct` wrapping the Rust `Copy` board by value — snapshots are bit-for-bit copies, `Sendable` for real, no `deinit`/free involved.
- `move-generation`: Generate and apply legal moves. Moves are packed `UInt16` (Move2 wire format: `from | (to << 6) | (promo << 12)`). Includes `play`/`isLegal`, make/unmake with `Undo`, bulk visitor enumeration, perft, check/checkmate/stalemate detection. Castling uses native king-captures-rook encoding (`e1h1`, `e1a1`, …).
- `notation`: FEN import/export plus SAN render/parse (`move_to_san` / `san_to_move` / `play_san` equivalents). Strings cross FFI into caller-owned buffers only.
- `zobrist-hashing`: Direct `UInt64` Polyglot Zobrist key access for position-keyed lookups (repertoire trees, transpositions, GigaBase indexing).
- `moves2-codec`: Batch movetext ↔ moves2 conversion (`parse_movetext_to_moves2`, `moves2_to_san_movetext`) and hash-stream replay (`replay_moves2_stream`/`batch`) over contiguous buffers — the 4.4× search-speedup story, available to Swift.
- `build-pipeline`: Cross-compilation of Rust `staticlib` for Apple targets, XCFramework creation as a Release asset, SPM `binaryTarget` with checksum, layout-drift CI guard (`BOARD_SIZE` assert).

### Modified Capabilities
_(none — this is a new project)_

## Impact

- **New SPM package**: `GigaChess` importable via `https://github.com/itshak/swift-gigachess.git`
- **Rust dependency**: only maintainers need the Rust toolchain; consumers get a prebuilt XCFramework from a GitHub Release asset
- **Binary size**: ~1-2MB per architecture for the static library (to be measured and recorded on first build)
- **Downstream**: `swift-gigaboard` depends on this package for chess logic; future native BlindBase GUI uses this FFI pattern for the wider Rust backend slice
- **Explicitly NOT included**: `shakmaty` compat facade, full PGN tag parsing (movetext codec only), UCI engine protocol / Stockfish embedding (separate backend-slice decision: in-process on iOS, external process + user-loadable engines on macOS)
