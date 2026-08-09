// Hostile-buffer client: commit a dma-buf whose modifier the compositor
// cannot import, and keep the connection alive. Stands in for the real
// incident (2026-08-08): Chromium, steered to the NVIDIA main_device,
// committed an NVIDIA-tiled buffer (modifier 0x300000000606014); the
// compositor's eglCreateImageKHR correctly refused it — and the shell then
// died of an amdgpu CS rejection. A failed import must cost the client its
// window content, never the compositor its life.
//
// The bo itself is an ordinary LINEAR allocation on the given render node
// (default /dev/dri/renderD129); only the ADVERTISED modifier lies. That is
// exactly what the import path sees either way — it never dereferences the
// pixels, it hands fd+modifier to EGL and EGL says no.
//
// Built on the fly by test/functional.py (wayland-scanner + cc), like
// idle-inhibit-client.c. "bad buffer committed" on stdout is the handshake;
// the process then dispatches until killed.
#include <fcntl.h>
#include <gbm.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wayland-client.h>
#include "linux-dmabuf-unstable-v1-client-protocol.h"
#include "xdg-shell-client-protocol.h"

static struct wl_compositor *compositor;
static struct zwp_linux_dmabuf_v1 *dmabuf;
static struct xdg_wm_base *wm_base;
static int configured = 0;

static void handle_global(void *data, struct wl_registry *reg, uint32_t name,
                          const char *iface, uint32_t version) {
    (void)data;
    if (!strcmp(iface, "wl_compositor")) {
        compositor = wl_registry_bind(reg, name, &wl_compositor_interface, 1);
    } else if (!strcmp(iface, "zwp_linux_dmabuf_v1")) {
        uint32_t v = version < 3 ? version : 3;
        dmabuf = wl_registry_bind(reg, name, &zwp_linux_dmabuf_v1_interface, v);
    } else if (!strcmp(iface, "xdg_wm_base")) {
        wm_base = wl_registry_bind(reg, name, &xdg_wm_base_interface, 1);
    }
}
static void handle_global_remove(void *d, struct wl_registry *r, uint32_t n) {
    (void)d; (void)r; (void)n;
}
static const struct wl_registry_listener registry_listener = {
    handle_global, handle_global_remove,
};

static void wm_ping(void *d, struct xdg_wm_base *wm, uint32_t serial) {
    (void)d;
    xdg_wm_base_pong(wm, serial);
}
static const struct xdg_wm_base_listener wm_listener = { wm_ping };

static void surf_configure(void *d, struct xdg_surface *s, uint32_t serial) {
    (void)d;
    xdg_surface_ack_configure(s, serial);
    configured = 1;
}
static const struct xdg_surface_listener surf_listener = { surf_configure };

static void top_configure(void *d, struct xdg_toplevel *t, int32_t w,
                          int32_t h, struct wl_array *states) {
    (void)d; (void)t; (void)w; (void)h; (void)states;
}
static void top_close(void *d, struct xdg_toplevel *t) {
    (void)d; (void)t;
    exit(0);
}
static const struct xdg_toplevel_listener top_listener = {
    top_configure, top_close,
};

int main(int argc, char **argv) {
    // The incident's modifier: NVIDIA-vendored (0x03 in bits 56-63), which
    // no AMD (or virgl) EGL will ever import. Overridable for future
    // incidents.
    uint64_t modifier = 0x300000000606014ull;
    if (argc > 2) modifier = strtoull(argv[2], NULL, 0);

    // Full-screen-sized and CYCLING, like the Chromium incident: a window's
    // first paint arrives as a rotation of large buffers, every one of them
    // failing to import, frame after frame.
    enum { NBUF = 4, W = 3840, H = 2020 };
    // Any render node that allocates will do — the modifier lies either
    // way. The dev box has two, the VM one.
    int drm = -1;
    if (argc > 1) {
        drm = open(argv[1], O_RDWR | O_CLOEXEC);
    } else {
        for (int i = 128; i < 136 && drm < 0; i++) {
            char node[32];
            snprintf(node, sizeof(node), "/dev/dri/renderD%d", i);
            drm = open(node, O_RDWR | O_CLOEXEC);
        }
    }
    if (drm < 0) { fprintf(stderr, "no render node opened\n"); return 1; }
    struct gbm_device *gbm = gbm_create_device(drm);
    if (!gbm) { fprintf(stderr, "gbm_create_device failed\n"); return 1; }
    int fds[NBUF];
    uint32_t strides[NBUF];
    for (int i = 0; i < NBUF; i++) {
        struct gbm_bo *bo = gbm_bo_create(gbm, W, H, GBM_FORMAT_XRGB8888,
                                          GBM_BO_USE_LINEAR);
        if (!bo) { fprintf(stderr, "gbm_bo_create failed\n"); return 1; }
        fds[i] = gbm_bo_get_fd(bo);
        strides[i] = gbm_bo_get_stride(bo);
        if (fds[i] < 0) { fprintf(stderr, "gbm_bo_get_fd failed\n"); return 1; }
    }

    struct wl_display *display = wl_display_connect(NULL);
    if (!display) { fprintf(stderr, "no display\n"); return 2; }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);
    if (!compositor || !dmabuf || !wm_base) {
        fprintf(stderr, "missing globals\n");
        return 3;
    }
    xdg_wm_base_add_listener(wm_base, &wm_listener, NULL);

    struct wl_surface *surface = wl_compositor_create_surface(compositor);
    struct xdg_surface *xsurf = xdg_wm_base_get_xdg_surface(wm_base, surface);
    xdg_surface_add_listener(xsurf, &surf_listener, NULL);
    struct xdg_toplevel *top = xdg_surface_get_toplevel(xsurf);
    xdg_toplevel_add_listener(top, &top_listener, NULL);
    xdg_toplevel_set_title(top, "bad-dmabuf");
    wl_surface_commit(surface);
    while (!configured && wl_display_dispatch(display) != -1) { }

    struct wl_buffer *buffers[NBUF];
    for (int i = 0; i < NBUF; i++) {
        struct zwp_linux_buffer_params_v1 *params =
            zwp_linux_dmabuf_v1_create_params(dmabuf);
        zwp_linux_buffer_params_v1_add(params, fds[i], 0, 0, strides[i],
                                       (uint32_t)(modifier >> 32),
                                       (uint32_t)(modifier & 0xffffffff));
        buffers[i] = zwp_linux_buffer_params_v1_create_immed(
            params, W, H, GBM_FORMAT_XRGB8888, 0);
        zwp_linux_buffer_params_v1_destroy(params);
    }

    wl_surface_attach(surface, buffers[0], 0, 0);
    wl_surface_damage(surface, 0, 0, W, H);
    wl_surface_commit(surface);
    wl_display_roundtrip(display);

    printf("bad buffer committed\n");
    fflush(stdout);

    // ~60fps of rotating unimportable buffers until killed. Every commit is
    // a fresh import attempt on the compositor's raster thread.
    for (int frame = 1;; frame++) {
        usleep(16000);
        wl_surface_attach(surface, buffers[frame % NBUF], 0, 0);
        wl_surface_damage(surface, 0, 0, W, H);
        wl_surface_commit(surface);
        if (wl_display_roundtrip(display) < 0) break;
    }
    return 0;
}
