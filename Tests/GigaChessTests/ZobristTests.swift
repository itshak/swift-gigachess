// ZobristTests.swift — Polyglot key stability, evolution, cross-language equality.
// SPDX-License-Identifier: MIT
import XCTest
@testable import GigaChess

final class ZobristTests: XCTestCase {
    /// Recorded Rust startpos key for gigachess 0.1.2 (see rust/tests + CI).
    static let expectedStartposKey: UInt64 = 0x463b96181691fc9c

    func testStartposKeyEqualsRecordedRustKey() {
        XCTAssertEqual(Board().zobrist, Self.expectedStartposKey)
        XCTAssertEqual(Board.startpos().zobrist, Self.expectedStartposKey)
    }

    func testKeyStability() {
        let board = Board()
        XCTAssertEqual(board.zobrist, board.zobrist)
    }

    func testMakeUnmakeKeyRestoration() throws {
        var board = Board()
        let before = board.zobrist
        let mv = Move(from: 12, to: 28)
        let undo = try board.play(mv)
        XCTAssertNotEqual(board.zobrist, before)
        board.unmake(mv, undo: undo)
        XCTAssertEqual(board.zobrist, before)
    }

    func testKeyEvolutionAcrossGame() throws {
        var board = Board()
        var seen = Set<UInt64>([board.zobrist])
        for san in ["e4", "e5", "Nf3", "Nc6"] {
            _ = try board.play(board.move(fromSan: san))
            XCTAssertFalse(seen.contains(board.zobrist), "hash collision at \(san)")
            seen.insert(board.zobrist)
        }
    }
}
