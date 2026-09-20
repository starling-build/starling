// Two independent Filament scenes in one shared EGL context, like two outputs.
#include "starling_room.h"
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <gbm.h>
#include <fcntl.h>
#include <unistd.h>
#include <cassert>
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <vector>

int main() {
    int fd = open(getenv("ROOMTEST_NODE") ? getenv("ROOMTEST_NODE") : "/dev/dri/renderD128", O_RDWR | O_CLOEXEC);
    if (fd < 0) { perror("render node"); return 1; }
    auto* gbm = gbm_create_device(fd);
    auto getDisplay = (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");
    EGLDisplay display = getDisplay(EGL_PLATFORM_GBM_MESA, gbm, nullptr);
    assert(eglInitialize(display, nullptr, nullptr));
    eglBindAPI(EGL_OPENGL_ES_API);
    EGLint attrs[] = {EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_NONE};
    EGLConfig config; EGLint count;
    assert(eglChooseConfig(display, attrs, &config, 1, &count) && count);
    EGLint contextAttrs[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE};
    EGLContext context = eglCreateContext(display, config, EGL_NO_CONTEXT, contextAttrs);
    assert(eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, context));
    GLuint textures[2], fbo;
    glGenTextures(2, textures);
    glGenFramebuffers(1, &fbo);
    sr_room* rooms[2];
    int widths[] = {480, 320}, heights[] = {300, 360};
    auto camera = [&](int i, double x) {
        float view[16] = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, float(-x), 0, -6, 1};
        float proj[16] = {};
        proj[0] = 1 / 0.7002f;
        proj[5] = float(widths[i]) / heights[i] / 0.7002f;
        proj[10] = -(100 + 0.08f) / (100 - 0.08f);
        proj[11] = -1;
        proj[14] = -2 * 100 * 0.08f / (100 - 0.08f);
        sr_room_set_camera(rooms[i], view, proj, 0.08, 100);
    };
    auto pixels = [&](int i) {
        glBindFramebuffer(GL_FRAMEBUFFER, fbo);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, textures[i], 0);
        assert(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE);
        std::vector<unsigned char> data(size_t(widths[i]) * heights[i] * 4);
        glReadPixels(0, 0, widths[i], heights[i], GL_RGBA, GL_UNSIGNED_BYTE, data.data());
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        return data;
    };
    auto render = [&](int i) { for (int n = 0; n < 3; ++n) assert(sr_room_render(rooms[i]) == 0); };
    auto difference = [](const auto& a, const auto& b) {
        double sum = 0;
        for (size_t i = 0; i < a.size(); ++i) sum += abs(int(a[i]) - int(b[i]));
        return sum / a.size();
    };
    for (int i = 0; i < 2; ++i) {
        glBindTexture(GL_TEXTURE_2D, textures[i]);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, widths[i], heights[i], 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glBindTexture(GL_TEXTURE_2D, 0);
        rooms[i] = sr_room_create(display, context);
        assert(rooms[i]);
        assert(sr_room_set_output(rooms[i], textures[i], widths[i], heights[i]) == 0);
        const float centre[] = {0, 0, 0}, colour[] = {1, 0.3f, 0.1f};
        assert(sr_room_set_orb(rooms[i], 1, centre, 1, colour, 3) == 0);
        camera(i, 0);
        render(i);
    }
    auto a = pixels(0), b = pixels(1);
    assert(*std::max_element(a.begin(), a.end()) > 0);
    camera(0, 2);
    render(0);
    assert(difference(a, pixels(0)) > 1);
    assert(b == pixels(1)); // Drawing A must never write B's target.
    render(1);
    assert(difference(b, pixels(1)) < 1); // Drawing B still uses its own camera.
    camera(1, -2);
    render(1);
    assert(difference(b, pixels(1)) > 1);
    a = pixels(0);
    sr_room_destroy(rooms[1]);
    render(0); // Disconnecting one output leaves the other alive.
    assert(difference(a, pixels(0)) < 1);
    sr_room_destroy(rooms[0]);
    // Leaving 3D must not terminate the EGL display owned by the shell.
    assert(eglQueryString(display, EGL_EXTENSIONS));
    assert(eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, context));
    rooms[0] = sr_room_create(display, context);
    assert(rooms[0]);
    assert(sr_room_set_output(rooms[0], textures[0], widths[0], heights[0]) == 0);
    camera(0, 0);
    render(0);
    sr_room_destroy(rooms[0]);
    glDeleteFramebuffers(1, &fbo);
    glDeleteTextures(2, textures);
    eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroyContext(display, context);
    eglTerminate(display);
    gbm_device_destroy(gbm);
    close(fd);
    puts("independent scenes: camera, targets, mixed sizes and teardown passed");
}
