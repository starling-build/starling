#include "starling_term.h"
#include <stdio.h>
#include <stdlib.h>
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
