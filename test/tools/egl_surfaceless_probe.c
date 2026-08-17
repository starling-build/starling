// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// Can we get a GL context with no window system and no /dev/dri?
//
// This is the W2 gate in docs/plans/rdp-wsl.md. In WSL there is no DRM device
// at all (dxgkrnl is a misc chardev; Mesa reaches the GPU through libdxcore),
// so the desktop's usual EGL entry — eglGetPlatformDisplay(EGL_PLATFORM_GBM)
// on a gbm_device — has no fd to open. Surfaceless EGL needs neither, which
// is why it is the candidate. What this measures:
//
//   1. does EGL_PLATFORM_SURFACELESS_MESA give a display + ES2 context,
//   2. what actually renders it (GL_RENDERER — d3d12 vs llvmpipe matters:
//      one is the GPU, the other is the CPU wearing a GL hat),
//   3. does an FBO render + glReadPixels round-trip produce correct pixels,
//   4. how long that readback takes at 1080p and 4K — the per-frame cost an
//      RDP display backend would pay, since there is no scanout to share.
//
// Build:  cc -o egl_surfaceless_probe egl_surfaceless_probe.c -lEGL -lGLESv2
// Run:    ./egl_surfaceless_probe
// In WSL: LD_LIBRARY_PATH=/usr/lib/wsl/lib ./egl_surfaceless_probe

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static double now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

static int probe_size(uint32_t w, uint32_t h, int reps) {
    GLuint tex = 0, fbo = 0;
    glGenTextures(1, &tex);
    glBindTexture(GL_TEXTURE_2D, tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, (GLsizei)w, (GLsizei)h, 0, GL_RGBA,
                 GL_UNSIGNED_BYTE, NULL);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glGenFramebuffers(1, &fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
                           tex, 0);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        printf("  %ux%u: FBO incomplete\n", w, h);
        return 0;
    }

    // A colour with all channels distinct, so a byte-order mistake downstream
    // is obvious rather than plausible.
    glViewport(0, 0, (GLsizei)w, (GLsizei)h);
    glClearColor(0.2f, 0.4f, 0.6f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    glFinish();

    uint8_t px[4] = {0, 0, 0, 0};
    glReadPixels(0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
    int ok = (px[0] > 45 && px[0] < 60) && (px[1] > 95 && px[1] < 110) &&
             (px[2] > 145 && px[2] < 160);

    uint8_t *buf = malloc((size_t)w * h * 4);
    if (!buf) return 0;
    // Warm once — the first readback allocates staging the others reuse.
    glReadPixels(0, 0, (GLsizei)w, (GLsizei)h, GL_RGBA, GL_UNSIGNED_BYTE, buf);
    double t0 = now_ms();
    for (int i = 0; i < reps; i++) {
        glClear(GL_COLOR_BUFFER_BIT);
        glReadPixels(0, 0, (GLsizei)w, (GLsizei)h, GL_RGBA, GL_UNSIGNED_BYTE,
                     buf);
    }
    double per = (now_ms() - t0) / reps;
    free(buf);

    printf("  %ux%u: pixels %s, readback %.1f ms/frame (%.0f fps ceiling)\n", w,
           h, ok ? "CORRECT" : "WRONG", per, per > 0 ? 1000.0 / per : 0.0);
    glDeleteFramebuffers(1, &fbo);
    glDeleteTextures(1, &tex);
    return ok;
}

int main(void) {
    printf("EGL surfaceless probe — a GL context with no window and no /dev/dri\n\n");

    const char *client_exts = eglQueryString(EGL_NO_DISPLAY, EGL_EXTENSIONS);
    printf("client extensions: %s\n\n", client_exts ? client_exts : "(none)");
    if (!client_exts || !strstr(client_exts, "EGL_MESA_platform_surfaceless")) {
        printf("VERDICT: EGL_MESA_platform_surfaceless NOT advertised.\n");
        printf("         Surfaceless is unavailable; see the plan's fallbacks.\n");
        return 2;
    }

    PFNEGLGETPLATFORMDISPLAYEXTPROC getPlatformDisplay =
        (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress(
            "eglGetPlatformDisplayEXT");
    if (!getPlatformDisplay) {
        printf("VERDICT: no eglGetPlatformDisplayEXT.\n");
        return 2;
    }

    EGLDisplay dpy = getPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA,
                                        EGL_DEFAULT_DISPLAY, NULL);
    if (dpy == EGL_NO_DISPLAY) {
        printf("VERDICT: eglGetPlatformDisplay(SURFACELESS) failed.\n");
        return 2;
    }
    EGLint major = 0, minor = 0;
    if (!eglInitialize(dpy, &major, &minor)) {
        printf("VERDICT: eglInitialize failed (0x%x).\n", eglGetError());
        return 2;
    }
    printf("EGL %d.%d initialized surfacelessly\n", major, minor);
    printf("EGL_VENDOR:  %s\n", eglQueryString(dpy, EGL_VENDOR));

    if (!eglBindAPI(EGL_OPENGL_ES_API)) {
        printf("VERDICT: eglBindAPI(ES) failed.\n");
        return 2;
    }

    // No EGL_WINDOW_BIT: there is no surface to ask for. Rendering goes to an
    // FBO, which is exactly what an RDP display backend would do anyway.
    const EGLint cfg_attribs[] = {EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
                                  EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
                                  EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8,
                                  EGL_BLUE_SIZE, 8, EGL_NONE};
    EGLConfig cfg;
    EGLint n = 0;
    if (!eglChooseConfig(dpy, cfg_attribs, &cfg, 1, &n) || n < 1) {
        printf("VERDICT: no usable EGLConfig.\n");
        return 2;
    }

    const EGLint ctx_attribs[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE};
    EGLContext ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, ctx_attribs);
    if (ctx == EGL_NO_CONTEXT) {
        printf("VERDICT: eglCreateContext failed (0x%x).\n", eglGetError());
        return 2;
    }
    // The whole point: current with NO surface at all.
    if (!eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx)) {
        printf("VERDICT: eglMakeCurrent(NO_SURFACE) failed (0x%x).\n",
               eglGetError());
        return 2;
    }

    const char *renderer = (const char *)glGetString(GL_RENDERER);
    const char *version = (const char *)glGetString(GL_VERSION);
    printf("GL_RENDERER: %s\n", renderer ? renderer : "?");
    printf("GL_VERSION:  %s\n\n", version ? version : "?");

    printf("FBO render + readback:\n");
    int ok = 1;
    ok &= probe_size(1920, 1080, 30);
    ok &= probe_size(3840, 2160, 10);

    int software = renderer && (strstr(renderer, "llvmpipe") ||
                                strstr(renderer, "softpipe") ||
                                strstr(renderer, "swrast"));
    printf("\nVERDICT: surfaceless GL %s.\n", ok ? "WORKS" : "rendered WRONG pixels");
    if (ok) {
        printf("         Renderer is %s — %s\n",
               software ? "SOFTWARE (CPU)" : "hardware-backed",
               software ? "no faster than the software renderer; W2 buys "
                          "GL semantics, not speed."
                        : "W2 is worth building on this box.");
    }

    eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroyContext(dpy, ctx);
    eglTerminate(dpy);
    return ok ? 0 : 1;
}
