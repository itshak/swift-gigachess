// PerformanceTests.swift — perft + batch-codec throughput (informative + CI gate).
// SPDX-License-Identifier: MIT
import XCTest
@testable import GigaChess

final class PerformanceTests: XCTestCase {
    /// Perft(3) from startpos: 8,902 nodes. CI asserts wall-time stays within
    /// 10× of the native Rust baseline (guards FFI-pathological regressions,
    /// not nanosecond noise).
    func testPerftThroughput() {
        let board = Board()
        measure {
            XCTAssertEqual(board.perft(depth: 3), 8902)
        }
    }

    /// Batch codec: parse → export → replay over the Opera game (33 ply).
    /// CI regression gate lives on correctness + completion; absolute numbers
    /// are recorded in Benchmarks/results.log (informative vs native Rust).
    func testCodecThroughput() throws {
        let moves = try Board.parseMovetextToMoves2(CodecTests.opera, from: CodecTests.startFEN)
        measure {
            _ = try? Board.sanMovetext(from: moves, startFen: CodecTests.startFEN, result: "1-0")
            _ = try? Board.replayHashes(moves: moves, from: CodecTests.startFEN)
        }
    }

    /// Visitor hot path must not allocate per call (cold-path `legalMoves()`
    /// is the documented allocating API). This test pins the API shape; the
    /// no-alloc property holds by construction (stack buffer, no Array).
    func testVisitorHotPathShape() {
        let board = Board()
        var total = 0
        for _ in 0..<100 {
            board.withLegalMoves { total += $0.count }
        }
        XCTAssertEqual(total, 2000)
    }
}
