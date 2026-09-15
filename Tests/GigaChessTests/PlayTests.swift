// PlayTests.swift — play/unmake, legality, mate/stalemate.
// SPDX-License-Identifier: MIT
import XCTest
@testable import GigaChess

final class PlayTests: XCTestCase {
    func testPlayUnmakeBitIdentityIncludingHash() throws {
        var board = Board()
        let before = board
        let beforeHash = board.zobrist
        let e2e4 = Move(from: 12, to: 28)
        let undo = try board.play(e2e4)
        XCTAssertNotEqual(board, before)
        XCTAssertNotEqual(board.zobrist, beforeHash)
        board.unmake(e2e4, undo: undo)
        XCTAssertEqual(board, before)
        XCTAssertEqual(board.zobrist, beforeHash)
        XCTAssertEqual(try board.fen(), BoardTests.startposFEN)
    }

    func testMakeUnmakeUncheckedRoundTrip() throws {
        var board = try Board(fen: "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3")
        let before = board
        let moves = board.legalMoves()
        XCTAssertFalse(moves.isEmpty)
        for mv in moves.prefix(8) {
            let undo = board.makeMoveUnchecked(mv)
            board.unmake(mv, undo: undo)
            XCTAssertEqual(board, before, "unmake failed for \(mv.uci)")
        }
    }

    func testIllegalMoveThrowsAndBoardUnchanged() throws {
        var board = Board()
        let before = board
        // e2e5 is not a legal pawn move from startpos.
        let illegal = Move(from: 12, to: 36)
        XCTAssertFalse(board.isLegal(illegal))
        XCTAssertThrowsError(try board.play(illegal)) { error in
            XCTAssertEqual(error as? GigaChessError, GigaChessError.illegalMove)
        }
        XCTAssertEqual(board, before)
        // Queen d1h6 blocked from startpos.
        XCTAssertFalse(board.isLegal(Move(from: 3, to: 47)))
    }

    func testScholarsMateIsCheckmate() throws {
        var board = Board()
        // 1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7#
        try board.playSan("e4", "e5", "Qh5", "Nc6", "Bc4", "Nf6", "Qxf7")
        XCTAssertTrue(board.isCheck)
        XCTAssertTrue(board.isCheckmate)
        XCTAssertFalse(board.isStalemate)
        XCTAssertEqual(board.legalMoves().count, 0)
    }

    func testFoolsMateIsCheckmate() throws {
        var board = Board()
        // 1. f3 e5 2. g4 Qh4#
        try board.playSan("f3", "e5", "g4", "Qh4")
        XCTAssertTrue(board.isCheckmate)
    }

    func testStalemateFixture() throws {
        let board = try Board(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
        XCTAssertFalse(board.isCheck)
        XCTAssertTrue(board.isStalemate)
        XCTAssertFalse(board.isCheckmate)
        XCTAssertEqual(board.legalMoves().count, 0)
    }

    func testVisitorMatchesConvenience() {
        let board = Board()
        let cold = board.legalMoves().map(\.word).sorted()
        let hot: [UInt16] = board.withLegalMoves { buf in buf.map(\.word).sorted() }
        XCTAssertEqual(hot, cold)
    }
}
