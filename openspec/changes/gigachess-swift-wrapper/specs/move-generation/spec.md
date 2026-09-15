## Purpose
Legal move generation, move application (play, make/unmake), bulk enumeration, perft, and game state detection — mirroring the native `Board` movegen API with zero-allocation hot paths.

## ADDED Requirements

### Requirement: Legal Move Generation
The library MUST generate all legal moves for the current position, mirroring native `legal_moves()`.

#### Scenario: Starting position
- **WHEN** legal moves are requested for the starting position
- **THEN** exactly 20 moves are returned

#### Scenario: Move representation
- **WHEN** a legal move is returned
- **THEN** it is a value type (`struct Move`) wrapping the 16-bit Move2 word (`from | (to << 6) | (promo << 12)`, promo 0 = none, 1 = N, 2 = B, 3 = R, 4 = Q)
- **THEN** moves expose `from: UInt8`, `to: UInt8`, `promotion: Promotion?` (knight/bishop/rook/queen), `uci` rendering (`e2e4`, `e7e8q`, castling verbatim), square-name helpers (`squareName(_:)` / `square(fromName:)`), and a failable `init(uci:)` that checks shape only (legality stays with `Board`)
- **THEN** moves are `Hashable`, `Equatable`, and `Sendable`

#### Scenario: Castling encoding
- **WHEN** a castling move is generated
- **THEN** it uses native king-captures-rook encoding (`e1h1`, `e1a1`, `e8h8`, `e8a8`) — identical to the Rust engine and `gigaboard` wire format

### Requirement: Bulk Enumeration Without Allocation
The library MUST provide a visitor/buffer-fill API (mirroring native `generate_visitor` / `MoveSink`) for hot paths, in addition to the allocating convenience API.

#### Scenario: Visitor path allocates nothing
- **WHEN** legal moves are enumerated via `withLegalMoves(_:)` (or buffer-fill variant)
- **THEN** no Swift heap allocation occurs per call (caller-provided stack buffer of at least `MAX_MOVES` = 256 words)

#### Scenario: Convenience path
- **WHEN** `legalMoves()` is called
- **THEN** it returns `[Move]` (allocating) and is documented as the cold-path API

### Requirement: Move Application
The library MUST support `play` (failable, legality-checked, mirroring native `play() -> Result<Undo, IllegalMove>`), `isLegal` checks, and explicit make/unmake with `Undo` tokens for search.

#### Scenario: Apply legal move
- **WHEN** a legal move is played on a (mutable) board
- **THEN** the board is updated and an `Undo` token is returned

#### Scenario: Apply illegal move
- **WHEN** an illegal move is played
- **THEN** the board is unchanged and a `GigaChessError.illegalMove` is thrown

#### Scenario: Make/unmake round-trip
- **WHEN** a move is made with `makeMoveUnchecked` and then unmade with its `Undo` token
- **THEN** the board is bit-identical to its pre-move state (hash included)

#### Scenario: Unchecked make skips legality
- **WHEN** a move is made with `makeMoveUnchecked`
- **THEN** no legality check runs (the caller guarantees legality; intended for search hot loops), and an `Undo` token is still returned for `unmake(_:undo:)`

### Requirement: Perft Parity
The library MUST expose perft counting with results identical to native Rust perft at every depth.

#### Scenario: Known perft values
- **WHEN** perft is run from the starting position
- **THEN** node counts match the canonical values (depth 1 = 20, depth 2 = 400, depth 3 = 8902, depth 4 = 197281 — the depth-4 count is the release gate)

### Requirement: Game State Detection
The library MUST detect check, checkmate, and stalemate from native state (`in_check` plus a count-only legal-move query against a null buffer — zero-alloc, no move materialization).

#### Scenario: Check detection
- **WHEN** the current side's king is in check
- **THEN** `isCheck` returns `true`

#### Scenario: Checkmate detection
- **WHEN** the current side is in checkmate (e.g. scholar's mate / fool's mate)
- **THEN** `isCheckmate` returns `true`
- **THEN** legal move enumeration yields zero moves

#### Scenario: Stalemate detection
- **WHEN** the current side has no legal moves but is not in check
- **THEN** `isStalemate` returns `true`
