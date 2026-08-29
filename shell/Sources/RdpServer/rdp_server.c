// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// rdp_server.c — RDP server over libfreerdp-server3 (see rdp_server.h).
//
// The peer lifecycle is the one FreeRDP's own server samples use: a
// listener thread accepts, and each peer runs its own thread pumping
// CheckFileDescriptor against the transport's event handles. Frames arrive
// from the other direction (rdp_server_push_frame) and go out as
// RemoteFX-compressed SurfaceBits.
//
// One client at a time, by construction. A second connection is refused at
// accept: replacing a live peer would mean tearing down the capture claim
// and re-establishing it mid-stream, which buys nothing for a v1 whose
// whole job is to prove the pipe.

#include "include/rdp_server.h"

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <freerdp/freerdp.h>
#include <freerdp/listener.h>
#include <freerdp/peer.h>
#include <freerdp/codec/color.h>
#include <freerdp/codec/nsc.h>
#include <freerdp/codec/rfx.h>
#include <freerdp/constants.h>
#include <freerdp/input.h>
#include <freerdp/settings.h>
#include <freerdp/update.h>
#include <winpr/stream.h>
#include <winpr/synch.h>

struct RdpServer {
    freerdp_listener* listener;
    pthread_t listen_thread;
    pthread_t peer_thread;

    RdpServerCallbacks cbs;
    void* ud;

    uint32_t desktop_w, desktop_h;
    int honor_client_size;  // display mode: the client's size wins
    char* cert_path;
    char* key_path;

    volatile int running;      // cleared by stop(); both threads watch it
    /// Signalled by stop() so the two waits below can block indefinitely.
    ///
    /// Without it each wait needed a timeout purely so that clearing
    /// `running` would eventually be noticed -- five wakeups a second, for
    /// as long as RDP was switched on, on a link with no traffic at all.
    /// A WinPR event is a HANDLE like any other, so it simply joins the
    /// array the wait already takes.
    HANDLE stop_event;
    volatile int peer_active;  // a peer is connected AND activated
    volatile int peer_present; // a peer object exists (pre-activation too)
    // Activate fires again on every deactivation-reactivation sequence,
    // which is a normal part of the protocol — but the capture claim is a
    // once-per-connection event, so the callback is gated on this.
    int notified_activation;

    // Encode state — touched only by the pushing thread, between
    // activation and disconnect.
    //
    // Which codec is in use is the client's choice, not ours: RemoteFX if it
    // negotiated one, else NSCodec, else raw bitmaps. mstsc does not always
    // take RemoteFX, and refusing it outright (as this once did) turns
    // "connect from Windows" into a disconnect with no explanation.
    enum { CODEC_RFX, CODEC_NSC, CODEC_RAW } codec;
    RFX_CONTEXT* rfx;
    NSC_CONTEXT* nsc;
    wStream* stream;
    freerdp_peer* peer;
    pthread_mutex_t peer_lock;  // guards peer/rfx/stream against teardown

    // The button mask as the client last reported it. RDP sends
    // transitions; the engine wants absolute state, so the translation
    // lives here.
    int64_t buttons;
    // Last position the client reported in an event whose coordinates were
    // meaningful — see peer_mouse_event.
    double last_x, last_y;
    // Monotonic id for surface frame markers.
    uint32_t frame_id;
};

// The per-peer context FreeRDP allocates for us; it only has to carry the
// back-pointer so the static callbacks can find the server.
typedef struct {
    rdpContext _p;
    RdpServer* server;
} StarlingPeerContext;

// ─── Peer callbacks (peer thread) ────────────────────────────────────────────

static BOOL peer_context_new(freerdp_peer* peer, rdpContext* context) {
    (void)peer;
    (void)context;
    return TRUE;
}

static void peer_context_free(freerdp_peer* peer, rdpContext* context) {
    (void)peer;
    (void)context;
}

static BOOL peer_capabilities(freerdp_peer* peer) {
    (void)peer;
    return TRUE;
}

static BOOL peer_post_connect(freerdp_peer* peer) {
    StarlingPeerContext* ctx = (StarlingPeerContext*)peer->context;
    RdpServer* s = ctx->server;
    rdpSettings* settings = peer->context->settings;

    if (s->honor_client_size) {
        // Display mode: there is no physical output, so the client's
        // requested size simply becomes the desktop. Adopt it and let it
        // size the render target, the window metrics and the encoder.
        uint32_t cw =
            freerdp_settings_get_uint32(settings, FreeRDP_DesktopWidth);
        uint32_t ch =
            freerdp_settings_get_uint32(settings, FreeRDP_DesktopHeight);
        // RemoteFX works in 64x64 tiles; a ragged edge is the codec's
        // problem, but a zero or absurd size is ours.
        if (cw >= 320 && ch >= 240 && cw <= 8192 && ch <= 8192) {
            s->desktop_w = cw;
            s->desktop_h = ch;
        } else {
            fprintf(stderr,
                    "[Rdp] client asked for %ux%u — refusing, keeping %ux%u\n",
                    cw, ch, s->desktop_w, s->desktop_h);
            if (!freerdp_settings_set_uint32(settings, FreeRDP_DesktopWidth,
                                             s->desktop_w) ||
                !freerdp_settings_set_uint32(settings, FreeRDP_DesktopHeight,
                                             s->desktop_h)) {
                return FALSE;
            }
        }
        if (!freerdp_settings_set_uint32(settings, FreeRDP_ColorDepth, 32)) {
            return FALSE;
        }
        return TRUE;  // nothing to resize: we took what was offered
    }

    // Share mode: the server wins. We send the primary output at its native
    // size and let the client scale or scroll — honouring the client would
    // mean resizing a desktop that is being scanned out to a real panel.
    if (!freerdp_settings_set_uint32(settings, FreeRDP_DesktopWidth,
                                     s->desktop_w) ||
        !freerdp_settings_set_uint32(settings, FreeRDP_DesktopHeight,
                                     s->desktop_h) ||
        !freerdp_settings_set_uint32(settings, FreeRDP_ColorDepth, 32)) {
        return FALSE;
    }
    if (!peer->context->update->DesktopResize(peer->context)) {
        fprintf(stderr, "[Rdp] DesktopResize failed\n");
        return FALSE;
    }
    return TRUE;
}

static BOOL peer_activate(freerdp_peer* peer) {
    StarlingPeerContext* ctx = (StarlingPeerContext*)peer->context;
    RdpServer* s = ctx->server;
    rdpSettings* settings = peer->context->settings;

    // Which codec the CLIENT offered is carried by the codec ids, not by the
    // RemoteFxCodec/NSCodec booleans: those keep whatever the server set on
    // itself and say nothing about the peer. The ids come out of the client's
    // Bitmap Codecs capability set, so a non-zero id is the real evidence
    // that this client can decode that codec.
    const UINT32 rfx_id =
        freerdp_settings_get_uint32(settings, FreeRDP_RemoteFxCodecId);
    const UINT32 nsc_id =
        freerdp_settings_get_uint32(settings, FreeRDP_NSCodecId);
    fprintf(stderr, "[Rdp] client codecs: rfx_id=%u nsc_id=%u surfcmds=%d\n",
            rfx_id, nsc_id,
            freerdp_settings_get_bool(settings, FreeRDP_SurfaceCommandsEnabled));

    // Test seam: the ladder's lower rungs are hard to reach with a client
    // that advertises everything (xfreerdp offers RemoteFX even with -rfx),
    // so allow forcing one. Not a tuning knob — a way to exercise the paths
    // mstsc will take without needing mstsc.
    const char* force = getenv("STARLING_RDP_CODEC");
    const int force_nsc = force && strcmp(force, "nsc") == 0;
    const int force_raw = force && strcmp(force, "raw") == 0;
    if (force) {
        fprintf(stderr, "[Rdp] STARLING_RDP_CODEC=%s\n", force);
    }
    if (force_nsc && nsc_id == 0) {
        fprintf(stderr, "[Rdp] cannot force NSCodec: this client did not "
                        "offer it (nsc_id=0) — using the ladder instead\n");
    }

    // Best the client offered, in descending order of what it costs on the
    // wire. Raw is always available — SurfaceCommands with codecID 0 — so
    // there is no client we cannot draw for, only clients we draw for
    // expensively.
    pthread_mutex_lock(&s->peer_lock);
    if (rfx_id != 0 && !force_raw && !(force_nsc && nsc_id != 0)) {
        s->codec = CODEC_RFX;
        if (!s->rfx) {
            s->rfx = rfx_context_new(TRUE);  // encoder
        }
        // Frames arrive R,G,B,X in memory order, from the capture sink on
        // DRM and from glReadPixels in display mode alike.
        if (!s->rfx || !rfx_context_reset(s->rfx, s->desktop_w, s->desktop_h)) {
            fprintf(stderr, "[Rdp] rfx_context_reset failed\n");
            pthread_mutex_unlock(&s->peer_lock);
            return FALSE;
        }
        rfx_context_set_pixel_format(s->rfx, PIXEL_FORMAT_RGBX32);
    } else if (nsc_id != 0 && !force_raw) {
        // Only when the client actually offered NSCodec. Sending NSC data
        // under a codec id the client never assigned decodes to nothing, and
        // a black screen is a worse failure than falling through to raw —
        // which is what forcing nsc against xfreerdp (it advertises no
        // NSCodec) produced while this was being written.
        s->codec = CODEC_NSC;
        if (!s->nsc) {
            s->nsc = nsc_context_new();
        }
        if (!s->nsc || !nsc_context_reset(s->nsc, s->desktop_w, s->desktop_h)) {
            fprintf(stderr, "[Rdp] nsc_context_reset failed\n");
            pthread_mutex_unlock(&s->peer_lock);
            return FALSE;
        }
        if (!nsc_context_set_parameters(s->nsc, NSC_COLOR_FORMAT,
                                        PIXEL_FORMAT_RGBX32)) {
            fprintf(stderr, "[Rdp] nsc colour format rejected\n");
            pthread_mutex_unlock(&s->peer_lock);
            return FALSE;
        }
    } else {
        s->codec = CODEC_RAW;
    }
    if (!s->stream) {
        // Raw frames are the largest thing that ever goes through here:
        // width * height * 4 plus command overhead, so size for that rather
        // than growing under the encode.
        const size_t raw = (size_t)s->desktop_w * s->desktop_h * 4 + 4096;
        s->stream = Stream_New(NULL, raw);
    }
    int ok = (s->stream != NULL);
    if (ok) {
        s->peer = peer;
    }
    pthread_mutex_unlock(&s->peer_lock);
    if (!ok) {
        return FALSE;
    }

    // Re-activation: the peer already owns the capture, so re-claiming it
    // would refuse itself. Everything above (codec check, encoder reset)
    // still re-runs, which is what a reactivation is for.
    if (s->notified_activation) {
        fprintf(stderr, "[Rdp] client re-activated\n");
        return TRUE;
    }
    if (s->cbs.on_activated &&
        s->cbs.on_activated(s->ud, s->desktop_w, s->desktop_h) != 0) {
        fprintf(stderr, "[Rdp] activation refused by the shell "
                        "(capture busy?)\n");
        return FALSE;
    }
    s->notified_activation = 1;

    s->buttons = 0;
    // Centre, so a scroll before the first motion lands somewhere sane.
    s->last_x = s->desktop_w / 2.0;
    s->last_y = s->desktop_h / 2.0;
    s->peer_active = 1;
    fprintf(stderr, "[Rdp] client activated: %ux%u %s\n", s->desktop_w,
            s->desktop_h,
            s->codec == CODEC_RFX ? "RemoteFX"
            : s->codec == CODEC_NSC ? "NSCodec"
                                    : "raw bitmaps (no codec negotiated)");
    return TRUE;
}

// RDP reports pointer transitions; the engine wants absolute state. Fold
// the flags into our mask and hand the result over.
static BOOL peer_mouse_event(rdpInput* input, UINT16 flags, UINT16 x,
                             UINT16 y) {
    StarlingPeerContext* ctx = (StarlingPeerContext*)input->context;
    RdpServer* s = ctx->server;
    if (!s->peer_active) {
        return TRUE;
    }

    const int down = (flags & PTR_FLAGS_DOWN) != 0;
    if (flags & PTR_FLAGS_BUTTON1) {
        s->buttons = down ? (s->buttons | 1) : (s->buttons & ~(int64_t)1);
    }
    if (flags & PTR_FLAGS_BUTTON2) {
        s->buttons = down ? (s->buttons | 2) : (s->buttons & ~(int64_t)2);
    }
    if (flags & PTR_FLAGS_BUTTON3) {
        s->buttons = down ? (s->buttons | 4) : (s->buttons & ~(int64_t)4);
    }

    // MS-RDPBCGR: on a wheel event xPos/yPos are NOT used, and FreeRDP's
    // client duly sends zeroes. Taking them at face value would warp the
    // pointer to the top-left corner on every scroll, so only a move or a
    // button carries a position.
    const int wheel_only = (flags & (PTR_FLAGS_WHEEL | PTR_FLAGS_HWHEEL)) &&
                           !(flags & PTR_FLAGS_MOVE);
    if (!wheel_only) {
        s->last_x = (double)x;
        s->last_y = (double)y;
    }

    double wheel_dx = 0, wheel_dy = 0;
    if (flags & (PTR_FLAGS_WHEEL | PTR_FLAGS_HWHEEL)) {
        // Low 8 bits are the rotation magnitude; the NEGATIVE flag carries
        // the sign (the field itself is unsigned).
        int delta = flags & 0xFF;
        if (flags & PTR_FLAGS_WHEEL_NEGATIVE) {
            delta = -delta;
        }
        // A notch is 120 units in RDP and ~20 pixels to Flutter. Scrolling
        // DOWN is a positive RDP rotation but a negative Flutter delta.
        double px = (delta / 120.0) * 20.0;
        if (flags & PTR_FLAGS_HWHEEL) {
            wheel_dx = px;
        } else {
            wheel_dy = -px;
        }
    }

    if (s->cbs.on_pointer) {
        s->cbs.on_pointer(s->ud, s->last_x, s->last_y, s->buttons, wheel_dx,
                          wheel_dy);
    }
    return TRUE;
}

static BOOL peer_extended_mouse_event(rdpInput* input, UINT16 flags, UINT16 x,
                                      UINT16 y) {
    // XBUTTON1/2 have no Flutter equivalent we use; treat as a plain move
    // so the pointer still tracks.
    (void)flags;
    return peer_mouse_event(input, PTR_FLAGS_MOVE, x, y);
}

static BOOL peer_keyboard_event(rdpInput* input, UINT16 flags, UINT8 code) {
    StarlingPeerContext* ctx = (StarlingPeerContext*)input->context;
    RdpServer* s = ctx->server;
    static int seen = 0;
    if (++seen <= 8) {
        fprintf(stderr,
                "[Rdp] key from client: flags=0x%04x code=0x%02x "
                "(active=%d handler=%d)\n",
                flags, code, s->peer_active, s->cbs.on_key != NULL);
    }
    if (!s->peer_active || !s->cbs.on_key) {
        return TRUE;
    }
    // KBD_FLAGS_RELEASE (0x8000) marks the up edge; KBD_FLAGS_EXTENDED
    // (0x0100) is the 0xE0 prefix that separates, say, Right Ctrl from Left.
    const int down = (flags & 0x8000) == 0;
    const int extended = (flags & 0x0100) != 0;
    s->cbs.on_key(s->ud, (uint32_t)code, extended, down);
    return TRUE;
}

static BOOL peer_unicode_keyboard_event(rdpInput* input, UINT16 flags,
                                        UINT16 code) {
    (void)input;
    (void)flags;
    (void)code;
    return TRUE;
}

static BOOL peer_synchronize_event(rdpInput* input, UINT32 flags) {
    StarlingPeerContext* ctx = (StarlingPeerContext*)input->context;
    RdpServer* s = ctx->server;
    // Sent at connect and after a client-side focus change: without it the
    // session never learns the client's Caps/Num state and silently
    // disagrees with the keyboard the user is looking at.
    if (s->cbs.on_key_sync) {
        s->cbs.on_key_sync(s->ud, flags);
    }
    return TRUE;
}

static BOOL peer_refresh_rect(rdpContext* context, BYTE count,
                              const RECTANGLE_16* areas) {
    (void)context;
    (void)count;
    (void)areas;
    return TRUE;  // we always send full frames
}

static BOOL peer_suppress_output(rdpContext* context, BYTE allow,
                                 const RECTANGLE_16* area) {
    (void)context;
    (void)allow;
    (void)area;
    return TRUE;
}

// ─── Peer thread ─────────────────────────────────────────────────────────────

static void* peer_thread_main(void* arg) {
    freerdp_peer* peer = (freerdp_peer*)arg;
    StarlingPeerContext* ctx = (StarlingPeerContext*)peer->context;
    RdpServer* s = ctx->server;

    if (!peer->Initialize(peer)) {
        fprintf(stderr, "[Rdp] peer Initialize failed\n");
        goto done;
    }

    while (s->running) {
        HANDLE handles[64];
        DWORD count = peer->GetEventHandles(peer, handles, 63);
        if (count == 0) {
            fprintf(stderr, "[Rdp] peer GetEventHandles failed\n");
            break;
        }
        // stop() signals the event rather than this waiting to notice.
        if (s->stop_event) {
            handles[count++] = s->stop_event;
        }
        DWORD status = WaitForMultipleObjects(count, handles, FALSE,
                                              s->stop_event ? INFINITE : 200);
        if (status == WAIT_FAILED) {
            break;
        }
        if (!peer->CheckFileDescriptor(peer)) {
            break;  // clean disconnect or transport error
        }
    }

done:
    fprintf(stderr, "[Rdp] client disconnected\n");
    // Drop the encode state before telling the shell, so a frame pushed
    // concurrently finds no peer rather than a half-freed one.
    pthread_mutex_lock(&s->peer_lock);
    s->peer_active = 0;
    s->notified_activation = 0;
    s->peer = NULL;
    if (s->rfx) {
        rfx_context_free(s->rfx);
        s->rfx = NULL;
    }
    if (s->nsc) {
        nsc_context_free(s->nsc);
        s->nsc = NULL;
    }
    if (s->stream) {
        Stream_Free(s->stream, TRUE);
        s->stream = NULL;
    }
    pthread_mutex_unlock(&s->peer_lock);

    if (s->cbs.on_disconnected) {
        s->cbs.on_disconnected(s->ud);
    }

    peer->Disconnect(peer);
    freerdp_peer_context_free(peer);
    freerdp_peer_free(peer);
    s->peer_present = 0;
    return NULL;
}

// ─── Listener (listener thread) ──────────────────────────────────────────────

static BOOL on_peer_accepted(freerdp_listener* instance, freerdp_peer* peer) {
    RdpServer* s = (RdpServer*)instance->info;

    // One client. A second is closed immediately rather than queued.
    if (s->peer_present) {
        fprintf(stderr, "[Rdp] refusing second client (one at a time)\n");
        return FALSE;
    }

    peer->ContextSize = sizeof(StarlingPeerContext);
    peer->ContextNew = peer_context_new;
    peer->ContextFree = peer_context_free;
    if (!freerdp_peer_context_new(peer)) {
        return FALSE;
    }
    StarlingPeerContext* ctx = (StarlingPeerContext*)peer->context;
    ctx->server = s;

    rdpSettings* settings = peer->context->settings;
    rdpCertificate* cert = freerdp_certificate_new_from_file(s->cert_path);
    rdpPrivateKey* key = freerdp_key_new_from_file(s->key_path);
    if (!cert || !key) {
        fprintf(stderr, "[Rdp] cannot load cert/key (%s, %s)\n", s->cert_path,
                s->key_path);
        goto fail;
    }
    if (!freerdp_settings_set_pointer_len(settings, FreeRDP_RdpServerCertificate,
                                          cert, 1) ||
        !freerdp_settings_set_pointer_len(settings, FreeRDP_RdpServerRsaKey, key,
                                          1)) {
        goto fail;
    }
    // TLS only: no NLA (we have no credential story yet) and no legacy RDP
    // security. See the security note in docs/plans/rdp.md — this is a
    // LAN/dev posture, not a shipping one.
    if (!freerdp_settings_set_bool(settings, FreeRDP_TlsSecurity, TRUE) ||
        !freerdp_settings_set_bool(settings, FreeRDP_NlaSecurity, FALSE) ||
        !freerdp_settings_set_bool(settings, FreeRDP_RdpSecurity, FALSE) ||
        !freerdp_settings_set_bool(settings, FreeRDP_RemoteFxCodec, TRUE) ||
        // Offered so a client without RemoteFX still has something better
        // than raw to negotiate; which one it picks is read back at activate.
        !freerdp_settings_set_bool(settings, FreeRDP_NSCodec, TRUE) ||
        !freerdp_settings_set_bool(settings, FreeRDP_SurfaceCommandsEnabled,
                                   TRUE) ||
        !freerdp_settings_set_uint32(settings, FreeRDP_ColorDepth, 32) ||
        !freerdp_settings_set_uint32(settings, FreeRDP_DesktopWidth,
                                     s->desktop_w) ||
        !freerdp_settings_set_uint32(settings, FreeRDP_DesktopHeight,
                                     s->desktop_h)) {
        goto fail;
    }

    peer->Capabilities = peer_capabilities;
    peer->PostConnect = peer_post_connect;
    peer->Activate = peer_activate;

    rdpInput* input = peer->context->input;
    input->MouseEvent = peer_mouse_event;
    input->ExtendedMouseEvent = peer_extended_mouse_event;
    input->KeyboardEvent = peer_keyboard_event;
    input->UnicodeKeyboardEvent = peer_unicode_keyboard_event;
    input->SynchronizeEvent = peer_synchronize_event;

    rdpUpdate* update = peer->context->update;
    update->RefreshRect = peer_refresh_rect;
    update->SuppressOutput = peer_suppress_output;

    s->peer_present = 1;
    if (pthread_create(&s->peer_thread, NULL, peer_thread_main, peer) != 0) {
        s->peer_present = 0;
        goto fail;
    }
    pthread_detach(s->peer_thread);
    fprintf(stderr, "[Rdp] client accepted\n");
    return TRUE;

fail:
    freerdp_peer_context_free(peer);
    return FALSE;
}

static void* listen_thread_main(void* arg) {
    RdpServer* s = (RdpServer*)arg;
    while (s->running) {
        HANDLE handles[64];
        DWORD count =
            s->listener->GetEventHandles(s->listener, handles, 63);
        if (count == 0) {
            fprintf(stderr, "[Rdp] listener GetEventHandles failed\n");
            break;
        }
        if (s->stop_event) {
            handles[count++] = s->stop_event;
        }
        DWORD status = WaitForMultipleObjects(count, handles, FALSE,
                                              s->stop_event ? INFINITE : 200);
        if (status == WAIT_FAILED) {
            break;
        }
        if (status != WAIT_TIMEOUT) {
            if (!s->listener->CheckFileDescriptor(s->listener)) {
                fprintf(stderr, "[Rdp] listener check failed\n");
                break;
            }
        }
    }
    return NULL;
}

// ─── Public API ──────────────────────────────────────────────────────────────

RdpServer* rdp_server_start(const char* bind_addr, int port,
                            const char* cert_path, const char* key_path,
                            uint32_t desktop_w, uint32_t desktop_h,
                            int honor_client_size,
                            const RdpServerCallbacks* cbs, void* ud) {
    if (!cert_path || !key_path || !cbs || desktop_w == 0 || desktop_h == 0) {
        return NULL;
    }
    // RemoteFX tiles are 64x64 and the encoder wants whole tiles; an odd
    // desktop size would produce a torn right/bottom edge.
    if (desktop_w % 16 != 0 || desktop_h % 16 != 0) {
        fprintf(stderr, "[Rdp] desktop %ux%u is not a multiple of 16 — "
                        "RemoteFX may tear at the edges\n",
                desktop_w, desktop_h);
    }

    RdpServer* s = calloc(1, sizeof(RdpServer));
    if (!s) {
        return NULL;
    }
    s->cbs = *cbs;
    s->ud = ud;
    s->desktop_w = desktop_w;
    s->desktop_h = desktop_h;
    s->honor_client_size = honor_client_size;
    s->cert_path = strdup(cert_path);
    s->key_path = strdup(key_path);
    pthread_mutex_init(&s->peer_lock, NULL);
    // Manual-reset: once stop() signals it, every wait stays woken.
    s->stop_event = CreateEvent(NULL, TRUE, FALSE, NULL);

    s->listener = freerdp_listener_new();
    if (!s->listener) {
        goto fail;
    }
    s->listener->info = s;
    s->listener->PeerAccepted = on_peer_accepted;

    if (!s->listener->Open(s->listener, bind_addr, (UINT16)port)) {
        fprintf(stderr, "[Rdp] cannot listen on %s:%d (in use?)\n",
                bind_addr ? bind_addr : "*", port);
        goto fail;
    }

    s->running = 1;
    if (pthread_create(&s->listen_thread, NULL, listen_thread_main, s) != 0) {
        s->running = 0;
        goto fail;
    }
    fprintf(stderr, "[Rdp] listening on %s:%d (%ux%u, TLS, no NLA)\n",
            bind_addr ? bind_addr : "*", port, desktop_w, desktop_h);
    return s;

fail:
    if (s->listener) {
        s->listener->Close(s->listener);
        freerdp_listener_free(s->listener);
    }
    free(s->cert_path);
    free(s->key_path);
    pthread_mutex_destroy(&s->peer_lock);
    if (s->stop_event) { CloseHandle(s->stop_event); s->stop_event = NULL; }
    free(s);
    return NULL;
}

void rdp_server_stop(RdpServer* s) {
    if (!s) {
        return;
    }
    s->running = 0;
    if (s->stop_event) {
        SetEvent(s->stop_event);
    }
    pthread_join(s->listen_thread, NULL);
    // The peer thread is detached and watches `running` too; give it the
    // same 200ms window its wait uses before tearing the listener down.
    for (int i = 0; i < 10 && s->peer_present; i++) {
        Sleep(50);
    }
    if (s->listener) {
        s->listener->Close(s->listener);
        freerdp_listener_free(s->listener);
    }
    free(s->cert_path);
    free(s->key_path);
    pthread_mutex_destroy(&s->peer_lock);
    if (s->stop_event) { CloseHandle(s->stop_event); s->stop_event = NULL; }
    free(s);
}

int rdp_server_client_connected(RdpServer* s) {
    return s && s->peer_active;
}

int rdp_server_push_frame(RdpServer* s, const uint8_t* rgba, uint32_t w,
                          uint32_t h) {
    if (!s || !rgba || !s->peer_active) {
        return 0;
    }
    if (w != s->desktop_w || h != s->desktop_h) {
        return 0;  // never scale: a wrong-sized frame is a bug upstream
    }

    pthread_mutex_lock(&s->peer_lock);
    if (!s->peer_active || !s->stream || !s->peer) {
        pthread_mutex_unlock(&s->peer_lock);
        return 0;
    }

    rdpSettings* settings = s->peer->context->settings;
    rdpUpdate* update = s->peer->context->update;

    // Bracket the frame. Some clients treat surface bits as provisional
    // until the END marker, and it is what frame acknowledgement is built
    // on. Weston brackets its raw path the same way.
    const int markers =
        freerdp_settings_get_bool(settings, FreeRDP_FrameMarkerCommandEnabled);
    SURFACE_FRAME_MARKER marker = { 0 };
    if (markers) {
        marker.frameId = s->frame_id;
        marker.frameAction = SURFACECMD_FRAMEACTION_BEGIN;
        update->SurfaceFrameMarker(update->context, &marker);
    }

    SURFACE_BITS_COMMAND cmd = { 0 };
    // skipCompression: the payload is ALREADY encoded (or deliberately
    // raw). Without it FreeRDP may compress it again on the way out, and
    // the client then decodes rubbish — weston sets this on both codec
    // paths for the same reason.
    cmd.skipCompression = TRUE;
    cmd.bmp.bpp = 32;
    cmd.bmp.flags = 0;
    cmd.bmp.width = (UINT16)w;
    cmd.bmp.height = (UINT16)h;
    cmd.destLeft = 0;
    cmd.destTop = 0;
    cmd.destRight = w;
    cmd.destBottom = h;

    int ok = 0;
    switch (s->codec) {
        case CODEC_RFX: {
            Stream_SetPosition(s->stream, 0);
            RFX_RECT rect = { 0, 0, (UINT16)w, (UINT16)h };
            if (!s->rfx || !rfx_compose_message(s->rfx, s->stream, &rect, 1,
                                                rgba, w, h, w * 4)) {
                pthread_mutex_unlock(&s->peer_lock);
                fprintf(stderr, "[Rdp] rfx_compose_message failed\n");
                return 0;
            }
            cmd.cmdType = CMDTYPE_STREAM_SURFACE_BITS;
            cmd.bmp.codecID = (UINT16)freerdp_settings_get_uint32(
                settings, FreeRDP_RemoteFxCodecId);
            cmd.bmp.bitmapDataLength = (UINT32)Stream_GetPosition(s->stream);
            cmd.bmp.bitmapData = Stream_Buffer(s->stream);
            ok = update->SurfaceBits(update->context, &cmd);
            break;
        }
        case CODEC_NSC: {
            Stream_SetPosition(s->stream, 0);
            if (!s->nsc || !nsc_compose_message(s->nsc, s->stream, rgba, w, h,
                                                w * 4)) {
                pthread_mutex_unlock(&s->peer_lock);
                fprintf(stderr, "[Rdp] nsc_compose_message failed\n");
                return 0;
            }
            // NSC goes as SET, not STREAM — weston makes the same
            // distinction, and a client entitled to be strict about it will
            // be.
            cmd.cmdType = CMDTYPE_SET_SURFACE_BITS;
            cmd.bmp.codecID =
                (UINT16)freerdp_settings_get_uint32(settings, FreeRDP_NSCodecId);
            cmd.bmp.bitmapDataLength = (UINT32)Stream_GetPosition(s->stream);
            cmd.bmp.bitmapData = Stream_Buffer(s->stream);
            ok = update->SurfaceBits(update->context, &cmd);
            break;
        }
        case CODEC_RAW:
        default: {
            // Uncompressed pixels differ from the codecs on three counts,
            // and all three are silent failures:
            //   - colour: 32bpp on the wire is BGRX, our frames are RGBX;
            //   - row order: bottom-up, where RemoteFX takes top-down;
            //   - SIZE: one whole frame is megabytes and a client will not
            //     accept a surface command larger than its own
            //     MultifragMaxRequestSize. It has to be cut into horizontal
            //     bands that fit — which is what weston does, and skipping
            //     it is why a full-frame raw update can arrive as nothing
            //     at all.
            const uint32_t maxreq = freerdp_settings_get_uint32(
                settings, FreeRDP_MultifragMaxRequestSize);
            const uint32_t row_bytes = w * 4;
            uint32_t band = maxreq > (row_bytes + 16)
                                ? (maxreq - 16) / row_bytes
                                : 1;
            if (band == 0) {
                band = 1;
            }
            if (band > h) {
                band = h;
            }

            cmd.cmdType = CMDTYPE_SET_SURFACE_BITS;
            cmd.bmp.codecID = RDP_CODEC_ID_NONE;
            cmd.skipCompression = TRUE;

            BYTE* scratch = Stream_Buffer(s->stream);
            if (Stream_Capacity(s->stream) < (size_t)band * row_bytes) {
                pthread_mutex_unlock(&s->peer_lock);
                fprintf(stderr, "[Rdp] raw scratch too small\n");
                return 0;
            }

            ok = 1;
            for (uint32_t top = 0; top < h && ok; top += band) {
                const uint32_t rows = (h - top < band) ? (h - top) : band;
                // Bottom-up within the band, BGRX as we go.
                for (uint32_t y = 0; y < rows; y++) {
                    const uint8_t* src = rgba + (size_t)(top + y) * row_bytes;
                    BYTE* dst = scratch + (size_t)(rows - 1 - y) * row_bytes;
                    for (uint32_t x = 0; x < row_bytes; x += 4) {
                        dst[x + 0] = src[x + 2];
                        dst[x + 1] = src[x + 1];
                        dst[x + 2] = src[x + 0];
                        dst[x + 3] = src[x + 3];
                    }
                }
                cmd.destTop = top;
                cmd.destBottom = top + rows;
                cmd.bmp.height = (UINT16)rows;
                cmd.bmp.bitmapDataLength = rows * row_bytes;
                cmd.bmp.bitmapData = scratch;
                ok = update->SurfaceBits(update->context, &cmd);
            }
            break;
        }
    }

    if (markers) {
        marker.frameAction = SURFACECMD_FRAMEACTION_END;
        update->SurfaceFrameMarker(update->context, &marker);
        s->frame_id++;
    }
    pthread_mutex_unlock(&s->peer_lock);

    if (!ok) {
        fprintf(stderr, "[Rdp] SurfaceBits failed\n");
    }
    return ok ? 1 : 0;
}
