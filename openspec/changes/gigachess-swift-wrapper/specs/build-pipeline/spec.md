## Purpose
Cross-compilation of the Rust chess engine for Apple platforms and packaging as an SPM-compatible XCFramework.

## ADDED Requirements

### Requirement: Apple Target Support
The build pipeline MUST produce static libraries for iOS device (arm64), iOS Simulator (arm64), and macOS (arm64).

#### Scenario: Build all targets
- **WHEN** the build script is executed
- **THEN** static libraries are produced for `aarch64-apple-ios`, `aarch64-apple-ios-sim`, and `aarch64-apple-darwin`

### Requirement: XCFramework Packaging
The build pipeline MUST produce an XCFramework containing all target architectures.

#### Scenario: Create XCFramework
- **WHEN** the static libraries are built
- **THEN** an XCFramework is created containing all architectures and the C bridging headers
- **THEN** the XCFramework is usable as an SPM `binaryTarget`

### Requirement: SPM Integration
The package MUST be consumable via Swift Package Manager using a Git URL.

#### Scenario: Add as dependency
- **WHEN** a consumer adds the package URL to their `Package.swift`
- **THEN** SPM resolves the package, links the binary target, and makes `import GigaChess` available
