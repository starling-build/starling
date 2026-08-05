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

typedef struct {
    Cell *cells;
    int   cols;      /* scrollback rows may predate a resize */
} Row;

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

    char osc[OSC_MAX];
    int  osc_len;

    uint8_t utf8_pending[4];
    int     utf8_pending_len;

    Cell *blank_template;      /* cols cells at cur_bg */
    uint32_t blank_bg;
    int      blank_cols;

    Cell **pool;               /* recycled row buffers, all `pool_cols` wide */
    int    pool_len;
    int    pool_cols;

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
    for (int i = 0; i < t->pool_len; i++) free(t->pool[i]);
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
            if (!t->pool) t->pool = malloc(sizeof(Cell *) * ROW_POOL_MAX);
            t->pool[t->pool_len++] = r->cells;
            r->cells = NULL;
            return;
        }
    }
    free(r->cells);
    r->cells = NULL;
}

static Cell *row_take(StarlingTerm *t) {
    if (t->pool_len > 0 && t->pool_cols == t->cols) return t->pool[--t->pool_len];
    return malloc(sizeof(Cell) * (size_t)t->cols);
}

static Row row_blank(StarlingTerm *t) {
    Row r;
    r.cols = t->cols;
    r.cells = row_take(t);
    memcpy(r.cells, blank_template(t), sizeof(Cell) * (size_t)t->cols);
    return r;
}

/* A row of default-blank cells (bg 0) — what a fresh grid and RIS produce. */
static Row row_default(StarlingTerm *t) {
    Row r;
    r.cols = t->cols;
    r.cells = row_take(t);
    Cell b; b.scalar = 32; b.fg = 0; b.bg = 0; b.attrs = 0;
    for (int i = 0; i < t->cols; i++) r.cells[i] = b;
    return r;
}

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

/* ------------------------------------------------------- cursor + printing */

static void line_feed(StarlingTerm *t);
static void scroll_up(StarlingTerm *t, int n);

static void put_scalar(StarlingTerm *t, uint32_t v) {
    if (t->wrap_pending) {
        t->wrap_pending = 0;
        if (t->autowrap) { t->cursor_col = 0; line_feed(t); }
    }
    if (t->cursor_row < 0 || t->cursor_row >= t->rows ||
        t->cursor_col < 0 || t->cursor_col >= t->cols) return;
    Cell *c = &t->grid[t->cursor_row].cells[t->cursor_col];
    c->scalar = v; c->fg = t->cur_fg; c->bg = t->cur_bg; c->attrs = t->cur_attrs;
    if (t->cursor_col == t->cols - 1) t->wrap_pending = 1;
    else t->cursor_col++;
}

static void line_feed(StarlingTerm *t) {
    t->wrap_pending = 0;
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
    if (mode == 0) {
        for (int c = t->cursor_col; c < t->cols; c++) r->cells[c] = b;
    } else if (mode == 1) {
        int last = t->cursor_col < t->cols - 1 ? t->cursor_col : t->cols - 1;
        for (int c = 0; c <= last; c++) r->cells[c] = b;
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
    Cell b = blank_cell(t);
    int end = t->cursor_col + n; if (end > t->cols) end = t->cols;
    for (int c = t->cursor_col; c < end; c++) t->grid[t->cursor_row].cells[c] = b;
}

static void delete_chars(StarlingTerm *t, int n) {
    if (t->cursor_row < 0 || t->cursor_row >= t->rows) return;
    Cell *line = t->grid[t->cursor_row].cells;
    int count = n < t->cols - t->cursor_col ? n : t->cols - t->cursor_col;
    if (count <= 0) return;
    memmove(line + t->cursor_col, line + t->cursor_col + count,
            sizeof(Cell) * (size_t)(t->cols - t->cursor_col - count));
    Cell b = blank_cell(t);
    for (int c = t->cols - count; c < t->cols; c++) line[c] = b;
}

static void insert_chars(StarlingTerm *t, int n) {
    if (t->cursor_row < 0 || t->cursor_row >= t->rows) return;
    Cell *line = t->grid[t->cursor_row].cells;
    int count = n < t->cols - t->cursor_col ? n : t->cols - t->cursor_col;
    if (count <= 0) return;
    memmove(line + t->cursor_col + count, line + t->cursor_col,
            sizeof(Cell) * (size_t)(t->cols - t->cursor_col - count));
    Cell b = blank_cell(t);
    for (int c = t->cursor_col; c < t->cursor_col + count; c++) line[c] = b;
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
    if (!t->csi_private) return;              /* ANSI modes ignored, as before */
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

static void dispatch_csi(StarlingTerm *t, uint8_t final) {
    const int *ps = t->csi_nums;
    int n = t->csi_count;
    /* Swift's p(i, def): an explicit 0 also means "use the default". */
    #define P(i, def) ((i) < n && ps[i] != 0 ? ps[i] : (def))
    int first = n > 0 ? ps[0] : 0;

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
    case 'c': respond(t, "\033[?6c"); break;
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
    case 0x08: if (t->cursor_col > 0) t->cursor_col--; t->wrap_pending = 0; break;
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
    case '[': t->csi_count = 0; t->csi_cur = -1; t->csi_private = 0; t->state = ST_CSI; break;
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
    } else if (b == 0x3F) {
        t->csi_private = 1;
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
                Cell *row = t->grid[t->cursor_row].cells;
                int start = t->cursor_col;
                uint32_t fg = t->cur_fg, bg = t->cur_bg; uint8_t at = t->cur_attrs;
                for (size_t k = 0; k < run; k++) {
                    Cell *c = &row[start + (int)k];
                    c->scalar = input[i + k]; c->fg = fg; c->bg = bg; c->attrs = at;
                }
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
