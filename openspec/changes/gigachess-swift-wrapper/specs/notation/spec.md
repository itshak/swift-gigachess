## Purpose
Chess notation import/export across the FFI boundary: FEN (positions) and SAN (moves) — mirroring native `fen` and `san` modules. PGN tag parsing stays app-level; the movetext ↔ moves2 codec lives in `moves2-codec`.

## ADDED Requirements

### Requirement: FEN Export
The library MUST export the current position as a valid FEN string, mirroring native `to_fen()` including canonical en-passant normalization.

#### Scenario: FEN round-trip
- **WHEN** a position is created from a FEN string
- **THEN** the exported FEN matches the input (canonical form)

#### Scenario: FEN after moves
- **WHEN** moves are applied to a position
- **THEN** the exported FEN reflects the current board state, side to move, castling rights, en passant square, halfmove clock, and fullmove number

### Requirement: SAN Rendering
The library MUST render any legal move in SAN notation for a given board, mirroring native `move_to_san` (including disambiguation, check/mate suffixes, and `O-O` castling with letter-O).

#### Scenario: Render SAN
- **WHEN** a legal move is rendered against its board
- **THEN** the output is canonical SAN (e.g. `e4`, `Nf3`, `exd8=Q+`, `O-O`)

### Requirement: SAN Parsing
The library MUST parse SAN strings to moves against a given board, mirroring native `san_to_move` (accepting both `O-O` and `0-0` castle spellings per BlindBase domain rules).

#### Scenario: Parse SAN
- **WHEN** a valid SAN string is parsed against its board
- **THEN** the corresponding `Move` is returned
- **WHEN** the SAN is invalid or illegal in that position
- **THEN** a `GigaChessError` is thrown

### Requirement: String Data Transfer
FEN/SAN strings MUST be copied across the FFI boundary into caller-owned buffers. The Rust side MUST NEVER allocate a string that Swift must free.

#### Scenario: No shared pointers
- **WHEN** a FEN or SAN string crosses from Rust
- **THEN** the data is copied into a Swift-owned stack buffer (FEN ≤ 96 bytes, SAN ≤ 12 bytes)
- **THEN** the Rust side retains no reference to the Swift buffer
