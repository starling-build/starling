// Copyright the Starling authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Public C API for the DRM/KMS Flutter shell.
// This is the ONLY header Swift needs to import.

#ifndef FLUTTER_SHELL_PLATFORM_LINUX_DRM_FL_DRM_VIEW_H_
#define FLUTTER_SHELL_PLATFORM_LINUX_DRM_FL_DRM_VIEW_H_

#include <stdint.h>

#ifdef FLUTTER_LINUX_DRM_COMPILATION
#define FL_DRM_EXPORT __attribute__((visibility("default")))
#else
#define FL_DRM_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct FlDrmView FlDrmView;

// Opaque Flutter engine handle (matches embedder.h typedef).
typedef void* FlDrmFlutterEngine;

// Create a DRM view. Opens /dev/dri/card0 (or FLUTTER_DRM_DEVICE env),
// sets up GBM+EGL, starts libinput, initializes Flutter engine.
//
// |assets_path|        Path to flutter_assets directory.
// |icu_data_path|      Path to icudtl.dat.
// |runtime_controller|  Opaque RuntimeControllerInterface* for Swift mode.
//                       Pass NULL for standard Dart mode.
FL_DRM_EXPORT FlDrmView* fl_drm_view_create(const char* assets_path,
                                             const char* icu_data_path,
                                             void* runtime_controller);

// Run the event loop (blocks). Handles DRM page flips, libinput events,
// engine task scheduling. Returns when fl_drm_view_shutdown() is called
// or a fatal error occurs.
FL_DRM_EXPORT void fl_drm_view_run(FlDrmView* view);

// Request shutdown (safe to call from signal handler).
FL_DRM_EXPORT void fl_drm_view_shutdown(FlDrmView* view);

// Get display dimensions (pixels).
FL_DRM_EXPORT uint32_t fl_drm_view_get_width(FlDrmView* view);
FL_DRM_EXPORT uint32_t fl_drm_view_get_height(FlDrmView* view);

// Get the Flutter engine handle (for sending events, etc.)
FL_DRM_EXPORT FlDrmFlutterEngine fl_drm_view_get_engine(FlDrmView* view);

// Get an OpenGL/EGL function address (replaces glfwGetProcAddress for DRM mode).
FL_DRM_EXPORT void* fl_drm_view_get_proc_address(const char* name);

// Callback type for external texture population.
// Parameters: user_data, texture_id, width, height, texture_out.
// Returns true if the texture was populated.
typedef int (*FlDrmExternalTextureCallback)(void* user_data,
                                            int64_t texture_id,
                                            int width,
                                            int height,
                                            void* texture_out);

// Register an external texture frame callback. The DRM engine will call
// this when a registered external texture needs to be populated.
FL_DRM_EXPORT void fl_drm_view_set_external_texture_callback(
    FlDrmView* view,
    FlDrmExternalTextureCallback callback,
    void* user_data);

// Get the EGL display (for DMA-BUF import via eglCreateImageKHR).
FL_DRM_EXPORT void* fl_drm_view_get_egl_display(FlDrmView* view);

// Register an external fd to be polled in the DRM event loop.
// When the fd is readable, |callback| is called and a frame is scheduled.
// Call BEFORE fl_drm_view_run().
FL_DRM_EXPORT void fl_drm_view_add_external_fd(FlDrmView* view,
                                                int fd,
                                                void (*callback)(void* user_data),
                                                void* user_data);

// Run `fn` on the ENGINE PLATFORM thread (the epoll loop). Callable from any
// thread, any time after fl_drm_view_create; the closure runs on the next
// loop iteration. This is the runtime door onto the thread that
// fl_drm_view_add_output_view / fl_drm_view_set_primary_output require —
// the outputs-changed callback is the only other entry, and it fires only
// on hotplug. Returns 1 if queued, 0 if the trampoline is unavailable.
FL_DRM_EXPORT int fl_drm_view_post_task(FlDrmView* view,
                                        void (*fn)(void* user_data),
                                        void* user_data);

// Re-send window metrics with a new pixel ratio (for runtime DPI changes).
FL_DRM_EXPORT void fl_drm_view_send_metrics(FlDrmView* view,
                                             double pixel_ratio);

// ─── Injected pointer input ──────────────────────────────────────────────────
// Drive the pointer from something that is not a physical device — the RDP
// server today, any remote/automation source tomorrow. The event joins the
// SAME virtual-desktop pointer state libinput feeds, so it inherits pointer
// capture, view routing, region crossing and hardware-cursor placement; from
// the framework's seat there is no difference between this and a real mouse.
//
// |x|,|y| are PRIMARY-OUTPUT PHYSICAL pixels — the space an absolute
// libinput device maps into, and (for a client rendering the primary output
// at its native size) the RDP client's framebuffer coordinates 1:1.
// |buttons| is the ABSOLUTE Flutter button mask (1 primary, 2 secondary,
// 4 middle): report state, not transitions — down/up/move/hover phases are
// derived by diffing against the current mask. Wheel deltas are in Flutter's
// pixel units (a notch is ~20); pass 0 when not scrolling.
//
// Safe from ANY thread: the call marshals onto the engine platform thread
// through the post-task trampoline and returns immediately, so events are
// applied in submission order and never race the libinput handlers.
// The hardware cursor is moved to match — without which the sprite would
// stay put, and since screen capture composites that sprite, a remote
// viewer would watch a frozen pointer while the desktop responded normally.
FL_DRM_EXPORT void fl_drm_view_inject_pointer_abs(FlDrmView* view,
                                                   double x, double y,
                                                   int64_t buttons,
                                                   double wheel_dx,
                                                   double wheel_dy);

// Request a screenshot on the next frame. Sets the internal flag that
// causes glReadPixels to dump a PPM file in the present callback.
// Safe to call from any thread (uses atomic flag).
FL_DRM_EXPORT void fl_drm_view_request_screenshot(void);

// X11 screen capture (for the in-tree X server's GetImage → Zoom screen share).
// arm_capture: mark that a client wants pixels; captures the presented desktop
// into a CPU mirror for the next couple of frames and schedules a frame so an
// idle desktop still refreshes. Safe from any thread. read_capture: copy the
// screen rect [x,y,w,h] into dst as X ZPixmap depth-32 BGRX, top-down; returns
// 1 on success, 0 if no frame has been mirrored yet. dst_len must be >= w*h*4.
FL_DRM_EXPORT void fl_drm_view_arm_capture(FlDrmView* view);
FL_DRM_EXPORT int fl_drm_view_read_capture(int x, int y, int w, int h,
                                           uint8_t* dst, int dst_len);
// Non-zero while a GetImage client is actively capturing — the shell's
// frame-tick pump forces presents while this holds so the mirror refreshes.
FL_DRM_EXPORT int fl_drm_view_capture_active(void);

// ─── Screen recording ────────────────────────────────────────────────────────
// The shell's screen recorder. Every presented primary-output frame is
// captured asynchronously (GPU blit + PBO ring — the present path is never
// stalled) and delivered to the registered callback as top-down RGBA with a
// CLOCK_MONOTONIC microsecond timestamp. The hardware cursor is composited
// into the frame (it scans out on a cursor plane no GL readback can see).
//
// The callback fires on an internal writer thread — NOT the platform or UI
// thread — and the pixel buffer is only valid for the duration of the call.
// Copy it and get out; encoding belongs on the caller's own thread.
typedef void (*FlDrmRecordFrameCallback)(void* user_data,
                                         const uint8_t* rgba,
                                         uint32_t width,
                                         uint32_t height,
                                         uint64_t timestamp_us);
FL_DRM_EXPORT void fl_drm_view_set_record_frame_callback(
    FlDrmView* view,
    FlDrmRecordFrameCallback callback,
    void* user_data);

// Start/stop recording. Requests are consumed on the presenting thread at
// the next present, so both need frames to be flowing: the shell's
// frame-tick pump must run while recording AND until recording_active()
// reads 0 again after a stop, or the stop is never observed. Frames are
// full-resolution >> downscale_shift (0 = full, clamped to [0,3]). A start
// with no callback registered, or while a recording (either sink) is
// already running, is logged and ignored.
FL_DRM_EXPORT void fl_drm_view_recording_start(FlDrmView* view,
                                               int downscale_shift);
// Record a region instead of the whole output (window recording): the crop
// is top-down framebuffer px; w<=0 means full output. Output dimensions
// freeze at start — a crop that later moves/resizes (track it with
// set_crop, callable per frame from any thread) scales into them. The
// cursor is composited crop-relative.
FL_DRM_EXPORT void fl_drm_view_recording_start_cropped(FlDrmView* view,
                                                       int downscale_shift,
                                                       int x, int y,
                                                       int w, int h);
FL_DRM_EXPORT void fl_drm_view_recording_set_crop(int x, int y,
                                                  int w, int h);
// TRUE app capture: record an external texture (a window's own composited
// content, resolved per present through the compositor's texture callback)
// instead of the framebuffer. Overlapping windows and position never show;
// the resolve also refreshes dirty client textures, so content stays live
// even minimized. |w|,|h| freeze the output size (the source scales to
// fit). A present where the texture cannot be resolved delivers no frame.
// |content_top_down|: pass the window's flipTextureY — Wayland client
// buffers are top-down (1), first-party children render bottom-up into GL
// FBOs (0, blit flips).
//
// The cursor is composited when the pointer is over the window, which needs
// the window's on-screen rect — see set_window_rect. Starting a texture
// session clears that rect, so push one after starting or the recording
// has no pointer.
FL_DRM_EXPORT void fl_drm_view_recording_start_texture(FlDrmView* view,
                                                       int downscale_shift,
                                                       int64_t texture_id,
                                                       int w, int h,
                                                       int content_top_down);
// Where the recorded window's CONTENT (no title bar) currently sits on
// screen, CRTC px. A window-space capture has no other way to place the
// screen-space pointer, so this is what puts the cursor in an app
// recording — and keeps it right as the window is dragged or resized.
// Callable per frame from any thread; w<=0 means unknown, which leaves the
// cursor out rather than drawing it somewhere wrong.
FL_DRM_EXPORT void fl_drm_view_recording_set_window_rect(int x, int y,
                                                         int w, int h);
FL_DRM_EXPORT void fl_drm_view_recording_stop(FlDrmView* view);
// Non-zero while a callback-sink recording session is live on the raster
// thread (i.e. between the start request being consumed and the stop
// request finishing its drain). The SIGRTMIN+1 debug file recording does
// not show up here.
FL_DRM_EXPORT int fl_drm_view_recording_active(void);

// ─── Zero-copy recording (DMA-BUF sink) ──────────────────────────────────────
// Alternative frame delivery for hardware encoders: instead of reading the
// capture FBO back to the CPU, the engine blits into a small ring of
// GBM-allocated linear buffers and hands their DMA-BUF fds to this callback —
// pixels never leave the GPU. The cursor is drawn into the buffer on the GPU
// (the CPU sink blends it during readback packing).
//
// Contract, which differs from the CPU sink on every point that matters:
//   - Fires on the PRESENTING thread. Queue the frame and get out — any real
//     work here stalls the desktop's present path.
//   - The fd is owned by the engine and stays open for the life of the ring;
//     never close it. Import it (VAAPI DRM PRIME etc.) and encode.
//   - Each frame names a ring `slot`. The engine will not reuse the slot's
//     buffer until fl_drm_view_recording_release_dmabuf_slot(slot) — release
//     promptly (a stalled consumer makes the engine drop frames, and a slot
//     leaked across a stop blocks the next session's ring re-size). GPU-side
//     write-vs-read ordering across GL and the encoder rides the kernel's
//     implicit dma-buf fencing.
//   - A frame with fd == -1 (slot == -1) is the one-shot fallback sentinel:
//     the ring could not be built, the session continues with CPU frames to
//     the regular record-frame callback, and no dmabuf frames will follow.
//
// Delivery is opt-in per session: arm with recording_set_dmabuf(1) before
// recording_start*, and re-arm (or clear) before every start — the flag is
// consumed when the start is. Starting armed with no dmabuf callback
// registered falls back to CPU frames silently.
typedef struct {
  int32_t slot;          // ring slot to release; -1 on the fallback sentinel
  int32_t fd;            // engine-owned dmabuf fd; -1 on the fallback sentinel
  uint32_t width;        // frame size in pixels (buffer may be wider — stride)
  uint32_t height;
  uint32_t stride;       // bytes per row
  uint32_t offset;       // byte offset of the frame within the buffer
  uint32_t fourcc;       // DRM_FORMAT_ABGR8888: R,G,B,A bytes in memory
  uint64_t modifier;     // DRM format modifier (linear)
  uint64_t timestamp_us; // CLOCK_MONOTONIC, same clock as the CPU sink
} FlDrmRecordDmabufFrame;
typedef void (*FlDrmRecordDmabufCallback)(void* user_data,
                                          const FlDrmRecordDmabufFrame* frame);
FL_DRM_EXPORT void fl_drm_view_set_record_dmabuf_callback(
    FlDrmView* view,
    FlDrmRecordDmabufCallback callback,
    void* user_data);
FL_DRM_EXPORT void fl_drm_view_recording_set_dmabuf(int enable);
// Cap the CAPTURE rate, in frames/sec (0 = capture every present, the
// default). Read when a start request is consumed; set it before
// recording_start*. Without a cap the capture runs at the present rate —
// on a 90Hz output that is three full blits for every frame a 30fps
// encoder keeps, each of them in the present path — so a session that
// encodes at N fps should set N here and let presents inside the interval
// skip capture entirely. The consumer's own pacing still applies; this
// only removes the work for frames nobody would keep.
FL_DRM_EXPORT void fl_drm_view_recording_set_max_fps(int fps);
FL_DRM_EXPORT void fl_drm_view_recording_release_dmabuf_slot(int slot);

// App capture only: tell the recorder the RECORDED window just committed
// new content. Its pixels cannot change without one, so between commits the
// capture skips presents instead of encoding byte-identical frames — call
// this from wherever that window's texture is refreshed, from any thread.
// Missing a call costs at most a 0.3s keepalive frame, never a wrong
// duration; calling it too often merely restores the old behaviour.
FL_DRM_EXPORT void fl_drm_view_recording_notify_source_changed(void);

// Cursor shapes — must stay in sync with flutter::CursorShape.
typedef enum {
  FL_DRM_CURSOR_DEFAULT = 0,
  FL_DRM_CURSOR_RESIZE_NS = 1,
  FL_DRM_CURSOR_RESIZE_EW = 2,
  FL_DRM_CURSOR_RESIZE_NESW = 3,
  FL_DRM_CURSOR_RESIZE_NWSE = 4,
  FL_DRM_CURSOR_TEXT = 5,
  FL_DRM_CURSOR_POINTER = 6,
} FlDrmCursorShape;

// Swap the hardware cursor bitmap to the requested shape. No-op if the
// shape is already current. Safe to call from the UI thread.
FL_DRM_EXPORT void fl_drm_view_set_cursor_shape(FlDrmView* view,
                                                 int shape);

// Present (page-flip) notification — fired on the PLATFORM thread for EVERY
// output's flips, with the output index (fl_drm_view_get_output_info order),
// the kernel's scanout timestamp (CLOCK_MONOTONIC ns), that output's OWN
// refresh period, and `dropped` = 1 when frames were mailbox-dropped on this
// output since its last flip (secondary outputs drop instead of stalling the
// raster thread — see set_primary_output). Use it to pace Wayland frame
// callbacks / presentation feedback off each panel's real vsync; on dropped,
// ask the app to redraw that output — the dropped frame was newer than what
// the panel shows, and nothing else is in flight to correct it.
typedef void (*FlDrmOutputPresentCallback)(void* user_data,
                                           uint32_t output_index,
                                           uint64_t flip_time_ns,
                                           uint32_t refresh_ns,
                                           int dropped);
FL_DRM_EXPORT void fl_drm_view_set_output_present_callback(
    FlDrmView* view,
    FlDrmOutputPresentCallback cb,
    void* user_data);

// Display refresh rate in mHz (e.g. 30000 for a 30 Hz panel), from the
// active DRM mode. For wl_output.mode advertisement.
FL_DRM_EXPORT uint32_t fl_drm_view_get_refresh_mhz(FlDrmView* view);

// The primary output's scale, as the view resolved it at creation:
// $FLUTTER_DRM_DPI when that is set and non-empty, otherwise derived from the
// panel (EDID physical size when the connector reports one, pixel count when
// it does not). Read this instead of assuming a default — the shell's own
// coordinate conversion and every child app's scale follow from it.
FL_DRM_EXPORT double fl_drm_view_get_scale(FlDrmView* view);

// ─── Multi-output ────────────────────────────────────────────────────────────
// Number of connected outputs (each with its own swap chain). The implicit
// Flutter view (id 0) always renders to the primary output.
FL_DRM_EXPORT uint32_t fl_drm_view_get_output_count(FlDrmView* view);

// Info for output `index` (0..count-1). Out-pointers may be NULL. `name_buf`
// receives the connector name ("HDMI-A-1") truncated to name_buf_size.
// Returns 1 on success, 0 on a bad index.
FL_DRM_EXPORT int fl_drm_view_get_output_info(FlDrmView* view,
                                               uint32_t index,
                                               uint32_t* width,
                                               uint32_t* height,
                                               uint32_t* refresh_mhz,
                                               int* is_primary,
                                               char* name_buf,
                                               uint32_t name_buf_size);

// The scale the engine would pick for output `index`'s panel (EDID density
// when the connector reports it, pixel count otherwise) — the same derivation
// the primary's startup scale uses. Pure function of the panel; no state.
// The app seeds per-output layout scales from it instead of guessing without
// the EDID. Returns 1.0 on a bad index.
FL_DRM_EXPORT double fl_drm_view_get_output_derived_scale(FlDrmView* view,
                                                           uint32_t index);

// Create Flutter view `flutter_view_id` (unique, nonzero) rendering to output
// `index`, with the given pixel ratio. The app decides which outputs get
// views and what they show (via its multi-view content builder). Requires the
// compositor path (default). Returns 1 on success, 0 on failure.
FL_DRM_EXPORT int fl_drm_view_add_output_view(FlDrmView* view,
                                               uint32_t index,
                                               int64_t flutter_view_id,
                                               double pixel_ratio);

// Rebind the implicit view (id 0) to output `index` — the runtime "make this
// monitor the primary display" switch. The explicit view currently on that
// output (if any) is removed; the implicit view's swap chain, EGL surface,
// window metrics (the output's mode at `pixel_ratio`; <= 0 derives one from
// the panel), present-callback pacing, capture-hook target, and pointer
// region all move. The OLD primary keeps its scanout resources and shows its
// last frame until the app gives it an explicit view via
// fl_drm_view_add_output_view — which now succeeds for it — and re-runs its
// fl_drm_view_set_output_layout pass.
//
// MUST run on the ENGINE PLATFORM thread (FlutterEngineRemoveView's thread
// affinity): call it from the outputs-changed callback or through
// fl_drm_view_post_task. Refused while a recording session is active (the
// recorder's capture geometry is frozen against the current primary), on the
// legacy non-compositor path, and for dead or disabled outputs.
// Returns 1 on success, 0 on refusal.
FL_DRM_EXPORT int fl_drm_view_set_primary_output(FlDrmView* view,
                                                  uint32_t index,
                                                  double pixel_ratio);

// Place output `index` at (logical_x, logical_y) with `scale` in the global
// logical ("virtual desktop") pointer space. The pointer moves across placed
// outputs; events carry the owning Flutter view's id and view-local physical
// coordinates, and the hardware cursor follows onto that output's CRTC.
// Call for every output after adding its view (the primary defaults to
// (0,0) at FLUTTER_DRM_DPI). Outputs without a placement or view don't
// participate in pointer motion.
FL_DRM_EXPORT void fl_drm_view_set_output_layout(FlDrmView* view,
                                                  uint32_t index,
                                                  double logical_x,
                                                  double logical_y,
                                                  double scale);

// Invoked when the connected-output set changes (monitor hotplug): the
// engine has already enumerated the new output(s) and modeset them black.
// Runs on the ENGINE PLATFORM thread — deliberately, because that is the
// thread fl_drm_view_add_output_view (FlutterEngineAddView) must be called
// from once the engine is running. Query outputs, add views, and set the
// layout directly in the callback; marshal UI work to your main thread.
typedef void (*FlDrmOutputsChangedCallback)(void* user_data);
FL_DRM_EXPORT void fl_drm_view_set_outputs_changed_callback(
    FlDrmView* view,
    FlDrmOutputsChangedCallback callback,
    void* user_data);

// Destroy and free all resources. Restores original CRTC, closes DRM fd.
FL_DRM_EXPORT void fl_drm_view_destroy(FlDrmView* view);

#ifdef __cplusplus
}
#endif

#endif  // FLUTTER_SHELL_PLATFORM_LINUX_DRM_FL_DRM_VIEW_H_
