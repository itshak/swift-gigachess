# AGENTS.md — GigaChess Swift Package

> Thin Swift wrapper over the native `gigachess` Rust engine API via raw C-ABI FFI. Same functions, Swift spelling. No compat shims, no reimplemented engine logic.

---

## Project Overview

**GigaChess** (Swift) is a Swift Package Manager library that provides idiomatic Swift access to
the **native** `gigachess` Rust engine API (`Board`, `Move`, SAN, FEN, Zobrist, moves2 codec, replay).
It uses raw C-ABI FFI (`extern "C"`) over a `Copy` value-type board — no heap allocation in hot paths.

- **License:** MIT
- **Language:** Swift 5.9+ (Swift 6 strict concurrency clean), Rust (staticlib)
- **Platforms:** iOS 16+, macOS 13+
- **FFI Strategy:** Raw C-ABI (no UniFFI) over `#[repr(C)]` value types; native API only, NO `shakmaty` compat facade (ADR-015)
- **Engine pin:** recorded in `scripts/build-xcframework.sh` (single source of truth); CI rebuilds + guards layout drift
- **Repo:** github.com/itshak/swift-gigachess

---

## Architecture

| Layer | Technology |
|---|---|
| **Public API** | Pure Swift module `GigaChess` — `Board` (struct, by value), `Move` (struct, packed `UInt16`), `Undo`, SAN/FEN/Zobrist/moves2 |
| **FFI Bridge** | C header + `module.modulemap` → `CGigaChessFFI` target (1:1 with native Rust API names) |
| **Binary** | `CGigaChessFFI.xcframework` via GitHub Release asset + checksum — Rust `staticlib` for iOS arm64, iOS Sim, macOS |
| **Engine** | `gigachess` Rust crate (pinned) — bitboard movegen, SAN, FEN, Zobrist, moves2 codec, replay |

---

## Build Commands

```bash
# Build the Swift package
swift build

# Run tests
swift test

# Build the Rust library for all Apple targets (run from gigachess Rust crate)
./scripts/build-xcframework.sh
```

---

## Repository Map

```
swift-gigachess/
├── Package.swift                         # SPM manifest (Swift 6 mode)
├── Sources/
│   ├── GigaChess/                        # Public Swift API (value types only)
│   │   ├── Board.swift                   # struct Board: Sendable (by-value Copy board)
│   │   ├── Move.swift                    # struct Move: packed UInt16 (Move2 wire format)
│   │   ├── Undo.swift                    # opaque make/unmake token
│   │   ├── San.swift                     # SAN render/parse
│   │   ├── Zobrist.swift                 # UInt64 key access (or on Board)
│   │   ├── Moves2Codec.swift             # movetext ↔ moves2, replay
│   │   └── GigaChessError.swift          # throws-based error enum
│   └── CGigaChessFFI/                    # C bridging module (single name — no CChessFFIHeaders)
│       └── include/
│           ├── gigachess_ffi.h
│           └── module.modulemap
├── Tests/
│   └── GigaChessTests/
├── scripts/
│   └── build-xcframework.sh              # engine pin + cross-compile + Release upload
└── openspec/
```

---

## Key Constraints

1. **Native API only** — mirror `gigachess` Rust `pub` API 1:1. NEVER wrap the `shakmaty` compat facade (ADR-015). NEVER reimplement engine logic in Swift.
2. **Value semantics** — `Board` is a `struct` (by-value `Copy` board, ~144B). No heap allocation, no `deinit`/free, no opaque-pointer handles.
3. **True Sendable** — engine types MUST be `Sendable` for real and build clean under Swift 6 strict concurrency. No `@unchecked Sendable` on engine types.
4. **Zero-alloc hot paths** — visitor/buffer-fill enumeration (`withLegalMoves`), caller-owned string buffers (FEN ≤ 96B, SAN ≤ 12B), `UInt64`-by-value Zobrist. Convenience allocating APIs MUST be documented as cold-path.
5. **Move2 wire fidelity** — `Move` bit-layout identical to Rust `Move(u16)`; castling stays king-captures-rook (`e1h1`…) verbatim across Swift ↔ Rust ↔ gigaboard.
6. **Panic-safe FFI** — every `extern "C"` entry uses `catch_unwind` → error code; Swift surfaces `throws`. A chess library MUST NEVER crash its host.
7. **MIT clean** — no GPL dependencies.
