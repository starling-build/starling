#ifndef FLUTTER_X11_SERVER_H
#define FLUTTER_X11_SERVER_H

#include <stdint.h>
#include <sys/types.h>   /* pid_t — x11_server_window_pid */

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque server handle */
typedef struct X11Server X11Server;

/* --------------------------------------------------------------------------
 * Configuration
 * -------------------------------------------------------------------------- */

typedef struct X11ServerConfig {
    int      display_width;
    int      display_height;
    int      depth;             /* Color depth (default 24) */
    void*    userdata;

    /* Callbacks (all optional) */

    /* A new top-level window was mapped. */
    void (*on_window_mapped)(void* userdata, uint32_t window_id,
                              int x, int y, int width, int height);

    /* An override-redirect top-level was mapped: a menu, dropdown or tooltip.
     * These bypass the window manager by definition, so they get no title bar,
     * no dock entry and no placement of our own — they are drawn exactly where
     * the client asked, anchored to `parent_window_id` (the client's active
     * ordinary toplevel). Without this the window exists in the X server and is
     * never composited, so every menu in every X11 app is invisible.
     * x/y are device pixels RELATIVE TO parent_window_id's origin — the client
     * places menus in root space against where it thinks its toplevel is, which
     * is not where the shell composites it, so the difference is taken here. */
    void (*on_popup_mapped)(void* userdata, uint32_t window_id,
                             uint32_t parent_window_id,
                             int x, int y, int width, int height);

    /* An override-redirect top-level was unmapped or destroyed. */
    void (*on_popup_unmapped)(void* userdata, uint32_t window_id);

    /* A window was unmapped (hidden). */
    void (*on_window_unmapped)(void* userdata, uint32_t window_id);

    /* A window was destroyed. */
    void (*on_window_destroyed)(void* userdata, uint32_t window_id);

    /* A window was resized/moved. */
    void (*on_window_configured)(void* userdata, uint32_t window_id,
                                  int x, int y, int width, int height);

    /* DRI3: client presented a DMA-BUF for display.
     * fd:           DMA-BUF file descriptor.
     * width/height: Buffer dimensions in pixels.
     * stride:       Row stride in bytes.
     * fourcc:       DRM fourcc pixel format. */
    void (*on_present_buffer)(void* userdata, uint32_t window_id,
                               int fd, int width, int height,
                               int stride, uint32_t fourcc);

    /* Software present: the client drew into a window with core X (PutImage)
     * or MIT-SHM (ShmPutImage) rather than DRI3. This is how raster toolkits
     * paint — Qt's raster engine, GTK, xclock — so without it such clients map
     * a window and never show a pixel.
     *
     * pixels is RGBA8888, top-down, tightly packed (stride = width*4), and is
     * only valid for the duration of the call: upload it synchronously. */
    void (*on_present_image)(void* userdata, uint32_t window_id,
                              const uint8_t* pixels, int width, int height);

    /* Window title changed. */
    void (*on_title_changed)(void* userdata, uint32_t window_id,
                              const char* title);

    /* GetImage / screen capture: fill dst with the screen rect [x,y,w,h] as
     * X ZPixmap depth-32 BGRX, top-down (dst_len bytes, must be >= w*h*4).
     * Returns 1 on success, 0 if no frame is available yet. Optional — when
     * NULL, GetImage returns a black frame. */
    int (*capture_screen)(void* userdata, int x, int y, int width, int height,
                           uint8_t* dst, int dst_len);
} X11ServerConfig;

/* --------------------------------------------------------------------------
 * Lifecycle
 * -------------------------------------------------------------------------- */

/* Create an X11 server listening on the given display number.
 * Creates /tmp/.X11-unix/X<display_num> socket.
 * Returns NULL on failure. */
X11Server* x11_server_create(int display_num, const X11ServerConfig* config);

/* Destroy the server and free all resources. */
void x11_server_destroy(X11Server* server);

/* --------------------------------------------------------------------------
 * Event loop
 * -------------------------------------------------------------------------- */

/* Return the listening socket fd for external polling. */
int x11_server_get_fd(X11Server* server);

/* Return all active fds (listen + client fds) for external polling.
 * Writes up to max_fds fds into the fds array. Returns the count. */
int x11_server_get_all_fds(X11Server* server, int* fds, int max_fds);

/* Set a callback that's called when a new client connects.
 * The callback receives the client's fd so it can be added to epoll. */
typedef void (*X11ClientConnectCallback)(int client_fd, void* userdata);
void x11_server_set_client_connect_callback(X11Server* server,
                                             X11ClientConnectCallback callback,
                                             void* userdata);

/* Set the epoll fd for automatic client fd registration.
 * When set, new client fds are added to this epoll automatically. */
void x11_server_set_epoll_fd(X11Server* server, int epoll_fd);

/* Accept new connections and process pending client data. */
void x11_server_dispatch(X11Server* server);

/* Return non-zero if there are active client connections. */
int x11_server_has_clients(X11Server* server);

/* --------------------------------------------------------------------------
 * Input — send events to X11 clients
 * -------------------------------------------------------------------------- */

/* Set focus to a window (sends FocusIn/FocusOut events). */
void x11_server_set_focus(X11Server* server, uint32_t window_id);

/* Send pointer motion to the focused window. */
void x11_server_pointer_motion(X11Server* server, int x, int y);

/* Send pointer button press/release.
 * button: X11 button number (1=left, 2=middle, 3=right).
 * x, y: coordinates relative to the window. */
void x11_server_pointer_button(X11Server* server, uint32_t button,
                                int pressed, int x, int y);

/* Send key press/release (evdev keycode). */
void x11_server_key_event(X11Server* server, uint32_t keycode, int pressed);

/* Ask a window to close (WM_DELETE_WINDOW). Advisory — clients may ignore it,
 * so a caller that must see the app go away follows up with
 * x11_server_window_pid() and a signal. */
void x11_server_close_window(X11Server* server, uint32_t window_id);

/* pid of the client owning a window, from peer credentials. 0 if unknown. */
pid_t x11_server_window_pid(X11Server* server, uint32_t window_id);

/* Send EnterNotify to a window. */
void x11_server_enter_notify(X11Server* server, uint32_t window_id,
                              int x, int y);

/* Send LeaveNotify to a window. */
void x11_server_leave_notify(X11Server* server, uint32_t window_id,
                              int x, int y);

/* --------------------------------------------------------------------------
 * Window management — compositor → X11 client
 * -------------------------------------------------------------------------- */

/* Send ConfigureNotify to resize a window. */
void x11_server_configure_window(X11Server* server, uint32_t window_id,
                                  int width, int height);

/* Send buffer release (PresentIdleNotify) so client can reuse the pixmap. */
void x11_server_release_buffer(X11Server* server, uint32_t window_id);

/* --------------------------------------------------------------------------
 * Timer fds — for external epoll integration
 * -------------------------------------------------------------------------- */

/* Return the resize debounce timer fd. */
int x11_server_get_resize_timer_fd(X11Server* server);

/* Flush a pending resize (called when resize timer fires). */
void x11_server_flush_resize(X11Server* server);

/* Return the VBlank timer fd (~60Hz pacing). */
int x11_server_get_vblank_timer_fd(X11Server* server);

/* Arm the VBlank timer at ~60fps (16ms interval). */
void x11_server_arm_vblank_timer(X11Server* server);
/// Stops it again. The timer only has work while a client is connected;
/// left armed it is the desktop's largest idle cost (see the note in
/// x11_update_vblank_timer).
void x11_server_disarm_vblank_timer(X11Server* server);

/* Process VBlank tick — send queued PresentComplete/IdleNotify events. */
void x11_server_vblank_tick(X11Server* server);

#ifdef __cplusplus
}
#endif

#endif /* FLUTTER_X11_SERVER_H */
