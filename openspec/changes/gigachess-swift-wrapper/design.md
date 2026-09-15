## Context

The `gigachess` Rust crate provides bitboard-based chess move generation. This package wraps it for Swift via raw C-ABI FFI. See proposal.md for motivation.

Existing Swift chess libraries (ChessKit) use pure Swift bitboards. We deliberately avoid rewriting engine logic in Swift — Rust is 2-5% faster due to no ARC overhead and stronger aliasing guarantees. The FFI overhead (~1ns per call via C-ABI) is negligible.

## Goals / Non-Goals

**Goals:**
- ~1ns FFI call overhead (raw C-ABI, no UniFFI)
- Memory-safe lifecycle management (Rust allocation freed in Swift `deinit`)
- Idiomatic Swift API (`Position`, `Move` as value type, `Sendable` conformance)
- Automated build pipeline (Rust → XCFramework → SPM)

**Non-Goals:**
- PGN parsing (future change)
- UCI protocol support (out of scope — use Chessblazer for that)
- Android/Kotlin bindings (separate project)
- Pure Swift fallback (no Rust → no package — it's a wrapper)

## Decisions

### Decision 1: Raw C-ABI over UniFFI

**Choice:** `#[no_mangle] extern "C"` functions with a C bridging header.

**Rationale:** UniFFI adds ~1,400ns per call due to serialization and mutex-based handle maps. For bulk analysis (perft, engine search with millions of calls), this is a 1,400× overhead. Raw C-ABI compiles to a single `bl` instruction.

**Alternative considered:** UniFFI — rejected for performance. The ergonomic cost of writing ~50 lines of Rust glue + ~15 lines of C header + ~40 lines of Swift wrapper is minimal.

### Decision 2: Opaque pointer handle (not value copy)

**Choice:** `Position` is a `final class` holding an `OpaquePointer` to a heap-allocated Rust `Box<Position>`.

**Rationale:** Chess positions contain substantial state (bitboards, history, castling rights). Copying across FFI on every access would be expensive. An opaque pointer means Swift owns the lifetime (via `deinit`) but Rust owns the memory.

**Alternative considered:** `#[repr(C)]` struct that Swift sees as a value type — rejected because the Rust `Position` struct layout is complex and may change between engine versions. Opaque pointer provides ABI stability.

### Decision 3: Move as packed UInt16 value type

**Choice:** `Move` is a Swift `struct` wrapping a `UInt16` (6 bits from, 6 bits to, 4 bits promotion).

**Rationale:** Zero-copy transfer across FFI — a `UInt16` fits in a register. No heap allocation, no ARC. Moves are `Hashable`, `Equatable`, `Sendable` for free.

### Decision 4: Caller-owned buffers for string/array data

**Choice:** FEN export and legal move listing write into caller-provided buffers (`UnsafeMutablePointer`).

**Rationale:** Avoids Rust allocating strings that Swift must free (error-prone). The caller allocates a stack buffer, Rust writes into it, Swift reads it. No shared ownership.

### Decision 5: XCFramework with committed binary

**Choice:** Pre-built `.xcframework` committed to the Git repo (or distributed as GitHub Release asset).

**Rationale:** Consumers don't need Rust toolchain installed. SPM resolves, links, done. For large binaries, GitHub Release URL + checksum in `binaryTarget` keeps the repo lean.

## Risks / Trade-offs

- **ABI stability**: If the Rust `Position` struct changes layout, the xcframework must be rebuilt. Opaque pointer insulates Swift from this, but the C header must stay in sync. → Mitigated by CI that rebuilds xcframework on Rust crate changes.
- **Rust toolchain dependency**: Building the xcframework requires `rustup` with Apple targets. → Mitigated by pre-building and committing/releasing the xcframework.
- **Thread safety**: `Position` is `@unchecked Sendable` — the Rust side is NOT thread-safe (mutable state). Concurrent mutation is undefined behavior. → Document clearly; consider adding a `LockedPosition` wrapper in a future change.
