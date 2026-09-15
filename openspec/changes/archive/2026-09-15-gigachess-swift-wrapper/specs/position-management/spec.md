## Purpose
Lifecycle and value semantics of chess positions: creation, copying/snapshots, and querying across the Rust↔Swift FFI boundary. `Board` is a Swift value type mirroring the native `Copy` Rust board — there is no heap allocation and no free function.

## ADDED Requirements

### Requirement: Position Creation
The library MUST support creating positions from the standard starting position, an empty board, and a FEN string — mirroring native `Board::startpos()`, `Board::empty()`, and `fen::parse_fen`.

#### Scenario: Create starting position
- **WHEN** a `Board` is created with no arguments (or via `Board.startpos()`)
- **THEN** the position represents the standard chess starting position (FEN: `rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1`)

#### Scenario: Create from FEN
- **WHEN** a `Board` is created with a valid FEN string
- **THEN** the position represents the board state described by that FEN

#### Scenario: Create empty board
- **WHEN** a `Board` is created via `Board.empty()`
- **THEN** the board contains no pieces, White is to move, castling rights are zero, and there is no en-passant square

#### Scenario: Invalid FEN throws
- **WHEN** a `Board` is created with an invalid FEN string
- **THEN** the initializer throws a `GigaChessError.invalidFen` (with Rust-provided detail where available), instead of trapping or returning a corrupt board

### Requirement: Value Semantics and Snapshots
`Board` MUST be a Swift `struct` holding Swift-owned 144-byte storage (`BoardStorage`, 18 × `UInt64`, layout-identical to the native `Copy` Rust board). Assignment and parameter passing MUST copy the bytes, producing independent bit-for-bit snapshots suitable for search stacks and undo-by-copy. Every FFI call bridges through scoped pointer rebinding (`withGigaBoard`), so the board NEVER crosses FFI as a language-level struct value and no field-offset coupling exists between Swift and Rust.

#### Scenario: Copy independence
- **WHEN** a board is copied and a move is played on the copy
- **THEN** the original board is unchanged

#### Scenario: No heap allocation
- **WHEN** boards are created, copied, or passed across the FFI boundary
- **THEN** board transfer and copying move bytes only — no board memory is heap-allocated, retained, or freed on either side (Swift zero-fills caller-owned storage before each FFI constructor call; Rust copies bytes in/out)

#### Scenario: Bit-for-bit snapshots
- **WHEN** a board is copied (assignment or parameter passing)
- **THEN** the copy is an independent byte-wise snapshot — playing a move on the copy leaves the original untouched

#### Scenario: Equality compares observable state, not raw bytes
- **WHEN** two boards are compared
- **THEN** equality covers turn, all 64 squares, castling rights, en-passant, clocks, and the Zobrist key — never raw storage bytes (Rust padding bytes are uninitialized and differ between identical constructions, as CI caught), and `Hashable` combines the Zobrist key

### Requirement: Position Queries
The library MUST expose native board queries: side to move, piece at square, king square, castling rights, en-passant square, halfmove clock, and fullmove number.

#### Scenario: Query after moves
- **WHEN** moves are played on a board
- **THEN** all queries reflect the current position (rights cleared on king/rook moves, clocks updated, en-passant set/cleared per native rules with canonical normalization)

#### Scenario: Square indexing
- **WHEN** squares are passed to `piece(at:)`, `kingSquare(_:)`, `enPassant`, or `Move(from:to:)`
- **THEN** indices use little-endian rank-file mapping with `0 = a1` through `63 = h8`

### Requirement: Thread Safety
`Board` MUST be `Sendable` for real (value type, no shared mutable state) and usable from Swift concurrency contexts without external synchronization. The package MUST build clean under Swift 6 strict concurrency with no `@unchecked Sendable` on engine types.

#### Scenario: Concurrent search
- **WHEN** board copies are searched on concurrent tasks
- **THEN** behavior is well-defined with no data races

#### Scenario: No unchecked or retroactive conformances
- **WHEN** the package builds under Swift 6 strict concurrency
- **THEN** `Sendable` holds by compiler checking for every engine type, with no `@unchecked Sendable` and no retroactive conformance on imported C types (the storage types are declared in Swift, so checking applies; CI fails the build otherwise)
