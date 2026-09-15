//! gigachess-ffi — raw C-ABI shim over the native `gigachess` engine.
//!
//! Thin wrapper only: same functions, C spelling. No engine logic here.
//! Every `extern "C"` entry is panic-safe (`catch_unwind` → error code).
//! Board crosses as caller-owned fixed-size bytes (144B); Undo as 24B.
//!
//! SPDX-License-Identifier: MIT

use std::ffi::CStr;
use std::os::raw::{c_char, c_int};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;
use std::slice;

use gigachess::{Board, Color, Move, Square};

// ── Layout contract (must match gigachess_ffi.h + build script) ─────────────

/// Board storage size in bytes (`sizeof(Board)` for gigachess 0.1.2).
pub const BOARD_SIZE: usize = 144;
/// Undo storage size in bytes (`sizeof(Undo)` for gigachess 0.1.2).
pub const UNDO_SIZE: usize = 24;
/// Maximum legal moves in any position (stack-buffer bound).
pub const MAX_MOVES: usize = 256;
/// Maximum FEN string length in bytes (excluding NUL).
pub const FEN_MAX: usize = 96;
/// Maximum SAN string length in bytes (excluding NUL).
pub const SAN_MAX: usize = 12;

// ── Status codes (must match gigachess_ffi.h) ───────────────────────────────

/// Success.
pub const GIGA_OK: c_int = 0;
/// Invalid FEN string.
pub const GIGA_E_INVALID_FEN: c_int = 1;
/// Illegal move for the position.
pub const GIGA_E_ILLEGAL_MOVE: c_int = 2;
/// SAN parse failure.
pub const GIGA_E_SAN_PARSE: c_int = 3;
/// Caller buffer too small.
pub const GIGA_E_BUFFER_TOO_SMALL: c_int = 4;
/// Rust panic caught at the boundary.
pub const GIGA_E_PANICKED: c_int = 5;
/// Codec/replay failure (failing ply reported out-of-band).
pub const GIGA_E_CODEC: c_int = 6;

// ── Opaque byte structs ─────────────────────────────────────────────────────

/// Caller-owned board storage (144 bytes, copied by value, never heap).
#[repr(C)]
#[derive(Copy, Clone)]
pub struct GigaBoard {
    pub bytes: [u8; BOARD_SIZE],
}

/// Opaque make/unmake token (24 bytes).
#[repr(C)]
#[derive(Copy, Clone)]
pub struct GigaUndo {
    pub bytes: [u8; UNDO_SIZE],
}

const _: () = {
    assert!(std::mem::size_of::<Board>() == BOARD_SIZE);
    assert!(std::mem::size_of::<gigachess::Undo>() == UNDO_SIZE);
    assert!(std::mem::size_of::<Move>() == 2);
    assert!(gigachess::board::MAX_MOVES == MAX_MOVES);
};

// ── Internal helpers (not exported) ─────────────────────────────────────────

#[inline]
unsafe fn load_board(ptr: *const GigaBoard) -> Board {
    debug_assert!(!ptr.is_null());
    let mut aligned: Board = std::mem::zeroed();
    ptr::copy_nonoverlapping(
        (*ptr).bytes.as_ptr(),
        &mut aligned as *mut Board as *mut u8,
        BOARD_SIZE,
    );
    aligned
}

#[inline]
unsafe fn store_board(ptr: *mut GigaBoard, board: &Board) {
    debug_assert!(!ptr.is_null());
    ptr::copy_nonoverlapping(
        board as *const Board as *const u8,
        (*ptr).bytes.as_mut_ptr(),
        BOARD_SIZE,
    );
}

#[inline]
unsafe fn load_undo(ptr: *const GigaUndo) -> gigachess::Undo {
    debug_assert!(!ptr.is_null());
    let mut aligned: gigachess::Undo = std::mem::zeroed();
    ptr::copy_nonoverlapping(
        (*ptr).bytes.as_ptr(),
        &mut aligned as *mut gigachess::Undo as *mut u8,
        UNDO_SIZE,
    );
    aligned
}

#[inline]
unsafe fn store_undo(ptr: *mut GigaUndo, undo: &gigachess::Undo) {
    debug_assert!(!ptr.is_null());
    ptr::copy_nonoverlapping(
        undo as *const gigachess::Undo as *const u8,
        (*ptr).bytes.as_mut_ptr(),
        UNDO_SIZE,
    );
}

#[inline]
fn color_from_u8(v: u8) -> Option<Color> {
    match v {
        0 => Some(Color::Black),
        1 => Some(Color::White),
        _ => None,
    }
}

/// Write `s` as NUL-terminated C string into `[out, out+cap)`.
/// Returns `GIGA_OK` or `GIGA_E_BUFFER_TOO_SMALL`; always NUL-terminates when
/// `cap > 0`. `out_len` receives the content length excluding NUL.
unsafe fn write_cstr(
    s: &str,
    out: *mut c_char,
    cap: usize,
    out_len: *mut usize,
) -> c_int {
    if out.is_null() || cap == 0 {
        return GIGA_E_BUFFER_TOO_SMALL;
    }
    let bytes = s.as_bytes();
    if bytes.len() + 1 > cap {
        // Best-effort NUL so callers can still print the truncated buffer.
        *out = 0;
        if !out_len.is_null() {
            *out_len = 0;
        }
        return GIGA_E_BUFFER_TOO_SMALL;
    }
    ptr::copy_nonoverlapping(bytes.as_ptr() as *const c_char, out, bytes.len());
    *out.add(bytes.len()) = 0;
    if !out_len.is_null() {
        *out_len = bytes.len();
    }
    GIGA_OK
}

unsafe fn read_cstr<'a>(ptr: *const c_char) -> Result<&'a str, c_int> {
    if ptr.is_null() {
        return Err(GIGA_E_INVALID_FEN);
    }
    let cstr = CStr::from_ptr(ptr);
    cstr.to_str().map_err(|_| GIGA_E_INVALID_FEN)
}

// ── Exported API ────────────────────────────────────────────────────────────

/// Layout-drift guard: returns `GIGA_OK` when the compiled engine matches the
/// header contract, else a non-zero error. Call from CI on every build.
#[no_mangle]
pub extern "C" fn gigachess_board_size_assert() -> c_int {
    match catch_unwind(AssertUnwindSafe(|| {
        if std::mem::size_of::<Board>() != BOARD_SIZE { return 1; }
        if std::mem::size_of::<gigachess::Undo>() != UNDO_SIZE { return 2; }
        if gigachess::board::MAX_MOVES != MAX_MOVES { return 3; }
        if std::mem::align_of::<Board>() != 8 { return 4; }
        0
    })) {
        Ok(v) => v,
        Err(_) => GIGA_E_PANICKED,
    }
}

/// Write the standard starting position into `out`.
#[no_mangle]
pub extern "C" fn gigachess_board_startpos(out: *mut GigaBoard) {
    if out.is_null() { return; }
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        let b = Board::startpos();
        store_board(out, &b);
    }));
}

/// Write the empty board (White to move) into `out`.
#[no_mangle]
pub extern "C" fn gigachess_board_empty(out: *mut GigaBoard) {
    if out.is_null() { return; }
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        let b = Board::empty();
        store_board(out, &b);
    }));
}

/// Parse FEN into `out`. On failure returns `GIGA_E_INVALID_FEN` and writes a
/// human-readable detail into `[err_buf, err_buf+err_cap)` when provided.
#[no_mangle]
pub extern "C" fn gigachess_board_from_fen(
    out: *mut GigaBoard,
    fen: *const c_char,
    err_buf: *mut c_char,
    err_cap: usize,
) -> c_int {
    if out.is_null() { return GIGA_E_INVALID_FEN; }
    match catch_unwind(AssertUnwindSafe(|| unsafe {
        let s = match read_cstr(fen) {
            Ok(s) => s,
            Err(e) => return e,
        };
        match gigachess::fen::parse_fen(s) {
            Ok(b) => {
                store_board(out, &b);
                GIGA_OK
            }
            Err(e) => {
                if !err_buf.is_null() && err_cap > 0 {
                    let msg = e.to_string();
                    let bytes = msg.as_bytes();
                    let n = bytes.len().min(err_cap - 1);
                    ptr::copy_nonoverlapping(bytes.as_ptr() as *const c_char, err_buf, n);
                    *err_buf.add(n) = 0;
                }
                GIGA_E_INVALID_FEN
            }
        }
    })) {
        Ok(v) => v,
        Err(_) => GIGA_E_PANICKED,
    }
}

/// Export FEN into caller buffer. `out_len` receives content length (excl. NUL).
#[no_mangle]
pub extern "C" fn gigachess_board_to_fen(
    board: *const GigaBoard,
    out: *mut c_char,
    cap: usize,
    out_len: *mut usize,
) -> c_int {
    if board.is_null() { return GIGA_E_INVALID_FEN; }
    match catch_unwind(AssertUnwindSafe(|| unsafe {
        let b = load_board(board);
        let s = b.to_fen();
        write_cstr(&s, out, cap, out_len)
    })) {
        Ok(v) => v,
        Err(_) => GIGA_E_PANICKED,
    }
}

/// Side to move: 1 = White, 0 = Black, 255 on panic.
#[no_mangle]
pub extern "C" fn gigachess_board_turn(board: *const GigaBoard) -> u8 {
    if board.is_null() { return 255; }
    match catch_unwind(AssertUnwindSafe(|| unsafe {
        load_board(board).turn() as u8
    })) {
        Ok(v) => v,
        Err(_) => 255,
    }
}

/// Piece code on `sq` (0..63): 0..11 mailbox code (Black 0..5, White 6..11),
/// 12 = empty, 255 = panic, 254 = bad args.
#[no_mangle]
pub extern "C" fn gigachess_board_piece_at(board: *const GigaBoard, sq: u8) -> c_int {
    if board.is_null() || sq >= 64 { return 254; }
    match catch_unwind(AssertUnwindSafe(|| unsafe {
        match load_board(board).piece_at(Square(sq)) {
            Some(p) => p.code() as c_int,
            None => 12,
        }
    })) {
        Ok(v) => v,
        Err(_) => 255,
    }
}

/// King square index 0..63 for `color` (0 = Black, 1 = White); 255 on error.
#[no_mangle]
pub extern "C" fn gigachess_board_king_square(board: *const GigaBoard, color: u8) -> u8 {
    if board.is_null() { return 255; }
    match catch_unwind(AssertUnwindSafe(|| unsafe {
        match color_from_u8(color) {
            Some(c) => load_board(board).king_square(c).0,
            None => 255,
        }
    })) {
        Ok(v) => v,
        Err(_) => 255,
    }
}

/// Castling-rights bitmask (bit0 WK, bit1 WQ, bit2 BK, bit3 BQ).
#[no_mangle]
pub extern "C" fn gigachess_board_castling_rights(board: *const GigaBoard) -> u8 {
    if board.is_null() { return 0; }
    match catch_unwind(AssertUnwindSafe(|| unsafe {
        load_board(board).castling_rights()
    })) {
        Ok(v) => v,
        Err(_) => 0,
    }
}

/// En-passant square 0..63, or -1 when none.
#[no_mangle]
pub extern "C" fn gigachess_board_en_passant(board: *const GigaBoard) -> c_int {
    if board.is_null() { return -2; }
    match catch_unwind(AssertUnwindSafe(|| unsafe {
        match load_board(board).en_passant() {
            Some(sq) => sq.0 as c_int,
            None => -1,
        }
    })) {
        Ok(v) => v,
        Err(_) => -2,
    }
}

/// Halfmove clock and fullmove number via out-params (ignored when null).
#[no_mangle]
pub extern "C" fn gigachess_board_clocks(
    board: *const GigaBoard,
    halfmove: *mut u16,
    fullmove: *mut u16,
) {
    if board.is_null() { return; }
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        let b = load_board(board);
        if !halfmove.is_null() { *halfmove = b.halfmove_clock(); }
        if !fullmove.is_null() { *fullmove = b.fullmove_number(); }
    }));
}

/// Current Polyglot Zobrist key, by value (0 on null/panic — note startpos is
/// never 0 for the pinned engine, so 0 is a usable sentinel here).
#[no_mangle]
pub extern "C" fn gigachess_board_zobrist(board: *const GigaBoard) -> u64 {
    if board.is_null() { return 0; }
    match catch_unwind(AssertUnwindSafe(|| unsafe {
        load_board(board).zobrist()
    })) {
        Ok(v) => v,
        Err(_) => 0,
    }
}

/// 1 when the side to move is in check, else 0.
#[no_mangle]
pub extern "C" fn gigachess_board_in_check(board: *const GigaBoard) -> c_int {
    if board.is_null() { return -1; }
    match catch_unwind(AssertUnwindSafe(|| unsafe {
        i32::from(load_board(board).in_check())
    })) {
        Ok(v) => v,
        Err(_) => -1,
    }
}

/// 1 when `move_word` is legal in the position, else 0.
#[no_mangle]
pub extern "C" fn gigachess_board_is_legal(board: *const GigaBoard, move_word: u16) -> c_int {
    if board.is_null() { return 0; }
    match catch_unwind(AssertUnwindSafe(|| unsafe {
        i32::from(load_board(board).is_legal(Move::from_word(move_word)))
    })) {
        Ok(v) => v,
        Err(_) => 0,
    }
}

/// Fill caller buffer with legal-move words. Returns the total count (which
/// may exceed `cap`; only `min(count, cap)` words are written).
#[no_mangle]
pub extern "C" fn gigachess_board_legal_moves(
    board: *const GigaBoard,
    out: *mut u16,
    cap: usize,
) -> usize {
    if board.is_null() { return 0; }
    match catch_unwind(AssertUnwindSafe(|| unsafe {
        let b = load_board(board);
        let moves = b.legal_moves();
        let n = moves.len();
        if !out.is_null() && cap > 0 {
            let k = n.min(cap);
            for (i, m) in moves.iter().take(k).enumerate() {
                *out.add(i) = m.word();
            }
        }
        n
    })) {
        Ok(v) => v,
        Err(_) => 0,
    }
}

/// Legality-checked play. On success updates `*board`, writes `*out_undo` and
/// returns `GIGA_OK`; on illegal move returns `GIGA_E_ILLEGAL_MOVE` with the
/// board unchanged.
#[no_mangle]
pub extern "C" fn gigachess_board_play(
    board: *mut GigaBoard,
    move_word: u16,
    out_undo: *mut GigaUndo,
) -> c_int {
    if board.is_null() { return GIGA_E_ILLEGAL_MOVE; }
    match catch_unwind(AssertUnwindSafe(|| unsafe {
        let mut b = load_board(board as *const GigaBoard);
        match b.play(Move::from_word(move_word)) {
            Ok(undo) => {
                store_board(board, &b);
                if !out_undo.is_null() { store_undo(out_undo, &undo); }
                GIGA_OK
            }
            Err(_) => GIGA_E_ILLEGAL_MOVE,
        }
    })) {
        Ok(v) => v,
        Err(_) => GIGA_E_PANICKED,
    }
}

/// Unchecked make (caller guarantees legality, e.g. replaying generated moves).
#[no_mangle]
pub extern "C" fn gigachess_board_make_unchecked(
    board: *mut GigaBoard,
    move_word: u16,
    out_undo: *mut GigaUndo,
) {
    if board.is_null() { return; }
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        let mut b = load_board(board as *const GigaBoard);
        let undo = b.make_move_unchecked(Move::from_word(move_word));
        store_board(board, &b);
        if !out_undo.is_null() { store_undo(out_undo, &undo); }
    }));
}

/// Unmake a move made with `make_unchecked` (or `play`) using its `Undo`.
#[no_mangle]
pub extern "C" fn gigachess_board_unmake(
    board: *mut GigaBoard,
    move_word: u16,
    undo: *const GigaUndo,
) {
    if board.is_null() || undo.is_null() { return; }
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        let mut b = load_board(board as *const GigaBoard);
        let u = load_undo(undo);
        b.unmake_move(Move::from_word(move_word), u);
        store_board(board, &b);
    }));
}

/// Perft node count at `depth` (leaf-counting, identical to native `perft`).
#[no_mangle]
pub extern "C" fn gigachess_board_perft(board: *const GigaBoard, depth: u32) -> u64 {
    if board.is_null() { return 0; }
    match catch_unwind(AssertUnwindSafe(|| unsafe {
        load_board(board).perft(depth)
    })) {
        Ok(v) => v,
        Err(_) => 0,
    }
}

/// Render a legal move as SAN into caller buffer (≤12B + NUL).
#[no_mangle]
pub extern "C" fn gigachess_board_move_to_san(
    board: *const GigaBoard,
    move_word: u16,
    out: *mut c_char,
    cap: usize,
    out_len: *mut usize,
) -> c_int {
    if board.is_null() { return GIGA_E_ILLEGAL_MOVE; }
    match catch_unwind(AssertUnwindSafe(|| unsafe {
        let b = load_board(board);
        match gigachess::san::move_to_san(&b, Move::from_word(move_word)) {
            Some(san) => write_cstr(san.as_str(), out, cap, out_len),
            None => GIGA_E_ILLEGAL_MOVE,
        }
    })) {
        Ok(v) => v,
        Err(_) => GIGA_E_PANICKED,
    }
}

/// Parse SAN against the position. Accepts `O-O` and `0-0` spellings.
#[no_mangle]
pub extern "C" fn gigachess_board_san_to_move(
    board: *const GigaBoard,
    san: *const c_char,
    out_move: *mut u16,
) -> c_int {
    if board.is_null() || out_move.is_null() { return GIGA_E_SAN_PARSE; }
    match catch_unwind(AssertUnwindSafe(|| unsafe {
        let b = load_board(board);
        let s = match read_cstr(san) {
            Ok(s) => s,
            Err(_) => return GIGA_E_SAN_PARSE,
        };
        match gigachess::san::san_to_move(&b, s) {
            Some(mv) => {
                *out_move = mv.word();
                GIGA_OK
            }
            None => GIGA_E_SAN_PARSE,
        }
    })) {
        Ok(v) => v,
        Err(_) => GIGA_E_PANICKED,
    }
}

/// Parse SAN movetext into moves2 words. On success writes `*out_count` words
/// (2 bytes each as `u16`) and returns `GIGA_OK`; on failure returns
/// `GIGA_E_CODEC` (or `GIGA_E_INVALID_FEN` for a bad start FEN, or
/// `GIGA_E_BUFFER_TOO_SMALL`) with `*out_fail_ply` set to the offending ply.
#[no_mangle]
pub extern "C" fn gigachess_parse_movetext_to_moves2(
    start_fen: *const c_char,
    movetext: *const c_char,
    out_words: *mut u16,
    cap_words: usize,
    out_count: *mut usize,
    out_fail_ply: *mut usize,
) -> c_int {
    match catch_unwind(AssertUnwindSafe(|| unsafe {
        let fen = match read_cstr(start_fen) {
            Ok(s) => s,
            Err(_) => return GIGA_E_INVALID_FEN,
        };
        // movetext: empty string is legal (zero moves); null is a caller bug.
        let text = if movetext.is_null() {
            return GIGA_E_CODEC;
        } else {
            match CStr::from_ptr(movetext).to_str() {
                Ok(s) => s,
                Err(_) => return GIGA_E_CODEC,
            }
        };
        match gigachess::database::parse_movetext_to_moves2(fen, text) {
            Ok(bytes) => {
                let nwords = bytes.len() / 2;
                if nwords > cap_words {
                    if !out_fail_ply.is_null() { *out_fail_ply = 0; }
                    return GIGA_E_BUFFER_TOO_SMALL;
                }
                if !out_words.is_null() && nwords > 0 {
                    for (i, pair) in bytes.chunks_exact(2).enumerate() {
                        *out_words.add(i) = u16::from_le_bytes([pair[0], pair[1]]);
                    }
                }
                if !out_count.is_null() { *out_count = nwords; }
                GIGA_OK
            }
            Err(e) => {
                if !out_fail_ply.is_null() { *out_fail_ply = e.ply; }
                if !out_count.is_null() { *out_count = 0; }
                // Bad start FEN surfaces as ply-0 + "bad start FEN" token.
                if e.ply == 0 && e.token.starts_with("bad start FEN") {
                    GIGA_E_INVALID_FEN
                } else {
                    GIGA_E_CODEC
                }
            }
        }
    })) {
        Ok(v) => v,
        Err(_) => GIGA_E_PANICKED,
    }
}

/// Render moves2 words as SAN movetext with move numbers plus `result` token.
/// `result` may be null/empty for no trailing token.
#[no_mangle]
pub extern "C" fn gigachess_moves2_to_san_movetext(
    start_fen: *const c_char,
    words: *const u16,
    nwords: usize,
    result: *const c_char,
    out_buf: *mut c_char,
    cap: usize,
    out_len: *mut usize,
    out_fail_ply: *mut usize,
) -> c_int {
    match catch_unwind(AssertUnwindSafe(|| unsafe {
        let fen = match read_cstr(start_fen) {
            Ok(s) => s,
            Err(_) => return GIGA_E_INVALID_FEN,
        };
        if nwords > 0 && words.is_null() { return GIGA_E_CODEC; }
        let word_slice = if nwords == 0 {
            &[][..]
        } else {
            slice::from_raw_parts(words, nwords)
        };
        // moves2 byte stream is little-endian pairs.
        let mut bytes = Vec::with_capacity(nwords * 2);
        for w in word_slice {
            bytes.extend_from_slice(&w.to_le_bytes());
        }
        let res = if result.is_null() {
            ""
        } else {
            match CStr::from_ptr(result).to_str() {
                Ok(s) => s,
                Err(_) => return GIGA_E_CODEC,
            }
        };
        match gigachess::database::moves2_to_san_movetext(fen, &bytes, res) {
            Ok(s) => {
                let rc = write_cstr(&s, out_buf, cap, out_len);
                if rc != GIGA_OK { return rc; }
                GIGA_OK
            }
            Err(e) => {
                if !out_fail_ply.is_null() { *out_fail_ply = e.ply; }
                if e.ply == 0 && e.token.starts_with("bad start FEN") {
                    GIGA_E_INVALID_FEN
                } else {
                    GIGA_E_CODEC
                }
            }
        }
    })) {
        Ok(v) => v,
        Err(_) => GIGA_E_PANICKED,
    }
}

/// Replay a moves2 stream to Zobrist hashes: writes `nwords+1` hashes (start
/// position first) when `cap` allows. `out_count` receives hashes written;
/// on illegal word returns `GIGA_E_CODEC` with `*out_fail_ply` set.
#[no_mangle]
pub extern "C" fn gigachess_replay_moves2_stream(
    start_fen: *const c_char,
    words: *const u16,
    nwords: usize,
    out_hashes: *mut u64,
    cap: usize,
    out_count: *mut usize,
    out_fail_ply: *mut usize,
) -> c_int {
    match catch_unwind(AssertUnwindSafe(|| unsafe {
        let fen = match read_cstr(start_fen) {
            Ok(s) => s,
            Err(_) => return GIGA_E_INVALID_FEN,
        };
        if nwords > 0 && words.is_null() { return GIGA_E_CODEC; }
        if cap < nwords + 1 {
            if !out_count.is_null() { *out_count = 0; }
            if !out_fail_ply.is_null() { *out_fail_ply = 0; }
            return GIGA_E_BUFFER_TOO_SMALL;
        }
        let word_slice = if nwords == 0 {
            &[][..]
        } else {
            slice::from_raw_parts(words, nwords)
        };
        match gigachess::database::replay_moves2_hashes(fen, word_slice) {
            Ok(seq) => {
                if !out_hashes.is_null() {
                    for (i, (h, _)) in seq.iter().enumerate() {
                        *out_hashes.add(i) = *h;
                    }
                }
                if !out_count.is_null() { *out_count = seq.len(); }
                GIGA_OK
            }
            Err(e) => {
                if !out_fail_ply.is_null() { *out_fail_ply = e.ply; }
                if !out_count.is_null() { *out_count = 0; }
                if e.ply == 0 && e.token.starts_with("bad start FEN") {
                    GIGA_E_INVALID_FEN
                } else {
                    GIGA_E_CODEC
                }
            }
        }
    })) {
        Ok(v) => v,
        Err(_) => GIGA_E_PANICKED,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn start_board() -> Board {
        Board::startpos()
    }

    #[test]
    fn layout_contract_holds() {
        assert_eq!(std::mem::size_of::<Board>(), BOARD_SIZE);
        assert_eq!(std::mem::size_of::<gigachess::Undo>(), UNDO_SIZE);
        assert_eq!(gigachess_board_size_assert(), GIGA_OK);
    }

    #[test]
    fn startpos_key_and_perft_match_pin() {
        let b = start_board();
        assert_eq!(b.zobrist(), 0x463b96181691fc9c);
        assert_eq!(b.perft(1), 20);
        assert_eq!(b.perft(2), 400);
        assert_eq!(b.perft(3), 8902);
    }

    #[test]
    fn ffi_round_trip_fen_and_play() {
        unsafe {
            let mut gb: GigaBoard = std::mem::zeroed();
            gigachess_board_startpos(&mut gb);
            assert_eq!(gigachess_board_turn(&gb), 1);
            assert_eq!(gigachess_board_legal_moves(&gb, ptr::null_mut(), 0), 20);

            let mut buf = [0u16; MAX_MOVES];
            let n = gigachess_board_legal_moves(&gb, buf.as_mut_ptr(), buf.len());
            assert_eq!(n, 20);

            // Play e2e4 (from=12, to=28) and unmake.
            let e2e4 = Move::new(Square(12), Square(28), None).word();
            assert!(buf.contains(&e2e4));
            let mut undo: GigaUndo = std::mem::zeroed();
            assert_eq!(gigachess_board_play(&mut gb, e2e4, &mut undo), GIGA_OK);
            assert_eq!(gigachess_board_turn(&gb), 0);
            let h1 = gigachess_board_zobrist(&gb);
            gigachess_board_unmake(&mut gb, e2e4, &undo);
            assert_eq!(gigachess_board_zobrist(&gb), start_board().zobrist());
            assert_ne!(h1, start_board().zobrist());

            // Illegal move rejected, board unchanged.
            let before = gb;
            assert_eq!(gigachess_board_play(&mut gb, 0, &mut undo), GIGA_E_ILLEGAL_MOVE);
            assert_eq!(gb.bytes, before.bytes);
        }
    }

    #[test]
    fn ffi_adversarial_inputs_never_abort() {
        unsafe {
            // Nulls and garbage must return errors, never trap.
            assert_eq!(
                gigachess_board_from_fen(ptr::null_mut(), ptr::null(), ptr::null_mut(), 0),
                GIGA_E_INVALID_FEN
            );
            let mut gb: GigaBoard = std::mem::zeroed();
            let mut err = [0 as c_char; 128];
            let bad = c"not a fen".as_ptr();
            assert_eq!(
                gigachess_board_from_fen(&mut gb, bad, err.as_mut_ptr(), err.len()),
                GIGA_E_INVALID_FEN
            );
            // Truncated buffers.
            gigachess_board_startpos(&mut gb);
            let mut tiny = [0 as c_char; 4];
            let mut len = 0usize;
            assert_eq!(
                gigachess_board_to_fen(&gb, tiny.as_mut_ptr(), tiny.len(), &mut len),
                GIGA_E_BUFFER_TOO_SMALL
            );
            // Out-of-range words / squares.
            assert_eq!(gigachess_board_piece_at(&gb, 64), 254);
            assert_eq!(gigachess_board_is_legal(&gb, 0xFFFF), 0);
            assert_eq!(gigachess_board_king_square(&gb, 7), 255);
            assert_eq!(gigachess_board_en_passant(ptr::null()), -2);
            // Codec with garbage.
            let mut words = [0u16; 8];
            let mut count = 0usize;
            let mut fail = 0usize;
            let rc = gigachess_parse_movetext_to_moves2(
                c"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1".as_ptr(),
                c"e4 Qh6".as_ptr(),
                words.as_mut_ptr(),
                words.len(),
                &mut count,
                &mut fail,
            );
            assert_eq!(rc, GIGA_E_CODEC);
            assert_eq!(fail, 1);
        }
    }
}
