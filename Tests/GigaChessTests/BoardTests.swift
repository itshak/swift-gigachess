// BoardTests.swift — position lifecycle, value semantics, queries.
// SPDX-License-Identifier: MIT
import XCTest
@testable import GigaChess

final class BoardTests: XCTestCase {
    static let startposFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    func testStartposFEN() throws {
        let board = Board()
        XCTAssertEqual(try board.fen(), Self.startposFEN)
        XCTAssertEqual(try Board(fen: Self.startposFEN).fen(), Self.startposFEN)
        XCTAssertEqual(Board.startpos(), Board())
    }

    func testEmptyBoard() throws {
        let board = Board.empty()
        XCTAssertEqual(board.turn, .white)
        XCTAssertEqual(board.castlingRights, 0)
        XCTAssertNil(board.enPassant)
        // No pieces anywhere.
        for sq: UInt8 in 0..<64 {
            XCTAssertNil(board.piece(at: sq), "expected empty at \(sq)")
        }
    }

    func testFENRoundTripsIncludingEPNormalization() throws {
        // Standard positions round-trip canonically.
        let fens = [
            Self.startposFEN,
            "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
            "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3",
            "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1",
        ]
        for fen in fens {
            XCTAssertEqual(try Board(fen: fen).fen(), fen, "round-trip failed for \(fen)")
        }
    }

    func testInvalidFENThrows() {
        XCTAssertThrowsError(try Board(fen: "not a fen")) { error in
            guard case GigaChessError.invalidFen = error else {
                return XCTFail("expected invalidFen, got \(error)")
            }
        }
        XCTAssertThrowsError(try Board(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 0")) // fullmove 0
    }

    func testCopyIndependence() throws {
        var original = Board()
        var copy = original // bit-for-bit snapshot
        let e2e4 = Move(from: 12, to: 28)
        _ = try copy.play(e2e4)
        // Original unchanged.
        XCTAssertEqual(try original.fen(), Self.startposFEN)
        XCTAssertNotEqual(try copy.fen(), try original.fen())
        XCTAssertEqual(original, Board())
    }

    func testQueries() throws {
        var board = Board()
        XCTAssertEqual(board.turn, .white)
        // e2 pawn, e1 king.
        XCTAssertEqual(board.piece(at: 12), Piece(color: .white, role: .pawn))
        XCTAssertEqual(board.piece(at: 4), Piece(color: .white, role: .king))
        XCTAssertEqual(board.kingSquare(.white), 4)
        XCTAssertEqual(board.kingSquare(.black), 60)
        XCTAssertEqual(board.castlingRights, 0b1111)
        XCTAssertNil(board.enPassant)
        XCTAssertEqual(board.halfmoveClock, 0)
        XCTAssertEqual(board.fullmoveNumber, 1)
        // After 1. e4: EP square e3 (20), clocks updated, turn black.
        _ = try board.play(Move(from: 12, to: 28))
        XCTAssertEqual(board.turn, .black)
        XCTAssertEqual(board.enPassant, 20)
        XCTAssertEqual(try board.fen(), "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1")
    }
}
