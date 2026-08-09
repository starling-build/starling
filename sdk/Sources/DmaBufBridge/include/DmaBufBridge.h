// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// DMA-BUF helpers for cross-process GPU buffer sharing on Linux.
// Wraps GBM, SCM_RIGHTS fd passing, and EGL DMA-BUF import.

#ifndef DMABUF_BRIDGE_H_
#define DMABUF_BRIDGE_H_

#include <gbm.h>
#include <stddef.h>
#include <stdint.h>
#include <unistd.h>

#ifdef __cplusplus
extern "C" {
#endif

// ─── SCM_RIGHTS fd passing ──────────────────────────────────────────────────
// The CMSG_* macros cannot be imported into Swift directly.

/// Send a file descriptor over a Unix domain socket via SCM_RIGHTS.
/// |meta| and |meta_len| carry an optional metadata payload alongside the fd.
/// Returns 0 on success, -1 on error (errno set).
int dmabuf_send_fd(int socket, int fd, const void* meta, size_t meta_len);

/// Receive a file descriptor from a Unix domain socket via SCM_RIGHTS.
/// |meta| and |meta_len| receive the metadata payload.
/// Returns the received fd on success, -1 on error (errno set).
int dmabuf_recv_fd(int socket, void* meta, size_t meta_len);

/// Receive data from a Unix domain socket, optionally receiving an fd via
/// SCM_RIGHTS.  Uses recvmsg() so both regular data and ancillary data are
/// handled in a single call.
/// |buf|/|buf_len|: buffer for regular data (frame signals, metadata, etc.)
/// |out_fd|: set to received fd (>= 0) if SCM_RIGHTS present, else -1.
/// Returns bytes read (0 = EOF, -1 = error).
ssize_t dmabuf_recv_with_fd(int socket, void* buf, size_t buf_len,
                            int* out_fd);

// ─── EGL DMA-BUF import ─────────────────────────────────────────────────────

/// Check if the EGL display supports EGL_EXT_image_dma_buf_import.
/// Returns 1 if supported, 0 if not.
int dmabuf_check_egl_support(void* egl_display);

/// Import a DMA-BUF fd as an EGLImage.
/// If modifier != DRM_FORMAT_MOD_INVALID, includes modifier attributes.
/// Returns the EGLImage handle (cast to void*), or NULL on failure.
void* dmabuf_import_egl_image(void* egl_display, int fd,
                              int width, int height, int stride,
                              uint32_t fourcc);

/// Import a DMA-BUF fd as an EGLImage with explicit DRM format modifier.
/// Returns the EGLImage handle (cast to void*), or NULL on failure.
void* dmabuf_import_egl_image_with_modifier(void* egl_display, int fd,
                                             int width, int height, int stride,
                                             uint32_t fourcc, uint64_t modifier);

/// Bind an EGLImage to the currently bound GL_TEXTURE_2D target.
/// Calls glEGLImageTargetTexture2DOES.
void dmabuf_bind_texture(void* egl_image);

/// Query the DRM modifiers this EGL display can import for `fourcc`
/// (EGL_EXT_image_dma_buf_import_modifiers). Fills up to `max` entries in
/// `modifiers` and returns the count, or 0 if the extension is missing or
/// the format is unsupported.
int dmabuf_query_modifiers(void* egl_display, uint32_t fourcc,
                           uint64_t* modifiers, int max);

/// Blit an EGLImage-backed texture into an output texture with vertical flip.
/// Creates a temporary FBO, binds the EGLImage as source, reads pixels with
/// glReadPixels, then uploads to output_tex with rows reversed.
/// This is needed because Wayland client buffers have top-left origin but the
/// Flutter engine assumes kBottomLeft_GrSurfaceOrigin for external textures.
/// Returns 1 on success, 0 on failure.
int dmabuf_blit_flipped_180(void* egl_image, uint32_t output_tex,
                            int width, int height);

/// Destroy an EGLImage created by dmabuf_import_egl_image.
void dmabuf_destroy_egl_image(void* egl_display, void* egl_image);

// ─── DMA-BUF metadata ──────────────────────────────────────────────────────

/// Metadata sent alongside the DMA-BUF fd.
struct DmaBufMeta {
    int32_t width;
    int32_t height;
    int32_t stride;
    uint32_t fourcc;
};

// ─── Parent → child input events ────────────────────────────────────────────

/// Input event sent from parent process to child over the Unix domain socket.
/// Fields are ordered for natural alignment (no padding).
#define DMABUF_INPUT_POINTER    0x01
#define DMABUF_INPUT_RESIZE     0x02
#define DMABUF_CONFIGURE        0x03
#define DMABUF_CONTROL_SET_DPI  0x04
#define DMABUF_INPUT_KEY        0x05
/* Appearance change (either direction): x = 1 dark, 0 light. */
#define DMABUF_CONTROL_SET_THEME 0x06
/* Mouse-wheel scroll: x/y = pointer position (logical px); buttons packs
 * the deltas as two Float32 bit patterns (dx low, dy high), logical px. */
#define DMABUF_INPUT_SCROLL     0x07
/* Window-manager layout (either direction): x = 1 tiling, 0 floating. */
#define DMABUF_CONTROL_SET_LAYOUT 0x09
/* Desktop wallpaper preset (either direction): x = the preset's raw value.
 * The shell owns the enum; children treat it as an opaque small integer. */
#define DMABUF_CONTROL_SET_WALLPAPER 0x0a
/* Screensaver idle timeout (either direction): x = seconds of no input
 * before the screensaver appears, 0 = never. */
#define DMABUF_CONTROL_SET_SCREENSAVER 0x0b
/* Caret rect report (child→parent): x/y = caret top-left in the child's
 * logical content coordinates; buttons packs width (low Float32) and
 * height (high Float32); phase = 1 caret visible / 0 hidden. Drives the
 * shell's IME candidate panel placement. */
#define DMABUF_CARET            0x08
/* Primary-display pick (child→parent): x = the display's output id, as the
 * shell reported it in DMABUF_DISPLAY_INFO. */
#define DMABUF_CONTROL_SET_PRIMARY_DISPLAY 0x0c
/* One connected display (parent→child), sent as a run: the whole list is
 * re-sent whenever it changes, and at connect. `phase` packs the output's
 * position in the run as (index << 16) | count — index 0 starts a fresh list
 * and index count-1 completes it, so a child never shows a half-built one.
 *   x       = physical width in device pixels
 *   y       = physical height in device pixels
 *   buttons = output id in bits 0..15, primary flag in bit 16,
 *             Float32 scale bit pattern in bits 32..63
 * The name arrives ahead of it in DMABUF_DISPLAY_NAME chunks. */
#define DMABUF_DISPLAY_INFO     0x0d
/* Eight bytes of the connector name for the display DMABUF_DISPLAY_INFO is
 * about to describe (parent→child): x = chunk index, buttons = the bytes,
 * low byte first, NUL-padded. Connector names run to 32 bytes ("Virtual-1",
 * "HDMI-A-1"), which does not fit one payload. */
#define DMABUF_DISPLAY_NAME     0x0e

/// Configure message sent from parent to child before the child creates its
/// buffer. Tells the child the content area dimensions (logical pixels).
struct DmaBufConfigure {
    int32_t width;
    int32_t height;
    int32_t type;       // DMABUF_CONFIGURE
    int32_t _reserved;
};

// ─── Window stream (shell → per-screen shell) ───────────────────────────────
// A second socket (FLUTTER_WINDOW_STREAM_SOCKET) carrying the windows that
// overlap an externally sourced output: fixed-size messages, FRAME ones with
// the buffer fd attached via SCM_RIGHTS (docs/plans/nv-view.md Stage B).

/* New buffer for the window — fd attached. Sent on first sight, on every
 * swapchain frame (each frame is a fresh dma-buf), and on resize. */
#define DMABUF_WINSTREAM_FRAME  1
/* Placement/stacking update, no fd; buffer fields are ignored. */
#define DMABUF_WINSTREAM_PLACE  2
/* Content changed in place, no fd: single-bo apps repaint their one buffer
 * and only signal — the importer re-samples the buffer it already holds. */
#define DMABUF_WINSTREAM_DAMAGE 3
/* The window no longer overlaps this output; drop its texture. No fd. */
#define DMABUF_WINSTREAM_REMOVE 4
/* Eight bytes of the window's TITLE (UTF-8, low byte first, NUL-padded),
 * sent as a run: z = chunk index (0 starts a fresh title), buf_w = total
 * byte length, modifier carries the bytes. Re-sent whole when it changes. */
#define DMABUF_WINSTREAM_TITLE  5

/* Window flag bits (FRAME / PLACE). */
#define DMABUF_WINFLAG_FOCUSED  0x1

struct DmaBufWindowStreamMsg {
    int32_t kind;         // DMABUF_WINSTREAM_*
    int32_t window;       // shell window key, stable for the window's life
    float x, y, w, h;     // CONTENT placement, output-local LOGICAL px
    int32_t z;            // stacking order, bottom = 0 (TITLE: chunk index)
    uint32_t flags;       // DMABUF_WINFLAG_*             (FRAME, PLACE)
    int32_t buf_w, buf_h; // buffer size in pixels (FRAME; TITLE: total len)
    int32_t stride;       // bytes per row                (FRAME)
    uint32_t fourcc;      // DRM format                   (FRAME)
    uint64_t modifier;    // DRM modifier (FRAME); title bytes (TITLE)
};

struct DmaBufInputEvent {
    double x;           // x coord (POINTER) / new width (RESIZE) / physical HID key (KEY)
    double y;           // y coord (POINTER) / new height (RESIZE) / logical keysym (KEY)
    int64_t buttons;    // FlutterPointerMouseButtons mask (POINTER) / Unicode scalar or 0 (KEY)
    int32_t type;       // DMABUF_INPUT_* event type
    int32_t phase;      // FlutterPointerPhase (POINTER) / 0=down 1=up (KEY)
};

// ─── EGL context management (headless, render node) ─────────────────────

/// Create an EGL display from a GBM device (GBM_MESA platform).
/// Returns EGLDisplay, or NULL on failure.
void* dmabuf_egl_create_display(struct gbm_device* gbm_dev);

/// Initialize EGL display. Returns 1 on success, 0 on failure.
int dmabuf_egl_initialize(void* egl_display);

/// Choose an EGL config suitable for offscreen Skia rendering.
/// Requires GLES2, stencil=8, RGBA8888. Returns config, or NULL.
void* dmabuf_egl_choose_config(void* egl_display);

/// Create an EGL context (GLES2). If share_context is non-NULL, resources
/// are shared (needed for resource context). Returns context, or NULL.
void* dmabuf_egl_create_context(void* egl_display, void* config,
                                void* share_context);

/// Make context current with no surface (surfaceless rendering).
int dmabuf_egl_make_current(void* egl_display, void* context);

/// Clear (unbind) the current context.
int dmabuf_egl_clear_current(void* egl_display);

/// Call eglGetProcAddress. Returns function pointer.
void* dmabuf_egl_get_proc_address(const char* name);

// ─── EGL window surface on a gbm_surface (swapchain mode) ──────────────
//
// The path for GPUs whose driver cannot render into a linear dma-buf via an
// EGLImage FBO (NVIDIA): render to an EGL window surface on a gbm_surface
// created with GBM_BO_USE_LINEAR, and eglSwapBuffers produces a linear
// front buffer to lock and export.

/// Choose a window-bit GLES2 config whose EGL_NATIVE_VISUAL_ID equals
/// |fourcc| (a GBM_FORMAT_* value) — GBM refuses mismatched visuals.
/// Returns config, or NULL if the driver exposes none for this format.
void* dmabuf_egl_choose_window_config(void* egl_display, uint32_t fourcc);

/// Create an EGL window surface on a gbm_surface. Returns EGLSurface or NULL.
void* dmabuf_egl_create_window_surface(void* egl_display, void* config,
                                       struct gbm_surface* gbm_surface);

/// Make context current with |egl_surface| as draw+read surface.
int dmabuf_egl_make_current_surface(void* egl_display, void* context,
                                    void* egl_surface);

/// eglSwapBuffers on the surface. Returns 1 on success.
int dmabuf_egl_swap_buffers(void* egl_display, void* egl_surface);

/// Destroy an EGL surface (NULL is a no-op).
void dmabuf_egl_destroy_surface(void* egl_display, void* egl_surface);

/// Ordinary FBO (RGBA8 + stencil renderbuffers, no dma-buf) the engine
/// renders into in swapchain mode; present() blits it Y-flipped onto the
/// window surface. Returns FBO name, 0 on failure. Needs a current context.
uint32_t dmabuf_create_plain_fbo(int width, int height,
                                 uint32_t* out_color_rb,
                                 uint32_t* out_stencil_rb);

/// Delete a plain FBO and its renderbuffers (0s are no-ops).
void dmabuf_destroy_plain_fbo(uint32_t fbo, uint32_t color_rb,
                              uint32_t stencil_rb);

/// Blit src_fbo onto the current window surface (fbo 0) with Y inverted.
/// Returns 1 on success, 0 if glBlitFramebuffer is unavailable.
int dmabuf_blit_flip_to_window(uint32_t src_fbo, int width, int height);

/// Call glFinish (ensure GPU commands complete — blocks CPU).
void dmabuf_gl_finish(void);

/// Call glFlush (submit GPU commands without blocking CPU).
void dmabuf_gl_flush(void);

/// Clear the current FBO to black (RGBA 0,0,0,1).
void dmabuf_gl_clear_black(void);

/// Dump the current FBO's pixels to a PPM file (diagnostic).
void dmabuf_gl_dump_fbo(int width, int height, const char* path);

/// Log the current GL viewport and FBO binding to stderr (diagnostic).
void dmabuf_gl_log_state(void);

// ─── Offscreen FBO backed by GBM BO ────────────────────────────────────

/// Create an offscreen FBO with:
///   - Color attachment: GL texture backed by GBM BO (via EGLImage from DMA-BUF fd)
///   - Stencil attachment: renderbuffer (GL_STENCIL_INDEX8)
/// Returns FBO name on success, 0 on failure.
/// |out_egl_image| receives the EGLImage handle (caller must destroy).
/// |out_color_tex| receives the GL texture name.
/// |out_stencil_rb| receives the stencil renderbuffer name.
uint32_t dmabuf_create_fbo(void* egl_display, int dma_fd,
                           int width, int height, int stride,
                           uint32_t fourcc,
                           void** out_egl_image,
                           uint32_t* out_color_tex,
                           uint32_t* out_stencil_rb);

/// Destroy FBO and associated GL/EGL resources.
void dmabuf_destroy_fbo(void* egl_display, uint32_t fbo,
                        void* egl_image, uint32_t color_tex,
                        uint32_t stencil_rb);

// ─── GPU texture copy (compositor buffer independence) ──────────────────

// ─── GL texture helpers (for external texture API) ─────────────────────

/// Generate a single GL texture name.
uint32_t dmabuf_gen_gl_texture(void);

/// Delete a GL texture name.
void dmabuf_delete_gl_texture(uint32_t tex);

/// Import a DMA-BUF as a GL_TEXTURE_2D with linear filtering.
/// Creates texture, imports EGLImage, binds, sets filter params.
/// Returns texture name on success, 0 on failure.
/// out_egl_image receives the EGLImage (caller must destroy).
uint32_t dmabuf_import_as_gl_texture(void* egl_display, int fd,
                                      int width, int height, int stride,
                                      uint32_t fourcc, uint64_t modifier,
                                      void** out_egl_image);

/// Rebind an EGLImage to an existing GL texture.
void dmabuf_rebind_gl_texture(uint32_t tex, void* egl_image);

/// GL_TEXTURE_EXTERNAL_OES — the target an NV12 image must be sampled
/// through. Exposed so Swift can hand it to the embedder as the external
/// texture's target without redeclaring the constant.
#define DMABUF_GL_TEXTURE_EXTERNAL_OES 0x8D65u

/// Import a two-plane NV12 DMA-BUF (both planes in ONE buffer, at their own
/// offsets — what a VA-API decoder hands back) as an EGLImage.
///
/// Kept apart from the single-plane import rather than folded into it: the
/// planes carry different formats and pitches, the result is only samplable
/// through GL_TEXTURE_EXTERNAL_OES, and the driver — not us — does the
/// YUV→RGB conversion and detiles it. Decoded surfaces are tiled, not linear
/// (radeonsi returns modifier 0x2000000104…), so there is no CPU-readable
/// layout here to fall back on. NULL on failure.
void* dmabuf_import_nv12_egl_image(void* egl_display, int fd,
                                    int width, int height, uint64_t modifier,
                                    uint32_t offset0, uint32_t pitch0,
                                    uint32_t offset1, uint32_t pitch1);

/// Bind an EGLImage to a texture through GL_TEXTURE_EXTERNAL_OES, creating
/// the texture when |tex| is 0. Returns the texture name, or 0 on failure.
///
/// A texture object's target is fixed by its first bind, so a name already
/// used as GL_TEXTURE_2D cannot be reused here — pass 0 (and delete the old
/// name) when switching a texture from the RGBA path to this one.
uint32_t dmabuf_bind_external_texture(uint32_t tex, void* egl_image);


/// Upload CPU RGBA pixels into a GL texture (creating it when |tex| is 0).
/// The CPU-pixel counterpart of dmabuf_import_as_gl_texture, for content
/// decoded in ordinary memory — e.g. video frames read from a pipe.
/// Rows must be tightly packed (stride == width * 4). Requires a current
/// GL context (call on the raster thread). Returns the texture name, or 0
/// on failure.
///
/// |reuse_storage| refills the existing allocation (glTexSubImage2D) instead
/// of allocating a fresh one (glTexImage2D); the caller passes it only when
/// |tex| is already allocated at exactly this width and height. Video runs
/// this once per frame, and allocating a multi-megabyte texture 30 times a
/// second — orphaning the one before it each time — degrades: the driver's
/// allocator falls further and further behind, the upload gets slower, and a
/// player that started clean is dropping frames minutes later.
uint32_t dmabuf_upload_rgba_texture(uint32_t tex, int width, int height,
                                     int reuse_storage,
                                     const uint8_t* pixels);

// ─── GPU texture copy (compositor buffer independence) ──────────────────

/// GPU-copy an EGLImage-backed source texture to an independent destination
/// texture using glBlitFramebuffer. After this call, the destination texture
/// owns the pixel data and the source DMA-BUF can be safely released.
///
/// |src_tex|: GL texture with EGLImage bound (from dmabuf_bind_texture).
/// |dst_tex|: GL texture to receive the copy. Will be (re)allocated to
///            width x height RGBA8 if current size doesn't match.
/// |width|, |height|: dimensions in pixels.
/// Returns 1 on success, 0 on failure.
int dmabuf_gpu_copy_texture(uint32_t src_tex, uint32_t dst_tex,
                            int width, int height);

#ifdef __cplusplus
}
#endif

#endif  // DMABUF_BRIDGE_H_
