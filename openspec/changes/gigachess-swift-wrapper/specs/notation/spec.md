## Purpose
Chess notation import/export across the FFI boundary, starting with FEN strings.

## ADDED Requirements

### Requirement: FEN Export
The library MUST export the current position as a valid FEN string.

#### Scenario: FEN round-trip
- **WHEN** a position is created from a FEN string
- **THEN** the exported FEN matches the input (canonical form)

#### Scenario: FEN after moves
- **WHEN** moves are applied to a position
- **THEN** the exported FEN reflects the current board state, side to move, castling rights, en passant square, halfmove clock, and fullmove number

### Requirement: String Data Transfer
FEN strings MUST be copied across the FFI boundary into caller-owned buffers.

#### Scenario: No shared pointers
- **WHEN** a FEN string is exported from Rust
- **THEN** the string data is copied into a Swift-owned buffer
- **THEN** the Rust side retains no reference to the Swift buffer
