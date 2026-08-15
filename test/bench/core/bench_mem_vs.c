/* bench_mem_vs — our terminal core against libghostty-vt, same payloads, same
 * instrument, one engine per process.
 *
 * This is the comparison bench_mem.c's baseline exists to feed. Everything in
 * that file's header applies here — one payload per process from a cold heap,
 * a streamed corpus that is never materialised, CRLF line endings, and the
 * two-instrument probe in mem_probe.h. What this file adds is the second
 * engine and the three ways a cross-core memory comparison lies:
 *
 * 1. MISMATCHED SCROLLBACK DEPTH. Our SB_LIMIT ships at 2000 rows; libghostty
 *    defaults to a 50 MB byte budget and effectively unlimited lines. Feed
 *    10,000 rows to both and ours quietly drops 77% of them, then reports a
 *    quarter of the memory — which is not a win, it is a report of who kept
 *    less history. Both sides are configured to the same line depth here, and
 *    the table prints RETAINED rows for each, because neither engine lands
 *    exactly on its configured limit: ours trims in batches with slack above
 *    the floor, and libghostty prunes at page granularity, so its retained
 *    count is "almost always higher than configured" by its own docs. Compare
 *    the per-row and per-cell columns, never the totals alone.
 *
 * 2. SAMPLING A COMPRESSING ENGINE TOO EARLY. libghostty compresses cold
 *    scrollback, and in the library that work is caller-driven: nothing
 *    happens until the embedder calls it. Sampling right after the feed would
 *    report its uncompressed size while calling it "the default configuration"
 *    — the shipping app runs the same compression from its idle handler. So
 *    the compressed run drives ghostty_terminal_compress(FULL) until it stops
 *    reporting PENDING, which is a deterministic quiesce and strictly better
 *    than sleeping and hoping. Both numbers are reported, because compressed
 *    is what a user gets and uncompressed is what the layout costs.
 *
 * 3. AN INSTRUMENT THAT IS BLIND TO ONE SIDE. The first run of this harness
 *    reported libghostty holding 21 KB for 9,977 rows — against a 7.1 MB
 *    footprint for the same state. It does not allocate its grid pages through
 *    libc malloc, so the malloc statistic that measures our core exactly is
 *    blind to nearly all of theirs. A single number here would have been off
 *    by 300x and looked like a landslide.
 *
 *    The obvious fix is to hand libghostty a counting allocator through its
 *    GhosttyAllocator vtable and count its bytes exactly. ALLOC=count does
 *    that, and it DOES NOT WORK — which is the finding, not a bug here. It
 *    accounts for 19,674 bytes of a state whose footprint is 7.2 MB, because
 *    `PageList.pageAllocator()` never asks the caller's allocator for grid
 *    pages: it takes them from Zig's page allocator, and on macOS from a
 *    *tagged* mach VM allocator (`application_specific_1`) so the grid can be
 *    attributed in vmmap. The vtable sees only ancillary allocations.
 *
 *    So the comparable column is `foot` — resident pages — for BOTH engines,
 *    because it is the only probe that sees a malloc-based core and an
 *    mmap-based one alike. ALLOC=count is kept because its 19 KB against
 *    7.2 MB is the evidence, and because anyone who reaches for the allocator
 *    interface expecting to count libghostty deserves to find this note first.
 *
 * Usage: bench_mem_vs <ours|ghostty> <payload> [cols] [rows] [lines] [sb_lines]
 *        env: COMPRESS=1   drive ghostty's scrollback compression to completion
 *             ALLOC=count  route ghostty through the counting libc allocator
 */

#include <starling_term.h>
#include <ghostty/vt.h>

#include "mem_payloads.h"
#include "mem_probe.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ROW_BYTES 24 /* sizeof(Row) in starling_term.c */

/* ------------------------------------------------- counting libc allocator
 *
 * Zig's allocator interface hands the length back on free, so exact live-byte
 * accounting needs no malloc_size() and no bookkeeping header.
 *
 * resize and remap both refuse. They are permitted to: the documented contract
 * is that a false/NULL return means "the caller should allocate, copy and
 * free", which routes every size change back through alloc/free and keeps the
 * counter exact. Accepting an in-place shrink would be faster and would make
 * the counter disagree with what malloc is really holding, which defeats the
 * point of having the malloc probe cross-check it.
 */
typedef struct { size_t live, peak; } CountAlloc;

static void *ca_alloc(void *ctx, size_t len, uint8_t alignment, uintptr_t ra) {
    (void)ra;
    CountAlloc *c = ctx;
    size_t a = alignment < sizeof(void *) ? sizeof(void *) : alignment;
    void *p = NULL;
    if (posix_memalign(&p, a, len) != 0) return NULL;
    c->live += len;
    if (c->live > c->peak) c->peak = c->live;
    return p;
}

static bool ca_resize(void *ctx, void *m, size_t len, uint8_t alignment,
                      size_t new_len, uintptr_t ra) {
    (void)ctx; (void)m; (void)len; (void)alignment; (void)new_len; (void)ra;
    return false;
}

static void *ca_remap(void *ctx, void *m, size_t len, uint8_t alignment,
                      size_t new_len, uintptr_t ra) {
    (void)ctx; (void)m; (void)len; (void)alignment; (void)new_len; (void)ra;
    return NULL;
}

static void ca_free(void *ctx, void *m, size_t len, uint8_t alignment,
                    uintptr_t ra) {
    (void)alignment; (void)ra;
    CountAlloc *c = ctx;
    c->live -= len;
    free(m);
}

static const GhosttyAllocatorVtable ca_vtable = {
    .alloc = ca_alloc,
    .resize = ca_resize,
    .remap = ca_remap,
    .free = ca_free,
};

typedef struct {
    int is_ghostty, compress, counting;
    StarlingTerm *ours;
    GhosttyTerminal theirs;
    CountAlloc counter;
    GhosttyAllocator alloc;
} Engine;

static int engine_open(Engine *e, const char *name, int cols, int rows,
                       long sb_lines) {
    memset(e, 0, sizeof *e);
    if (!strcmp(name, "ours")) {
        e->ours = starling_term_new(cols, rows);
        return e->ours != NULL;
    }
    e->is_ghostty = 1;
    {
        const char *z = getenv("COMPRESS");
        const char *a = getenv("ALLOC");
        e->compress = z && *z && strcmp(z, "0");
        e->counting = a && !strcmp(a, "count");
    }
    e->alloc.ctx = &e->counter;
    e->alloc.vtable = &ca_vtable;
    if (ghostty_terminal_new(e->counting ? &e->alloc : NULL, &e->theirs,
                             (uint16_t)cols, (uint16_t)rows) != GHOSTTY_SUCCESS)
        return 0;
    /* Line depth matched to ours; the byte budget removed so that the line
       limit is what binds. Left at its 50 MB default the byte limit would
       silently govern the styled payload first and the two engines would be
       holding different amounts of history for reasons the table cannot show. */
    size_t lim = (size_t)sb_lines;
    if (ghostty_terminal_set(e->theirs, GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_LINES,
                             &lim) != GHOSTTY_SUCCESS)
        return 0;
    ghostty_terminal_set(e->theirs, GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_BYTES,
                         NULL);
    return 1;
}

static void engine_feed(Engine *e, const uint8_t *b, size_t n) {
    if (e->is_ghostty) ghostty_terminal_vt_write(e->theirs, b, n);
    else starling_term_feed(e->ours, b, n);
}

/* The quiesce. Ours has no idle-time work at all, so it is already at steady
   state; libghostty is stepped until it reports no continuation. */
static void engine_settle(Engine *e) {
    if (!e->is_ghostty || !e->compress) return;
    for (;;) {
        GhosttyTerminalCompressionResult r;
        if (ghostty_terminal_compress(e->theirs,
                                      GHOSTTY_TERMINAL_COMPRESSION_MODE_FULL,
                                      &r) != GHOSTTY_SUCCESS)
            return;
        if (r != GHOSTTY_TERMINAL_COMPRESSION_RESULT_PENDING) return;
    }
}

static long engine_scrollback(Engine *e) {
    if (!e->is_ghostty) return starling_term_scrollback_count(e->ours);
    size_t sb = 0;
    if (ghostty_terminal_get(e->theirs, GHOSTTY_TERMINAL_DATA_SCROLLBACK_ROWS,
                             &sb) != GHOSTTY_SUCCESS)
        return -1;
    return (long)sb;
}

static void engine_close(Engine *e) {
    if (e->is_ghostty) ghostty_terminal_free(e->theirs);
    else starling_term_free(e->ours);
}

int main(int argc, char **argv) {
    const char *engine = argc > 1 ? argv[1] : "ours";
    const char *payload = argc > 2 ? argv[2] : "plain";
    int cols = argc > 3 ? atoi(argv[3]) : 80;
    int rows = argc > 4 ? atoi(argv[4]) : 24;
    long lines = argc > 5 ? atol(argv[5]) : 10000;
    long sb_lines = argc > 6 ? atol(argv[6]) : 10000;

    int trailing_newline = 1;
    MpLineFn fn = mp_resolve(payload, rows, &lines, &trailing_newline);
    if (!fn && strcmp(payload, "empty")) {
        fprintf(stderr, "unknown payload %s\n", payload);
        return 1;
    }

    char *line = malloc(MP_LINE_CAP(cols));
    char *feed = malloc(MP_FEED_CHUNK);
    if (!line || !feed) return 1;

    size_t heap0 = mem_heap_in_use(), foot0 = mem_footprint();

    Engine e;
    if (!engine_open(&e, engine, cols, rows, sb_lines)) {
        fprintf(stderr, "cannot create engine %s\n", engine);
        return 1;
    }
    size_t heap_new = mem_heap_in_use();

    size_t used = 0;
    for (long n = 0; n < lines; n++) {
        int len = fn(line, cols, n);
        if (trailing_newline || n + 1 < lines) {
            line[len++] = '\r';
            line[len++] = '\n';
        }
        if (used + (size_t)len > MP_FEED_CHUNK) {
            engine_feed(&e, (const uint8_t *)feed, used);
            used = 0;
        }
        if ((size_t)len > MP_FEED_CHUNK) engine_feed(&e, (const uint8_t *)line, (size_t)len);
        else { memcpy(feed + used, line, (size_t)len); used += (size_t)len; }
    }
    if (used) engine_feed(&e, (const uint8_t *)feed, used);

    engine_settle(&e);

    size_t heap1 = mem_heap_in_use(), foot1 = mem_footprint();
    long sb = engine_scrollback(&e);
    long retained = (long)rows + (sb > 0 ? sb : 0);

    size_t heap_total = heap1 - heap0;
    size_t foot_total = foot1 > foot0 ? foot1 - foot0 : 0;

    /* foot, for BOTH engines. It is the only probe that sees both: ours is
       entirely libc malloc, theirs is mmap'd VM, and resident pages count
       either. `heap` and `counted` are printed beside it as the evidence for
       that choice — see the ALLOC=count note in the header. Using malloc for
       ours (13.1 MB against a 14.1 MB footprint) and pages for theirs would
       have quietly credited us with the 7% of our footprint that is allocator
       slack, on the side of the table where it helps. */
    size_t counted = e.is_ghostty && e.counting ? e.counter.live : 0;
    size_t comparable = foot_total;

    printf("%-8s %-7s %-8s %5d %5d %8ld %8ld %10zu %10zu %10zu %9.1f %8.2f\n",
           engine,
           e.is_ghostty ? (e.counting ? (e.compress ? "cnt+z" : "cnt")
                                      : (e.compress ? "def+z" : "def"))
                        : "-",
           payload, cols, rows, lines, sb, heap_total, counted, foot_total,
           retained > 0 ? (double)comparable / (double)retained : 0.0,
           retained > 0 ? (double)comparable / (double)(retained * cols) : 0.0);

    engine_close(&e);
    free(line);
    free(feed);
    return 0;
}
