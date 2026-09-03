// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// GuestDisplay — QEMU's p2p D-Bus display, as a callback struct.
//
// QEMU started with `-display dbus,gl=on,p2p=yes` hands its scanout to one
// client over a private D-Bus socket that libvirt opens for us
// (virDomainOpenGraphicsFD). The guest's framebuffer arrives as a dma-buf fd,
// its damage as method calls whose *replies* pace the guest, and its cursor as
// a bitmap. Input goes back the other way as XT set-1 scancodes and absolute
// pointer positions.
//
// This is a callback struct rather than per-callback setters on purpose:
// CLAUDE.md records what an unregistered `wayland_server_on_*` setter cost
// twice over — a silent NULL check and a compositor that looked like it had a
// rendering bug. A struct field the compiler can see cannot go unset by
// accident.
//
// Threading: the bus lives on its own thread. Every callback fires there;
// every command function may be called from any thread and never blocks.

#ifndef STARLING_GUEST_DISPLAY_H
#define STARLING_GUEST_DISPLAY_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct GuestDisplay GuestDisplay;

enum {
    GUEST_DISPLAY_CONNECTING = 0,
    GUEST_DISPLAY_CONNECTED = 1,
    GUEST_DISPLAY_DISCONNECTED = 2,
    GUEST_DISPLAY_FAILED = 3,
};

typedef struct GuestDisplayCallbacks {
    void* ctx;

    // Connection lifecycle. `detail` is libvirt's or sd-bus's own message on
    // FAILED — "Domain not found", "permission denied" — and NULL otherwise.
    void (*on_state)(void* ctx, int state, const char* detail);

    // One new scanout: the guest's framebuffer changed size, format or
    // buffer. `fd` is a dup owned by the callee. Plane 0 only — the spike saw
    // one plane, AB24, modifier INVALID; the rest stay with the message.
    // `stride` carries padding (1400 px came back as 5632 bytes), so import
    // with it and never compute it from the width. `y0_top` is inverted
    // relative to its name: row 0 is the BOTTOM when it is true, and it
    // differs between the placeholder scanout and the real one, so it is
    // per-frame state and not a property of the window.
    void (*on_scanout)(void* ctx, int fd, uint32_t width, uint32_t height,
                       uint32_t stride, uint32_t offset, uint32_t fourcc,
                       uint64_t modifier, int y0_top);

    // Damage. The reply to this call is QEMU's frame ack — it blocks the
    // guest's display pipeline until we send it — so it is withheld until
    // guest_display_ack_frame(token) or the deadline, whichever comes first.
    // The rect is timing information only; the compositor repaints whole
    // surfaces.
    void (*on_update)(void* ctx, uint64_t token, int x, int y, int w, int h);

    // The console went away (guest reset, display off). A scanout follows
    // when it comes back.
    void (*on_disable)(void* ctx);

    // CursorDefine: straight-alpha BGRA, `len` == w*h*4. Only ever sent when
    // the guest has HWCursor=1; without it Windows paints its pointer into
    // the framebuffer instead.
    void (*on_cursor_define)(void* ctx, int w, int h, int hot_x, int hot_y,
                             const uint8_t* bgra, size_t len);
    void (*on_mouse_set)(void* ctx, int x, int y, int visible);

    // Clipboard (Phase 6). Not called until guest_display_clipboard_enable().
    void (*on_clipboard_grab)(void* ctx, const char* const* mimes, int n);
    void (*on_clipboard_release)(void* ctx);
    void (*on_clipboard_request)(void* ctx, uint64_t token, const char* mime);
} GuestDisplayCallbacks;

// Returns at once. The connection is made on the display's own thread and
// reported through on_state; a NULL return means only that the thread could
// not be started.
GuestDisplay* guest_display_open(const char* domain,
                                 const GuestDisplayCallbacks* cb);

// Releases any keys the guest still thinks are down, joins the thread and
// frees everything. Never call it from inside a callback.
void guest_display_close(GuestDisplay* gd);

// ── Commands. Any thread; each is queued to the bus thread and returns at
// once. A command for a display that is not connected yet is dropped.

// Send the frame ack for `token`. Acking from the compositor's own present
// callback paces the guest to our refresh exactly as a monitor would.
void guest_display_ack_frame(GuestDisplay* gd, uint64_t token);

// XT set-1 scancode, extended keys folded into the high bit (0xe0 0x1c ->
// 0x9c) — the encoding HidQnum.swift generates.
void guest_display_key(GuestDisplay* gd, uint32_t qnum, int down);

// Guest pixels, which are the window's content size times the shell's dpi.
void guest_display_mouse_abs(GuestDisplay* gd, uint32_t x, uint32_t y);

// 0 left, 1 middle, 2 right, 3 wheel-up, 4 wheel-down (a wheel notch is a
// press and a release of 3 or 4).
void guest_display_mouse_button(GuestDisplay* gd, uint32_t button, int down);

// Console.SetUIInfo — asks the guest to change resolution. The guest's own
// resolution service answers with a fresh scanout, ~40 ms later when
// vgpusrv is installed and never when it is not.
void guest_display_set_ui_size(GuestDisplay* gd, uint32_t w, uint32_t h);

// ── Clipboard (Phase 6). Enable exports our Clipboard object and registers
// it; until then the three clipboard callbacks never fire.
void guest_display_clipboard_enable(GuestDisplay* gd);
void guest_display_clipboard_grab(GuestDisplay* gd, const char* const* mimes,
                                  int n);
void guest_display_clipboard_reply(GuestDisplay* gd, uint64_t token,
                                   const char* mime, const void* data,
                                   size_t len);

// ── libvirt, synchronous and tens of milliseconds each. Not for the UI
// thread. They open their own connection, so they work before the display is
// opened and after it has failed.

// virDomainState (1 == running), or -1 when there is no such domain.
int guest_display_domain_state(const char* domain);
int guest_display_domain_start(const char* domain);
// ACPI shutdown — the guest decides how long it takes.
int guest_display_domain_shutdown(const char* domain);

#ifdef __cplusplus
}
#endif

#endif  // STARLING_GUEST_DISPLAY_H
