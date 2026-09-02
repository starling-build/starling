/*
 * dmabuf-shot: read a dma-buf back to a PPM through EGL on the render node.
 *
 *   dmabuf-shot FD WIDTH HEIGHT STRIDE OFFSET FOURCC MODIFIER FLIP OUT.ppm
 *
 * FD is an inherited dma-buf fd; MODIFIER is the DRM modifier or -1 for
 * DRM_FORMAT_MOD_INVALID (the buffer's tiling is then whatever the driver
 * that exported it recorded on the BO, which works only on the same device
 * -- exactly the case for a QEMU `-display dbus,gl=on` scanout read back on
 * the same render node). FLIP=1 flips vertically: QEMU's y0_top=true marks a
 * GL-rendered texture whose row 0 is the bottom; false (blob scanouts, QEMU's
 * own placeholder surface) is the ordinary top-down layout and needs no flip.
 *
 *   gcc -O2 -o dmabuf-shot dmabuf-shot.c $(pkg-config --cflags --libs egl gbm glesv2)
 *
 * Driven by dbus-display.py's `shot`; plain enough to run by hand.
 */
#define _GNU_SOURCE
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <fcntl.h>
#include <gbm.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define DIE(...) do { fprintf(stderr, "dmabuf-shot: " __VA_ARGS__); fputc('\n', stderr); exit(1); } while (0)

int main(int argc, char **argv)
{
    if (argc != 10) DIE("usage: FD W H STRIDE OFFSET FOURCC MODIFIER FLIP OUT.ppm");
    int fd = atoi(argv[1]), w = atoi(argv[2]), h = atoi(argv[3]);
    int stride = atoi(argv[4]), offset = atoi(argv[5]);
    unsigned fourcc = strtoul(argv[6], NULL, 0);
    long long modifier = strtoll(argv[7], NULL, 0);
    int flip = atoi(argv[8]);
    const char *out = argv[9];
    const char *node = getenv("DMABUF_SHOT_NODE") ?: "/dev/dri/renderD128";

    int drm = open(node, O_RDWR | O_CLOEXEC);
    if (drm < 0) DIE("open %s failed", node);
    struct gbm_device *gbm = gbm_create_device(drm);
    if (!gbm) DIE("gbm_create_device failed");

    PFNEGLGETPLATFORMDISPLAYEXTPROC getPlatformDisplay =
        (void *)eglGetProcAddress("eglGetPlatformDisplayEXT");
    PFNEGLCREATEIMAGEKHRPROC createImage = (void *)eglGetProcAddress("eglCreateImageKHR");
    PFNEGLDESTROYIMAGEKHRPROC destroyImage = (void *)eglGetProcAddress("eglDestroyImageKHR");
    PFNGLEGLIMAGETARGETTEXTURE2DOESPROC imageTargetTexture =
        (void *)eglGetProcAddress("glEGLImageTargetTexture2DOES");
    if (!getPlatformDisplay || !createImage || !imageTargetTexture) DIE("missing EGL entry points");

    EGLDisplay dpy = getPlatformDisplay(EGL_PLATFORM_GBM_KHR, gbm, NULL);
    if (dpy == EGL_NO_DISPLAY || !eglInitialize(dpy, NULL, NULL)) DIE("eglInitialize failed");
    if (!eglBindAPI(EGL_OPENGL_ES_API)) DIE("eglBindAPI failed");
    static const EGLint ctx_attrs[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
    EGLContext ctx = eglCreateContext(dpy, EGL_NO_CONFIG_KHR, EGL_NO_CONTEXT, ctx_attrs);
    if (ctx == EGL_NO_CONTEXT) DIE("eglCreateContext failed (0x%x)", eglGetError());
    if (!eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx)) DIE("eglMakeCurrent failed (0x%x)", eglGetError());

    EGLint attrs[32]; int n = 0;
    attrs[n++] = EGL_WIDTH; attrs[n++] = w;
    attrs[n++] = EGL_HEIGHT; attrs[n++] = h;
    attrs[n++] = EGL_LINUX_DRM_FOURCC_EXT; attrs[n++] = (EGLint)fourcc;
    attrs[n++] = EGL_DMA_BUF_PLANE0_FD_EXT; attrs[n++] = fd;
    attrs[n++] = EGL_DMA_BUF_PLANE0_OFFSET_EXT; attrs[n++] = offset;
    attrs[n++] = EGL_DMA_BUF_PLANE0_PITCH_EXT; attrs[n++] = stride;
    if (modifier != -1) {
        attrs[n++] = EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT; attrs[n++] = (EGLint)(modifier & 0xffffffff);
        attrs[n++] = EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT; attrs[n++] = (EGLint)(modifier >> 32);
    }
    attrs[n++] = EGL_NONE;
    EGLImageKHR img = createImage(dpy, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, NULL, attrs);
    if (img == EGL_NO_IMAGE_KHR) DIE("eglCreateImageKHR failed (0x%x)", eglGetError());

    GLuint tex, fbo;
    glGenTextures(1, &tex);
    glBindTexture(GL_TEXTURE_2D, tex);
    imageTargetTexture(GL_TEXTURE_2D, img);
    glGenFramebuffers(1, &fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) DIE("framebuffer incomplete");

    unsigned char *px = malloc((size_t)w * h * 4);
    if (!px) DIE("malloc");
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, px);
    GLenum err = glGetError();
    if (err) DIE("glReadPixels: 0x%x", err);

    FILE *f = fopen(out, "wb");
    if (!f) DIE("open %s for writing failed", out);
    fprintf(f, "P6\n%d %d\n255\n", w, h);
    for (int y = 0; y < h; y++) {
        const unsigned char *row = px + (size_t)(flip ? h - 1 - y : y) * w * 4;
        for (int x = 0; x < w; x++) fwrite(row + x * 4, 1, 3, f);
    }
    fclose(f);
    destroyImage(dpy, img);
    eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroyContext(dpy, ctx);
    eglTerminate(dpy);
    gbm_device_destroy(gbm);
    close(drm);
    return 0;
}
