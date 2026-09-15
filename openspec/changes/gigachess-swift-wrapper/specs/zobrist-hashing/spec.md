## Purpose
Direct access to the incrementally-maintained 64-bit Polyglot Zobrist key — the primitive behind all position-keyed lookups (repertoire trees, transposition caches, GigaBase position indexing).

## ADDED Requirements

### Requirement: Zobrist Key Access
The library MUST expose the current position's Zobrist key as a plain `UInt64`, mirroring native `Board::zobrist()`.

#### Scenario: Key stability
- **WHEN** the key is read twice without an intervening move
- **THEN** both reads are identical

#### Scenario: Key evolution
- **WHEN** a move is played and then unmade with its `Undo` token
- **THEN** the key after unmake equals the key before the move (incremental update + restore, bit-exact)

### Requirement: Cross-Language Key Equality
Keys produced by the Swift wrapper MUST equal keys produced by the Rust engine and the TypeScript `gigachess` package for the same positions (shared Polyglot tables).

#### Scenario: Startpos key
- **WHEN** the startpos key is read via Swift
- **THEN** it equals the documented Rust startpos key (recorded in tests on first implementation)

### Requirement: FFI Transfer
The key MUST cross FFI by value (`UInt64` in a register). No buffer, no allocation, no heap object.

#### Scenario: Hot-loop use
- **WHEN** keys are read inside a search loop
- **THEN** each read is a single FFI call returning a value type
