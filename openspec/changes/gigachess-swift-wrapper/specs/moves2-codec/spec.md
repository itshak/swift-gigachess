## Purpose
Batch movetext ↔ moves2 conversion and hash-stream replay over contiguous buffers — mirroring the native `database` and `replay` modules. This is the engine slice behind GigaBase import/export and million-game position search; `HashMap`-returning aggregation helpers stay Rust-side.

## ADDED Requirements

### Requirement: Movetext to Moves2 Parsing
The library MUST parse SAN movetext into packed moves2 words, mirroring native `parse_movetext_to_moves2`.

#### Scenario: Parse game
- **WHEN** a SAN movetext string is parsed with its starting FEN
- **THEN** the output words decode to the game’s moves (`from | (to << 6) | (promo << 12)`)
- **WHEN** the movetext contains an illegal move
- **THEN** parsing stops and reports the offending ply index (no partial silent success)

### Requirement: Moves2 to SAN Export
The library MUST convert moves2 words back to SAN movetext, mirroring native `moves2_to_san_movetext`.

#### Scenario: Round-trip
- **WHEN** words produced by parsing are exported back
- **THEN** the movetext is equivalent (canonical SAN per move)

### Requirement: Hash-Stream Replay
The library MUST replay moves2 streams to Zobrist hash sequences, mirroring native `replay_moves2_stream` / `replay_moves2_batch`, for position search without materializing SAN.

#### Scenario: Replay stream
- **WHEN** a word stream is replayed from a starting position
- **THEN** the returned hash per ply matches stepping the `Board` through the same moves
- **THEN** an illegal word is reported with its ply index and replay stops there

### Requirement: Flat FFI Transfer
All codec/replay traffic MUST cross FFI as contiguous `UInt16`/`UInt64` buffers with explicit lengths plus flat outcome structs (count, illegal-ply index, status code). No `Vec`, `String`, or `HashMap` crosses the boundary; Swift owns all buffers.

#### Scenario: Batch import
- **WHEN** 10,000 games are converted in one batch call
- **THEN** the crossing is a bounded number of buffer calls (not one call per move) and throughput is benchmarked against native Rust in CI (regression gate, not just parity)
