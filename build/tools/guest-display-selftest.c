// guest-display-selftest — drive shell/Sources/GuestDisplay against a real
// domain, with no shell in the way.
//
// docs/windows-vm/guest-display-probe.c answered a different question: can
// sd-bus speak QEMU's p2p display at all. This one exercises the code we
// actually ship — the callback struct, the command queue, the deferred frame
// ack, the held-key release on close — so a bug there is found here rather
// than as "the Windows window is black".
//
//   gcc -O1 -g -Wall -Ishell/Sources/GuestDisplay/include
//       build/tools/guest-display-selftest.c
//       shell/Sources/GuestDisplay/guest_display.c -o /tmp/gd-selftest
//       $(pkg-config --cflags --libs libsystemd libvirt) -lpthread
//   /tmp/gd-selftest win11-dbus 30
//
// (one line; wrapped here because a backslash in a // comment is a warning)
//
// Exits 0 when a scanout arrived and the guest repainted after a keystroke.

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "guest_display.h"

static uint64_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000 + (uint64_t)ts.tv_nsec / 1000000;
}

static uint64_t t0;
#define LOG(...)                                                    \
    do {                                                            \
        printf("[%6.2fs] ", (now_ms() - t0) / 1000.0);              \
        printf(__VA_ARGS__);                                        \
        putchar('\n');                                              \
        fflush(stdout);                                             \
    } while (0)

struct self {
    GuestDisplay* gd;
    int state;
    int scanouts, updates, cursors, mousesets, disables;
    uint32_t w, h;
    uint64_t key_at;
    int updates_at_key;
    int repainted_after_key;
    uint64_t resize_at;
    int resized;
    uint32_t want_w, want_h;
};

static void on_state(void* ctx, int state, const char* detail) {
    struct self* s = ctx;
    static const char* names[] = {"CONNECTING", "CONNECTED", "DISCONNECTED",
                                  "FAILED"};
    s->state = state;
    LOG("state -> %s%s%s", names[state], detail ? ": " : "",
        detail ? detail : "");
}

static void on_scanout(void* ctx, int fd, uint32_t w, uint32_t h,
                       uint32_t stride, uint32_t offset, uint32_t fourcc,
                       uint64_t modifier, int y0_top) {
    struct self* s = ctx;
    char fc[5] = {(char)(fourcc & 0xff), (char)((fourcc >> 8) & 0xff),
                  (char)((fourcc >> 16) & 0xff), (char)((fourcc >> 24) & 0xff),
                  0};
    s->scanouts++;
    LOG("scanout #%d %ux%u %s stride=%u offset=%u mod=0x%016llx y0_top=%d fd=%d",
        s->scanouts, w, h, fc, stride, offset, (unsigned long long)modifier,
        y0_top, fd);
    if (stride < w * 4) {
        LOG("  !! stride is below width*4 — the import would read short");
    }
    if (s->resize_at && (w != s->w || h != s->h)) {
        LOG(">>> SetUIInfo(%ux%u) answered in %llu ms -> %ux%u", s->want_w,
            s->want_h, (unsigned long long)(now_ms() - s->resize_at), w, h);
        s->resized = 1;
        s->resize_at = 0;
    }
    s->w = w;
    s->h = h;
    // The shell hands this to the texture registry with ownsFd: true; here it
    // just proves the fd is ours to close.
    close(fd);
}

static void on_update(void* ctx, uint64_t token, int x, int y, int w, int h) {
    struct self* s = ctx;
    if (s->updates < 3) {
        LOG("update #%d damage %dx%d+%d+%d token=%llu", s->updates + 1, w, h, x,
            y, (unsigned long long)token);
    }
    s->updates++;
    // What the compositor's present callback does. Acking from inside a
    // callback is the same path — the command is queued, never executed
    // inline.
    if (token) {
        guest_display_ack_frame(s->gd, token);
    }
    if (s->key_at && !s->repainted_after_key && s->updates > s->updates_at_key) {
        LOG(">>> the guest repainted %llu ms after the key",
            (unsigned long long)(now_ms() - s->key_at));
        s->repainted_after_key = 1;
    }
}

static void on_disable(void* ctx) {
    struct self* s = ctx;
    s->disables++;
    LOG("disable #%d", s->disables);
}

static void on_cursor_define(void* ctx, int w, int h, int hx, int hy,
                             const uint8_t* bgra, size_t len) {
    struct self* s = ctx;
    s->cursors++;
    if (s->cursors > 3) {
        return;
    }
    int soft = 0;
    for (size_t i = 3; i < len; i += 4) {
        if (bgra[i] != 0 && bgra[i] != 0xff) soft++;
    }
    LOG("cursor #%d %dx%d hot=%d,%d %zu bytes (%zu expected), %d "
        "partially-transparent px",
        s->cursors, w, h, hx, hy, len, (size_t)w * h * 4, soft);
}

static void on_mouse_set(void* ctx, int x, int y, int visible) {
    struct self* s = ctx;
    if (s->mousesets++ < 3) {
        LOG("mouse set %d,%d visible=%d", x, y, visible);
    }
}

int main(int argc, char** argv) {
    t0 = now_ms();
    const char* domain = argc > 1 ? argv[1] : "win11-dbus";
    int seconds = argc > 2 ? atoi(argv[2]) : 25;

    int st = guest_display_domain_state(domain);
    LOG("domain %s state=%d (1 = running)", domain, st);
    if (st < 0) {
        fprintf(stderr, "no such domain, or qemu:///system is unreachable\n");
        return 1;
    }
    if (st != 1) {
        LOG("starting it");
        if (guest_display_domain_start(domain) < 0) {
            fprintf(stderr, "virDomainCreate failed\n");
            return 1;
        }
        sleep(20);  // the display only exists once QEMU is up
    }

    struct self s = {0};
    GuestDisplayCallbacks cb = {
        .ctx = &s,
        .on_state = on_state,
        .on_scanout = on_scanout,
        .on_update = on_update,
        .on_disable = on_disable,
        .on_cursor_define = on_cursor_define,
        .on_mouse_set = on_mouse_set,
    };
    s.gd = guest_display_open(domain, &cb);
    if (!s.gd) {
        fprintf(stderr, "guest_display_open failed to start its thread\n");
        return 1;
    }

    int stage = 0;
    uint64_t start = now_ms();
    while (now_ms() - start < (uint64_t)seconds * 1000) {
        usleep(50 * 1000);
        if (s.state == GUEST_DISPLAY_FAILED ||
            s.state == GUEST_DISPLAY_DISCONNECTED) {
            break;
        }
        uint64_t el = now_ms() - start;
        if (stage == 0 && el > 3000) {
            stage = 1;
            LOG("--- pointer sweep (expect mouse sets, and cursors with "
                "HWCursor=1) ---");
            for (int i = 0; i < 6; i++) {
                guest_display_mouse_abs(s.gd, 200 + i * 150, 200 + i * 90);
                usleep(60 * 1000);
            }
        } else if (stage == 1 && el > 7000) {
            stage = 2;
            // Ask for a size the guest is NOT already at, or it answers with
            // nothing and the check silently proves nothing.
            s.want_w = (s.w == 1280) ? 1600 : 1280;
            s.want_h = (s.w == 1280) ? 900 : 800;
            LOG("--- SetUIInfo(%ux%u) ---", s.want_w, s.want_h);
            s.resize_at = now_ms();
            guest_display_set_ui_size(s.gd, s.want_w, s.want_h);
        } else if (stage == 2 && el > 14000) {
            stage = 3;
            LOG("--- Left GUI (qnum 0xDB): the Start menu ---");
            s.key_at = now_ms();
            s.updates_at_key = s.updates;
            guest_display_key(s.gd, 0xDB, 1);
            guest_display_key(s.gd, 0xDB, 0);
        } else if (stage == 3 && el > 19000) {
            stage = 4;
            LOG("--- Escape, and one key left DOWN for close to release ---");
            guest_display_key(s.gd, 0x01, 1);
            guest_display_key(s.gd, 0x01, 0);
            guest_display_key(s.gd, 0x2A, 1);  // left shift, deliberately held
        }
    }

    LOG("--- summary ---");
    LOG("scanouts=%d updates=%d cursors=%d mousesets=%d disables=%d",
        s.scanouts, s.updates, s.cursors, s.mousesets, s.disables);
    LOG("last scanout %ux%u; SetUIInfo answered: %s; repaint after key: %s",
        s.w, s.h, s.resized ? "yes" : "no",
        s.repainted_after_key ? "yes" : "no");

    uint64_t close_at = now_ms();
    guest_display_close(s.gd);
    LOG("close took %llu ms (it releases the held shift on the way out)",
        (unsigned long long)(now_ms() - close_at));

    return (s.scanouts > 0 && s.repainted_after_key) ? 0 : 2;
}
