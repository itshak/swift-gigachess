// Undo.swift — opaque make/unmake token (fixed-size bytes).
// Only meaningful paired with the move that produced it. Value type, Sendable.
//
// Storage is a Swift-owned struct (3 × UInt64, layout-identical to `GigaUndo`),
// bridged to C via scoped rebinding — so `Sendable` holds by checking, with
// no `@unchecked` or retroactive conformance on imported C types.
//
// SPDX-License-Identifier: MIT
import CGigaChessFFI

/// Swift-owned 24-byte undo storage, layout-identical to `GigaUndo`.
struct UndoStorage: Sendable {
    var w0: UInt64 = 0
    var w1: UInt64 = 0
    var w2: UInt64 = 0

    /// Scoped read-only access as `GigaUndo`.
    func withGigaUndo<R>(_ body: (UnsafePointer<GigaUndo>) throws -> R) rethrows -> R {
        try withUnsafePointer(to: self) {
            try $0.withMemoryRebound(to: GigaUndo.self, capacity: 1, body)
        }
    }

    /// Scoped mutable access as `GigaUndo`.
    mutating func withMutableGigaUndo<R>(_ body: (UnsafeMutablePointer<GigaUndo>) throws -> R) rethrows -> R {
        try withUnsafeMutablePointer(to: &self) {
            try $0.withMemoryRebound(to: GigaUndo.self, capacity: 1, body)
        }
    }
}

/// Opaque token returned by play/make, consumed by unmake.
public struct Undo: Sendable {
    var storage: UndoStorage

    init(storage: UndoStorage) {
        self.storage = storage
    }
}
