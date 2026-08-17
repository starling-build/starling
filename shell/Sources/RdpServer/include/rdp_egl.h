// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// rdp_egl.h — a GL context with no window system and no DRM device.
//
// This is what lets the desktop render where there is no KMS: WSL, a
// container, a cloud VM. EGL's surfaceless platform gives a context bound to
// no surface at all, the engine renders into an FBO we own, and the pixels
// leave through `rdp_egl_read_frame` instead of a page flip.
//
// Measured in WSL (docs/plans/rdp-wsl.md): surfaceless initialises on
// llvmpipe by default and on the real GPU with GALLIUM_DRIVER=d3d12. Nothing
// here selects a driver — that is Mesa's business and the session's env.
//
// Threading follows the embedder's GL contract: `make_current`/`read_frame`
// on the raster thread, `make_resource_current` on the engine's upload
// thread (a second context in the same sharegroup), and `get_proc_address`
// from anywhere.

#ifndef STARLING_RDP_EGL_H_
#define STARLING_RDP_EGL_H_

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct RdpEgl RdpEgl;

// Create the surfaceless display, the render and resource contexts, and the
// render target at |width| x |height|. Returns NULL if surfaceless EGL is
// unavailable — the caller should fall back to the software renderer rather
// than treat this as fatal.
RdpEgl* rdp_egl_create(uint32_t width, uint32_t height);
void rdp_egl_destroy(RdpEgl* e);

// Embedder GL callbacks. make_current also (re)builds the render target on
// first use, because an FBO needs a current context to exist.
int rdp_egl_make_current(RdpEgl* e);
int rdp_egl_clear_current(RdpEgl* e);
int rdp_egl_make_resource_current(RdpEgl* e);

// The FBO the engine renders into. Valid only with the context current.
uint32_t rdp_egl_fbo(RdpEgl* e);

void* rdp_egl_get_proc_address(const char* name);

// Read the rendered frame back as top-down RGBA, 4 bytes per pixel.
// |dst_len| must be >= width*height*4. Call with the context current, from
// the present callback. Returns 0 on a short buffer or GL error.
//
// GL's origin is bottom-left, so this flips as it reads — RDP wants
// top-down, and flipping here costs one pass over pixels we are already
// copying, rather than a second one downstream.
int rdp_egl_read_frame(RdpEgl* e, uint8_t* dst, size_t dst_len);

// Resize the render target (a client reconnecting at another size).
// Context must be current. Returns 0 on failure, leaving the old target.
int rdp_egl_resize(RdpEgl* e, uint32_t width, uint32_t height);

void rdp_egl_size(RdpEgl* e, uint32_t* width, uint32_t* height);

// GL_RENDERER, for the log line that tells an operator whether this session
// is on the GPU or on llvmpipe. Valid with the context current; may be NULL.
const char* rdp_egl_renderer(RdpEgl* e);

#ifdef __cplusplus
}
#endif

#endif  // STARLING_RDP_EGL_H_
