# GigaChess (Swift)

Thin Swift wrapper over the native [`gigachess`](https://github.com/itshak/gigachess-rs)
Rust engine API via raw C-ABI FFI. Same functions, Swift spelling.
No compat shims, no reimplemented engine logic.

- License: MIT
- Swift 5.9+ (Swift 6 strict concurrency clean) · iOS 16+ · macOS 13+
- FFI: raw `extern "C"` over a `Copy` value-type board (no UniFFI)
- Repo: `github.com/itshak/swift-gigachess`

## Install

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/itshak/swift-gigachess.git", from: "0.1.2"),
],
targets: [
    .target(name: "MyApp", dependencies: ["GigaChess"]),
]
```

Consumers need no Rust toolchain: the `CGigaChessFFI` binary target ships as a
GitHub Release-asset XCFramework + checksum (see `Package.swift`).

## Quick start

```swift
import GigaChess

var board = Board() // startpos
print(try board.fen())

let e2e4 = Move(from: 12, to: 28) // or Move(uci: "e2e4")!
let undo = try board.play(e2e4)
print(board.turn, board.enPassant as Any)
board.unmake(e2e4, undo: undo)

// Visitor hot path (zero-alloc) vs cold-path convenience (allocates).
board.withLegalMoves { moves in
    print("legal:", moves.count) // 20 from startpos
}
let all: [Move] = board.legalMoves()

// SAN (accepts O-O and 0-0).
let nf3 = try board.move(fromSan: "Nf3")
print(try board.san(for: nf3))

// Zobrist key (UInt64 by value).
print(String(format: "%#018x", board.zobrist))

// moves2 codec + replay.
let moves = try Board.parseMovetextToMoves2("1. e4 e5 2. Nf3 1-0", from: try Board().fen())
let text = try Board.sanMovetext(from: moves, startFen: try Board().fen(), result: "1-0")
let hashes: [UInt64] = try Board.replayHashes(moves: moves, from: try Board().fen())
```

## Pinned engine version

| Component | Pin |
|---|---|
| `gigachess` engine | `0.1.2` (crates.io, repo `itshak/gigachess-rs`) |
| Single source of truth | `scripts/build-xcframework.sh` (`GIGACHESS_VERSION`) |
| Mirrored in | `Package.swift` (`gigachessVersion`), `rust/Cargo.toml` (`gigachess = "=0.1.2"`), this README |
| Startpos Zobrist | `0x463b96181691fc9c` |
| `BOARD_SIZE` / `UNDO_SIZE` | `144` / `24` bytes (`gigachess_board_size_assert` + CI) |
| Perft gate (startpos) | d1 `20` · d2 `400` · d3 `8902` · d4 `197281` |

Bump the pin in `scripts/build-xcframework.sh` first; CI fails on layout/offset
drift, missing FFI symbols, and perft deviation until wrapper + headers move together.

## Castling wire format

Native king-captures-rook, preserved verbatim Swift ↔ Rust ↔ gigaboard:

| Side | UCI word | From → To |
|---|---|---|
| White kingside | `e1h1` | 4 → 7 |
| White queenside | `e1a1` | 4 → 0 |
| Black kingside | `e8h8` | 60 → 63 |
| Black queenside | `e8a8` | 60 → 56 |

`Move.uci` renders castling this way; SAN renders letter-O (`O-O` / `O-O-O`)
and parses both `O-O` and `0-0` spellings.

## Buffer-size contracts

| Direction | Contract |
|---|---|
| FEN export | caller buffer ≤ 96B + NUL (`GIGACHESS_FEN_MAX`) |
| SAN render | caller buffer ≤ 12B + NUL (`GIGACHESS_SAN_MAX`) |
| Legal moves | caller `u16` buffer ≥ 256 words (`GIGACHESS_MAX_MOVES`) |
| Codec/replay | contiguous `UInt16`/`UInt64` buffers + explicit lengths; flat outcome structs (count, fail-ply, status). No `Vec`/`String`/`HashMap` crosses FFI; Swift owns all buffers |
| Strings | copied into caller-owned buffers; Rust never allocates a string Swift must free |

## Panic policy

Every `extern "C"` entry wraps its body in `catch_unwind` → error code
(the engine profile uses `panic = "abort"`, so an uncaught panic would kill the
host). Swift surfaces codes as `throws GigaChessError`:

| Code | Meaning |
|---|---|
| 0 | OK |
| 1 | invalid FEN |
| 2 | illegal move (board unchanged) |
| 3 | SAN parse failure |
| 4 | buffer too small |
| 5 | engine panicked |
| 6 | codec failure (failing ply reported) |

Adversarial inputs (garbage FEN, truncated buffers, out-of-range words) return
errors — never trap, abort, or corrupt memory (see `FFISafetyTests`).

## Layout

```
Sources/GigaChess/Board.swift        struct Board: Sendable (by-value Copy board)
Sources/GigaChess/Move.swift         struct Move: packed UInt16 (Move2 wire format)
Sources/GigaChess/Undo.swift         opaque make/unmake token
Sources/GigaChess/San.swift          SAN render/parse
Sources/GigaChess/Zobrist.swift      UInt64 key access
Sources/GigaChess/Moves2Codec.swift  movetext ↔ moves2, replay
Sources/GigaChess/GigaChessError.swift
Sources/CGigaChessFFI/include/gigachess_ffi.h + module.modulemap
rust/                                FFI shim crate (staticlib source for the XCFramework)
scripts/build-xcframework.sh         engine pin + cross-compile + Release upload
```

## Building

```bash
swift build
swift test
./scripts/build-xcframework.sh  # cross-compile aarch64-apple-ios / sim / macOS (macOS host)
cargo test --release --manifest-path rust/Cargo.toml  # FFI shim on any host
```

Explicitly out of scope (ADR-015): `shakmaty` compat facade, full PGN tag
parsing (movetext codec only), UCI/Stockfish embedding.
