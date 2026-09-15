## 1. Pin Engine Version and Scaffold SPM Package Structure

- [x] 1.1 Record the pinned `gigachess` version/hash in `scripts/build-xcframework.sh` as single source of truth and verify the pin resolves on crates.io
- [x] 1.2 Create `Package.swift` with `CGigaChessFFI` binaryTarget (Release-asset XCFramework) and `GigaChess` Swift wrapper target in Swift 6 language mode with strict concurrency, and verify `swift package describe` succeeds
- [x] 1.3 Create directory structure `Sources/GigaChess/`, `Sources/CGigaChessFFI/include/`, `Tests/GigaChessTests/`, `scripts/`, `Frameworks/` (gitignored) and verify layout matches AGENTS.md repository map

## 2. Rust FFI Layer (Native API Only)

- [x] 2.1 Add Rust FFI crate exposing `extern "C"` lifecycle/queries (`board_startpos`, `board_empty`, `board_from_fen`, `board_to_fen`, `board_turn`, `board_piece_at`, `board_king_square`, `board_castling_rights`, `board_en_passant`, `board_clocks`, `board_size_assert`) with `catch_unwind` panic-safety and verify `cargo build` produces `staticlib`
- [x] 2.2 Add Rust FFI movegen functions (`board_legal_moves`, `board_play`, `board_is_legal`, `board_make_unchecked`/`board_unmake`, `board_in_check`, `board_perft`) over by-value `#[repr(C)]` board plus `Undo` fixed-size bytes, and verify perft parity 20/400/8902
- [x] 2.3 Add Rust FFI SAN/Zobrist/codec functions (`board_move_to_san`, `board_san_to_move`, `board_zobrist`, `parse_movetext_to_moves2`, `moves2_to_san_movetext`, `replay_moves2_stream`) with caller-owned buffers and flat outcomes, and verify adversarial-input test passes with no aborts

## 3. C Bridging Header and Module Map

- [x] 3.1 Write `Sources/CGigaChessFFI/include/gigachess_ffi.h` with all function declarations under single target name `CGigaChessFFI` and verify it compiles with `clang -fsyntax-only`
- [x] 3.2 Write matching `module.modulemap` and verify Swift can `import CGigaChessFFI`

## 4. Build XCFramework Script and CI Guards

- [x] 4.1 Create `scripts/build-xcframework.sh` cross-compiling `aarch64-apple-ios`, `aarch64-apple-ios-sim`, `aarch64-apple-darwin`, running `xcodebuild -create-xcframework`, uploading to GitHub Release and printing checksum for `Package.swift`, and verify script produces valid XCFramework
- [x] 4.2 Add CI job that rebuilds on pin change and fails on `BOARD_SIZE`/offset mismatch, missing FFI symbols, and perft spot-check drift, and verify CI is green on first run

## 5. Swift Wrapper — Board Value Type and Errors

- [x] 5.1 Create `Sources/GigaChess/Board.swift` as `struct Board: Sendable` (no class, no `deinit`) with `init`/`startpos`/`empty`/`init(fen:) throws` plus queries (`turn`, `piece(at:)`, `kingSquare`, `castlingRights`, `enPassant`, clocks, `fen`, `zobrist`, `isCheck`/`isCheckmate`/`isStalemate`) and verify `swift build` succeeds in Swift 6 mode with zero concurrency warnings
- [x] 5.2 Create `Sources/GigaChess/GigaChessError.swift` with `invalidFen`, `illegalMove`, `sanParseFailed`, `bufferTooSmall`, `enginePanicked`, `codecFailed(ply:)` and verify all FFI error codes map to throws

## 6. Swift Wrapper — Move, Undo, Play/Make-Unmake, Visitor

- [x] 6.1 Create `Sources/GigaChess/Move.swift` as `struct Move: Hashable, Equatable, Sendable` wrapping `UInt16` with `from`/`to`/`promotion`, algebraic plus UCI rendering, preserving king-captures-rook castling verbatim, and verify packing round-trip over all words
- [x] 6.2 Create `Sources/GigaChess/Undo.swift` as opaque fixed-size token paired with make/unmake and verify make/unmake restores bit-identical board including hash
- [x] 6.3 Implement `mutating play(_:) throws -> Undo`, `isLegal(_:)`, `makeMoveUnchecked`/`unmake`, `withLegalMoves(_:)` visitor plus `legalMoves()` cold-path convenience, and `perft(depth:)`, and verify `swift build` succeeds

## 7. Swift Wrapper — SAN, Zobrist, Moves2 Codec

- [x] 7.1 Implement SAN `san(for:)`, `init(parsing:board:)`/`move(fromSan:board:)` accepting `O-O` and `0-0`, plus `playSan(_:)` sequence with error ply, and verify render/parse round-trip including disambiguation
- [x] 7.2 Implement `var zobrist: UInt64` by-value access and verify startpos key equals recorded Rust key with make/unmake restoration
- [x] 7.3 Implement codec `parseMovetextToMoves2(_:from:)`, `sanMovetext(from:moves:)`, `replayHashes(moves:from:)` with flat outcomes and caller-owned buffers, and verify game round-trip plus illegal-ply reporting

## 8. Tests — Parity, Not Just Behavior

- [x] 8.1 Write `BoardTests` (startpos FEN, empty board, FEN round-trips incl. EP normalization, copy independence, query correctness) and verify `swift test` passes
- [x] 8.2 Write `MoveTests` (20 startpos moves, packing round-trip over all promo words, castling words verbatim `e1h1`) plus `PlayTests` (play/unmake bit-identity incl. hash, illegal throws with board unchanged, scholar's/fool's mate, stalemate fixture) and verify `swift test` passes
- [x] 8.3 Write `SanTests` (render/parse round-trip incl. disambiguation, `O-O`/`0-0` acceptance, `playSan` error ply), `ZobristTests` (startpos key equality, make/unmake restoration), `CodecTests` (parse→export round-trip, replay hashes equal stepped hashes, illegal-ply reporting) and verify `swift test` passes
- [x] 8.4 Write `PerftTests` (canonical startpos 20/400/8902 release gate) plus `FFISafetyTests` (adversarial inputs across every entry point with no abort/trap, `BOARD_SIZE`/offset asserts) and verify `swift test` passes in Swift 6 mode with zero warnings

## 9. Benchmarks and Docs

- [x] 9.1 Add `perft` plus batch-codec throughput benchmarks, record first numbers vs native Rust, and verify benchmarks run with CI regression gate on codec throughput
- [x] 9.2 Document pinned engine version, castling wire format, buffer-size contracts, and panic policy in README and verify docs match implementation

## 10. Final Verification

- [ ] 10.1 Run `swift build` for iOS Simulator and macOS plus full `swift test`, confirm no heap allocation in `withLegalMoves`/zobrist hot paths, no `@unchecked Sendable` on engine types, no `shakmaty`/`chessjs` compat imports, and verify all checks pass
- [ ] 10.2 Confirm XCFramework Release-asset flow end to end (fresh checkout → SPM resolve → build → test with no Rust toolchain) and verify consumer `import GigaChess` works
