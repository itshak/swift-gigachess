## Purpose
Batch movetext ↔ moves2 conversion and hash-stream replay over contiguous buffers — mirroring the native `database` module and the per-game `replay` path (one FFI call per game; the parallel `replay_moves2_batch` and `HashMap`-returning aggregation helpers stay Rust-side). This is the engine slice behind GigaBase import/export and million-game position search.

## ADDED Requirements

### Requirement: Movetext to Moves2 Parsing
The library MUST parse SAN movetext into packed moves2 words, mirroring native `parse_movetext_to_moves2`.

#### Scenario: Parse game
- **WHEN** a SAN movetext string is parsed with its starting FEN
- **THEN** the output words decode to the game’s moves (`from | (to << 6) | (promo << 12)`)
- **WHEN** the movetext contains an illegal move
- **THEN** parsing throws `GigaChessError.codecFailed(ply:)` with the offending ply index (no partial silent success); a bad start FEN throws `invalidFen`

### Requirement: Moves2 to SAN Export
The library MUST convert moves2 words back to SAN movetext with move numbers plus an optional trailing result token, mirroring native `moves2_to_san_movetext`.

#### Scenario: Round-trip
- **WHEN** words produced by parsing are exported back (optionally with a result token such as `1-0`)
- **THEN** the movetext is equivalent (canonical SAN per move)
- **WHEN** a word is illegal in its replayed position
- **THEN** export throws `GigaChessError.codecFailed(ply:)` with the offending ply index

### Requirement: Hash-Stream Replay
The library MUST replay moves2 streams from an arbitrary start FEN to Zobrist hash sequences, via per-game `replay_moves2_stream` (backed by native `replay_moves2_hashes`), for position search without materializing SAN. There is intentionally no multi-game batch entry: batch workloads issue one FFI call per game.

#### Scenario: Replay stream
- **WHEN** a word stream is replayed from a start FEN
- **THEN** `moves.count + 1` hashes are returned (start position first), each matching a `Board` stepped through the same moves
- **THEN** an illegal word throws `GigaChessError.codecFailed(ply:)` with its ply index and replay stops there

### Requirement: Flat FFI Transfer
All codec/replay traffic MUST cross FFI as contiguous `UInt16`/`UInt64` buffers with explicit lengths plus flat outcome structs (count, illegal-ply index, status code). No `Vec`, `String`, or `HashMap` crosses the boundary; Swift owns all buffers.

#### Scenario: Batch import
- **WHEN** games are converted or replayed
- **THEN** each game crosses in exactly one FFI call (never one call per move); contiguous `UInt16`/`UInt64` caller buffers with explicit lengths plus count/fail-ply out-params carry everything

#### Scenario: Bounded buffers with fallback
- **WHEN** a single-game movetext exceeds the 4,096-word caller buffer
- **THEN** parsing retries once in a heap buffer (16,384 words) rather than failing; only truly oversized input surfaces `bufferTooSmall`

#### Scenario: Throughput benchmarks
- **WHEN** codec throughput is measured
- **THEN** `PerformanceTests` perft/codec `measure` blocks run under `swift test` and first numbers vs native Rust are recorded in `Benchmarks/README.md` (informative comparison, no hard CI threshold)
