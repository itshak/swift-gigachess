# Move Generation Specification

## Purpose
Legal move generation, move application (play, make/unmake), bulk enumeration, perft, and game state detection — mirroring the native `Board` movegen API with zero-allocation hot paths.

## Requirements

### Requirement: Legal Move Generation
The library MUST generate all legal moves for the current position, mirroring native `legal_moves()`.

#### Scenario: Starting position
- **GIVEN** the standard starting position
- **WHEN** legal moves are requested for it
- **THEN** exactly 20 moves are returned

#### Scenario: Move representation
- **GIVEN** a returned legal move
- **WHEN** it is inspected
- **THEN** it is a value type (`struct Move`) wrapping the 16-bit Move2 word (`from | (to << 6) | (promo << 12)`, promo 0 = none, 1 = N, 2 = B, 3 = R, 4 = Q)
- **THEN** moves expose `from: UInt8`, `to: UInt8`, `promotion: Promotion?` (knight/bishop/rook/queen), `uci` rendering (`e2e4`, `e7e8q`, castling verbatim), square-name helpers (`squareName(_:)` / `square(fromName:)`), and a failable `init(uci:)` that checks shape only (legality stays with `Board`)
- **THEN** moves are `Hashable`, `Equatable`, and `Sendable`

#### Scenario: Castling encoding
- **GIVEN** a generated castling move
- **WHEN** it is inspected
- **THEN** it uses native king-captures-rook encoding (`e1h1`, `e1a1`, `e8h8`, `e8a8`) — identical to the Rust engine and `gigaboard` wire format

### Requirement: Bulk Enumeration Without Allocation
The library MUST provide a visitor/buffer-fill API (mirroring native `generate_visitor` / `MoveSink`) for hot paths, in addition to the allocating convenience API.

#### Scenario: Visitor path allocates nothing
- **GIVEN** a hot enumeration loop
- **WHEN** legal moves are enumerated via `withLegalMoves(_:)` (or buffer-fill variant)
- **THEN** no Swift heap allocation occurs per call (caller-provided stack buffer of at least `MAX_MOVES` = 256 words)

#### Scenario: Convenience path
- **GIVEN** a caller that accepts allocation
- **WHEN** `legalMoves()` is called
- **THEN** it returns `[Move]` (allocating) and is documented as the cold-path API

### Requirement: Move Application
The library MUST support `play` (failable, legality-checked, mirroring native `play() -> Result<Undo, IllegalMove>`), `isLegal` checks, and explicit make/unmake with `Undo` tokens for search.

#### Scenario: Apply legal move
- **GIVEN** a mutable board and a legal move
- **WHEN** the move is played on it
- **THEN** the board is updated and an `Undo` token is returned

#### Scenario: Apply illegal move
- **GIVEN** a board and an illegal move
- **WHEN** the move is played
- **THEN** the board is unchanged and a `GigaChessError.illegalMove` is thrown

#### Scenario: Make/unmake round-trip
- **GIVEN** a board and a legal move with its `Undo` token from `makeMoveUnchecked`
- **WHEN** the move is unmade with that token
- **THEN** the board equals its pre-move state across all observable state plus the hash (`==` is state-wise: raw storage bytes are excluded because Rust padding is uninitialized)

#### Scenario: Unchecked make skips legality
- **GIVEN** a search hot loop holding a legal move
- **WHEN** the move is made with `makeMoveUnchecked`
- **THEN** no legality check runs (the caller guarantees legality; intended for search hot loops), and an `Undo` token is still returned for `unmake(_:undo:)`

### Requirement: Perft Parity
The library MUST expose perft counting with results identical to native Rust perft at every depth.

#### Scenario: Known perft values
- **GIVEN** the starting position
- **WHEN** perft is run from it
- **THEN** node counts match the canonical values (depth 1 = 20, depth 2 = 400, depth 3 = 8902, depth 4 = 197281 — the depth-4 count is the release gate)

### Requirement: Game State Detection
The library MUST detect check, checkmate, and stalemate from native state (`in_check` plus a count-only legal-move query against a null buffer — zero-alloc, no move materialization).

#### Scenario: Check detection
- **GIVEN** a position where the side to move is in check
- **WHEN** `isCheck` is read
- **THEN** it returns `true`

#### Scenario: Checkmate detection
- **GIVEN** a checkmate position (e.g. scholar's mate / fool's mate)
- **WHEN** it is inspected
- **THEN** `isCheckmate` returns `true`
- **THEN** legal move enumeration yields zero moves

#### Scenario: Stalemate detection
- **GIVEN** a position where the side to move has no legal moves but is not in check
- **WHEN** it is inspected
- **THEN** `isStalemate` returns `true`

### Requirement: API Documentation
All public API in this capability SHALL carry Swift DocC documentation, and every engine type SHALL be a struct or enum — never a class.

#### Scenario: DocC coverage
- **GIVEN** the public API surface of this capability (`Move`, `Promotion`, `Undo`, `isLegal`, `play`, `makeMoveUnchecked`, `unmake`, `withLegalMoves`, `legalMoves`, `perft`, `isCheck`, `isCheckmate`, `isStalemate`)
- **WHEN** it is inspected
- **THEN** every public type, method, property, and enum case carries `///` documentation

#### Scenario: Value types only
- **GIVEN** the engine types (`Move`, `Undo`)
- **WHEN** they are inspected
- **THEN** each is a struct; the `Undo` storage is an opaque fixed-size value with no API surface beyond the make/unmake pairing
