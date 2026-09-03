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

struct OfferState {
    char mime[128];
    int  rank;
};

/* Reads are queued rather than kept in a single slot: Clipboard.getData
 * promises its completion runs exactly once, and two pastes in quick
 * succession would otherwise drop the first callback (and leak the closure the
 * Swift side retained for it). */
struct ReadReq {
    WlClipTextCallback cb;
    void*              ctx;
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
    char*  own_text;
    size_t own_len;
    int    owns_selection;

    /* Mirror hook: see wlclip_set_selection_callback. Read on the bridge
     * thread, written from the caller's, so it rides the same lock as the
     * command queue. */
    WlClipSelectionCallback sel_cb;
    void*                   sel_ctx;

    pthread_t       thread;
    pthread_mutex_t lock;
    int             cmd_fd;      /* eventfd: wakes the thread for commands */
    int             quit;
    int             started;

    /* Pending commands, guarded by lock. */
    char*  pending_text;
    size_t pending_text_len;
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
    (void)src; (void)mime;
    WlClipboard* c = data;
    /* Runs on the bridge thread, so own_text is stable here. */
    if (c->own_text) write_all_bounded(fd, c->own_text, c->own_len);
    else             close(fd);
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

    /* The mimes are already in: the protocol sends data_offer, then one offer
     * event per mime, then this. So "is there text on the clipboard now" is
     * answerable here and nowhere earlier. */
    int has_text = 0;
    if (offer) {
        struct OfferState* st = zwlr_data_control_offer_v1_get_user_data(offer);
        has_text = st && st->rank > 0;
    }
    pthread_mutex_lock(&c->lock);
    WlClipSelectionCallback cb = c->sel_cb;
    void* ctx = c->sel_ctx;
    pthread_mutex_unlock(&c->lock);
    if (cb) cb(ctx, has_text, c->owns_selection);
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

static void do_set_text(WlClipboard* c, char* text, size_t len) {
    free(c->own_text);
    c->own_text = text;          /* takes ownership */
    c->own_len = len;

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
    for (int i = 0; i < kOfferedMimeCount; i++)
        zwlr_data_control_source_v1_offer(c->src, kOfferedMimes[i]);
    zwlr_data_control_device_v1_set_selection(c->dev, c->src);
    c->owns_selection = 1;
    wl_display_flush(c->dpy);
}

static void do_read_text(WlClipboard* c, WlClipTextCallback cb, void* ctx) {
    /* We own it: answer locally. Round-tripping would ask US to write while
     * this thread is blocked reading — a self-deadlock. */
    if (c->owns_selection) {
        cb(ctx, c->own_text ? c->own_text : "", c->own_text ? c->own_len : 0);
        return;
    }
    if (!c->offer) { cb(ctx, NULL, 0); return; }

    struct OfferState* st = zwlr_data_control_offer_v1_get_user_data(c->offer);
    if (!st || st->rank == 0) { cb(ctx, NULL, 0); return; }

    int fds[2];
    if (pipe2(fds, O_CLOEXEC) != 0) { cb(ctx, NULL, 0); return; }

    zwlr_data_control_offer_v1_receive(c->offer, st->mime, fds[1]);
    wl_display_flush(c->dpy);   /* must reach the compositor before we block */
    close(fds[1]);              /* the owner holds the only write end now */

    size_t len = 0;
    char* text = read_all_bounded(fds[0], &len);
    cb(ctx, text, len);
    free(text);
}

static void run_pending(WlClipboard* c) {
    for (;;) {
        pthread_mutex_lock(&c->lock);
        int do_set = c->pending_set;
        char* text = c->pending_text; size_t tlen = c->pending_text_len;
        struct ReadReq* reads = c->reads_head;
        c->pending_set = 0;
        c->pending_text = NULL; c->pending_text_len = 0;
        c->reads_head = NULL; c->reads_tail = NULL;
        pthread_mutex_unlock(&c->lock);

        if (!do_set && !reads) return;
        /* Set first: a copy queued before a paste must be visible to it. */
        if (do_set) do_set_text(c, text, tlen);
        while (reads) {
            struct ReadReq* next = reads->next;
            do_read_text(c, reads->cb, reads->ctx);
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
    free(c->own_text);
    free(c->pending_text);
    free(c);
}

void wlclip_set_text(WlClipboard* c, const char* text, size_t len) {
    if (!c || !text) return;
    char* copy = malloc(len + 1);
    if (!copy) return;
    memcpy(copy, text, len);
    copy[len] = '\0';

    pthread_mutex_lock(&c->lock);
    free(c->pending_text);          /* a newer copy supersedes an unsent one */
    c->pending_text = copy;
    c->pending_text_len = len;
    c->pending_set = 1;
    pthread_mutex_unlock(&c->lock);
    wake(c);
}

int wlclip_read_text(WlClipboard* c, WlClipTextCallback cb, void* ctx) {
    if (!c || !cb) return -1;
    struct ReadReq* req = calloc(1, sizeof(*req));
    if (!req) return -1;
    req->cb = cb;
    req->ctx = ctx;

    pthread_mutex_lock(&c->lock);
    if (c->reads_tail) c->reads_tail->next = req;
    else               c->reads_head = req;
    c->reads_tail = req;
    pthread_mutex_unlock(&c->lock);
    wake(c);
    return 0;
}

void wlclip_set_selection_callback(WlClipboard* c, WlClipSelectionCallback cb,
                                   void* ctx) {
    if (!c) return;
    pthread_mutex_lock(&c->lock);
    c->sel_cb = cb;
    c->sel_ctx = ctx;
    pthread_mutex_unlock(&c->lock);
}

int wlclip_owns_selection(WlClipboard* c) {
    return c && c->owns_selection;
}
