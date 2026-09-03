// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/*
 * WaylandClipboardBridge — the system clipboard for an app running under the
 * Starling shell, reached with zwlr_data_control_manager_v1.
 *
 * Why data-control and not the shell's private socket: the compositor already
 * implements this protocol completely (it is what wl-copy/wl-paste use), so an
 * app owning or reading the selection needs no compositor changes at all. It is
 * also focus-free, which matters because a Starling app is a dma-buf child, not
 * an xdg_toplevel client of its own compositor — it has no surface to focus.
 *
 * Threading: this owns a private thread and a private wl_display. Nothing here
 * runs on, or blocks, the caller's UI thread. That is the whole point — Wayland
 * clipboard transfer is pull-based, so a paste waits on the CURRENT OWNER to
 * write to a pipe, and an owner that is slow or stopped must never be able to
 * freeze the app (let alone, as an earlier design would have, the compositor).
 * Every transfer is bounded by WLCLIP_TIMEOUT_MS.
 *
 * Callbacks fire on that private thread. The caller is responsible for hopping
 * to its own UI thread before touching app state.
 */

#ifndef WAYLAND_CLIPBOARD_BRIDGE_H_
#define WAYLAND_CLIPBOARD_BRIDGE_H_

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct WlClipboard WlClipboard;

/* Delivered text is NUL-terminated and owned by the bridge — copy it before
 * returning. `text` is NULL when there is nothing to paste (empty selection,
 * no text mime on offer, or the owner failed to answer in time). */
typedef void (*WlClipTextCallback)(void* ctx, const char* text, size_t len);

/* Connect to the compositor socket `display` (e.g. "wayland-0") inside
 * XDG_RUNTIME_DIR; NULL falls back to $WAYLAND_DISPLAY. Returns NULL if the
 * compositor is unreachable or does not advertise data-control, which is the
 * normal case off Starling — callers should treat NULL as "no system
 * clipboard here" rather than an error. */
WlClipboard* wlclip_connect(const char* display);

/* Stop the thread, drop the selection if we own it, close the connection. */
void wlclip_destroy(WlClipboard* c);

/* Take ownership of the selection. `text` is copied. Serving it to whoever
 * pastes later happens on the bridge thread. */
void wlclip_set_text(WlClipboard* c, const char* text, size_t len);

/* Ask for the current selection as text. Returns 0 if the request was queued
 * (the callback always fires exactly once, possibly with NULL), -1 if it could
 * not be queued at all. Never blocks the caller. */
int wlclip_read_text(WlClipboard* c, WlClipTextCallback cb, void* ctx);

/* Fires on the bridge thread every time the selection changes — a new owner,
 * new content, or a clear. `has_text` is 1 when the new offer carries a mime
 * this bridge can read as text; `mine` is 1 when WE are the new owner, which
 * anything mirroring the selection somewhere else must check, or it announces
 * its own paste back to itself for ever. Set it before anything else runs;
 * passing NULL clears it. */
typedef void (*WlClipSelectionCallback)(void* ctx, int has_text, int mine);
void wlclip_set_selection_callback(WlClipboard* c, WlClipSelectionCallback cb,
                                   void* ctx);

/* 1 while this process is the selection owner. Reading then answers from our
 * own copy instead of round-tripping through the compositor — which would
 * deadlock, since we would be asking ourselves to write while blocked reading. */
int wlclip_owns_selection(WlClipboard* c);

#ifdef __cplusplus
}
#endif

#endif  /* WAYLAND_CLIPBOARD_BRIDGE_H_ */
