// gigachess_ffi.h — raw C-ABI surface over the native `gigachess` engine.
// Mirrors gigachess 0.1.2 `pub` API 1:1 (native only, no shakmaty compat).
// Board is caller-owned value bytes (144B); Undo is opaque bytes (24B).
// Every function is panic-safe on the Rust side (catch_unwind → error code).
//
// SPDX-License-Identifier: MIT
#ifndef GIGACHESS_FFI_H
#define GIGACHESS_FFI_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ── Layout contract (checked by gigachess_board_size_assert + CI) ───────────
#define GIGACHESS_BOARD_SIZE 144
#define GIGACHESS_UNDO_SIZE 24
#define GIGACHESS_MAX_MOVES 256
#define GIGACHESS_FEN_MAX 96
#define GIGACHESS_SAN_MAX 12

// ── Status codes ────────────────────────────────────────────────────────────
#define GIGA_OK 0
#define GIGA_E_INVALID_FEN 1
#define GIGA_E_ILLEGAL_MOVE 2
#define GIGA_E_SAN_PARSE 3
#define GIGA_E_BUFFER_TOO_SMALL 4
#define GIGA_E_PANICKED 5
#define GIGA_E_CODEC 6

// ── Value types ─────────────────────────────────────────────────────────────

/// Caller-owned board storage. Copying these bytes snapshots the position
/// (bit-for-bit, suitable for search stacks). Never heap-allocated.
typedef struct {
    uint8_t bytes[GIGACHESS_BOARD_SIZE];
} GigaBoard;

/// Opaque make/unmake token. Only meaningful paired with its move.
typedef struct {
    uint8_t bytes[GIGACHESS_UNDO_SIZE];
} GigaUndo;

// ── Layout guard ────────────────────────────────────────────────────────────

/// Returns GIGA_OK when the linked engine matches this header, else non-zero.
int gigachess_board_size_assert(void);

// ── Lifecycle / queries ─────────────────────────────────────────────────────

void gigachess_board_startpos(GigaBoard *out);
void gigachess_board_empty(GigaBoard *out);
int gigachess_board_from_fen(GigaBoard *out, const char *fen, char *err_buf, size_t err_cap);
int gigachess_board_to_fen(const GigaBoard *board, char *out, size_t cap, size_t *out_len);

/// Side to move: 1 = White, 0 = Black.
uint8_t gigachess_board_turn(const GigaBoard *board);
/// Piece code 0..11 (Black 0..5, White 6..11), 12 = empty.
int gigachess_board_piece_at(const GigaBoard *board, uint8_t sq);
/// King square 0..63 for color (0 = Black, 1 = White).
uint8_t gigachess_board_king_square(const GigaBoard *board, uint8_t color);
/// Castling-rights bitmask (bit0 WK, bit1 WQ, bit2 BK, bit3 BQ).
uint8_t gigachess_board_castling_rights(const GigaBoard *board);
/// En-passant square 0..63, or -1 when none.
int gigachess_board_en_passant(const GigaBoard *board);
void gigachess_board_clocks(const GigaBoard *board, uint16_t *halfmove, uint16_t *fullmove);

// ── Zobrist / check ─────────────────────────────────────────────────────────

uint64_t gigachess_board_zobrist(const GigaBoard *board);
/// 1 when the side to move is in check, else 0.
int gigachess_board_in_check(const GigaBoard *board);

// ── Movegen ─────────────────────────────────────────────────────────────────

/// 1 when move_word is legal, else 0.
int gigachess_board_is_legal(const GigaBoard *board, uint16_t move_word);
/// Fill caller buffer (capacity >= GIGACHESS_MAX_MOVES words).
/// Returns the total count (only min(count, cap) words written).
size_t gigachess_board_legal_moves(const GigaBoard *board, uint16_t *out, size_t cap);
/// Legality-checked play. Board unchanged on GIGA_E_ILLEGAL_MOVE.
int gigachess_board_play(GigaBoard *board, uint16_t move_word, GigaUndo *out_undo);
void gigachess_board_make_unchecked(GigaBoard *board, uint16_t move_word, GigaUndo *out_undo);
void gigachess_board_unmake(GigaBoard *board, uint16_t move_word, const GigaUndo *undo);
uint64_t gigachess_board_perft(const GigaBoard *board, uint32_t depth);

// ── SAN ─────────────────────────────────────────────────────────────────────

int gigachess_board_move_to_san(const GigaBoard *board, uint16_t move_word,
                                char *out, size_t cap, size_t *out_len);
/// Accepts O-O and 0-0 castling spellings.
int gigachess_board_san_to_move(const GigaBoard *board, const char *san, uint16_t *out_move);

// ── moves2 codec / replay (flat buffers, no Vec/String/HashMap) ─────────────

int gigachess_parse_movetext_to_moves2(const char *start_fen, const char *movetext,
                                       uint16_t *out_words, size_t cap_words,
                                       size_t *out_count, size_t *out_fail_ply);
int gigachess_moves2_to_san_movetext(const char *start_fen, const uint16_t *words, size_t nwords,
                                     const char *result, char *out_buf, size_t cap,
                                     size_t *out_len, size_t *out_fail_ply);
/// Writes nwords+1 hashes (start position first). Needs cap >= nwords+1.
int gigachess_replay_moves2_stream(const char *start_fen, const uint16_t *words, size_t nwords,
                                   uint64_t *out_hashes, size_t cap,
                                   size_t *out_count, size_t *out_fail_ply);

#ifdef __cplusplus
}
#endif

#endif // GIGACHESS_FFI_H
