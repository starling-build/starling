// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#ifndef FLUTTER_WAYLAND_SERVER_H
#define FLUTTER_WAYLAND_SERVER_H

#include <stdint.h>
#include <sys/types.h>   /* pid_t — wayland_server_surface_pid */

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque server handle */
typedef struct WaylandServer WaylandServer;

/* --------------------------------------------------------------------------
 * Configuration (display parameters only — no callbacks)
 * -------------------------------------------------------------------------- */

typedef struct WaylandServerConfig {
    int      display_width;
    int      display_height;
    int      refresh_mhz;       /* Display refresh rate in milli-Hz (e.g. 60000) */
    int      scale;             /* Output scale factor (default 1, use 2 for HiDPI) */
} WaylandServerConfig;

/* --------------------------------------------------------------------------
 * Lifecycle
 * -------------------------------------------------------------------------- */

/* Create a Wayland server. Returns NULL on failure. */
WaylandServer* wayland_server_create(const WaylandServerConfig* config);

/* Destroy the server and free all resources. */
void wayland_server_destroy(WaylandServer* server);

/* --------------------------------------------------------------------------
 * Multi-output (virtual desktop)
 * -------------------------------------------------------------------------- */

/* One output in the virtual desktop, in the same arrangement the shell's
 * DisplayLayout uses: a rect in global LOGICAL coordinates + the mode. */
typedef struct {
    int32_t logical_x;    /* position in the global logical space */
    int32_t logical_y;
    int32_t physical_w;   /* current mode, device pixels */
    int32_t physical_h;
    int32_t scale;        /* integer scale (>= 1) */
    int32_t refresh_mhz;
    char    name[32];     /* connector name, e.g. "HDMI-A-1" */
} WaylandOutputDesc;

/* Replace the advertised output set. Until called, the server advertises a
 * single output built from the create-time config. New outputs get their own
 * wl_output globals (existing clients learn of them via the registry);
 * changed ones re-send geometry/mode/scale/done to bound resources. Shrinking
 * the set is not supported yet (hotplug-remove comes with P4). */
void wayland_server_set_outputs(WaylandServer* server,
                                const WaylandOutputDesc* outputs, int count);

/* Set the outputs a mapped toplevel currently intersects (bit i = output i
 * of the set_outputs array). The server diffs against the previous mask and
 * sends wl_surface.enter/leave. Freshly mapped surfaces default to bit 0.
 * `pace_mask` is the ONE output whose flips drive this surface's frame
 * callbacks and presentation feedback — the output it mostly sits on. A
 * straddler intersects two panels with different refresh rates; firing its
 * callbacks on both would over-pace the client. 0 = pace off the primary
 * (bit 0 — the shell advertises the primary first). */
void wayland_server_surface_set_outputs(WaylandServer* server,
                                        uint32_t surface_id, uint32_t mask,
                                        uint32_t pace_mask);

/* Agent seat (Murmuration): broker-injected input delivered on a second
 * wl_seat with its own focus stream — never disturbs the human seat. */
void wayland_server_agent_pointer_enter(WaylandServer* server,
                                        uint32_t surface_id, double x, double y);
void wayland_server_agent_pointer_motion(WaylandServer* server,
                                         uint32_t surface_id, uint32_t time_ms,
                                         double x, double y);
void wayland_server_agent_pointer_button(WaylandServer* server,
                                         uint32_t surface_id, uint32_t time_ms,
                                         uint32_t button, uint32_t state);
void wayland_server_agent_pointer_axis(WaylandServer* server,
                                       uint32_t surface_id, uint32_t time_ms,
                                       double axis_x, double axis_y);
void wayland_server_agent_keyboard_enter(WaylandServer* server,
                                         uint32_t surface_id);
void wayland_server_agent_keyboard_key(WaylandServer* server,
                                       uint32_t surface_id, uint32_t time_ms,
                                       uint32_t key, uint32_t state);

/* Frame-callback throttle for tile-only agent windows (Murmuration):
 * interval_ms = 0 restores full rate. */
void wayland_server_set_surface_throttle(WaylandServer* server,
                                         uint32_t surface_id,
                                         uint32_t interval_ms);

/* --------------------------------------------------------------------------
 * Callback registration — events from Wayland clients to the compositor
 *
 * Each callback is registered individually via a setter function.
 * This avoids struct layout issues when adding new callbacks.
 * All callbacks are optional. Pass NULL to unregister.
 * -------------------------------------------------------------------------- */

/* client_id identifies the wl_client connection — the shell uses it to
 * attribute every toplevel a client maps to the agent that launched it.
 *
 * Stable for the connection's lifetime and NOT beyond it: the value is the
 * client pointer, so after the client disconnects the same value can be
 * handed to an unrelated one. Anything keyed on it must be dropped in
 * on_client_destroy, or a later client inherits the earlier one's identity. */
void wayland_server_on_new_toplevel(WaylandServer* server,
    void (*cb)(void* ctx, uint32_t surface_id, uint64_t client_id), void* ctx);

void wayland_server_on_title_changed(WaylandServer* server,
    void (*cb)(void* ctx, uint32_t surface_id, const char* title), void* ctx);

void wayland_server_on_app_id_changed(WaylandServer* server,
    void (*cb)(void* ctx, uint32_t surface_id, const char* app_id), void* ctx);

void wayland_server_on_toplevel_destroy(WaylandServer* server,
    void (*cb)(void* ctx, uint32_t surface_id), void* ctx);

/* Client connection closed — the end of client_id's meaning. See above. */
void wayland_server_on_client_destroy(WaylandServer* server,
    void (*cb)(void* ctx, uint64_t client_id), void* ctx);

/* DMA-BUF surface commit. */
void wayland_server_on_surface_commit(WaylandServer* server,
    void (*cb)(void* ctx, uint32_t surface_id,
               int fd, int width, int height, int stride,
               uint32_t fourcc, uint64_t modifier,
               int first_commit, int buffer_scale), void* ctx);

/* SHM surface commit. pixel_data is valid only for the duration of the callback. */
void wayland_server_on_shm_surface_commit(WaylandServer* server,
    void (*cb)(void* ctx, uint32_t surface_id,
               const void* pixel_data,
               int width, int height, int stride,
               uint32_t format, int first_commit, int buffer_scale), void* ctx);

/* Client set max/min size hint. */
void wayland_server_on_toplevel_resize_request(WaylandServer* server,
    void (*cb)(void* ctx, uint32_t surface_id, int width, int height), void* ctx);

/* --- Text input (zwp_text_input_v3) — IME delivery --------------------- */

/* Focused client's text-input state changed: enabled flag + cursor
 * rectangle in surface-local logical coordinates. */
void wayland_server_on_text_input_state(WaylandServer* server,
    void (*cb)(void* ctx, uint32_t surface_id, int enabled,
               int32_t x, int32_t y, int32_t w, int32_t h), void* ctx);

/* Send composed text to the focused surface's enabled text input.
 * Returns 1 when delivered. Call on the server's event-loop thread. */
int wayland_server_text_input_commit_string(WaylandServer* server,
                                            const char* text);

/* Composition-in-progress text (empty/NULL clears the preedit). */
int wayland_server_text_input_preedit(WaylandServer* server,
                                      const char* text, int32_t cursor);

/* 1 when the focused surface's client has an enabled text input. */
int wayland_server_text_input_active(WaylandServer* server);

/* Client asked the compositor to start an interactive window move
 * (xdg_toplevel.move — CSD titlebar / Chrome tab-strip drag). */
void wayland_server_on_move_request(WaylandServer* server,
    void (*cb)(void* ctx, uint32_t surface_id), void* ctx);

/* Client asked the compositor to start an interactive resize from the
 * given edges (xdg_toplevel.resize; xdg resize_edge enum bitmask). */
void wayland_server_on_interactive_resize_request(WaylandServer* server,
    void (*cb)(void* ctx, uint32_t surface_id, uint32_t edges), void* ctx);

/* New popup created. x/y/width/height are surface-local coords from positioner. */
void wayland_server_on_new_popup(WaylandServer* server,
    void (*cb)(void* ctx, uint32_t surface_id, uint32_t parent_surface_id,
               int x, int y, int width, int height), void* ctx);

void wayland_server_on_popup_destroy(WaylandServer* server,
    void (*cb)(void* ctx, uint32_t surface_id), void* ctx);

/* Window geometry changed (applied on commit). */
void wayland_server_on_window_geometry(WaylandServer* server,
    void (*cb)(void* ctx, uint32_t surface_id,
               int x, int y, int width, int height), void* ctx);

/* Cursor shape changed (wp_cursor_shape_v1). shape is the enum value. */
void wayland_server_on_cursor_shape(WaylandServer* server,
    void (*cb)(void* ctx, uint32_t shape), void* ctx);

/* Client requested fullscreen (xdg_toplevel.set_fullscreen). */
void wayland_server_on_fullscreen_request(WaylandServer* server,
    void (*cb)(void* ctx, uint32_t surface_id), void* ctx);

/* Client requested exit fullscreen (xdg_toplevel.unset_fullscreen). */
void wayland_server_on_unfullscreen_request(WaylandServer* server,
    void (*cb)(void* ctx, uint32_t surface_id), void* ctx);

/* --------------------------------------------------------------------------
 * Event loop
 * -------------------------------------------------------------------------- */

/* Return the file descriptor for the Wayland event loop.
 * Poll this fd for readability, then call wayland_server_dispatch(). */
int wayland_server_get_fd(WaylandServer* server);

/* Dispatch pending events from the event loop. Call after the fd is readable. */
void wayland_server_dispatch(WaylandServer* server);

/* Flush pending outbound data to all connected clients. */
void wayland_server_flush_clients(WaylandServer* server);

/* --------------------------------------------------------------------------
 * Window management
 * -------------------------------------------------------------------------- */

/* Ask a toplevel to close (xdg_toplevel.close). Advisory — the client may
 * ignore it, so a caller that must see the app go away follows up with
 * wayland_server_surface_pid() and a signal. */
void wayland_server_close_toplevel(WaylandServer* server, uint32_t surface_id);

/* pid behind a surface's connection, from SO_PEERCRED-style peer credentials.
 * 0 if unknown. */
pid_t wayland_server_surface_pid(WaylandServer* server, uint32_t surface_id);

/* Send a configure (resize) event to a toplevel surface.
 * The client will resize and commit a new buffer in response.
 * Sends ACTIVATED + MAXIMIZED states. */
void wayland_server_configure_toplevel(WaylandServer* server,
                                       uint32_t surface_id,
                                       int width, int height);

/* Send a fullscreen configure event to a toplevel surface.
 * Sends ACTIVATED + FULLSCREEN states. width/height are surface-local. */
void wayland_server_configure_fullscreen(WaylandServer* server,
                                         uint32_t surface_id,
                                         int width, int height);

/* --------------------------------------------------------------------------
 * Frame signaling
 * -------------------------------------------------------------------------- */

/* Send presentation feedback for the given surface.
 * Called internally from the per-surface frame-done timer; exposed for the
 * bridge header only. Event-loop thread only. */
void wayland_server_presentation_feedback(WaylandServer* server,
                                          uint32_t surface_id);

/* Real-vsync frame pacing: call when a display page flip lands, with the
 * kernel scanout timestamp (CLOCK_MONOTONIC ns) and refresh period (ns).
 * Fires every pending wl_surface.frame callback and answers all pending
 * wp_presentation feedback with the real timing, then flushes clients.
 * While flips arrive, the per-surface frame-done timer only acts as a
 * stall fallback. Event-loop thread only.
 * `flip_output_mask` is the bit of the output whose flip this is (same bit
 * numbering as surface_set_outputs); only surfaces paced by that output
 * fire. Pass 1 (bit 0 = primary) on a single-output desktop. */
void wayland_server_on_present(WaylandServer* server,
                               uint64_t flip_time_ns,
                               uint32_t refresh_ns,
                               uint32_t flip_output_mask);

/* --------------------------------------------------------------------------
 * Input — Pointer
 * -------------------------------------------------------------------------- */

void wayland_server_pointer_enter(WaylandServer* server,
                                  uint32_t surface_id,
                                  double x, double y);

void wayland_server_pointer_leave(WaylandServer* server,
                                  uint32_t surface_id);

void wayland_server_pointer_motion(WaylandServer* server,
                                   uint32_t surface_id,
                                   uint32_t time_ms,
                                   double x, double y);

void wayland_server_pointer_button(WaylandServer* server,
                                   uint32_t surface_id,
                                   uint32_t time_ms,
                                   uint32_t button,
                                   uint32_t state);

void wayland_server_pointer_axis(WaylandServer* server,
                                  uint32_t surface_id,
                                  uint32_t time_ms,
                                  double axis_x,
                                  double axis_y);

/* --------------------------------------------------------------------------
 * DMA-BUF format advertisement
 * -------------------------------------------------------------------------- */

/* Replace the advertised dma-buf (format, modifier) pairs with the list the
 * compositor's EGL can actually import (from eglQueryDmaBufModifiersEXT).
 * Affects the v3 modifier events and the v4 feedback format table for
 * clients binding after the call. Call before clients connect. */
void wayland_server_set_dmabuf_formats(WaylandServer* server,
                                       const uint32_t* formats,
                                       const uint64_t* modifiers,
                                       int count);

/* Whether (fourcc, modifier) is one the compositor advertised as importable
 * (LINEAR and the implicit modifier always are). The import path checks this
 * BEFORE calling eglCreateImageKHR: handing the AMD driver a foreign tiled
 * layout can make it allocate-then-fail and, under memory pressure, abort
 * the shell with a CS rejection. Returns 1 = safe to import, 0 = skip. */
int wayland_server_dmabuf_modifier_importable(uint32_t fourcc,
                                              uint64_t modifier);

/* Demote a modifier the EGL import path REJECTED at runtime (zink's
 * eglQueryDmaBufModifiersEXT over-reports AMD tiled support — the query
 * lies, the import is ground truth). Drops every advertised pair with
 * that modifier and re-sends v4 feedback to all live feedback objects so
 * clients re-allocate with what remains (LINEAR/implicit are never
 * demoted). Thread-safe (marshals onto the event-loop thread);
 * idempotent per modifier. */
void wayland_server_demote_dmabuf_modifier(WaylandServer* server,
                                           uint32_t fourcc,
                                           uint64_t modifier);

/* --------------------------------------------------------------------------
 * Input — Keyboard
 * -------------------------------------------------------------------------- */

void wayland_server_keyboard_enter(WaylandServer* server,
                                   uint32_t surface_id);

void wayland_server_keyboard_leave(WaylandServer* server,
                                   uint32_t surface_id);

void wayland_server_keyboard_key(WaylandServer* server,
                                 uint32_t surface_id,
                                 uint32_t time_ms,
                                 uint32_t key,
                                 uint32_t state);

void wayland_server_keyboard_modifiers(WaylandServer* server,
                                       uint32_t surface_id,
                                       uint32_t mods_depressed,
                                       uint32_t mods_latched,
                                       uint32_t mods_locked,
                                       uint32_t group);

/* --------------------------------------------------------------------------
 * Utility
 * -------------------------------------------------------------------------- */

const char* wayland_server_get_socket_name(WaylandServer* server);

/* Update the output scale and notify all connected clients.
 * |scale|: integer output scale (wl_output.scale).
 * |fractional_scale_120ths|: fractional scale in 120ths (e.g. 240 = 2.0x, 180 = 1.5x).
 * Sends wl_output.scale + done to all bound outputs, and
 * wp_fractional_scale_v1.preferred_scale to all surfaces. */
void wayland_server_update_scale(WaylandServer* server,
                                  int scale, uint32_t fractional_scale_120ths);

/* Get viewport destination for a surface (surface-local coords).
 * Returns 1 if viewport destination is set, 0 otherwise.
 * When set, these dimensions override buffer_size/buffer_scale for
 * determining the surface-local size. */
int wayland_server_get_viewport_destination(WaylandServer* server,
                                            uint32_t surface_id,
                                            int* out_width, int* out_height);

/* Number of live zwp_idle_inhibitor_v1 objects across all clients.
 * Nonzero means at least one client (Chrome playing video, a presentation,
 * a player) has asked the compositor not to blank; the shell's screensaver
 * idle timer treats that as ongoing activity. */
int wayland_server_idle_inhibited(WaylandServer* server);

#ifdef __cplusplus
}
#endif

#endif /* FLUTTER_WAYLAND_SERVER_H */
