// The same terminal core as bench_cpp.cpp, in plain C99 — same state machine,
// same flat grid, same per-character writes, same scroll/scrollback policy.
// Point of the exercise: find out whether C gives up anything to C++ on this
// workload, given the repo bridges Swift to C everywhere and only once to C++.
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>

typedef struct { uint32_t scalar, fg, bg, attrs; } Cell;

#define SB_LIMIT 2000
#define SB_SLACK 512
#define MAXPARAM 32

typedef struct {
    int cols, rows;
    Cell *grid;
    Cell **sb;            /* scrollback rows, ring */
    int sb_cap, sb_head, sb_len;
    int cursorRow, cursorCol;
    int wrapPending;
    enum { Ground, Escape, Csi } state;
    int param[MAXPARAM], nparam, priv;
    uint32_t curFg, curBg, curAttrs;
    uint64_t writes;
} Emu;

static void emu_init(Emu *e, int cols, int rows) {
    memset(e, 0, sizeof *e);
    e->cols = cols; e->rows = rows;
    e->grid = malloc(sizeof(Cell) * (size_t)cols * rows);
    for (size_t i = 0; i < (size_t)cols * rows; i++) {
        e->grid[i] = (Cell){32, 0, 0, 0};
    }
    e->sb_cap = SB_LIMIT + SB_SLACK + 1;
    e->sb = calloc((size_t)e->sb_cap, sizeof(Cell *));
    e->param[0] = -1;
}

static uint32_t palette(int idx) { return 0xFF000000u | (uint32_t)(idx * 2654435761u); }

static void scrollUp(Emu *e) {
    /* push top row to scrollback (ring), shift up, blank last row */
    Cell *row = malloc(sizeof(Cell) * (size_t)e->cols);
    memcpy(row, e->grid, sizeof(Cell) * (size_t)e->cols);
    if (e->sb_len == e->sb_cap - 1) {                 /* full: evict oldest */
        free(e->sb[e->sb_head]);
        e->sb_head = (e->sb_head + 1) % e->sb_cap;
        e->sb_len--;
    }
    e->sb[(e->sb_head + e->sb_len) % e->sb_cap] = row;
    e->sb_len++;
    memmove(e->grid, e->grid + e->cols,
            sizeof(Cell) * ((size_t)e->cols * e->rows - e->cols));
    Cell b = {32, 0, e->curBg, 0};
    for (int i = 0; i < e->cols; i++) e->grid[(size_t)e->cols * (e->rows - 1) + i] = b;
    while (e->sb_len > SB_LIMIT + SB_SLACK) {
        free(e->sb[e->sb_head]);
        e->sb_head = (e->sb_head + 1) % e->sb_cap;
        e->sb_len--;
    }
}

static void lineFeed(Emu *e) {
    if (e->cursorRow + 1 >= e->rows) scrollUp(e); else e->cursorRow++;
    e->wrapPending = 0;
}

static void putScalar(Emu *e, uint32_t v) {
    if (e->wrapPending) { e->cursorCol = 0; lineFeed(e); e->wrapPending = 0; }
    if (e->cursorCol >= e->cols) { e->cursorCol = 0; lineFeed(e); }
    e->writes++;
    Cell *c = &e->grid[(size_t)e->cursorRow * e->cols + e->cursorCol];
    c->scalar = v; c->fg = e->curFg; c->bg = e->curBg; c->attrs = e->curAttrs;
    if (e->cursorCol + 1 >= e->cols) { e->cursorCol = e->cols - 1; e->wrapPending = 1; }
    else e->cursorCol++;
}

static int param_at(Emu *e, int i, int dflt) {
    if (i > e->nparam) return dflt;
    return e->param[i] < 0 ? dflt : e->param[i];
}

static void applySgr(Emu *e) {
    if (e->nparam == 0 && e->param[0] < 0) { e->curFg = e->curBg = e->curAttrs = 0; return; }
    for (int i = 0; i <= e->nparam; i++) {
        int v = param_at(e, i, 0);
        if (v == 0) { e->curFg = e->curBg = e->curAttrs = 0; }
        else if (v == 1) e->curAttrs |= 1;
        else if (v == 4) e->curAttrs |= 2;
        else if (v == 7) e->curAttrs |= 4;
        else if (v >= 30 && v <= 37) e->curFg = palette(v - 30);
        else if (v >= 40 && v <= 47) e->curBg = palette(v - 40);
        else if (v >= 90 && v <= 97) e->curFg = palette(v - 90 + 8);
        else if (v >= 100 && v <= 107) e->curBg = palette(v - 100 + 8);
        else if (v == 39) e->curFg = 0;
        else if (v == 49) e->curBg = 0;
        else if ((v == 38 || v == 48) && i + 1 <= e->nparam) {
            int mode = param_at(e, i + 1, 0);
            if (mode == 5 && i + 2 <= e->nparam) {
                uint32_t c = palette(param_at(e, i + 2, 0)); i += 2;
                if (v == 38) e->curFg = c; else e->curBg = c;
            } else if (mode == 2 && i + 4 <= e->nparam) {
                uint32_t c = 0xFF000000u | ((uint32_t)param_at(e,i+2,0) << 16)
                           | ((uint32_t)param_at(e,i+3,0) << 8) | (uint32_t)param_at(e,i+4,0);
                i += 4;
                if (v == 38) e->curFg = c; else e->curBg = c;
            }
        }
    }
}

static void dispatchCsi(Emu *e, uint8_t f) {
    if (e->priv) return;
    size_t total = (size_t)e->cols * e->rows;
    switch (f) {
    case 'H': case 'f': {
        int r = param_at(e, 0, 1) - 1, c = param_at(e, 1, 1) - 1;
        e->cursorRow = r < 0 ? 0 : (r >= e->rows ? e->rows - 1 : r);
        e->cursorCol = c < 0 ? 0 : (c >= e->cols ? e->cols - 1 : c);
        e->wrapPending = 0;
        break;
    }
    case 'J': {
        int m = param_at(e, 0, 0);
        size_t from = 0, to = total;
        if (m == 0) from = (size_t)e->cursorRow * e->cols + e->cursorCol;
        else if (m == 1) to = (size_t)e->cursorRow * e->cols + e->cursorCol + 1;
        Cell b = {32, 0, e->curBg, 0};
        for (size_t i = from; i < to; i++) e->grid[i] = b;
        break;
    }
    case 'K': {
        int m = param_at(e, 0, 0);
        size_t rs = (size_t)e->cursorRow * e->cols;
        size_t from = rs + e->cursorCol, to = rs + e->cols;
        if (m == 1) { from = rs; to = rs + e->cursorCol + 1; }
        else if (m == 2) { from = rs; }
        Cell b = {32, 0, e->curBg, 0};
        for (size_t i = from; i < to; i++) e->grid[i] = b;
        break;
    }
    case 'm': applySgr(e); break;
    default: break;
    }
}

static void processByte(Emu *e, uint8_t b) {
    switch (e->state) {
    case Ground:
        switch (b) {
        case 0x1B: e->state = Escape; break;
        case '\n': lineFeed(e); break;
        case '\r': e->cursorCol = 0; e->wrapPending = 0; break;
        case '\b': if (e->cursorCol > 0) e->cursorCol--; e->wrapPending = 0; break;
        case '\t': e->cursorCol = (e->cursorCol / 8 + 1) * 8;
                   if (e->cursorCol >= e->cols) e->cursorCol = e->cols - 1; break;
        default: break;
        }
        break;
    case Escape:
        if (b == '[') { e->state = Csi; e->nparam = 0; e->param[0] = -1; e->priv = 0; }
        else e->state = Ground;
        break;
    case Csi:
        if (b >= '0' && b <= '9') {
            if (e->param[e->nparam] < 0) e->param[e->nparam] = 0;
            e->param[e->nparam] = e->param[e->nparam] * 10 + (b - '0');
        } else if (b == ';') {
            if (e->nparam + 1 < MAXPARAM) { e->nparam++; e->param[e->nparam] = -1; }
        } else if (b == '?') {
            e->priv = 1;
        } else if (b >= 0x40 && b <= 0x7E) {
            dispatchCsi(e, b); e->state = Ground;
        }
        break;
    }
}

static void emu_feed(Emu *e, const uint8_t *p, size_t n) {
    for (size_t i = 0; i < n; ) {
        uint8_t b = p[i];
        if (e->state == Ground) {
            if (b >= 0x20 && b < 0x7F) { putScalar(e, b); i++; continue; }
            if (b >= 0x80) {
                int len = b >= 0xF0 ? 4 : b >= 0xE0 ? 3 : b >= 0xC0 ? 2 : 1;
                if (i + (size_t)len > n) break;
                uint32_t v;
                switch (len) {
                case 2: v = ((uint32_t)(b & 0x1F) << 6) | (p[i+1] & 0x3F); break;
                case 3: v = ((uint32_t)(b & 0x0F) << 12) | ((uint32_t)(p[i+1] & 0x3F) << 6)
                          | (p[i+2] & 0x3F); break;
                case 4: v = ((uint32_t)(b & 0x07) << 18) | ((uint32_t)(p[i+1] & 0x3F) << 12)
                          | ((uint32_t)(p[i+2] & 0x3F) << 6) | (p[i+3] & 0x3F); break;
                default: v = b; break;
                }
                putScalar(e, v); i += (size_t)len; continue;
            }
        }
        processByte(e, b); i++;
    }
}

static size_t emu_checksum(Emu *e) {
    size_t s = 0, total = (size_t)e->cols * e->rows;
    for (size_t i = 0; i < total; i++) s += e->grid[i].scalar + e->grid[i].fg + e->grid[i].bg;
    return s + (size_t)e->sb_len;
}

int main(int argc, char **argv) {
    const char *path = argc > 1 ? argv[1] : "/var/tmp/bench/doomstream.bin";
    int reps = argc > 2 ? atoi(argv[2]) : 3;
    FILE *f = fopen(path, "rb");
    if (!f) { fprintf(stderr, "cannot read %s\n", path); return 1; }
    fseek(f, 0, SEEK_END); long sz = ftell(f); fseek(f, 0, SEEK_SET);
    uint8_t *buf = malloc((size_t)sz);
    if (fread(buf, 1, (size_t)sz, f) != (size_t)sz) { fprintf(stderr, "short read\n"); return 1; }
    fclose(f);
    printf("stream %ld MB, chunk 65536, grid 47x201\n", sz / 1000000);

    const size_t chunk = 65536;
    for (int r = 1; r <= reps; r++) {
        Emu e; emu_init(&e, 201, 47);
        struct timespec t0, t1;
        clock_gettime(CLOCK_MONOTONIC, &t0);
        for (size_t i = 0; i < (size_t)sz; i += chunk) {
            size_t m = (size_t)sz - i < chunk ? (size_t)sz - i : chunk;
            emu_feed(&e, buf + i, m);
        }
        clock_gettime(CLOCK_MONOTONIC, &t1);
        double secs = (double)(t1.tv_sec - t0.tv_sec) + (double)(t1.tv_nsec - t0.tv_nsec) / 1e9;
        printf("run %d  %.3f s  %.1f MB/s  cellwrites %llu  [checksum %zu]\n",
               r, secs, (double)sz / 1e6 / secs,
               (unsigned long long)e.writes, emu_checksum(&e));
        free(e.grid);
        for (int i = 0; i < e.sb_len; i++) free(e.sb[(e.sb_head + i) % e.sb_cap]);
        free(e.sb);
    }
    free(buf);
    return 0;
}
