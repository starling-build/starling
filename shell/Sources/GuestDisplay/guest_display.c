// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// The QEMU p2p D-Bus display, transcribed from the M0 spike. Everything the
// protocol does here was measured against a real Windows guest first —
// docs/windows-vm/guest-display-probe.c is the sd-bus proof and
// docs/windows-vm/dbus-display.py the protocol reference. Where this file
// looks over-careful, docs/plans/guest-display.md §Traps says what it cost.

#include "guest_display.h"

#include <errno.h>
#include <poll.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/eventfd.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#include <libvirt/libvirt.h>
#include <libvirt/virterror.h>
#include <systemd/sd-bus.h>

#define GD_ROOT      "/org/qemu/Display1"
#define GD_CONSOLE   GD_ROOT "/Console_0"
#define GD_LISTENER  GD_ROOT "/Listener"
#define GD_CLIPBOARD GD_ROOT "/Clipboard"

#define IFACE_CONSOLE   "org.qemu.Display1.Console"
#define IFACE_KBD       "org.qemu.Display1.Keyboard"
#define IFACE_MOUSE     "org.qemu.Display1.Mouse"
#define IFACE_LISTENER  "org.qemu.Display1.Listener"
#define IFACE_DMABUF2   "org.qemu.Display1.Listener.Unix.ScanoutDMABUF2"
#define IFACE_CLIPBOARD "org.qemu.Display1.Clipboard"

// QEMU blocks the guest's display pipeline on the UpdateDMABUF reply, so a
// window nobody is compositing (minimised, covered, another workspace) must
// not stall the guest: past this the ack goes out unasked.
#define GD_ACK_DEADLINE_MS 20
#define GD_MAX_PENDING 32
#define GD_MAX_CMDS 256

// ── plumbing ───────────────────────────────────────────────────────────────

enum gd_cmd_kind {
    GD_CMD_ACK = 1,
    GD_CMD_KEY,
    GD_CMD_MOUSE_ABS,
    GD_CMD_MOUSE_BUTTON,
    GD_CMD_UI_SIZE,
    GD_CMD_CLIP_ENABLE,
    GD_CMD_CLIP_GRAB,
    GD_CMD_CLIP_REPLY,
    GD_CMD_CLIP_PULL,
};

struct gd_cmd {
    int kind;
    uint64_t token;
    uint32_t a, b;
    int down;
    char** mimes;  // owned (CLIP_GRAB)
    int n_mimes;
    char* mime;    // owned (CLIP_REPLY)
    void* data;    // owned (CLIP_REPLY)
    size_t len;
};

// One damage call whose reply we are sitting on.
struct gd_pending {
    uint64_t token;
    sd_bus_message* msg;
    uint64_t deadline_ms;
};

// A Request from the guest, waiting on the host clipboard.
struct gd_clip_req {
    uint64_t token;
    sd_bus_message* msg;
};

struct GuestDisplay {
    GuestDisplayCallbacks cb;
    char domain[256];

    pthread_t thread;
    int thread_started;
    volatile int running;
    int wake_fd;
    pthread_mutex_t mu;

    struct gd_cmd cmds[GD_MAX_CMDS];
    int n_cmds;
    volatile int connected;  // read under mu; commands before this are dropped

    // ── bus thread only past this point ──
    sd_bus* ctl;
    sd_bus* lis;
    virConnectPtr conn;
    virDomainPtr dom;

    struct gd_pending pending[GD_MAX_PENDING];
    int n_pending;
    uint64_t next_token;
    int ack_immediate;

    struct gd_clip_req clip_reqs[8];
    int n_clip_reqs;
    int clip_enabled;
    /* Grab serials start at 1 and only go up. QEMU orders grabs by this, and
     * a serial of 0 is not a grab anyone has to believe. */
    uint32_t clip_serial;
    /* QEMU allows ONE outstanding clipboard Request: a second is refused with
     * "Pending request", which is what a burst of guest grabs produces (one
     * per copy, and Ctrl+A/Ctrl+C is two events). So pulls are serialised, and
     * a grab arriving mid-pull is remembered rather than dropped — the content
     * it announced is newer than the one being fetched. */
    int   clip_pull_inflight;
    char* clip_pull_again;

    // Keys the guest believes are down, by qnum. Extended scancodes fold
    // into the high bit, so one byte covers the space and 32 bytes covers
    // every key we can send.
    uint8_t held[32];
};

static uint64_t gd_now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000 + (uint64_t)ts.tv_nsec / 1000000;
}

static void gd_wake(GuestDisplay* gd) {
    uint64_t one = 1;
    ssize_t n = write(gd->wake_fd, &one, sizeof(one));
    (void)n;  // an eventfd write fails only at UINT64_MAX pending
}

static void gd_cmd_free(struct gd_cmd* c) {
    for (int i = 0; i < c->n_mimes; i++) free(c->mimes[i]);
    free(c->mimes);
    free(c->mime);
    free(c->data);
    memset(c, 0, sizeof(*c));
}

// Queue a command for the bus thread. Commands sent before the display is
// connected are dropped rather than buffered: they describe an instant (this
// pointer position, this frame's ack) that will have passed by the time a
// connection exists.
static void gd_push(GuestDisplay* gd, const struct gd_cmd* c) {
    if (!gd) {
        return;
    }
    int queued = 0;
    pthread_mutex_lock(&gd->mu);
    if (gd->connected && gd->n_cmds < GD_MAX_CMDS) {
        gd->cmds[gd->n_cmds++] = *c;
        queued = 1;
    }
    pthread_mutex_unlock(&gd->mu);
    if (queued) {
        gd_wake(gd);
    } else {
        struct gd_cmd tmp = *c;
        gd_cmd_free(&tmp);
    }
}

static void gd_state(GuestDisplay* gd, int state, const char* detail) {
    if (gd->cb.on_state) {
        gd->cb.on_state(gd->cb.ctx, state, detail);
    }
}

// Fire-and-forget on the control bus. After RegisterListener nothing here may
// block: a synchronous call deadlocks both sides for the full 25 s timeout,
// and QEMU reports it as the listener downgrading rather than as a hang.
static void gd_call_async(GuestDisplay* gd, const char* iface,
                          const char* member, const char* types, ...) {
    if (!gd->ctl) {
        return;
    }
    sd_bus_message* m = NULL;
    int r = sd_bus_message_new_method_call(gd->ctl, &m, NULL, GD_CONSOLE, iface,
                                           member);
    if (r < 0) {
        return;
    }
    va_list ap;
    va_start(ap, types);
    r = sd_bus_message_appendv(m, types, ap);
    va_end(ap);
    if (r >= 0) {
        sd_bus_message_set_expect_reply(m, 0);
        r = sd_bus_send(gd->ctl, m, NULL);
    }
    if (r < 0) {
        fprintf(stderr, "[guest] %s.%s failed: %s\n", iface, member,
                strerror(-r));
    }
    sd_bus_message_unref(m);
}

// ── listener object: what QEMU calls on us ─────────────────────────────────

static int gd_on_scanout_dmabuf2(sd_bus_message* m, void* ud,
                                 sd_bus_error* e) {
    GuestDisplay* gd = ud;
    int r, fd, first_fd = -1;
    uint32_t x, y, w, h, nplanes, fourcc, bw, bh;
    uint32_t offsets[8] = {0}, strides[8] = {0};
    uint64_t modifier;
    int y0_top;

    if ((r = sd_bus_message_enter_container(m, 'a', "h")) < 0) return r;
    while ((r = sd_bus_message_read(m, "h", &fd)) > 0) {
        // The fds belong to the message; dup the one we keep and let sd-bus
        // close the rest when it unrefs.
        if (first_fd < 0) first_fd = fd;
    }
    if (r < 0) return r;
    sd_bus_message_exit_container(m);

    if ((r = sd_bus_message_read(m, "uuuu", &x, &y, &w, &h)) < 0) return r;
    for (int pass = 0; pass < 2; pass++) {
        uint32_t* dst = pass ? strides : offsets;
        uint32_t v;
        int n = 0;
        if ((r = sd_bus_message_enter_container(m, 'a', "u")) < 0) return r;
        while ((r = sd_bus_message_read(m, "u", &v)) > 0) {
            if (n < 8) dst[n++] = v;
        }
        if (r < 0) return r;
        sd_bus_message_exit_container(m);
    }
    if ((r = sd_bus_message_read(m, "uuuu", &nplanes, &fourcc, &bw, &bh)) < 0)
        return r;
    if ((r = sd_bus_message_read(m, "tb", &modifier, &y0_top)) < 0) return r;

    if (first_fd >= 0 && gd->cb.on_scanout) {
        int owned = dup(first_fd);
        if (owned >= 0) {
            gd->cb.on_scanout(gd->cb.ctx, owned, w, h, strides[0], offsets[0],
                              fourcc, modifier, y0_top);
        }
    }
    return sd_bus_reply_method_return(m, "");
}

// v1 of the same call. QEMU only sends it to a listener that did not declare
// ScanoutDMABUF2, which we always do — answered so a mismatch shows up as a
// black window instead of a stalled guest.
static int gd_on_scanout_dmabuf(sd_bus_message* m, void* ud, sd_bus_error* e) {
    GuestDisplay* gd = ud;
    int fd, y0_top;
    uint32_t w, h, stride, fourcc;
    uint64_t mod;
    int r = sd_bus_message_read(m, "huuuutb", &fd, &w, &h, &stride, &fourcc,
                                &mod, &y0_top);
    if (r < 0) return r;
    if (gd->cb.on_scanout) {
        int owned = dup(fd);
        if (owned >= 0) {
            gd->cb.on_scanout(gd->cb.ctx, owned, w, h, stride, 0, fourcc, mod,
                              y0_top);
        }
    }
    return sd_bus_reply_method_return(m, "");
}

static int gd_on_update_dmabuf(sd_bus_message* m, void* ud, sd_bus_error* e) {
    GuestDisplay* gd = ud;
    int x, y, w, h;
    int r = sd_bus_message_read(m, "iiii", &x, &y, &w, &h);
    if (r < 0) return r;

    // Immediate mode (STARLING_GUEST_ACK=immediate) and a full pending list
    // both mean: answer now. The second is the safety valve — a compositor
    // that has stopped acking must not take the guest down with it.
    if (gd->ack_immediate || gd->n_pending >= GD_MAX_PENDING) {
        if (gd->cb.on_update) {
            gd->cb.on_update(gd->cb.ctx, 0, x, y, w, h);
        }
        return sd_bus_reply_method_return(m, "");
    }

    uint64_t token = ++gd->next_token;
    gd->pending[gd->n_pending].token = token;
    gd->pending[gd->n_pending].msg = sd_bus_message_ref(m);
    gd->pending[gd->n_pending].deadline_ms = gd_now_ms() + GD_ACK_DEADLINE_MS;
    gd->n_pending++;
    if (gd->cb.on_update) {
        gd->cb.on_update(gd->cb.ctx, token, x, y, w, h);
    }
    return 1;  // handled; the reply goes out from gd_ack or the deadline
}

// The gl=off pixel paths. Reaching these means the domain's <gl enable='yes'/>
// did not take, which is worth saying once rather than discovering as a blank
// window.
static int gd_on_scanout_cpu(sd_bus_message* m, void* ud, sd_bus_error* e) {
    static int said = 0;
    if (!said) {
        said = 1;
        fprintf(stderr, "[guest] Scanout (CPU pixels): the domain is not "
                        "running with gl=on — nothing will be displayed\n");
    }
    return sd_bus_reply_method_return(m, "");
}

static int gd_on_update_cpu(sd_bus_message* m, void* ud, sd_bus_error* e) {
    return sd_bus_reply_method_return(m, "");
}

static int gd_on_disable(sd_bus_message* m, void* ud, sd_bus_error* e) {
    GuestDisplay* gd = ud;
    if (gd->cb.on_disable) {
        gd->cb.on_disable(gd->cb.ctx);
    }
    return sd_bus_reply_method_return(m, "");
}

static int gd_on_mouse_set(sd_bus_message* m, void* ud, sd_bus_error* e) {
    GuestDisplay* gd = ud;
    int x, y, on;
    int r = sd_bus_message_read(m, "iii", &x, &y, &on);
    if (r < 0) return r;
    if (gd->cb.on_mouse_set) {
        gd->cb.on_mouse_set(gd->cb.ctx, x, y, on);
    }
    return sd_bus_reply_method_return(m, "");
}

static int gd_on_cursor_define(sd_bus_message* m, void* ud, sd_bus_error* e) {
    GuestDisplay* gd = ud;
    int w, h, hx, hy;
    const void* data;
    size_t len;
    int r = sd_bus_message_read(m, "iiii", &w, &h, &hx, &hy);
    if (r < 0) return r;
    if ((r = sd_bus_message_read_array(m, 'y', &data, &len)) < 0) return r;
    if (gd->cb.on_cursor_define) {
        gd->cb.on_cursor_define(gd->cb.ctx, w, h, hx, hy, data, len);
    }
    return sd_bus_reply_method_return(m, "");
}

// QEMU does a synchronous GetAll on this during RegisterListener, so it must
// be answered by the vtable before the listener goes live.
static int gd_prop_listener_interfaces(sd_bus* bus, const char* path,
                                       const char* iface, const char* prop,
                                       sd_bus_message* reply, void* ud,
                                       sd_bus_error* e) {
    return sd_bus_message_append_strv(reply,
                                      (char*[]){(char*)IFACE_DMABUF2, NULL});
}

static const sd_bus_vtable gd_listener_vtable[] = {
    SD_BUS_VTABLE_START(0),
    SD_BUS_METHOD("Scanout", "uuuuay", "", gd_on_scanout_cpu,
                  SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("Update", "iiiiuuay", "", gd_on_update_cpu,
                  SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("ScanoutDMABUF", "huuuutb", "", gd_on_scanout_dmabuf,
                  SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("UpdateDMABUF", "iiii", "", gd_on_update_dmabuf,
                  SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("Disable", "", "", gd_on_disable, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("MouseSet", "iii", "", gd_on_mouse_set,
                  SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("CursorDefine", "iiiiay", "", gd_on_cursor_define,
                  SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_PROPERTY("Interfaces", "as", gd_prop_listener_interfaces, 0,
                    SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_VTABLE_END,
};

static const sd_bus_vtable gd_dmabuf2_vtable[] = {
    SD_BUS_VTABLE_START(0),
    SD_BUS_METHOD("ScanoutDMABUF2", "ahuuuuauauuuuutb", "",
                  gd_on_scanout_dmabuf2, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_VTABLE_END,
};

// ── clipboard object: the guest's half of the selection ────────────────────

static int gd_on_clip_grab(sd_bus_message* m, void* ud, sd_bus_error* e) {
    GuestDisplay* gd = ud;
    uint32_t selection, serial;
    char** mimes = NULL;
    int r = sd_bus_message_read(m, "uu", &selection, &serial);
    if (r < 0) return r;
    if ((r = sd_bus_message_read_strv(m, &mimes)) < 0) return r;
    int n = 0;
    while (mimes && mimes[n]) n++;
    if (selection == 0 && gd->cb.on_clipboard_grab) {
        gd->cb.on_clipboard_grab(gd->cb.ctx, (const char* const*)mimes, n);
    }
    for (int i = 0; i < n; i++) free(mimes[i]);
    free(mimes);
    return sd_bus_reply_method_return(m, "");
}

static int gd_on_clip_release(sd_bus_message* m, void* ud, sd_bus_error* e) {
    GuestDisplay* gd = ud;
    uint32_t selection;
    int r = sd_bus_message_read(m, "u", &selection);
    if (r < 0) return r;
    if (selection == 0 && gd->cb.on_clipboard_release) {
        gd->cb.on_clipboard_release(gd->cb.ctx);
    }
    return sd_bus_reply_method_return(m, "");
}

// The guest is pasting: it wants the host selection's bytes. Reading them
// means a round trip through our own compositor's data-control protocol, so
// the reply is deferred exactly as a frame ack is.
static int gd_on_clip_request(sd_bus_message* m, void* ud, sd_bus_error* e) {
    GuestDisplay* gd = ud;
    uint32_t selection;
    char** mimes = NULL;
    int r = sd_bus_message_read(m, "u", &selection);
    if (r < 0) return r;
    if ((r = sd_bus_message_read_strv(m, &mimes)) < 0) return r;

    int usable = selection == 0 && mimes && mimes[0] && gd->cb.on_clipboard_request &&
                 gd->n_clip_reqs < (int)(sizeof(gd->clip_reqs) /
                                         sizeof(gd->clip_reqs[0]));
    uint64_t token = 0;
    char* mime = NULL;
    if (usable) {
        token = ++gd->next_token;
        mime = strdup(mimes[0]);
        gd->clip_reqs[gd->n_clip_reqs].token = token;
        gd->clip_reqs[gd->n_clip_reqs].msg = sd_bus_message_ref(m);
        gd->n_clip_reqs++;
    }
    for (int i = 0; mimes && mimes[i]; i++) free(mimes[i]);
    free(mimes);

    if (!usable) {
        // Built by hand rather than through the "say" format: the array
        // argument's calling convention is the kind of thing that compiles
        // and then misreads the stack.
        sd_bus_message* reply = NULL;
        if (sd_bus_message_new_method_return(m, &reply) >= 0) {
            sd_bus_message_append(reply, "s", "");
            sd_bus_message_append_array(reply, 'y', NULL, 0);
            sd_bus_send(sd_bus_message_get_bus(m), reply, NULL);
            sd_bus_message_unref(reply);
        }
        return 1;
    }
    gd->cb.on_clipboard_request(gd->cb.ctx, token, mime ? mime : "");
    free(mime);
    return 1;  // handled; guest_display_clipboard_reply sends the reply
}

static int gd_prop_clip_interfaces(sd_bus* bus, const char* path,
                                   const char* iface, const char* prop,
                                   sd_bus_message* reply, void* ud,
                                   sd_bus_error* e) {
    return sd_bus_message_append_strv(reply, (char*[]){NULL});
}

static const sd_bus_vtable gd_clipboard_vtable[] = {
    SD_BUS_VTABLE_START(0),
    SD_BUS_METHOD("Grab", "uuas", "", gd_on_clip_grab,
                  SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("Release", "u", "", gd_on_clip_release,
                  SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("Request", "uas", "say", gd_on_clip_request,
                  SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_PROPERTY("Interfaces", "as", gd_prop_clip_interfaces, 0,
                    SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_VTABLE_END,
};

// ── command execution, on the bus thread ───────────────────────────────────

static void gd_ack(GuestDisplay* gd, uint64_t token) {
    for (int i = 0; i < gd->n_pending; i++) {
        if (gd->pending[i].token != token) {
            continue;
        }
        sd_bus_reply_method_return(gd->pending[i].msg, "");
        sd_bus_message_unref(gd->pending[i].msg);
        gd->pending[i] = gd->pending[--gd->n_pending];
        return;
    }
}

// Everything still unacked when the deadline passes, so a window nobody is
// drawing cannot freeze the guest.
static void gd_expire_pending(GuestDisplay* gd) {
    uint64_t now = gd_now_ms();
    for (int i = 0; i < gd->n_pending;) {
        if (gd->pending[i].deadline_ms > now) {
            i++;
            continue;
        }
        sd_bus_reply_method_return(gd->pending[i].msg, "");
        sd_bus_message_unref(gd->pending[i].msg);
        gd->pending[i] = gd->pending[--gd->n_pending];
    }
}

static void gd_clip_reply(GuestDisplay* gd, struct gd_cmd* c) {
    for (int i = 0; i < gd->n_clip_reqs; i++) {
        if (gd->clip_reqs[i].token != c->token) {
            continue;
        }
        sd_bus_message* reply = NULL;
        if (sd_bus_message_new_method_return(gd->clip_reqs[i].msg, &reply) >= 0) {
            sd_bus_message_append(reply, "s", c->mime ? c->mime : "");
            sd_bus_message_append_array(reply, 'y', c->data, c->len);
            sd_bus_send(gd->ctl, reply, NULL);
            sd_bus_message_unref(reply);
        }
        sd_bus_message_unref(gd->clip_reqs[i].msg);
        gd->clip_reqs[i] = gd->clip_reqs[--gd->n_clip_reqs];
        return;
    }
}

// The guest's answer to our Request. Signature is (say): the mime it chose,
// then the bytes.
static void gd_clip_pull_send(GuestDisplay* gd, const char* mime);

static int gd_on_clip_pull_reply(sd_bus_message* m, void* ud,
                                 sd_bus_error* e) {
    GuestDisplay* gd = ud;
    gd->clip_pull_inflight = 0;
    /* Whatever the outcome, a grab that arrived while this was in flight is
     * still owed a fetch. */
    char* again = gd->clip_pull_again;
    gd->clip_pull_again = NULL;

    const sd_bus_error* err = sd_bus_message_get_error(m);
    if (err) {
        fprintf(stderr, "[guest] clipboard pull failed: %s\n",
                err->message ? err->message : "?");
        if (again) { gd_clip_pull_send(gd, again); free(again); }
        return 0;
    }
    const char* mime = NULL;
    const void* data = NULL;
    size_t len = 0;
    int r = sd_bus_message_read(m, "s", &mime);
    if (r < 0) return 0;
    r = sd_bus_message_read_array(m, 'y', &data, &len);
    if (r < 0) return 0;
    if (gd->cb.on_clipboard_data) {
        gd->cb.on_clipboard_data(gd->cb.ctx, mime ? mime : "", data, len);
    }
    if (again) { gd_clip_pull_send(gd, again); free(again); }
    return 0;
}

/* Bus thread. Issues one Request, or remembers the mime if one is already
 * out. */
static void gd_clip_pull_send(GuestDisplay* gd, const char* mime) {
    if (!gd->clip_enabled || !gd->ctl) {
        return;
    }
    if (gd->clip_pull_inflight) {
        free(gd->clip_pull_again);
        gd->clip_pull_again = strdup(mime ? mime : "");
        return;
    }
    sd_bus_message* m = NULL;
    if (sd_bus_message_new_method_call(gd->ctl, &m, NULL, GD_CLIPBOARD,
                                       IFACE_CLIPBOARD, "Request") < 0) {
        return;
    }
    const char* mimes[2] = { mime ? mime : "", NULL };
    sd_bus_message_append(m, "u", (uint32_t)0);
    sd_bus_message_append_strv(m, (char**)mimes);
    /* Async, like everything else after RegisterListener: the guest answers
     * this by asking Windows, which takes as long as Windows likes. */
    int rr = sd_bus_call_async(gd->ctl, NULL, m, gd_on_clip_pull_reply, gd, 0);
    if (rr < 0) {
        fprintf(stderr, "[guest] clipboard pull: %s\n", strerror(-rr));
    } else {
        gd->clip_pull_inflight = 1;
    }
    sd_bus_message_unref(m);
}

static int gd_on_clip_register_reply(sd_bus_message* m, void* ud,
                                     sd_bus_error* e) {
    const sd_bus_error* err = sd_bus_message_get_error(m);
    fprintf(stderr, "[guest] clipboard Register: %s\n",
            err ? (err->message ? err->message : "failed") : "ok");
    return 0;
}

static void gd_enable_clipboard(GuestDisplay* gd) {
    if (gd->clip_enabled || !gd->ctl) {
        return;
    }
    int r = sd_bus_add_object_vtable(gd->ctl, NULL, GD_CLIPBOARD,
                                     IFACE_CLIPBOARD, gd_clipboard_vtable, gd);
    if (r < 0) {
        fprintf(stderr, "[guest] clipboard vtable: %s\n", strerror(-r));
        return;
    }
    gd->clip_enabled = 1;
    /* Async on purpose: QEMU's Register handler does a synchronous GetAll on
     * OUR object before it replies, so the reply cannot arrive until this
     * thread is back in its poll loop. */
    int r2 = sd_bus_call_method_async(gd->ctl, NULL, NULL, GD_CLIPBOARD,
                                      IFACE_CLIPBOARD, "Register",
                                      gd_on_clip_register_reply, gd, NULL);
    fprintf(stderr, "[guest] clipboard Register -> %s\n",
            r2 < 0 ? strerror(-r2) : "asked");
}

static void gd_exec(GuestDisplay* gd, struct gd_cmd* c) {
    switch (c->kind) {
        case GD_CMD_ACK:
            gd_ack(gd, c->token);
            break;
        case GD_CMD_KEY:
            if (c->a < 256) {
                if (c->down) {
                    gd->held[c->a >> 3] |= (uint8_t)(1u << (c->a & 7));
                } else {
                    gd->held[c->a >> 3] &= (uint8_t) ~(1u << (c->a & 7));
                }
            }
            gd_call_async(gd, IFACE_KBD, c->down ? "Press" : "Release", "u",
                          c->a);
            break;
        case GD_CMD_MOUSE_ABS:
            gd_call_async(gd, IFACE_MOUSE, "SetAbsPosition", "uu", c->a, c->b);
            break;
        case GD_CMD_MOUSE_BUTTON:
            gd_call_async(gd, IFACE_MOUSE, c->down ? "Press" : "Release", "u",
                          c->a);
            break;
        case GD_CMD_UI_SIZE:
            // (width_mm, height_mm, xoff, yoff, width, height) — the guest's
            // resolution service answers with a fresh scanout.
            gd_call_async(gd, IFACE_CONSOLE, "SetUIInfo", "qqiiuu",
                          (uint16_t)0, (uint16_t)0, 0, 0, c->a, c->b);
            break;
        case GD_CMD_CLIP_ENABLE:
            gd_enable_clipboard(gd);
            break;
        case GD_CMD_CLIP_GRAB:
            if (!gd->clip_enabled || !gd->ctl) {
                fprintf(stderr, "[guest] clipboard grab dropped: %s\n",
                        gd->clip_enabled ? "no bus" : "clipboard not registered");
                break;
            } else {
                sd_bus_message* m = NULL;
                if (sd_bus_message_new_method_call(gd->ctl, &m, NULL,
                                                   GD_CLIPBOARD,
                                                   IFACE_CLIPBOARD, "Grab") >= 0) {
                    sd_bus_message_append(m, "uu", (uint32_t)0,
                                          ++gd->clip_serial);
                    sd_bus_message_append_strv(m, c->mimes);
                    sd_bus_message_set_expect_reply(m, 0);
                    int rr = sd_bus_send(gd->ctl, m, NULL);
                    fprintf(stderr, "[guest] clipboard grab #%u -> %s\n",
                            gd->clip_serial, rr < 0 ? strerror(-rr) : "sent");
                    sd_bus_message_unref(m);
                }
            }
            break;
        case GD_CMD_CLIP_REPLY:
            gd_clip_reply(gd, c);
            break;
        case GD_CMD_CLIP_PULL:
            gd_clip_pull_send(gd, c->mime);
            break;
        default:
            break;
    }
    gd_cmd_free(c);
}

// ── the thread ─────────────────────────────────────────────────────────────

static int gd_on_register_reply(sd_bus_message* m, void* ud, sd_bus_error* e) {
    GuestDisplay* gd = ud;
    const sd_bus_error* err = sd_bus_message_get_error(m);
    if (err) {
        gd_state(gd, GUEST_DISPLAY_FAILED,
                 err->message ? err->message : "RegisterListener failed");
        gd->running = 0;
        return 0;
    }
    gd_state(gd, GUEST_DISPLAY_CONNECTED, NULL);
    return 0;
}

// Build our listener connection and hand QEMU the other end of it. The
// vtables go on before sd_bus_start — sd-bus's equivalent of GDBus's
// DELAY_MESSAGE_PROCESSING, which the spike needed because QEMU reads the
// Interfaces property during registration.
static int gd_setup_listener(GuestDisplay* gd) {
    int sp[2];
    if (socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, sp) < 0) {
        return -errno;
    }
    sd_bus* lis = NULL;
    int r;
    if ((r = sd_bus_new(&lis)) < 0) goto out;
    if ((r = sd_bus_set_fd(lis, sp[0], sp[0])) < 0) goto out;
    if ((r = sd_bus_set_description(lis, "starling-guest-listener")) < 0) goto out;
    if ((r = sd_bus_negotiate_fds(lis, 1)) < 0) goto out;
    if ((r = sd_bus_add_object_vtable(lis, NULL, GD_LISTENER, IFACE_LISTENER,
                                      gd_listener_vtable, gd)) < 0) goto out;
    if ((r = sd_bus_add_object_vtable(lis, NULL, GD_LISTENER, IFACE_DMABUF2,
                                      gd_dmabuf2_vtable, gd)) < 0) goto out;
    if ((r = sd_bus_start(lis)) < 0) goto out;

    // Destination is NULL: p2p has no bus daemon to route through.
    r = sd_bus_call_method_async(gd->ctl, NULL, NULL, GD_CONSOLE, IFACE_CONSOLE,
                                 "RegisterListener", gd_on_register_reply, gd,
                                 "h", sp[1]);
    if (r < 0) goto out;

    close(sp[1]);
    gd->lis = lis;
    return 0;

out:
    if (lis) sd_bus_flush_close_unref(lis);
    close(sp[0]);
    close(sp[1]);
    return r;
}

static void gd_release_held(GuestDisplay* gd) {
    for (uint32_t q = 0; q < 256; q++) {
        if (gd->held[q >> 3] & (1u << (q & 7))) {
            gd_call_async(gd, IFACE_KBD, "Release", "u", q);
        }
    }
    memset(gd->held, 0, sizeof(gd->held));
    if (gd->ctl) {
        sd_bus_flush(gd->ctl);
    }
}

static void* gd_thread(void* arg) {
    GuestDisplay* gd = arg;
    int r;

    gd_state(gd, GUEST_DISPLAY_CONNECTING, NULL);

    gd->conn = virConnectOpen("qemu:///system");
    if (!gd->conn) {
        virErrorPtr err = virGetLastError();
        gd_state(gd, GUEST_DISPLAY_FAILED,
                 err && err->message ? err->message
                                     : "cannot reach qemu:///system");
        return NULL;
    }
    gd->dom = virDomainLookupByName(gd->conn, gd->domain);
    if (!gd->dom) {
        virErrorPtr err = virGetLastError();
        gd_state(gd, GUEST_DISPLAY_FAILED,
                 err && err->message ? err->message : "no such domain");
        return NULL;
    }
    // One call only: a second openGraphicsFD closes the first connection, so
    // a stray dbus-display.py against the same domain takes this window down
    // and it looks like a shell crash.
    int gfd = virDomainOpenGraphicsFD(gd->dom, 0, 0);
    if (gfd < 0) {
        virErrorPtr err = virGetLastError();
        gd_state(gd, GUEST_DISPLAY_FAILED,
                 err && err->message ? err->message
                                     : "virDomainOpenGraphicsFD failed");
        return NULL;
    }

    // QEMU is the authentication server on both sockets and we are the SASL
    // client on both. No sd_bus_set_bus_client: p2p has no bus daemon, so no
    // Hello and no destinations.
    if ((r = sd_bus_new(&gd->ctl)) < 0) goto fail;
    if ((r = sd_bus_set_fd(gd->ctl, gfd, gfd)) < 0) goto fail;
    if ((r = sd_bus_set_description(gd->ctl, "starling-guest-ctl")) < 0) goto fail;
    if ((r = sd_bus_negotiate_fds(gd->ctl, 1)) < 0) goto fail;
    if ((r = sd_bus_start(gd->ctl)) < 0) goto fail;

    if ((r = gd_setup_listener(gd)) < 0) goto fail;

    pthread_mutex_lock(&gd->mu);
    gd->connected = 1;
    pthread_mutex_unlock(&gd->mu);

    while (gd->running) {
        int p1 = gd->ctl ? sd_bus_process(gd->ctl, NULL) : 0;
        int p2 = gd->lis ? sd_bus_process(gd->lis, NULL) : 0;
        if (p1 < 0 || p2 < 0) {
            break;
        }

        // Drain whatever the UI thread queued.
        for (;;) {
            struct gd_cmd c;
            pthread_mutex_lock(&gd->mu);
            if (gd->n_cmds == 0) {
                pthread_mutex_unlock(&gd->mu);
                break;
            }
            c = gd->cmds[0];
            gd->n_cmds--;
            memmove(&gd->cmds[0], &gd->cmds[1],
                    (size_t)gd->n_cmds * sizeof(gd->cmds[0]));
            pthread_mutex_unlock(&gd->mu);
            gd_exec(gd, &c);
        }

        gd_expire_pending(gd);
        if (p1 > 0 || p2 > 0) {
            continue;
        }

        struct pollfd pfd[3];
        int n = 0;
        pfd[n].fd = gd->wake_fd;
        pfd[n].events = POLLIN;
        n++;
        uint64_t bus_usec = UINT64_MAX;
        if (gd->ctl) {
            pfd[n].fd = sd_bus_get_fd(gd->ctl);
            pfd[n].events = (short)sd_bus_get_events(gd->ctl);
            n++;
            sd_bus_get_timeout(gd->ctl, &bus_usec);
        }
        if (gd->lis) {
            uint64_t t = UINT64_MAX;
            pfd[n].fd = sd_bus_get_fd(gd->lis);
            pfd[n].events = (short)sd_bus_get_events(gd->lis);
            n++;
            sd_bus_get_timeout(gd->lis, &t);
            if (t < bus_usec) bus_usec = t;
        }
        int timeout_ms = 200;
        if (bus_usec != UINT64_MAX && bus_usec / 1000 < (uint64_t)timeout_ms) {
            timeout_ms = (int)(bus_usec / 1000);
        }
        // A pending ack must not wait on the bus being readable.
        if (gd->n_pending > 0) {
            uint64_t now = gd_now_ms();
            for (int i = 0; i < gd->n_pending; i++) {
                int64_t left = (int64_t)gd->pending[i].deadline_ms - (int64_t)now;
                if (left < 0) left = 0;
                if (left < timeout_ms) timeout_ms = (int)left;
            }
        }
        if (poll(pfd, (nfds_t)n, timeout_ms) < 0 && errno != EINTR) {
            break;
        }
        if (pfd[0].revents & POLLIN) {
            uint64_t drain;
            ssize_t got = read(gd->wake_fd, &drain, sizeof(drain));
            (void)got;
        }
    }

    if (gd->running) {
        // We fell out of the loop rather than being closed: the socket went.
        gd_state(gd, GUEST_DISPLAY_DISCONNECTED, NULL);
    }
    return NULL;

fail:
    gd_state(gd, GUEST_DISPLAY_FAILED, strerror(-r));
    return NULL;
}

// ── public API ─────────────────────────────────────────────────────────────

GuestDisplay* guest_display_open(const char* domain,
                                 const GuestDisplayCallbacks* cb) {
    if (!domain || !cb) {
        return NULL;
    }
    GuestDisplay* gd = calloc(1, sizeof(*gd));
    if (!gd) {
        return NULL;
    }
    gd->cb = *cb;
    snprintf(gd->domain, sizeof(gd->domain), "%s", domain);
    gd->running = 1;
    gd->wake_fd = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
    const char* ack = getenv("STARLING_GUEST_ACK");
    gd->ack_immediate = ack && strcmp(ack, "immediate") == 0;
    pthread_mutex_init(&gd->mu, NULL);
    if (gd->wake_fd < 0 || pthread_create(&gd->thread, NULL, gd_thread, gd) != 0) {
        if (gd->wake_fd >= 0) close(gd->wake_fd);
        pthread_mutex_destroy(&gd->mu);
        free(gd);
        return NULL;
    }
    gd->thread_started = 1;
    return gd;
}

void guest_display_close(GuestDisplay* gd) {
    if (!gd) {
        return;
    }
    // running = 0 first: it is also what tells the thread its exit is a close
    // rather than a hang-up, so no DISCONNECTED is reported for a window the
    // user shut themselves.
    gd->running = 0;
    gd_wake(gd);
    if (gd->thread_started) {
        pthread_join(gd->thread, NULL);
    }

    gd_release_held(gd);
    for (int i = 0; i < gd->n_pending; i++) {
        sd_bus_reply_method_return(gd->pending[i].msg, "");
        sd_bus_message_unref(gd->pending[i].msg);
    }
    for (int i = 0; i < gd->n_clip_reqs; i++) {
        sd_bus_message_unref(gd->clip_reqs[i].msg);
    }
    for (int i = 0; i < gd->n_cmds; i++) {
        gd_cmd_free(&gd->cmds[i]);
    }
    free(gd->clip_pull_again);
    if (gd->lis) sd_bus_flush_close_unref(gd->lis);
    if (gd->ctl) sd_bus_flush_close_unref(gd->ctl);
    if (gd->dom) virDomainFree(gd->dom);
    if (gd->conn) virConnectClose(gd->conn);
    close(gd->wake_fd);
    pthread_mutex_destroy(&gd->mu);
    free(gd);
}

void guest_display_ack_frame(GuestDisplay* gd, uint64_t token) {
    struct gd_cmd c = {.kind = GD_CMD_ACK, .token = token};
    gd_push(gd, &c);
}

void guest_display_key(GuestDisplay* gd, uint32_t qnum, int down) {
    struct gd_cmd c = {.kind = GD_CMD_KEY, .a = qnum, .down = down};
    gd_push(gd, &c);
}

void guest_display_mouse_abs(GuestDisplay* gd, uint32_t x, uint32_t y) {
    struct gd_cmd c = {.kind = GD_CMD_MOUSE_ABS, .a = x, .b = y};
    gd_push(gd, &c);
}

void guest_display_mouse_button(GuestDisplay* gd, uint32_t button, int down) {
    struct gd_cmd c = {.kind = GD_CMD_MOUSE_BUTTON, .a = button, .down = down};
    gd_push(gd, &c);
}

void guest_display_set_ui_size(GuestDisplay* gd, uint32_t w, uint32_t h) {
    struct gd_cmd c = {.kind = GD_CMD_UI_SIZE, .a = w, .b = h};
    gd_push(gd, &c);
}

void guest_display_clipboard_enable(GuestDisplay* gd) {
    struct gd_cmd c = {.kind = GD_CMD_CLIP_ENABLE};
    gd_push(gd, &c);
}

void guest_display_clipboard_grab(GuestDisplay* gd, const char* const* mimes,
                                  int n) {
    struct gd_cmd c = {.kind = GD_CMD_CLIP_GRAB};
    if (n > 0) {
        c.mimes = calloc((size_t)n + 1, sizeof(char*));
        if (!c.mimes) return;
        for (int i = 0; i < n; i++) {
            c.mimes[i] = strdup(mimes[i]);
        }
        c.n_mimes = n;
    }
    gd_push(gd, &c);
}

void guest_display_clipboard_pull(GuestDisplay* gd, const char* mime) {
    struct gd_cmd c = {.kind = GD_CMD_CLIP_PULL};
    c.mime = strdup(mime ? mime : "text/plain;charset=utf-8");
    gd_push(gd, &c);
}

void guest_display_clipboard_reply(GuestDisplay* gd, uint64_t token,
                                   const char* mime, const void* data,
                                   size_t len) {
    struct gd_cmd c = {.kind = GD_CMD_CLIP_REPLY, .token = token};
    c.mime = strdup(mime ? mime : "");
    if (len > 0 && data) {
        c.data = malloc(len);
        if (c.data) {
            memcpy(c.data, data, len);
            c.len = len;
        }
    }
    gd_push(gd, &c);
}

// ── libvirt, off the bus ───────────────────────────────────────────────────

// Each of these opens its own connection: they are called before a display
// exists (is the domain even running?) and after one has failed.
static virDomainPtr gd_lookup(virConnectPtr* out_conn, const char* domain) {
    virConnectPtr c = virConnectOpen("qemu:///system");
    if (!c) {
        return NULL;
    }
    virDomainPtr d = virDomainLookupByName(c, domain);
    if (!d) {
        virConnectClose(c);
        return NULL;
    }
    *out_conn = c;
    return d;
}

int guest_display_domain_state(const char* domain) {
    virConnectPtr c = NULL;
    virDomainPtr d = gd_lookup(&c, domain);
    if (!d) {
        return -1;
    }
    int state = 0, reason = 0;
    int r = virDomainGetState(d, &state, &reason, 0);
    virDomainFree(d);
    virConnectClose(c);
    return r < 0 ? -1 : state;
}

int guest_display_domain_start(const char* domain) {
    virConnectPtr c = NULL;
    virDomainPtr d = gd_lookup(&c, domain);
    if (!d) {
        return -1;
    }
    int r = virDomainCreate(d);
    virDomainFree(d);
    virConnectClose(c);
    return r;
}

int guest_display_domain_shutdown(const char* domain) {
    virConnectPtr c = NULL;
    virDomainPtr d = gd_lookup(&c, domain);
    if (!d) {
        return -1;
    }
    int r = virDomainShutdown(d);
    virDomainFree(d);
    virConnectClose(c);
    return r;
}
