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

#### Scenario: Invalid FEN throws
- **WHEN** a `Board` is created with an invalid FEN string
- **THEN** the initializer throws a `GigaChessError.invalidFen` (with Rust-provided detail where available), instead of trapping or returning a corrupt board

### Requirement: Value Semantics and Snapshots
`Board` MUST be a Swift `struct` wrapping the Rust board by value. Assignment and parameter passing MUST produce independent bit-for-bit snapshots suitable for search stacks and undo-by-copy.

#### Scenario: Copy independence
- **WHEN** a board is copied and a move is played on the copy
- **THEN** the original board is unchanged

#### Scenario: No heap allocation
- **WHEN** boards are created, copied, or passed across the FFI boundary
- **THEN** no heap allocation occurs on either side (verified by design: `Copy` struct transfer only)

### Requirement: Position Queries
The library MUST expose native board queries: side to move, piece at square, king square, castling rights, en-passant square, halfmove clock, and fullmove number.

#### Scenario: Query after moves
- **WHEN** moves are played on a board
- **THEN** all queries reflect the current position (rights cleared on king/rook moves, clocks updated, en-passant set/cleared per native rules with canonical normalization)

### Requirement: Thread Safety
`Board` MUST be `Sendable` for real (value type, no shared mutable state) and usable from Swift concurrency contexts without external synchronization. The package MUST build clean under Swift 6 strict concurrency with no `@unchecked Sendable` on engine types.

#### Scenario: Concurrent search
- **WHEN** board copies are searched on concurrent tasks
- **THEN** behavior is well-defined with no data races
