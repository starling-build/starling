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

#if !defined(_WIN32)
#include <unistd.h>
#endif
#if defined(__linux__)
#include <sys/syscall.h>
// glibc only declares syscall() under _GNU_SOURCE, and this header is also
// compiled by plain-gcc test harnesses. Same prototype glibc uses, so the
// two declarations coexist when both are visible.
long syscall(long __sysno, ...);
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Between fork() and exec(): close every fd above stderr, so the spawned
// shell starts with 0/1/2 and nothing else. What it would otherwise inherit
// is other people's plumbing — the app↔shell control socket, exit-watch
// fds, event pipes — and a descendant that outlives the pty hangup
// (`setsid`, `nohup`, a daemon) then holds them open on the terminal's
// behalf: the desktop shell reads "still alive" from fds whose owner is
// long dead. Swift can't express this itself (glibc's close_range isn't in
// the Glibc module, and the fallback loop must run between fork and exec,
// where only async-signal-safe calls are allowed).
static inline void starling_close_extra_fds(void) {
#if defined(__linux__)
    // By syscall number: the glibc wrapper needs _GNU_SOURCE and glibc
    // 2.34; the syscall (Linux 5.9+) needs neither. ENOSYS falls through.
    if (syscall(SYS_close_range, 3u, ~0u, 0u) == 0) return;
#endif
#if !defined(_WIN32)
    long limit = sysconf(_SC_OPEN_MAX);
    if (limit < 0 || limit > 65536) limit = 65536;  // rlimit can be 2^20
    for (long fd = 3; fd < limit; fd++) close((int)fd);
#endif
}

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
    /* Wide (two-column) characters occupy a LEAD cell carrying the scalar
       and a CONTINUATION cell with scalar 0. The renderer draws the lead
       across two cell widths and draws nothing for the continuation; the
       emulator keeps the pair consistent (overwriting either half blanks
       the other). */
    STARLING_ATTR_WIDE      = 1 << 5,
    STARLING_ATTR_WIDE_CONT = 1 << 6,
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

// Where the shell last said it is (OSC 7), or "" if it has never said. Owned
// by the terminal and valid until the next feed. Many shells never emit it —
// treat empty as "no idea", never as "/".
const char *starling_term_cwd(const StarlingTerm *t);

// Copies exactly `cols` cells of one line into `out`, normalising width the way
// the Swift `_fitLine` did (scrollback rows can predate a resize).
// `abs_index` spans scrollback first, then the live grid:
//   [0, scrollback_count)                      -> scrollback
//   [scrollback_count, scrollback_count + rows) -> grid
void starling_term_copy_line(const StarlingTerm *t, int abs_index,
                             StarlingTermCell *out);

// Terminal responses (DSR/DA) destined for the pty, and BEL.
/* UTF-8 of a cell's full content. A plain scalar encodes directly; a
   grapheme-cluster reference (scalar above the Unicode range) expands to
   its full sequence. Returns bytes written (no terminator). */
int starling_term_cell_text(const StarlingTerm *t, uint32_t scalar, char *buf, int cap);

void starling_term_set_response_cb(StarlingTerm *t,
                                   void (*cb)(void *ctx, const char *s),
                                   void *ctx);
void starling_term_set_bell_cb(StarlingTerm *t, void (*cb)(void *ctx), void *ctx);

/* SPSC byte ring + pace helper for the Darwin paced pty reader (st_ring.c,
   Darwin-only definitions). One producer thread, one consumer thread. */
typedef struct StRing StRing;
StRing *st_ring_new(size_t cap);
void    st_ring_free(StRing *r);
void    st_ring_write(StRing *r, const unsigned char *p, size_t n);
size_t  st_ring_take(StRing *r, const unsigned char **out);  /* 0 = closed+drained */
void    st_ring_consume(StRing *r, size_t n);
void    st_ring_close(StRing *r);
void    st_pace(unsigned long long ns);                      /* busy-wait */

#ifdef __cplusplus
}
#endif
#endif
