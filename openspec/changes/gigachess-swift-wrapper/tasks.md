## Tasks

### 1. Scaffold SPM package structure
- Create `Package.swift` with three targets: `CGigaChessFFI` (binaryTarget), `CChessFFIHeaders` (C module with headers), `GigaChess` (Swift wrapper)
- Create directory structure: `Sources/GigaChess/`, `Sources/CChessFFIHeaders/include/`, `Frameworks/`, `Tests/GigaChessTests/`, `scripts/`
- Add `.gitignore` for build artifacts
- Verify: `swift package describe` succeeds

### 2. Write Rust FFI layer
- Add `src/ffi.rs` to the `gigachess` Rust crate with `#[no_mangle] extern "C"` functions:
  - `chess_position_new`, `chess_position_from_fen`, `chess_position_free`
  - `chess_legal_moves` (writes into caller buffer, returns count)
  - `chess_make_move` (packed UInt16 move)
  - `chess_get_fen` (writes into caller buffer)
  - `chess_is_check`, `chess_is_checkmate`, `chess_is_stalemate`
- Set `crate-type = ["staticlib"]` in `Cargo.toml`
- Verify: `cargo build --release` produces `libgigachess.a`

### 3. Create C bridging header and module map
- Write `Sources/CChessFFIHeaders/include/gigachess_ffi.h` with all function declarations
- Write `Sources/CChessFFIHeaders/include/module.modulemap`
- Verify: header compiles cleanly with `clang -fsyntax-only`

### 4. Write build-xcframework script
- Create `scripts/build-xcframework.sh` that:
  - Cross-compiles for `aarch64-apple-ios`, `aarch64-apple-ios-sim`, `aarch64-apple-darwin`
  - Runs `xcodebuild -create-xcframework` with all architectures + headers
  - Outputs to `Frameworks/CGigaChessFFI.xcframework/`
- Verify: script produces valid xcframework

### 5. Implement Swift wrapper — Position
- Create `Sources/GigaChess/Position.swift`:
  - `final class Position: @unchecked Sendable`
  - `init()` — starting position via `chess_position_new`
  - `init?(fen: String)` — failable, via `chess_position_from_fen`
  - `deinit` — calls `chess_position_free`
  - `var fen: String` — reads via `chess_get_fen` into stack buffer
  - `var isCheck: Bool`, `var isCheckmate: Bool`, `var isStalemate: Bool`
- Verify: `swift build` succeeds

### 6. Implement Swift wrapper — Move and legalMoves
- Create `Sources/GigaChess/Move.swift`:
  - `struct Move: Hashable, Equatable, Sendable` wrapping `UInt16`
  - Computed properties: `from`, `to`, `fromAlgebraic`, `toAlgebraic`
- Add to `Position`:
  - `func legalMoves() -> [Move]` — calls `chess_legal_moves` with stack buffer
  - `@discardableResult func makeMove(_ move: Move) -> Bool`
- Verify: `swift build` succeeds

### 7. Write tests
- Create `Tests/GigaChessTests/PositionTests.swift`:
  - Test starting position FEN
  - Test 20 legal moves from starting position
  - Test make move and FEN update
  - Test check/checkmate/stalemate detection (scholar's mate)
  - Test failable init with invalid FEN
  - Test FEN round-trip
- Verify: `swift build` and `swift test` pass

### 8. Final verification
- Run `swift build` for all platforms (iOS Simulator, macOS)
- Run `swift test`
- Verify no memory leaks (Position deinit fires correctly)
- Verify thread safety documentation is present
