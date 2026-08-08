# A view rendered on the NVIDIA GPU

Goal: per-screen shells where each screen's shell is rendered — and recorded
— by one GPU, end to end. On this machine every connector is wired to the
AMD 680M, so an "NVIDIA screen" means: shell content rendered on the 3050,
presented through the AMD card. Explored 2026-08-08; nothing here is built
yet except the encoder ([nvenc], commit 54b4c64) and the app-level prior art
([swapchain], commit 7c47ded).

## Hard facts (probed on the dev box, RTX 3050 / driver 595.84)

1. **NVIDIA renders into linear dma-bufs** only via a gbm_surface
   swapchain (`RENDERING|LINEAR`, eglSwapBuffers detiles; front buffer is
   modifier 0x0). Direct render-to-linear through EGLImage FBOs is refused.
   Proven at app scale by GpuDmaBufRenderer's swapchain mode.
2. **AMD imports NVIDIA linear buffers as GL textures** — explicit LINEAR
   and implicit modifier both sample correctly.
3. **AMD cannot scan out NVIDIA buffers.** `drmPrimeFDToHandle` on card2
   succeeds, but `drmModeAddFB2` (with and without modifiers) returns
   EINVAL — amdgpu refuses KMS framebuffers over foreign dma-bufs. So a
   presentation blit on the AMD GPU is mandatory, exactly as in upstream
   PRIME render offload. There is no zero-AMD-cost path to the CRTC.
4. **The reverse import (AMD buffer into NVIDIA EGL) binds only as
   `GL_TEXTURE_EXTERNAL_OES`** — TEXTURE_2D bind fails. Skia can sample
   external textures (the NV12 video path already does), so an NV-side
   compositor of AMD-client windows is possible but external-target-only.
5. **NVENC encodes NVIDIA-resident buffers zero-copy** via EGL interop
   (`eglCreateImageKHR` → `cuGraphicsEGLRegisterImage`);
   `cuImportExternalMemory(OPAQUE_FD)` rejects gbm dma-bufs (999).

## What the embedder is today (see the multi-view map, 2026-08-08)

- One `FlDrmDisplay` (one DRM fd), one `FlDrmGbm`, one `FlDrmEgl` — one
  render context on the scanout GPU; every view rasters sequentially on the
  engine's single raster thread (`CompositorPresentView` →
  `glBlitFramebuffer` into the output's gbm_surface window surface →
  `FlDrmSwapChain::Present` → `drmModeAddFB` + page flip).
- Views are per-connector; secondaries are real `FlutterEngineAddView`
  views created by the Swift side (`syncEngineViewsAndLayout`).
- Nothing in-tree ever imports an fd as a KMS framebuffer; imported
  dma-bufs become GL textures on the one AMD EGL display, full stop.
- The recording ring is process-global and captures the primary output
  only.
- A second in-process `FlutterEngine` is blocked by a long list of
  singletons: embedder statics (VT/signal handlers, `g_seat_ptr`, the
  recording ring and `g_api_record_*` atomics, view-less C entry points),
  `fl_drm_view_run` being the process main loop, and the Swift side's
  single `engine`/`drmViewHandle`/`runApp` — plus the Swift framework's
  own singletons (`PlatformDispatcher.instance`).

## Design: three stages, each independently useful

### Stage A — the "imported view" (engine, small, enables everything)

Teach the embedder that an output's content can come from OUTSIDE:

- New per-output mode: instead of rastering a Flutter view for output N,
  accept a stream of linear dma-buf fds (fd, stride, fourcc, release
  callback). Present path: EGLImage import on the existing AMD display
  (cached per bo, same ino-keyed pattern as everywhere else) → fullscreen
  textured quad into that output's existing gbm_surface/EGL surface →
  existing `FlDrmSwapChain::Present`. Release the producer's previous
  buffer on flip completion (same hold-newest-two discipline as the app
  swapchain; explicit sync later via EGL_ANDROID_native_fence if tearing
  is ever observed — implicit sync has been sufficient for the app path).
- C API sketch: `fl_drm_view_set_output_external(view, output_id, on/off)`
  + `fl_drm_view_push_external_frame(view, output_id, fd, stride, fourcc)`.
- Per-output recording tap: for an external output, recording duplicates
  the incoming fds — which are NVIDIA-resident — straight into
  NvencEncoder. The RecordingService already selects the encoder by
  device; this makes the ring per-output for external views and satisfies
  the recording doctrine with no extra copies.

### Stage B — the per-screen shell as a swapchain child (shell, mostly reuse)

Run the NVIDIA screen's shell UI as a dedicated first-party process using
the PROVEN GpuDmaBufRenderer swapchain on `renderD128`, fullscreen at the
output's size, its fd stream routed into Stage A's imported view instead
of a window texture. The compositor (Wayland/X11/window state) stays in
the main process — "one compositor, multiple shells".

- Input: the per-output input regions already tag events with the view;
  route that view's events over the existing child socket protocol.
- Windows on the NV screen: client buffers live in the compositor; forward
  their fds to the screen-shell, which imports them — NV-native app
  buffers as TEXTURE_2D, AMD-client buffers as EXTERNAL_OES (fact 4). The
  cleaner policy is affinity: apps launched on the NV screen render on the
  NV GPU (`STARLING_APP_DRM_DEVICE`), making the whole screen's content
  chain NV-native.
- This stage delivers the user-visible feature (an NVIDIA-rendered,
  NVENC-recorded screen) with the process boundary as scaffolding.

### Stage C — fold in-process (the stated end state)

Replace the Stage B process with a second engine instance in the shell
process ("separate engine views within the one shell process"). The audit
list from the map is the work plan: de-globalize the embedder statics
(signals, VT, seat, ring, capture atomics → per-instance), add a
render-only engine mode (no DRM master, no seat, no input, no hotplug —
those remain with the primary), give it its own UI loop thread, and scope
the Swift framework's singletons per engine. The external-frame protocol
from Stage A is unchanged — Stage C only moves the producer in-process,
so nothing above it (recording, presentation, input routing) changes.

## Open questions

- Fence discipline for A: start with implicit sync + hold-two; measure.
- HiDPI: the imported view is at physical resolution; the screen-shell
  child must receive the output's scale (the DPI plumbing exists in the
  child protocol).
- Cursor: stays on the AMD hardware cursor plane for all outputs —
  unaffected by who renders the screen, and deliberately NOT part of the
  screen's recorded content today (matches current primary recording).
- Power: the 3050 idles in D3cold; a permanent NV screen keeps it awake.
  Fine for desktops, a real battery cost on this laptop.
