// Moves2Codec.swift — batch movetext ↔ moves2 conversion and hash-stream replay.
// Mirrors native `database` + `replay` over contiguous buffers with flat
// outcomes: no Vec/String/HashMap crosses FFI; Swift owns all buffers.
// One FFI call per game (not per move) — the batch-search throughput story.
//
// SPDX-License-Identifier: MIT
import CGigaChessFFI

extension Board {
    // MARK: - Movetext → moves2

    /// Parse SAN movetext into packed moves2 words, starting from `startFen`.
    /// Skips move numbers, comments, NAGs, variations, and result tokens.
    /// Throws `.codecFailed(ply:)` at the first illegal/unparseable token,
    /// or `.invalidFen` for a bad start position.
    public static func parseMovetextToMoves2(_ movetext: String, from startFen: String) throws -> [Move] {
        try startFen.withCString { fenPtr in
            try movetext.withCString { textPtr in
                // Single-game movetext is small; 4K words covers ~2000-ply games.
                let cap = 4096
                return try withUnsafeTemporaryAllocation(of: UInt16.self, capacity: cap) { buf in
                    guard let base = buf.baseAddress else { throw GigaChessError.enginePanicked }
                    var count = 0
                    var failPly = 0
                    let status = gigachess_parse_movetext_to_moves2(
                        fenPtr, textPtr, base, buf.count, &count, &failPly
                    )
                    if status == GIGA_E_BUFFER_TOO_SMALL {
                        // Fall back to a heap buffer twice as large (cold path).
                        var big = [UInt16](repeating: 0, count: cap * 4)
                        var bigCount = 0
                        var bigFail = 0
                        let bigStatus: Int32 = big.withUnsafeMutableBufferPointer { bigBuf in
                            gigachess_parse_movetext_to_moves2(
                                fenPtr, textPtr, bigBuf.baseAddress, bigBuf.count,
                                &bigCount, &bigFail
                            )
                        }
                        if let err = GigaChessError.fromStatus(bigStatus, ply: bigFail) { throw err }
                        return (0..<bigCount).map { Move(word: big[$0]) }
                    }
                    if let err = GigaChessError.fromStatus(status, ply: failPly) { throw err }
                    return (0..<count).map { Move(word: base[$0]) }
                }
            }
        }
    }

    // MARK: - moves2 → SAN movetext

    /// Convert moves2 words back to SAN movetext with move numbers plus an
    /// optional trailing result token (e.g. "1-0"). Throws `.codecFailed(ply:)`
    /// at the first illegal word.
    public static func sanMovetext(from moves: [Move], startFen: String, result: String = "") throws -> String {
        try startFen.withCString { fenPtr in
            try result.withCString { resultPtr in
                if moves.isEmpty {
                    return try withUnsafeTemporaryAllocation(of: CChar.self, capacity: 32768) { out in
                        guard let outBase = out.baseAddress else { throw GigaChessError.enginePanicked }
                        var outLen = 0
                        var failPly = 0
                        let status = gigachess_moves2_to_san_movetext(
                            fenPtr, nil, 0, resultPtr,
                            outBase, out.count, &outLen, &failPly
                        )
                        if let err = GigaChessError.fromStatus(status, ply: failPly) { throw err }
                        return String(cString: outBase)
                    }
                }
                return try moves.withUnsafeBufferPointer { moveBuf in
                    guard let base = moveBuf.baseAddress else { throw GigaChessError.enginePanicked }
                    return try base.withMemoryRebound(to: UInt16.self, capacity: moveBuf.count) { words in
                        try withUnsafeTemporaryAllocation(of: CChar.self, capacity: 32768) { out in
                            guard let outBase = out.baseAddress else { throw GigaChessError.enginePanicked }
                            var outLen = 0
                            var failPly = 0
                            let status = gigachess_moves2_to_san_movetext(
                                fenPtr, words, moveBuf.count, resultPtr,
                                outBase, out.count, &outLen, &failPly
                            )
                            if let err = GigaChessError.fromStatus(status, ply: failPly) { throw err }
                            return String(cString: outBase)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Hash-stream replay

    /// Replay a moves2 stream to Zobrist hashes, starting from `startFen`.
    /// Returns `moves.count + 1` hashes (start position first); each entry
    /// equals stepping a `Board` through the same moves. Throws
    /// `.codecFailed(ply:)` at the first illegal word.
    public static func replayHashes(moves: [Move], from startFen: String) throws -> [UInt64] {
        try startFen.withCString { fenPtr in
            if moves.isEmpty {
                // Zero moves: hash of the start position alone.
                let board = try Board(fen: startFen)
                return [board.zobrist]
            }
            return try moves.withUnsafeBufferPointer { moveBuf in
                guard let base = moveBuf.baseAddress else { throw GigaChessError.enginePanicked }
                return try base.withMemoryRebound(to: UInt16.self, capacity: moveBuf.count) { words in
                    let need = moveBuf.count + 1
                    return try withUnsafeTemporaryAllocation(of: UInt64.self, capacity: need) { out in
                        guard let outBase = out.baseAddress else { throw GigaChessError.enginePanicked }
                        var count = 0
                        var failPly = 0
                        let status = gigachess_replay_moves2_stream(
                            fenPtr, words, moveBuf.count, outBase, out.count,
                            &count, &failPly
                        )
                        if let err = GigaChessError.fromStatus(status, ply: failPly) { throw err }
                        return (0..<count).map { outBase[$0] }
                    }
                }
            }
        }
    }

    /// Replay from this board's current position (uses its FEN as the start).
    public func replayHashes(moves: [Move]) throws -> [UInt64] {
        try Board.replayHashes(moves: moves, from: try fen())
    }
}
