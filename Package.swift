// swift-tools-version: 6.0
// GigaChess — thin Swift wrapper over the native `gigachess` Rust engine (v0.1.2).
// SPDX-License-Identifier: MIT
import PackageDescription

// Engine pin (must match scripts/build-xcframework.sh GIGACHESS_VERSION).
let gigachessVersion = "0.1.2"
let ffiReleaseTag = "gigachess-ffi-0.1.2-1"
// Checksum of CGigaChessFFI.xcframework.zip attached to the Release below
// (first published from CI run 35036281698). Refresh from
// scripts/build-xcframework.sh output whenever the pin changes.
let ffiChecksum = "197f79eb9fa4e8c6b847917f572c03a15ee82f4ffe649d7d6500561e06323f85"

let package = Package(
    name: "GigaChess",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "GigaChess", targets: ["GigaChess"]),
    ],
    targets: [
        // Prebuilt Rust staticlib (Release asset; consumers need no Rust toolchain).
        // Local dev: `scripts/build-xcframework.sh` drops the built XCFramework
        // into Frameworks/ and zips it for upload. CI downloads via this URL.
        .binaryTarget(
            name: "CGigaChessFFI",
            url: "https://github.com/itshak/swift-gigachess/releases/download/\(ffiReleaseTag)/CGigaChessFFI.xcframework.zip",
            checksum: ffiChecksum
        ),
        // Pure Swift wrapper: value types only, Swift 6 strict concurrency clean.
        .target(
            name: "GigaChess",
            dependencies: ["CGigaChessFFI"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "GigaChessTests",
            dependencies: ["GigaChess"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
