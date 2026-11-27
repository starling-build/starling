// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/*
 * A zwlr_data_control_v1 clipboard client on a private thread.
 * See include/WaylandClipboardBridge.h for the contract and the rationale.
 */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE   /* pipe2 */
#endif

#include "include/WaylandClipboardBridge.h"

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/eventfd.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>

#include "wlr-data-control-unstable-v1-client-protocol.h"

/* Every transfer is bounded. A selection owner that is stopped, wedged, or
 * simply slow must degrade to an empty paste, never to a hung app.
 *
 * Overridable so the unit test can assert the bound in milliseconds instead of
 * spending two seconds per case proving it. */
#ifndef WLCLIP_TIMEOUT_MS
#define WLCLIP_TIMEOUT_MS 2000
#endif
#define WLCLIP_MAX_BYTES  (16 * 1024 * 1024)

/* Preference order for "this offer is text". Highest rank wins. */
static int mime_rank(const char* m) {
    if (!strcmp(m, "text/plain;charset=utf-8")) return 100;
    if (!strcmp(m, "text/plain;charset=UTF-8")) return 99;
    if (!strcmp(m, "text/plain"))               return 90;
    if (!strcmp(m, "UTF8_STRING"))              return 80;
    if (!strcmp(m, "STRING"))                   return 70;
    if (!strcmp(m, "TEXT"))                     return 60;
    if (!strncmp(m, "text/", 5))                return 50;
    return 0;
}

/* Mimes we advertise when WE own the selection. Ordered best-first; the list is
 * deliberately generous because GTK, Qt and Chromium each ask for a different
 * spelling of "plain text". */
static const char* const kOfferedMimes[] = {
    "text/plain;charset=utf-8",
    "text/plain",
    "UTF8_STRING",
    "STRING",
    "TEXT",
};
#define kOfferedMimeCount ((int)(sizeof(kOfferedMimes) / sizeof(kOfferedMimes[0])))

/* Most MIME types one offer is remembered with. Real owners advertise a
 * dozen or so (LibreOffice about 20); past this the extras are ignored, which
 * only means they cannot be asked for by name. */
#define WLCLIP_MAX_OFFER_MIMES 64

struct OfferState {
    char  mime[128];     /* the best text type, for wlclip_read_text */
    int   rank;
    char* mimes[WLCLIP_MAX_OFFER_MIMES];   /* every type, in offer order */
    int   n_mimes;
};

/* One copy: the text plus any number of other flavours (text/html, image/png,
 * an app's private format). The text is served for every kOfferedMimes
 * spelling; a flavour only for its own exact type. */
struct ClipSet {
    char*   text;        /* NULL: this copy has no plain text */
    size_t  text_len;
    int     n;
    char**  mimes;
    char**  datas;
    size_t* lens;
};

static void clipset_free(struct ClipSet* s) {
    free(s->text);
    for (int i = 0; i < s->n; i++) { free(s->mimes[i]); free(s->datas[i]); }
    free(s->mimes); free(s->datas); free(s->lens);
    memset(s, 0, sizeof(*s));
}

static int is_text_mime(const char* m) {
    for (int i = 0; i < kOfferedMimeCount; i++)
        if (!strcmp(m, kOfferedMimes[i])) return 1;
    return 0;
}

/* The bytes this copy holds for `mime` (NULL: the text). An exact flavour
 * wins over the text, so a copy that carries its own "text/plain" keeps it. */
static int clipset_lookup(const struct ClipSet* s, const char* mime,
                          const char** data, size_t* len) {
    if (mime) {
        for (int i = 0; i < s->n; i++)
            if (!strcmp(s->mimes[i], mime)) {
                *data = s->datas[i]; *len = s->lens[i]; return 1;
            }
    }
    if (s->text && (!mime || is_text_mime(mime))) {
        *data = s->text; *len = s->text_len; return 1;
    }
    return 0;
}

static int clipset_has_flavour(const struct ClipSet* s, const char* mime) {
    for (int i = 0; i < s->n; i++)
        if (!strcmp(s->mimes[i], mime)) return 1;
    return 0;
}

/* Every type this copy is offered as, in offer order: the flavours first (they
 * are the richer ones), then the text spellings no flavour already covers. */
static int clipset_offer_list(const struct ClipSet* s, const char** out, int cap) {
    int n = 0;
    for (int i = 0; i < s->n && n < cap; i++) out[n++] = s->mimes[i];
    if (s->text)
        for (int i = 0; i < kOfferedMimeCount && n < cap; i++)
            if (!clipset_has_flavour(s, kOfferedMimes[i])) out[n++] = kOfferedMimes[i];
    return n;
}

/* A list of types as one '\n'-terminated string per type. Caller frees. */
static char* join_mimes(const char* const* mimes, int n, size_t* out_len) {
    size_t cap = 1;
    for (int i = 0; i < n; i++) cap += strlen(mimes[i]) + 1;
    char* out = malloc(cap);
    if (!out) { *out_len = 0; return NULL; }
    size_t at = 0;
    for (int i = 0; i < n; i++) {
        size_t l = strlen(mimes[i]);
        memcpy(out + at, mimes[i], l);
        at += l;
        out[at++] = '\n';
    }
    out[at] = '\0';
    *out_len = at;
    return out;
}

/* Reads are queued rather than kept in a single slot: Clipboard.getData
 * promises its completion runs exactly once, and two pastes in quick
 * succession would otherwise drop the first callback (and leak the closure the
 * Swift side retained for it). */
enum { READ_TEXT, READ_MIME, READ_LIST };

struct ReadReq {
    WlClipTextCallback cb;
    void*              ctx;
    int                kind;
    char*              mime;     /* READ_MIME only */
    struct ReadReq*    next;
};

struct WlClipboard {
    struct wl_display*  dpy;
    struct wl_registry* reg;
    struct zwlr_data_control_manager_v1* mgr;
    struct wl_seat*     seat;
    struct zwlr_data_control_device_v1* dev;

    /* The selection currently on offer from somebody else. */
    struct zwlr_data_control_offer_v1* offer;

    /* Our own selection, when we are the owner. */
    struct zwlr_data_control_source_v1* src;
    struct ClipSet own;
    int    owns_selection;

    pthread_t       thread;
    pthread_mutex_t lock;
    int             cmd_fd;      /* eventfd: wakes the thread for commands */
    int             quit;
    int             started;

    /* Pending commands, guarded by lock. */
    struct ClipSet pending;
    int    pending_set;
    struct ReadReq* reads_head;
    struct ReadReq* reads_tail;
};

/* ========================================================================= */
/* Bounded pipe I/O                                                           */
/* ========================================================================= */

/* Read everything from `fd` (which we own and close) with a total deadline.
 * Returns a NUL-terminated buffer the caller frees, or NULL. */
static char* read_all_bounded(int fd, size_t* out_len) {
    int fl = fcntl(fd, F_GETFL, 0);
    if (fl >= 0) fcntl(fd, F_SETFL, fl | O_NONBLOCK);

    size_t cap = 4096, len = 0;
    char* buf = malloc(cap);
    if (!buf) { close(fd); return NULL; }

    /* One deadline for the whole transfer, not per-poll: a peer trickling a
     * byte at a time must not be able to hold us open indefinitely. */
    struct timespec t0;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (;;) {
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        long elapsed_ms = (now.tv_sec - t0.tv_sec) * 1000
                        + (now.tv_nsec - t0.tv_nsec) / 1000000;
        int remaining = WLCLIP_TIMEOUT_MS - (int)elapsed_ms;
        if (remaining <= 0) break;

        struct pollfd p = { .fd = fd, .events = POLLIN };
        int pr = poll(&p, 1, remaining);
        if (pr <= 0) break;                       /* timeout or error: give up */
        if (!(p.revents & (POLLIN | POLLHUP))) break;

        if (len + 4096 > cap) {
            if (cap >= WLCLIP_MAX_BYTES) break;   /* refuse to grow forever */
            size_t ncap = cap * 2;
            char* nb = realloc(buf, ncap);
            if (!nb) break;
            buf = nb; cap = ncap;
        }
        ssize_t n = read(fd, buf + len, cap - len - 1);
        if (n > 0) { len += (size_t)n; continue; }
        if (n == 0) break;                        /* EOF: the owner is done */
        if (errno == EAGAIN || errno == EINTR) continue;
        break;
    }
    close(fd);
    buf[len] = '\0';
    if (out_len) *out_len = len;
    return buf;
}

/* Write `len` bytes to `fd` (which we own and close) with a total deadline.
 * A peer that asks to paste and then does not read must not wedge us. */
static void write_all_bounded(int fd, const char* data, size_t len) {
    int fl = fcntl(fd, F_GETFL, 0);
    if (fl >= 0) fcntl(fd, F_SETFL, fl | O_NONBLOCK);

    size_t off = 0;
    while (off < len) {
        struct pollfd p = { .fd = fd, .events = POLLOUT };
        int pr = poll(&p, 1, WLCLIP_TIMEOUT_MS);
        if (pr <= 0) break;
        if (!(p.revents & POLLOUT)) break;        /* POLLERR/POLLHUP: peer gone */
        ssize_t n = write(fd, data + off, len - off);
        if (n > 0) { off += (size_t)n; continue; }
        if (n < 0 && (errno == EAGAIN || errno == EINTR)) continue;
        break;
    }
    close(fd);
}

/* ========================================================================= */
/* Selection source — serving our data to whoever pastes                      */
/* ========================================================================= */

static void src_send(void* data, struct zwlr_data_control_source_v1* src,
                     const char* mime, int32_t fd) {
    (void)src;
    WlClipboard* c = data;
    /* Runs on the bridge thread, so `own` is stable here. */
    const char* bytes; size_t len;
    if (mime && clipset_lookup(&c->own, mime, &bytes, &len))
        write_all_bounded(fd, bytes, len);
    else
        close(fd);
}

static void src_cancelled(void* data, struct zwlr_data_control_source_v1* src) {
    WlClipboard* c = data;
    /* Somebody else took the selection. Drop ours so a later paste round-trips
     * to the new owner instead of answering from our stale copy. */
    if (c->src == src) {
        c->owns_selection = 0;
        c->src = NULL;
    }
    zwlr_data_control_source_v1_destroy(src);
}

static const struct zwlr_data_control_source_v1_listener src_listener = {
    .send = src_send,
    .cancelled = src_cancelled,
};

/* ========================================================================= */
/* Offers — what somebody else is advertising                                 */
/* ========================================================================= */

static void offer_mime(void* data, struct zwlr_data_control_offer_v1* offer,
                       const char* mime) {
    (void)offer;
    struct OfferState* st = data;
    if (!st || !mime) return;
    if (st->n_mimes < WLCLIP_MAX_OFFER_MIMES) {
        char* copy = strdup(mime);
        if (copy) st->mimes[st->n_mimes++] = copy;
    }
    int r = mime_rank(mime);
    if (r > st->rank) {
        st->rank = r;
        snprintf(st->mime, sizeof(st->mime), "%s", mime);
    }
}

static const struct zwlr_data_control_offer_v1_listener offer_listener = {
    .offer = offer_mime,
};

static void offer_drop(struct zwlr_data_control_offer_v1* offer) {
    if (!offer) return;
    struct OfferState* st = zwlr_data_control_offer_v1_get_user_data(offer);
    if (st) for (int i = 0; i < st->n_mimes; i++) free(st->mimes[i]);
    free(st);
    zwlr_data_control_offer_v1_destroy(offer);
}

/* ========================================================================= */
/* Device                                                                     */
/* ========================================================================= */

static void dev_data_offer(void* data, struct zwlr_data_control_device_v1* dev,
                           struct zwlr_data_control_offer_v1* offer) {
    (void)data; (void)dev;
    struct OfferState* st = calloc(1, sizeof(*st));
    zwlr_data_control_offer_v1_add_listener(offer, &offer_listener, st);
    zwlr_data_control_offer_v1_set_user_data(offer, st);
}

static void dev_selection(void* data, struct zwlr_data_control_device_v1* dev,
                          struct zwlr_data_control_offer_v1* offer) {
    (void)dev;
    WlClipboard* c = data;
    if (c->offer && c->offer != offer) offer_drop(c->offer);
    c->offer = offer;   /* may be NULL: the selection was cleared */
}

static void dev_primary_selection(void* data,
                                  struct zwlr_data_control_device_v1* dev,
                                  struct zwlr_data_control_offer_v1* offer) {
    (void)data; (void)dev;
    /* Primary selection is not implemented desktop-wide (see
     * docs/plans/clipboard.md). Drop the offer so it is not leaked. */
    if (offer) offer_drop(offer);
}

static void dev_finished(void* data, struct zwlr_data_control_device_v1* dev) {
    WlClipboard* c = data;
    (void)dev;
    if (c->dev) { zwlr_data_control_device_v1_destroy(c->dev); c->dev = NULL; }
}

static const struct zwlr_data_control_device_v1_listener dev_listener = {
    .data_offer = dev_data_offer,
    .selection = dev_selection,
    .finished = dev_finished,
    .primary_selection = dev_primary_selection,
};

/* ========================================================================= */
/* Registry                                                                   */
/* ========================================================================= */

static void reg_global(void* data, struct wl_registry* reg, uint32_t name,
                       const char* iface, uint32_t version) {
    WlClipboard* c = data;
    if (!strcmp(iface, zwlr_data_control_manager_v1_interface.name)) {
        uint32_t v = version < 2 ? version : 2;
        c->mgr = wl_registry_bind(reg, name,
                                  &zwlr_data_control_manager_v1_interface, v);
    } else if (!strcmp(iface, wl_seat_interface.name) && !c->seat) {
        uint32_t v = version < 7 ? version : 7;
        c->seat = wl_registry_bind(reg, name, &wl_seat_interface, v);
    }
}

static void reg_global_remove(void* data, struct wl_registry* reg,
                              uint32_t name) {
    (void)data; (void)reg; (void)name;
}

static const struct wl_registry_listener reg_listener = {
    .global = reg_global,
    .global_remove = reg_global_remove,
};

/* ========================================================================= */
/* Commands, executed on the bridge thread                                    */
/* ========================================================================= */

static void do_set(WlClipboard* c, struct ClipSet* set) {
    clipset_free(&c->own);
    c->own = *set;               /* takes ownership */
    memset(set, 0, sizeof(*set));

    if (c->src) {
        /* Replacing our own selection. Destroying the proxy stops libwayland
         * delivering its `cancelled` — which would otherwise arrive after we
         * have re-taken ownership and clear the flag we are about to set. */
        zwlr_data_control_source_v1_destroy(c->src);
        c->src = NULL;
    }
    if (!c->mgr || !c->dev) return;

    c->src = zwlr_data_control_manager_v1_create_data_source(c->mgr);
    if (!c->src) return;
    zwlr_data_control_source_v1_add_listener(c->src, &src_listener, c);
    const char* types[WLCLIP_MAX_OFFER_MIMES];
    int n = clipset_offer_list(&c->own, types, WLCLIP_MAX_OFFER_MIMES);
    for (int i = 0; i < n; i++)
        zwlr_data_control_source_v1_offer(c->src, types[i]);
    zwlr_data_control_device_v1_set_selection(c->dev, c->src);
    c->owns_selection = 1;
    wl_display_flush(c->dpy);
}

/* The best text type of an offer, or the exact `mime` if it is on offer. */
static const char* offer_pick(const struct OfferState* st, const char* mime) {
    if (!st) return NULL;
    if (!mime) return st->rank ? st->mime : NULL;
    for (int i = 0; i < st->n_mimes; i++)
        if (!strcmp(st->mimes[i], mime)) return st->mimes[i];
    return NULL;
}

static void do_read(WlClipboard* c, const struct ReadReq* r) {
    const char* mime = r->kind == READ_MIME ? r->mime : NULL;

    /* We own it: answer locally. Round-tripping would ask US to write while
     * this thread is blocked reading — a self-deadlock. */
    if (c->owns_selection) {
        if (r->kind == READ_LIST) {
            const char* types[WLCLIP_MAX_OFFER_MIMES];
            int n = clipset_offer_list(&c->own, types, WLCLIP_MAX_OFFER_MIMES);
            size_t len; char* list = join_mimes(types, n, &len);
            r->cb(r->ctx, list, list ? len : 0);
            free(list);
            return;
        }
        const char* bytes; size_t len;
        if (clipset_lookup(&c->own, mime, &bytes, &len)) r->cb(r->ctx, bytes, len);
        else if (r->kind == READ_TEXT) r->cb(r->ctx, "", 0);
        else r->cb(r->ctx, NULL, 0);
        return;
    }
    if (!c->offer) { r->cb(r->ctx, NULL, 0); return; }

    struct OfferState* st = zwlr_data_control_offer_v1_get_user_data(c->offer);
    if (r->kind == READ_LIST) {
        size_t len = 0;
        char* list = st ? join_mimes((const char* const*)st->mimes, st->n_mimes, &len) : NULL;
        r->cb(r->ctx, list, list ? len : 0);
        free(list);
        return;
    }
    const char* want = offer_pick(st, mime);
    if (!want) { r->cb(r->ctx, NULL, 0); return; }

    int fds[2];
    if (pipe2(fds, O_CLOEXEC) != 0) { r->cb(r->ctx, NULL, 0); return; }

    zwlr_data_control_offer_v1_receive(c->offer, want, fds[1]);
    wl_display_flush(c->dpy);   /* must reach the compositor before we block */
    close(fds[1]);              /* the owner holds the only write end now */

    size_t len = 0;
    char* bytes = read_all_bounded(fds[0], &len);
    r->cb(r->ctx, bytes, len);
    free(bytes);
}

static void run_pending(WlClipboard* c) {
    for (;;) {
        pthread_mutex_lock(&c->lock);
        int do_set_now = c->pending_set;
        struct ClipSet set = c->pending;
        struct ReadReq* reads = c->reads_head;
        c->pending_set = 0;
        memset(&c->pending, 0, sizeof(c->pending));
        c->reads_head = NULL; c->reads_tail = NULL;
        pthread_mutex_unlock(&c->lock);

        if (!do_set_now && !reads) return;
        /* Set first: a copy queued before a paste must be visible to it. */
        if (do_set_now) do_set(c, &set);
        while (reads) {
            struct ReadReq* next = reads->next;
            do_read(c, reads);
            free(reads->mime);
            free(reads);
            reads = next;
        }
    }
}

static void* clip_thread(void* arg) {
    WlClipboard* c = arg;

    /* Block SIGPIPE here, because every write in this file goes to a pipe
     * owned by somebody else. A client that asks to paste and then closes its
     * end — cancelling, crashing, or just reading less than it asked for —
     * makes our write raise SIGPIPE, whose default action TERMINATES THE
     * PROCESS. That is the app dying because another program changed its mind
     * about a paste. Blocked, write() returns EPIPE instead and
     * write_all_bounded gives up like any other failed transfer.
     *
     * Blocked on this thread rather than SIG_IGN process-wide: this is library
     * code inside somebody else's app, and stamping on a global signal
     * disposition would be ours to answer for. Every write lives on this
     * thread, so the narrower fix is also the complete one. */
    sigset_t pipe_only;
    sigemptyset(&pipe_only);
    sigaddset(&pipe_only, SIGPIPE);
    pthread_sigmask(SIG_BLOCK, &pipe_only, NULL);

    while (!c->quit) {
        wl_display_flush(c->dpy);
        struct pollfd pfds[2] = {
            { .fd = wl_display_get_fd(c->dpy), .events = POLLIN },
            { .fd = c->cmd_fd,                 .events = POLLIN },
        };
        if (poll(pfds, 2, -1) < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (pfds[0].revents & POLLIN) {
            if (wl_display_dispatch(c->dpy) < 0) break;   /* connection lost */
        }
        if (pfds[1].revents & POLLIN) {
            uint64_t v;
            while (read(c->cmd_fd, &v, sizeof(v)) == sizeof(v)) { /* drain */ }
            run_pending(c);
        }
    }
    return NULL;
}

static void wake(WlClipboard* c) {
    uint64_t one = 1;
    ssize_t n = write(c->cmd_fd, &one, sizeof(one));
    (void)n;
}

/* ========================================================================= */
/* Public API                                                                 */
/* ========================================================================= */

WlClipboard* wlclip_connect(const char* display) {
    WlClipboard* c = calloc(1, sizeof(*c));
    if (!c) return NULL;

    c->dpy = wl_display_connect(display);
    if (!c->dpy) { free(c); return NULL; }

    c->reg = wl_display_get_registry(c->dpy);
    wl_registry_add_listener(c->reg, &reg_listener, c);
    wl_display_roundtrip(c->dpy);   /* globals */

    if (!c->mgr || !c->seat) {
        /* No data-control here — not Starling, or an older compositor. */
        wl_display_disconnect(c->dpy);
        free(c);
        return NULL;
    }

    c->dev = zwlr_data_control_manager_v1_get_data_device(c->mgr, c->seat);
    if (!c->dev) { wl_display_disconnect(c->dpy); free(c); return NULL; }
    zwlr_data_control_device_v1_add_listener(c->dev, &dev_listener, c);
    wl_display_roundtrip(c->dpy);   /* the current selection, if any */

    c->cmd_fd = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
    if (c->cmd_fd < 0) { wl_display_disconnect(c->dpy); free(c); return NULL; }
    pthread_mutex_init(&c->lock, NULL);

    if (pthread_create(&c->thread, NULL, clip_thread, c) != 0) {
        close(c->cmd_fd);
        pthread_mutex_destroy(&c->lock);
        wl_display_disconnect(c->dpy);
        free(c);
        return NULL;
    }
    c->started = 1;
    return c;
}

void wlclip_destroy(WlClipboard* c) {
    if (!c) return;
    c->quit = 1;
    wake(c);
    if (c->started) pthread_join(c->thread, NULL);

    /* Anything still queued must be answered, not dropped: each request holds a
     * caller-side closure that is only released when its callback runs. */
    struct ReadReq* reads = c->reads_head;
    c->reads_head = NULL; c->reads_tail = NULL;
    while (reads) {
        struct ReadReq* next = reads->next;
        reads->cb(reads->ctx, NULL, 0);
        free(reads->mime);
        free(reads);
        reads = next;
    }

    if (c->src)   zwlr_data_control_source_v1_destroy(c->src);
    if (c->offer) offer_drop(c->offer);
    if (c->dev)   zwlr_data_control_device_v1_destroy(c->dev);
    if (c->mgr)   zwlr_data_control_manager_v1_destroy(c->mgr);
    if (c->seat)  wl_seat_destroy(c->seat);
    if (c->reg)   wl_registry_destroy(c->reg);
    wl_display_disconnect(c->dpy);

    close(c->cmd_fd);
    pthread_mutex_destroy(&c->lock);
    clipset_free(&c->own);
    clipset_free(&c->pending);
    free(c);
}

static char* dup_bytes(const char* p, size_t len) {
    char* copy = malloc(len + 1);
    if (!copy) return NULL;
    if (len) memcpy(copy, p, len);
    copy[len] = '\0';
    return copy;
}

int wlclip_set_data(WlClipboard* c, const char* text, size_t text_len,
                    const char* const* mimes, const char* const* datas,
                    const size_t* lens, int count) {
    if (!c || count < 0 || (!text && count == 0)) return -1;
    if (count > WLCLIP_MAX_OFFER_MIMES) count = WLCLIP_MAX_OFFER_MIMES;
    struct ClipSet set = {0};
    if (text && !(set.text = dup_bytes(text, text_len))) return -1;
    set.text_len = text ? text_len : 0;
    if (count) {
        set.mimes = calloc((size_t)count, sizeof(char*));
        set.datas = calloc((size_t)count, sizeof(char*));
        set.lens  = calloc((size_t)count, sizeof(size_t));
        if (!set.mimes || !set.datas || !set.lens) { clipset_free(&set); return -1; }
        for (int i = 0; i < count; i++) {
            if (!mimes[i] || !mimes[i][0] || (!datas[i] && lens[i])) continue;
            if (clipset_has_flavour(&set, mimes[i])) continue;   /* first one wins */
            char* m = strdup(mimes[i]);
            char* d = dup_bytes(datas[i] ? datas[i] : "", lens[i]);
            if (!m || !d) { free(m); free(d); clipset_free(&set); return -1; }
            set.mimes[set.n] = m; set.datas[set.n] = d; set.lens[set.n] = lens[i];
            set.n++;
        }
    }

    pthread_mutex_lock(&c->lock);
    clipset_free(&c->pending);      /* a newer copy supersedes an unsent one */
    c->pending = set;
    c->pending_set = 1;
    pthread_mutex_unlock(&c->lock);
    wake(c);
    return 0;
}

void wlclip_set_text(WlClipboard* c, const char* text, size_t len) {
    if (!text) return;
    wlclip_set_data(c, text, len, NULL, NULL, NULL, 0);
}

static int queue_read(WlClipboard* c, int kind, const char* mime,
                      WlClipTextCallback cb, void* ctx) {
    if (!c || !cb) return -1;
    struct ReadReq* req = calloc(1, sizeof(*req));
    if (!req) return -1;
    req->cb = cb;
    req->ctx = ctx;
    req->kind = kind;
    if (mime && !(req->mime = strdup(mime))) { free(req); return -1; }

    pthread_mutex_lock(&c->lock);
    if (c->reads_tail) c->reads_tail->next = req;
    else               c->reads_head = req;
    c->reads_tail = req;
    pthread_mutex_unlock(&c->lock);
    wake(c);
    return 0;
}

int wlclip_read_text(WlClipboard* c, WlClipTextCallback cb, void* ctx) {
    return queue_read(c, READ_TEXT, NULL, cb, ctx);
}

int wlclip_read_mime(WlClipboard* c, const char* mime,
                     WlClipTextCallback cb, void* ctx) {
    if (!mime || !mime[0]) return -1;
    return queue_read(c, READ_MIME, mime, cb, ctx);
}

int wlclip_read_mimes(WlClipboard* c, WlClipTextCallback cb, void* ctx) {
    return queue_read(c, READ_LIST, NULL, cb, ctx);
}

int wlclip_owns_selection(WlClipboard* c) {
    return c && c->owns_selection;
}
