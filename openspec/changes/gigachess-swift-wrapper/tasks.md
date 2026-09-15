## Tasks

### 1. Pin engine version and scaffold SPM package structure
- Record the pinned `gigachess` version/hash in `scripts/build-xcframework.sh` (single source of truth)
- Create `Package.swift` with two targets: `CGigaChessFFI` (binaryTarget → Release-asset XCFramework) and `GigaChess` (Swift wrapper, Swift 6 language mode, strict concurrency)
- Create directory structure: `Sources/GigaChess/`, `Tests/GigaChessTests/`, `scripts/`, `Frameworks/` (gitignored; CI downloads the asset)
- Open/propose upstream `ffi.rs` PR in `gigachess-rs` (fallback: pinned patch with recorded hash until merged)
- Verify: `swift package describe` succeeds

### 2. Write Rust FFI layer (native API only, no compat)
- Add `src/ffi.rs` to the `gigachess` Rust crate with `extern "C"` functions, 1:1 named with native API:
  - Lifecycle/queries: `gigachess_board_startpos`, `gigachess_board_empty`, `gigachess_board_from_fen` (error code + message buffer), `gigachess_board_to_fen` (caller buffer ≤ 96B), `gigachess_board_turn`, `gigachess_board_piece_at`, `gigachess_board_king_square`, `gigachess_board_castling_rights`, `gigachess_board_en_passant`, `gigachess_board_clocks`, `gigachess_board_size_assert`
  - Movegen: `gigachess_board_legal_moves` (caller `u16` buffer ≥ 256, returns count), `gigachess_board_play` (returns `Undo` bytes + status), `gigachess_board_is_legal`, `gigachess_board_make_unchecked` / `gigachess_board_unmake`, `gigachess_board_in_check`, `gigachess_board_perft`
  - SAN: `gigachess_board_move_to_san` (caller buffer ≤ 12B), `gigachess_board_san_to_move`, `gigachess_board_size` constants
  - Zobrist: `gigachess_board_zobrist` (returns `u64` by value)
  - Codec/replay: `gigachess_parse_movetext_to_moves2`, `gigachess_moves2_to_san_movetext`, `gigachess_replay_moves2_stream` (flat outcomes, caller buffers)
- Every entry point wraps its body in `catch_unwind` → error code (panic-safety)
- Board crosses by value (`#[repr(C)]` struct, `Copy`); `Undo` crosses as fixed-size bytes
- Set `crate-type = ["staticlib"]` in `Cargo.toml`
- Verify: `cargo build --release` produces `libgigachess.a`; adversarial-input test passes with no aborts

### 3. Create C bridging header and module map
- Write `Sources/CGigaChessFFI/include/gigachess_ffi.h` with all function declarations (single target name `CGigaChessFFI` — replaces the earlier `CChessFFIHeaders` draft name)
- Write matching `module.modulemap`
- Verify: header compiles cleanly with `clang -fsyntax-only`

### 4. Write build-xcframework script + CI guards
- Create `scripts/build-xcframework.sh`: cross-compile `aarch64-apple-ios`, `aarch64-apple-ios-sim`, `aarch64-apple-darwin`; `xcodebuild -create-xcframework`; upload to GitHub Release; print checksum for `Package.swift`
- CI: rebuild on pin change; fail on `BOARD_SIZE`/offset mismatch, missing FFI symbols, perft spot-check drift
- Verify: script produces valid XCFramework; CI job green on first run

### 5. Implement Swift wrapper — Board (value type) + errors
- Create `Sources/GigaChess/Board.swift`: `struct Board: Sendable` (no class, no `deinit`); `init()` / `startpos()` / `empty()` / `init(fen:) throws`; queries (`turn`, `piece(at:)`, `kingSquare`, `castlingRights`, `enPassant`, clocks, `fen`, `zobrist`, `isCheck`/`isCheckmate`/`isStalemate`)
- Create `Sources/GigaChess/GigaChessError.swift`: `invalidFen`, `illegalMove`, `sanParseFailed`, `bufferTooSmall`, `enginePanicked`, `codecFailed(ply:)`
- Verify: `swift build` succeeds with Swift 6 mode, zero concurrency warnings

### 6. Implement Swift wrapper — Move, Undo, play/make-unmake, visitor
- Create `Sources/GigaChess/Move.swift`: `struct Move: Hashable, Equatable, Sendable` (`UInt16` word; `from`/`to`/`promotion`; algebraic + UCI rendering; king-captures-rook castling preserved verbatim)
- Create `Sources/GigaChess/Undo.swift`: opaque fixed-size token (internal bytes, no API surface beyond make/unmake pairing)
- On `Board`: `mutating play(_:) throws -> Undo`, `isLegal(_:)`, `makeMoveUnchecked`/`unmake`, `withLegalMoves(_:)` visitor + `legalMoves()` convenience, `perft(depth:)`
- Verify: `swift build` succeeds

### 7. Implement Swift wrapper — SAN, Zobrist, moves2 codec
- SAN: `san(for:)`, `init(parsing:board:)` / `move(fromSan:board:)` (accept `O-O` and `0-0`), `playSan(_:)` sequence
- Zobrist: `var zobrist: UInt64`
- Codec: `parseMovetextToMoves2(_:from:)`, `sanMovetext(from:moves:)`, `replayHashes(moves:from:)` with flat outcomes and caller-owned buffers
- Verify: `swift build` succeeds

### 8. Write tests — parity, not just behavior
- `BoardTests`: startpos FEN, empty board, FEN round-trips (incl. EP normalization), copy independence, query correctness
- `MoveTests`: 20 startpos moves, packing round-trip over all 64×64×promo words, castling words verbatim (`e1h1` etc.)
- `PlayTests`: play/unmake bit-identity (incl. hash), illegal move throws + board unchanged, scholar's/fool's mate, stalemate fixture
- `SanTests`: render/parse round-trip incl. disambiguation, `O-O`/`0-0` acceptance, `playSan` error ply
- `ZobristTests`: startpos key equals recorded Rust key; make/unmake key restoration
- `CodecTests`: game parse→export round-trip; replay hashes equal stepped-board hashes; illegal-ply reporting
- `PerftTests`: canonical startpos counts (20 / 400 / 8902 / …) — release gate
- `FFISafetyTests`: adversarial inputs across every entry point (no abort/trap); `BOARD_SIZE`/offset asserts
- Verify: `swift build` and `swift test` pass; Swift 6 mode with zero warnings

### 9. Benchmarks + docs
- Add `perft` + batch-codec throughput benchmarks; record first numbers vs native Rust (informative, with CI regression gate on codec throughput)
- Document the pinned engine version, castling wire format, buffer-size contracts, and panic policy in README
- Verify: `swift test` + benchmarks run in CI

### 10. Final verification
- Run `swift build` for iOS Simulator and macOS; run full `swift test`
- Confirm: no heap allocation in `withLegalMoves`/zobrist hot paths (document method), no `@unchecked Sendable` on engine types, no `shakmaty`/`chessjs` compat imports anywhere
- Confirm XCFramework Release-asset flow end to end (fresh checkout → SPM resolve → build → test, no Rust toolchain installed)
