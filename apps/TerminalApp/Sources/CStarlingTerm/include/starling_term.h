// starling_term — the terminal emulator core in C.
//
// A faithful port of TerminalEmulator.swift's semantics: VT100/xterm parsing,
// character grid, scrollback, alternate screen, SGR, scroll regions. It exists
// because the Swift version spends ~47% of its time in runtime bookkeeping
// (exclusivity, ARC, copy-on-write) that this has no equivalent of — measured
// 5.6x on an escape-saturated stream. See test/bench/core/.
//
// Threading: exactly as the Swift original — feed/resize and reads must be
// externally synchronized by the caller.
#ifndef STARLING_TERM_H
#define STARLING_TERM_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Layout-compatible with Swift's TermCell: size 13, stride 16, align 4,
// offsets scalar=0 fg=4 bg=8 attrs=12. `attrs` MUST stay uint8_t —
// CellAttrs.rawValue is a UInt8, and a uint32_t here would make the two sides
// disagree about the three bytes after it.
typedef struct {
    uint32_t scalar;
    uint32_t fg;
    uint32_t bg;
    uint8_t  attrs;
} StarlingTermCell;

enum {
    STARLING_ATTR_BOLD      = 1 << 0,
    STARLING_ATTR_DIM       = 1 << 1,
    STARLING_ATTR_ITALIC    = 1 << 2,
    STARLING_ATTR_UNDERLINE = 1 << 3,
    STARLING_ATTR_REVERSE   = 1 << 4,
};

typedef struct StarlingTerm StarlingTerm;

StarlingTerm *starling_term_new(int cols, int rows);
void starling_term_free(StarlingTerm *t);

void starling_term_feed(StarlingTerm *t, const uint8_t *bytes, size_t n);
void starling_term_resize(StarlingTerm *t, int cols, int rows);

int      starling_term_cols(const StarlingTerm *t);
int      starling_term_rows(const StarlingTerm *t);
int      starling_term_cursor_row(const StarlingTerm *t);
int      starling_term_cursor_col(const StarlingTerm *t);
int      starling_term_cursor_visible(const StarlingTerm *t);
int      starling_term_app_cursor_keys(const StarlingTerm *t);
int      starling_term_bracketed_paste(const StarlingTerm *t);
/* Alt screen is readable because the scrollback belongs to the PRIMARY buffer:
   a full-screen app has no history of its own to scroll back through. */
int      starling_term_alt_active(const StarlingTerm *t);
/* DEC 1000/1002/1003 (any tracking flavour) and 1006 (SGR encoding). The UI
   reports the wheel only, and gates it on SGR so a wide window is not
   misreported by the legacy single-byte encoding. */
int      starling_term_mouse_tracking(const StarlingTerm *t);
int      starling_term_mouse_sgr(const StarlingTerm *t);
int      starling_term_scrollback_count(const StarlingTerm *t);
uint64_t starling_term_generation(const StarlingTerm *t);

// Copies exactly `cols` cells of one line into `out`, normalising width the way
// the Swift `_fitLine` did (scrollback rows can predate a resize).
// `abs_index` spans scrollback first, then the live grid:
//   [0, scrollback_count)                      -> scrollback
//   [scrollback_count, scrollback_count + rows) -> grid
void starling_term_copy_line(const StarlingTerm *t, int abs_index,
                             StarlingTermCell *out);

// Terminal responses (DSR/DA) destined for the pty, and BEL.
void starling_term_set_response_cb(StarlingTerm *t,
                                   void (*cb)(void *ctx, const char *s),
                                   void *ctx);
void starling_term_set_bell_cb(StarlingTerm *t, void (*cb)(void *ctx), void *ctx);

#ifdef __cplusplus
}
#endif
#endif
