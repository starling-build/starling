// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/*
 * wayland_dmabuf.c — zwp_linux_dmabuf_v1 and zwp_linux_buffer_params_v1
 *
 * Implements DMA-BUF buffer import for the Wayland server.
 * Supports single-plane buffers with ARGB8888/XRGB8888/ABGR8888/XBGR8888 formats.
 */

#define _GNU_SOURCE  /* memfd_create */
#include "wayland_server_internal.h"
#include <wayland-server-protocol.h>
#include "linux-dmabuf-unstable-v1-protocol.h"
#include <dirent.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

/* DRM fourcc format codes — define if drm_fourcc.h is not available */
#ifndef DRM_FORMAT_ARGB8888
#define DRM_FORMAT_ARGB8888 0x34325241
#define DRM_FORMAT_XRGB8888 0x34325258
#define DRM_FORMAT_ABGR8888 0x34324241
#define DRM_FORMAT_XBGR8888 0x34324258
#endif
#ifndef DRM_FORMAT_MOD_LINEAR
#define DRM_FORMAT_MOD_LINEAR 0ULL
#define DRM_FORMAT_MOD_INVALID ((1ULL << 56) - 1)
#endif

/* ------------------------------------------------------------------ */
/* Internal struct for buffer params (temporary, used during creation) */
/* ------------------------------------------------------------------ */

struct DmaBufParams {
    struct WaylandServer* server;
    int fd;           /* DMA-BUF fd for plane 0 */
    int32_t offset;
    int32_t stride;
    uint64_t modifier;
    int has_plane;    /* whether add() was called at least once */
};

/* ------------------------------------------------------------------ */
/* wl_buffer interface (destroy only)                                  */
/* ------------------------------------------------------------------ */

static void buffer_destroy_request(struct wl_client* client,
                                   struct wl_resource* resource) {
    wl_resource_destroy(resource);
}

static const struct wl_buffer_interface buffer_impl = {
    .destroy = buffer_destroy_request,
};

static void buffer_destroy(struct wl_resource* resource) {
    struct DmaBufBuffer* buf = wl_resource_get_user_data(resource);
    if (buf) {
        if (buf->fd >= 0)
            close(buf->fd);
        free(buf);
    }
}

/* ------------------------------------------------------------------ */
/* zwp_linux_buffer_params_v1 implementation                           */
/* ------------------------------------------------------------------ */

static void params_destroy(struct wl_client* client,
                           struct wl_resource* resource) {
    wl_resource_destroy(resource);
}

static void params_add(struct wl_client* client, struct wl_resource* resource,
                       int32_t fd, uint32_t plane_idx, uint32_t offset,
                       uint32_t stride, uint32_t modifier_hi,
                       uint32_t modifier_lo) {
    struct DmaBufParams* params = wl_resource_get_user_data(resource);

    if (plane_idx == 0) {
        /* Re-adding plane 0 replaces the previous fd — don't leak it. */
        if (params->fd >= 0)
            close(params->fd);
        params->fd = fd;
        params->offset = (int32_t)offset;
        params->stride = (int32_t)stride;
        params->modifier = ((uint64_t)modifier_hi << 32) | modifier_lo;
        params->has_plane = 1;
    } else {
        /* We only support single-plane for now, close extra fds */
        close(fd);
    }
}

static void params_create(struct wl_client* client,
                           struct wl_resource* resource,
                           int32_t width, int32_t height,
                           uint32_t format, uint32_t flags) {
    struct DmaBufParams* params = wl_resource_get_user_data(resource);

    if (!params->has_plane) {
        zwp_linux_buffer_params_v1_send_failed(resource);
        return;
    }

    struct DmaBufBuffer* buf = calloc(1, sizeof(struct DmaBufBuffer));
    if (!buf) {
        zwp_linux_buffer_params_v1_send_failed(resource);
        return;
    }

    buf->type = BUFFER_TYPE_DMABUF;
    buf->fd = params->fd;
    buf->width = width;
    buf->height = height;
    buf->stride = params->stride;
    buf->fourcc = format;
    buf->modifier = params->modifier;

    /* Create wl_buffer resource (id=0 means server allocates) */
    struct wl_resource* buffer_resource = wl_resource_create(client,
        &wl_buffer_interface, 1, 0);
    if (!buffer_resource) {
        close(buf->fd);
        params->fd = -1;  /* already closed — params destructor must not double-close */
        free(buf);
        zwp_linux_buffer_params_v1_send_failed(resource);
        return;
    }

    wl_resource_set_implementation(buffer_resource, &buffer_impl, buf,
                                   buffer_destroy);
    buf->resource = buffer_resource;

    /* Don't close fd — it's owned by the buffer now */
    params->fd = -1;

    zwp_linux_buffer_params_v1_send_created(resource, buffer_resource);
}

static void params_create_immed(struct wl_client* client,
                                struct wl_resource* resource,
                                uint32_t buffer_id,
                                int32_t width, int32_t height,
                                uint32_t format, uint32_t flags) {
    struct DmaBufParams* params = wl_resource_get_user_data(resource);

    if (!params->has_plane) {
        wl_resource_post_error(resource,
            ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_INVALID_WL_BUFFER,
            "no planes added");
        return;
    }

    struct DmaBufBuffer* buf = calloc(1, sizeof(struct DmaBufBuffer));
    if (!buf) {
        wl_resource_post_error(resource,
            ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_INVALID_WL_BUFFER,
            "out of memory");
        return;
    }

    buf->type = BUFFER_TYPE_DMABUF;
    buf->fd = params->fd;
    buf->width = width;
    buf->height = height;
    buf->stride = params->stride;
    buf->fourcc = format;
    buf->modifier = params->modifier;

    struct wl_resource* buffer_resource = wl_resource_create(client,
        &wl_buffer_interface, 1, buffer_id);
    if (!buffer_resource) {
        close(buf->fd);
        params->fd = -1;  /* already closed — params destructor must not double-close */
        free(buf);
        wl_resource_post_no_memory(resource);
        return;
    }

    wl_resource_set_implementation(buffer_resource, &buffer_impl, buf,
                                   buffer_destroy);
    buf->resource = buffer_resource;

    /* Don't close fd — it's owned by the buffer now */
    params->fd = -1;
}

static const struct zwp_linux_buffer_params_v1_interface params_impl = {
    .destroy = params_destroy,
    .add = params_add,
    .create = params_create,
    .create_immed = params_create_immed,
};

static void params_resource_destroy(struct wl_resource* resource) {
    struct DmaBufParams* params = wl_resource_get_user_data(resource);
    if (params) {
        if (params->fd >= 0)
            close(params->fd);
        free(params);
    }
}

/* ------------------------------------------------------------------ */
/* zwp_linux_dmabuf_v1 implementation                                  */
/* ------------------------------------------------------------------ */

static void dmabuf_destroy(struct wl_client* client,
                           struct wl_resource* resource) {
    wl_resource_destroy(resource);
}

static void dmabuf_create_params(struct wl_client* client,
                                  struct wl_resource* resource,
                                  uint32_t params_id) {
    struct WaylandServer* server = wl_resource_get_user_data(resource);

    struct DmaBufParams* params = calloc(1, sizeof(struct DmaBufParams));
    if (!params) {
        wl_resource_post_no_memory(resource);
        return;
    }

    params->server = server;
    params->fd = -1;
    params->has_plane = 0;

    struct wl_resource* params_resource = wl_resource_create(client,
        &zwp_linux_buffer_params_v1_interface,
        wl_resource_get_version(resource), params_id);
    if (!params_resource) {
        free(params);
        wl_resource_post_no_memory(resource);
        return;
    }

    wl_resource_set_implementation(params_resource, &params_impl, params,
                                   params_resource_destroy);
}

/* ------------------------------------------------------------------ */
/* zwp_linux_dmabuf_feedback_v1 (v4) — device + format-table feedback  */
/*                                                                     */
/* Without this (or the legacy wl_drm global), Mesa's Wayland platform */
/* has no way to discover which DRM device the compositor uses and     */
/* silently falls back to llvmpipe — sandboxed clients bringing their  */
/* own Mesa get software rendering. The feedback carries the render    */
/* node's dev_t plus a format+modifier table the client mmaps.         */
/* ------------------------------------------------------------------ */

/* The format table mirrors the v3 modifier advertisement. */
struct FeedbackTableEntry {
    uint32_t format;
    uint32_t padding;
    uint64_t modifier;
};

/* Advertised (format, modifier) pairs. Defaults cover the formats the
 * compositor's import path handles with LINEAR + implicit modifiers;
 * wayland_server_set_dmabuf_formats replaces them with the real list
 * queried from EGL. */
#define DMABUF_MAX_ADVERTISED 128

static uint32_t adv_formats[DMABUF_MAX_ADVERTISED];
static uint64_t adv_modifiers[DMABUF_MAX_ADVERTISED];
static int adv_count = 0;

static int feedback_table_fd = -1;
static uint32_t feedback_table_size = 0;
static dev_t feedback_main_device = 0;

/* Live feedback objects, so a runtime demotion can re-send feedback and
 * make clients re-allocate. Lazily initialized (wl_list zero state has
 * next == NULL). */
struct FeedbackResource {
    struct wl_resource* resource;
    struct wl_list link;
};
static struct wl_list feedback_resources;

static void ensure_feedback_list(void) {
    if (!feedback_resources.next) wl_list_init(&feedback_resources);
}

static void ensure_default_formats(void) {
    if (adv_count > 0) return;
    static const uint32_t defaults[] = {
        DRM_FORMAT_ARGB8888, DRM_FORMAT_XRGB8888,
        DRM_FORMAT_ABGR8888, DRM_FORMAT_XBGR8888,
    };
    const int n = (int)(sizeof(defaults) / sizeof(defaults[0]));
    for (int i = 0; i < n; i++) {
        adv_formats[i] = defaults[i];
        adv_modifiers[i] = DRM_FORMAT_MOD_LINEAR;
        adv_formats[n + i] = defaults[i];
        adv_modifiers[n + i] = DRM_FORMAT_MOD_INVALID;
    }
    adv_count = n * 2;
}

void wayland_server_set_dmabuf_formats(struct WaylandServer* server,
                                       const uint32_t* formats,
                                       const uint64_t* modifiers,
                                       int count) {
    (void)server;
    if (!formats || !modifiers || count <= 0) return;
    if (count > DMABUF_MAX_ADVERTISED) count = DMABUF_MAX_ADVERTISED;
    memcpy(adv_formats, formats, (size_t)count * sizeof(uint32_t));
    memcpy(adv_modifiers, modifiers, (size_t)count * sizeof(uint64_t));
    adv_count = count;
    /* Invalidate the feedback table so new feedback objects rebuild it. */
    if (feedback_table_fd >= 0) {
        close(feedback_table_fd);
        feedback_table_fd = -1;
        feedback_table_size = 0;
    }
}

/* Is (fourcc, modifier) one the compositor advertised as importable? The
 * import path asks BEFORE handing a buffer to eglCreateImageKHR: a modifier
 * we never advertised (a foreign GPU's tiled layout — a PRIME-offloaded
 * client that allocated on the wrong device, or a hostile client) can make
 * the AMD driver allocate to interpret the layout and only then fail, which
 * under GPU-memory pressure aborts the shell with an amdgpu CS rejection
 * (-12). LINEAR and the implicit modifier are always importable — they are
 * the universal fallbacks and the child-app path's only layouts. */
int wayland_server_dmabuf_modifier_importable(uint32_t fourcc,
                                              uint64_t modifier) {
    if (modifier == DRM_FORMAT_MOD_LINEAR ||
        modifier == DRM_FORMAT_MOD_INVALID) {
        return 1;
    }
    ensure_default_formats();
    for (int i = 0; i < adv_count; i++) {
        if (adv_formats[i] == fourcc && adv_modifiers[i] == modifier) {
            return 1;
        }
    }
    return 0;
}

static void send_feedback(struct wl_resource* feedback);

/* The import path found out the hard way that this modifier doesn't
 * import (zink's modifier query over-reports; the EGLImage creation is
 * ground truth). Drop it — for every format; a layout the EGL can't
 * texture from won't start working for a different fourcc — and re-send
 * feedback so v4 clients (Chrome) re-allocate from the reduced table.
 * LINEAR and the implicit modifier are the floor and never demoted.
 * Loop-thread only: reached via the deferred queue (WL_DMABUF_DEMOTE). */
void wayland_dmabuf_demote_on_loop_thread(struct WaylandServer* server,
                                          uint32_t fourcc, uint64_t modifier) {
    (void)server;
    (void)fourcc;
    if (modifier == DRM_FORMAT_MOD_LINEAR || modifier == DRM_FORMAT_MOD_INVALID)
        return;

    int kept = 0, removed = 0;
    for (int i = 0; i < adv_count; i++) {
        if (adv_modifiers[i] == modifier) {
            removed++;
            continue;
        }
        adv_formats[kept] = adv_formats[i];
        adv_modifiers[kept] = adv_modifiers[i];
        kept++;
    }
    if (!removed) return;  /* already demoted — idempotent */
    adv_count = kept;

    if (feedback_table_fd >= 0) {
        close(feedback_table_fd);
        feedback_table_fd = -1;
        feedback_table_size = 0;
    }

    fprintf(stderr,
            "[wayland_dmabuf] demoted modifier 0x%llx (%d pairs) after EGL "
            "import failure; re-sending feedback\n",
            (unsigned long long)modifier, removed);

    ensure_feedback_list();
    struct FeedbackResource* fr;
    wl_list_for_each(fr, &feedback_resources, link) {
        send_feedback(fr->resource);
    }
}

/* Resolve the render node matching the card the shell renders on
 * (FLUTTER_DRM_DEVICE, e.g. /dev/dri/card1) by comparing the sysfs
 * device links; falls back to the first available render node. */
static dev_t find_render_node_devid(void) {
    char card_link[512] = {0};
    const char* card_path = getenv("FLUTTER_DRM_DEVICE");
    if (card_path) {
        const char* card_name = strrchr(card_path, '/');
        if (card_name) {
            char sys_path[256];
            snprintf(sys_path, sizeof(sys_path), "/sys/class/drm/%s/device",
                     card_name + 1);
            ssize_t n = readlink(sys_path, card_link, sizeof(card_link) - 1);
            if (n < 0) card_link[0] = '\0';
        }
    }

    dev_t fallback = 0;
    for (int i = 128; i < 136; i++) {
        char dev_path[64];
        snprintf(dev_path, sizeof(dev_path), "/dev/dri/renderD%d", i);
        struct stat st;
        if (stat(dev_path, &st) != 0) continue;
        if (fallback == 0) fallback = st.st_rdev;
        if (card_link[0]) {
            char sys_path[256];
            char render_link[512] = {0};
            snprintf(sys_path, sizeof(sys_path),
                     "/sys/class/drm/renderD%d/device", i);
            ssize_t n = readlink(sys_path, render_link, sizeof(render_link) - 1);
            if (n > 0 && strcmp(render_link, card_link) == 0) {
                return st.st_rdev;
            }
        }
    }
    return fallback;
}

/* Build the format-table memfd once (shared by every feedback object;
 * rebuilt after wayland_server_set_dmabuf_formats). */
static void ensure_feedback_table(void) {
    if (feedback_table_fd >= 0) return;

    ensure_default_formats();
    struct FeedbackTableEntry entries[DMABUF_MAX_ADVERTISED];
    memset(entries, 0, sizeof(entries));
    for (int i = 0; i < adv_count; i++) {
        entries[i].format = adv_formats[i];
        entries[i].modifier = adv_modifiers[i];
    }
    const size_t table_bytes = (size_t)adv_count * sizeof(struct FeedbackTableEntry);

    int fd = memfd_create("starling-dmabuf-feedback", MFD_CLOEXEC | MFD_ALLOW_SEALING);
    if (fd < 0) return;
    if (write(fd, entries, table_bytes) != (ssize_t)table_bytes) {
        close(fd);
        return;
    }
#ifdef F_ADD_SEALS
    fcntl(fd, F_ADD_SEALS, F_SEAL_SHRINK | F_SEAL_GROW | F_SEAL_WRITE | F_SEAL_SEAL);
#endif
    feedback_table_fd = fd;
    feedback_table_size = (uint32_t)table_bytes;
    feedback_main_device = find_render_node_devid();
}

static void feedback_destroy(struct wl_client* client,
                             struct wl_resource* resource) {
    wl_resource_destroy(resource);
}

static const struct zwp_linux_dmabuf_feedback_v1_interface feedback_impl = {
    .destroy = feedback_destroy,
};

static void send_feedback(struct wl_resource* feedback) {
    ensure_feedback_table();
    if (feedback_table_fd < 0 || feedback_main_device == 0) {
        /* No render node — send an empty done so the client can fall back. */
        zwp_linux_dmabuf_feedback_v1_send_done(feedback);
        return;
    }

    zwp_linux_dmabuf_feedback_v1_send_format_table(
        feedback, feedback_table_fd, feedback_table_size);

    struct wl_array device;
    wl_array_init(&device);
    dev_t* dev = wl_array_add(&device, sizeof(dev_t));
    *dev = feedback_main_device;
    zwp_linux_dmabuf_feedback_v1_send_main_device(feedback, &device);

    /* Single tranche: every table entry, targeting the main device. */
    zwp_linux_dmabuf_feedback_v1_send_tranche_target_device(feedback, &device);
    zwp_linux_dmabuf_feedback_v1_send_tranche_flags(feedback, 0);

    struct wl_array indices;
    wl_array_init(&indices);
    const size_t nentries = feedback_table_size / sizeof(struct FeedbackTableEntry);
    for (uint16_t i = 0; i < nentries; i++) {
        uint16_t* idx = wl_array_add(&indices, sizeof(uint16_t));
        *idx = i;
    }
    zwp_linux_dmabuf_feedback_v1_send_tranche_formats(feedback, &indices);
    zwp_linux_dmabuf_feedback_v1_send_tranche_done(feedback);
    zwp_linux_dmabuf_feedback_v1_send_done(feedback);

    wl_array_release(&indices);
    wl_array_release(&device);
}

static void feedback_resource_destroy(struct wl_resource* resource) {
    struct FeedbackResource* fr = wl_resource_get_user_data(resource);
    if (fr) {
        wl_list_remove(&fr->link);
        free(fr);
    }
}

static void dmabuf_get_feedback_common(struct wl_client* client,
                                       struct wl_resource* resource,
                                       uint32_t id) {
    struct wl_resource* feedback = wl_resource_create(client,
        &zwp_linux_dmabuf_feedback_v1_interface,
        wl_resource_get_version(resource), id);
    if (!feedback) {
        wl_resource_post_no_memory(resource);
        return;
    }
    /* Track it so a runtime modifier demotion can re-send feedback. */
    ensure_feedback_list();
    struct FeedbackResource* fr = calloc(1, sizeof(*fr));
    if (fr) {
        fr->resource = feedback;
        wl_list_insert(&feedback_resources, &fr->link);
    }
    wl_resource_set_implementation(feedback, &feedback_impl, fr,
                                   feedback_resource_destroy);
    send_feedback(feedback);
}

static void dmabuf_get_default_feedback(struct wl_client* client,
                                        struct wl_resource* resource,
                                        uint32_t id) {
    dmabuf_get_feedback_common(client, resource, id);
}

static void dmabuf_get_surface_feedback(struct wl_client* client,
                                        struct wl_resource* resource,
                                        uint32_t id,
                                        struct wl_resource* surface) {
    (void)surface;  /* same feedback for every surface */
    dmabuf_get_feedback_common(client, resource, id);
}

static const struct zwp_linux_dmabuf_v1_interface dmabuf_impl = {
    .destroy = dmabuf_destroy,
    .create_params = dmabuf_create_params,
    .get_default_feedback = dmabuf_get_default_feedback,
    .get_surface_feedback = dmabuf_get_surface_feedback,
};

/* ------------------------------------------------------------------ */
/* Bind callback — advertise supported formats                         */
/* ------------------------------------------------------------------ */

static void dmabuf_bind(struct wl_client* client, void* data,
                        uint32_t version, uint32_t id) {
    struct wl_resource* resource = wl_resource_create(client,
        &zwp_linux_dmabuf_v1_interface, version, id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }

    wl_resource_set_implementation(resource, &dmabuf_impl, data, NULL);

    /* Advertise supported formats. v4+ clients use the feedback object
     * instead (format/modifier events are deprecated from v4). */
    if (version >= 4) {
        return;
    }

    ensure_default_formats();
    if (version == 3) {
        /* Version 3: send format+modifier pairs */
        for (int i = 0; i < adv_count; i++) {
            zwp_linux_dmabuf_v1_send_modifier(resource, adv_formats[i],
                (uint32_t)(adv_modifiers[i] >> 32),
                (uint32_t)(adv_modifiers[i] & 0xFFFFFFFF));
        }
    } else {
        /* Version 1-2: just send format events (dedup across modifiers) */
        for (int i = 0; i < adv_count; i++) {
            int seen = 0;
            for (int j = 0; j < i; j++) {
                if (adv_formats[j] == adv_formats[i]) { seen = 1; break; }
            }
            if (!seen) {
                zwp_linux_dmabuf_v1_send_format(resource, adv_formats[i]);
            }
        }
    }
}

/* ------------------------------------------------------------------ */
/* Public init function                                                */
/* ------------------------------------------------------------------ */

void wayland_dmabuf_init(struct WaylandServer* server) {
    server->dmabuf_global = wl_global_create(server->display,
        &zwp_linux_dmabuf_v1_interface, 4, server, dmabuf_bind);
}
