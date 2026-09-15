# Build Pipeline Specification

## Purpose
Cross-compilation of the Rust chess engine for Apple platforms and packaging as an SPM-compatible XCFramework distributed via GitHub Release asset, with CI guarding version sync and struct-layout drift.

## Requirements

### Requirement: Apple Target Support
The build pipeline MUST produce static libraries for iOS device (arm64), iOS Simulator (arm64), and macOS (arm64).

#### Scenario: Build all targets
- **GIVEN** a macOS host with the Rust toolchain and Xcode
- **WHEN** the build script is executed
- **THEN** static libraries are produced for `aarch64-apple-ios`, `aarch64-apple-ios-sim`, and `aarch64-apple-darwin`
- **THEN** the pinned `gigachess` version/hash recorded in `scripts/build-xcframework.sh` is the exact source compiled

#### Scenario: Non-macOS host
- **GIVEN** a host without `xcodebuild`
- **WHEN** the build script is executed
- **THEN** only the host `staticlib` is built for layout checks; cross-compilation and XCFramework assembly are skipped with an explanatory note

### Requirement: XCFramework Packaging and Distribution
The build pipeline MUST produce an XCFramework containing all target architectures and the C bridging headers, published as a versioned GitHub Release asset (NOT committed to the repo).

#### Scenario: Create XCFramework
- **GIVEN** built static libraries for all targets
- **WHEN** packaging runs
- **THEN** an XCFramework is created containing all architectures and headers
- **THEN** it is uploaded to a GitHub Release and referenced from SPM `binaryTarget` by URL + checksum
- **THEN** the script prints the zip checksum plus Release-tag upload instructions for `Package.swift`

#### Scenario: Bootstrap before first publish
- **GIVEN** a `Package.swift` still carrying the zero placeholder checksum (Release asset unpublished, so URL resolution 404s)
- **WHEN** CI builds
- **THEN** the `CGigaChessFFI` binary target is swapped to the locally-built `Frameworks/CGigaChessFFI.xcframework` path for that job only (`scripts/use-local-xcframework.sh`), so `swift build`/`swift test` exercise the freshly built artifact

#### Scenario: First publish fills the checksum
- **GIVEN** an XCFramework zip uploaded to its Release tag for the first time
- **WHEN** publishing completes
- **THEN** the zero placeholder checksum in `Package.swift` is replaced with the script-printed checksum
- **THEN** subsequent jobs keep the URL target and verify the exact consumer resolution path (the bootstrap swap becomes a no-op)

### Requirement: SPM Integration
The package MUST be consumable via Swift Package Manager using a Git URL, with no Rust toolchain required on the consumer side.

#### Scenario: Add as dependency
- **GIVEN** a consumer package
- **WHEN** the consumer adds the package URL to their `Package.swift`
- **THEN** SPM resolves the package, downloads the XCFramework asset, links the binary target, and makes `import GigaChess` available

### Requirement: Version-Sync and Layout-Drift CI
CI MUST fail when the Swift wrapper drifts from the pinned engine: `BOARD_SIZE`/`UNDO_SIZE` size asserts (field offsets are inapplicable — the board crosses as opaque bytes), header↔Rust FFI symbol 1:1 checks, perft/Zobrist pin checks in the Rust tests, and pin-consistency checks across `scripts/build-xcframework.sh`, `Package.swift`, and `rust/Cargo.toml` run on every build.

#### Scenario: Engine bump without wrapper update
- **GIVEN** a pinned `gigachess` version that changes the `Board` layout or FFI surface
- **WHEN** CI builds without a matching wrapper update
- **THEN** CI fails with the exact mismatch (size, missing symbol, perft/key deviation, or pin inconsistency) until the wrapper and headers are updated together

### Requirement: Panic Safety Verification
Every `extern "C"` entry point MUST convert Rust panics to error codes via `catch_unwind` (the engine profile uses `panic = "abort"`).

#### Scenario: Adversarial inputs
- **GIVEN** garbage FEN, truncated buffers, null pointers, or out-of-range words/squares fed across lifecycle, movegen, SAN, and codec entries
- **WHEN** they are processed
- **THEN** all calls return errors — none trap, abort, or corrupt memory
