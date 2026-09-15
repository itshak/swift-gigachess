# AGENTS.md — GigaChess Swift Package

> Swift wrapper over the `gigachess` Rust chess engine via raw C-ABI FFI.

---

## Project Overview

**GigaChess** (Swift) is a Swift Package Manager library that provides an idiomatic Swift API
for the `gigachess` Rust chess engine. It uses raw C-ABI FFI (`extern "C"`) for maximum
performance (~1ns call overhead per FFI crossing).

- **License:** MIT
- **Language:** Swift 5.9+, Rust (staticlib)
- **Platforms:** iOS 16+, macOS 13+
- **FFI Strategy:** Raw C-ABI (no UniFFI) for maximum performance
- **Repo:** github.com/itshak/swift-gigachess

---

## Architecture

| Layer | Technology |
|---|---|
| **Public API** | Pure Swift module `GigaChess` — `Position`, `Move`, `GameState` |
| **FFI Bridge** | C header + `module.modulemap` → `CGigaChessFFI` target |
| **Binary** | `CGigaChessFFI.xcframework` — Rust `staticlib` for iOS arm64, iOS Sim, macOS |
| **Engine** | `gigachess` Rust crate — bitboard move gen, validation, FEN/PGN |

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
├── Package.swift                         # SPM manifest
├── Sources/
│   ├── GigaChess/                        # Public Swift API
│   │   ├── Position.swift
│   │   ├── Move.swift
│   │   └── GameState.swift
│   └── CGigaChessFFI/                    # C bridging module
│       └── include/
│           ├── gigachess_ffi.h
│           └── module.modulemap
├── Frameworks/
│   └── CGigaChessFFI.xcframework/        # Pre-built Rust static libs
├── Tests/
│   └── GigaChessTests/
├── scripts/
│   └── build-xcframework.sh
└── openspec/
```

---

## Key Constraints

1. **Raw C-ABI only** — no UniFFI, no serialization overhead. ~1ns per call.
2. **Memory safety** — every `OpaquePointer` must have a matching `deinit` that calls the Rust free function.
3. **Sendable** — `Position` must be `@unchecked Sendable` with documented thread-safety guarantees.
4. **MIT clean** — no GPL dependencies.
5. **Zero Swift runtime overhead** — use `struct` for value types (Move, Square), `final class` only for the opaque Rust handle.
