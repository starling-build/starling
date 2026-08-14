/* SPSC byte ring + paced-reader helpers for the Darwin pty reader.
 *
 * The paced reader (Pty._startReaderPaced) overlaps pty reads with parsing
 * WITHOUT the eager-reader trap every earlier ring design hit: a reader that
 * re-arms read(2) immediately catches the tty queue empty and sleeps a full
 * writer-wake round trip per kilobyte (~242 MB/s ceiling, measured), while
 * the inline reader's parse accidentally paced it (~282 MB/s on ascii — and
 * 209 on escape-dense alt_screen, where the parse overshoots the refill
 * window). A fixed ~1us busy pace between reads keeps the writer refilling
 * in lockstep and holds ~290 MB/s on EVERY content shape (probe: scratch
 * ptyread_mac mode 13, 2026-08-14). mach_wait_until cannot replace the busy
 * wait: the kernel stretches 1us sleeps to ~5 and the pipeline collapses to
 * the eager floor.
 *
 * SPSC: one producer (reader thread), one consumer (parse thread). The
 * consumer polls with usleep(ST_RING_EMPTY_US) when empty — at 8 MB of
 * headroom that is ~26 ms of slack, and a calm consumer measurably beats an
 * eager one (100us polling cost ~8% of throughput in the probe).
 */
#if defined(__APPLE__)
#include "starling_term.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <mach/mach_time.h>

#define ST_RING_EMPTY_US 500

struct StRing {
    unsigned char *buf;
    size_t cap;
    _Atomic unsigned long long head;   /* consumer position */
    _Atomic unsigned long long tail;   /* producer position */
    _Atomic int closed;
};

StRing *st_ring_new(size_t cap) {
    StRing *r = calloc(1, sizeof *r);
    if (!r) return NULL;
    r->buf = malloc(cap);
    if (!r->buf) { free(r); return NULL; }
    r->cap = cap;
    return r;
}

void st_ring_free(StRing *r) {
    if (!r) return;
    free(r->buf);
    free(r);
}

void st_ring_write(StRing *r, const unsigned char *p, size_t n) {
    unsigned long long t = atomic_load_explicit(&r->tail, memory_order_relaxed);
    /* Wait for space. Never taken in practice: the consumer runs at a
       fraction of the producer's rate and the ring holds megabytes. */
    while (t + n - atomic_load_explicit(&r->head, memory_order_acquire) > r->cap)
        usleep(ST_RING_EMPTY_US);
    size_t off = (size_t)(t % r->cap);
    if (n > r->cap - off) {
        size_t first = r->cap - off;
        memcpy(r->buf + off, p, first);
        memcpy(r->buf, p + first, n - first);
    } else {
        memcpy(r->buf + off, p, n);
    }
    atomic_store_explicit(&r->tail, t + n, memory_order_release);
}

size_t st_ring_take(StRing *r, const unsigned char **out) {
    unsigned long long h = atomic_load_explicit(&r->head, memory_order_relaxed);
    for (;;) {
        unsigned long long t = atomic_load_explicit(&r->tail, memory_order_acquire);
        if (t != h) {
            size_t off = (size_t)(h % r->cap);
            unsigned long long run = t - h;
            if (run > r->cap - off) run = r->cap - off;   /* stop at the wrap */
            *out = r->buf + off;
            return (size_t)run;
        }
        if (atomic_load_explicit(&r->closed, memory_order_acquire)) return 0;
        usleep(ST_RING_EMPTY_US);
    }
}

void st_ring_consume(StRing *r, size_t n) {
    atomic_fetch_add_explicit(&r->head, n, memory_order_release);
}

void st_ring_close(StRing *r) {
    atomic_store_explicit(&r->closed, 1, memory_order_release);
}

void st_pace(unsigned long long ns) {
    static _Atomic unsigned int numer, denom;
    unsigned int nu = atomic_load_explicit(&numer, memory_order_relaxed);
    unsigned int de = atomic_load_explicit(&denom, memory_order_relaxed);
    if (!de) {
        mach_timebase_info_data_t tb;
        mach_timebase_info(&tb);
        atomic_store_explicit(&numer, tb.numer, memory_order_relaxed);
        atomic_store_explicit(&denom, tb.denom, memory_order_relaxed);
        nu = tb.numer; de = tb.denom;
    }
    unsigned long long ticks = ns * de / nu;
    unsigned long long t0 = mach_absolute_time();
    while (mach_absolute_time() - t0 < ticks) ;
}
#endif /* __APPLE__ */
