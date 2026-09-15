// Undo.swift — opaque make/unmake token (fixed-size bytes).
// Only meaningful paired with the move that produced it. Value type, Sendable.
//
// SPDX-License-Identifier: MIT
import CGigaChessFFI

extension GigaUndo: Sendable {}
extension GigaBoard: Sendable {}

/// Opaque token returned by play/make, consumed by unmake.
public struct Undo: Sendable {
    var storage: GigaUndo

    init(storage: GigaUndo) {
        self.storage = storage
    }
}

extension GigaBoard {
    /// Zero-initialized board storage (overwritten by every FFI constructor).
    static func zeroed() -> GigaBoard {
        // Bypass the 144-element tuple initializer via raw memory.
        let ptr = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<GigaBoard>.size,
            alignment: MemoryLayout<GigaBoard>.alignment
        )
        defer { ptr.deallocate() }
        ptr.initializeMemory(as: UInt8.self, repeating: 0, count: MemoryLayout<GigaBoard>.size)
        return ptr.load(as: GigaBoard.self)
    }
}

extension GigaUndo {
    static func zeroed() -> GigaUndo {
        let ptr = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<GigaUndo>.size,
            alignment: MemoryLayout<GigaUndo>.alignment
        )
        defer { ptr.deallocate() }
        ptr.initializeMemory(as: UInt8.self, repeating: 0, count: MemoryLayout<GigaUndo>.size)
        return ptr.load(as: GigaUndo.self)
    }
}
