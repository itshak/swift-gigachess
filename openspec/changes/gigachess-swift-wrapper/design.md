## Context

The `gigachess` Rust crate (`turbochess-rs`, v0.1.2, MIT) provides bitboard-based chess move generation with a native API: `Board` (a `Copy`, `#[repr(C)]` ~144-byte struct), `Move(u16)` (Move2 wire format), `Undo`, plus `san`, `fen`, `zobrist`, `replay`, and `database` (moves2 codec) modules. There is additionally a `compat::shakmaty` facade, which this package deliberately does NOT wrap (ADR-015: native-only API).

Existing Swift chess libraries (ChessKit) reimplement movegen in pure Swift. We deliberately avoid that — the wrapper is thin by design: same functions, Swift spelling, zero engine logic reimplementation.

## Goals / Non-Goals

**Goals:**
- 1:1 Swift access to the native `gigachess` API (no subset, no compat shims)
- Zero heap allocation in hot paths (stack buffers, visitor enumeration, value-type board)
- True `Sendable` value semantics (`Board` struct, Swift 6 strict concurrency clean)
- Automated build pipeline (Rust → XCFramework Release asset → SPM) with version-sync CI

**Non-Goals:**
- `shakmaty` compatibility facade (out of scope — native API only, per ADR-015)
- Full PGN tag parsing (movetext ↔ moves2 codec only; tags stay app-level)
- UCI protocol / Stockfish embedding (separate backend-slice decision)
- Android/Kotlin bindings (separate project)
- Pure Swift fallback (no Rust → no package — it's a wrapper)

## Decisions

### Decision 1: Raw C-ABI over UniFFI

**Choice:** `extern "C"` functions with a C bridging header (a local `rust/` shim crate, `gigachess-ffi`, depending on `gigachess = "=0.1.2"` with `crate-type = ["staticlib", "rlib"]`; upstreaming `ffi.rs` into `gigachess-rs` remains an option, version-recorded).

**Rationale:** UniFFI adds serialization + handle-map overhead per call. For bulk analysis (perft, search, batch replay with millions of calls) raw C-ABI compiles to a direct call. The glue cost (~790 lines Rust incl. tests + ~110-line C header + thin Swift) is minimal and stays in sync via CI.

**Alternative considered:** UniFFI — rejected for per-call overhead and because our types are already FFI-friendly (`u16` moves, `u64` hashes, `#[repr(C)]` board).

### Decision 2: Board as a Swift value struct (not an opaque pointer)

**Choice:** `Board` is a Swift `struct` holding opaque 144-byte caller-owned storage (`GigaBoard`, same size as the `Copy` Rust board). Transfer is byte copies via pointer — never a language-level struct value — so copying a board is still a bit-for-bit snapshot for search stacks, exactly how the Rust engine itself is used, with zero field-offset coupling.

**Rationale:** The engine's own architecture (ADR-013, close-gap D3) centers on a small `Copy` board with zero-allocation movegen. An opaque-pointer class would add `malloc`/`free` per position, a pointer chase per call, and an `@unchecked Sendable` lie on a mutable handle. The value struct is faster, truly `Sendable`, and gives snapshot semantics for free (undo = keep the old struct).

**Alternative considered:** Opaque pointer + `final class` + `deinit` free — rejected: slower, heap-dependent, concurrency-hostile. There is no Rust allocation to free in this design, so the entire memory-safety section of the old spec collapses to "don't hold stale pointers across calls," enforced by value semantics.

**Drift guard:** a layout test asserts `BOARD_SIZE`/`UNDO_SIZE` against the pinned `gigachess` version (field offsets are N/A — opaque bytes); CI fails the build on mismatch so struct drift is caught, not shipped.

### Decision 3: Move as packed UInt16 value type

**Choice:** `Move` is a Swift `struct` wrapping a `UInt16` (`from | (to << 6) | (promo << 12)`; promo 0 = none, 1 = N, 2 = B, 3 = R, 4 = Q) — bit-identical to Rust `Move(u16)` and the moves2 database format.

**Rationale:** Zero-copy transfer across FFI in a register. `Hashable`, `Equatable`, `Sendable` for free. Moves stored in BlindBase databases (`moves2` blobs) decode with a single `Move(word:)` init. Castling is king-captures-rook (`e1h1`/`e1a1`/`e8h8`/`e8a8`), matching both the Rust engine and `gigaboard`.

### Decision 4: Bulk enumeration, not per-call arrays

**Choice:** Two movegen APIs: (a) `withLegalMoves(_:)` visitor closure filling a caller buffer (hot path, zero alloc); (b) convenience `legalMoves() -> [Move]` (cold path, allocates). Perft parity with Rust numbers is a release gate.

**Rationale:** A per-call `[Move]` array alloc dominates the ~nanosecond FFI cost and would make the "1ns overhead" claim meaningless. The visitor mirrors Rust's `generate_visitor` / `MoveSink` design instead of fighting it.

### Decision 5: Caller-owned buffers + C error codes for strings/fallible ops

**Choice:** FEN export and SAN rendering write into caller-provided stack buffers (`UnsafeMutableBufferPointer`; FEN ≤ 96 bytes, SAN ≤ 12 bytes `ArrayString` equivalent). Fallible Rust ops (`parse_fen`, `san_to_move`) return C error codes + optional message buffer; Swift surfaces them as `throws` with a `GigaChessError` enum. No Rust-allocated string ever crosses the boundary.

**Rationale:** No shared ownership, no cross-language free, no leaks by construction. Matches the engine's no-alloc policy end to end.

### Decision 6: Zobrist and moves2 codec cross FFI as plain data

**Choice:** `zobrist()` returns `UInt64` by value (Polyglot key, incrementally maintained). Moves2 codec functions (`parse_movetext_to_moves2`, `moves2_to_san_movetext`, `replay_moves2_stream`/`batch`) operate on contiguous `UInt16` buffers with flat outcome structs — `HashMap`-returning helpers (e.g. `position_stats`) stay Rust-side; if Swift needs them later they get a flattened batch API, not a hash map across FFI.

**Rationale:** Everything crossing the boundary is `Copy`: words, hashes, counts. This is what makes the 4.4× batch-search speedup reachable from Swift.

### Decision 7: Panic policy — catch_unwind at every boundary

**Choice:** Every `extern "C"` entry point wraps its body in `catch_unwind` and converts panics to error codes. The Rust profile uses `panic = "abort"`, so an uncaught panic across FFI would kill the host app.

**Rationale:** A chess library must never crash its host. Verified by a test that feeds adversarial inputs (garbage FEN, truncated buffers) under all entry points.

### Decision 8: XCFramework as Release asset + version-sync CI

**Choice:** Prebuilt `.xcframework` distributed as a GitHub Release asset with checksum pinned in SPM `binaryTarget` (repo stays lean). CI rebuilds the XCFramework whenever the pinned `gigachess` version changes; the pin (crates.io version or crate hash) is recorded in `scripts/build-xcframework.sh` and in this spec.

**Rationale:** Consumers need no Rust toolchain. Version skew between Swift wrapper and engine is the #1 drift risk — CI, not discipline, prevents it.

**Targets:** `aarch64-apple-ios`, `aarch64-apple-ios-sim`, `aarch64-apple-darwin`. x86_64 macOS slice added on demand (decision recorded; Apple Silicon is the tier-1 desktop target).

## Risks / Trade-offs

- **Struct layout drift**: Rust `Board` internals may change between engine versions. → Mitigated by `BOARD_SIZE`/offset assert test + version-sync CI (Decision 2, 8).
- **FFI surface growth**: full native mirror means more entry points than a minimal wrapper. → Mitigated by 1:1 naming with Rust (`board_play`, `board_legal_moves`, …) so audits are mechanical.
- **Swift 6 strict concurrency**: new requirement vs old `@unchecked Sendable` plan. → Value semantics make this free; CI builds with Swift 6 mode to keep it that way.
- **Upstream dependency**: `ffi.rs` ideally lives upstream in `gigachess-rs`; as built, the shim lives in-repo under `rust/` instead, so there is no pending upstream PR to track. Upstreaming stays optional. → No action; recorded here so a future bump re-evaluates it.
