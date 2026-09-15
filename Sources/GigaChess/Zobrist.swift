// Zobrist.swift — UInt64 Polyglot key access (by value, no allocation).
// Keys equal Rust and TypeScript `gigachess` keys for the same positions
// (shared Polyglot tables): the primitive behind repertoire trees,
// transposition caches, and GigaBase indexing.
//
// SPDX-License-Identifier: MIT
import CGigaChessFFI

extension Board {
    /// Current incrementally-maintained Polyglot Zobrist key.
    /// Single FFI call returning a value type — safe in search hot loops.
    /// Make/unmake restores the key bit-exactly.
    public var zobrist: UInt64 {
        storage.withGigaBoard { gigachess_board_zobrist($0) }
    }
}
