// guest-display-probe — does sd-bus speak QEMU's p2p dbus display?
//
// The one question the M1 plan rests on and nothing in-tree answers: sd-bus
// on a socket from virDomainOpenGraphicsFD, against QEMU's GDBus server, with
// fd passing. Prints the first scanout, the first cursor, and how long the
// guest takes to answer SetUIInfo. The sd-bus counterpart of
// docs/windows-vm/dbus-display.py.
//
//   gcc -O1 -g probe.c -o probe $(pkg-config --cflags --libs libsystemd) -lvirt

#define _GNU_SOURCE
#include <errno.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#include <libvirt/libvirt.h>
#include <libvirt/virterror.h>
#include <systemd/sd-bus.h>

#define ROOT     "/org/qemu/Display1"
#define CONSOLE  ROOT "/Console_0"
#define LISTENER ROOT "/Listener"
#define IFACE_CONSOLE  "org.qemu.Display1.Console"
#define IFACE_KBD      "org.qemu.Display1.Keyboard"
#define IFACE_MOUSE    "org.qemu.Display1.Mouse"
#define IFACE_LISTENER "org.qemu.Display1.Listener"
#define IFACE_DMABUF2  "org.qemu.Display1.Listener.Unix.ScanoutDMABUF2"

static uint64_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static uint64_t t0;
#define LOG(...) do { printf("[%6.2fs] ", (now_ms() - t0) / 1000.0); \
                      printf(__VA_ARGS__); putchar('\n'); fflush(stdout); } while (0)

struct state {
    int detach_on_disable, want_detach, reattaches;
    int scanouts, updates, cursors, disables, mousesets, cpu_scanouts;
    uint32_t w, h;               // last scanout size
    uint64_t resize_sent_ms;     // 0 = not waiting
    uint32_t want_w, want_h;
    int resize_answered;
    sd_bus *ctl;
};

static void fourcc_str(uint32_t f, char out[5]) {
    out[0] = f & 0xff; out[1] = (f >> 8) & 0xff;
    out[2] = (f >> 16) & 0xff; out[3] = (f >> 24) & 0xff; out[4] = 0;
    for (int i = 0; i < 4; i++) if (out[i] < 32 || out[i] > 126) out[i] = '?';
}

// ---- listener methods -----------------------------------------------------

static int on_scanout_dmabuf2(sd_bus_message *m, void *ud, sd_bus_error *e) {
    struct state *s = ud;
    int r, fds[8], nfd = 0, fd;
    uint32_t x, y, w, h, nplanes, fourcc, bw, bh;
    uint32_t offsets[8] = {0}, strides[8] = {0};
    uint64_t modifier; int y0_top;

    if ((r = sd_bus_message_enter_container(m, 'a', "h")) < 0) return r;
    while ((r = sd_bus_message_read(m, "h", &fd)) > 0)
        if (nfd < 8) fds[nfd++] = fd;
    if (r < 0) return r;
    sd_bus_message_exit_container(m);

    if ((r = sd_bus_message_read(m, "uuuu", &x, &y, &w, &h)) < 0) return r;
    for (int pass = 0; pass < 2; pass++) {
        uint32_t *dst = pass ? strides : offsets, v; int n = 0;
        if ((r = sd_bus_message_enter_container(m, 'a', "u")) < 0) return r;
        while ((r = sd_bus_message_read(m, "u", &v)) > 0) if (n < 8) dst[n++] = v;
        if (r < 0) return r;
        sd_bus_message_exit_container(m);
    }
    if ((r = sd_bus_message_read(m, "uuuu", &nplanes, &fourcc, &bw, &bh)) < 0) return r;
    if ((r = sd_bus_message_read(m, "tb", &modifier, &y0_top)) < 0) return r;

    char fc[5]; fourcc_str(fourcc, fc);
    s->scanouts++;
    LOG("ScanoutDMABUF2 #%d  %ux%u  fourcc=%s(0x%08x)  planes=%u  fds=%d",
        s->scanouts, w, h, fc, fourcc, nplanes, nfd);
    LOG("               stride=%u offset=%u  modifier=0x%016llx  y0_top=%d  backing=%ux%u",
        strides[0], offsets[0], (unsigned long long)modifier, y0_top, bw, bh);
    // Prove the fd is a real, mappable dma-buf: dup it (what GuestDisplay
    // would hand the texture registry) and stat its size.
    if (nfd > 0) {
        int d = dup(fds[0]);
        off_t sz = d >= 0 ? lseek(d, 0, SEEK_END) : -1;
        LOG("               fd dup -> %d, size %lld bytes (need >= %llu)",
            d, (long long)sz, (unsigned long long)strides[0] * h);
        if (d >= 0) close(d);
    }
    if (s->resize_sent_ms && (w != s->w || h != s->h)) {
        LOG(">>> guest answered SetUIInfo(%ux%u) in %llu ms -> %ux%u",
            s->want_w, s->want_h,
            (unsigned long long)(now_ms() - s->resize_sent_ms), w, h);
        s->resize_answered = 1;
        s->resize_sent_ms = 0;
    }
    s->w = w; s->h = h;
    return sd_bus_reply_method_return(m, "");
}

static int on_scanout_dmabuf(sd_bus_message *m, void *ud, sd_bus_error *e) {
    struct state *s = ud;
    int fd, y0_top; uint32_t w, h, stride, fourcc; uint64_t mod;
    int r = sd_bus_message_read(m, "huuuutb", &fd, &w, &h, &stride, &fourcc, &mod, &y0_top);
    if (r < 0) return r;
    char fc[5]; fourcc_str(fourcc, fc);
    s->scanouts++;
    LOG("ScanoutDMABUF (v1) %ux%u fourcc=%s stride=%u mod=0x%llx y0_top=%d",
        w, h, fc, stride, (unsigned long long)mod, y0_top);
    s->w = w; s->h = h;
    return sd_bus_reply_method_return(m, "");
}

static int on_update_dmabuf(sd_bus_message *m, void *ud, sd_bus_error *e) {
    struct state *s = ud;
    int x, y, w, h;
    int r = sd_bus_message_read(m, "iiii", &x, &y, &w, &h);
    if (r < 0) return r;
    if (s->updates < 3 || s->updates % 100 == 0)
        LOG("UpdateDMABUF #%d  damage %dx%d+%d+%d", s->updates + 1, w, h, x, y);
    s->updates++;
    return sd_bus_reply_method_return(m, "");   // the frame ack
}

static int on_scanout_cpu(sd_bus_message *m, void *ud, sd_bus_error *e) {
    struct state *s = ud;
    s->cpu_scanouts++;
    LOG("Scanout (CPU pixels) — gl=on is not in effect!");
    return sd_bus_reply_method_return(m, "");
}
static int on_update_cpu(sd_bus_message *m, void *ud, sd_bus_error *e) {
    return sd_bus_reply_method_return(m, "");
}
static int on_disable(sd_bus_message *m, void *ud, sd_bus_error *e) {
    struct state *s = ud; s->disables++;
    LOG("Disable #%d%s", s->disables,
        s->detach_on_disable ? " -> dropping the listener" : "");
    if (s->detach_on_disable) s->want_detach = 1;
    return sd_bus_reply_method_return(m, "");
}
static int on_mouse_set(sd_bus_message *m, void *ud, sd_bus_error *e) {
    struct state *s = ud; int x, y, on;
    int r = sd_bus_message_read(m, "iii", &x, &y, &on);
    if (r < 0) return r;
    if (s->mousesets++ < 3) LOG("MouseSet %d,%d on=%d", x, y, on);
    return sd_bus_reply_method_return(m, "");
}
static int on_cursor_define(sd_bus_message *m, void *ud, sd_bus_error *e) {
    struct state *s = ud;
    int w, h, hx, hy; const void *data; size_t len;
    int r = sd_bus_message_read(m, "iiii", &w, &h, &hx, &hy);
    if (r < 0) return r;
    r = sd_bus_message_read_array(m, 'y', &data, &len);
    if (r < 0) return r;
    s->cursors++;
    if (s->cursors <= 3) {
        const uint8_t *p = data;
        int opaque = 0;
        for (size_t i = 3; i < len; i += 4) if (p[i] == 0xff) opaque++;
        LOG("CursorDefine #%d  %dx%d hot=%d,%d  %zu bytes (%zu expected)  "
            "fully-opaque px=%d", s->cursors, w, h, hx, hy, len,
            (size_t)w * h * 4, opaque);
    }
    return sd_bus_reply_method_return(m, "");
}

static int prop_interfaces(sd_bus *bus, const char *path, const char *iface,
                           const char *prop, sd_bus_message *reply,
                           void *ud, sd_bus_error *e) {
    return sd_bus_message_append_strv(reply, (char *[]){ (char *)IFACE_DMABUF2, NULL });
}

static const sd_bus_vtable listener_vtable[] = {
    SD_BUS_VTABLE_START(0),
    SD_BUS_METHOD("Scanout",      "uuuuay",   "", on_scanout_cpu,    SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("Update",       "iiiiuuay", "", on_update_cpu,     SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("ScanoutDMABUF","huuuutb",  "", on_scanout_dmabuf, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("UpdateDMABUF", "iiii",     "", on_update_dmabuf,  SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("Disable",      "",         "", on_disable,        SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("MouseSet",     "iii",      "", on_mouse_set,      SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("CursorDefine", "iiiiay",   "", on_cursor_define,  SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_PROPERTY("Interfaces", "as", prop_interfaces, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_VTABLE_END
};

static const sd_bus_vtable dmabuf2_vtable[] = {
    SD_BUS_VTABLE_START(0),
    SD_BUS_METHOD("ScanoutDMABUF2", "ahuuuuauauuuuutb", "", on_scanout_dmabuf2,
                  SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_VTABLE_END
};

// Build a listener connection and hand its far end to QEMU. Vtables go on
// before sd_bus_start (sd-bus's DELAY_MESSAGE_PROCESSING).
static int setup_listener(sd_bus *ctl, sd_bus **out, struct state *st) {
    int sp[2], r;
    if (socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, sp) < 0) return -errno;
    sd_bus *lis = NULL;
    if ((r = sd_bus_new(&lis)) < 0) return r;
    if ((r = sd_bus_set_fd(lis, sp[0], sp[0])) < 0) return r;
    if ((r = sd_bus_set_description(lis, "qemu-display-listener")) < 0) return r;
    if ((r = sd_bus_negotiate_fds(lis, 1)) < 0) return r;
    if ((r = sd_bus_add_object_vtable(lis, NULL, LISTENER, IFACE_LISTENER,
                                      listener_vtable, st)) < 0) return r;
    if ((r = sd_bus_add_object_vtable(lis, NULL, LISTENER, IFACE_DMABUF2,
                                      dmabuf2_vtable, st)) < 0) return r;
    if ((r = sd_bus_start(lis)) < 0) return r;
    sd_bus_error err = SD_BUS_ERROR_NULL;
    r = sd_bus_call_method(ctl, NULL, CONSOLE, IFACE_CONSOLE, "RegisterListener",
                           &err, NULL, "h", sp[1]);
    close(sp[1]);
    if (r < 0) {
        LOG("RegisterListener failed: %s", err.message ? err.message : strerror(-r));
        sd_bus_flush_close_unref(lis);
        return r;
    }
    *out = lis;
    return 0;
}

// ---- main -----------------------------------------------------------------

int main(int argc, char **argv) {
    t0 = now_ms();
    const char *domain = argc > 1 ? argv[1] : "win11-dbus";
    int seconds = argc > 2 ? atoi(argv[2]) : 20;
    struct state st = {0};
    st.detach_on_disable = (argc > 3 && strcmp(argv[3], "detach") == 0);
    int r;

    virConnectPtr c = virConnectOpen("qemu:///system");
    if (!c) { fprintf(stderr, "virConnectOpen failed\n"); return 1; }
    virDomainPtr d = virDomainLookupByName(c, domain);
    if (!d) { fprintf(stderr, "no domain %s\n", domain); return 1; }
    // ONE call only: a second openGraphicsFD closes the first connection.
    int gfd = virDomainOpenGraphicsFD(d, 0, 0);
    if (gfd < 0) {
        virErrorPtr err = virGetLastError();
        fprintf(stderr, "virDomainOpenGraphicsFD: %s\n", err ? err->message : "?");
        return 1;
    }
    LOG("libvirt gave us fd %d for %s", gfd, domain);

    // Control connection: QEMU is the auth server, we are the client. No
    // Hello (p2p), so no sd_bus_set_bus_client.
    sd_bus *ctl = NULL;
    if ((r = sd_bus_new(&ctl)) < 0) goto fail;
    if ((r = sd_bus_set_fd(ctl, gfd, gfd)) < 0) goto fail;
    if ((r = sd_bus_set_description(ctl, "qemu-display-ctl")) < 0) goto fail;
    if ((r = sd_bus_negotiate_fds(ctl, 1)) < 0) goto fail;
    if ((r = sd_bus_start(ctl)) < 0) goto fail;
    LOG("control bus started (sd_bus_set_fd + sd_bus_start, no Hello)");
    st.ctl = ctl;

    int is_abs = 0;
    sd_bus_error perr = SD_BUS_ERROR_NULL;
    r = sd_bus_get_property_trivial(ctl, NULL, CONSOLE, IFACE_MOUSE,
                                    "IsAbsolute", &perr, 'b', &is_abs);
    LOG("Mouse.IsAbsolute = %s", r < 0 ? "?" : (is_abs ? "true" : "false"));

    sd_bus *lis = NULL;
    if ((r = setup_listener(ctl, &lis, &st)) < 0) goto fail;
    LOG("listener registered%s", st.detach_on_disable
        ? " (will drop it on Disable — the reboot workaround)" : "");

    // Fire-and-forget: p2p has no destination, and after RegisterListener
    // nothing may block (a sync call here deadlocks both sides for 25s).
    #define ASYNC(iface, member, types, ...) do {                              \
        int rr = sd_bus_call_method_async(ctl, NULL, NULL, CONSOLE, iface,     \
                                          member, NULL, NULL, types,           \
                                          __VA_ARGS__);                        \
        if (rr < 0) LOG("%s.%s failed: %s", iface, member, strerror(-rr));      \
    } while (0)

    uint64_t t_start = now_ms();
    uint64_t deadline = t_start + (uint64_t)seconds * 1000;
    int stage = 0;
    uint64_t reattach_at = 0;
    uint64_t key_sent_ms = 0; int updates_at_key = 0;

    while (now_ms() < deadline) {
        int p1 = sd_bus_process(ctl, NULL);
        int p2 = lis ? sd_bus_process(lis, NULL) : 0;
        if (p1 < 0) { LOG("control bus error: %d", p1); break; }
        if (p2 < 0) {
            LOG("listener bus error: %d — dropping it", p2);
            sd_bus_flush_close_unref(lis); lis = NULL;
            reattach_at = now_ms() + 6000;
        }

        if (st.want_detach && lis) {
            st.want_detach = 0;
            sd_bus_flush_close_unref(lis);
            lis = NULL;
            LOG("listener dropped; will re-register in 6s");
            st.resize_sent_ms = 0;
            reattach_at = now_ms() + 6000;
        }
        if (!lis && reattach_at && now_ms() > reattach_at) {
            reattach_at = 0;
            if (setup_listener(ctl, &lis, &st) == 0) {
                st.reattaches++;
                LOG(">>> re-registered a listener after the reboot (#%d)",
                    st.reattaches);
            } else {
                reattach_at = now_ms() + 4000;   // guest still coming back
            }
        }

        uint64_t el = now_ms() - t_start;

        if (st.detach_on_disable) { /* reboot test: no input */ }
        else if (stage == 0 && el > 2000) {
            stage = 1;
            LOG("--- moving the pointer (expect MouseSet, and CursorDefine "
                "if HWCursor=1 is set in the guest) ---");
            for (int i = 0; i < 6; i++) {
                uint32_t mx = 200 + i * 150, my = 200 + i * 90;
                ASYNC(IFACE_MOUSE, "SetAbsPosition", "uu", mx, my);
            }
        } else if (stage == 1 && el > 7000) {
            stage = 2;
            st.want_w = 1280; st.want_h = 800;
            LOG("--- SetUIInfo(%ux%u) ---", st.want_w, st.want_h);
            ASYNC(IFACE_CONSOLE, "SetUIInfo", "qqiiuu",
                  (unsigned)0, (unsigned)0, 0, 0, st.want_w, st.want_h);
            st.resize_sent_ms = now_ms();
        } else if (stage == 2 && el > 17000) {
            stage = 3;
            // qnum 0xDB = HID 0xE3 (Left GUI) straight out of the table
            // generated this session: shell/.../Guest/HidQnum.swift.
            LOG("--- Left GUI (HID 0xE3 -> qnum 0xDB): the Start menu ---");
            updates_at_key = st.updates; key_sent_ms = now_ms();
            ASYNC(IFACE_KBD, "Press", "u", (unsigned)0xDB);
            ASYNC(IFACE_KBD, "Release", "u", (unsigned)0xDB);
        } else if (stage == 3 && el > 24000) {
            stage = 4;
            LOG("--- Escape (qnum 0x01) ---");
            ASYNC(IFACE_KBD, "Press", "u", (unsigned)0x01);
            ASYNC(IFACE_KBD, "Release", "u", (unsigned)0x01);
        }

        if (key_sent_ms && st.updates > updates_at_key) {
            LOG(">>> the guest repainted %llu ms after the key "
                "(%d damage rects) — the qnum table reaches Windows",
                (unsigned long long)(now_ms() - key_sent_ms),
                st.updates - updates_at_key);
            key_sent_ms = 0;
        }

        if (p1 > 0 || p2 > 0) continue;
        struct pollfd pfd[2] = {
            { sd_bus_get_fd(ctl), sd_bus_get_events(ctl), 0 },
            { lis ? sd_bus_get_fd(lis) : -1, lis ? sd_bus_get_events(lis) : 0, 0 },
        };
        if (poll(pfd, lis ? 2 : 1, 100) < 0 && errno != EINTR) break;
    }

    LOG("--- summary ---");
    LOG("scanouts=%d (dma-buf)  cpu-scanouts=%d  updates=%d  cursors=%d  "
        "disables=%d  mousesets=%d", st.scanouts, st.cpu_scanouts, st.updates,
        st.cursors, st.disables, st.mousesets);
    LOG("last scanout %ux%u; SetUIInfo answered: %s",
        st.w, st.h, st.resize_answered ? "yes" : "no");
    LOG("reattaches=%d", st.reattaches);
    if (lis) sd_bus_flush_close_unref(lis);
    sd_bus_flush_close_unref(ctl);
    virDomainFree(d); virConnectClose(c);
    return st.scanouts > 0 ? 0 : 2;

fail:
    fprintf(stderr, "sd-bus setup failed: %s\n", strerror(-r));
    return 1;
}
