## Purpose
Lifecycle management of chess positions: creation, querying, mutation, and memory-safe cleanup across the Rust↔Swift FFI boundary.

## ADDED Requirements

### Requirement: Position Creation
The library MUST support creating positions from a FEN string and from the standard starting position.

#### Scenario: Create starting position
- **WHEN** a `Position` is created with no arguments
- **THEN** the position represents the standard chess starting position (FEN: `rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1`)

#### Scenario: Create from FEN
- **WHEN** a `Position` is created with a valid FEN string
- **THEN** the position represents the board state described by that FEN

#### Scenario: Invalid FEN
- **WHEN** a `Position` is created with an invalid FEN string
- **THEN** the initializer returns `nil` (failable init)

### Requirement: Memory Safety
The Rust-allocated position MUST be freed when the Swift `Position` object is deallocated.

#### Scenario: Automatic cleanup
- **WHEN** a `Position` object goes out of scope and is deallocated
- **THEN** the underlying Rust `ChessPosition` is freed via the FFI free function
- **THEN** no memory is leaked

### Requirement: Thread Safety
The `Position` type MUST declare `Sendable` conformance with documented thread-safety semantics.

#### Scenario: Concurrent access
- **WHEN** a `Position` is accessed from multiple Swift concurrency contexts
- **THEN** the behavior is well-defined (either safe or documented as requiring external synchronization)
