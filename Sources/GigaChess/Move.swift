// Move.swift — packed UInt16 move (Move2 wire format).
// Bit-identical to Rust `Move(u16)`: word = from | (to << 6) | (promo << 12),
// promo 0 = none, 1 = N, 2 = B, 3 = R, 4 = Q. Castling stays king-captures-rook
// (e1h1, e1a1, e8h8, e8a8) verbatim across Swift ↔ Rust ↔ gigaboard.
//
// SPDX-License-Identifier: MIT
import CGigaChessFFI

/// Promotion piece (moves2 promo nibble).
public enum Promotion: UInt16, Sendable, Hashable, CustomStringConvertible {
    /// Knight (promo 1).
    case knight = 1
    /// Bishop (promo 2).
    case bishop = 2
    /// Rook (promo 3).
    case rook = 3
    /// Queen (promo 4).
    case queen = 4

    /// Lowercase UCI promotion letter.
    public var description: String {
        switch self {
        case .knight: return "n"
        case .bishop: return "b"
        case .rook: return "r"
        case .queen: return "q"
        }
    }

    /// Uppercase SAN/FEN letter.
    public var letter: Character {
        switch self {
        case .knight: return "N"
        case .bishop: return "B"
        case .rook: return "R"
        case .queen: return "Q"
        }
    }
}

/// A chess move packed into 16 bits (moves2 wire format).
public struct Move: Hashable, Equatable, Sendable, CustomStringConvertible {
    /// Raw 16-bit word.
    public let word: UInt16

    /// Wrap a raw word (e.g. decoded from a moves2 blob).
    @inline(__always)
    public init(word: UInt16) {
        self.word = word
    }

    /// Pack from origin/destination squares (0 = a1 … 63 = h8) plus promotion.
    @inline(__always)
    public init(from: UInt8, to: UInt8, promotion: Promotion? = nil) {
        precondition(from < 64 && to < 64, "square out of range")
        let p = promotion?.rawValue ?? 0
        self.word = UInt16(from) | (UInt16(to) << 6) | (p << 12)
    }

    /// Origin square (0 = a1 … 63 = h8).
    @inline(__always)
    public var from: UInt8 { UInt8(word & 0x3F) }

    /// Destination square (0 = a1 … 63 = h8). For castling this is the
    /// rook's square (king-captures-rook, e.g. e1h1) — preserved verbatim.
    @inline(__always)
    public var to: UInt8 { UInt8((word >> 6) & 0x3F) }

    /// Promotion piece, if any.
    @inline(__always)
    public var promotion: Promotion? { Promotion(rawValue: word >> 12) }

    /// UCI rendering (e2e4, e7e8q). Castling renders king-captures-rook
    /// (e1h1) to stay wire-identical with Rust and gigaboard.
    public var uci: String {
        let s = "\(Move.squareName(from))\(Move.squareName(to))"
        if let p = promotion { return s + p.description }
        return s
    }

    /// UCI rendering (same as `uci`).
    public var description: String { uci }

    /// Algebraic square name (e4) for a 0…63 index (a1 = 0, h8 = 63).
    @inline(__always)
    public static func squareName(_ sq: UInt8) -> String {
        precondition(sq < 64, "square out of range")
        let file = Int(sq & 7)
        let rank = Int(sq >> 3)
        let f = Character(UnicodeScalar(97 + file)!)
        let r = Character(UnicodeScalar(49 + rank)!)
        return "\(f)\(r)"
    }

    /// Parse an algebraic square (e4) to a 0…63 index, or nil.
    public static func square(fromName name: some StringProtocol) -> UInt8? {
        guard name.count == 2 else { return nil }
        let bytes = Array(name.utf8)
        guard bytes.count == 2 else { return nil }
        let file = Int(bytes[0]) - 97
        let rank = Int(bytes[1]) - 49
        guard (0..<8).contains(file), (0..<8).contains(rank) else { return nil }
        return UInt8(rank * 8 + file)
    }

    /// Parse a UCI string (e2e4, e7e8q, e1h1) to a Move, or nil on bad shape.
    /// Legality is checked by `Board.play` / `Board.isLegal`, not here.
    public init?(uci: String) {
        guard uci.count == 4 || uci.count == 5 else { return nil }
        let chars = Array(uci)
        guard chars.count == 4 || chars.count == 5 else { return nil }
        guard let f = Move.square(fromName: String([chars[0], chars[1]])),
              let t = Move.square(fromName: String([chars[2], chars[3]])) else { return nil }
        var promo: Promotion?
        if chars.count == 5 {
            switch chars[4] {
            case "n", "N": promo = .knight
            case "b", "B": promo = .bishop
            case "r", "R": promo = .rook
            case "q", "Q": promo = .queen
            default: return nil
            }
        }
        self.init(from: f, to: t, promotion: promo)
    }
}
