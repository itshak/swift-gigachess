# Zobrist Hashing Specification

## Purpose
Direct access to the incrementally-maintained 64-bit Polyglot Zobrist key — the primitive behind all position-keyed lookups (repertoire trees, transposition caches, GigaBase position indexing).

## Requirements

### Requirement: Zobrist Key Access
The library MUST expose the current position's Zobrist key as a plain `UInt64`, mirroring native `Board::zobrist()`.

#### Scenario: Key stability
- **GIVEN** a position with no intervening move
- **WHEN** the key is read twice
- **THEN** both reads are identical

#### Scenario: Key evolution
- **GIVEN** a move played and then unmade with its `Undo` token
- **WHEN** the key is compared before the move and after the unmake
- **THEN** both keys are equal (incremental update + restore, bit-exact)

#### Scenario: Board hashing uses the key
- **GIVEN** a board used as a hashed key (e.g. in a dictionary)
- **WHEN** it is hashed
- **THEN** `Hashable` combines the current Zobrist key

### Requirement: Cross-Language Key Equality
Keys produced by the Swift wrapper MUST equal keys produced by the Rust engine and the TypeScript `gigachess` package for the same positions (shared Polyglot tables).

#### Scenario: Startpos key
- **GIVEN** the standard starting position
- **WHEN** its key is read via Swift
- **THEN** it equals `0x463b96181691fc9c` — the pinned-engine key recorded in the Rust tests, the Swift suite, `scripts/build-xcframework.sh`, and the README

### Requirement: FFI Transfer
The key MUST cross FFI by value (`UInt64` in a register). No buffer, no allocation, no heap object.

#### Scenario: Hot-loop use
- **GIVEN** a search loop reading keys
- **WHEN** keys are read inside it
- **THEN** each read is a single FFI call returning a value type

### Requirement: API Documentation
All public API in this capability SHALL carry Swift DocC documentation. This capability exposes a single value-type property and introduces no new types.

#### Scenario: DocC coverage
- **GIVEN** the public API surface of this capability (`zobrist`)
- **WHEN** it is inspected
- **THEN** it carries `///` documentation
