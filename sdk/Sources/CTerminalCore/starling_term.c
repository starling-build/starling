// See starling_term.h. Ported from TerminalEmulator.swift; every behavioural
// quirk there is deliberate and is reproduced here, including:
//   - the wrap-pending bookkeeping (cursor parks on the last column)
//   - scrollback trimmed in batches with slack, so the limit is a floor
//   - CSI parameters where an explicit 0 means "use the default"
//   - an empty parameter list staying empty (CSI m != CSI 0 m)
//   - erase using the CURRENT background, not the default
//
// One deliberate divergence: the Swift version hands out a single shared blank
// row by copy-on-write, so a row that scrolls past untouched costs a retain.
// Here a blank row is memcpy'd from a template instead, into a buffer recycled
// through the row pool below. Refcounted sharing is NOT the fix if scrolling
// looks slow — it was implemented and measured, and cost 23-28% everywhere else
// because put_scalar then tests a shared flag per character. The scroll cost was
// the allocator, not the copy; see test/bench/core/README.md.
#include "include/starling_term.h"

#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#define SB_LIMIT 2000
#define SB_SLACK 512
/* Rows of headroom after the live screen, so a full-screen scroll can bump a
   pointer instead of moving every row. One recentring memmove per this many
   line feeds; at 24 bytes a Row the whole reserve is ~24 KB. */
#define GRID_SLACK 1024
#define MAX_PARAMS 64
#define OSC_MAX 256
/* Sized to the scrollback trim batch: a trim frees SB_SLACK rows at once and the
   next SB_SLACK line feeds each want one back, so a pool smaller than the batch
   spills the difference to the allocator and the churn returns. The extra 64
   covers a full-grid erase on top of a trim. */
#define ROW_POOL_MAX (SB_SLACK + 64)

typedef StarlingTermCell Cell;

/* Extent-based blanking. Filling a freshly recycled row used to memset the
   full width on every line feed; at 478 columns the light_cells workload
   (1.5 M line feeds) moved 11.5 GB of blanking for rows that carry ~7
   characters, and the emulator alone pushed `cat` 40% past the pty's read
   floor. Each row instead tracks how far it has been written:

     INVARIANT: cells[used..cols) all equal the blank cell
                {scalar 32, fg 0, attrs 0, bg = tail_bg}.

   Writers maintain it (extending `used` costs one compare); recycling
   exploits it (fill [0, used) and, when the pooled buffer's tail already
   matches the requested background, skip the rest). Every cell in memory is
   at all times byte-identical to what the full-width code produced — readers
   and the differential harness see no difference. */
typedef struct {
    Cell *cells;
    int   cols;      /* scrollback rows may predate a resize */
    int   used;
    uint32_t tail_bg;
} Row;

typedef struct {                /* a pooled buffer keeps its extent */
    Cell *cells;
    int   used;
    uint32_t tail_bg;
} PoolRow;

typedef enum {
    ST_GROUND, ST_ESCAPE, ST_ESC_INTERMEDIATE, ST_CSI, ST_OSC, ST_OSC_ESCAPE
} ParseState;

/* Grapheme cluster pool entry — the full codepoint sequence of a cell
   whose scalar is a GP_BASE reference. See the pool section. */
#define GP_BASE    0x110000u
#define GP_MAX     65536
#define GP_MAX_CPS 15
typedef struct { uint32_t *cps; int n; } GraphemeEntry;

/* One remembered width answer and the codepoint interval over which it is
   the answer. See the character-width section. */
/* Remembered width answers, keyed by the codepoint's 512-wide block rather
   than held in a most-recently-used list. See width_lookup. 128 slots cover
   the whole BMP with no aliasing at all (0xFFFF >> 9 == 127); the astral
   planes fold back onto it, which costs a recompute on collision and can
   never give a wrong answer, because every slot re-checks the interval it
   stored. 2 KB per terminal. */
#define WIDTH_SLOTS 128
#define WIDTH_SLOT(cp) (((cp) >> 9) & (WIDTH_SLOTS - 1))
typedef struct { uint32_t lo, hi; int w, ordinary; } WidthSpan;

struct StarlingTerm {
    int cols, rows;

    /* The live screen is a WINDOW into a larger block, not the block itself:
       `grid[0 .. rows-1]` are the rows, and `grid` slides forward through
       `grid_base[0 .. grid_cap-1]` as the screen scrolls. See grid_rotate_in
       for why. Only scrolling ever moves `grid`; everything else calls
       grid_recenter() first and then treats grid_base as a plain array. */
    Row *grid;                 /* rows entries — the live window */
    Row *grid_base;            /* the allocation `grid` points into */
    int  grid_cap;             /* Row slots in grid_base */
    Row *sb;                   /* scrollback ring, oldest at sb_head */
    int  sb_cap, sb_head, sb_len;

    int cursor_row, cursor_col;
    int cursor_visible;
    uint64_t generation;

    uint32_t cur_fg, cur_bg;
    uint8_t  cur_attrs;

    int region_top, region_bottom;

    int autowrap, origin_mode, wrap_pending;
    int app_cursor_keys, bracketed_paste;
    int mouse_tracking, mouse_sgr;

    int  alt_active;
    Row *saved_primary;        /* NULL when not in alt screen — always the
                                  recentred base, so it is a plain array */
    int  saved_primary_rows;
    int  saved_primary_cap;
    int  saved_primary_cursor_row, saved_primary_cursor_col;

    int      saved_cursor_row, saved_cursor_col;
    uint32_t saved_fg, saved_bg;
    uint8_t  saved_attrs;

    ParseState state;
    int  csi_nums[MAX_PARAMS];
    int  csi_count;
    int  csi_cur;              /* -1 = no digits since the last ';' */
    int  csi_private;
    /* The most recent printed cell (lead column), for the retroactive
       width fix-ups: VS16 widens it, VS15 narrows it, and a regional
       indicator pairs with it into one flag. -1 = nothing to fix up —
       any cursor movement or control invalidates it. */
    int      last_row, last_col, last_w;
    uint32_t last_scalar;
    /* Grapheme cluster pool (see its section) and the join state: after a
       ZWJ or a virama, the next printed character extends the last cell's
       cluster instead of taking a column of its own. */
    GraphemeEntry *gp;
    int gp_n, gp_cap;
    int *gp_map, gp_map_cap;
    int join_pending;
    /* Intermediate byte (0x20-0x2F) collected inside a CSI, 0 if none. Before
       this was tracked, `CSI ... $ r` (DECCARA) dispatched as a bare 'r' and
       silently reprogrammed the scroll region. */
    int  csi_inter;

    char osc[OSC_MAX];
    int  osc_len;

    uint8_t utf8_pending[4];
    int     utf8_pending_len;

    Cell *blank_template;      /* cols cells at cur_bg */
    uint32_t blank_bg;
    int      blank_cols;

    PoolRow *pool;             /* recycled row buffers, all `pool_cols` wide */
    int      pool_len;
    int      pool_cols;

    void (*response_cb)(void *ctx, const char *s);
    void *response_ctx;
    void (*bell_cb)(void *ctx);
    void *bell_ctx;

    /* Last, deliberately. This is 128 bytes and it is touched only by the
       non-ASCII run path, so putting it among the fields the hot loops use
       pushes those across cache lines and costs the workloads that never
       reach it: measured +5% on 03_sgr_fg and +6% on 02_dense_cells, neither
       of which contains a byte >= 0x80. Seeded in starling_term_new. */
    WidthSpan wspan[WIDTH_SLOTS];
};

/* ---------------------------------------------------------------- palette */

static const uint32_t kAnsi16[16] = {
    0xFF000000u, 0xFFC23621u, 0xFF25BC24u, 0xFFADAD27u,
    0xFF4C7BD4u, 0xFFD338D3u, 0xFF33BBC8u, 0xFFCBCCCDu,
    0xFF818383u, 0xFFFC391Fu, 0xFF31E722u, 0xFFEAEC23u,
    0xFF6A9BF5u, 0xFFF935F8u, 0xFF14F0F0u, 0xFFFFFFFFu,
};

static uint32_t pal_ansi(int index, int bold) {
    int i = index < 0 ? 0 : (index > 7 ? 7 : index);
    return kAnsi16[i + (bold ? 8 : 0)];
}

static uint32_t pal_256(int index) {
    int i = index < 0 ? 0 : (index > 255 ? 255 : index);
    if (i < 16) return kAnsi16[i];
    if (i < 232) {
        static const uint32_t steps[6] = {0, 95, 135, 175, 215, 255};
        int v = i - 16;
        uint32_t r = steps[(v / 36) % 6], g = steps[(v / 6) % 6], b = steps[v % 6];
        return 0xFF000000u | (r << 16) | (g << 8) | b;
    }
    uint32_t gray = (uint32_t)(8 + (i - 232) * 10);
    return 0xFF000000u | (gray << 16) | (gray << 8) | gray;
}

/* ------------------------------------------------------------- row helpers */

static Cell blank_cell(const StarlingTerm *t) {
    Cell c; c.scalar = 32; c.fg = 0; c.bg = t->cur_bg; c.attrs = 0;
    return c;
}

/* Template of `cols` blank cells at the current background, rebuilt only when
   the background or the width changes. */
static const Cell *blank_template(StarlingTerm *t) {
    if (!t->blank_template || t->blank_bg != t->cur_bg || t->blank_cols != t->cols) {
        free(t->blank_template);
        t->blank_template = malloc(sizeof(Cell) * (size_t)t->cols);
        Cell b = blank_cell(t);
        for (int i = 0; i < t->cols; i++) t->blank_template[i] = b;
        t->blank_bg = t->cur_bg;
        t->blank_cols = t->cols;
    }
    return t->blank_template;
}

/* Row buffers are recycled through a small pool rather than returned to the
   allocator. Scrolling frees one row and allocates another of the same width on
   every single line feed, but when the freed row goes via scrollback the two are
   separated by ~2000 intervening rows, and glibc cannot pair them up: the FIFO
   churn across that ~6 MB working set costs more in page faults than the scroll
   itself. Measured on the light_cells workload (1.5 M line feeds): 226 k minor
   faults, ~62% of the run in the kernel. Pooling pairs them directly. */
static void pool_drain(StarlingTerm *t) {
    for (int i = 0; i < t->pool_len; i++) free(t->pool[i].cells);
    t->pool_len = 0;
}

/* Hand a row's buffer back for reuse, and leave the Row holding nothing. Rows
   that predate a resize are the wrong width, so they are simply freed; a pool
   left over from an older width is dropped whole on the first release at the
   new one, which is what keeps `pool_cols` honest without every caller that
   changes `cols` having to remember the pool exists. */
static void row_release(StarlingTerm *t, Row *r) {
    if (!r->cells) return;
    if (r->cols == t->cols) {
        if (t->pool_cols != t->cols) { pool_drain(t); t->pool_cols = t->cols; }
        if (t->pool_len < ROW_POOL_MAX) {
            if (!t->pool) t->pool = malloc(sizeof(PoolRow) * ROW_POOL_MAX);
            t->pool[t->pool_len++] =
                (PoolRow){ r->cells, r->used, r->tail_bg };
            r->cells = NULL;
            return;
        }
    }
    free(r->cells);
    r->cells = NULL;
}

/* A row of blank cells at background `bg`. From the pool, only the previous
   life's written prefix needs refilling — the tail beyond it is already the
   blank pattern, provided its background matches. */
static Row row_filled(StarlingTerm *t, uint32_t bg) {
    Row r;
    r.cols = t->cols;
    r.used = 0;
    r.tail_bg = bg;
    int fill = t->cols;
    if (t->pool_len > 0 && t->pool_cols == t->cols) {
        PoolRow p = t->pool[--t->pool_len];
        r.cells = p.cells;
        if (p.tail_bg == bg) fill = p.used;
    } else {
        r.cells = malloc(sizeof(Cell) * (size_t)t->cols);
    }
    if (fill > 0) {
        if (bg == t->cur_bg) {
            memcpy(r.cells, blank_template(t), sizeof(Cell) * (size_t)fill);
        } else {
            Cell b; b.scalar = 32; b.fg = 0; b.bg = bg; b.attrs = 0;
            for (int i = 0; i < fill; i++) r.cells[i] = b;
        }
    }
    return r;
}

static Row row_blank(StarlingTerm *t)   { return row_filled(t, t->cur_bg); }

/* A row of default-blank cells (bg 0) — what a fresh grid and RIS produce. */
static Row row_default(StarlingTerm *t) { return row_filled(t, 0); }

/* Nothing has ever been written to this row. `used == 0` is exactly that under
   the extent invariant; a row left with a non-default tail background was
   painted by the client and counts as content. */
static int row_is_blank(const Row *r) { return r->used == 0 && r->tail_bg == 0; }

static void row_fit(Row *r, int cols) {
    if (r->cols == cols) return;
    Cell *n = malloc(sizeof(Cell) * (size_t)cols);
    int keep = r->cols < cols ? r->cols : cols;
    memcpy(n, r->cells, sizeof(Cell) * (size_t)keep);
    Cell b; b.scalar = 32; b.fg = 0; b.bg = 0; b.attrs = 0;   /* .blank */
    for (int i = keep; i < cols; i++) n[i] = b;
    free(r->cells);
    r->cells = n;
    r->cols = cols;
    /* The copied prefix may end in the old row's tail (old tail_bg); only
       past `keep` is the new default-blank tail guaranteed. */
    if (r->used > keep || r->tail_bg != 0) r->used = keep;
    r->tail_bg = 0;
}

/* ---------------------------------------------------------- scrollback ring */

static void sb_push(StarlingTerm *t, Row r) {
    if (t->sb_len == t->sb_cap) {                 /* shouldn't happen; guard */
        row_release(t, &t->sb[t->sb_head]);
        t->sb_head = (t->sb_head + 1) % t->sb_cap;
        t->sb_len--;
    }
    t->sb[(t->sb_head + t->sb_len) % t->sb_cap] = r;
    t->sb_len++;
}

static void sb_trim_to(StarlingTerm *t, int keep) {
    while (t->sb_len > keep) {
        row_release(t, &t->sb[t->sb_head]);
        t->sb_head = (t->sb_head + 1) % t->sb_cap;
        t->sb_len--;
    }
}

static Row *sb_at(const StarlingTerm *t, int i) {
    return &t->sb[(t->sb_head + i) % t->sb_cap];
}

/* --------------------------------------------------------------- lifecycle */

StarlingTerm *starling_term_new(int cols, int rows) {
    StarlingTerm *t = calloc(1, sizeof *t);
    t->cols = cols < 2 ? 2 : cols;
    t->rows = rows < 2 ? 2 : rows;
    t->region_top = 0;
    t->region_bottom = t->rows - 1;
    t->autowrap = 1;
    t->cursor_visible = 1;
    t->csi_cur = -1;
    t->last_col = -1;
    t->blank_bg = 0xFFFFFFFFu;
    t->blank_cols = -1;
    /* Every width span starts as the one scalar_width answers without
       consulting a table. Seeding matters as well as helping: a calloc'd
       entry is the interval [0,0] claiming width 0, and U+0000 would hit it. */
    for (int i = 0; i < WIDTH_SLOTS; i++) {
        /* An EMPTY interval, not a plausible one: `lo > hi` can be satisfied
           by no codepoint, so a cold slot always misses and recomputes. A
           calloc'd or [0,0x2FF]-seeded slot would instead be a live answer
           for the wrong block — U+0000 hitting a zero-width [0,0] is the
           original form of that bug. */
        t->wspan[i].lo = 1; t->wspan[i].hi = 0;
        t->wspan[i].w = 1;  t->wspan[i].ordinary = 1;
    }
    t->grid_cap = t->rows + GRID_SLACK;
    t->grid_base = malloc(sizeof(Row) * (size_t)t->grid_cap);
    t->grid = t->grid_base;
    for (int i = 0; i < t->rows; i++) t->grid[i] = row_default(t);
    t->sb_cap = SB_LIMIT + SB_SLACK + 2;
    t->sb = calloc((size_t)t->sb_cap, sizeof(Row));
    return t;
}

void starling_term_free(StarlingTerm *t) {
    if (!t) return;
    for (int i = 0; i < t->gp_n; i++) free(t->gp[i].cps);
    free(t->gp);
    free(t->gp_map);
    for (int i = 0; i < t->rows; i++) free(t->grid[i].cells);
    free(t->grid_base);
    for (int i = 0; i < t->sb_len; i++) free(sb_at(t, i)->cells);
    free(t->sb);
    if (t->saved_primary) {
        for (int i = 0; i < t->saved_primary_rows; i++) free(t->saved_primary[i].cells);
        free(t->saved_primary);
    }
    free(t->blank_template);
    pool_drain(t);
    free(t->pool);
    free(t);
}

void starling_term_set_response_cb(StarlingTerm *t,
                                   void (*cb)(void *ctx, const char *s), void *ctx) {
    t->response_cb = cb; t->response_ctx = ctx;
}
void starling_term_set_bell_cb(StarlingTerm *t, void (*cb)(void *ctx), void *ctx) {
    t->bell_cb = cb; t->bell_ctx = ctx;
}

int starling_term_cols(const StarlingTerm *t) { return t->cols; }
int starling_term_rows(const StarlingTerm *t) { return t->rows; }
int starling_term_cursor_row(const StarlingTerm *t) { return t->cursor_row; }
int starling_term_cursor_col(const StarlingTerm *t) { return t->cursor_col; }
int starling_term_cursor_visible(const StarlingTerm *t) { return t->cursor_visible; }
int starling_term_app_cursor_keys(const StarlingTerm *t) { return t->app_cursor_keys; }
int starling_term_bracketed_paste(const StarlingTerm *t) { return t->bracketed_paste; }
int starling_term_alt_active(const StarlingTerm *t) { return t->alt_active; }
int starling_term_mouse_tracking(const StarlingTerm *t) { return t->mouse_tracking; }
int starling_term_mouse_sgr(const StarlingTerm *t) { return t->mouse_sgr; }
int starling_term_scrollback_count(const StarlingTerm *t) { return t->sb_len; }
uint64_t starling_term_generation(const StarlingTerm *t) { return t->generation; }

void starling_term_copy_line(const StarlingTerm *t, int abs_index, Cell *out) {
    const Row *r;
    if (abs_index < t->sb_len) r = sb_at(t, abs_index);
    else {
        int g = abs_index - t->sb_len;
        if (g < 0 || g >= t->rows) { memset(out, 0, sizeof(Cell) * (size_t)t->cols); return; }
        r = &t->grid[g];
    }
    int keep = r->cols < t->cols ? r->cols : t->cols;
    memcpy(out, r->cells, sizeof(Cell) * (size_t)keep);
    Cell b; b.scalar = 32; b.fg = 0; b.bg = 0; b.attrs = 0;
    for (int i = keep; i < t->cols; i++) out[i] = b;
}

/* ------------------------------------------------------- character width */

/* Display width of a codepoint: 0 (combining/format), 2 (East Asian
   Wide/Fullwidth and emoji presentation), else 1. Interval tables in the
   spirit of Markus Kuhn's wcwidth, brought forward to cover the emoji
   blocks and the scripts terminals actually meet; the ASCII fast path
   never reaches here, so this only prices the non-ASCII stream. A pair
   {first, last} covers an inclusive range. */

typedef struct { uint32_t first, last; } CpRange;

#include "starling_widths_gen.h"

static int in_ranges(const CpRange *tbl, int n, uint32_t cp) {
    if (cp < tbl[0].first || cp > tbl[n - 1].last) return 0;
    int lo = 0, hi = n - 1;
    while (lo <= hi) {
        int mid = (lo + hi) / 2;
        if (cp < tbl[mid].first) hi = mid - 1;
        else if (cp > tbl[mid].last) lo = mid + 1;
        else return 1;
    }
    return 0;
}

#define IN(tbl, cp) in_ranges(tbl, (int)(sizeof tbl / sizeof *(tbl)), cp)

/* The range containing cp, or the gap between the two that surround it. The
   caller gets the same yes/no answer in_ranges gives, plus the interval over
   which that answer cannot change. */
static int span_in_ranges(const CpRange *tbl, int n, uint32_t cp,
                          uint32_t *lo, uint32_t *hi) {
    int at = -1, a = 0, b = n - 1;
    while (a <= b) {                       /* last entry with first <= cp */
        int m = (a + b) / 2;
        if (tbl[m].first <= cp) { at = m; a = m + 1; }
        else b = m - 1;
    }
    if (at >= 0 && cp <= tbl[at].last) {
        *lo = tbl[at].first; *hi = tbl[at].last;
        return 1;
    }
    *lo = at >= 0 ? tbl[at].last + 1 : 0;
    *hi = at + 1 < n ? tbl[at + 1].first - 1 : 0x10FFFF;
    return 0;
}

static int scalar_width(uint32_t cp) {
    if (cp < 0x0300) return 1;   /* covers all of ASCII + Latin-1 fast */
    if (IN(gen_zero_tbl, cp)) return 0;
    if (IN(gen_wide_tbl, cp)) return 2;
    return 1;
}

/* scalar_width's answer for cp, plus the interval over which that answer
   holds and whether every codepoint in the interval prints as an ordinary
   cell — the two things a run of characters wants to know at once. The
   tables are sorted and mutually disjoint (a codepoint is zero-width or
   wide, never both), so a hit is constant across its own range and a miss is
   constant across the intersection of both gaps. */
static int width_span(uint32_t cp, WidthSpan *s) {
    uint32_t zl, zh, wl, wh;
    if (cp < 0x0300) {           /* the shortcut in scalar_width, as a span */
        s->lo = 0; s->hi = 0x02FF; s->w = 1; s->ordinary = 1;
        return 1;
    }
    if (span_in_ranges(gen_zero_tbl, (int)(sizeof gen_zero_tbl / sizeof *gen_zero_tbl),
                       cp, &zl, &zh)) {
        s->w = 0; s->lo = zl; s->hi = zh;
    } else if (span_in_ranges(gen_wide_tbl, (int)(sizeof gen_wide_tbl / sizeof *gen_wide_tbl),
                              cp, &wl, &wh)) {
        s->w = 2; s->lo = wl; s->hi = wh;
    } else {
        s->w = 1;
        s->lo = zl > wl ? zl : wl;
        s->hi = zh < wh ? zh : wh;
    }
    /* Below U+0300 the answer is the shortcut's, not the tables' ({0x0,0x0}
       is a zero-width range the shortcut overrides), so no span computed
       from the tables may reach down there. */
    if (s->lo < 0x0300) s->lo = 0x0300;
    /* "Ordinary" is what put_scalar_w does with nothing to say: width 0 is
       the whole combining and cluster machinery, and two ranges of width 2
       carry rules of their own — regional indicators pair into a flag, and
       skin-tone modifiers melt into the emoji before them. Excluding them by
       interval rather than per character keeps the test out of the run
       scanner's inner loop. */
    s->ordinary = s->w != 0 &&
                  !(s->lo <= 0x1F1FF && s->hi >= 0x1F1E6) &&
                  !(s->lo <= 0x1F3FF && s->hi >= 0x1F3FB);
    return s->w;
}

/* Same answer as scalar_width, remembering the last few intervals it came
   from, and reporting `ordinary` alongside. A width lookup is two binary
   searches over ~460 intervals and it is the price of every non-ASCII
   character; but text arrives in runs from one script, and the tables' gaps
   are wide (Cyrillic and Greek share the single gap 0x370-0x482, all of CJK
   is one range), so the interval one lookup lands in almost always answers
   the next one too.

   This WAS an eight-entry most-recently-used list, on the reasoning that
   eight holds every script a mixed line touches at once. That is true and
   it is still the wrong structure, because a line does not touch its
   scripts once — it CYCLES them, and a cycle is the one access pattern MRU
   handles worst: each script is evicted to the back exactly in time for its
   next use, so every transition misses, pays both binary searches, and then
   shifts seven entries. Ghostty's own published unicode corpus is that case
   in the extreme — Latin, Cyrillic, Greek, CJK, kana, Hangul, Arabic,
   symbols and emoji, in runs of two to five characters — and a profile put
   43.6% of the whole core inside this function, nearly all of it the miss.

   So: direct-mapped on the codepoint's block instead. Distinct scripts land
   in distinct slots and stay there, so a cycle hits every time, and there is
   no list to search or shift. Collisions cannot give a wrong answer — the
   slot re-checks the interval it stored, and a mismatch just recomputes.
   The spans are derived from the tables at the moment of use, so nothing
   here needs updating when they are regenerated, and there is nothing to
   invalidate: the tables are immutable. */
static int width_lookup(StarlingTerm *t, uint32_t cp, int *ordinary) {
    WidthSpan *s = &t->wspan[WIDTH_SLOT(cp)];
    if (cp >= s->lo && cp <= s->hi) {          /* the slot still answers */
        *ordinary = s->ordinary;
        return s->w;
    }
    int w = width_span(cp, s);                 /* computed straight into it */
    *ordinary = s->ordinary;
    return w;
}

/* --------------------------------------------------- grapheme cluster pool */

/* A cell stores one uint32. A grapheme cluster (ZWJ family, conjunct,
   base + combining marks) stores its full codepoint sequence in an
   interned pool, and the cell's scalar becomes GP_BASE + index — above
   the Unicode range, so plain scalars and references never collide, and
   the 16-byte Cell ABI with Swift is untouched. Interning means entries
   are immutable and live for the terminal's lifetime: rows can scroll
   into history, be recycled, or memmove around without any refcounting.
   Real content repeats a small set of clusters; the pool is capped, and
   past the cap new clusters degrade to their first codepoint — the
   pre-cluster behaviour. */

static uint32_t gp_hash(const uint32_t *cps, int n) {
    uint32_t h = 2166136261u;
    for (int i = 0; i < n; i++) {
        h ^= cps[i];
        h *= 16777619u;
    }
    return h ? h : 1;
}

static int gp_find_slot(const StarlingTerm *t, const uint32_t *cps, int n, uint32_t h);

static void gp_grow_map(StarlingTerm *t) {
    int cap = t->gp_map_cap ? t->gp_map_cap * 2 : 256;
    free(t->gp_map);
    t->gp_map = malloc(sizeof(int) * (size_t)cap);
    for (int i = 0; i < cap; i++) t->gp_map[i] = -1;
    t->gp_map_cap = cap;
    for (int i = 0; i < t->gp_n; i++) {
        GraphemeEntry *e = &t->gp[i];
        int s = gp_find_slot(t, e->cps, e->n, gp_hash(e->cps, e->n));
        t->gp_map[s] = i;
    }
}

/* First free-or-matching slot for the sequence; the map is always kept
   under half full, so the probe terminates. */
static int gp_find_slot(const StarlingTerm *t, const uint32_t *cps, int n, uint32_t h) {
    int mask = t->gp_map_cap - 1;
    int s = (int)(h & (uint32_t)mask);
    for (;;) {
        int idx = t->gp_map[s];
        if (idx < 0) return s;
        GraphemeEntry *e = &t->gp[idx];
        if (e->n == n && memcmp(e->cps, cps, sizeof(uint32_t) * (size_t)n) == 0) return s;
        s = (s + 1) & mask;
    }
}

/* Interned index for the sequence, creating it if new; -1 on cap. */
static int gp_intern(StarlingTerm *t, const uint32_t *cps, int n) {
    if (n < 1 || n > GP_MAX_CPS) return -1;
    if (t->gp_map_cap == 0 || t->gp_n * 2 >= t->gp_map_cap) gp_grow_map(t);
    uint32_t h = gp_hash(cps, n);
    int s = gp_find_slot(t, cps, n, h);
    if (t->gp_map[s] >= 0) return t->gp_map[s];
    if (t->gp_n >= GP_MAX) return -1;
    if (t->gp_n == t->gp_cap) {
        t->gp_cap = t->gp_cap ? t->gp_cap * 2 : 64;
        t->gp = realloc(t->gp, sizeof(GraphemeEntry) * (size_t)t->gp_cap);
    }
    GraphemeEntry *e = &t->gp[t->gp_n];
    e->cps = malloc(sizeof(uint32_t) * (size_t)n);
    memcpy(e->cps, cps, sizeof(uint32_t) * (size_t)n);
    e->n = n;
    t->gp_map[s] = t->gp_n;
    return t->gp_n++;
}

static uint32_t cell_first_cp(const StarlingTerm *t, uint32_t scalar) {
    if (scalar < GP_BASE) return scalar;
    uint32_t idx = scalar - GP_BASE;
    if ((int)idx >= t->gp_n) return 32;
    return t->gp[idx].cps[0];
}

/* ------------------------------------------------------- cursor + printing */

static void line_feed(StarlingTerm *t);
static void scroll_up(StarlingTerm *t, int n);

/* Overwriting one half of a wide pair must not strand the other: a lead
   without its continuation renders a glyph across a cell that now belongs
   to someone else, and a continuation without its lead is a hole that
   claims to belong to a glyph that is gone. Called for a column that is
   about to be written; repairs the NEIGHBOUR, never the target. */
static void unsplit_pair(StarlingTerm *t, Row *rw, int col) {
    (void)t;
    Cell *c = &rw->cells[col];
    if ((c->attrs & STARLING_ATTR_WIDE) && col + 1 < rw->cols) {
        Cell *n = &rw->cells[col + 1];
        if (n->attrs & STARLING_ATTR_WIDE_CONT) {
            n->scalar = 32; n->attrs = 0; n->fg = 0;
        }
    } else if ((c->attrs & STARLING_ATTR_WIDE_CONT) && col > 0) {
        Cell *p = &rw->cells[col - 1];
        if (p->attrs & STARLING_ATTR_WIDE) {
            p->scalar = 32; p->attrs = 0; p->fg = 0;
        }
    }
}

/* Make the last printed cell wide (used by VS16 and by the conjunct and
   Mc rules, whose clusters are capped at two columns). Only possible if
   that cell is still ours, still narrow, and has a column to grow into. */
static void widen_last(StarlingTerm *t) {
    if (t->last_col < 0 || t->last_w != 1) return;
    if (t->last_row < 0 || t->last_row >= t->rows) return;
    Row *rw = &t->grid[t->last_row];
    if (t->last_col + 1 >= t->cols) return;   /* no room at the margin */
    Cell *c = &rw->cells[t->last_col];
    if (c->scalar != t->last_scalar) return;  /* someone wrote over it */
    unsplit_pair(t, rw, t->last_col + 1);
    c->attrs = (uint8_t)(c->attrs | STARLING_ATTR_WIDE);
    Cell *nx = &rw->cells[t->last_col + 1];
    nx->scalar = 0; nx->fg = c->fg; nx->bg = c->bg;
    nx->attrs = (uint8_t)((c->attrs & ~STARLING_ATTR_WIDE) | STARLING_ATTR_WIDE_CONT);
    if (t->last_col + 2 > rw->used) rw->used = t->last_col + 2;
    if (t->cursor_row == t->last_row && t->cursor_col == t->last_col + 1) {
        if (t->last_col + 2 >= t->cols) { t->cursor_col = t->cols - 1; t->wrap_pending = 1; }
        else t->cursor_col = t->last_col + 2;
    }
    t->last_w = 2;
}

/* VS15 asks for text presentation: the wide character just printed
   becomes narrow again, giving its second column back. */
static void narrow_last(StarlingTerm *t) {
    if (t->last_col < 0 || t->last_w != 2) return;
    if (t->last_row < 0 || t->last_row >= t->rows) return;
    Row *rw = &t->grid[t->last_row];
    Cell *c = &rw->cells[t->last_col];
    if (c->scalar != t->last_scalar || !(c->attrs & STARLING_ATTR_WIDE)) return;
    c->attrs = (uint8_t)(c->attrs & ~STARLING_ATTR_WIDE);
    if (t->last_col + 1 < t->cols) {
        Cell *nx = &rw->cells[t->last_col + 1];
        if (nx->attrs & STARLING_ATTR_WIDE_CONT) {
            nx->scalar = 32; nx->attrs = 0; nx->fg = 0;
        }
    }
    if (t->cursor_row == t->last_row) {
        int after_pair = (t->wrap_pending && t->cursor_col == t->cols - 1)
            ? t->cols : t->cursor_col;
        if (after_pair == t->last_col + 2) {
            t->cursor_col = t->last_col + 1;
            t->wrap_pending = 0;
        }
    }
    t->last_w = 1;
}

static int is_regional_indicator(uint32_t v) {
    return v >= 0x1F1E6 && v <= 0x1F1FF;
}

static int is_virama(uint32_t v) {
    return IN(gen_virama_tbl, v);
}

/* Extend the last printed cell's cluster with one more codepoint. The
   cell's scalar becomes (or stays) a pool reference; the cursor does not
   move. Silently a no-op if the cell is gone or the pool is capped —
   the degradation is exactly the pre-cluster behaviour. */
static void append_to_last(StarlingTerm *t, uint32_t v) {
    if (t->last_col < 0 || t->last_row < 0 || t->last_row >= t->rows) return;
    Row *rw = &t->grid[t->last_row];
    if (t->last_col >= rw->cols) return;
    Cell *c = &rw->cells[t->last_col];
    if (c->scalar != t->last_scalar) return;
    uint32_t tmp[GP_MAX_CPS + 1];
    int n = 0;
    if (c->scalar >= GP_BASE) {
        uint32_t idx = c->scalar - GP_BASE;
        if ((int)idx >= t->gp_n) return;
        GraphemeEntry *e = &t->gp[idx];
        if (e->n >= GP_MAX_CPS) return;
        memcpy(tmp, e->cps, sizeof(uint32_t) * (size_t)e->n);
        n = e->n;
    } else {
        tmp[0] = c->scalar; n = 1;
    }
    tmp[n++] = v;
    int idx = gp_intern(t, tmp, n);
    if (idx < 0) return;
    c->scalar = GP_BASE + (uint32_t)idx;
    t->last_scalar = c->scalar;
}

enum { JP_NONE = 0, JP_ZWJ, JP_VIRAMA };

/* `w` is scalar_width(v), taken as a parameter because the feed loop's run
   scanner has already measured the character to decide whether it belonged in
   the run. put_scalar, at the end of this function, is the spelling for every
   other caller. */
static void put_scalar_w(StarlingTerm *t, uint32_t v, int w) {
    /* The joining model mirrors python wcwidth (the library ucs-detect
       grades against) branch for branch — see starling_widths_gen.h for
       the shared tables. In cluster terms: ZWJ swallows the following
       character into the last cell with no width change; a virama joins
       the following consonant and caps the cluster at TWO columns (a
       conjunct is 2 cells wide no matter how many consonants stack); a
       spacing mark (Mc) also makes its cluster 2 columns; a Fitzpatrick
       modifier melts into an emoji base; the second regional indicator
       completes a flag. */
    if (t->join_pending == JP_ZWJ) {
        t->join_pending = JP_NONE;
        if (t->last_col >= 0) {
            append_to_last(t, v);
            return;
        }
    } else if (t->join_pending == JP_VIRAMA && w > 0) {
        t->join_pending = JP_NONE;
        if (t->last_col >= 0) {
            append_to_last(t, v);
            widen_last(t);      /* conjunct: cluster capped at 2 columns */
            return;
        }
    }
    if (w == 0) {
        if (v == 0x200D) {
            /* ZWJ after a virama keeps the virama armed (wcwidth's rule);
               otherwise it arms its own join. */
            if (t->join_pending != JP_VIRAMA && t->last_col >= 0) {
                append_to_last(t, v);
                t->join_pending = JP_ZWJ;
            }
            return;
        }
        if (IN(gen_virama_tbl, v)) {
            if (t->last_col >= 0) {
                append_to_last(t, v);
                t->join_pending = JP_VIRAMA;
            }
            return;
        }
        t->join_pending = JP_NONE;
        if (v == 0xFE0F) {
            /* Emoji presentation: widens only the bases wcwidth widens. */
            if (t->last_col >= 0 && IN(gen_vs16_base_tbl, cell_first_cp(t, t->last_scalar))) {
                append_to_last(t, v);
                widen_last(t);
            } else {
                append_to_last(t, v);
            }
            return;
        }
        if (v == 0xFE0E) {
            if (t->last_col >= 0 && IN(gen_vs15_base_tbl, cell_first_cp(t, t->last_scalar))) {
                append_to_last(t, v);
                narrow_last(t);
            } else {
                append_to_last(t, v);
            }
            return;
        }
        if (t->last_col >= 0 && IN(gen_mc_tbl, v)) {
            /* A spacing combining mark joins its base and the cluster
               becomes two columns. */
            append_to_last(t, v);
            widen_last(t);
            return;
        }
        /* Plain combining mark: joins the cluster, no width change. */
        append_to_last(t, v);
        return;
    }
    t->join_pending = JP_NONE;
    /* Two regional indicators pair into one flag occupying the first
       one's two columns; a third starts a new flag. */
    if (is_regional_indicator(v) && t->last_col >= 0 &&
        t->last_scalar < GP_BASE && is_regional_indicator(t->last_scalar)) {
        append_to_last(t, v);
        t->last_col = -1;
        return;
    }
    /* A Fitzpatrick skin-tone modifier melts into the emoji before it. */
    if (v >= 0x1F3FB && v <= 0x1F3FF && t->last_col >= 0 &&
        IN(gen_emoji_zwj_tbl, cell_first_cp(t, t->last_scalar))) {
        append_to_last(t, v);
        return;
    }
    if (t->wrap_pending) {
        t->wrap_pending = 0;
        if (t->autowrap) { t->cursor_col = 0; line_feed(t); }
    }
    if (t->cursor_row < 0 || t->cursor_row >= t->rows ||
        t->cursor_col < 0 || t->cursor_col >= t->cols) return;
    if (w == 2) {
        /* A wide character needs two columns. At the last column it cannot
           fit: with autowrap it moves whole to the next line (xterm's
           behaviour); without, it is dropped rather than torn in half. */
        if (t->cursor_col >= t->cols - 1) {
            if (!t->autowrap) return;
            t->cursor_col = 0; line_feed(t);
            if (t->cursor_row < 0 || t->cursor_row >= t->rows) return;
        }
        Row *rw = &t->grid[t->cursor_row];
        unsplit_pair(t, rw, t->cursor_col);
        unsplit_pair(t, rw, t->cursor_col + 1);
        Cell *c = &rw->cells[t->cursor_col];
        c->scalar = v; c->fg = t->cur_fg; c->bg = t->cur_bg;
        c->attrs = (uint8_t)(t->cur_attrs | STARLING_ATTR_WIDE);
        Cell *n = &rw->cells[t->cursor_col + 1];
        n->scalar = 0; n->fg = t->cur_fg; n->bg = t->cur_bg;
        n->attrs = (uint8_t)(t->cur_attrs | STARLING_ATTR_WIDE_CONT);
        if (t->cursor_col + 2 > rw->used) rw->used = t->cursor_col + 2;
        t->last_row = t->cursor_row; t->last_col = t->cursor_col;
        t->last_w = 2; t->last_scalar = v;
        if (t->cursor_col + 2 >= t->cols) { t->cursor_col = t->cols - 1; t->wrap_pending = 1; }
        else t->cursor_col += 2;
        return;
    }
    Row *rw = &t->grid[t->cursor_row];
    unsplit_pair(t, rw, t->cursor_col);
    Cell *c = &rw->cells[t->cursor_col];
    c->scalar = v; c->fg = t->cur_fg; c->bg = t->cur_bg; c->attrs = t->cur_attrs;
    if (t->cursor_col >= rw->used) rw->used = t->cursor_col + 1;
    t->last_row = t->cursor_row; t->last_col = t->cursor_col;
    t->last_w = 1; t->last_scalar = v;
    if (t->cursor_col == t->cols - 1) t->wrap_pending = 1;
    else t->cursor_col++;
}

static void put_scalar(StarlingTerm *t, uint32_t v) {
    put_scalar_w(t, v, scalar_width(v));
}

static void line_feed(StarlingTerm *t) {
    t->wrap_pending = 0;
    t->last_col = -1;
    if (t->cursor_row == t->region_bottom) scroll_up(t, 1);
    else if (t->cursor_row < t->rows - 1) t->cursor_row++;
}

static void move_cursor(StarlingTerm *t, int dr, int dc) {
    int r = t->cursor_row + dr, c = t->cursor_col + dc;
    t->cursor_row = r < 0 ? 0 : (r > t->rows - 1 ? t->rows - 1 : r);
    t->cursor_col = c < 0 ? 0 : (c > t->cols - 1 ? t->cols - 1 : c);
    t->wrap_pending = 0;
}

static void set_cursor(StarlingTerm *t, int row, int col) {
    int base  = t->origin_mode ? t->region_top : 0;
    int limit = t->origin_mode ? t->region_bottom : t->rows - 1;
    int r = base + row;
    t->cursor_row = r < base ? base : (r > limit ? limit : r);
    t->cursor_col = col < 0 ? 0 : (col > t->cols - 1 ? t->cols - 1 : col);
    t->wrap_pending = 0;
}

static void save_cursor(StarlingTerm *t) {
    t->saved_cursor_row = t->cursor_row;
    t->saved_cursor_col = t->cursor_col;
    t->saved_fg = t->cur_fg; t->saved_bg = t->cur_bg; t->saved_attrs = t->cur_attrs;
}

static void restore_cursor(StarlingTerm *t) {
    t->cursor_row = t->saved_cursor_row < t->rows - 1 ? t->saved_cursor_row : t->rows - 1;
    t->cursor_col = t->saved_cursor_col < t->cols - 1 ? t->saved_cursor_col : t->cols - 1;
    t->cur_fg = t->saved_fg; t->cur_bg = t->saved_bg; t->cur_attrs = t->saved_attrs;
    t->wrap_pending = 0;
}

/* ------------------------------------------------------------ erase / edit */

static void erase_line(StarlingTerm *t, int mode) {
    if (t->cursor_row < 0 || t->cursor_row >= t->rows) return;
    Row *r = &t->grid[t->cursor_row];
    Cell b = blank_cell(t);
    /* A partial erase whose boundary lands mid-pair must not strand the
       surviving half. Mode 2 clears the whole row — no seam. */
    if (mode == 0 || mode == 1) unsplit_pair(t, r, t->cursor_col);
    if (mode == 0) {
        /* Erase-to-end grows the tail. Backgrounds match: cells past the
           old extent are already these blanks, store only the prefix and
           let the tail reach down to the cursor. Backgrounds differ: the
           full span is written, and the tail can start no earlier than the
           cursor — below it may sit old-background blanks that are content
           now. Memory is byte-identical to the full-width loop either way. */
        if (b.bg == r->tail_bg) {
            int end = r->used > t->cursor_col ? r->used : t->cursor_col;
            for (int c = t->cursor_col; c < end; c++) r->cells[c] = b;
            if (r->used > t->cursor_col) r->used = t->cursor_col;
        } else {
            for (int c = t->cursor_col; c < t->cols; c++) r->cells[c] = b;
            r->used = t->cursor_col;
            r->tail_bg = b.bg;
        }
    } else if (mode == 1) {
        int last = t->cursor_col < t->cols - 1 ? t->cursor_col : t->cols - 1;
        for (int c = 0; c <= last; c++) r->cells[c] = b;
        if (last + 1 > r->used) r->used = last + 1;
    } else if (mode == 2) {
        row_release(t, r); *r = row_blank(t);
    }
}

static void erase_display(StarlingTerm *t, int mode) {
    if (mode == 0) {
        erase_line(t, 0);
        for (int r = t->cursor_row + 1; r < t->rows; r++) {
            row_release(t, &t->grid[r]); t->grid[r] = row_blank(t);
        }
    } else if (mode == 1) {
        erase_line(t, 1);
        for (int r = 0; r < t->cursor_row; r++) {
            row_release(t, &t->grid[r]); t->grid[r] = row_blank(t);
        }
    } else if (mode == 2 || mode == 3) {
        for (int r = 0; r < t->rows; r++) {
            row_release(t, &t->grid[r]); t->grid[r] = row_blank(t);
        }
        if (mode == 3) sb_trim_to(t, 0);
    }
}

static void erase_chars(StarlingTerm *t, int n) {
    if (t->cursor_row < 0 || t->cursor_row >= t->rows) return;
    Row *rw = &t->grid[t->cursor_row];
    Cell b = blank_cell(t);
    int end = t->cursor_col + n; if (end > t->cols) end = t->cols;
    if (end <= t->cursor_col) return;
    unsplit_pair(t, rw, t->cursor_col);
    unsplit_pair(t, rw, end - 1);
    for (int c = t->cursor_col; c < end; c++) rw->cells[c] = b;
    if (end > rw->used) rw->used = end;
}

static void delete_chars(StarlingTerm *t, int n) {
    if (t->cursor_row < 0 || t->cursor_row >= t->rows) return;
    Row *rw = &t->grid[t->cursor_row];
    Cell *line = rw->cells;
    int count = n < t->cols - t->cursor_col ? n : t->cols - t->cursor_col;
    if (count <= 0) return;
    /* Seams: the first deleted cell may be the continuation of a lead
       that survives on the left; the first SURVIVING cell may be the
       continuation of a lead that is being deleted — the survivor then
       has no lead, so it becomes a blank before it shifts into place. */
    unsplit_pair(t, rw, t->cursor_col);
    if (t->cursor_col + count < t->cols &&
        (line[t->cursor_col + count].attrs & STARLING_ATTR_WIDE_CONT)) {
        line[t->cursor_col + count] = blank_cell(t);
    }
    memmove(line + t->cursor_col, line + t->cursor_col + count,
            sizeof(Cell) * (size_t)(t->cols - t->cursor_col - count));
    Cell b = blank_cell(t);
    for (int c = t->cols - count; c < t->cols; c++) line[c] = b;
    rw->used = t->cols - count;
    rw->tail_bg = b.bg;
}

static void insert_chars(StarlingTerm *t, int n) {
    if (t->cursor_row < 0 || t->cursor_row >= t->rows) return;
    Row *rw = &t->grid[t->cursor_row];
    Cell *line = rw->cells;
    int count = n < t->cols - t->cursor_col ? n : t->cols - t->cursor_col;
    if (count <= 0) return;
    /* Seams: shifting right can tear a pair at the cursor (its lead stays,
       the continuation moves) and push a continuation off the end leaving
       its lead at the edge. */
    unsplit_pair(t, rw, t->cursor_col);
    memmove(line + t->cursor_col + count, line + t->cursor_col,
            sizeof(Cell) * (size_t)(t->cols - t->cursor_col - count));
    Cell b = blank_cell(t);
    for (int c = t->cursor_col; c < t->cursor_col + count; c++) line[c] = b;
    if (line[t->cols - 1].attrs & STARLING_ATTR_WIDE) line[t->cols - 1] = b;
    rw->used = t->cols;
}

/* Slide the live window back to the start of its block, so everything that is
   not a scroll can treat grid_base as a plain `rows`-long array. Costs one
   memmove of the window, amortised over GRID_SLACK scrolls. */
static void grid_recenter(StarlingTerm *t) {
    if (t->grid == t->grid_base) return;
    memmove(t->grid_base, t->grid, sizeof(Row) * (size_t)t->rows);
    t->grid = t->grid_base;
}

/* Remove grid row `at`, shifting up, and put `r` in at `to` (to >= at).
 *
 * The whole-screen case — `at == 0 && to == rows-1`, which is what every
 * line feed outside a scroll region does — is a POINTER BUMP, not a move.
 * That case dominates: 01_light_cells is 1.5 M line feeds, and profiling the
 * core on it put 68% of the entire workload inside this function's memmove
 * (1128 bytes of Row per feed, 1.7 GB over the run). Sliding costs one
 * memmove per GRID_SLACK scrolls instead of one per scroll.
 *
 * A scroll REGION still moves rows: sliding would carry the rows outside the
 * region along with it. */
static void grid_rotate_in(StarlingTerm *t, int at, int to, Row r) {
    if (at == 0 && to == t->rows - 1) {
        if (t->grid + t->rows >= t->grid_base + t->grid_cap) grid_recenter(t);
        t->grid++;
        t->grid[to] = r;
        return;
    }
    memmove(&t->grid[at], &t->grid[at + 1], sizeof(Row) * (size_t)(to - at));
    t->grid[to] = r;
}
/* Remove grid row `at`, shifting down, and put `r` in at `to` (to <= at).
 *
 * The mirror image, and it can only slide when the window has already moved
 * forward — which is the case that matters, since scrolling back down is
 * always undoing a scroll up. With no room before the window it falls back to
 * the move rather than growing a second recentre direction for a rare path. */
static void grid_rotate_in_rev(StarlingTerm *t, int at, int to, Row r) {
    if (to == 0 && at == t->rows - 1 && t->grid > t->grid_base) {
        t->grid--;
        t->grid[0] = r;
        return;
    }
    memmove(&t->grid[to + 1], &t->grid[to], sizeof(Row) * (size_t)(at - to));
    t->grid[to] = r;
}

static void scroll_up(StarlingTerm *t, int n) {
    for (int k = 0; k < n; k++) {
        Row removed = t->grid[t->region_top];
        if (!t->alt_active && t->region_top == 0) {
            sb_push(t, removed);
            if (t->sb_len > SB_LIMIT + SB_SLACK) sb_trim_to(t, SB_LIMIT);
        } else {
            row_release(t, &removed);
        }
        grid_rotate_in(t, t->region_top, t->region_bottom, row_blank(t));
    }
}

static void scroll_down(StarlingTerm *t, int n) {
    for (int k = 0; k < n; k++) {
        row_release(t, &t->grid[t->region_bottom]);
        grid_rotate_in_rev(t, t->region_bottom, t->region_top, row_blank(t));
    }
}

static void insert_lines(StarlingTerm *t, int n) {
    if (t->cursor_row < t->region_top || t->cursor_row > t->region_bottom) return;
    int count = t->region_bottom - t->cursor_row + 1;
    if (n < count) count = n;
    for (int k = 0; k < count; k++) {
        row_release(t, &t->grid[t->region_bottom]);
        grid_rotate_in_rev(t, t->region_bottom, t->cursor_row, row_blank(t));
    }
    t->cursor_col = 0;
}

static void delete_lines(StarlingTerm *t, int n) {
    if (t->cursor_row < t->region_top || t->cursor_row > t->region_bottom) return;
    int count = t->region_bottom - t->cursor_row + 1;
    if (n < count) count = n;
    for (int k = 0; k < count; k++) {
        row_release(t, &t->grid[t->cursor_row]);
        grid_rotate_in(t, t->cursor_row, t->region_bottom, row_blank(t));
    }
    t->cursor_col = 0;
}

/* ---------------------------------------------------------------- SGR/mode */

static void sgr(StarlingTerm *t, const int *p, int n) {
    int zero = 0;
    if (n == 0) { p = &zero; n = 1; }
    for (int i = 0; i < n; i++) {
        int v = p[i];
        if (v == 0) { t->cur_fg = 0; t->cur_bg = 0; t->cur_attrs = 0; }
        else if (v == 1) t->cur_attrs |= STARLING_ATTR_BOLD;
        else if (v == 2) t->cur_attrs |= STARLING_ATTR_DIM;
        else if (v == 3) t->cur_attrs |= STARLING_ATTR_ITALIC;
        else if (v == 4) t->cur_attrs |= STARLING_ATTR_UNDERLINE;
        else if (v == 7) t->cur_attrs |= STARLING_ATTR_REVERSE;
        else if (v == 22) t->cur_attrs &= (uint8_t)~(STARLING_ATTR_BOLD | STARLING_ATTR_DIM);
        else if (v == 23) t->cur_attrs &= (uint8_t)~STARLING_ATTR_ITALIC;
        else if (v == 24) t->cur_attrs &= (uint8_t)~STARLING_ATTR_UNDERLINE;
        else if (v == 27) t->cur_attrs &= (uint8_t)~STARLING_ATTR_REVERSE;
        else if (v >= 30 && v <= 37) t->cur_fg = pal_ansi(v - 30, 0);
        else if (v == 39) t->cur_fg = 0;
        else if (v >= 40 && v <= 47) t->cur_bg = pal_ansi(v - 40, 0);
        else if (v == 49) t->cur_bg = 0;
        else if (v >= 90 && v <= 97) t->cur_fg = pal_ansi(v - 90, 1);
        else if (v >= 100 && v <= 107) t->cur_bg = pal_ansi(v - 100, 1);
        else if (v == 38 || v == 48) {
            /* Swift used `i + 2 < count` / `i + 4 < count` — strictly less
               than, so a sequence with exactly the needed params and nothing
               after it is IGNORED. Reproduced deliberately. */
            uint32_t color = 0; int have = 0;
            if (i + 2 < n && p[i + 1] == 5) { color = pal_256(p[i + 2]); i += 2; have = 1; }
            else if (i + 4 < n && p[i + 1] == 2) {
                uint32_t r = p[i+2] < 0 ? 0 : (uint32_t)p[i+2];
                uint32_t g = p[i+3] < 0 ? 0 : (uint32_t)p[i+3];
                uint32_t b = p[i+4] < 0 ? 0 : (uint32_t)p[i+4];
                color = 0xFF000000u | (r << 16) | (g << 8) | b; i += 4; have = 1;
            }
            if (have) { if (v == 38) t->cur_fg = color; else t->cur_bg = color; }
        }
    }
}

static void enter_alt(StarlingTerm *t, int with_cursor) {
    if (t->alt_active) return;
    if (with_cursor) save_cursor(t);
    /* Hand the primary screen over as a plain array — everything that touches
       saved_primary (resize, the refit in exit_alt) indexes it directly. */
    grid_recenter(t);
    t->saved_primary = t->grid_base;
    t->saved_primary_rows = t->rows;
    t->saved_primary_cap = t->grid_cap;
    t->saved_primary_cursor_row = t->cursor_row;
    t->saved_primary_cursor_col = t->cursor_col;
    t->alt_active = 1;
    t->grid_cap = t->rows + GRID_SLACK;
    t->grid_base = malloc(sizeof(Row) * (size_t)t->grid_cap);
    t->grid = t->grid_base;
    for (int i = 0; i < t->rows; i++) t->grid[i] = row_blank(t);
    t->cursor_row = 0; t->cursor_col = 0;
}

static void exit_alt(StarlingTerm *t, int with_cursor) {
    if (!t->alt_active) return;
    t->alt_active = 0;
    if (t->saved_primary) {
        for (int i = 0; i < t->rows; i++) row_release(t, &t->grid[i]);
        free(t->grid_base);
        t->grid_base = t->saved_primary;
        t->grid = t->grid_base;
        t->grid_cap = t->saved_primary_cap;
        t->saved_primary = NULL;
        /* resize() keeps saved_primary fitted to the live rows/cols, so this
           is normally a no-op; it is the equivalent of Swift's _normalizeGrid
           on the restored screen. */
        for (int i = 0; i < t->saved_primary_rows; i++) row_fit(&t->grid[i], t->cols);
        if (t->saved_primary_rows != t->rows) {
            int cap = t->rows + GRID_SLACK;
            Row *g = malloc(sizeof(Row) * (size_t)cap);
            int keep = t->saved_primary_rows < t->rows ? t->saved_primary_rows : t->rows;
            int drop = t->saved_primary_rows - keep;      /* oldest lines go first */
            for (int k = 0; k < drop; k++) row_release(t, &t->grid[k]);
            for (int i = 0; i < keep; i++) g[i] = t->grid[drop + i];
            for (int i = keep; i < t->rows; i++) g[i] = row_default(t);
            free(t->grid_base);
            t->grid_base = g;
            t->grid = g;
            t->grid_cap = cap;
        }
        t->saved_primary_rows = t->rows;
    }
    t->cursor_row = t->saved_primary_cursor_row;
    t->cursor_col = t->saved_primary_cursor_col;
    if (t->cursor_row > t->rows - 1) t->cursor_row = t->rows - 1;
    if (t->cursor_col > t->cols - 1) t->cursor_col = t->cols - 1;
    if (with_cursor) restore_cursor(t);
}

static void set_mode(StarlingTerm *t, const int *p, int n, int on) {
    if (t->csi_private != '?') return;        /* ANSI modes ignored, as before */
    for (int i = 0; i < n; i++) {
        switch (p[i]) {
        case 1: t->app_cursor_keys = on; break;
        case 7: t->autowrap = on; break;
        case 6: t->origin_mode = on; set_cursor(t, 0, 0); break;
        case 25: t->cursor_visible = on; break;
        case 47: case 1047: on ? enter_alt(t, 0) : exit_alt(t, 0); break;
        case 1049: on ? enter_alt(t, 1) : exit_alt(t, 1); break;
        case 1048: on ? save_cursor(t) : restore_cursor(t); break;
        case 2004: t->bracketed_paste = on; break;
        /* Mouse tracking. We report the WHEEL only (see the UI's
           onPointerSignal), which is what makes scrolling work inside a
           full-screen app; the exact tracking flavour does not change how a
           wheel event is encoded, so all three set the same flag. */
        case 1000: case 1002: case 1003: t->mouse_tracking = on; break;
        case 1006: t->mouse_sgr = on; break;
        default: break;  /* blinking, focus reporting… ignored */
        }
    }
}

static void full_reset(StarlingTerm *t) {
    for (int i = 0; i < t->rows; i++) { row_release(t, &t->grid[i]); t->grid[i] = row_default(t); }
    sb_trim_to(t, 0);
    t->cursor_row = 0; t->cursor_col = 0;
    t->cur_fg = 0; t->cur_bg = 0; t->cur_attrs = 0;
    t->region_top = 0; t->region_bottom = t->rows - 1;
    t->autowrap = 1; t->origin_mode = 0; t->wrap_pending = 0;
    t->cursor_visible = 1;
    t->mouse_tracking = 0; t->mouse_sgr = 0;
    if (t->alt_active && t->saved_primary) {
        for (int i = 0; i < t->saved_primary_rows; i++) free(t->saved_primary[i].cells);
        free(t->saved_primary);
    }
    t->alt_active = 0;
    t->saved_primary = NULL;
}

/* ------------------------------------------------------------ CSI dispatch */

static void respond(StarlingTerm *t, const char *s) {
    if (t->response_cb) t->response_cb(t->response_ctx, s);
}

static void soft_reset(StarlingTerm *t) {
    /* DECSTR (CSI ! p): reset modes and attributes, keep screen contents.
       esctest sends it before every unit test. */
    t->cur_fg = 0; t->cur_bg = 0; t->cur_attrs = 0;
    t->region_top = 0; t->region_bottom = t->rows - 1;
    t->origin_mode = 0; t->wrap_pending = 0;
    t->cursor_visible = 1;
    t->app_cursor_keys = 0;
    t->saved_cursor_row = 0; t->saved_cursor_col = 0;
    t->saved_fg = 0; t->saved_bg = 0; t->saved_attrs = 0;
}

static void dispatch_csi(StarlingTerm *t, uint8_t final) {
    const int *ps = t->csi_nums;
    int n = t->csi_count;
    /* Any control between a character and its variation selector breaks
       the fix-up window; real emitters send the pair adjacently. */
    t->last_col = -1;
    /* Swift's p(i, def): an explicit 0 also means "use the default". */
    #define P(i, def) ((i) < n && ps[i] != 0 ? ps[i] : (def))
    int first = n > 0 ? ps[0] : 0;

    if (t->csi_inter) {
        /* An intermediate names a different control; never fall through to
           the plain finals. */
        if (t->csi_inter == '!' && final == 'p') { soft_reset(t); }
        else if (t->csi_inter == '*' && final == 'y') {
            /* DECRQCRA: checksum of a rectangle, the readback esctest's
               screen assertions are built on (VT level 4). Coordinates are
               1-based inclusive; defaults cover the whole screen; the page
               parameter is ignored (one page). The checksum is the NEGATED
               16-bit sum of the character codes — DEC STD 070 as xterm
               implements it (verified against xterm patch 407: a lone 'A'
               reads back 0xFFBF = 0x10000 - 0x41). esctest's --xterm-checksum
               flag must be < 279 so it applies the same negation. */
            int pid = n > 0 ? ps[0] : 0;
            int top  = P(2, 1) - 1, left = P(3, 1) - 1;
            int bot  = P(4, t->rows) - 1, right = P(5, t->cols) - 1;
            if (top < 0) top = 0; if (left < 0) left = 0;
            if (bot > t->rows - 1) bot = t->rows - 1;
            if (right > t->cols - 1) right = t->cols - 1;
            unsigned sum = 0;
            for (int r = top; r <= bot; r++)
                for (int c = left; c <= right && c < t->grid[r].cols; c++)
                    sum += cell_first_cp(t, t->grid[r].cells[c].scalar);
            char buf[48];
            snprintf(buf, sizeof buf, "\x1bP%d!~%04X\x1b\\", pid,
                     (0x10000 - (sum & 0xFFFF)) & 0xFFFF);
            respond(t, buf);
        }
        /* "p (DECSCL), $p (DECRQM), $r (DECCARA)... consumed, unimplemented */
        return;
    }

    switch (final) {
    case 'A': move_cursor(t, -P(0, 1), 0); break;
    case 'B': move_cursor(t,  P(0, 1), 0); break;
    case 'C': move_cursor(t, 0,  P(0, 1)); break;
    case 'D': move_cursor(t, 0, -P(0, 1)); break;
    case 'E': t->cursor_col = 0; move_cursor(t,  P(0, 1), 0); break;
    case 'F': t->cursor_col = 0; move_cursor(t, -P(0, 1), 0); break;
    case 'G': case '`': {
        int c = P(0, 1) - 1;
        t->cursor_col = c < 0 ? 0 : (c > t->cols - 1 ? t->cols - 1 : c);
        t->wrap_pending = 0;
        break;
    }
    case 'd': set_cursor(t, P(0, 1) - 1, t->cursor_col); break;
    case 'H': case 'f': set_cursor(t, P(0, 1) - 1, P(1, 1) - 1); break;
    case 'J': erase_display(t, first); break;
    case 'K': erase_line(t, first); break;
    case 'L': insert_lines(t, P(0, 1)); break;
    case 'M': delete_lines(t, P(0, 1)); break;
    case 'P': delete_chars(t, P(0, 1)); break;
    case '@': insert_chars(t, P(0, 1)); break;
    case 'X': erase_chars(t, P(0, 1)); break;
    case 'S': scroll_up(t, P(0, 1)); break;
    case 'T': scroll_down(t, P(0, 1)); break;
    case 'r': {
        int top = P(0, 1) - 1;
        int bottom = P(1, t->rows) - 1;
        if (top < bottom && bottom < t->rows) { t->region_top = top; t->region_bottom = bottom; }
        else { t->region_top = 0; t->region_bottom = t->rows - 1; }
        set_cursor(t, 0, 0);
        break;
    }
    case 'm': sgr(t, ps, n); break;
    case 'h': set_mode(t, ps, n, 1); break;
    case 'l': set_mode(t, ps, n, 0); break;
    case 'n': {
        if (n > 0 && ps[0] == 5) respond(t, "\033[0n");
        if (n > 0 && ps[0] == 6) {
            char buf[64];
            snprintf(buf, sizeof buf, "\033[%d;%dR", t->cursor_row + 1, t->cursor_col + 1);
            respond(t, buf);
        }
        break;
    }
    case 'c':
        /* DA: which question depends on the private prefix. DA1 (no
           prefix) claims VT102; DA2 (ESC[>c) is the "secondary" identity
           — VT220-class, firmware 10, no options. The prefix must be
           honoured: answering DA2 with the DA1 string hangs probes
           (ucs-detect's identification stalls exactly there). */
        if (t->csi_private == '>') respond(t, "\033[>1;10;0c");
        else if (!t->csi_private) respond(t, "\033[?6c");
        break;
    case 'q':
        /* XTVERSION (ESC[>q): name and version as a DCS. No version
           number — it would rot; tools want the name. */
        if (t->csi_private == '>') respond(t, "\033P>|Starling Terminal\033\\");
        break;
    case 's': save_cursor(t); break;
    case 'u': restore_cursor(t); break;
    default: break;
    }
    #undef P
}

/* ------------------------------------------------------------ state machine */

static void process_byte(StarlingTerm *t, uint8_t b);

static void process_ground(StarlingTerm *t, uint8_t b) {
    switch (b) {
    case 0x07: if (t->bell_cb) t->bell_cb(t->bell_ctx); break;
    case 0x08: if (t->cursor_col > 0) t->cursor_col--; t->wrap_pending = 0; t->last_col = -1; break;
    case 0x09: {
        int c = ((t->cursor_col / 8) + 1) * 8;
        t->cursor_col = c < t->cols - 1 ? c : t->cols - 1;
        break;
    }
    case 0x0A: case 0x0B: case 0x0C: line_feed(t); break;
    case 0x0D: t->cursor_col = 0; t->wrap_pending = 0; break;
    case 0x1B: t->state = ST_ESCAPE; break;
    default:
        if (b >= 0x20) put_scalar(t, b);
        break;
    }
}

static void process_escape(StarlingTerm *t, uint8_t b) {
    t->state = ST_GROUND;
    switch (b) {
    case '[': t->csi_count = 0; t->csi_cur = -1; t->csi_private = 0; t->csi_inter = 0; t->state = ST_CSI; break;
    case ']': t->osc_len = 0; t->state = ST_OSC; break;
    case '7': save_cursor(t); break;
    case '8': restore_cursor(t); break;
    case 'D': line_feed(t); break;
    case 'E': t->cursor_col = 0; line_feed(t); break;
    case 'M':
        if (t->cursor_row == t->region_top) scroll_down(t, 1);
        else if (t->cursor_row > 0) t->cursor_row--;
        break;
    case 'c': full_reset(t); break;
    case '(': case ')': case '*': case '+': case '#': case '%':
        t->state = ST_ESC_INTERMEDIATE; break;
    default: break;
    }
}

static void process_csi(StarlingTerm *t, uint8_t b) {
    if (b >= 0x40 && b <= 0x7E) {
        t->state = ST_GROUND;
        /* Close the parameter in flight; an empty list stays empty. */
        if (t->csi_cur >= 0 || t->csi_count > 0) {
            if (t->csi_count < MAX_PARAMS) t->csi_nums[t->csi_count++] = t->csi_cur < 0 ? 0 : t->csi_cur;
            t->csi_cur = -1;
        }
        dispatch_csi(t, b);
    } else if (b >= 0x30 && b <= 0x39) {
        t->csi_cur = (t->csi_cur < 0 ? 0 : t->csi_cur) * 10 + (b - 0x30);
    } else if (b == 0x3B) {
        if (t->csi_count < MAX_PARAMS) t->csi_nums[t->csi_count++] = t->csi_cur < 0 ? 0 : t->csi_cur;
        t->csi_cur = -1;
    } else if (b >= 0x3C && b <= 0x3F) {
        /* Private parameter prefix — '<', '=', '>' or '?'. Stored as the
           byte itself: '?' selects DEC modes, '>' selects the secondary
           DA / XTVERSION family. Dropping the byte (as this parser once
           did for everything but '?') makes ESC[>c parse as ESC[c, and
           the DA1 answer to a DA2 question hangs any tool that waits for
           a ">"-shaped reply. */
        t->csi_private = b;
    } else if (b >= 0x20 && b <= 0x2F) {
        t->csi_inter = b;
    } else if (b == 0x1B) {
        t->state = ST_ESCAPE;
    }
}

static void finish_osc(StarlingTerm *t) { t->state = ST_GROUND; t->osc_len = 0; }

static void process_byte(StarlingTerm *t, uint8_t b) {
    switch (t->state) {
    case ST_GROUND: process_ground(t, b); break;
    case ST_ESCAPE: process_escape(t, b); break;
    case ST_ESC_INTERMEDIATE: t->state = ST_GROUND; break;
    case ST_CSI: process_csi(t, b); break;
    case ST_OSC:
        if (b == 0x07) finish_osc(t);
        else if (b == 0x1B) t->state = ST_OSC_ESCAPE;
        else if (t->osc_len < OSC_MAX - 1) t->osc[t->osc_len++] = (char)b;
        break;
    case ST_OSC_ESCAPE:
        finish_osc(t);
        if (b != 0x5C) process_byte(t, b);
        break;
    }
}

/* ------------------------------------------------------------------- feed */

static int utf8_len(uint8_t lead) {
    if ((lead & 0xE0) == 0xC0) return 2;
    if ((lead & 0xF0) == 0xE0) return 3;
    if ((lead & 0xF8) == 0xF0) return 4;
    return 1;
}

static int is_scalar(uint32_t v) {          /* mirrors UnicodeScalar(v) == nil */
    if (v > 0x10FFFF) return 0;
    if (v >= 0xD800 && v <= 0xDFFF) return 0;
    return 1;
}

/* One scalar from the `len` bytes at `p`, which the caller has already
   confirmed are all present. Malformed input — a lead byte utf8_len could not
   classify, a bad continuation byte, a surrogate, a value past U+10FFFF —
   yields U+FFFD, and the caller consumes all `len` bytes either way, so a
   truncated sequence swallows the byte after it. Both of those, and the
   absence of an overlong check, are the behaviour the per-character loop has
   always had and the differential harness pins; this is that code lifted out
   so the run scanner can share it, not a new decoder. */
static uint32_t utf8_decode(const uint8_t *p, int len) {
    uint32_t v;
    switch (len) {
    case 2: v = (uint32_t)(p[0] & 0x1F); break;
    case 3: v = (uint32_t)(p[0] & 0x0F); break;
    case 4: v = (uint32_t)(p[0] & 0x07); break;
    default: return 0xFFFD;
    }
    for (int k = 1; k < len; k++) {
        if ((p[k] & 0xC0) != 0x80) return 0xFFFD;
        v = (v << 6) | (uint32_t)(p[k] & 0x3F);
    }
    return is_scalar(v) ? v : 0xFFFD;
}

/* How many scalars the non-ASCII run path decodes before committing. A run
   stops at the right margin regardless, so this only bites on grids wider
   than 256 columns, and then only by splitting one run into two. */
#define UTF8_RUN_MAX 256

/* In that buffer, and nowhere else, the top bit tags a two-column scalar:
   scalars stop at U+10FFFF, and the tag is stripped before the value reaches
   a cell. Carrying the width beside the scalar is what lets one run mix
   widths without measuring anything twice. */
#define RUN_WIDE 0x80000000u

/* Defined below the feed loop, deliberately — see the comment there. */
static int feed_ordinary_run(StarlingTerm *t, const uint8_t *input, size_t count,
                             size_t *ip, uint32_t v, int w, int ordinary);

void starling_term_feed(StarlingTerm *t, const uint8_t *bytes, size_t n) {
    const uint8_t *input = bytes;
    size_t count = n;
    uint8_t *joined = NULL;

    if (t->utf8_pending_len > 0) {
        joined = malloc((size_t)t->utf8_pending_len + n);
        memcpy(joined, t->utf8_pending, (size_t)t->utf8_pending_len);
        memcpy(joined + t->utf8_pending_len, bytes, n);
        input = joined;
        count = (size_t)t->utf8_pending_len + n;
    }
    t->utf8_pending_len = 0;

    size_t i = 0;
    while (i < count) {
        uint8_t b = input[i];

        /* Fast path: a run of printable ASCII into the current row. Kept
           because it is still a win here (one bounds computation and a tight
           store loop), though nothing like as load-bearing as in Swift, where
           it existed to amortise exclusivity and COW checks. */
        if (t->state == ST_GROUND && !t->wrap_pending &&
            b >= 0x20 && b < 0x7F &&
            t->cursor_row >= 0 && t->cursor_row < t->rows && t->cursor_col < t->cols) {
            size_t limit = i + (size_t)(t->cols - t->cursor_col);
            if (limit > count) limit = count;
            size_t end = i;
            while (end < limit) {
                uint8_t x = input[end];
                if (x < 0x20 || x >= 0x7F) break;
                end++;
            }
            size_t run = end - i;
            if (run > 0) {
                Row *rw = &t->grid[t->cursor_row];
                Cell *row = rw->cells;
                int start = t->cursor_col;
                /* Pairs strictly inside the run are overwritten whole; only
                   the run's two edges can tear one. Two checks, not per-cell
                   work — the fast path stays a tight store loop. */
                unsplit_pair(t, rw, start);
                unsplit_pair(t, rw, start + (int)run - 1);
                uint32_t fg = t->cur_fg, bg = t->cur_bg; uint8_t at = t->cur_attrs;
                for (size_t k = 0; k < run; k++) {
                    Cell *c = &row[start + (int)k];
                    c->scalar = input[i + k]; c->fg = fg; c->bg = bg; c->attrs = at;
                }
                if (start + (int)run > rw->used) rw->used = start + (int)run;
                t->last_row = t->cursor_row; t->last_col = start + (int)run - 1;
                t->last_w = 1; t->last_scalar = input[i + run - 1];
                if (start + (int)run >= t->cols) { t->cursor_col = t->cols - 1; t->wrap_pending = 1; }
                else t->cursor_col = start + (int)run;
                i = end;
                continue;
            }
        }

        if (t->state == ST_GROUND && b >= 0x80) {
            int len = utf8_len(b);
            if (i + (size_t)len > count) {
                int keep = (int)(count - i);
                if (keep > 4) keep = 4;
                memcpy(t->utf8_pending, input + i, (size_t)keep);
                t->utf8_pending_len = keep;
                break;
            }
            uint32_t v = utf8_decode(input + i, len);
            int ordinary, w = width_lookup(t, v, &ordinary);
            i += (size_t)len;

            /* Fast path 2: a run of ORDINARY scalars — the ones put_scalar_w
               merely stores and steps the cursor over — committed the way the
               ASCII run above is. width_lookup decides ordinariness by
               interval: width 0 is the whole combining and cluster machinery,
               and regional indicators and skin-tone modifiers reach back into
               the cell already printed, so all of those stay on put_scalar_w,
               which remains the only place those rules live. What is left is
               one or two columns of plain storage, so a run may mix widths —
               and it must: one character in six of the unicode benchmark is
               CJK or emoji, and ending a run at each of them leaves runs
               about five characters long, too short to amortise a commit.

               Only the cursor's own state has to be rechecked: a run cannot
               start mid-wrap or mid-join, and it stops at the right margin,
               so no wrap — and so no scroll, and so no scroll region — can
               happen inside one. ASCII printables ride along inside a run
               rather than starting one; mixed text ("héllo wörld Привет") is
               otherwise a dozen two- and three-character runs each paying a
               full commit, while a run that begins with ASCII still belongs
               to the path above. */
            if (feed_ordinary_run(t, input, count, &i, v, w, ordinary)) continue;
            put_scalar_w(t, v, w);
            continue;
        }

        process_byte(t, b);
        i++;
    }
    t->generation++;
    free(joined);
}

/* The body of fast path 2, out of line. It is only reachable for a byte >=
   0x80, but leaving it inside the feed loop cost the streams that never get
   there: `cat 03_sgr_fg` measured 0.392 -> 0.444 s and dense_cells 0.109 ->
   0.113 with it inlined, on a workload whose every byte is ASCII. The loop
   around it is small and extremely hot, and this is ~70 lines with a 256-entry
   scratch array; the win is in keeping that out of it. Runs average 88
   characters, so one call per run costs nothing measurable.

   Returns 1 when the run was committed (the caller's `i` has been advanced
   past it), 0 when the character is not eligible and the caller should print
   it the ordinary way. */
static int feed_ordinary_run(StarlingTerm *t, const uint8_t *input, size_t count,
                             size_t *ip, uint32_t v, int w, int ordinary) {
    size_t i = *ip;
    if (ordinary && !t->wrap_pending && t->join_pending == JP_NONE &&
        t->cursor_row >= 0 && t->cursor_row < t->rows &&
        t->cursor_col >= 0 && t->cursor_col + w <= t->cols) {
                uint32_t run[UTF8_RUN_MAX];
                int cap = t->cols - t->cursor_col;   /* columns, not characters */
                int used = w, n = 1, tail = 0;
                run[0] = v | (w == 2 ? RUN_WIDE : 0);
                while (n < UTF8_RUN_MAX && used < cap && i < count) {
                    uint8_t x = input[i];
                    int adv;
                    if (x < 0x80) {
                        if (x < 0x20 || x >= 0x7F) break;   /* the state machine's */
                        v = x; w = 1; adv = 1;
                    } else {
                        adv = utf8_len(x);
                        /* A sequence straddling the end of this feed belongs
                           to the pending stash above; stop and let the next
                           turn of the loop hand it over intact. */
                        if (i + (size_t)adv > count) break;
                        v = utf8_decode(input + i, adv);
                        w = width_lookup(t, v, &ordinary);
                        /* Not ours: consume it here and print it below, so
                           that the character which ended the run is not
                           decoded and measured a second time. */
                        if (!ordinary) { i += (size_t)adv; tail = 1; break; }
                        /* A wide character with one column left does not go
                           here at all — it wraps whole, or is dropped with
                           autowrap off. Leave it to put_scalar_w. */
                        if (used + w > cap) break;
                    }
                    run[n++] = v | (w == 2 ? RUN_WIDE : 0);
                    used += w;
                    i += (size_t)adv;
                }

                Row *rw = &t->grid[t->cursor_row];
                Cell *row = rw->cells;
                int start = t->cursor_col;
                /* As in the ASCII path: every column from `start` to the last
                   one written is overwritten whole, so only the two edges can
                   tear an existing pair. */
                unsplit_pair(t, rw, start);
                unsplit_pair(t, rw, start + used - 1);
                uint32_t fg = t->cur_fg, bg = t->cur_bg; uint8_t at = t->cur_attrs;
                int col = start;
                for (int k = 0; k < n; k++) {
                    Cell *c = &row[col];
                    c->fg = fg; c->bg = bg;
                    if (run[k] & RUN_WIDE) {
                        c->scalar = run[k] & ~RUN_WIDE;
                        c->attrs = (uint8_t)(at | STARLING_ATTR_WIDE);
                        Cell *nx = &row[col + 1];
                        nx->scalar = 0; nx->fg = fg; nx->bg = bg;
                        nx->attrs = (uint8_t)(at | STARLING_ATTR_WIDE_CONT);
                        col += 2;
                    } else {
                        c->scalar = run[k]; c->attrs = at;
                        col++;
                    }
                }
                if (col > rw->used) rw->used = col;
                t->last_row = t->cursor_row;
                t->last_w = (run[n - 1] & RUN_WIDE) ? 2 : 1;
                t->last_col = col - t->last_w;
                t->last_scalar = run[n - 1] & ~RUN_WIDE;
                if (col >= t->cols) { t->cursor_col = t->cols - 1; t->wrap_pending = 1; }
                else t->cursor_col = col;
                if (tail) put_scalar_w(t, v, w);
                *ip = i;
                return 1;
    }
    *ip = i;
    return 0;
}

/* ----------------------------------------------------------------- resize */

void starling_term_resize(StarlingTerm *t, int new_cols, int new_rows) {
    if (new_cols < 2) new_cols = 2;
    if (new_rows < 2) new_rows = 2;
    if (new_cols == t->cols && new_rows == t->rows) return;

    /* Everything below indexes the grid as a plain array and reallocs it, so
       flatten the scroll window first — while `t->rows` still describes it. */
    grid_recenter(t);

    int old_rows = t->rows;
    t->cols = new_cols;
    t->rows = new_rows;
    t->region_top = 0;
    t->region_bottom = t->rows - 1;

    /* Fit existing rows to the new width. */
    for (int i = 0; i < old_rows; i++) row_fit(&t->grid[i], t->cols);

    if (new_rows > old_rows) {
        t->grid_cap = new_rows + GRID_SLACK;
        t->grid_base = realloc(t->grid_base, sizeof(Row) * (size_t)t->grid_cap);
        t->grid = t->grid_base;
        for (int i = old_rows; i < new_rows; i++) t->grid[i] = row_default(t);
    } else if (new_rows < old_rows) {
        int drop = old_rows - new_rows;

        /* Reclaim untouched rows below the cursor before evicting anything off
           the top. Growing appends blank rows at the bottom, so without this
           the two directions are not inverses: a grow/shrink round trip at the
           same size — every switch between tiled and floating panes, and every
           window resize that undoes an earlier one — scrolls one line of real
           output out of view per row previously grown, while blank rows sit
           under the cursor. A pane holding a few lines near the top loses all
           of them at once and reads as a repaint bug. */
        int live = old_rows;
        while (drop > 0 && live - 1 > t->cursor_row && row_is_blank(&t->grid[live - 1])) {
            row_release(t, &t->grid[live - 1]);
            live--;
            drop--;
        }

        for (int k = 0; k < drop; k++) {
            Row removed = t->grid[0];
            if (!t->alt_active) {
                sb_push(t, removed);
                if (t->sb_len > SB_LIMIT) sb_trim_to(t, SB_LIMIT);
            } else {
                row_release(t, &removed);
            }
            memmove(&t->grid[0], &t->grid[1], sizeof(Row) * (size_t)(live - 1 - k));
            if (t->cursor_row > 0) t->cursor_row--;
        }
        t->grid_cap = new_rows + GRID_SLACK;
        t->grid_base = realloc(t->grid_base, sizeof(Row) * (size_t)t->grid_cap);
        t->grid = t->grid_base;
    }

    if (t->saved_primary) {
        for (int i = 0; i < t->saved_primary_rows; i++) row_fit(&t->saved_primary[i], t->cols);
        if (t->saved_primary_rows < t->rows) {
            t->saved_primary_cap = t->rows + GRID_SLACK;
            t->saved_primary = realloc(t->saved_primary,
                                       sizeof(Row) * (size_t)t->saved_primary_cap);
            for (int i = t->saved_primary_rows; i < t->rows; i++)
                t->saved_primary[i] = row_default(t);
        } else if (t->saved_primary_rows > t->rows) {
            int drop = t->saved_primary_rows - t->rows;
            for (int k = 0; k < drop; k++) row_release(t, &t->saved_primary[k]);
            memmove(&t->saved_primary[0], &t->saved_primary[drop],
                    sizeof(Row) * (size_t)t->rows);
            t->saved_primary_cap = t->rows + GRID_SLACK;
            t->saved_primary = realloc(t->saved_primary,
                                       sizeof(Row) * (size_t)t->saved_primary_cap);
        }
        t->saved_primary_rows = t->rows;
    }

    if (t->cursor_row > t->rows - 1) t->cursor_row = t->rows - 1;
    if (t->cursor_col > t->cols - 1) t->cursor_col = t->cols - 1;
    t->wrap_pending = 0;
    t->generation++;
}

/* UTF-8 of a cell's full content. A plain scalar encodes directly; a
   cluster reference expands to its interned sequence. Returns bytes
   written (no terminator), 0 for an empty/invalid cell. */
int starling_term_cell_text(const StarlingTerm *t, uint32_t scalar, char *buf, int cap) {
    const uint32_t one = scalar;
    const uint32_t *cps = &one;
    int n = 1;
    if (scalar >= GP_BASE) {
        uint32_t idx = scalar - GP_BASE;
        if ((int)idx >= t->gp_n) return 0;
        cps = t->gp[idx].cps;
        n = t->gp[idx].n;
    } else if (scalar == 0) {
        return 0;
    }
    int out = 0;
    for (int i = 0; i < n; i++) {
        uint32_t c = cps[i];
        if (c < 0x80) {
            if (out + 1 > cap) break;
            buf[out++] = (char)c;
        } else if (c < 0x800) {
            if (out + 2 > cap) break;
            buf[out++] = (char)(0xC0 | (c >> 6));
            buf[out++] = (char)(0x80 | (c & 0x3F));
        } else if (c < 0x10000) {
            if (out + 3 > cap) break;
            buf[out++] = (char)(0xE0 | (c >> 12));
            buf[out++] = (char)(0x80 | ((c >> 6) & 0x3F));
            buf[out++] = (char)(0x80 | (c & 0x3F));
        } else {
            if (out + 4 > cap) break;
            buf[out++] = (char)(0xF0 | (c >> 18));
            buf[out++] = (char)(0x80 | ((c >> 12) & 0x3F));
            buf[out++] = (char)(0x80 | ((c >> 6) & 0x3F));
            buf[out++] = (char)(0x80 | (c & 0x3F));
        }
    }
    return out;
}
