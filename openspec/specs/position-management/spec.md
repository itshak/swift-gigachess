# Position Management Specification

## Purpose
Lifecycle and value semantics of chess positions: creation, copying/snapshots, and querying across the Rust↔Swift FFI boundary. `Board` is a Swift value type mirroring the native `Copy` Rust board — there is no heap allocation and no free function.

## Requirements

### Requirement: Position Creation
The library MUST support creating positions from the standard starting position, an empty board, and a FEN string — mirroring native `Board::startpos()`, `Board::empty()`, and `fen::parse_fen`.

#### Scenario: Create starting position
- **GIVEN** no existing position
- **WHEN** a `Board` is created with no arguments (or via `Board.startpos()`)
- **THEN** the position represents the standard chess starting position (FEN: `rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1`)

#### Scenario: Create from FEN
- **GIVEN** a valid FEN string
- **WHEN** a `Board` is created with it
- **THEN** the position represents the board state described by that FEN

#### Scenario: Invalid FEN throws
- **GIVEN** an invalid FEN string
- **WHEN** a `Board` is created with it
- **THEN** the initializer throws a `GigaChessError.invalidFen` (with Rust-provided detail where available), instead of trapping or returning a corrupt board

#### Scenario: Create empty board
- **GIVEN** no existing position
- **WHEN** a `Board` is created via `Board.empty()`
- **THEN** the board contains no pieces, White is to move, castling rights are zero, and there is no en-passant square

### Requirement: Value Semantics and Snapshots
`Board` MUST be a Swift `struct` holding Swift-owned 144-byte storage (`BoardStorage`, 18 × `UInt64`, layout-identical to the native `Copy` Rust board). Assignment and parameter passing MUST copy the bytes, producing independent bit-for-bit snapshots suitable for search stacks and undo-by-copy. Every FFI call bridges through scoped pointer rebinding (`withGigaBoard`), so the board NEVER crosses FFI as a language-level struct value and no field-offset coupling exists between Swift and Rust.

#### Scenario: Copy independence
- **GIVEN** a board
- **WHEN** it is copied and a move is played on the copy
- **THEN** the original board is unchanged

#### Scenario: No heap allocation
- **GIVEN** board creation, copying, or FFI transfer
- **WHEN** any of these is performed
- **THEN** board transfer and copying move bytes only — no board memory is heap-allocated, retained, or freed on either side (Swift zero-fills caller-owned storage before each FFI constructor call; Rust copies bytes in/out)

#### Scenario: Bit-for-bit snapshots
- **GIVEN** a board
- **WHEN** it is copied (assignment or parameter passing)
- **THEN** the copy is an independent byte-wise snapshot — playing a move on the copy leaves the original untouched

#### Scenario: Equality compares observable state, not raw bytes
- **GIVEN** two boards
- **WHEN** they are compared
- **THEN** equality covers turn, all 64 squares, castling rights, en-passant, clocks, and the Zobrist key — never raw storage bytes (Rust padding bytes are uninitialized and differ between identical constructions), and `Hashable` combines the Zobrist key

### Requirement: Position Queries
The library MUST expose native board queries: side to move, piece at square, king square, castling rights, en-passant square, halfmove clock, and fullmove number.

#### Scenario: Query after moves
- **GIVEN** a board on which moves have been played
- **WHEN** its queries are read
- **THEN** all queries reflect the current position (rights cleared on king/rook moves, clocks updated, en-passant set/cleared per native rules with canonical normalization)

#### Scenario: Square indexing
- **GIVEN** any square-taking API (`piece(at:)`, `kingSquare(_:)`, `enPassant`, `Move(from:to:)`)
- **WHEN** square indices are passed
- **THEN** indices use little-endian rank-file mapping with `0 = a1` through `63 = h8`

### Requirement: Thread Safety
`Board` MUST be `Sendable` for real (value type, no shared mutable state) and usable from Swift concurrency contexts without external synchronization. The package MUST build clean under Swift 6 strict concurrency with no `@unchecked Sendable` on engine types.

#### Scenario: Concurrent search
- **GIVEN** board copies shared across concurrent tasks
- **WHEN** they are searched without external synchronization
- **THEN** behavior is well-defined with no data races

#### Scenario: No unchecked or retroactive conformances
- **GIVEN** a build under Swift 6 strict concurrency
- **WHEN** engine-type conformances are checked
- **THEN** `Sendable` holds by compiler checking for every engine type, with no `@unchecked Sendable` and no retroactive conformance on imported C types (the storage types are declared in Swift, so checking applies; CI fails the build otherwise)

### Requirement: API Documentation
All public API in this capability SHALL carry Swift DocC documentation, and every engine type SHALL be a struct or enum — never a class.

#### Scenario: DocC coverage
- **GIVEN** the public API surface of this capability (`Board`, `Color`, `Role`, `Piece`, `GigaChessError`, and their members)
- **WHEN** it is inspected
- **THEN** every public type, method, property, and enum case carries `///` documentation

#### Scenario: Value types only
- **GIVEN** the engine types (`Board`, `Color`, `Role`, `Piece`, `GigaChessError`)
- **WHEN** they are inspected
- **THEN** each is a struct or enum; no class exists anywhere in the wrapper
