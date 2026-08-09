// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#ifndef WAYLAND_SERVER_INTERNAL_H
#define WAYLAND_SERVER_INTERNAL_H

#include <pthread.h>
#include <stdio.h>
#include <wayland-server.h>
#include "include/wayland_server.h"

/* Buffer type tag — first member of both DmaBufBuffer and ShmBuffer,
 * so surface_commit can distinguish them via a common pointer cast. */
enum WaylandBufferType {
    BUFFER_TYPE_DMABUF = 1,
    BUFFER_TYPE_SHM    = 2,
};

/* Positioner data — stores values set by the client for popup placement. */
struct WaylandPositioner {
    int32_t width, height;                // popup size
    int32_t anchor_x, anchor_y;          // anchor rect position
    int32_t anchor_w, anchor_h;          // anchor rect size
    uint32_t anchor;                      // anchor edge enum
    uint32_t gravity;                     // gravity enum
    int32_t offset_x, offset_y;          // additional offset
};

struct WaylandGeometry {
    int32_t x, y, width, height;
    int set;
};

struct WaylandSurface {
    struct wl_resource* resource;         // wl_surface
    struct wl_resource* xdg_surface;      // xdg_surface (if role assigned)
    struct wl_resource* xdg_toplevel;     // xdg_toplevel (if role assigned)
    struct wl_resource* xdg_popup;        // xdg_popup (if popup role)
    struct wl_resource* decoration;       // zxdg_toplevel_decoration_v1
    uint32_t id;                          // our surface_id for callbacks
    struct wl_list link;                  // in WaylandServer.surfaces
    struct WaylandServer* server;

    // The surface's window sits (at least partly) on an externally sourced
    // output (nv-view.md Stage B): its v4 dmabuf feedback advertises only
    // LINEAR modifiers, so the client re-allocates buffers both GPUs can
    // sample. Toggled from the shell via wayland_server_set_surface_external.
    int external_linear_only;

    // Popup state
    uint32_t parent_surface_id;           // parent surface id (for popups)
    int32_t popup_x, popup_y;            // position relative to parent

    // Subsurface state (wl_subsurface). is_subsurface is set when this surface
    // is turned into a subsurface; subsurface_parent points at the parent
    // WaylandSurface. Used to route a subsurface's committed buffer to its
    // toplevel ancestor's window texture (e.g. Waydroid renders the Android
    // screen to a full-size dma-buf subsurface over a 1x1 dummy toplevel).
    int is_subsurface;
    struct WaylandSurface* subsurface_parent;
    int32_t subsurface_x, subsurface_y;   // position relative to parent
    // The wl_subsurface role object, tracked for exactly one reason: it
    // stores a raw pointer to this surface, and a client may legally destroy
    // the wl_surface while keeping the wl_subsurface alive. Recording it lets
    // surface_destroy_resource() null its user_data instead of leaving it
    // dangling (set_position then wrote through the freed surface).
    struct wl_resource* subsurface_resource;

    // Double-buffered pending state (applied atomically on commit)
    struct {
        struct wl_resource* buffer;
        int buffer_set;
        int32_t damage_x, damage_y, damage_w, damage_h;
        int damage_set;
        struct wl_resource* frame_callback;
        int32_t buffer_scale;           // pending wl_surface.set_buffer_scale
        int buffer_scale_set;
    } pending;
    // Clears pending.buffer if the client destroys the attached wl_buffer
    // before committing it (attach → destroy → commit must not UAF).
    struct wl_listener pending_buffer_destroy_listener;

    // Current committed buffer scale (default 1)
    int32_t buffer_scale;

    // Current committed state
    struct wl_resource* committed_buffer;
    struct wl_listener committed_buffer_destroy_listener;
    struct wl_resource* frame_callback;   // active frame callback waiting for done
    /* Frame-callback throttle (Murmuration): 0 = full rate. While set, the
     * armed callback is held across flips until interval_ms has elapsed
     * since the last done — the client idles between frames. */
    uint32_t frame_throttle_ms;
    uint32_t last_frame_done_ms;
    int first_commit_done;
    int had_role;   // sticky: set once this surface ever had an xdg toplevel/popup
                    // role, stays set after the role is destroyed so we keep
                    // releasing its buffers on unmap.

    /* Dimensions of the last buffer this surface committed for ITSELF (not one
     * routed up from a subsurface). Used to decide whether a subsurface's
     * buffer is the window's actual content — see the routing rule in
     * surface_commit(). Zero until the surface commits its own buffer. */
    int32_t own_buf_w, own_buf_h;

    // Toplevel metadata
    char title[256];
    char app_id[256];

    // Window geometry (from xdg_surface.set_window_geometry, in surface-local coords)
    // Double-buffered: pending is set by client, committed is applied on wl_surface.commit.
    struct WaylandGeometry pending_geometry;
    struct WaylandGeometry geometry;

    // Viewport destination (from wp_viewport.set_destination, surface-local coords)
    // When set, overrides buffer_size/buffer_scale for surface sizing.
    int32_t viewport_dst_width;    // 0 = not set (use buffer dimensions)
    int32_t viewport_dst_height;

    // Fractional scale (wp_fractional_scale_v1)
    struct wl_resource* fractional_scale_resource;

    // Configure tracking
    uint32_t pending_configure_serial;
    int initial_configure_sent;

    // Frame-done throttle timer (fires within wl_event_loop_dispatch)
    struct wl_event_source* frame_done_timer;

    // Outputs this mapped toplevel currently intersects (bit i = server
    // outputs[i]); wl_surface.enter/leave are sent on changes. 0 = unmapped.
    uint32_t outputs_mask;

    // The single output this surface's frame callbacks pace off (a straddler
    // intersects two panels with different refresh rates, and firing on both
    // over-paces the client). One bit; 0 = default to the primary, which is
    // always bit 0 (the shell advertises the primary first).
    uint32_t pace_mask;
};

struct DmaBufBuffer {
    enum WaylandBufferType type;          // = BUFFER_TYPE_DMABUF
    struct wl_resource* resource;         // wl_buffer
    int fd;                               // DMA-BUF file descriptor
    int32_t width, height;
    int32_t stride;
    uint32_t fourcc;
    uint64_t modifier;
};

struct ShmPool {
    int fd;                               // shm file descriptor
    void* data;                           // mmap'd pointer
    size_t size;                          // current pool size
    int refcount;                         // live buffer count + 1 (for the pool resource itself)
};

struct ShmBuffer {
    enum WaylandBufferType type;          // = BUFFER_TYPE_SHM
    struct wl_resource* resource;         // wl_buffer
    struct ShmPool* pool;
    int32_t offset;
    int32_t width, height;
    int32_t stride;
    uint32_t format;                      // wl_shm_format
};

struct WaylandServer {
    struct wl_display* display;
    struct wl_event_loop* event_loop;

    // Globals
    struct wl_global* compositor_global;
    struct wl_global* dmabuf_global;
    struct wl_global* xdg_wm_base_global;
    struct wl_global* seat_global;
    struct wl_global* seat_agent_global;   // Murmuration: the agent seat
    struct WaylandSeatDesc { struct WaylandServer* server; int index; } seat_descs[2];
    // Outputs (virtual desktop): outputs[0] defaults to the create-time
    // config; wayland_server_set_outputs installs the real arrangement.
    // Each bound wl_output resource's user_data is its struct WaylandOutput.
    #define WAYLAND_MAX_OUTPUTS 8
    struct WaylandOutput {
        struct WaylandServer* server;
        int index;
        int32_t logical_x, logical_y;    // global logical position
        int32_t physical_w, physical_h;  // current mode
        int32_t scale;                   // integer scale (>= 1)
        int32_t refresh_mhz;
        char name[32];
        struct wl_global* global;        // NULL = slot unused
        struct wl_list resources;        // bound wl_output resources
    } outputs[WAYLAND_MAX_OUTPUTS];
    int output_count;
    struct wl_global* shm_global;
    struct wl_global* decoration_manager_global;
    struct wl_global* subcompositor_global;
    struct wl_global* data_device_manager_global;
    struct wl_global* fractional_scale_global;
    struct wl_global* viewporter_global;
    struct wl_global* cursor_shape_manager_global;
    struct wl_global* pointer_constraints_global;
    struct wl_global* relative_pointer_manager_global;

    // Relative pointer resources (WaylandRelativePointerResource.link)
    struct wl_list relative_pointers;

    struct wl_global* primary_selection_manager_global;
    struct wl_global* text_input_manager_global;
    // Bound zwp_text_input_v3 resources (TextInputV3.link) + the surface
    // holding keyboard focus for text-input enter/leave routing.
    struct wl_list text_inputs;
    struct WaylandSurface* ti_focus;
    struct wl_global* idle_inhibit_manager_global;
    // Live zwp_idle_inhibitor_v1 resources. Nonzero = some client is
    // playing video (or otherwise asked to stay awake); the shell's idle
    // timer reads it through wayland_server_idle_inhibited().
    int idle_inhibitors;
    struct wl_global* xdg_output_manager_global;
    struct wl_global* xdg_activation_global;
    struct wl_global* presentation_global;

    // Presentation feedback objects (WaylandPresentationFeedback.link)
    struct wl_list presentation_feedbacks;
    uint32_t presentation_seq;

    // Clipboard — unified selection shared across BOTH the focus-based
    // wl_data_device protocol and the focus-free zwlr_data_control protocol,
    // so a copy in any client is pasteable in any other regardless of which
    // protocol set it (Chrome uses wl_data_device; wl-clipboard / the
    // Waydroid clipboard bridge use data-control). `owner` is the current
    // source object (a WaylandDataSource* or WaylandDataControlSource*);
    // `send`/`cancel` dispatch to whichever protocol owns it; `serial` is
    // bumped on every change so an offer minted for an old selection is
    // rejected (EOF) instead of using a stale/freed source.
    struct WaylandClipboard {
        void* owner;                 // NULL = empty selection
        uint64_t serial;             // bumped each set; offers carry it
        char** mimes;                // -> owner's mime array (valid while owner alive)
        int mime_count;
        void (*send)(void* owner, const char* mime, int32_t fd);
        void (*cancel)(void* owner); // notify a displaced owner it lost the selection
    } clipboard;
    struct wl_global* data_control_manager_global;
    // All bound wl_data_device resources (WaylandDataDevice.link, defined in
    // wayland_data_device.c), one per get_data_device call. Entries unlink
    // themselves in their resource destructor — never store a bare
    // wl_data_device pointer here.
    struct wl_list data_device_resources;
    // All bound zwlr_data_control_device_v1 resources (same discipline).
    struct wl_list data_control_devices;

    // Surface list
    struct wl_list surfaces;              // WaylandSurface.link
    uint32_t next_surface_id;

    // Input resources — one per wl_client that called get_pointer/get_keyboard.
    // Chrome opens many connections; we must send events to the right client.
    struct wl_list pointer_resources;  // WaylandInputResource.link
    struct wl_list keyboard_resources; // WaylandInputResource.link

    // Deferred pointer event queue (sent from Flutter thread, drained in dispatch).
    // `lock` guards queue/count/capacity: the enqueue side runs on the Flutter
    // UI thread while the drain runs on the Wayland event-loop thread — the
    // pipe is only a wakeup, not a fence.
    struct {
        pthread_mutex_t lock;
        int pipe_fd[2];                   // pipe for wakeup
        struct wl_event_source* source;   // event loop source for pipe read end
        struct WaylandPointerEvent* queue;
        int count;
        int capacity;
    } deferred_input;

    // Configuration (display parameters only)
    WaylandServerConfig config;
    uint32_t fractional_scale_120ths;  // 0 = derive from config.scale

    // Event-loop thread identity, recorded on the first dispatch. Public
    // entry points that send protocol events directly (configure, flush, …)
    // are only safe on this thread; WARN_IF_OFF_LOOP_THREAD flags misuse.
    pthread_t loop_thread;
    int loop_thread_set;

    // Set once the first real page-flip notification arrives
    // (wayland_server_on_present). While set, the per-surface frame-done
    // timer is only a stall fallback (100ms) — flips drive frame pacing.
    int saw_flip;

    // Callbacks (registered individually via wayland_server_on_* functions)
    // All share a single context pointer for simplicity.
    void* cb_ctx;
    struct {
        void (*on_new_toplevel)(void* ctx, uint32_t surface_id, uint64_t client_id);
        void (*on_title_changed)(void* ctx, uint32_t surface_id, const char* title);
        void (*on_app_id_changed)(void* ctx, uint32_t surface_id, const char* app_id);
        void (*on_toplevel_destroy)(void* ctx, uint32_t surface_id);
        /* A client connection went away. client_id is the same opaque value
         * on_new_toplevel reported — and the ONLY point at which it stops
         * being meaningful, because it is the wl_client pointer: once freed,
         * the allocator can hand the same address to the next client that
         * connects. Anything the shell keyed on it must be dropped here. */
        void (*on_client_destroy)(void* ctx, uint64_t client_id);
        void (*on_surface_commit)(void* ctx, uint32_t surface_id,
                                   int fd, int w, int h, int stride,
                                   uint32_t fourcc, uint64_t modifier,
                                   int first_commit, int buffer_scale);
        void (*on_shm_surface_commit)(void* ctx, uint32_t surface_id,
                                       const void* pixel_data,
                                       int w, int h, int stride,
                                       uint32_t format, int first_commit,
                                       int buffer_scale);
        void (*on_toplevel_resize_request)(void* ctx, uint32_t surface_id,
                                            int w, int h);
        // Client-initiated interactive move/resize (xdg_toplevel.move /
        // xdg_toplevel.resize during a pointer grab — e.g. dragging Chrome's
        // tab strip or a CSD titlebar). The shell takes over the drag.
        void (*on_move_request)(void* ctx, uint32_t surface_id);
        void (*on_interactive_resize_request)(void* ctx, uint32_t surface_id,
                                              uint32_t edges);
        void (*on_new_popup)(void* ctx, uint32_t surface_id,
                              uint32_t parent_surface_id,
                              int x, int y, int w, int h);
        void (*on_popup_destroy)(void* ctx, uint32_t surface_id);
        void (*on_window_geometry)(void* ctx, uint32_t surface_id,
                                    int x, int y, int w, int h);
        void (*on_cursor_shape)(void* ctx, uint32_t shape);
        void (*on_fullscreen_request)(void* ctx, uint32_t surface_id);
        void (*on_unfullscreen_request)(void* ctx, uint32_t surface_id);
        // Text-input-v3 state on the focused surface: fires when a client
        // enables/disables IME input or updates its cursor rectangle
        // (surface-local logical coords).
        void (*on_text_input_state)(void* ctx, uint32_t surface_id,
                                    int enabled, int32_t x, int32_t y,
                                    int32_t w, int32_t h);
    } cb;

    // Socket
    char socket_name[64];
};

// Presentation feedback (one per wp_presentation.feedback request)
struct WaylandPresentationFeedback {
    struct wl_resource* resource;
    uint32_t surface_id;
    struct wl_list link;  // in WaylandServer.presentation_feedbacks
};

// Per-client relative pointer resource
struct WaylandRelativePointerResource {
    struct wl_resource* resource;
    struct wl_list link;  // in WaylandServer.relative_pointers
};

// Per-client input resource (pointer or keyboard)
struct WaylandInputResource {
    struct wl_resource* resource;
    struct wl_list link;  // in WaylandServer.pointer_resources or keyboard_resources
    int seat;             // which wl_seat global this resource was bound from
};

// Deferred input event types
enum WaylandInputEventType {
    WL_PTR_ENTER = 1,
    WL_PTR_LEAVE = 2,
    WL_PTR_MOTION = 3,
    WL_PTR_BUTTON = 4,
    WL_KB_ENTER = 5,
    WL_KB_LEAVE = 6,
    WL_KB_KEY = 7,
    WL_KB_MODIFIERS = 8,
    WL_PTR_AXIS = 9,
    /* Not input: dma-buf modifier demotion marshalled from the raster
     * thread (EGL import failure) onto the loop thread, where the
     * linux-dmabuf feedback re-send is safe. Rides this queue because it
     * is the one cross-thread → loop-thread mechanism (see the
     * WARN_IF_OFF_LOOP_THREAD note below). fourcc in `button`,
     * modifier in `modifier`. */
    WL_DMABUF_DEMOTE = 10,
    /* Not input: per-surface external-output flag flip marshalled from the
     * shell's UI thread. on/off in `state`; re-sends that surface's dmabuf
     * feedback (linear-only when external). */
    WL_SURFACE_EXTERNAL = 11,
};

struct WaylandPointerEvent {
    enum WaylandInputEventType type;
    /* 0 = the human seat, 1 = the agent seat (Murmuration). Delivered only
     * to wl_pointer/wl_keyboard resources bound from the matching seat. */
    int seat;
    uint32_t surface_id;
    uint32_t time_ms;
    double x, y;
    uint32_t button;
    uint32_t state;
    // Keyboard modifier fields (used by WL_KB_KEY and WL_KB_MODIFIERS)
    uint32_t mods_depressed;
    uint32_t mods_latched;
    uint32_t mods_locked;
    uint32_t group;
    // DRM format modifier (used by WL_DMABUF_DEMOTE; fourcc rides in button)
    uint64_t modifier;
};

// Forward declaration for clipboard
struct WaylandDataSource;

// Module init functions (called by wayland_server_create)
void wayland_compositor_init(struct WaylandServer* server);
void wayland_dmabuf_init(struct WaylandServer* server);
/* Loop-thread only (reached via the deferred queue, WL_DMABUF_DEMOTE):
 * drop a modifier from the linux-dmabuf advertisement and re-send v4
 * feedback to every live feedback object so clients re-allocate. */
void wayland_dmabuf_demote_on_loop_thread(struct WaylandServer* server,
                                          uint32_t fourcc, uint64_t modifier);
/* Loop-thread only (reached via the deferred queue, WL_SURFACE_EXTERNAL):
 * flip a surface's external flag and re-send its v4 feedback objects so the
 * client re-allocates with modifiers the external GPU can import. */
void wayland_dmabuf_surface_external_on_loop_thread(struct WaylandServer* server,
                                                    struct WaylandSurface* surface,
                                                    int external);
void wayland_xdg_shell_init(struct WaylandServer* server);
void wayland_seat_init(struct WaylandServer* server);
void wayland_output_init(struct WaylandServer* server);
void wayland_output_send_enter(struct WaylandServer* server,
                               struct WaylandSurface* surface);
void wayland_output_send_leave(struct WaylandServer* server,
                               struct WaylandSurface* surface);
void wayland_shm_init(struct WaylandServer* server);
void wayland_decoration_init(struct WaylandServer* server);
void wayland_subcompositor_init(struct WaylandServer* server);
void wayland_data_device_init(struct WaylandServer* server);
void wayland_data_control_init(struct WaylandServer* server);
/* Unified clipboard: replace the current selection (owner NULL clears it),
 * notify the displaced owner, and broadcast the new offer to every bound
 * wl_data_device AND zwlr_data_control_device. Called by both protocols'
 * set_selection handlers. */
void wayland_clipboard_set(struct WaylandServer* server, void* owner,
                           char** mimes, int mime_count,
                           void (*send)(void* owner, const char* mime, int32_t fd),
                           void (*cancel)(void* owner));
/* Re-send the current selection to all bound devices of each protocol
 * (implemented in the respective file). */
void wayland_data_device_broadcast_selection(struct WaylandServer* server);
void wayland_data_control_broadcast_selection(struct WaylandServer* server);
/* Offer the current selection to a client that is starting to interact with a
 * surface, if it has not already been told about this selection. Without it a
 * client never sees a selection that predates it. Called from the pointer- and
 * keyboard-enter paths; cheap (serial-guarded) and a no-op when empty. */
void wayland_data_device_offer_on_interaction(struct WaylandServer* server,
                                              struct WaylandSurface* surface);
void wayland_fractional_scale_init(struct WaylandServer* server);
void wayland_viewporter_init(struct WaylandServer* server);
void wayland_cursor_shape_init(struct WaylandServer* server);
void wayland_pointer_constraints_init(struct WaylandServer* server);
void wayland_relative_pointer_init(struct WaylandServer* server);
void wayland_primary_selection_init(struct WaylandServer* server);
void wayland_text_input_init(struct WaylandServer* server);
void wayland_text_input_focus_enter(struct WaylandServer* server,
                                    struct WaylandSurface* surface);
void wayland_text_input_focus_leave(struct WaylandServer* server,
                                    struct WaylandSurface* surface);
void wayland_text_input_surface_destroyed(struct WaylandServer* server,
                                          struct WaylandSurface* surface);
void wayland_idle_inhibit_init(struct WaylandServer* server);
void wayland_xdg_output_init(struct WaylandServer* server);
void wayland_xdg_activation_init(struct WaylandServer* server);
void wayland_presentation_init(struct WaylandServer* server);

// Warn (once per call site) when a loop-thread-only function runs on another
// thread. libwayland-server send/marshal paths are not thread-safe; calling
// them off the event-loop thread corrupts the client connection. This is a
// diagnostic, not a fix — route new cross-thread work through the deferred
// input queue or the Swift command queue instead.
#define WARN_IF_OFF_LOOP_THREAD(server, what)                                 \
    do {                                                                      \
        if ((server)->loop_thread_set &&                                      \
            !pthread_equal(pthread_self(), (server)->loop_thread)) {          \
            static int warned_;                                               \
            if (!warned_) {                                                   \
                warned_ = 1;                                                  \
                fprintf(stderr, "[WaylandServer] WARNING: %s called off the " \
                        "event-loop thread (unsafe)\n", what);                \
            }                                                                 \
        }                                                                     \
    } while (0)

// Helpers
uint32_t wayland_server_next_serial(struct WaylandServer* server);
struct WaylandSurface* wayland_server_find_surface(struct WaylandServer* server, uint32_t surface_id);

// Send `discarded` to (and destroy) all pending wp_presentation feedback
// objects for a surface — called when the surface is destroyed so feedbacks
// don't linger until client disconnect.
void wayland_server_presentation_discard(struct WaylandServer* server,
                                         uint32_t surface_id);

// Answer pending wp_presentation feedbacks paced by the flipping output
// (surface pace_mask; 0 = primary = bit 0) with a real scanout timestamp +
// that output's refresh period (flip-driven path). Event-loop thread only.
void wayland_server_presentation_present_all(struct WaylandServer* server,
                                             uint64_t flip_time_ns,
                                             uint32_t refresh_ns,
                                             uint32_t flip_output_mask);

#endif
