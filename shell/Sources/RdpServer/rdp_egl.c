// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// rdp_egl.c — surfaceless EGL render target (see rdp_egl.h).

#include "include/rdp_egl.h"

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>

struct RdpEgl {
    EGLDisplay dpy;
    EGLConfig cfg;
    EGLContext render_ctx;
    EGLContext resource_ctx;  // same sharegroup, for the engine's uploads
    GLuint fbo;
    GLuint tex;
    GLuint depth_rb;
    uint32_t width, height;
    int target_built;
    uint8_t* flip_row;  // scratch for the bottom-up → top-down flip
    size_t flip_row_len;
};

static int build_target(RdpEgl* e) {
    if (e->fbo) {
        glDeleteFramebuffers(1, &e->fbo);
        e->fbo = 0;
    }
    if (e->tex) {
        glDeleteTextures(1, &e->tex);
        e->tex = 0;
    }
    if (e->depth_rb) {
        glDeleteRenderbuffers(1, &e->depth_rb);
        e->depth_rb = 0;
    }

    glGenTextures(1, &e->tex);
    glBindTexture(GL_TEXTURE_2D, e->tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, (GLsizei)e->width,
                 (GLsizei)e->height, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    glGenFramebuffers(1, &e->fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, e->fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
                           e->tex, 0);

    // Skia wants a stencil buffer for clipping; without one, complex clips
    // silently degrade rather than fail, which is worse than paying for it.
    glGenRenderbuffers(1, &e->depth_rb);
    glBindRenderbuffer(GL_RENDERBUFFER, e->depth_rb);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8_OES,
                          (GLsizei)e->width, (GLsizei)e->height);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT,
                              GL_RENDERBUFFER, e->depth_rb);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT,
                              GL_RENDERBUFFER, e->depth_rb);

    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (status != GL_FRAMEBUFFER_COMPLETE) {
        fprintf(stderr, "[RdpEgl] framebuffer incomplete (0x%x) at %ux%u\n",
                status, e->width, e->height);
        return 0;
    }
    e->target_built = 1;
    return 1;
}

RdpEgl* rdp_egl_create(uint32_t width, uint32_t height) {
    if (width == 0 || height == 0) {
        return NULL;
    }
    const char* client_exts = eglQueryString(EGL_NO_DISPLAY, EGL_EXTENSIONS);
    if (!client_exts || !strstr(client_exts, "EGL_MESA_platform_surfaceless")) {
        fprintf(stderr, "[RdpEgl] EGL_MESA_platform_surfaceless unavailable\n");
        return NULL;
    }
    PFNEGLGETPLATFORMDISPLAYEXTPROC get_platform_display =
        (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress(
            "eglGetPlatformDisplayEXT");
    if (!get_platform_display) {
        fprintf(stderr, "[RdpEgl] no eglGetPlatformDisplayEXT\n");
        return NULL;
    }

    RdpEgl* e = calloc(1, sizeof(RdpEgl));
    if (!e) {
        return NULL;
    }
    e->width = width;
    e->height = height;

    e->dpy = get_platform_display(EGL_PLATFORM_SURFACELESS_MESA,
                                  EGL_DEFAULT_DISPLAY, NULL);
    if (e->dpy == EGL_NO_DISPLAY) {
        fprintf(stderr, "[RdpEgl] surfaceless eglGetPlatformDisplay failed\n");
        goto fail;
    }
    EGLint major = 0, minor = 0;
    if (!eglInitialize(e->dpy, &major, &minor)) {
        fprintf(stderr, "[RdpEgl] eglInitialize failed (0x%x)\n", eglGetError());
        goto fail;
    }
    if (!eglBindAPI(EGL_OPENGL_ES_API)) {
        fprintf(stderr, "[RdpEgl] eglBindAPI(ES) failed\n");
        goto fail;
    }

    // PBUFFER_BIT, not WINDOW_BIT: there is no window to be a surface of.
    // Rendering goes to our FBO either way.
    const EGLint cfg_attribs[] = {EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
                                  EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
                                  EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8,
                                  EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
                                  EGL_NONE};
    EGLint n = 0;
    if (!eglChooseConfig(e->dpy, cfg_attribs, &e->cfg, 1, &n) || n < 1) {
        fprintf(stderr, "[RdpEgl] no usable EGLConfig\n");
        goto fail;
    }

    const EGLint ctx_attribs[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE};
    e->render_ctx =
        eglCreateContext(e->dpy, e->cfg, EGL_NO_CONTEXT, ctx_attribs);
    if (e->render_ctx == EGL_NO_CONTEXT) {
        fprintf(stderr, "[RdpEgl] eglCreateContext failed (0x%x)\n",
                eglGetError());
        goto fail;
    }
    // Shares with the render context so uploaded textures are visible to it.
    e->resource_ctx =
        eglCreateContext(e->dpy, e->cfg, e->render_ctx, ctx_attribs);
    if (e->resource_ctx == EGL_NO_CONTEXT) {
        // Not fatal: the engine treats make_resource_current failure as
        // "no async uploads", which costs performance, not correctness.
        fprintf(stderr, "[RdpEgl] no resource context (uploads stay inline)\n");
    }

    fprintf(stderr, "[RdpEgl] surfaceless EGL %d.%d at %ux%u\n", major, minor,
            width, height);
    return e;

fail:
    if (e->dpy != EGL_NO_DISPLAY) {
        eglTerminate(e->dpy);
    }
    free(e);
    return NULL;
}

void rdp_egl_destroy(RdpEgl* e) {
    if (!e) {
        return;
    }
    eglMakeCurrent(e->dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    if (e->resource_ctx != EGL_NO_CONTEXT) {
        eglDestroyContext(e->dpy, e->resource_ctx);
    }
    if (e->render_ctx != EGL_NO_CONTEXT) {
        eglDestroyContext(e->dpy, e->render_ctx);
    }
    eglTerminate(e->dpy);
    free(e->flip_row);
    free(e);
}

int rdp_egl_make_current(RdpEgl* e) {
    if (!e) {
        return 0;
    }
    if (!eglMakeCurrent(e->dpy, EGL_NO_SURFACE, EGL_NO_SURFACE,
                        e->render_ctx)) {
        fprintf(stderr, "[RdpEgl] make_current failed (0x%x)\n", eglGetError());
        return 0;
    }
    // First current: the FBO can only be built now, and this is the first
    // moment GL_RENDERER can be asked. Log it — "is this session on the GPU
    // or on llvmpipe" is the first question anyone debugging performance
    // has, and in WSL the answer is llvmpipe unless GALLIUM_DRIVER=d3d12 is
    // set, with nothing else to hint at it.
    if (!e->target_built) {
        const char* r = (const char*)glGetString(GL_RENDERER);
        const char* v = (const char*)glGetString(GL_VERSION);
        fprintf(stderr, "[RdpEgl] renderer: %s | %s\n", r ? r : "?",
                v ? v : "?");
        if (!build_target(e)) {
            return 0;
        }
    }
    return 1;
}

int rdp_egl_clear_current(RdpEgl* e) {
    if (!e) {
        return 0;
    }
    return eglMakeCurrent(e->dpy, EGL_NO_SURFACE, EGL_NO_SURFACE,
                          EGL_NO_CONTEXT)
               ? 1
               : 0;
}

int rdp_egl_make_resource_current(RdpEgl* e) {
    if (!e || e->resource_ctx == EGL_NO_CONTEXT) {
        return 0;
    }
    return eglMakeCurrent(e->dpy, EGL_NO_SURFACE, EGL_NO_SURFACE,
                          e->resource_ctx)
               ? 1
               : 0;
}

uint32_t rdp_egl_fbo(RdpEgl* e) { return e ? e->fbo : 0; }

void* rdp_egl_get_proc_address(const char* name) {
    void* p = (void*)eglGetProcAddress(name);
    if (p) {
        return p;
    }
    // eglGetProcAddress is not required to resolve core GL entry points on
    // every driver; fall back to the library itself.
    static void* gles = NULL;
    if (!gles) {
        gles = dlopen("libGLESv2.so.2", RTLD_LAZY | RTLD_LOCAL);
        if (!gles) {
            gles = dlopen("libGLESv2.so", RTLD_LAZY | RTLD_LOCAL);
        }
    }
    return gles ? dlsym(gles, name) : NULL;
}

int rdp_egl_read_frame(RdpEgl* e, uint8_t* dst, size_t dst_len) {
    if (!e || !dst || !e->target_built) {
        return 0;
    }
    const size_t stride = (size_t)e->width * 4;
    const size_t need = stride * e->height;
    if (dst_len < need) {
        return 0;
    }

    glBindFramebuffer(GL_FRAMEBUFFER, e->fbo);
    glPixelStorei(GL_PACK_ALIGNMENT, 4);
    glReadPixels(0, 0, (GLsizei)e->width, (GLsizei)e->height, GL_RGBA,
                 GL_UNSIGNED_BYTE, dst);

    // GL hands back bottom-up; RDP wants top-down. Swap rows in place.
    if (e->flip_row_len < stride) {
        uint8_t* row = realloc(e->flip_row, stride);
        if (!row) {
            return 0;
        }
        e->flip_row = row;
        e->flip_row_len = stride;
    }
    for (uint32_t y = 0; y < e->height / 2; y++) {
        uint8_t* top = dst + (size_t)y * stride;
        uint8_t* bot = dst + (size_t)(e->height - 1 - y) * stride;
        memcpy(e->flip_row, top, stride);
        memcpy(top, bot, stride);
        memcpy(bot, e->flip_row, stride);
    }
    return 1;
}

int rdp_egl_resize(RdpEgl* e, uint32_t width, uint32_t height) {
    if (!e || width == 0 || height == 0) {
        return 0;
    }
    if (e->width == width && e->height == height && e->target_built) {
        return 1;
    }
    uint32_t ow = e->width, oh = e->height;
    e->width = width;
    e->height = height;
    if (!build_target(e)) {
        e->width = ow;
        e->height = oh;
        build_target(e);
        return 0;
    }
    return 1;
}

void rdp_egl_size(RdpEgl* e, uint32_t* width, uint32_t* height) {
    if (!e) {
        return;
    }
    if (width) {
        *width = e->width;
    }
    if (height) {
        *height = e->height;
    }
}

const char* rdp_egl_renderer(RdpEgl* e) {
    (void)e;
    return (const char*)glGetString(GL_RENDERER);
}
