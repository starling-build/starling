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

struct StarlingTerm {
    int cols, rows;

    Row *grid;                 /* rows entries */
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
    Row *saved_primary;        /* NULL when not in alt screen */
    int  saved_primary_rows;
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
    t->grid = malloc(sizeof(Row) * (size_t)t->rows);
    for (int i = 0; i < t->rows; i++) t->grid[i] = row_default(t);
    t->sb_cap = SB_LIMIT + SB_SLACK + 2;
    t->sb = calloc((size_t)t->sb_cap, sizeof(Row));
    return t;
}

void starling_term_free(StarlingTerm *t) {
    if (!t) return;
    for (int i = 0; i < t->rows; i++) free(t->grid[i].cells);
    free(t->grid);
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

static const CpRange zero_width_tbl[] = {
    {0x0300,0x036F},{0x0483,0x0489},{0x0591,0x05BD},{0x05BF,0x05BF},
    {0x05C1,0x05C2},{0x05C4,0x05C5},{0x05C7,0x05C7},{0x0610,0x061A},
    {0x064B,0x065F},{0x0670,0x0670},{0x06D6,0x06DC},{0x06DF,0x06E4},
    {0x06E7,0x06E8},{0x06EA,0x06ED},{0x0711,0x0711},{0x0730,0x074A},
    {0x07A6,0x07B0},{0x07EB,0x07F3},{0x07FD,0x07FD},{0x0816,0x0819},
    {0x081B,0x0823},{0x0825,0x0827},{0x0829,0x082D},{0x0859,0x085B},
    {0x08D3,0x08E1},{0x08E3,0x0902},{0x093A,0x093A},{0x093C,0x093C},
    {0x0941,0x0948},{0x094D,0x094D},{0x0951,0x0957},{0x0962,0x0963},
    {0x0981,0x0981},{0x09BC,0x09BC},{0x09C1,0x09C4},{0x09CD,0x09CD},
    {0x09E2,0x09E3},{0x09FE,0x09FE},{0x0A01,0x0A02},{0x0A3C,0x0A3C},
    {0x0A41,0x0A42},{0x0A47,0x0A48},{0x0A4B,0x0A4D},{0x0A51,0x0A51},
    {0x0A70,0x0A71},{0x0A75,0x0A75},{0x0A81,0x0A82},{0x0ABC,0x0ABC},
    {0x0AC1,0x0AC5},{0x0AC7,0x0AC8},{0x0ACD,0x0ACD},{0x0AE2,0x0AE3},
    {0x0AFA,0x0AFF},{0x0B01,0x0B01},{0x0B3C,0x0B3C},{0x0B3F,0x0B3F},
    {0x0B41,0x0B44},{0x0B4D,0x0B4D},{0x0B55,0x0B56},{0x0B62,0x0B63},
    {0x0B82,0x0B82},{0x0BC0,0x0BC0},{0x0BCD,0x0BCD},{0x0C00,0x0C00},
    {0x0C04,0x0C04},{0x0C3E,0x0C40},{0x0C46,0x0C48},{0x0C4A,0x0C4D},
    {0x0C55,0x0C56},{0x0C62,0x0C63},{0x0C81,0x0C81},{0x0CBC,0x0CBC},
    {0x0CBF,0x0CBF},{0x0CC6,0x0CC6},{0x0CCC,0x0CCD},{0x0CE2,0x0CE3},
    {0x0D00,0x0D01},{0x0D3B,0x0D3C},{0x0D41,0x0D44},{0x0D4D,0x0D4D},
    {0x0D62,0x0D63},{0x0D81,0x0D81},{0x0DCA,0x0DCA},{0x0DD2,0x0DD4},
    {0x0DD6,0x0DD6},{0x0E31,0x0E31},{0x0E34,0x0E3A},{0x0E47,0x0E4E},
    {0x0EB1,0x0EB1},{0x0EB4,0x0EBC},{0x0EC8,0x0ECD},{0x0F18,0x0F19},
    {0x0F35,0x0F35},{0x0F37,0x0F37},{0x0F39,0x0F39},{0x0F71,0x0F7E},
    {0x0F80,0x0F84},{0x0F86,0x0F87},{0x0F8D,0x0F97},{0x0F99,0x0FBC},
    {0x0FC6,0x0FC6},{0x102D,0x1030},{0x1032,0x1037},{0x1039,0x103A},
    {0x103D,0x103E},{0x1058,0x1059},{0x105E,0x1060},{0x1071,0x1074},
    {0x1082,0x1082},{0x1085,0x1086},{0x108D,0x108D},{0x109D,0x109D},
    /* Hangul jungseong/jongseong combine into the preceding choseong;
       terminals give them zero columns (Kuhn's convention). */
    {0x1160,0x11FF},
    {0x135D,0x135F},{0x1712,0x1714},{0x1732,0x1734},{0x1752,0x1753},
    {0x1772,0x1773},{0x17B4,0x17B5},{0x17B7,0x17BD},{0x17C6,0x17C6},
    {0x17C9,0x17D3},{0x17DD,0x17DD},{0x180B,0x180D},{0x1885,0x1886},
    {0x18A9,0x18A9},{0x1920,0x1922},{0x1927,0x1928},{0x1932,0x1932},
    {0x1939,0x193B},{0x1A17,0x1A18},{0x1A1B,0x1A1B},{0x1A56,0x1A56},
    {0x1A58,0x1A5E},{0x1A60,0x1A60},{0x1A62,0x1A62},{0x1A65,0x1A6C},
    {0x1A73,0x1A7C},{0x1A7F,0x1A7F},{0x1AB0,0x1ACE},{0x1B00,0x1B03},
    {0x1B34,0x1B34},{0x1B36,0x1B3A},{0x1B3C,0x1B3C},{0x1B42,0x1B42},
    {0x1B6B,0x1B73},{0x1B80,0x1B81},{0x1BA2,0x1BA5},{0x1BA8,0x1BA9},
    {0x1BAB,0x1BAD},{0x1BE6,0x1BE6},{0x1BE8,0x1BE9},{0x1BED,0x1BED},
    {0x1BEF,0x1BF1},{0x1C2C,0x1C33},{0x1C36,0x1C37},{0x1CD0,0x1CD2},
    {0x1CD4,0x1CE0},{0x1CE2,0x1CE8},{0x1CED,0x1CED},{0x1CF4,0x1CF4},
    {0x1CF8,0x1CF9},{0x1DC0,0x1DFF},{0x200B,0x200F},{0x202A,0x202E},
    {0x2060,0x2064},{0x20D0,0x20F0},{0x2CEF,0x2CF1},{0x2D7F,0x2D7F},
    {0x2DE0,0x2DFF},{0xA66F,0xA672},{0xA674,0xA67D},{0xA69E,0xA69F},
    {0xA6F0,0xA6F1},{0xA802,0xA802},{0xA806,0xA806},{0xA80B,0xA80B},
    {0xA825,0xA826},{0xA82C,0xA82C},{0xA8C4,0xA8C5},{0xA8E0,0xA8F1},
    {0xA8FF,0xA8FF},{0xA926,0xA92D},{0xA947,0xA951},{0xA980,0xA982},
    {0xA9B3,0xA9B3},{0xA9B6,0xA9B9},{0xA9BC,0xA9BD},{0xA9E5,0xA9E5},
    {0xAA29,0xAA2E},{0xAA31,0xAA32},{0xAA35,0xAA36},{0xAA43,0xAA43},
    {0xAA4C,0xAA4C},{0xAA7C,0xAA7C},{0xAAB0,0xAAB0},{0xAAB2,0xAAB4},
    {0xAAB7,0xAAB8},{0xAABE,0xAABF},{0xAAC1,0xAAC1},{0xAAEC,0xAAED},
    {0xAAF6,0xAAF6},{0xABE5,0xABE5},{0xABE8,0xABE8},{0xABED,0xABED},
    {0xFB1E,0xFB1E},{0xFE00,0xFE0F},{0xFE20,0xFE2F},{0xFEFF,0xFEFF},
    {0x101FD,0x101FD},{0x102E0,0x102E0},{0x10376,0x1037A},
    {0x10A01,0x10A03},{0x10A05,0x10A06},{0x10A0C,0x10A0F},
    {0x10A38,0x10A3A},{0x10A3F,0x10A3F},{0x11001,0x11001},
    {0x11038,0x11046},{0x1D165,0x1D169},{0x1D16D,0x1D172},
    {0x1D17B,0x1D182},{0x1D185,0x1D18B},{0x1D1AA,0x1D1AD},
    {0x1D242,0x1D244},{0xE0001,0xE0001},{0xE0020,0xE007F},
    {0xE0100,0xE01EF},
};

static const CpRange wide_tbl[] = {
    {0x1100,0x115F},{0x231A,0x231B},{0x2329,0x232A},{0x23E9,0x23EC},
    {0x23F0,0x23F0},{0x23F3,0x23F3},{0x25FD,0x25FE},{0x2614,0x2615},
    {0x2630,0x2637},{0x2648,0x2653},{0x267F,0x267F},{0x268A,0x268F},
    {0x2693,0x2693},{0x26A1,0x26A1},
    {0x26AA,0x26AB},{0x26BD,0x26BE},{0x26C4,0x26C5},{0x26CE,0x26CE},
    {0x26D4,0x26D4},{0x26EA,0x26EA},{0x26F2,0x26F3},{0x26F5,0x26F5},
    {0x26FA,0x26FA},{0x26FD,0x26FD},{0x2705,0x2705},{0x270A,0x270B},
    {0x2728,0x2728},{0x274C,0x274C},{0x274E,0x274E},{0x2753,0x2755},
    {0x2757,0x2757},{0x2795,0x2797},{0x27B0,0x27B0},{0x27BF,0x27BF},
    {0x2B1B,0x2B1C},{0x2B50,0x2B50},{0x2B55,0x2B55},{0x2E80,0x2E99},
    {0x2E9B,0x2EF3},{0x2F00,0x2FD5},{0x2FF0,0x2FFF},{0x3000,0x303E},
    {0x3041,0x3096},{0x3099,0x30FF},{0x3105,0x312F},{0x3131,0x318E},
    {0x3190,0x31E5},{0x31EF,0x321E},{0x3220,0x3247},{0x3250,0x4DBF},
    {0x4E00,0xA48C},{0xA490,0xA4C6},{0xA960,0xA97C},{0xAC00,0xD7A3},
    {0xF900,0xFAFF},{0xFE10,0xFE19},{0xFE30,0xFE52},{0xFE54,0xFE66},
    {0xFE68,0xFE6B},{0xFF00,0xFF60},{0xFFE0,0xFFE6},
    {0x16FE0,0x16FE4},{0x17000,0x187F7},{0x18800,0x18CD5},
    {0x18D00,0x18D08},{0x1AFF0,0x1AFFF},{0x1B000,0x1B152},
    {0x1B164,0x1B167},{0x1B170,0x1B2FB},{0x1F004,0x1F004},
    {0x1F0CF,0x1F0CF},{0x1F18E,0x1F18E},{0x1F191,0x1F19A},
    {0x1F1E6,0x1F1FF},
    {0x1F200,0x1F202},{0x1F210,0x1F23B},{0x1F240,0x1F248},
    {0x1F250,0x1F251},{0x1F260,0x1F265},{0x1F300,0x1F320},
    {0x1F32D,0x1F335},{0x1F337,0x1F37C},{0x1F37E,0x1F393},
    {0x1F3A0,0x1F3CA},{0x1F3CF,0x1F3D3},{0x1F3E0,0x1F3F0},
    {0x1F3F4,0x1F3F4},{0x1F3F8,0x1F43E},{0x1F440,0x1F440},
    {0x1F442,0x1F4FC},{0x1F4FF,0x1F53D},{0x1F54B,0x1F54E},
    {0x1F550,0x1F567},{0x1F57A,0x1F57A},{0x1F595,0x1F596},
    {0x1F5A4,0x1F5A4},{0x1F5FB,0x1F64F},{0x1F680,0x1F6C5},
    {0x1F6CC,0x1F6CC},{0x1F6D0,0x1F6D2},{0x1F6D5,0x1F6D7},
    {0x1F6DC,0x1F6DF},{0x1F6EB,0x1F6EC},{0x1F6F4,0x1F6FC},
    {0x1F7E0,0x1F7EB},{0x1F7F0,0x1F7F0},{0x1F90C,0x1F93A},
    {0x1F93C,0x1F945},{0x1F947,0x1F9FF},{0x1FA70,0x1FA7C},
    {0x1FA80,0x1FA88},{0x1FA90,0x1FABD},{0x1FABF,0x1FAC5},
    {0x1FACE,0x1FADB},{0x1FAE0,0x1FAE8},{0x1FAF0,0x1FAF8},
    {0x20000,0x2FFFD},{0x30000,0x3FFFD},
};

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

static int scalar_width(uint32_t cp) {
    if (cp < 0x0300) return 1;   /* covers all of ASCII + Latin-1 fast */
    if (in_ranges(zero_width_tbl, (int)(sizeof zero_width_tbl / sizeof *zero_width_tbl), cp)) return 0;
    if (in_ranges(wide_tbl, (int)(sizeof wide_tbl / sizeof *wide_tbl), cp)) return 2;
    return 1;
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

/* VS16 asks for emoji presentation: the character just printed becomes
   wide. Only possible if that cell is still ours, still narrow, and has a
   column to grow into. */
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

static void put_scalar(StarlingTerm *t, uint32_t v) {
    int w = scalar_width(v);
    if (w == 0) {
        /* Combining marks and ZWJ take no columns and are not stored —
           cells hold one scalar, so the base renders unaccented while the
           CURSOR arithmetic every TUI aligns by stays exact. The two
           variation selectors are honoured as retroactive width fix-ups.
           Grapheme storage is a renderer-model change for later. */
        if (v == 0xFE0F) widen_last(t);
        else if (v == 0xFE0E) narrow_last(t);
        return;
    }
    /* Two regional indicators pair into one flag occupying the first
       one's two columns; a third starts a new flag. */
    if (is_regional_indicator(v) && t->last_col >= 0 &&
        is_regional_indicator(t->last_scalar)) {
        t->last_col = -1;
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

/* Remove grid row `at`, shifting up, and put `r` in at `to` (to >= at). */
static void grid_rotate_in(StarlingTerm *t, int at, int to, Row r) {
    memmove(&t->grid[at], &t->grid[at + 1], sizeof(Row) * (size_t)(to - at));
    t->grid[to] = r;
}
/* Remove grid row `at`, shifting down, and put `r` in at `to` (to <= at). */
static void grid_rotate_in_rev(StarlingTerm *t, int at, int to, Row r) {
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
    t->saved_primary = t->grid;
    t->saved_primary_rows = t->rows;
    t->saved_primary_cursor_row = t->cursor_row;
    t->saved_primary_cursor_col = t->cursor_col;
    t->alt_active = 1;
    t->grid = malloc(sizeof(Row) * (size_t)t->rows);
    for (int i = 0; i < t->rows; i++) t->grid[i] = row_blank(t);
    t->cursor_row = 0; t->cursor_col = 0;
}

static void exit_alt(StarlingTerm *t, int with_cursor) {
    if (!t->alt_active) return;
    t->alt_active = 0;
    if (t->saved_primary) {
        for (int i = 0; i < t->rows; i++) row_release(t, &t->grid[i]);
        free(t->grid);
        t->grid = t->saved_primary;
        t->saved_primary = NULL;
        /* resize() keeps saved_primary fitted to the live rows/cols, so this
           is normally a no-op; it is the equivalent of Swift's _normalizeGrid
           on the restored screen. */
        for (int i = 0; i < t->saved_primary_rows; i++) row_fit(&t->grid[i], t->cols);
        if (t->saved_primary_rows != t->rows) {
            Row *g = malloc(sizeof(Row) * (size_t)t->rows);
            int keep = t->saved_primary_rows < t->rows ? t->saved_primary_rows : t->rows;
            int drop = t->saved_primary_rows - keep;      /* oldest lines go first */
            for (int k = 0; k < drop; k++) row_release(t, &t->grid[k]);
            for (int i = 0; i < keep; i++) g[i] = t->grid[drop + i];
            for (int i = keep; i < t->rows; i++) g[i] = row_default(t);
            free(t->grid);
            t->grid = g;
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
                    sum += t->grid[r].cells[c].scalar;
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
            uint32_t v;
            switch (len) {
            case 2: v = (uint32_t)(b & 0x1F); break;
            case 3: v = (uint32_t)(b & 0x0F); break;
            case 4: v = (uint32_t)(b & 0x07); break;
            default: v = b; break;
            }
            int valid = len > 1;
            for (int k = 1; k < (len > 1 ? len : 1); k++) {
                uint8_t cont = input[i + (size_t)k];
                if ((cont & 0xC0) != 0x80) { valid = 0; break; }
                v = (v << 6) | (uint32_t)(cont & 0x3F);
            }
            if (!valid || !is_scalar(v)) v = 0xFFFD;
            put_scalar(t, v);
            i += (size_t)len;
            continue;
        }

        process_byte(t, b);
        i++;
    }
    t->generation++;
    free(joined);
}

/* ----------------------------------------------------------------- resize */

void starling_term_resize(StarlingTerm *t, int new_cols, int new_rows) {
    if (new_cols < 2) new_cols = 2;
    if (new_rows < 2) new_rows = 2;
    if (new_cols == t->cols && new_rows == t->rows) return;

    int old_rows = t->rows;
    t->cols = new_cols;
    t->rows = new_rows;
    t->region_top = 0;
    t->region_bottom = t->rows - 1;

    /* Fit existing rows to the new width. */
    for (int i = 0; i < old_rows; i++) row_fit(&t->grid[i], t->cols);

    if (new_rows > old_rows) {
        t->grid = realloc(t->grid, sizeof(Row) * (size_t)new_rows);
        for (int i = old_rows; i < new_rows; i++) t->grid[i] = row_default(t);
    } else if (new_rows < old_rows) {
        int drop = old_rows - new_rows;
        for (int k = 0; k < drop; k++) {
            Row removed = t->grid[0];
            if (!t->alt_active) {
                sb_push(t, removed);
                if (t->sb_len > SB_LIMIT) sb_trim_to(t, SB_LIMIT);
            } else {
                row_release(t, &removed);
            }
            memmove(&t->grid[0], &t->grid[1], sizeof(Row) * (size_t)(old_rows - 1 - k));
            if (t->cursor_row > 0) t->cursor_row--;
        }
        t->grid = realloc(t->grid, sizeof(Row) * (size_t)new_rows);
    }

    if (t->saved_primary) {
        for (int i = 0; i < t->saved_primary_rows; i++) row_fit(&t->saved_primary[i], t->cols);
        if (t->saved_primary_rows < t->rows) {
            t->saved_primary = realloc(t->saved_primary, sizeof(Row) * (size_t)t->rows);
            for (int i = t->saved_primary_rows; i < t->rows; i++)
                t->saved_primary[i] = row_default(t);
        } else if (t->saved_primary_rows > t->rows) {
            int drop = t->saved_primary_rows - t->rows;
            for (int k = 0; k < drop; k++) row_release(t, &t->saved_primary[k]);
            memmove(&t->saved_primary[0], &t->saved_primary[drop],
                    sizeof(Row) * (size_t)t->rows);
            t->saved_primary = realloc(t->saved_primary, sizeof(Row) * (size_t)t->rows);
        }
        t->saved_primary_rows = t->rows;
    }

    if (t->cursor_row > t->rows - 1) t->cursor_row = t->rows - 1;
    if (t->cursor_col > t->cols - 1) t->cursor_col = t->cols - 1;
    t->wrap_pending = 0;
    t->generation++;
}
