/* Hammer the row pool: heavy scrolling (so the scrollback trim batches fire and
   fill the pool) interleaved with resizes that change the width underneath it.
   The pool holds raw cell buffers of one width; if a resize ever let a buffer of
   the old width be handed out as a row of the new one, this overflows the heap
   and ASan says so. Also reads every line back, so a too-short buffer is caught
   on the read side even when the write side happens to fit. */
#include "starling_term.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

int main(void) {
    StarlingTerm *t = starling_term_new(201, 47);
    const char *bits[] = {
        "\033[41m", "\033[0m", "hello world\r\n", "\033[?1049h", "alt text\r\n",
        "\033[?1049l", "\033[2J", "\033[5;20r", "\033[2K", "x\r\n", "\033[44m",
        "\033[3L", "\033[2M", "\033[T", "\033[S", "\033[1J", "\033[0J", "\033c",
        "\033[38;5;208mcoloured\r\n", "\033[r",
    };
    const int nbits = (int)(sizeof bits / sizeof bits[0]);

    for (int i = 0; i < 60000; i++) {
        const char *s = bits[i % nbits];
        starling_term_feed(t, (const unsigned char *)s, strlen(s));

        /* Plain line feeds in bulk: this is what drives the scrollback past its
           limit and makes the trim hand ~512 rows to the pool at once. */
        if (i % 5 == 0) starling_term_feed(t, (const unsigned char *)"line\r\n", 6);

        /* Change the width while the pool is holding buffers of the old one. */
        if (i % 97 == 0) starling_term_resize(t, 20 + (i % 220), 5 + (i % 50));

        /* Read every line back at the current width. */
        if (i % 991 == 0) {
            int C = starling_term_cols(t), R = starling_term_rows(t);
            int sb = starling_term_scrollback_count(t);
            StarlingTermCell *line = malloc(sizeof(StarlingTermCell) * (size_t)C);
            unsigned long acc = 0;
            for (int k = 0; k < sb + R; k++) {
                starling_term_copy_line(t, k, line);
                for (int c = 0; c < C; c++) acc += line[c].scalar;
            }
            free(line);
            if (acc == 0xdeadbeef) printf("unreachable\n");
        }
    }
    starling_term_free(t);
    printf("asan_pool: done\n");
    return 0;
}
