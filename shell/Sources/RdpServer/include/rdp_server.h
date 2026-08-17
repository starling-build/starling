// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// rdp_server.h — a minimal RDP server over libfreerdp-server3.
//
// Scope is deliberately one client, one screen, mouse only: a client
// connects over TLS, sees the primary output, and can point and click.
// Keyboard, clipboard, audio and the GFX/H.264 pipeline are all later
// increments on this pipe (docs/plans/rdp.md).
//
// Threading: rdp_server_start returns immediately and the listener runs on
// its own thread; an accepted peer gets a second thread. Every callback
// below therefore fires OFF the shell's main thread — the Swift side hops
// to wherever the work belongs. rdp_server_push_frame is the one call in
// the other direction, and it encodes synchronously on the CALLER's
// thread, so the caller must not be the engine's capture callback.

#ifndef STARLING_RDP_SERVER_H_
#define STARLING_RDP_SERVER_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct RdpServer RdpServer;

typedef struct {
    // A peer finished capability exchange and wants pixels. |w|,|h| are
    // what the server advertised (the desktop size passed to start).
    // Return 0 to accept, non-zero to reject — the shell rejects when
    // another service already owns the engine's single capture session.
    int (*on_activated)(void* ud, uint32_t w, uint32_t h);
    // The peer went away (clean disconnect or transport error). Always
    // paired with a preceding successful on_activated.
    void (*on_disconnected)(void* ud);
    // Pointer report in DESKTOP PHYSICAL PIXELS, with the ABSOLUTE button
    // mask in Flutter's encoding (1 primary, 2 secondary, 4 middle) and
    // wheel deltas already in Flutter's pixel units. The shim owns the
    // PTR_FLAGS_* bookkeeping so the Swift side never sees RDP's
    // transition-flavoured input model.
    void (*on_pointer)(void* ud, double x, double y, int64_t buttons,
                       double wheel_dx, double wheel_dy);
    // A key, as RDP sends it: PC/AT set-1 |scancode|, its 0xE0 |extended|
    // prefix, and |down|. Translation to the engine's representation is the
    // caller's (see rdp_keyboard.h) — this only carries the wire values.
    // May be NULL; share mode leaves it so, having a real keyboard already.
    void (*on_key)(void* ud, uint32_t scancode, int extended, int down);
    // Client's lock-key state (MS-RDPBCGR synchronize): bit 0 scroll,
    // 1 num, 2 caps. May be NULL.
    void (*on_key_sync)(void* ud, uint32_t toggle_flags);
} RdpServerCallbacks;

// Start listening. |bind_addr| may be NULL for all interfaces. |cert_path|
// and |key_path| are PEM files and are required — there is no unencrypted
// mode. Returns NULL on failure (port in use, unreadable cert, no TLS).
//
// |honor_client_size| picks who wins the size negotiation, and the two modes
// want opposite answers. Share mode (0) forces the client to the physical
// output's size, because the desktop is already being scanned out at it.
// Display mode (1) keeps whatever the client asks for, because there is no
// physical output and the client's window IS the screen — the negotiated
// size then arrives via on_activated and sizes everything downstream.
RdpServer* rdp_server_start(const char* bind_addr, int port,
                            const char* cert_path, const char* key_path,
                            uint32_t desktop_w, uint32_t desktop_h,
                            int honor_client_size,
                            const RdpServerCallbacks* cbs, void* ud);

// Stop listening, drop any peer, join both threads. Safe with NULL.
void rdp_server_stop(RdpServer* s);

// Hand over one full frame: top-down, 4 bytes per pixel, R first (both the
// DRM capture format and what glReadPixels returns). Encodes and sends
// synchronously; returns 0 if there is no active peer or the encode failed.
// Dimensions must match the negotiated size — a mismatch is dropped rather
// than scaled.
int rdp_server_push_frame(RdpServer* s, const uint8_t* rgba,
                          uint32_t w, uint32_t h);

// Non-zero while a peer is connected AND activated.
int rdp_server_client_connected(RdpServer* s);

#ifdef __cplusplus
}
#endif

#endif  // STARLING_RDP_SERVER_H_
