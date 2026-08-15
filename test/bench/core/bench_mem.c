/* bench_mem — memory baseline for the C core: bytes of PURE terminal state.
 *
 * The counterpart to bench_st.c. That one asks how fast the core drains a
 * stream; this one asks what the core costs to *hold* the result — the number
 * an embedder sees, with no renderer, no pty, no GUI and no font atlas in it.
 *
 * bench_mem_vs.c is the same measurement run against libghostty-vt as well;
 * both share the payload generators in mem_payloads.h so the two engines are
 * fed byte-identical streams. Anything explained here applies to both.
 *
 * ONE PAYLOAD PER PROCESS, deliberately. The obvious harness loops the
 * payloads in one process and samples between them, and it is wrong in a way
 * that flatters whichever payload runs first: freeing a 10k-row scrollback
 * returns the rows to the allocator but not to the OS, so the next payload
 * fills a warm heap and reports a smaller footprint for identical state. Each
 * payload therefore runs in its own process from a cold heap. mem-bench.sh
 * drives that loop; this binary measures exactly one.
 *
 * THE CORPUS IS STREAMED, NEVER MATERIALISED. A generated payload held in one
 * big malloc would sit inside every number this prints. Lines are built into a
 * 64 KB feed buffer (bench_st.c's chunk, and the app reader's) and flushed, so
 * the only large live allocation at sample time is the terminal itself.
 *
 * CRLF, NOT LF — the ONLCR trap from bench_st.c applies here for the same
 * reason and bites harder. A bare LF moves down without returning to column 0,
 * so every generated line lands staircased at an ever-growing column, wraps
 * early, and the row count that reaches scrollback stops matching the line
 * count that was fed. Lines are emitted with CRLF exactly as a tty's line
 * discipline would deliver them.
 *
 * Two numbers, because they answer different questions:
 *   heap  — allocator bytes in use (mstats/mallinfo). What the terminal state
 *           actually occupies. Comparable across machines.
 *   foot  — phys_footprint (macOS) / RSS (Linux). What Activity Monitor shows.
 *           Includes allocator slack and anything mapped outside malloc, so it
 *           is the honest "what the user sees" number and the noisier one.
 *
 * A third, `model`, is computed from the core's own structures: one Row
 * (24 bytes) plus cols*sizeof(Cell) per retained row. heap/model is the
 * allocator overhead of a per-row cell allocation strategy, which is the
 * thing a page-based core (ghostty) is buying away.
 *
 * Usage: bench_mem <payload> [cols] [rows] [lines]
 *        payload = empty | screen | plain | unicode | styled | mixed
 */

/* Built as gnu99, NOT c99 + _POSIX_C_SOURCE like the timing harnesses here.
   Strict POSIX mode sets Darwin's __DARWIN_C_LEVEL low enough to hide both
   `malloc_zone_t` (so <malloc/malloc.h> fails to parse) and snprintf inside
   the core itself. Nothing in this file needs the POSIX clock the others do. */

/* Angle brackets on purpose. test/bench/core/ keeps a COPY of starling_term.h
   so the other harnesses build with no -I, and a quoted include would search
   this directory first and silently pick up that copy — which has drifted
   behind the real header before (see the note at the top of it). With -I
   pointing at sdk/Sources/CTerminalCore/include, this form cannot. */
#include <starling_term.h>

#include "mem_payloads.h"
#include "mem_probe.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* sizeof(Row) in starling_term.c: Cell* + int cols + int used + uint32_t
   tail_bg, padded to 24. Not exported, and it does not need to be — this is
   the model's constant, and the core's own comment names the same number. */
#define ROW_BYTES 24

int main(int argc, char **argv) {
    const char *payload = argc > 1 ? argv[1] : "plain";
    int cols = argc > 2 ? atoi(argv[2]) : 80;
    int rows = argc > 3 ? atoi(argv[3]) : 24;
    long lines = argc > 4 ? atol(argv[4]) : 10000;

    int trailing_newline = 1;
    MpLineFn fn = mp_resolve(payload, rows, &lines, &trailing_newline);
    if (!fn && strcmp(payload, "empty")) {
        fprintf(stderr, "unknown payload %s\n", payload);
        return 1;
    }

    /* Everything the harness itself needs is allocated BEFORE the first
       sample, so it cancels out of every delta below. */
    char *line = malloc(MP_LINE_CAP(cols));
    char *feed = malloc(MP_FEED_CHUNK);
    if (!line || !feed) return 1;

    size_t heap0 = mem_heap_in_use(), foot0 = mem_footprint();

    StarlingTerm *t = starling_term_new(cols, rows);
    if (!t) return 1;
    size_t heap_empty = mem_heap_in_use();

    size_t used = 0;
    for (long n = 0; n < lines; n++) {
        int len = fn(line, cols, n);
        if (trailing_newline || n + 1 < lines) {
            line[len++] = '\r';
            line[len++] = '\n';
        }
        if (used + (size_t)len > MP_FEED_CHUNK) {
            starling_term_feed(t, (const uint8_t *)feed, used);
            used = 0;
        }
        if ((size_t)len > MP_FEED_CHUNK) {
            starling_term_feed(t, (const uint8_t *)line, (size_t)len);
        } else {
            memcpy(feed + used, line, (size_t)len);
            used += (size_t)len;
        }
    }
    if (used) starling_term_feed(t, (const uint8_t *)feed, used);

    /* No idle-time work exists in this core — no compression, no deferred
       trim — so the post-feed sample IS the steady state. A core that
       compresses cold history in the background does not have that property;
       bench_mem_vs.c drives libghostty's compression to completion before
       sampling for exactly this reason. */
    size_t heap1 = mem_heap_in_use(), foot1 = mem_footprint();

    int sb = starling_term_scrollback_count(t);
    long retained = (long)rows + sb;
    double model = (double)retained *
                   (ROW_BYTES + (double)cols * (double)sizeof(StarlingTermCell));

    size_t heap_total = heap1 - heap0;
    size_t foot_total = foot1 > foot0 ? foot1 - foot0 : 0;

    printf("%-8s %5d %5d %8ld %8d %10zu %10zu %10zu %10.0f %7.2f %8.1f\n",
           payload, cols, rows, lines, sb, heap_empty - heap0, heap_total,
           foot_total, model, model > 0 ? (double)heap_total / model : 0.0,
           retained > 0 ? (double)heap_total / (double)(retained * cols) : 0.0);

    starling_term_free(t);
    free(line);
    free(feed);
    return 0;
}
