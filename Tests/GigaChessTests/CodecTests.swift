// CodecTests.swift — movetext ↔ moves2, replay hashes, illegal-ply reporting.
// SPDX-License-Identifier: MIT
import XCTest
@testable import GigaChess

final class CodecTests: XCTestCase {
    static let startFEN = BoardTests.startposFEN
    static let opera = "1. e4 e5 2. Nf3 d6 3. d4 Bg4 4. dxe5 Bxf3 5. Qxf3 dxe5 6. Bc4 Nf6 7. Qb3 Qe7 8. Nc3 c6 9. Bg5 b5 10. Nxb5 cxb5 11. Bxb5+ Nbd7 12. O-O-O Rd8 13. Rxd7 Rxd7 14. Rd1 Qe6 15. Bxd7+ Nxd7 16. Qb8+ Nxb8 17. Rd8# 1-0"

    func testParseGame() throws {
        let moves = try Board.parseMovetextToMoves2(Self.opera, from: Self.startFEN)
        XCTAssertEqual(moves.count, 33)
    }

    func testExportRoundTrip() throws {
        let moves = try Board.parseMovetextToMoves2(Self.opera, from: Self.startFEN)
        let rendered = try Board.sanMovetext(from: moves, startFen: Self.startFEN, result: "1-0")
        XCTAssertTrue(rendered.hasPrefix("1. e4 e5 2. Nf3 d6"))
        XCTAssertTrue(rendered.hasSuffix("Rd8# 1-0"))
        let reparsed = try Board.parseMovetextToMoves2(rendered, from: Self.startFEN)
        XCTAssertEqual(reparsed, moves)
    }

    func testReplayHashesEqualSteppedHashes() throws {
        let moves = try Board.parseMovetextToMoves2(Self.opera, from: Self.startFEN)
        let hashes = try Board.replayHashes(moves: moves, from: Self.startFEN)
        XCTAssertEqual(hashes.count, moves.count + 1)
        // Step a board through the same moves and compare.
        var board = Board()
        XCTAssertEqual(hashes[0], board.zobrist)
        for (i, mv) in moves.enumerated() {
            _ = try board.play(mv)
            XCTAssertEqual(hashes[i + 1], board.zobrist, "hash mismatch at ply \(i)")
        }
    }

    func testIllegalPlyReporting() {
        // Qh6 on move 2 is illegal from startpos (ply 1: e4 ok, ply 1 fails on Qh6? tokens: e4(0) Qh6(1)).
        XCTAssertThrowsError(try Board.parseMovetextToMoves2("e4 Qh6", from: Self.startFEN)) { error in
            XCTAssertEqual(error as? GigaChessError, GigaChessError.codecFailed(ply: 1))
        }
        // Replay with an illegal word reports its ply.
        let e2e4 = Move(from: 12, to: 28)
        let illegal = Move(from: 3, to: 47) // d1h6 blocked
        XCTAssertThrowsError(try Board.replayHashes(moves: [e2e4, illegal], from: Self.startFEN)) { error in
            guard case GigaChessError.codecFailed(let ply) = error else {
                return XCTFail("expected codecFailed, got \(error)")
            }
            XCTAssertEqual(ply, 1)
        }
    }

    func testEmptyMovetext() throws {
        let moves = try Board.parseMovetextToMoves2("", from: Self.startFEN)
        XCTAssertEqual(moves.count, 0)
        let hashes = try Board.replayHashes(moves: [], from: Self.startFEN)
        XCTAssertEqual(hashes, [Board().zobrist])
    }
}
