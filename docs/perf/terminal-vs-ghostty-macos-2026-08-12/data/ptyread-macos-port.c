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
 *     5 = io_uring read loop, discard (PTYREAD_ASYNC=1 adds IOSQE_ASYNC) —
 *         the transport ghostty's nightly uses; needs -luring
 *     6 = paced read(2), discard: nanosleep after each read so the ldisc
 *         accumulates (PTYREAD_PACE_US, default 100)
 *     7 = io_uring multishot read + provided-buffer ring, discard; -luring
 *     8 = drain burst + pace between bursts, discard (PTYREAD_PACE_US)
 *     9 = mode 4 with 256K slots and a ~300us linger on EAGAIN: keep filling
 *         the slot while data is still arriving, publish on slot-full or
 *         quiescence — ~4x fewer ring handoffs (PTYREAD_LINGER_US)
 *
 * Mode 0 also models the per-chunk Swift cost the app pays on top of feed: an
 * allocation and a copy of the chunk (`Array(buf[0..<n])`). Mode 1 has none.
 * Modes 5-7 are transport prototypes: compare their wall against mode 2 (the
 * read(2) floor) — ghostty's live wall sits BELOW that floor on dense_cells /
 * scroll_region / the ascii cat, so the floor is a property of the consumption
 * pattern, not of the pty.
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
#ifdef __APPLE__
#include <util.h>
#else
#include <pty.h>
#endif
#include <pthread.h>
#include <sys/wait.h>
#ifndef __APPLE__
#include <sys/prctl.h>
#endif
#include <signal.h>

#ifdef __APPLE__
/* Linux-only knobs, no-oped for the macOS floor measurement. Timer slack is a
   scheduler hint (modes 6/8/9 pacing); poll stands in for ppoll at ms
   granularity, which is coarser but only affects the linger modes. */
#include <poll.h>
#define prctl(...) (0)
static int ppoll_shim(struct pollfd *f, nfds_t n, const struct timespec *ts, const void *sm) {
    (void)sm;
    int ms = ts ? (int)(ts->tv_sec * 1000 + ts->tv_nsec / 1000000) : -1;
    return poll(f, n, ms);
}
#define ppoll ppoll_shim
#endif

#ifndef __APPLE__
#include <liburing.h>
#endif

static double now(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}

static void print_cat_time(int timed) {
    if (!timed) return;
    FILE *f = fopen("/tmp/ptyread-cat-time.txt", "r");
    if (!f) return;
    char line[256];
    while (fgets(line, sizeof line, f)) fputs(line, stdout);
    fclose(f);
}

/* ---- mode 3: reader thread fills a ring, parser thread drains it ----------
   The point is that the pty keeps being drained while the parser is busy, so
   wall time becomes max(transport, parse) instead of transport + parse. The
   ring is small and blocking in both directions, which keeps the backpressure
   the single-threaded loop already had. */
#define RING_SLOTS 8
#define SLOT_CAP   65536
#define MAX_SLOTS  16

typedef struct {
    unsigned char *storage;        /* nslots x cap, one malloc */
    size_t         cap;
    int            nslots;
    size_t        len[MAX_SLOTS];
    int           head, tail, count, eof;
    pthread_mutex_t m;
    pthread_cond_t  not_empty, not_full;
} Ring;

static unsigned char *slotbuf(Ring *r, int i) { return r->storage + (size_t)i * r->cap; }

typedef struct { int fd; Ring *r; long reads; size_t total;
                 StarlingTerm *t; long inlines; } RdArg;   /* t, inlines: mode 10 */
typedef struct { StarlingTerm *t; Ring *r; long feeds; } FdArg;


/* ---- mode 4: ring + drain-into-slot --------------------------------------
   Reader: one blocking-ish read (via poll) then keep reading non-blocking
   into the SAME slot until it is full or the pty is empty, then publish once.
   Coalesces only bytes already queued in the kernel, so a short burst still
   publishes immediately; a flood publishes ~64K per ring pass instead of
   ~700B, cutting lock/condvar traffic ~80x. */
static long linger_us;   /* mode 9: how long to wait out an EAGAIN mid-fill */

static void *rd4_thread(void *p) {
    RdArg *a = p; Ring *r = a->r;
    int flags = fcntl(a->fd, F_GETFL, 0);
    fcntl(a->fd, F_SETFL, flags | O_NONBLOCK);
    if (linger_us) prctl(PR_SET_TIMERSLACK, 1000UL);
    struct pollfd pf = { .fd = a->fd, .events = POLLIN };
    for (;;) {
        pthread_mutex_lock(&r->m);
        while (r->count == r->nslots) pthread_cond_wait(&r->not_full, &r->m);
        int slot = r->tail;
        pthread_mutex_unlock(&r->m);

        size_t got = 0;
        for (;;) {
            ssize_t n = read(a->fd, slotbuf(r, slot) + got, r->cap - got);
            if (n > 0) {
                a->reads++; got += (size_t)n; a->total += (size_t)n;
                if (got == r->cap) break;
                continue;
            }
            if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                if (got > 0) {
                    /* mode 9: data already in hand, but more may be right
                       behind it — wait out one linger before handing off.
                       POLLIN inside the window: keep filling this slot.
                       Quiet for the whole window: genuine pause, publish. */
                    if (linger_us) {
                        struct timespec lts = { 0, linger_us * 1000L };
                        pf.revents = 0;
                        int pr = ppoll(&pf, 1, &lts, NULL);
                        if (pr > 0 && (pf.revents & POLLIN)) continue;
                        if (pr < 0 && errno == EINTR) continue;
                    }
                    break;                       /* publish what we have */
                }
                if (poll(&pf, 1, -1) < 0 && errno != EINTR) { got = 0; goto eof4; }
                continue;
            }
            if (n < 0 && errno == EINTR) continue;
            goto eof4;                            /* EOF or error */
        }
        pthread_mutex_lock(&r->m);
        r->len[slot] = got;
        r->tail = (r->tail + 1) % r->nslots;
        r->count++;
        pthread_cond_signal(&r->not_empty);
        pthread_mutex_unlock(&r->m);
        continue;
    eof4:
        pthread_mutex_lock(&r->m);
        if (got) { r->len[slot] = got; r->tail = (r->tail + 1) % r->nslots; r->count++; }
        r->eof = 1;
        pthread_cond_signal(&r->not_empty);
        pthread_mutex_unlock(&r->m);
        return NULL;
    }
}

/* ---- mode 10: adaptive inline parse -------------------------------------
   Modes 4 and 9 proved the residual over the read floor is not the handoff
   COUNT (cutting it 4x moved nothing) — it is the second busy thread in the
   pipeline. Ghostty sits on the floor by parsing inline on its read thread.
   So: when the drain ended at EAGAIN (reader is ahead of the pty) and the
   ring is empty (parser idle, every prior byte parsed — feed order and
   exclusivity hold), parse the slot HERE and skip the ring. When the slot
   fills without going dry (parse cannot keep up: escape-heavy streams),
   publish as mode 4 — the split engages exactly where it wins. */
static void *rd10_thread(void *p) {
    RdArg *a = p; Ring *r = a->r;
    fcntl(a->fd, F_SETFL, fcntl(a->fd, F_GETFL, 0) | O_NONBLOCK);
    struct pollfd pf = { .fd = a->fd, .events = POLLIN };
    for (;;) {
        pthread_mutex_lock(&r->m);
        while (r->count == r->nslots) pthread_cond_wait(&r->not_full, &r->m);
        int slot = r->tail;
        pthread_mutex_unlock(&r->m);

        size_t got = 0; int dry = 0;
        for (;;) {
            ssize_t n = read(a->fd, slotbuf(r, slot) + got, r->cap - got);
            if (n > 0) {
                a->reads++; got += (size_t)n; a->total += (size_t)n;
                if (got == r->cap) break;
                continue;
            }
            if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                if (got > 0) { dry = 1; break; }
                if (poll(&pf, 1, -1) < 0 && errno != EINTR) { got = 0; goto eofB; }
                continue;
            }
            if (n < 0 && errno == EINTR) continue;
            goto eofB;
        }
        if (dry) {
            pthread_mutex_lock(&r->m);
            int empty = (r->count == 0);
            pthread_mutex_unlock(&r->m);
            if (empty) {
                starling_term_feed(a->t, slotbuf(r, slot), got);
                a->inlines++;
                continue;                    /* slot never published; reuse it */
            }
        }
        pthread_mutex_lock(&r->m);
        r->len[slot] = got;
        r->tail = (r->tail + 1) % r->nslots;
        r->count++;
        pthread_cond_signal(&r->not_empty);
        pthread_mutex_unlock(&r->m);
        continue;
    eofB:
        pthread_mutex_lock(&r->m);
        if (got) { r->len[slot] = got; r->tail = (r->tail + 1) % r->nslots; r->count++; }
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
        while (r->count == r->nslots) pthread_cond_wait(&r->not_full, &r->m);
        int slot = r->tail;
        pthread_mutex_unlock(&r->m);

        ssize_t n = read(a->fd, slotbuf(r, slot), r->cap);
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
        r->tail = (r->tail + 1) % r->nslots;
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

        starling_term_feed(a->t, slotbuf(r, slot), len);
        a->feeds++;

        pthread_mutex_lock(&r->m);
        r->head = (r->head + 1) % r->nslots;
        r->count--;
        pthread_cond_signal(&r->not_full);
        pthread_mutex_unlock(&r->m);
    }
}

static void run_split_fn(void *(*rfn)(void *), int fd, StarlingTerm *t,
                         size_t cap, int nslots,
                         long *reads, long *feeds, size_t *total, double *elapsed) {
    static Ring r;
    memset(&r, 0, sizeof r);
    r.cap = cap; r.nslots = nslots;
    r.storage = malloc(cap * (size_t)nslots);
    pthread_mutex_init(&r.m, NULL);
    pthread_cond_init(&r.not_empty, NULL);
    pthread_cond_init(&r.not_full, NULL);
    RdArg ra = { .fd = fd, .r = &r, .t = t };
    FdArg fa = { .t = t, .r = &r };
    pthread_t rt, ft;
    double t0 = now();
    pthread_create(&rt, NULL, rfn, &ra);
    pthread_create(&ft, NULL, fd_thread, &fa);
    pthread_join(rt, NULL);
    pthread_join(ft, NULL);
    *elapsed = now() - t0;
    *reads = ra.reads; *feeds = fa.feeds + ra.inlines; *total = ra.total;
    if (ra.inlines)
        printf("   inline feeds %ld  ring feeds %ld\n", ra.inlines, fa.feeds);
    free(r.storage);
}

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: ptyread <mode 0-9> <file> [cols rows]\n"); return 2; }
    int mode = atoi(argv[1]);
    const char *file = argv[2];
    int cols = argc > 3 ? atoi(argv[3]) : 201, rows = argc > 4 ? atoi(argv[4]) : 47;

    int master;
    struct winsize ws = { .ws_row = (unsigned short)rows, .ws_col = (unsigned short)cols };
    pid_t pid = forkpty(&master, NULL, NULL, &ws);
    if (pid < 0) { perror("forkpty"); return 1; }
    /* PTYREAD_TIME=1 wraps cat in /usr/bin/time — the WRITER's wall, which is
       what `time cat` inside a live terminal (the bench metric) reports. The
       reader-side wall this harness prints ends at EOF instead and includes
       exec + final drain, so the two clocks differ; compare like with like. */
    int timed = getenv("PTYREAD_TIME") != NULL;
    const char *cmd = getenv("PTYREAD_CMD");   /* child override; it writes
                                                  /tmp/ptyread-cat-time.txt */
    if (cmd) timed = 1;
    if (pid == 0) {
        if (cmd)
            execlp(cmd, cmd, (char *)NULL);
        if (timed)
            execlp("/usr/bin/time", "time", "-o", "/tmp/ptyread-cat-time.txt",
                   "-f", "cat: %e wall  %U user  %S sys", "cat", file, (char *)NULL);
        execlp("cat", "cat", file, (char *)NULL);
        _exit(127);
    }

    if (mode == 1) fcntl(master, F_SETFL, fcntl(master, F_GETFL, 0) | O_NONBLOCK);

    const size_t cap = 65536;
    unsigned char *buf = malloc(cap);
    StarlingTerm *t = starling_term_new(cols, rows);

    long reads = 0, polls = 0, feeds = 0, eagain = 0;
    size_t total = 0;
    long b4k = 0, b16k = 0, b64k = 0;
    double t0 = now();

    if (mode == 3 || mode == 4 || mode == 9 || mode == 10) {  /* split modes */
        double el3;
        if (mode == 9) {
            linger_us = getenv("PTYREAD_LINGER_US")
                ? atol(getenv("PTYREAD_LINGER_US")) : 300;
        }
        void *(*rfn)(void *) = mode == 3 ? rd_thread
                             : mode == 10 ? rd10_thread : rd4_thread;
        run_split_fn(rfn, master, t,
                     mode == 9 ? 262144 : SLOT_CAP,
                     mode == 9 ? 4 : RING_SLOTS,
                     &reads, &feeds, &total, &el3);
        int st3; waitpid(pid, &st3, 0); close(master);
        printf("mode %d  wall %.3f s  %.1f MB  %.0f MB/s\n", mode, el3, total / 1e6, total / 1e6 / el3);
        printf("   reads %ld  feeds %ld  mean batch %.0f B\n",
               reads, feeds, feeds ? (double)total / feeds : 0);
        print_cat_time(timed);
        starling_term_free(t); free(buf);
        return 0;
    }

    #ifndef __APPLE__
if (mode == 5) {              /* io_uring read loop, discard */
        struct io_uring ring;
        int rc = io_uring_queue_init(64, &ring, 0);
        if (rc < 0) { fprintf(stderr, "io_uring_queue_init: %s\n", strerror(-rc)); return 1; }
        int async = getenv("PTYREAD_ASYNC") != NULL;
        for (;;) {
            struct io_uring_sqe *sqe = io_uring_get_sqe(&ring);
            io_uring_prep_read(sqe, master, buf, cap, (__u64)-1);
            if (async) sqe->flags |= IOSQE_ASYNC;
            io_uring_submit_and_wait(&ring, 1);
            struct io_uring_cqe *cqe;
            if (io_uring_peek_cqe(&ring, &cqe) < 0) continue;
            int n = cqe->res;
            io_uring_cqe_seen(&ring, cqe);
            if (n == -EINTR) continue;
            if (n <= 0) {
                if (n < 0 && n != -EIO)   /* EIO = child closed the slave */
                    fprintf(stderr, "mode 5 read: %s\n", strerror(-n));
                break;
            }
            reads++; feeds++; total += (size_t)n;
            if (n <= 4096) b4k++; else if (n <= 16384) b16k++; else b64k++;
        }
        io_uring_queue_exit(&ring);
        kill(pid, SIGKILL);   /* no-op after EOF; unwedges cat if we bailed */
        goto done;
    }
#else
    if (mode == 5) { fprintf(stderr, "mode needs io_uring (Linux only)\n"); return 2; }
#endif

    #ifndef __APPLE__
if (mode == 7) {              /* io_uring multishot + provided buffers */
        enum { MS_BUFS = 64, MS_BUFSZ = 16384 };
        struct io_uring ring;
        int rc = io_uring_queue_init(128, &ring, 0);
        if (rc < 0) { fprintf(stderr, "io_uring_queue_init: %s\n", strerror(-rc)); return 1; }
        int err = 0;
        struct io_uring_buf_ring *br = io_uring_setup_buf_ring(&ring, MS_BUFS, 0, 0, &err);
        if (!br) { fprintf(stderr, "setup_buf_ring: %s\n", strerror(-err)); return 1; }
        unsigned char *bufs = malloc((size_t)MS_BUFS * MS_BUFSZ);
        for (int i = 0; i < MS_BUFS; i++)
            io_uring_buf_ring_add(br, bufs + (size_t)i * MS_BUFSZ, MS_BUFSZ, i,
                                  io_uring_buf_ring_mask(MS_BUFS), i);
        io_uring_buf_ring_advance(br, MS_BUFS);
        int armed = 0, dead = 0;
        while (!dead) {
            if (!armed) {
                struct io_uring_sqe *sqe = io_uring_get_sqe(&ring);
                io_uring_prep_read_multishot(sqe, master, 0, (__u64)-1, 0);
                io_uring_submit(&ring);
                armed = 1;
            }
            struct io_uring_cqe *cqe;
            int wrc = io_uring_wait_cqe(&ring, &cqe);
            if (wrc < 0) { if (wrc == -EINTR) continue; break; }
            unsigned head; int seen = 0;
            io_uring_for_each_cqe(&ring, head, cqe) {
                seen++;
                int n = cqe->res;
                if (!(cqe->flags & IORING_CQE_F_MORE)) armed = 0;
                if (n <= 0) {
                    if (n != -ENOBUFS && n != -EINTR) {
                        if (n < 0 && n != -EIO)
                            fprintf(stderr, "mode 7 read: %s\n", strerror(-n));
                        dead = 1;
                    }
                } else {
                    reads++; feeds++; total += (size_t)n;
                    if (n <= 4096) b4k++; else if (n <= 16384) b16k++; else b64k++;
                    if (cqe->flags & IORING_CQE_F_BUFFER) {
                        int bid = (int)(cqe->flags >> IORING_CQE_BUFFER_SHIFT);
                        io_uring_buf_ring_add(br, bufs + (size_t)bid * MS_BUFSZ, MS_BUFSZ, bid,
                                              io_uring_buf_ring_mask(MS_BUFS), 0);
                        io_uring_buf_ring_advance(br, 1);
                    }
                }
            }
            io_uring_cq_advance(&ring, (unsigned)seen);
        }
        free(bufs);
        io_uring_queue_exit(&ring);
        kill(pid, SIGKILL);
        goto done;
    }
#else
    if (mode == 7) { fprintf(stderr, "mode needs io_uring (Linux only)\n"); return 2; }
#endif


    long pace_us = getenv("PTYREAD_PACE_US") ? atol(getenv("PTYREAD_PACE_US")) : 100;
    if (mode == 6 || mode == 8) prctl(PR_SET_TIMERSLACK, 1000UL);  /* default slack is 50us */
    struct timespec pace_ts = { .tv_sec = 0, .tv_nsec = pace_us * 1000L };

    if (mode == 8) {   /* drain burst + pace: ghostty's rhythm, minus the parse.
                          Strace of the nightly shows one thread alternating
                          drain-to-dry bursts with ~250us of parsing; during the
                          pause the pty refills in big strides (4-27KB reads)
                          instead of 600-850B, and the writer's flush path runs
                          without per-chunk reader wakeups. Mode 6 fails because
                          a single read after the pause caps at the 4K ldisc
                          buffer; the burst collects the flip-buffer backlog. */
        fcntl(master, F_SETFL, fcntl(master, F_GETFL, 0) | O_NONBLOCK);
        struct pollfd p8 = { .fd = master, .events = POLLIN };
        int dead8 = 0;
        while (!dead8) {
            size_t got = 0;
            for (;;) {
                ssize_t n = read(master, buf + got, cap - got);
                reads++;
                if (n > 0) { got += (size_t)n; if (got == cap) break; continue; }
                if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) { eagain++; break; }
                if (n < 0 && errno == EINTR) continue;
                dead8 = 1; break;
            }
            if (got) {
                feeds++; total += got;
                if (got <= 4096) b4k++; else if (got <= 16384) b16k++; else b64k++;
                nanosleep(&pace_ts, NULL);   /* let the pty refill in peace */
            } else if (!dead8) {
                if (poll(&p8, 1, -1) < 0 && errno != EINTR) dead8 = 1;
                polls++;
            }
        }
        goto done;
    }

    for (;;) {
        if (mode == 2 || mode == 6) {        /* transport floor: read, discard */
            ssize_t n = read(master, buf, cap);
            reads++;
            if (n <= 0) { if (n < 0 && errno == EINTR) continue; break; }
            total += (size_t)n; feeds++;
            if (n <= 4096) b4k++; else if (n <= 16384) b16k++; else b64k++;
            /* mode 6: let the ldisc accumulate before the next read. Idle
               cost is nil — after the last read of a burst the sleep just
               precedes a read that would have blocked anyway. */
            if (mode == 6) nanosleep(&pace_ts, NULL);
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
done:;
    double el = now() - t0;
    int st; waitpid(pid, &st, 0);
    close(master);

    printf("mode %d  wall %.3f s  %.1f MB  %.0f MB/s\n", mode, el, total / 1e6, total / 1e6 / el);
    printf("   reads %ld  polls %ld  eagain %ld  feeds %ld  mean batch %.0f B\n",
           reads, polls, eagain, feeds, feeds ? (double)total / feeds : 0);
    printf("   batches <=4K %ld   <=16K %ld   >16K %ld\n", b4k, b16k, b64k);
    print_cat_time(timed);
    starling_term_free(t); free(buf);
    return 0;
}
