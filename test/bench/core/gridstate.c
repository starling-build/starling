/* Grid-storage regression differential: OLD core against NEW core.
 *
 * `diff_c.c` compares the C core against the Swift one. This compares the C
 * core against ITSELF at another commit, which is what you want when changing
 * how rows are STORED rather than what they contain — the grid is a sliding
 * window into a slack block now (see grid_rotate_in), and every path that is
 * not a scroll has to flatten it first.
 *
 *   git show HEAD:sdk/Sources/CTerminalCore/starling_term.c > /tmp/old/starling_term.c
 *   git show HEAD:sdk/Sources/CTerminalCore/include/starling_term.h > /tmp/old/include/
 *   cp sdk/Sources/CTerminalCore/starling_widths_gen.h /tmp/old/
 *   cc -O1 -std=c99 -I/tmp/old/include gridstate.c /tmp/old/starling_term.c -o /tmp/g_old
 *   cc -O1 -std=c99 -Isdk/Sources/CTerminalCore/include \
 *      gridstate.c sdk/Sources/CTerminalCore/starling_term.c -o /tmp/g_new
 *   for f in /var/tmp/bench/corpus/[01]*.txt; do
 *       [ "$(/tmp/g_old $f)" = "$(/tmp/g_new $f)" ] || echo "DIFFER $f"; done
 *
 * It hashes everything observable — all of scrollback and the live grid, cell
 * by cell, plus cursor and mode state — after each of a series of stages that
 * a straight `cat` never reaches: scroll regions, reverse index, IL/DL at the
 * top of the screen and inside a region, alt-screen enter/exit, resizes in
 * both directions, alt across a resize, and RIS. Build it under
 * `-fsanitize=address` too; the window arithmetic is exactly the kind that
 * reads one Row past its block.
 */
#include "starling_term.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned long long H = 1469598103934665603ULL;
static void h_bytes(const void *p, size_t n) {
    const unsigned char *b = p;
    for (size_t i = 0; i < n; i++) { H ^= b[i]; H *= 1099511628211ULL; }
}

static void hash_all(StarlingTerm *t, int unused_cols) {
    /* copy_line always writes the terminal's CURRENT width, so size the
       buffer from the terminal — not from whatever the caller last saw. */
    (void)unused_cols;
    int cols = starling_term_cols(t);
    int total = starling_term_scrollback_count(t) + starling_term_rows(t);
    StarlingTermCell *line = malloc(sizeof(StarlingTermCell) * (size_t)cols);
    for (int i = 0; i < total; i++) {
        starling_term_copy_line(t, i, line);
        for (int c = 0; c < cols; c++) {
            h_bytes(&line[c].scalar, sizeof line[c].scalar);
            h_bytes(&line[c].fg, sizeof line[c].fg);
            h_bytes(&line[c].bg, sizeof line[c].bg);
            h_bytes(&line[c].attrs, sizeof line[c].attrs);
        }
    }
    free(line);
    int v[6] = { starling_term_cursor_row(t), starling_term_cursor_col(t),
                 starling_term_cursor_visible(t), starling_term_alt_active(t),
                 starling_term_scrollback_count(t), starling_term_rows(t) };
    h_bytes(v, sizeof v);
}

static void feed_str(StarlingTerm *t, const char *s) {
    starling_term_feed(t, (const unsigned char *)s, strlen(s));
}

int main(int argc, char **argv) {
    const char *path = argv[1];
    int cols = argc > 2 ? atoi(argv[2]) : 201;
    int rows = argc > 3 ? atoi(argv[3]) : 47;

    FILE *f = fopen(path, "rb");
    if (!f) { fprintf(stderr, "cannot read %s\n", path); return 1; }
    fseek(f, 0, SEEK_END); long sz = ftell(f); fseek(f, 0, SEEK_SET);
    unsigned char *buf = malloc((size_t)sz);
    if (fread(buf, 1, (size_t)sz, f) != (size_t)sz) return 1;
    fclose(f);

    StarlingTerm *t = starling_term_new(cols, rows);

    /* Feed at an awkward grain so escape sequences straddle chunks. */
    const size_t chunk = 997;
    for (size_t i = 0; i < (size_t)sz; i += chunk)
        starling_term_feed(t, buf + i, (size_t)sz - i < chunk ? (size_t)sz - i : chunk);
    hash_all(t, cols);

    /* Scroll region, then more output through it. */
    feed_str(t, "\033[5;20r\033[10;1Hregion text\r\n");
    for (int i = 0; i < 60; i++) feed_str(t, "scrolling in a region\r\n");
    hash_all(t, cols);
    feed_str(t, "\033[r");                      /* release the region */

    /* Reverse scroll (the rev-slide path). */
    feed_str(t, "\033[1;1H");
    for (int i = 0; i < 80; i++) feed_str(t, "\033M");
    hash_all(t, cols);

    /* IL/DL at the top of the screen — the other way into the reverse slide,
       and into grid_rotate_in with at == 0 but to < rows-1. */
    for (int i = 0; i < 120; i++) {
        feed_str(t, "\033[1;1H\033[3L");
        feed_str(t, "inserted at the top\r\n");
        feed_str(t, "\033[1;1H\033[2M");
    }
    hash_all(t, cols);
    /* IL/DL inside a scroll region, cursor at the region top. */
    feed_str(t, "\033[8;30r");
    for (int i = 0; i < 120; i++) {
        feed_str(t, "\033[8;1H\033[2L");
        feed_str(t, "in region\r\n");
        feed_str(t, "\033[8;1H\033[1M");
    }
    hash_all(t, cols);
    feed_str(t, "\033[r");

    /* Alt screen in and out, with output on both sides. */
    feed_str(t, "\033[?1049h");
    for (int i = 0; i < 100; i++) feed_str(t, "alt screen line\r\n");
    hash_all(t, cols);
    feed_str(t, "\033[?1049l");
    hash_all(t, cols);

    /* Resizes in both directions, with scrolling between them. */
    int sizes[][2] = { { 120, 30 }, { 240, 60 }, { 80, 24 }, { 201, 47 } };
    for (int k = 0; k < 4; k++) {
        starling_term_resize(t, sizes[k][0], sizes[k][1]);
        for (int i = 0; i < 90; i++) feed_str(t, "after resize\r\n");
        hash_all(t, sizes[k][0] < cols ? sizes[k][0] : cols);
    }

    /* Alt screen across a resize — saved_primary has to survive it. */
    feed_str(t, "\033[?1049h");
    starling_term_resize(t, 100, 40);
    for (int i = 0; i < 50; i++) feed_str(t, "alt after resize\r\n");
    starling_term_resize(t, 201, 47);
    feed_str(t, "\033[?1049l");
    hash_all(t, cols);

    /* Full reset. */
    feed_str(t, "\033c");
    for (int i = 0; i < 200; i++) feed_str(t, "post reset\r\n");
    hash_all(t, cols);

    printf("%016llx\n", H);
    starling_term_free(t);
    free(buf);
    return 0;
}
