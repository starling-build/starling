/* Isolate the terminal's READ path: a real pty, a real `cat`, the real core.
 *
 *   ptyread <mode> <file> [cols rows]
 *     0 = blocking 64K reads, one feed per read
 *     1 = poll + non-blocking drain, one feed per batch
 *     2 = transport floor: read and discard, no parse
 *     3 = ring: reader thread + parser thread, one publish per read
 *         (what TerminalApp did before the drain change)
 *     4 = ring + drain-into-slot: publish once per FULL slot or empty pty
 *         (what TerminalApp does now — see Pty.swift startReader)
 *
 * Mode 0 also models the per-chunk Swift cost the app pays on top of feed: an
 * allocation and a copy of the chunk (`Array(buf[0..<n])`). Mode 1 has none.
 * Prints wall, syscall counts and the batch-size distribution, so the question
 * "does draining actually coalesce, or does the pty hand back 4K regardless?"
 * is answered with a number instead of a guess. */
#define _GNU_SOURCE
#include "include/starling_term.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <time.h>
#include <errno.h>
#include <pty.h>
#include <pthread.h>
#include <sys/wait.h>

static double now(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}

/* ---- mode 3: reader thread fills a ring, parser thread drains it ----------
   The point is that the pty keeps being drained while the parser is busy, so
   wall time becomes max(transport, parse) instead of transport + parse. The
   ring is small and blocking in both directions, which keeps the backpressure
   the single-threaded loop already had. */
#define RING_SLOTS 8
#define SLOT_CAP   65536

typedef struct {
    unsigned char buf[RING_SLOTS][SLOT_CAP];
    size_t        len[RING_SLOTS];
    int           head, tail, count, eof;
    pthread_mutex_t m;
    pthread_cond_t  not_empty, not_full;
} Ring;

typedef struct { int fd; Ring *r; long reads; size_t total; } RdArg;
typedef struct { StarlingTerm *t; Ring *r; long feeds; } FdArg;


/* ---- mode 4: ring + drain-into-slot --------------------------------------
   Reader: one blocking-ish read (via poll) then keep reading non-blocking
   into the SAME slot until it is full or the pty is empty, then publish once.
   Coalesces only bytes already queued in the kernel, so a short burst still
   publishes immediately; a flood publishes ~64K per ring pass instead of
   ~700B, cutting lock/condvar traffic ~80x. */
static void *rd4_thread(void *p) {
    RdArg *a = p; Ring *r = a->r;
    int flags = fcntl(a->fd, F_GETFL, 0);
    fcntl(a->fd, F_SETFL, flags | O_NONBLOCK);
    struct pollfd pf = { .fd = a->fd, .events = POLLIN };
    for (;;) {
        pthread_mutex_lock(&r->m);
        while (r->count == RING_SLOTS) pthread_cond_wait(&r->not_full, &r->m);
        int slot = r->tail;
        pthread_mutex_unlock(&r->m);

        size_t got = 0;
        for (;;) {
            ssize_t n = read(a->fd, r->buf[slot] + got, SLOT_CAP - got);
            if (n > 0) {
                a->reads++; got += (size_t)n; a->total += (size_t)n;
                if (got == SLOT_CAP) break;
                continue;
            }
            if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                if (got > 0) break;              /* publish what we have */
                if (poll(&pf, 1, -1) < 0 && errno != EINTR) { got = 0; goto eof4; }
                continue;
            }
            if (n < 0 && errno == EINTR) continue;
            goto eof4;                            /* EOF or error */
        }
        pthread_mutex_lock(&r->m);
        r->len[slot] = got;
        r->tail = (r->tail + 1) % RING_SLOTS;
        r->count++;
        pthread_cond_signal(&r->not_empty);
        pthread_mutex_unlock(&r->m);
        continue;
    eof4:
        pthread_mutex_lock(&r->m);
        if (got) { r->len[slot] = got; r->tail = (r->tail + 1) % RING_SLOTS; r->count++; }
        r->eof = 1;
        pthread_cond_signal(&r->not_empty);
        pthread_mutex_unlock(&r->m);
        return NULL;
    }
}

static void *rd_thread(void *p) {
    RdArg *a = p; Ring *r = a->r;
    for (;;) {
        pthread_mutex_lock(&r->m);
        while (r->count == RING_SLOTS) pthread_cond_wait(&r->not_full, &r->m);
        int slot = r->tail;
        pthread_mutex_unlock(&r->m);

        ssize_t n = read(a->fd, r->buf[slot], SLOT_CAP);
        a->reads++;
        if (n <= 0 && !(n < 0 && errno == EINTR)) {
            pthread_mutex_lock(&r->m);
            r->eof = 1;
            pthread_cond_signal(&r->not_empty);
            pthread_mutex_unlock(&r->m);
            return NULL;
        }
        if (n <= 0) continue;
        a->total += (size_t)n;

        pthread_mutex_lock(&r->m);
        r->len[slot] = (size_t)n;
        r->tail = (r->tail + 1) % RING_SLOTS;
        r->count++;
        pthread_cond_signal(&r->not_empty);
        pthread_mutex_unlock(&r->m);
    }
}

static void *fd_thread(void *p) {
    FdArg *a = p; Ring *r = a->r;
    for (;;) {
        pthread_mutex_lock(&r->m);
        while (r->count == 0 && !r->eof) pthread_cond_wait(&r->not_empty, &r->m);
        if (r->count == 0 && r->eof) { pthread_mutex_unlock(&r->m); return NULL; }
        int slot = r->head;
        size_t len = r->len[slot];
        pthread_mutex_unlock(&r->m);

        starling_term_feed(a->t, r->buf[slot], len);
        a->feeds++;

        pthread_mutex_lock(&r->m);
        r->head = (r->head + 1) % RING_SLOTS;
        r->count--;
        pthread_cond_signal(&r->not_full);
        pthread_mutex_unlock(&r->m);
    }
}

static void run_split_fn(void *(*rfn)(void *), int fd, StarlingTerm *t,
                         long *reads, long *feeds, size_t *total, double *elapsed) {
    static Ring r;
    memset(&r, 0, sizeof r);
    pthread_mutex_init(&r.m, NULL);
    pthread_cond_init(&r.not_empty, NULL);
    pthread_cond_init(&r.not_full, NULL);
    RdArg ra = { .fd = fd, .r = &r };
    FdArg fa = { .t = t, .r = &r };
    pthread_t rt, ft;
    double t0 = now();
    pthread_create(&rt, NULL, rfn, &ra);
    pthread_create(&ft, NULL, fd_thread, &fa);
    pthread_join(rt, NULL);
    pthread_join(ft, NULL);
    *elapsed = now() - t0;
    *reads = ra.reads; *feeds = fa.feeds; *total = ra.total;
}

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: ptyread <0|1|2|3|4> <file> [cols rows]\n"); return 2; }
    int mode = atoi(argv[1]);
    const char *file = argv[2];
    int cols = argc > 3 ? atoi(argv[3]) : 201, rows = argc > 4 ? atoi(argv[4]) : 47;

    int master;
    struct winsize ws = { .ws_row = (unsigned short)rows, .ws_col = (unsigned short)cols };
    pid_t pid = forkpty(&master, NULL, NULL, &ws);
    if (pid < 0) { perror("forkpty"); return 1; }
    if (pid == 0) { execlp("cat", "cat", file, (char *)NULL); _exit(127); }

    if (mode == 1) fcntl(master, F_SETFL, fcntl(master, F_GETFL, 0) | O_NONBLOCK);

    const size_t cap = 65536;
    unsigned char *buf = malloc(cap);
    StarlingTerm *t = starling_term_new(cols, rows);

    long reads = 0, polls = 0, feeds = 0, eagain = 0;
    size_t total = 0;
    long b4k = 0, b16k = 0, b64k = 0;
    double t0 = now();

    if (mode == 3 || mode == 4) {      /* split: read on one thread, feed on another */
        double el3;
        run_split_fn(mode == 4 ? rd4_thread : rd_thread,
                     master, t, &reads, &feeds, &total, &el3);
        int st3; waitpid(pid, &st3, 0); close(master);
        printf("mode %d  wall %.3f s  %.1f MB  %.0f MB/s\n", mode, el3, total / 1e6, total / 1e6 / el3);
        printf("   reads %ld  feeds %ld  mean batch %.0f B\n",
               reads, feeds, feeds ? (double)total / feeds : 0);
        starling_term_free(t); free(buf);
        return 0;
    }

    for (;;) {
        if (mode == 2) {                     /* transport floor: read, discard */
            ssize_t n = read(master, buf, cap);
            reads++;
            if (n <= 0) { if (n < 0 && errno == EINTR) continue; break; }
            total += (size_t)n; feeds++;
            if (n <= 4096) b4k++; else if (n <= 16384) b16k++; else b64k++;
        } else if (mode == 0) {
            ssize_t n = read(master, buf, cap);
            reads++;
            if (n <= 0) { if (n < 0 && errno == EINTR) continue; break; }
            /* what the Swift side pays per chunk today: Array(buf[0..<n]) */
            unsigned char *copy = malloc((size_t)n);
            memcpy(copy, buf, (size_t)n);
            starling_term_feed(t, copy, (size_t)n);
            free(copy);
            feeds++; total += (size_t)n;
            if (n <= 4096) b4k++; else if (n <= 16384) b16k++; else b64k++;
        } else {
            struct pollfd p = { .fd = master, .events = POLLIN };
            if (poll(&p, 1, -1) < 0) { if (errno == EINTR) continue; break; }
            polls++;
            size_t got = 0; int closed = 0;
            while (got < cap) {
                ssize_t n = read(master, buf + got, cap - got);
                reads++;
                if (n > 0) { got += (size_t)n; continue; }
                if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) { eagain++; break; }
                if (n < 0 && errno == EINTR) continue;
                closed = 1; break;
            }
            if (got) {
                starling_term_feed(t, buf, got);   /* no copy, one feed per batch */
                feeds++; total += got;
                if (got <= 4096) b4k++; else if (got <= 16384) b16k++; else b64k++;
            }
            if (closed) break;
        }
    }
    double el = now() - t0;
    int st; waitpid(pid, &st, 0);
    close(master);

    printf("mode %d  wall %.3f s  %.1f MB  %.0f MB/s\n", mode, el, total / 1e6, total / 1e6 / el);
    printf("   reads %ld  polls %ld  eagain %ld  feeds %ld  mean batch %.0f B\n",
           reads, polls, eagain, feeds, feeds ? (double)total / feeds : 0);
    printf("   batches <=4K %ld   <=16K %ld   >16K %ld\n", b4k, b16k, b64k);
    starling_term_free(t); free(buf);
    return 0;
}
