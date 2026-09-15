## Purpose
Legal move generation, move application, and game state detection for chess positions.

## ADDED Requirements

### Requirement: Legal Move Generation
The library MUST generate all legal moves for the current position.

#### Scenario: Starting position
- **WHEN** legal moves are requested for the starting position
- **THEN** exactly 20 moves are returned

#### Scenario: Move representation
- **WHEN** a legal move is returned
- **THEN** it is a value type (`struct Move`) containing source square, destination square, and optional promotion piece
- **THEN** moves are `Hashable`, `Equatable`, and `Sendable`

### Requirement: Move Application
The library MUST support applying moves to mutate the position.

#### Scenario: Apply legal move
- **WHEN** a legal move is applied to a position
- **THEN** the position is updated to reflect the move
- **THEN** the method returns `true`

#### Scenario: Apply illegal move
- **WHEN** an illegal move is applied to a position
- **THEN** the position is unchanged
- **THEN** the method returns `false`

### Requirement: Game State Detection
The library MUST detect check, checkmate, and stalemate.

#### Scenario: Check detection
- **WHEN** the current side's king is in check
- **THEN** `isCheck` returns `true`

#### Scenario: Checkmate detection
- **WHEN** the current side is in checkmate
- **THEN** `isCheckmate` returns `true`
- **THEN** `legalMoves()` returns an empty array

#### Scenario: Stalemate detection
- **WHEN** the current side has no legal moves but is not in check
- **THEN** `isStalemate` returns `true`
