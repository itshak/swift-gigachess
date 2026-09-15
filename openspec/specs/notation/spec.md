# Notation Specification

## Purpose
Chess notation import/export across the FFI boundary: FEN (positions) and SAN (moves) — mirroring native `fen` and `san` modules. PGN tag parsing stays app-level; the movetext ↔ moves2 codec lives in `moves2-codec`.

## Requirements

### Requirement: FEN Export
The library MUST export the current position as a valid FEN string, mirroring native `to_fen()` including canonical en-passant normalization.

#### Scenario: FEN round-trip
- **GIVEN** a position created from a FEN string
- **WHEN** it is exported back
- **THEN** the exported FEN matches the input (canonical form)

#### Scenario: FEN after moves
- **GIVEN** a position to which moves have been applied
- **WHEN** it is exported
- **THEN** the exported FEN reflects the current board state, side to move, castling rights, en passant square, halfmove clock, and fullmove number

### Requirement: SAN Rendering
The library MUST render any legal move in SAN notation for a given board, mirroring native `move_to_san` (including disambiguation, check/mate suffixes, and `O-O` castling with letter-O).

#### Scenario: Render SAN
- **GIVEN** a legal move and its board
- **WHEN** the move is rendered against it
- **THEN** the output is canonical SAN (e.g. `e4`, `Nf3`, `exd8=Q+`, `O-O`)

### Requirement: SAN Parsing
The library MUST parse SAN strings to moves against a given board, mirroring native `san_to_move` (accepting both `O-O` and `0-0` castle spellings per BlindBase domain rules).

#### Scenario: Parse SAN
- **GIVEN** a valid SAN string and its board
- **WHEN** the string is parsed against the board
- **THEN** the corresponding `Move` is returned (also available as `Move(parsing:on:)`)
- **GIVEN** an invalid SAN string or one illegal in that position
- **WHEN** it is parsed
- **THEN** direct parsing throws `GigaChessError.sanParseFailed` carrying the offending token

### Requirement: SAN Sequence Play
The library MUST play an ordered sequence of SAN tokens, returning one `Undo` per ply and identifying the first failing token by index.

#### Scenario: Play sequence
- **GIVEN** ordered SAN tokens
- **WHEN** they are played in order via `playSan(_:)`
- **THEN** one `Undo` per ply is returned (a variadic spelling is also available)

#### Scenario: Bad token reports ply
- **GIVEN** a token sequence whose token at index `i` is invalid or illegal in its position
- **WHEN** the sequence is played
- **THEN** `GigaChessError.codecFailed(ply: i)` is thrown

### Requirement: String Data Transfer
FEN/SAN strings MUST be copied across the FFI boundary into caller-owned buffers. The Rust side MUST NEVER allocate a string that Swift must free.

#### Scenario: No shared pointers
- **GIVEN** a FEN or SAN string crossing from Rust
- **WHEN** it is transferred
- **THEN** the data is copied into a Swift-owned temporary buffer under the contract FEN ≤ 96 bytes + NUL, SAN ≤ 12 bytes + NUL (Rust always NUL-terminates when capacity > 0 and returns `BUFFER_TOO_SMALL` otherwise)
- **THEN** the Rust side retains no reference to the Swift buffer

### Requirement: API Documentation
All public API in this capability SHALL carry Swift DocC documentation. This capability exposes functions only and introduces no new types.

#### Scenario: DocC coverage
- **GIVEN** the public API surface of this capability (`fen()`, `san(for:)`, `move(fromSan:)`, `playSan(_:)`, `Move(parsing:on:)`)
- **WHEN** it is inspected
- **THEN** every public method carries `///` documentation
