// San.swift — SAN render/parse over the native `san` module.
// Strings cross FFI into caller-owned buffers only (SAN ≤ 12B + NUL).
//
// SPDX-License-Identifier: MIT
import CGigaChessFFI

extension Board {
    /// Render a legal move in canonical SAN (disambiguation, check/mate
    /// suffixes, letter-O castling). Throws `.illegalMove` for illegal input.
    public func san(for move: Move) throws -> String {
        var copy = storage
        return try withUnsafeTemporaryAllocation(of: CChar.self, capacity: 32) { buf in
            guard let base = buf.baseAddress else { throw GigaChessError.enginePanicked }
            var outLen = 0
            let status = gigachess_board_move_to_san(&copy, move.word, base, buf.count, &outLen)
            if let err = GigaChessError.fromStatus(status) { throw err }
            return String(cString: base)
        }
    }

    /// Parse a SAN token against this position. Accepts both `O-O` and `0-0`
    /// castling spellings (plus `+`/`#`/`!`/`?` suffixes, `=Q` promotion).
    public func move(fromSan san: String) throws -> Move {
        var copy = storage
        var word: UInt16 = 0
        let status: Int32 = san.withCString { sanPtr in
            gigachess_board_san_to_move(&copy, sanPtr, &word)
        }
        if let err = GigaChessError.fromStatus(status, token: san) { throw err }
        return Move(word: word)
    }

    /// Play a sequence of SAN tokens, returning one Undo per ply.
    /// Throws `.codecFailed(ply:)` identifying the first bad token.
    @discardableResult
    public mutating func playSan(_ sans: [String]) throws -> [Undo] {
        var undos: [Undo] = []
        undos.reserveCapacity(sans.count)
        for (ply, token) in sans.enumerated() {
            do {
                let mv = try move(fromSan: token)
                undos.append(try play(mv))
            } catch {
                throw GigaChessError.codecFailed(ply: ply)
            }
        }
        return undos
    }

    /// Play a variadic SAN sequence (e.g. `try board.playSan("e4", "e5")`).
    @discardableResult
    public mutating func playSan(_ sans: String...) throws -> [Undo] {
        try playSan(sans)
    }
}

extension Move {
    /// Parse a SAN token against a board (`Move(parsing: "Nf3", on: board)`).
    public init(parsing san: String, on board: Board) throws {
        self = try board.move(fromSan: san)
    }
}
