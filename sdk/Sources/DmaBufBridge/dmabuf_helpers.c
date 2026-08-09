// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#define _GNU_SOURCE  /* memfd_create */
#include "include/DmaBufBridge.h"

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

// ─── SCM_RIGHTS helpers ─────────────────────────────────────────────────────

int dmabuf_create_memfd(size_t size) {
    int fd = memfd_create("starling-shm-relay", MFD_CLOEXEC);
    if (fd < 0) return -1;
    if (ftruncate(fd, (off_t)size) != 0) {
        close(fd);
        return -1;
    }
    return fd;
}

int dmabuf_send_fd(int socket, int fd, const void* meta, size_t meta_len) {
    // Use a small inline buffer if no metadata provided
    char dummy = 0;
    struct iovec iov;
    if (meta && meta_len > 0) {
        iov.iov_base = (void*)meta;
        iov.iov_len = meta_len;
    } else {
        iov.iov_base = &dummy;
        iov.iov_len = 1;
    }

    // Control message buffer for one fd
    char cmsg_buf[CMSG_SPACE(sizeof(int))];
    memset(cmsg_buf, 0, sizeof(cmsg_buf));

    struct msghdr msg;
    memset(&msg, 0, sizeof(msg));
    msg.msg_iov = &iov;
    msg.msg_iovlen = 1;
    msg.msg_control = cmsg_buf;
    msg.msg_controllen = sizeof(cmsg_buf);

    struct cmsghdr* cmsg = CMSG_FIRSTHDR(&msg);
    cmsg->cmsg_level = SOL_SOCKET;
    cmsg->cmsg_type = SCM_RIGHTS;
    cmsg->cmsg_len = CMSG_LEN(sizeof(int));
    memcpy(CMSG_DATA(cmsg), &fd, sizeof(int));

    ssize_t sent = sendmsg(socket, &msg, 0);
    if (sent < 0) {
        fprintf(stderr, "[DmaBufBridge] sendmsg failed: %s\n", strerror(errno));
        return -1;
    }
    return 0;
}

int dmabuf_recv_fd(int socket, void* meta, size_t meta_len) {
    char dummy = 0;
    struct iovec iov;
    if (meta && meta_len > 0) {
        iov.iov_base = meta;
        iov.iov_len = meta_len;
    } else {
        iov.iov_base = &dummy;
        iov.iov_len = 1;
    }

    char cmsg_buf[CMSG_SPACE(sizeof(int))];
    memset(cmsg_buf, 0, sizeof(cmsg_buf));

    struct msghdr msg;
    memset(&msg, 0, sizeof(msg));
    msg.msg_iov = &iov;
    msg.msg_iovlen = 1;
    msg.msg_control = cmsg_buf;
    msg.msg_controllen = sizeof(cmsg_buf);

    ssize_t received = recvmsg(socket, &msg, 0);
    if (received < 0) {
        fprintf(stderr, "[DmaBufBridge] recvmsg failed: %s\n", strerror(errno));
        return -1;
    }
    if (received == 0) {
        return -1;  // Connection closed
    }

    struct cmsghdr* cmsg = CMSG_FIRSTHDR(&msg);
    if (!cmsg || cmsg->cmsg_level != SOL_SOCKET ||
        cmsg->cmsg_type != SCM_RIGHTS ||
        cmsg->cmsg_len != CMSG_LEN(sizeof(int))) {
        fprintf(stderr, "[DmaBufBridge] No fd in control message\n");
        return -1;
    }

    int fd;
    memcpy(&fd, CMSG_DATA(cmsg), sizeof(int));
    return fd;
}

ssize_t dmabuf_recv_with_fd(int socket, void* buf, size_t buf_len,
                            int* out_fd) {
    struct iovec iov;
    iov.iov_base = buf;
    iov.iov_len = buf_len;

    char cmsg_buf[CMSG_SPACE(sizeof(int))];
    memset(cmsg_buf, 0, sizeof(cmsg_buf));

    struct msghdr msg;
    memset(&msg, 0, sizeof(msg));
    msg.msg_iov = &iov;
    msg.msg_iovlen = 1;
    msg.msg_control = cmsg_buf;
    msg.msg_controllen = sizeof(cmsg_buf);

    // EINTR retry, not optional hygiene: the shell's per-child reader thread
    // treats any <= 0 as EOF and exits FOREVER, and this process is drenched
    // in signals (SIGCHLD from every spawned wpctl/nmcli, SIGUSR1 screenshots,
    // SIGRTMIN recording toggles). One interrupted recvmsg silently killed the
    // child->shell control channel: the Settings app kept receiving pushes and
    // pointer events while every request it SENT went nowhere.
    ssize_t received;
    do {
        received = recvmsg(socket, &msg, 0);
    } while (received < 0 && errno == EINTR);
    if (out_fd) *out_fd = -1;

    if (received <= 0) return received;

    // Check for SCM_RIGHTS ancillary data
    struct cmsghdr* cmsg = CMSG_FIRSTHDR(&msg);
    if (cmsg && cmsg->cmsg_level == SOL_SOCKET &&
        cmsg->cmsg_type == SCM_RIGHTS &&
        cmsg->cmsg_len == CMSG_LEN(sizeof(int))) {
        int fd;
        memcpy(&fd, CMSG_DATA(cmsg), sizeof(int));
        if (out_fd) *out_fd = fd;
    }

    return received;
}

// ─── EGL DMA-BUF import ─────────────────────────────────────────────────────

// Function pointer types
typedef EGLImageKHR(EGLAPIENTRYP PFNEGLCREATEIMAGEKHRPROC_)(
    EGLDisplay dpy, EGLContext ctx, EGLenum target,
    EGLClientBuffer buffer, const EGLint* attrib_list);
typedef void(EGLAPIENTRYP PFNGLEGLIMAGETARGETTEXTURE2DOESPROC_)(
    GLenum target, GLeglImageOES image);
typedef EGLBoolean(EGLAPIENTRYP PFNEGLDESTROYIMAGEKHRPROC_)(
    EGLDisplay dpy, EGLImageKHR image);

static PFNEGLCREATEIMAGEKHRPROC_ s_eglCreateImageKHR = NULL;
static PFNGLEGLIMAGETARGETTEXTURE2DOESPROC_ s_glEGLImageTargetTexture2DOES =
    NULL;
static PFNEGLDESTROYIMAGEKHRPROC_ s_eglDestroyImageKHR = NULL;
static int s_egl_loaded = 0;

static void ensure_egl_loaded(void) {
    if (s_egl_loaded) return;
    s_eglCreateImageKHR = (PFNEGLCREATEIMAGEKHRPROC_)eglGetProcAddress(
        "eglCreateImageKHR");
    s_glEGLImageTargetTexture2DOES =
        (PFNGLEGLIMAGETARGETTEXTURE2DOESPROC_)eglGetProcAddress(
            "glEGLImageTargetTexture2DOES");
    s_eglDestroyImageKHR = (PFNEGLDESTROYIMAGEKHRPROC_)eglGetProcAddress(
        "eglDestroyImageKHR");
    s_egl_loaded = 1;
}

typedef EGLBoolean(EGLAPIENTRYP PFNEGLQUERYDMABUFMODIFIERSEXTPROC_)(
    EGLDisplay dpy, EGLint format, EGLint max_modifiers,
    EGLuint64KHR* modifiers, EGLBoolean* external_only, EGLint* num_modifiers);

int dmabuf_query_modifiers(void* egl_display, uint32_t fourcc,
                           uint64_t* modifiers, int max) {
    const char* exts = eglQueryString((EGLDisplay)egl_display, EGL_EXTENSIONS);
    if (!exts || !strstr(exts, "EGL_EXT_image_dma_buf_import_modifiers")) {
        return 0;
    }
    PFNEGLQUERYDMABUFMODIFIERSEXTPROC_ query =
        (PFNEGLQUERYDMABUFMODIFIERSEXTPROC_)eglGetProcAddress(
            "eglQueryDmaBufModifiersEXT");
    if (!query) return 0;

    EGLint count = 0;
    EGLBoolean external_only[64];
    EGLuint64KHR mods[64];
    if (max > 64) max = 64;
    if (!query((EGLDisplay)egl_display, (EGLint)fourcc, max, mods,
               external_only, &count)) {
        return 0;
    }
    if (count > max) count = max;

    /* Skip external-only modifiers — we sample as regular GL textures. */
    int out = 0;
    for (EGLint i = 0; i < count; i++) {
        if (external_only[i]) continue;
        modifiers[out++] = mods[i];
    }
    return out;
}

int dmabuf_check_egl_support(void* egl_display) {
    const char* exts = eglQueryString((EGLDisplay)egl_display, EGL_EXTENSIONS);
    if (!exts) return 0;
    return strstr(exts, "EGL_EXT_image_dma_buf_import") != NULL ? 1 : 0;
}

void* dmabuf_import_egl_image(void* egl_display, int fd, int width, int height,
                              int stride, uint32_t fourcc) {
    ensure_egl_loaded();
    if (!s_eglCreateImageKHR) {
        fprintf(stderr,
                "[DmaBufBridge] eglCreateImageKHR not available\n");
        return NULL;
    }

    // EGL_LINUX_DMA_BUF_EXT = 0x3270
    EGLint attribs[] = {
        EGL_WIDTH,                     width,
        EGL_HEIGHT,                    height,
        0x3271 /* EGL_LINUX_DRM_FOURCC_EXT */,   (EGLint)fourcc,
        0x3272 /* EGL_DMA_BUF_PLANE0_FD_EXT */,  fd,
        0x3273 /* EGL_DMA_BUF_PLANE0_OFFSET_EXT */, 0,
        0x3274 /* EGL_DMA_BUF_PLANE0_PITCH_EXT */, stride,
        EGL_NONE,
    };

    EGLImageKHR image = s_eglCreateImageKHR(
        (EGLDisplay)egl_display, EGL_NO_CONTEXT,
        0x3270 /* EGL_LINUX_DMA_BUF_EXT */,
        (EGLClientBuffer)NULL, attribs);

    if (image == EGL_NO_IMAGE_KHR) {
        fprintf(stderr,
                "[DmaBufBridge] eglCreateImageKHR failed: 0x%x\n",
                eglGetError());
        return NULL;
    }

    return (void*)image;
}

void* dmabuf_import_egl_image_with_modifier(void* egl_display, int fd,
                                             int width, int height, int stride,
                                             uint32_t fourcc, uint64_t modifier) {
    ensure_egl_loaded();
    if (!s_eglCreateImageKHR) {
        fprintf(stderr,
                "[DmaBufBridge] eglCreateImageKHR not available\n");
        return NULL;
    }

    // DRM_FORMAT_MOD_INVALID = ((1ULL << 56) - 1)
    uint64_t DRM_FORMAT_MOD_INVALID_ = (1ULL << 56) - 1;

    EGLint attribs[20];
    int i = 0;
    attribs[i++] = EGL_WIDTH;
    attribs[i++] = width;
    attribs[i++] = EGL_HEIGHT;
    attribs[i++] = height;
    attribs[i++] = 0x3271; /* EGL_LINUX_DRM_FOURCC_EXT */
    attribs[i++] = (EGLint)fourcc;
    attribs[i++] = 0x3272; /* EGL_DMA_BUF_PLANE0_FD_EXT */
    attribs[i++] = fd;
    attribs[i++] = 0x3273; /* EGL_DMA_BUF_PLANE0_OFFSET_EXT */
    attribs[i++] = 0;
    attribs[i++] = 0x3274; /* EGL_DMA_BUF_PLANE0_PITCH_EXT */
    attribs[i++] = stride;

    if (modifier != DRM_FORMAT_MOD_INVALID_) {
        /* EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT = 0x3443 */
        /* EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT = 0x3444 */
        attribs[i++] = 0x3443;
        attribs[i++] = (EGLint)(modifier & 0xFFFFFFFF);
        attribs[i++] = 0x3444;
        attribs[i++] = (EGLint)(modifier >> 32);
    }

    attribs[i++] = EGL_NONE;

    fprintf(stderr,
            "[DmaBufBridge] Importing DMA-BUF: fd=%d %dx%d stride=%d fourcc=0x%08x modifier=0x%llx\n",
            fd, width, height, stride, fourcc, (unsigned long long)modifier);

    EGLImageKHR image = s_eglCreateImageKHR(
        (EGLDisplay)egl_display, EGL_NO_CONTEXT,
        0x3270 /* EGL_LINUX_DMA_BUF_EXT */,
        (EGLClientBuffer)NULL, attribs);

    if (image == EGL_NO_IMAGE_KHR) {
        fprintf(stderr,
                "[DmaBufBridge] eglCreateImageKHR failed: 0x%x (modifier=0x%llx)\n",
                eglGetError(), (unsigned long long)modifier);
        if (modifier == DRM_FORMAT_MOD_INVALID_) {
            // An unknown layout was rejected (zink refuses to guess). The
            // DMA-BUF child-app protocol always allocates GBM_BO_USE_LINEAR
            // buffers, so retry with an explicit LINEAR modifier.
            fprintf(stderr,
                    "[DmaBufBridge] retrying import with explicit LINEAR modifier\n");
            return dmabuf_import_egl_image_with_modifier(
                egl_display, fd, width, height, stride, fourcc, 0 /* LINEAR */);
        }
        // Fall back to import without modifier
        return dmabuf_import_egl_image(egl_display, fd, width, height, stride, fourcc);
    }

    return (void*)image;
}

int dmabuf_blit_flipped_180(void* egl_image, uint32_t output_tex,
                            int width, int height) {
    ensure_egl_loaded();
    if (!s_glEGLImageTargetTexture2DOES) return 0;

    // Save current FBO binding
    GLint prev_fbo = 0;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &prev_fbo);

    // Create temp texture from EGLImage
    GLuint src_tex = 0;
    glGenTextures(1, &src_tex);
    glBindTexture(GL_TEXTURE_2D, src_tex);
    s_glEGLImageTargetTexture2DOES(GL_TEXTURE_2D, (GLeglImageOES)egl_image);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

    // Create FBO with source texture as color attachment, read pixels
    GLuint fbo = 0;
    glGenFramebuffers(1, &fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                           GL_TEXTURE_2D, src_tex, 0);

    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (status != GL_FRAMEBUFFER_COMPLETE) {
        fprintf(stderr,
                "[DmaBufBridge] blit_flipped: FBO incomplete (0x%x)\n",
                status);
        glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)prev_fbo);
        glDeleteFramebuffers(1, &fbo);
        glDeleteTextures(1, &src_tex);
        return 0;
    }

    // Read pixels from the EGLImage
    size_t row_bytes = (size_t)width * 4;
    uint8_t* pixels = (uint8_t*)malloc(row_bytes * (size_t)height);
    if (!pixels) {
        glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)prev_fbo);
        glDeleteFramebuffers(1, &fbo);
        glDeleteTextures(1, &src_tex);
        return 0;
    }

    glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, pixels);

    // Vertical flip: reverse row order to convert from GL bottom-left origin
    // to top-left origin that glTexImage2D expects for correct display with
    // the engine's kBottomLeft_GrSurfaceOrigin.
    uint8_t* flipped = (uint8_t*)malloc(row_bytes * (size_t)height);
    if (!flipped) {
        free(pixels);
        glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)prev_fbo);
        glDeleteFramebuffers(1, &fbo);
        glDeleteTextures(1, &src_tex);
        return 0;
    }

    for (int y = 0; y < height; y++) {
        memcpy(flipped + (size_t)y * row_bytes,
               pixels + (size_t)(height - 1 - y) * row_bytes,
               row_bytes);
    }

    // Upload flipped pixels to output texture
    glBindTexture(GL_TEXTURE_2D, output_tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0,
                 GL_RGBA, GL_UNSIGNED_BYTE, flipped);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glBindTexture(GL_TEXTURE_2D, 0);

    // Cleanup
    free(pixels);
    free(flipped);
    glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)prev_fbo);
    glDeleteFramebuffers(1, &fbo);
    glDeleteTextures(1, &src_tex);

    return 1;
}

void dmabuf_bind_texture(void* egl_image) {
    ensure_egl_loaded();
    if (!s_glEGLImageTargetTexture2DOES) {
        fprintf(stderr,
                "[DmaBufBridge] glEGLImageTargetTexture2DOES not available\n");
        return;
    }
    s_glEGLImageTargetTexture2DOES(GL_TEXTURE_2D, (GLeglImageOES)egl_image);
}

void dmabuf_destroy_egl_image(void* egl_display, void* egl_image) {
    ensure_egl_loaded();
    if (s_eglDestroyImageKHR && egl_image) {
        s_eglDestroyImageKHR((EGLDisplay)egl_display, (EGLImageKHR)egl_image);
    }
}

// ─── EGL context management (headless, render node) ─────────────────────────

// Function pointer type for eglGetPlatformDisplayEXT
typedef EGLDisplay(EGLAPIENTRYP PFNEGLGETPLATFORMDISPLAYEXTPROC_)(
    EGLenum platform, void* native_display, const EGLint* attrib_list);

// EGL_PLATFORM_GBM_MESA
#ifndef EGL_PLATFORM_GBM_MESA
#define EGL_PLATFORM_GBM_MESA 0x31D7
#endif

void* dmabuf_egl_create_display(struct gbm_device* gbm_dev) {
    // Try eglGetPlatformDisplayEXT first (more explicit about GBM platform)
    PFNEGLGETPLATFORMDISPLAYEXTPROC_ getPlatformDisplay =
        (PFNEGLGETPLATFORMDISPLAYEXTPROC_)eglGetProcAddress(
            "eglGetPlatformDisplayEXT");
    if (getPlatformDisplay) {
        EGLDisplay display = getPlatformDisplay(
            EGL_PLATFORM_GBM_MESA, (void*)gbm_dev, NULL);
        if (display != EGL_NO_DISPLAY) {
            return (void*)display;
        }
        fprintf(stderr,
                "[DmaBufBridge] eglGetPlatformDisplayEXT(GBM_MESA) failed, "
                "falling back to eglGetDisplay\n");
    }

    // Fallback to eglGetDisplay
    EGLDisplay display = eglGetDisplay((EGLNativeDisplayType)gbm_dev);
    if (display == EGL_NO_DISPLAY) {
        fprintf(stderr, "[DmaBufBridge] eglGetDisplay failed\n");
        return NULL;
    }
    return (void*)display;
}

int dmabuf_egl_initialize(void* egl_display) {
    EGLint major, minor;
    if (!eglInitialize((EGLDisplay)egl_display, &major, &minor)) {
        fprintf(stderr, "[DmaBufBridge] eglInitialize failed: 0x%x\n",
                eglGetError());
        return 0;
    }
    fprintf(stderr, "[DmaBufBridge] EGL %d.%d initialized\n", major, minor);
    return 1;
}

void* dmabuf_egl_choose_config(void* egl_display) {
    EGLDisplay dpy = (EGLDisplay)egl_display;

    // Try surfaceless first (EGL_SURFACE_TYPE = 0)
    EGLint attribs[] = {
        EGL_SURFACE_TYPE,    0,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_RED_SIZE,        8,
        EGL_GREEN_SIZE,      8,
        EGL_BLUE_SIZE,       8,
        EGL_ALPHA_SIZE,      8,
        EGL_STENCIL_SIZE,    8,
        EGL_NONE,
    };

    EGLConfig config;
    EGLint num_configs = 0;
    if (eglChooseConfig(dpy, attribs, &config, 1, &num_configs) &&
        num_configs > 0) {
        return (void*)config;
    }

    fprintf(stderr,
            "[DmaBufBridge] Surfaceless config failed, trying pbuffer\n");

    // Fallback: try EGL_PBUFFER_BIT
    attribs[1] = EGL_PBUFFER_BIT;
    num_configs = 0;
    if (eglChooseConfig(dpy, attribs, &config, 1, &num_configs) &&
        num_configs > 0) {
        return (void*)config;
    }

    fprintf(stderr, "[DmaBufBridge] eglChooseConfig failed: 0x%x\n",
            eglGetError());
    return NULL;
}

void* dmabuf_egl_create_context(void* egl_display, void* config,
                                void* share_context) {
    EGLDisplay dpy = (EGLDisplay)egl_display;
    EGLConfig cfg = (EGLConfig)config;
    EGLContext share = share_context ? (EGLContext)share_context
                                    : EGL_NO_CONTEXT;

    EGLint ctx_attribs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 2,
        EGL_NONE,
    };

    EGLContext ctx = eglCreateContext(dpy, cfg, share, ctx_attribs);
    if (ctx == EGL_NO_CONTEXT) {
        fprintf(stderr, "[DmaBufBridge] eglCreateContext failed: 0x%x\n",
                eglGetError());
        return NULL;
    }
    return (void*)ctx;
}

int dmabuf_egl_make_current(void* egl_display, void* context) {
    if (!eglMakeCurrent((EGLDisplay)egl_display,
                        EGL_NO_SURFACE, EGL_NO_SURFACE,
                        (EGLContext)context)) {
        fprintf(stderr, "[DmaBufBridge] eglMakeCurrent failed: 0x%x\n",
                eglGetError());
        return 0;
    }
    return 1;
}

int dmabuf_egl_clear_current(void* egl_display) {
    if (!eglMakeCurrent((EGLDisplay)egl_display,
                        EGL_NO_SURFACE, EGL_NO_SURFACE,
                        EGL_NO_CONTEXT)) {
        fprintf(stderr, "[DmaBufBridge] eglMakeCurrent(clear) failed: 0x%x\n",
                eglGetError());
        return 0;
    }
    return 1;
}

void* dmabuf_egl_get_proc_address(const char* name) {
    return (void*)eglGetProcAddress(name);
}

// ─── EGL window surface on a gbm_surface (swapchain mode) ───────────────────
//
// NVIDIA's driver cannot render into a linear dma-buf through an
// EGLImage-backed FBO (the bind fails with GL_INVALID_OPERATION), and its GBM
// refuses LINEAR|RENDERING allocations outright. The only way it renders into
// linear memory is an EGL window surface on a gbm_surface created with the
// LINEAR use flag: eglSwapBuffers detiles into the linear buffer internally.

void* dmabuf_egl_choose_window_config(void* egl_display, uint32_t fourcc) {
    EGLDisplay dpy = (EGLDisplay)egl_display;

    EGLint attribs[] = {
        EGL_SURFACE_TYPE,    EGL_WINDOW_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_RED_SIZE,        8,
        EGL_GREEN_SIZE,      8,
        EGL_BLUE_SIZE,       8,
        EGL_STENCIL_SIZE,    8,
        EGL_NONE,
    };

    EGLConfig configs[64];
    EGLint num_configs = 0;
    if (!eglChooseConfig(dpy, attribs, configs, 64, &num_configs) ||
        num_configs == 0) {
        fprintf(stderr,
                "[DmaBufBridge] no window-bit EGL configs: 0x%x\n",
                eglGetError());
        return NULL;
    }

    // GBM requires the config's native visual to be the surface's format,
    // or eglCreateWindowSurface fails with EGL_BAD_MATCH.
    for (EGLint i = 0; i < num_configs; i++) {
        EGLint visual = 0;
        if (eglGetConfigAttrib(dpy, configs[i], EGL_NATIVE_VISUAL_ID,
                               &visual) && (uint32_t)visual == fourcc) {
            return (void*)configs[i];
        }
    }
    return NULL;
}

void* dmabuf_egl_create_window_surface(void* egl_display, void* config,
                                       struct gbm_surface* gbm_surface) {
    EGLSurface surf = eglCreateWindowSurface(
        (EGLDisplay)egl_display, (EGLConfig)config,
        (EGLNativeWindowType)gbm_surface, NULL);
    if (surf == EGL_NO_SURFACE) {
        fprintf(stderr,
                "[DmaBufBridge] eglCreateWindowSurface failed: 0x%x\n",
                eglGetError());
        return NULL;
    }
    return (void*)surf;
}

int dmabuf_egl_make_current_surface(void* egl_display, void* context,
                                    void* egl_surface) {
    if (!eglMakeCurrent((EGLDisplay)egl_display,
                        (EGLSurface)egl_surface, (EGLSurface)egl_surface,
                        (EGLContext)context)) {
        fprintf(stderr,
                "[DmaBufBridge] eglMakeCurrent(surface) failed: 0x%x\n",
                eglGetError());
        return 0;
    }
    return 1;
}

int dmabuf_egl_swap_buffers(void* egl_display, void* egl_surface) {
    if (!eglSwapBuffers((EGLDisplay)egl_display, (EGLSurface)egl_surface)) {
        fprintf(stderr, "[DmaBufBridge] eglSwapBuffers failed: 0x%x\n",
                eglGetError());
        return 0;
    }
    return 1;
}

void dmabuf_egl_destroy_surface(void* egl_display, void* egl_surface) {
    if (egl_surface) {
        eglDestroySurface((EGLDisplay)egl_display, (EGLSurface)egl_surface);
    }
}

// A window surface's memory comes out of eglSwapBuffers vertically flipped
// relative to what the parent's sampler expects (the driver stores GL's
// bottom-up window framebuffer top-down for scanout). So the engine keeps
// rendering into an ordinary FBO — identical semantics to the bo path — and
// present() blits it onto the window surface with Y inverted.

#ifndef GL_READ_FRAMEBUFFER
#define GL_READ_FRAMEBUFFER 0x8CA8
#endif
#ifndef GL_DRAW_FRAMEBUFFER
#define GL_DRAW_FRAMEBUFFER 0x8CA9
#endif
#ifndef GL_RGBA8_OES
#define GL_RGBA8_OES 0x8058
#endif

typedef void (*PFNGLBLITFRAMEBUFFERPROC_)(GLint, GLint, GLint, GLint,
                                          GLint, GLint, GLint, GLint,
                                          GLbitfield, GLenum);
static PFNGLBLITFRAMEBUFFERPROC_ s_glBlitFramebuffer = NULL;

uint32_t dmabuf_create_plain_fbo(int width, int height,
                                 uint32_t* out_color_rb,
                                 uint32_t* out_stencil_rb) {
    GLuint color = 0, stencil = 0, fbo = 0;
    glGenRenderbuffers(1, &color);
    glBindRenderbuffer(GL_RENDERBUFFER, color);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8_OES, width, height);
    glGenRenderbuffers(1, &stencil);
    glBindRenderbuffer(GL_RENDERBUFFER, stencil);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_STENCIL_INDEX8, width, height);
    glGenFramebuffers(1, &fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                              GL_RENDERBUFFER, color);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT,
                              GL_RENDERBUFFER, stencil);
    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    if (status != GL_FRAMEBUFFER_COMPLETE) {
        fprintf(stderr, "[DmaBufBridge] plain FBO incomplete: 0x%x\n", status);
        glDeleteFramebuffers(1, &fbo);
        glDeleteRenderbuffers(1, &color);
        glDeleteRenderbuffers(1, &stencil);
        return 0;
    }
    if (out_color_rb)   *out_color_rb = color;
    if (out_stencil_rb) *out_stencil_rb = stencil;
    return fbo;
}

void dmabuf_destroy_plain_fbo(uint32_t fbo, uint32_t color_rb,
                              uint32_t stencil_rb) {
    if (fbo)        glDeleteFramebuffers(1, &fbo);
    if (color_rb)   glDeleteRenderbuffers(1, &color_rb);
    if (stencil_rb) glDeleteRenderbuffers(1, &stencil_rb);
}

int dmabuf_blit_flip_to_window(uint32_t src_fbo, int width, int height) {
    if (!s_glBlitFramebuffer) {
        s_glBlitFramebuffer = (PFNGLBLITFRAMEBUFFERPROC_)eglGetProcAddress(
            "glBlitFramebuffer");
        if (!s_glBlitFramebuffer) {
            fprintf(stderr, "[DmaBufBridge] glBlitFramebuffer unavailable\n");
            return 0;
        }
    }
    glBindFramebuffer(GL_READ_FRAMEBUFFER, src_fbo);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
    s_glBlitFramebuffer(0, 0, width, height,
                        0, height, width, 0,
                        GL_COLOR_BUFFER_BIT, GL_NEAREST);
    // The engine runs with fbo_reset_after_present=false: it assumes its FBO
    // stays bound between frames. Leaving DRAW at 0 here sent every frame
    // after the first into the window surface, where this blit then
    // overwrote it with the stale first-frame content of src_fbo — a frozen
    // window with a perfectly healthy UI underneath.
    glBindFramebuffer(GL_FRAMEBUFFER, src_fbo);
    return 1;
}

void dmabuf_gl_finish(void) {
    glFinish();
}

void dmabuf_gl_flush(void) {
    glFlush();
}

void dmabuf_gl_clear_black(void) {
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    glFlush();
}

void dmabuf_gl_dump_fbo(int width, int height, const char* path) {
    // Read pixels from the currently bound FBO and save as PPM
    GLint fbo;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &fbo);
    fprintf(stderr, "[DmaBufBridge] dump_fbo: fbo=%d %dx%d -> %s\n",
            fbo, width, height, path);

    size_t rowBytes = (size_t)width * 4;
    size_t totalBytes = rowBytes * (size_t)height;
    unsigned char* pixels = (unsigned char*)malloc(totalBytes);
    if (!pixels) {
        fprintf(stderr, "[DmaBufBridge] dump_fbo: malloc failed\n");
        return;
    }

    glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, pixels);

    FILE* f = fopen(path, "wb");
    if (!f) {
        fprintf(stderr, "[DmaBufBridge] dump_fbo: fopen failed: %s\n",
                strerror(errno));
        free(pixels);
        return;
    }
    fprintf(f, "P6\n%d %d\n255\n", width, height);
    // GL pixels are bottom-up; write top-down for PPM
    for (int y = height - 1; y >= 0; y--) {
        for (int x = 0; x < width; x++) {
            size_t idx = (size_t)y * rowBytes + (size_t)x * 4;
            fputc(pixels[idx + 0], f);  // R
            fputc(pixels[idx + 1], f);  // G
            fputc(pixels[idx + 2], f);  // B
        }
    }
    fclose(f);
    free(pixels);
    fprintf(stderr, "[DmaBufBridge] dump_fbo: saved %s\n", path);
}

void dmabuf_gl_log_state(void) {
    GLint viewport[4];
    glGetIntegerv(GL_VIEWPORT, viewport);
    GLint fbo;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &fbo);
    GLint stencil_bits;
    glGetIntegerv(GL_STENCIL_BITS, &stencil_bits);
    fprintf(stderr, "[DmaBufBridge] GL state: viewport=%dx%d+%d+%d fbo=%d stencil=%d\n",
            viewport[2], viewport[3], viewport[0], viewport[1], fbo, stencil_bits);
}

// ─── Offscreen FBO backed by GBM BO ─────────────────────────────────────────

// GL constants (GLES2 core, but define if missing)
#ifndef GL_FRAMEBUFFER
#define GL_FRAMEBUFFER 0x8D40
#endif
#ifndef GL_RENDERBUFFER
#define GL_RENDERBUFFER 0x8D41
#endif
#ifndef GL_COLOR_ATTACHMENT0
#define GL_COLOR_ATTACHMENT0 0x8CE0
#endif
#ifndef GL_STENCIL_ATTACHMENT
#define GL_STENCIL_ATTACHMENT 0x8D20
#endif
#ifndef GL_FRAMEBUFFER_COMPLETE
#define GL_FRAMEBUFFER_COMPLETE 0x8CD5
#endif
#ifndef GL_STENCIL_INDEX8
#define GL_STENCIL_INDEX8 0x8D48
#endif

uint32_t dmabuf_create_fbo(void* egl_display, int dma_fd,
                           int width, int height, int stride,
                           uint32_t fourcc,
                           void** out_egl_image,
                           uint32_t* out_color_tex,
                           uint32_t* out_stencil_rb) {
    // 1. Import DMA-BUF fd as EGLImage
    void* egl_image = dmabuf_import_egl_image(egl_display, dma_fd,
                                               width, height, stride, fourcc);
    if (!egl_image) {
        fprintf(stderr, "[DmaBufBridge] dmabuf_create_fbo: "
                "failed to import EGLImage\n");
        return 0;
    }

    // 2. Create GL texture and bind EGLImage to it
    GLuint tex = 0;
    glGenTextures(1, &tex);
    glBindTexture(GL_TEXTURE_2D, tex);
    dmabuf_bind_texture(egl_image);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

    // 3. Create stencil renderbuffer
    GLuint rb = 0;
    glGenRenderbuffers(1, &rb);
    glBindRenderbuffer(GL_RENDERBUFFER, rb);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_STENCIL_INDEX8, width, height);

    // 4. Create FBO and attach color + stencil
    GLuint fbo = 0;
    glGenFramebuffers(1, &fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                           GL_TEXTURE_2D, tex, 0);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT,
                              GL_RENDERBUFFER, rb);

    // 5. Check completeness
    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (status != GL_FRAMEBUFFER_COMPLETE) {
        fprintf(stderr, "[DmaBufBridge] dmabuf_create_fbo: "
                "framebuffer incomplete: 0x%x\n", status);
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glDeleteFramebuffers(1, &fbo);
        glDeleteTextures(1, &tex);
        glDeleteRenderbuffers(1, &rb);
        dmabuf_destroy_egl_image(egl_display, egl_image);
        return 0;
    }

    // 6. Unbind and return
    glBindFramebuffer(GL_FRAMEBUFFER, 0);

    if (out_egl_image)  *out_egl_image  = egl_image;
    if (out_color_tex)  *out_color_tex  = tex;
    if (out_stencil_rb) *out_stencil_rb = rb;
    return (uint32_t)fbo;
}

void dmabuf_destroy_fbo(void* egl_display, uint32_t fbo,
                        void* egl_image, uint32_t color_tex,
                        uint32_t stencil_rb) {
    if (fbo) {
        glDeleteFramebuffers(1, &fbo);
    }
    if (color_tex) {
        glDeleteTextures(1, &color_tex);
    }
    if (stencil_rb) {
        glDeleteRenderbuffers(1, &stencil_rb);
    }
    if (egl_image) {
        dmabuf_destroy_egl_image(egl_display, egl_image);
    }
}

// ─── GL texture helpers ─────────────────────────────────────────────────

uint32_t dmabuf_gen_gl_texture(void) {
    GLuint tex = 0;
    glGenTextures(1, &tex);
    return (uint32_t)tex;
}

void dmabuf_delete_gl_texture(uint32_t tex) {
    GLuint t = (GLuint)tex;
    if (t) glDeleteTextures(1, &t);
}

uint32_t dmabuf_import_as_gl_texture(void* egl_display, int fd,
                                      int width, int height, int stride,
                                      uint32_t fourcc, uint64_t modifier,
                                      void** out_egl_image) {
    void* img = dmabuf_import_egl_image_with_modifier(
        egl_display, fd, width, height, stride, fourcc, modifier);
    if (!img) {
        fprintf(stderr, "[DmaBufBridge] import_as_gl_texture: EGLImage import failed\n");
        return 0;
    }

    GLuint tex = 0;
    glGenTextures(1, &tex);
    glBindTexture(GL_TEXTURE_2D, tex);
    dmabuf_bind_texture(img);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glBindTexture(GL_TEXTURE_2D, 0);

    if (out_egl_image) *out_egl_image = img;
    return (uint32_t)tex;
}

void dmabuf_rebind_gl_texture(uint32_t tex, void* egl_image) {
    glBindTexture(GL_TEXTURE_2D, (GLuint)tex);
    dmabuf_bind_texture(egl_image);
    glBindTexture(GL_TEXTURE_2D, 0);
}

#ifndef GL_TEXTURE_EXTERNAL_OES
#define GL_TEXTURE_EXTERNAL_OES 0x8D65
#endif

void* dmabuf_import_nv12_egl_image(void* egl_display, int fd,
                                    int width, int height, uint64_t modifier,
                                    uint32_t offset0, uint32_t pitch0,
                                    uint32_t offset1, uint32_t pitch1) {
    ensure_egl_loaded();
    if (!s_eglCreateImageKHR) {
        fprintf(stderr, "[DmaBufBridge] eglCreateImageKHR not available\n");
        return NULL;
    }

    const uint64_t MOD_INVALID = (1ULL << 56) - 1;
    const EGLint DRM_FORMAT_NV12 = 0x3231564e;  /* 'NV12' */

    EGLint a[36];
    int i = 0;
    a[i++] = EGL_WIDTH;                        a[i++] = width;
    a[i++] = EGL_HEIGHT;                       a[i++] = height;
    a[i++] = 0x3271 /* EGL_LINUX_DRM_FOURCC_EXT */;  a[i++] = DRM_FORMAT_NV12;

    a[i++] = 0x3272 /* PLANE0_FD_EXT     */;   a[i++] = fd;
    a[i++] = 0x3273 /* PLANE0_OFFSET_EXT */;   a[i++] = (EGLint)offset0;
    a[i++] = 0x3274 /* PLANE0_PITCH_EXT  */;   a[i++] = (EGLint)pitch0;
    a[i++] = 0x3275 /* PLANE1_FD_EXT     */;   a[i++] = fd;
    a[i++] = 0x3276 /* PLANE1_OFFSET_EXT */;   a[i++] = (EGLint)offset1;
    a[i++] = 0x3277 /* PLANE1_PITCH_EXT  */;   a[i++] = (EGLint)pitch1;

    // Both planes live in one tiled buffer, so both need the modifier — an
    // import that names it for plane 0 only is rejected.
    if (modifier != MOD_INVALID) {
        a[i++] = 0x3443 /* PLANE0_MODIFIER_LO_EXT */;
        a[i++] = (EGLint)(modifier & 0xFFFFFFFF);
        a[i++] = 0x3444 /* PLANE0_MODIFIER_HI_EXT */;
        a[i++] = (EGLint)(modifier >> 32);
        a[i++] = 0x3445 /* PLANE1_MODIFIER_LO_EXT */;
        a[i++] = (EGLint)(modifier & 0xFFFFFFFF);
        a[i++] = 0x3446 /* PLANE1_MODIFIER_HI_EXT */;
        a[i++] = (EGLint)(modifier >> 32);
    }
    a[i++] = EGL_NONE;

    EGLImageKHR image = s_eglCreateImageKHR(
        (EGLDisplay)egl_display, EGL_NO_CONTEXT,
        0x3270 /* EGL_LINUX_DMA_BUF_EXT */, (EGLClientBuffer)NULL, a);
    if (image == EGL_NO_IMAGE_KHR) {
        fprintf(stderr,
                "[DmaBufBridge] NV12 import failed: 0x%x (%dx%d mod=0x%llx "
                "p0=%u/%u p1=%u/%u)\n",
                eglGetError(), width, height, (unsigned long long)modifier,
                offset0, pitch0, offset1, pitch1);
        return NULL;
    }
    return (void*)image;
}

uint32_t dmabuf_bind_external_texture(uint32_t tex, void* egl_image) {
    ensure_egl_loaded();
    if (!s_glEGLImageTargetTexture2DOES) return 0;
    GLuint t = (GLuint)tex;
    if (t == 0) {
        glGenTextures(1, &t);
        if (t == 0) return 0;
    }
    glBindTexture(GL_TEXTURE_EXTERNAL_OES, t);
    s_glEGLImageTargetTexture2DOES(GL_TEXTURE_EXTERNAL_OES,
                                   (GLeglImageOES)egl_image);
    // External textures take no mipmaps and must clamp; NEAREST vs LINEAR is
    // the usual quality tradeoff and the video quad is scaled, so LINEAR.
    glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glBindTexture(GL_TEXTURE_EXTERNAL_OES, 0);
    return (uint32_t)t;
}

uint32_t dmabuf_upload_rgba_texture(uint32_t tex, int width, int height,
                                     int reuse_storage,
                                     const uint8_t* pixels) {
    if (width <= 0 || height <= 0 || !pixels) {
        return 0;
    }
    GLuint t = (GLuint)tex;
    if (t == 0) {
        glGenTextures(1, &t);
        if (t == 0) {
            return 0;
        }
        reuse_storage = 0;  // nothing allocated yet
        glBindTexture(GL_TEXTURE_2D, t);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    } else {
        glBindTexture(GL_TEXTURE_2D, t);
    }
    glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
    if (reuse_storage) {
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, width, height,
                        GL_RGBA, GL_UNSIGNED_BYTE, pixels);
    } else {
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0,
                     GL_RGBA, GL_UNSIGNED_BYTE, pixels);
    }
    glBindTexture(GL_TEXTURE_2D, 0);
    return (uint32_t)t;
}

// ─── GPU texture copy ────────────────────────────────────────────────────

#ifndef GL_READ_FRAMEBUFFER
#define GL_READ_FRAMEBUFFER 0x8CA8
#endif
#ifndef GL_DRAW_FRAMEBUFFER
#define GL_DRAW_FRAMEBUFFER 0x8CA9
#endif
#ifndef GL_COLOR_BUFFER_BIT
#define GL_COLOR_BUFFER_BIT 0x00004000
#endif
#ifndef GL_NEAREST
#define GL_NEAREST 0x2600
#endif

typedef void (*PFNGLBLITFRAMEBUFFERPROC)(GLint, GLint, GLint, GLint,
                                          GLint, GLint, GLint, GLint,
                                          GLbitfield, GLenum);

int dmabuf_gpu_copy_texture(uint32_t src_tex, uint32_t dst_tex,
                            int width, int height) {
    static PFNGLBLITFRAMEBUFFERPROC glBlitFramebuffer_ = NULL;
    if (!glBlitFramebuffer_) {
        glBlitFramebuffer_ = (PFNGLBLITFRAMEBUFFERPROC)
            eglGetProcAddress("glBlitFramebuffer");
        if (!glBlitFramebuffer_) {
            fprintf(stderr, "[DmaBufBridge] glBlitFramebuffer not available\n");
            return 0;
        }
    }

    /* Save current FBO binding */
    GLint prev_fbo = 0;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &prev_fbo);

    /* Create two FBOs: read (src) and draw (dst) */
    GLuint read_fbo = 0, draw_fbo = 0;
    glGenFramebuffers(1, &read_fbo);
    glGenFramebuffers(1, &draw_fbo);

    /* Allocate dst texture storage (RGBA8, same size as src) */
    glBindTexture(GL_TEXTURE_2D, dst_tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0,
                 GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glBindTexture(GL_TEXTURE_2D, 0);

    /* Attach src to read FBO */
    glBindFramebuffer(GL_READ_FRAMEBUFFER, read_fbo);
    glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                           GL_TEXTURE_2D, src_tex, 0);

    /* Attach dst to draw FBO */
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, draw_fbo);
    glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                           GL_TEXTURE_2D, dst_tex, 0);

    /* Blit src → dst */
    glBlitFramebuffer_(0, 0, width, height,
                       0, 0, width, height,
                       GL_COLOR_BUFFER_BIT, GL_NEAREST);

    /* Restore previous FBO and cleanup */
    glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)prev_fbo);
    glDeleteFramebuffers(1, &read_fbo);
    glDeleteFramebuffers(1, &draw_fbo);

    return 1;
}
