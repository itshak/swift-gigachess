# Moves2 Codec Specification

## Purpose
Batch movetext ↔ moves2 conversion and hash-stream replay over contiguous buffers — mirroring the native `database` module and the per-game `replay` path (one FFI call per game; the parallel `replay_moves2_batch` and `HashMap`-returning aggregation helpers stay Rust-side). This is the engine slice behind GigaBase import/export and million-game position search.

## Requirements

### Requirement: Movetext to Moves2 Parsing
The library MUST parse SAN movetext into packed moves2 words, mirroring native `parse_movetext_to_moves2`.

#### Scenario: Parse game
- **GIVEN** a SAN movetext string with its starting FEN
- **WHEN** it is parsed
- **THEN** the output words decode to the game’s moves (`from | (to << 6) | (promo << 12)`)
- **GIVEN** movetext containing an illegal move
- **WHEN** it is parsed
- **THEN** parsing throws `GigaChessError.codecFailed(ply:)` with the offending ply index (no partial silent success); a bad start FEN throws `invalidFen`

### Requirement: Moves2 to SAN Export
The library MUST convert moves2 words back to SAN movetext with move numbers plus an optional trailing result token, mirroring native `moves2_to_san_movetext`.

#### Scenario: Round-trip
- **GIVEN** words produced by parsing (and optionally a result token such as `1-0`)
- **WHEN** they are exported back
- **THEN** the movetext is equivalent (canonical SAN per move)
- **GIVEN** a word illegal in its replayed position
- **WHEN** it is exported
- **THEN** export throws `GigaChessError.codecFailed(ply:)` with the offending ply index

### Requirement: Hash-Stream Replay
The library MUST replay moves2 streams from an arbitrary start FEN to Zobrist hash sequences, via per-game `replay_moves2_stream` (backed by native `replay_moves2_hashes`), for position search without materializing SAN. There is intentionally no multi-game batch entry: batch workloads issue one FFI call per game.

#### Scenario: Replay stream
- **GIVEN** a word stream with a start FEN
- **WHEN** it is replayed
- **THEN** `moves.count + 1` hashes are returned (start position first), each matching a `Board` stepped through the same moves
- **GIVEN** a stream containing an illegal word
- **WHEN** it is replayed
- **THEN** replay throws `GigaChessError.codecFailed(ply:)` with its ply index and stops there

### Requirement: Flat FFI Transfer
All codec/replay traffic MUST cross FFI as contiguous `UInt16`/`UInt64` buffers with explicit lengths plus flat outcome structs (count, illegal-ply index, status code). No `Vec`, `String`, or `HashMap` crosses the boundary; Swift owns all buffers.

#### Scenario: Batch import
- **GIVEN** games to convert or replay
- **WHEN** they cross FFI
- **THEN** each game crosses in exactly one FFI call (never one call per move); contiguous `UInt16`/`UInt64` caller buffers with explicit lengths plus count/fail-ply out-params carry everything

#### Scenario: Bounded buffers with fallback
- **GIVEN** a single-game movetext exceeding the 4,096-word caller buffer
- **WHEN** it is parsed
- **THEN** parsing retries once in a heap buffer (16,384 words) rather than failing; only truly oversized input surfaces `bufferTooSmall`

#### Scenario: Throughput benchmarks
- **GIVEN** a codec throughput measurement
- **WHEN** it runs
- **THEN** `PerformanceTests` perft/codec `measure` blocks run under `swift test`, and the `bench` workflow additionally runs Rust criterion (`ffi_parity`) against Swift (`GigaBenchmarks`) on identical seeded corpora with a joined comparison table (informative, no hard CI threshold)
- **THEN** first numbers vs native Rust are recorded in `Benchmarks/README.md` and `Benchmarks/results.log`

### Requirement: API Documentation
All public API in this capability SHALL carry Swift DocC documentation. This capability exposes functions only and introduces no new types.

#### Scenario: DocC coverage
- **GIVEN** the public API surface of this capability (`parseMovetextToMoves2`, `sanMovetext`, `replayHashes`)
- **WHEN** it is inspected
- **THEN** every public method carries `///` documentation
