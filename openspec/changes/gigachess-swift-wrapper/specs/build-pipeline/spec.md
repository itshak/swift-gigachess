## Purpose
Cross-compilation of the Rust chess engine for Apple platforms and packaging as an SPM-compatible XCFramework distributed via GitHub Release asset, with CI guarding version sync and struct-layout drift.

## ADDED Requirements

### Requirement: Apple Target Support
The build pipeline MUST produce static libraries for iOS device (arm64), iOS Simulator (arm64), and macOS (arm64).

#### Scenario: Build all targets
- **WHEN** the build script is executed
- **THEN** static libraries are produced for `aarch64-apple-ios`, `aarch64-apple-ios-sim`, and `aarch64-apple-darwin`
- **THEN** the pinned `gigachess` version/hash recorded in `scripts/build-xcframework.sh` is the exact source compiled

### Requirement: XCFramework Packaging and Distribution
The build pipeline MUST produce an XCFramework containing all target architectures and the C bridging headers, published as a versioned GitHub Release asset (NOT committed to the repo).

#### Scenario: Create XCFramework
- **WHEN** the static libraries are built
- **THEN** an XCFramework is created containing all architectures and headers
- **THEN** it is uploaded to a GitHub Release and referenced from SPM `binaryTarget` by URL + checksum

### Requirement: SPM Integration
The package MUST be consumable via Swift Package Manager using a Git URL, with no Rust toolchain required on the consumer side.

#### Scenario: Add as dependency
- **WHEN** a consumer adds the package URL to their `Package.swift`
- **THEN** SPM resolves the package, downloads the XCFramework asset, links the binary target, and makes `import GigaChess` available

### Requirement: Version-Sync and Layout-Drift CI
CI MUST fail when the Swift wrapper drifts from the pinned engine: struct size/offset asserts (`BOARD_SIZE`), perft parity spot-checks, and FFI symbol presence checks run on every build.

#### Scenario: Engine bump without wrapper update
- **WHEN** the pinned `gigachess` version changes the `Board` layout or FFI surface
- **THEN** CI fails with the exact mismatch (size, offset, or missing symbol) until the wrapper and headers are updated together

### Requirement: Panic Safety Verification
Every `extern "C"` entry point MUST convert Rust panics to error codes via `catch_unwind` (the engine profile uses `panic = "abort"`).

#### Scenario: Adversarial inputs
- **WHEN** garbage FEN, truncated buffers, or out-of-range words are fed to every entry point
- **THEN** all calls return errors — none trap, abort, or corrupt memory
