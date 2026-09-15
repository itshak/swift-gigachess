// PerftTests.swift — canonical node counts (release gate).
// SPDX-License-Identifier: MIT
import XCTest
@testable import GigaChess

final class PerftTests: XCTestCase {
    func testStartposPerftDepths1To3() {
        let board = Board()
        XCTAssertEqual(board.perft(depth: 1), 20)
        XCTAssertEqual(board.perft(depth: 2), 400)
        XCTAssertEqual(board.perft(depth: 3), 8902)
    }

    func testStartposPerftDepth4() {
        // Release gate: full parity with native Rust perft.
        XCTAssertEqual(Board().perft(depth: 4), 197_281)
    }
}
