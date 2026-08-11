// Differential harness, C side: feed a stream through starling_term and print a
// canonical dump of the resulting state. The Swift side prints the same thing.
// If one byte of one cell differs anywhere, the hashes diverge.
#include "starling_term.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint64_t fnv(uint64_t h, const void *p, size_t n) {
    const unsigned char *b = p;
    for (size_t i = 0; i < n; i++) { h ^= b[i]; h *= 1099511628211ULL; }
    return h;
}

static void resp(void *ctx, const char *s) {
    uint64_t *h = ctx;
    *h = fnv(*h, s, strlen(s));
}

int main(int argc, char **argv) {
    if (argc < 4) { fprintf(stderr, "usage: diff_c <stream> <cols> <rows> [chunk]\n"); return 2; }
    const char *path = argv[1];
    int cols = atoi(argv[2]), rows = atoi(argv[3]);
    size_t chunk = argc > 4 ? (size_t)atoi(argv[4]) : 65536;

    FILE *f = fopen(path, "rb");
    if (!f) { fprintf(stderr, "cannot read %s\n", path); return 1; }
    fseek(f, 0, SEEK_END); long sz = ftell(f); fseek(f, 0, SEEK_SET);
    size_t nb = (size_t)sz;
    unsigned char *buf = malloc(nb);
    if (fread(buf, 1, nb, f) != nb) { fprintf(stderr, "short read\n"); return 1; }
    fclose(f);

    uint64_t rhash = 1469598103934665603ULL;
    StarlingTerm *t = starling_term_new(cols, rows);
    starling_term_set_response_cb(t, resp, &rhash);
    for (size_t i = 0; i < nb; i += chunk) {
        size_t m = nb - i < chunk ? nb - i : chunk;
        starling_term_feed(t, buf + i, m);
    }

    int C = starling_term_cols(t), R = starling_term_rows(t);
    int sb = starling_term_scrollback_count(t);
    uint64_t h = 1469598103934665603ULL;
    StarlingTermCell *line = malloc(sizeof(StarlingTermCell) * (size_t)C);
    for (int i = 0; i < sb + R; i++) {
        starling_term_copy_line(t, i, line);
        for (int c = 0; c < C; c++) {
            /* field-by-field: the struct has padding bytes that are not
               guaranteed equal between the two implementations */
            h = fnv(h, &line[c].scalar, sizeof line[c].scalar);
            h = fnv(h, &line[c].fg, sizeof line[c].fg);
            h = fnv(h, &line[c].bg, sizeof line[c].bg);
            h = fnv(h, &line[c].attrs, sizeof line[c].attrs);
        }
    }
    printf("cols=%d rows=%d cur=%d,%d vis=%d appkeys=%d bpaste=%d sb=%d cells=%016llx resp=%016llx\n",
           C, R, starling_term_cursor_row(t), starling_term_cursor_col(t),
           starling_term_cursor_visible(t), starling_term_app_cursor_keys(t),
           starling_term_bracketed_paste(t), sb,
           (unsigned long long)h, (unsigned long long)rhash);
    free(line); free(buf);
    starling_term_free(t);
    return 0;
}
