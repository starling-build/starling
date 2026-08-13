/* The macOS read path, measured: a real pty, a real `cat`, the real C core.
 *
 *   ptyread_mac <mode> <file> [cols rows]
 *     0  = blocking reads, parse INLINE on the same thread   (what ships)
 *     4  = classic ring: reader thread + parser thread, one condvar handoff
 *          per read (what Linux/Windows ship, and what Darwin gave up)
 *     11 = SPSC byte ring with a spin/yield handoff and NO condvar in the
 *          hot path — the reader never stops draining the pty, the parser
 *          feeds whatever has accumulated
 *
 * Why 11 exists. On macOS the pty hands back at most 1024 bytes per read (a
 * hard kernel queue limit — `ptyprobe` reports max=1024 on every workload), so
 * a flood is ~432k producer/consumer round trips for the 442 MB suite. With
 * the inline reader, the pty is UNDRAINED for the whole time we parse, so
 * `cat` sits blocked on a full queue and the two costs serialize: a sample of
 * 05_unicode puts 64% of the reader thread inside read(2). The ring overlaps
 * them but pays a condition-variable round trip per kilobyte to hand over a
 * kilobyte of parse, which is why it lost. Mode 11 keeps the overlap and
 * drops the handoff: two indices, release/acquire, and a bounded spin.
 *
 * Prints wall, MB/s, read and feed counts, mean feed size, and how often the
 * consumer found the ring empty — so "does the overlap actually happen" is a
 * number rather than a hope.
 */
#include "starling_term.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <sched.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <util.h>

/* ── shared ────────────────────────────────────────────────────────────── */

static int master = -1;
static StarlingTerm *term;
static long long n_reads, n_feeds, feed_bytes, n_empty, n_full;

static double now_s(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}

/* ── mode 4: classic slot ring, condvar handoff ────────────────────────── */

#define SLOT_CAP  65536
#define SLOTS     8

static struct {
    unsigned char *buf[SLOTS];
    size_t len[SLOTS];
    int head, tail, count, eof;
    pthread_mutex_t m;
    pthread_cond_t not_empty, not_full;
} R;

static void *rd4_thread(void *unused) {
    (void)unused;
    for (;;) {
        pthread_mutex_lock(&R.m);
        while (R.count == SLOTS) pthread_cond_wait(&R.not_full, &R.m);
        int slot = R.head;
        pthread_mutex_unlock(&R.m);

        ssize_t n = read(master, R.buf[slot], SLOT_CAP);
        if (n <= 0) {
            if (n < 0 && errno == EINTR) continue;
            pthread_mutex_lock(&R.m);
            R.eof = 1;
            pthread_cond_signal(&R.not_empty);
            pthread_mutex_unlock(&R.m);
            return NULL;
        }
        n_reads++;
        pthread_mutex_lock(&R.m);
        R.len[slot] = (size_t)n;
        R.head = (R.head + 1) % SLOTS;
        R.count++;
        pthread_cond_signal(&R.not_empty);
        pthread_mutex_unlock(&R.m);
    }
}

static void run_ring4(void) {
    for (int i = 0; i < SLOTS; i++) R.buf[i] = malloc(SLOT_CAP);
    pthread_mutex_init(&R.m, NULL);
    pthread_cond_init(&R.not_empty, NULL);
    pthread_cond_init(&R.not_full, NULL);
    pthread_t th;
    pthread_create(&th, NULL, rd4_thread, NULL);
    for (;;) {
        pthread_mutex_lock(&R.m);
        while (R.count == 0 && !R.eof) pthread_cond_wait(&R.not_empty, &R.m);
        if (R.count == 0 && R.eof) { pthread_mutex_unlock(&R.m); break; }
        int slot = R.tail;
        size_t len = R.len[slot];
        pthread_mutex_unlock(&R.m);

        starling_term_feed(term, R.buf[slot], len);
        n_feeds++; feed_bytes += len;

        pthread_mutex_lock(&R.m);
        R.tail = (R.tail + 1) % SLOTS;
        R.count--;
        pthread_cond_signal(&R.not_full);
        pthread_mutex_unlock(&R.m);
    }
    pthread_join(th, NULL);
}

/* ── mode 11: SPSC byte ring, spin/yield handoff ───────────────────────── */
//
// One circular byte buffer. The producer owns `head`, the consumer owns
// `tail`; each publishes with a release store and reads the other with an
// acquire load, so no lock is taken on either side.
//
// The ring is sized far above the pty's 1 KB grain (8 MB) for one reason: the
// producer must never be the reason the pty goes undrained. At 8 MB the
// consumer would have to fall a full suite-second behind to fill it.
//
// Idling is bounded, not free-running: a consumer that finds the ring empty
// spins briefly (the producer is likely mid-read), then yields, then sleeps in
// 50 us steps. A terminal is idle almost all of its life, so an unbounded spin
// would burn a core to watch a shell prompt.

#define RING_BYTES (8u << 20)

static unsigned char *ring;
static _Atomic size_t r_head, r_tail;
static _Atomic int r_eof;

static void idle_backoff(int *spins) {
    if (*spins < 64) { (*spins)++; __asm__ __volatile__("yield" ::: "memory"); return; }
    if (*spins < 128) { (*spins)++; sched_yield(); return; }
    struct timespec ts = { 0, 50 * 1000 };
    nanosleep(&ts, NULL);
}

static void *rd11_thread(void *unused) {
    (void)unused;
    for (;;) {
        size_t head = atomic_load_explicit(&r_head, memory_order_relaxed);
        size_t tail = atomic_load_explicit(&r_tail, memory_order_acquire);
        size_t used = head - tail;
        if (used >= RING_BYTES - 1) { n_full++; sched_yield(); continue; }

        /* Read straight into the ring's contiguous free run — no bounce
         * buffer, no copy. Stop at the wrap so one read is one span. */
        size_t off = head & (RING_BYTES - 1);
        size_t room = RING_BYTES - 1 - used;
        size_t contig = RING_BYTES - off;
        size_t want = room < contig ? room : contig;

        ssize_t n = read(master, ring + off, want);
        if (n <= 0) {
            if (n < 0 && errno == EINTR) continue;
            atomic_store_explicit(&r_eof, 1, memory_order_release);
            return NULL;
        }
        n_reads++;
        atomic_store_explicit(&r_head, head + (size_t)n, memory_order_release);
    }
}

static void run_spin_ring(void) {
    ring = malloc(RING_BYTES);
    pthread_t th;
    pthread_create(&th, NULL, rd11_thread, NULL);
    int spins = 0;
    for (;;) {
        size_t tail = atomic_load_explicit(&r_tail, memory_order_relaxed);
        size_t head = atomic_load_explicit(&r_head, memory_order_acquire);
        size_t avail = head - tail;
        if (avail == 0) {
            if (atomic_load_explicit(&r_eof, memory_order_acquire)) break;
            n_empty++;
            idle_backoff(&spins);
            continue;
        }
        spins = 0;
        size_t off = tail & (RING_BYTES - 1);
        size_t contig = RING_BYTES - off;
        size_t len = avail < contig ? avail : contig;

        starling_term_feed(term, ring + off, len);
        n_feeds++; feed_bytes += len;
        atomic_store_explicit(&r_tail, tail + len, memory_order_release);
    }
    pthread_join(th, NULL);
}

/* ── mode 0: inline ────────────────────────────────────────────────────── */

static void run_inline(void) {
    unsigned char *buf = malloc(SLOT_CAP);
    for (;;) {
        ssize_t n = read(master, buf, SLOT_CAP);
        if (n <= 0) {
            if (n < 0 && errno == EINTR) continue;
            break;
        }
        n_reads++;
        starling_term_feed(term, buf, (size_t)n);
        n_feeds++; feed_bytes += n;
    }
    free(buf);
}

/* ── driver ────────────────────────────────────────────────────────────── */

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: ptyread_mac <mode> <file> [cols rows]\n"); return 2; }
    int mode = atoi(argv[1]);
    const char *path = argv[2];
    int cols = argc > 3 ? atoi(argv[3]) : 201;
    int rows = argc > 4 ? atoi(argv[4]) : 47;

    struct winsize ws = { .ws_row = (unsigned short)rows, .ws_col = (unsigned short)cols };
    int slave;
    if (openpty(&master, &slave, NULL, NULL, &ws) < 0) { perror("openpty"); return 1; }

    pid_t pid = fork();
    if (pid == 0) {
        close(master);
        setsid();
        ioctl(slave, TIOCSCTTY, 0);
        dup2(slave, 0); dup2(slave, 1); dup2(slave, 2);
        if (slave > 2) close(slave);
        execlp("cat", "cat", path, (char *)NULL);
        _exit(127);
    }
    close(slave);

    term = starling_term_new(cols, rows);
    double a = now_s();
    switch (mode) {
        case 0:  run_inline();    break;
        case 4:  run_ring4();     break;
        case 11: run_spin_ring(); break;
        default: fprintf(stderr, "unknown mode %d\n", mode); return 2;
    }
    double s = now_s() - a;
    int st; waitpid(pid, &st, 0);

    struct stat { long long sz; } ;
    FILE *f = fopen(path, "rb");
    fseek(f, 0, SEEK_END); double nb = (double)ftell(f); fclose(f);

    printf("mode %-2d  %.3f s  %6.1f MB/s  reads=%-8lld feeds=%-8lld "
           "mean_feed=%-8.0f empty=%-8lld full=%lld\n",
           mode, s, nb / 1e6 / s, n_reads, n_feeds,
           n_feeds ? (double)feed_bytes / n_feeds : 0.0, n_empty, n_full);
    starling_term_free(term);
    return 0;
}
