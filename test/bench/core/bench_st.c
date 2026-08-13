/* The C core alone: feed a captured stream, time it, report MB/s.
 *
 * ONLCR, and why this is not a detail. A corpus captured to a FILE holds bare
 * LFs, but the core never sees those in a live terminal: `cat` writes to a pty
 * slave, and the tty line discipline expands every LF to CRLF on the way out.
 * Feed the file as-is and a bare LF moves down a row WITHOUT returning to
 * column 0, so the text staircases diagonally across the screen — a completely
 * different workload from the one the app runs, on the same bytes.
 *
 * It is not a small difference and it does not look like an error. On
 * 01_light_cells (1.5 M short lines) the staircase leaves every row ~100
 * columns wide instead of ~7, so each scrolled-in row has ~100 cells to blank
 * instead of ~7: the same core measured 90 MB/s staircased and 196 MB/s as a
 * pty delivers it. That 90 stood in docs/plans/terminal-perf-macos.md as "the
 * core's outlier, 4x slower per byte than anything else" and sent Lever 3
 * after the allocator. The outlier was the harness.
 *
 * So: expand LF to CRLF by default, exactly as the tty would, and require
 * BENCH_RAW=1 to feed a stream verbatim (right for a capture taken FROM a pty,
 * which already carries its CRs). Streams that already contain CR are passed
 * through untouched either way.
 */
#include "starling_term.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

int main(int argc, char **argv) {
    const char *path = argv[1];
    int reps = argc > 2 ? atoi(argv[2]) : 3;
    int cols = argc > 3 ? atoi(argv[3]) : 201, rows = argc > 4 ? atoi(argv[4]) : 47;
    FILE *f = fopen(path, "rb");
    if (!f) { fprintf(stderr, "cannot read %s\n", path); return 1; }
    fseek(f, 0, SEEK_END); long sz = ftell(f); fseek(f, 0, SEEK_SET);
    size_t nb = (size_t)sz; unsigned char *buf = malloc(nb);
    if (fread(buf,1,nb,f) != nb) return 1;
    fclose(f);

    int raw = getenv("BENCH_RAW") != NULL;
    size_t lf = 0, cr = 0;
    for (size_t i = 0; i < nb; i++) {
        if (buf[i] == '\n') lf++;
        else if (buf[i] == '\r') cr++;
    }
    if (!raw && lf > 0 && cr == 0) {
        unsigned char *out = malloc(nb + lf);
        size_t o = 0;
        for (size_t i = 0; i < nb; i++) {
            if (buf[i] == '\n') out[o++] = '\r';
            out[o++] = buf[i];
        }
        free(buf);
        buf = out; nb = o;
    }

    const size_t chunk = 65536;
    double best = 0;
    for (int r = 0; r < reps; r++) {
        StarlingTerm *t = starling_term_new(cols, rows);
        struct timespec a,b; clock_gettime(CLOCK_MONOTONIC,&a);
        for (size_t i = 0; i < nb; i += chunk)
            starling_term_feed(t, buf+i, nb-i < chunk ? nb-i : chunk);
        clock_gettime(CLOCK_MONOTONIC,&b);
        double s = (b.tv_sec-a.tv_sec)+(b.tv_nsec-a.tv_nsec)/1e9;
        double mbs = (double)nb/1e6/s;
        if (mbs > best) best = mbs;
        starling_term_free(t);
    }
    printf("%.1f MB/s\n", best);
    free(buf);
    return 0;
}
