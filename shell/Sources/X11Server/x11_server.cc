/*
 * x11_server.cc — Minimal X11 server for GPU-accelerated clients (C++ rewrite)
 *
 * Implements the core X11 protocol (connection handshake, window management)
 * plus DRI3 (DMA-BUF buffer sharing) and Present (vsync buffer swap).
 *
 * Only supports GPU rendering path — no software rendering (PutImage/GetImage).
 */

#include "include/x11_server.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <algorithm>
#include <utility>
#include <new>
#include <unistd.h>
#include <sys/syscall.h>
#include <errno.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/eventfd.h>
#include <sys/epoll.h>
#include <signal.h>
#include <time.h>
#include <sys/timerfd.h>
#include <pthread.h>
#include <sys/ipc.h>
#include <sys/shm.h>
#include <sys/mman.h>
#include <map>
#include <dirent.h>
extern "C" {
#include <X11/xshmfence.h>
#include <drm/drm_fourcc.h>
#include <gbm.h>
}

/* ========================================================================== */
/* DRI3 render node selection                                                  */
/* ========================================================================== */

/* The render node we hand to DRI3 clients MUST be the GPU the compositor
 * itself renders on. It used to be hardcoded to renderD128 — "the first
 * render node", which is the right answer only on a single-GPU box. On a
 * switchable-graphics laptop it is whichever card enumerated first, and that
 * can be the one nobody drives the display with: on the 14ARP8 dev box
 * renderD128 is the NVIDIA card (GL there is zink-on-NVK) while the AMD iGPU
 * drives the panel and runs the compositor.
 *
 * Getting this wrong does NOT fail visibly on the client side. The client
 * renders perfectly happily on the wrong GPU, allocates its buffers there,
 * and hands them over through DRI3 — and every eglCreateImageKHR in the
 * compositor then fails with EGL_BAD_ALLOC, because those buffers belong to
 * a device its EGL display knows nothing about. The window maps, presents
 * frames forever, and composites as NOTHING. That reads as "this app doesn't
 * render" rather than "the server handed it the wrong GPU". Zoom lost a day
 * to exactly this. (The VM harness hit the same trap pointing virgl at
 * nouveau — see test/vm-harness/launch-vm-2604.sh.)
 *
 * Resolution order:
 *   1. STARLING_X11_RENDER_NODE — explicit override, wins outright.
 *   2. The render node of FLUTTER_DRM_DEVICE, i.e. the card the compositor
 *      was told to scan out on. Same PCI device => imports work. This is the
 *      answer in a real session, where the session launcher always sets it.
 *   3. First render node whose driver is a display-capable one we prefer
 *      (amdgpu/i915/xe/radeon) over anything else — matches pick_rendernode()
 *      in the VM harness.
 *   4. renderD128, the historical guess.
 */
static std::string sysfs_driver_of(const char* render_node_name) {
    char path[256];
    snprintf(path, sizeof(path), "/sys/class/drm/%s/device/uevent", render_node_name);
    FILE* f = fopen(path, "r");
    if (!f) return "";
    char line[256];
    std::string drv;
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "DRIVER=", 7) == 0) {
            drv = line + 7;
            while (!drv.empty() && (drv.back() == '\n' || drv.back() == '\r')) drv.pop_back();
            break;
        }
    }
    fclose(f);
    return drv;
}

/* The render node that sits on the same DRM device as `card_path`
 * (/dev/dri/cardN) — /sys/class/drm/cardN/device/drm/ lists every node the
 * device exposes, so the renderD* sibling there is by construction the same
 * GPU. */
static std::string render_node_for_card(const char* card_path) {
    const char* base = strrchr(card_path, '/');
    base = base ? base + 1 : card_path;
    char dir_path[256];
    snprintf(dir_path, sizeof(dir_path), "/sys/class/drm/%s/device/drm", base);
    DIR* d = opendir(dir_path);
    if (!d) return "";
    std::string found;
    struct dirent* e;
    while ((e = readdir(d)) != nullptr) {
        if (strncmp(e->d_name, "renderD", 7) == 0) {
            found = std::string("/dev/dri/") + e->d_name;
            break;
        }
    }
    closedir(d);
    return found;
}

/* Resolved once — every DRI3Open must hand out the SAME device, or clients
 * disagree with each other about which GPU the pixmaps live on. */
static const char* dri3_render_node_path() {
    static std::string cached;
    static bool resolved = false;
    if (resolved) return cached.c_str();
    resolved = true;

    if (const char* env = getenv("STARLING_X11_RENDER_NODE")) {
        if (env[0] != '\0') {
            cached = env;
            fprintf(stderr, "[X11Server] render node %s (STARLING_X11_RENDER_NODE)\n",
                    cached.c_str());
            return cached.c_str();
        }
    }

    if (const char* card = getenv("FLUTTER_DRM_DEVICE")) {
        if (card[0] != '\0') {
            std::string node = render_node_for_card(card);
            if (!node.empty()) {
                cached = node;
                fprintf(stderr, "[X11Server] render node %s (compositor's %s)\n",
                        cached.c_str(), card);
                return cached.c_str();
            }
            fprintf(stderr, "[X11Server] no render node for %s — falling back\n", card);
        }
    }

    std::string fallback;
    DIR* d = opendir("/dev/dri");
    if (d) {
        std::vector<std::string> nodes;
        struct dirent* e;
        while ((e = readdir(d)) != nullptr) {
            if (strncmp(e->d_name, "renderD", 7) == 0) nodes.push_back(e->d_name);
        }
        closedir(d);
        std::sort(nodes.begin(), nodes.end());
        for (const auto& n : nodes) {
            std::string drv = sysfs_driver_of(n.c_str());
            if (drv == "amdgpu" || drv == "i915" || drv == "xe" || drv == "radeon") {
                cached = "/dev/dri/" + n;
                fprintf(stderr, "[X11Server] render node %s (driver %s)\n",
                        cached.c_str(), drv.c_str());
                return cached.c_str();
            }
            if (fallback.empty()) fallback = "/dev/dri/" + n;
        }
    }

    cached = fallback.empty() ? "/dev/dri/renderD128" : fallback;
    fprintf(stderr, "[X11Server] render node %s (fallback)\n", cached.c_str());
    return cached.c_str();
}

/* ========================================================================== */
/* X11 Protocol Constants                                                      */
/* ========================================================================== */

/* Core request opcodes */
static constexpr uint8_t X11_CREATE_WINDOW         = 1;
static constexpr uint8_t X11_CHANGE_WINDOW_ATTRS   = 2;
static constexpr uint8_t X11_GET_WINDOW_ATTRS      = 3;
static constexpr uint8_t X11_DESTROY_WINDOW        = 4;
static constexpr uint8_t X11_MAP_WINDOW            = 8;
static constexpr uint8_t X11_UNMAP_WINDOW          = 10;
static constexpr uint8_t X11_CONFIGURE_WINDOW      = 12;
static constexpr uint8_t X11_GET_GEOMETRY          = 14;
static constexpr uint8_t X11_QUERY_TREE            = 15;
static constexpr uint8_t X11_INTERN_ATOM           = 16;
static constexpr uint8_t X11_GET_ATOM_NAME         = 17;
static constexpr uint8_t X11_CHANGE_PROPERTY       = 18;
static uint32_t x11_timestamp(void);
static constexpr uint8_t X11_GET_PROPERTY          = 20;
static constexpr uint8_t X11_DELETE_PROPERTY       = 19;
static constexpr uint8_t X11_GRAB_POINTER          = 26;
static constexpr uint8_t X11_UNGRAB_POINTER        = 27;
static constexpr uint8_t X11_GRAB_BUTTON           = 28;
static constexpr uint8_t X11_UNGRAB_BUTTON         = 29;
static constexpr uint8_t X11_GRAB_KEY              = 33;
static constexpr uint8_t X11_UNGRAB_KEY            = 34;
static constexpr uint8_t X11_QUERY_POINTER         = 38;
static constexpr uint8_t X11_CHANGE_GC             = 56;
static constexpr uint8_t X11_CREATE_GC             = 55;
static constexpr uint8_t X11_FREE_GC               = 60;
static constexpr uint8_t X11_CREATE_PIXMAP         = 53;
static constexpr uint8_t X11_FREE_PIXMAP           = 54;
static constexpr uint8_t X11_CLEAR_AREA            = 61;
static constexpr uint8_t X11_QUERY_EXTENSION       = 98;
static constexpr uint8_t X11_LIST_EXTENSIONS       = 99;
static constexpr uint8_t X11_GET_KEYBOARD_MAPPING  = 101;
static constexpr uint8_t X11_CHANGE_KEYBOARD_CTRL  = 102;
static constexpr uint8_t X11_GET_KEYBOARD_CTRL     = 103;
static constexpr uint8_t X11_CREATE_COLORMAP       = 78;
static constexpr uint8_t X11_FREE_COLORMAP         = 79;
static constexpr uint8_t X11_GET_SELECTION_OWNER   = 23;
static constexpr uint8_t X11_SET_SELECTION_OWNER   = 22;
static constexpr uint8_t X11_CONVERT_SELECTION     = 24;
static constexpr uint8_t X11_SEND_EVENT            = 25;
static constexpr uint8_t X11_GRAB_SERVER           = 36;
static constexpr uint8_t X11_UNGRAB_SERVER         = 37;
static constexpr uint8_t X11_TRANSLATE_COORDS      = 40;
static constexpr uint8_t X11_WARP_POINTER          = 41;
static constexpr uint8_t X11_SET_INPUT_FOCUS       = 42;
static constexpr uint8_t X11_GET_INPUT_FOCUS       = 43;
static constexpr uint8_t X11_OPEN_FONT             = 45;
static constexpr uint8_t X11_CLOSE_FONT            = 46;
static constexpr uint8_t X11_QUERY_FONT            = 47;
static constexpr uint8_t X11_LIST_FONTS            = 49;
static constexpr uint8_t X11_SET_CLIP_RECTANGLES   = 59;
static constexpr uint8_t X11_COPY_AREA             = 62;
static constexpr uint8_t X11_POLY_FILL_RECT        = 70;
static constexpr uint8_t X11_IMAGE_TEXT8           = 76;
static constexpr uint8_t X11_ALLOC_COLOR           = 84;
static constexpr uint8_t X11_QUERY_COLORS          = 91;
static constexpr uint8_t X11_LOOKUP_COLOR          = 92;
static constexpr uint8_t X11_QUERY_BEST_SIZE       = 97;
static constexpr uint8_t X11_LIST_INSTALLED_CMAPS  = 83;
static constexpr uint8_t X11_BELL                  = 104;
static constexpr uint8_t X11_KILL_CLIENT           = 113;
static constexpr uint8_t X11_GET_MODIFIER_MAPPING  = 119;
static constexpr uint8_t X11_SET_MODIFIER_MAPPING  = 118;
static constexpr uint8_t X11_CHANGE_HOSTS          = 109;
static constexpr uint8_t X11_LIST_HOSTS            = 110;
static constexpr uint8_t X11_SET_ACCESS_CONTROL    = 111;
static constexpr uint8_t X11_NO_OPERATION          = 127;

/* Event types */
static constexpr uint8_t X11_KEY_PRESS_EVENT       = 2;
static constexpr uint8_t X11_KEY_RELEASE_EVENT     = 3;
static constexpr uint8_t X11_BUTTON_PRESS_EVENT    = 4;
static constexpr uint8_t X11_BUTTON_RELEASE_EVENT  = 5;
static constexpr uint8_t X11_MOTION_NOTIFY_EVENT   = 6;
static constexpr uint8_t X11_ENTER_NOTIFY_EVENT    = 7;
static constexpr uint8_t X11_LEAVE_NOTIFY_EVENT    = 8;
static constexpr uint8_t X11_FOCUS_IN_EVENT        = 9;
static constexpr uint8_t X11_FOCUS_OUT_EVENT       = 10;
static constexpr uint8_t X11_EXPOSE_EVENT          = 12;
static constexpr uint8_t X11_MAP_NOTIFY_EVENT      = 19;
static constexpr uint8_t X11_CONFIGURE_NOTIFY      = 22;
static constexpr uint8_t X11_PROPERTY_NOTIFY       = 28;
static constexpr uint8_t X11_CLIENT_MESSAGE        = 33;
static constexpr uint8_t X11_GENERIC_EVENT         = 35;

/* Present event sub-types (inside GenericEvent) */
static constexpr uint16_t PRESENT_CONFIGURE_NOTIFY = 0;
static constexpr uint16_t PRESENT_COMPLETE_NOTIFY  = 1;
static constexpr uint16_t PRESENT_IDLE_NOTIFY      = 2;

/* ========================================================================== */
/* Internal Data Structures                                                    */
/* ========================================================================== */

static constexpr int MAX_CLIENTS = 32;
static constexpr int CLIENT_BUF_SIZE = 4 * 1024 * 1024;  /* VSCode _NET_WM_ICON can be 1.4MB+ */

struct X11Property {
    uint32_t atom = 0;
    uint32_t type = 0;
    uint8_t  format = 0;     /* 8, 16, or 32 */
    std::vector<uint8_t> data;
    uint32_t length = 0;     /* number of elements */
};

struct PresentReg {
    uint32_t eid = 0;
    uint32_t mask = 0;
    int      client = -1;
};

struct XI2Sub {
    int      client = -1;        /* client index, or -1 if unused */
    uint16_t deviceid = 0;       /* 0=XIAllDevices, 1=XIAllMasterDevices, N=specific device */
    uint32_t event_mask = 0;     /* bitmask: (1<<XI_ButtonPress)|(1<<XI_ButtonRelease)|(1<<XI_Motion) etc */
};

struct X11Fence {
    uint32_t xid = 0;
    int      fd = -1;                  /* memfd backing the xshmfence */
    struct xshmfence *shm_fence = nullptr;  /* mapped xshmfence pointer */
    int      triggered = 0;

    X11Fence() = default;

    ~X11Fence() {
        if (shm_fence) xshmfence_unmap_shm(shm_fence);
        if (fd >= 0) close(fd);
    }

    /* Move constructor */
    X11Fence(X11Fence&& o) noexcept
        : xid(o.xid), fd(o.fd), shm_fence(o.shm_fence), triggered(o.triggered) {
        o.fd = -1;
        o.shm_fence = nullptr;
    }

    /* Move assignment */
    X11Fence& operator=(X11Fence&& o) noexcept {
        if (this != &o) {
            if (shm_fence) xshmfence_unmap_shm(shm_fence);
            if (fd >= 0) close(fd);
            xid = o.xid; fd = o.fd; shm_fence = o.shm_fence; triggered = o.triggered;
            o.fd = -1; o.shm_fence = nullptr;
        }
        return *this;
    }

    /* Delete copy */
    X11Fence(const X11Fence&) = delete;
    X11Fence& operator=(const X11Fence&) = delete;
};

struct X11Window {
    uint32_t id = 0;
    uint32_t parent_id = 0;
    int16_t  x = 0, y = 0;
    uint16_t width = 0, height = 0;
    uint16_t border_width = 0;
    uint32_t event_mask = 0;
    int      mapped = 0;
    int      override_redirect = 0;
    int      pointer_entered = 0;  /* 1 after first MotionNotify (EnterNotify sent) */
    uint32_t owner_client = 0;  /* index into clients[] */
    std::vector<X11Property> properties;

    /* Present event registrations — Chrome uses multiple eids */
    std::vector<PresentReg> present_regs;

    /* Front buffer tracking for cross-swapchain IdleNotify. */
    uint32_t front_pixmap = 0;
    uint32_t front_fence_xid = 0;
    uint32_t front_eid = 0;
    int      front_client = 0;
    uint32_t front_serial = 0;
    int      front_idle_sent = 0;  /* 1 after vblank sends IdleNotify+CompleteNotify */

    /* XI2 input event subscriptions per client */
    std::vector<XI2Sub> xi2_subs;

    /* CPU backing store for clients that paint with core X / MIT-SHM instead
     * of DRI3 — Qt's raster engine, GTK, xclock. RGBA8888, top-down,
     * shadow_w*shadow_h*4. Empty until the client's first PutImage. */
    std::vector<uint8_t> shadow;
    uint16_t shadow_w = 0, shadow_h = 0;
};

struct X11Pixmap {
    uint32_t id = 0;
    int      dma_fd = -1;     /* DMA-BUF fd (-1 if none) */
    uint16_t width = 0, height = 0;
    uint16_t stride = 0;
    uint32_t fourcc = 0;
    uint32_t window_id = 0;  /* associated window */
    uint32_t last_serial = 0; /* last PresentPixmap serial for this pixmap */
    uint32_t fence_xid = 0;  /* DRI3 fence XID for PresentIdleNotify */
    int      fence_fd = -1;   /* eventfd backing the fence — write 1 to trigger */
    uint8_t  server_allocated = 0; /* storage GBM-allocated by us (known LINEAR) */
    /* CPU shadow (RGBA) for core-X painted pixmaps: Qt's no-SHM backingstore
     * PutImages into a pixmap and CopyAreas it to the window. */
    std::vector<uint8_t> shadow;

    X11Pixmap() = default;

    ~X11Pixmap() {
        if (dma_fd >= 0) close(dma_fd);
        if (fence_fd >= 0) close(fence_fd);
    }

    /* Move constructor */
    X11Pixmap(X11Pixmap&& o) noexcept
        : id(o.id), dma_fd(o.dma_fd), width(o.width), height(o.height),
          stride(o.stride), fourcc(o.fourcc), window_id(o.window_id),
          last_serial(o.last_serial), fence_xid(o.fence_xid), fence_fd(o.fence_fd),
          server_allocated(o.server_allocated), shadow(std::move(o.shadow)) {
        o.dma_fd = -1;
        o.fence_fd = -1;
    }

    /* Move assignment */
    X11Pixmap& operator=(X11Pixmap&& o) noexcept {
        if (this != &o) {
            if (dma_fd >= 0) close(dma_fd);
            if (fence_fd >= 0) close(fence_fd);
            id = o.id; dma_fd = o.dma_fd; width = o.width; height = o.height;
            stride = o.stride; fourcc = o.fourcc; window_id = o.window_id;
            last_serial = o.last_serial; fence_xid = o.fence_xid; fence_fd = o.fence_fd;
            server_allocated = o.server_allocated;
            shadow = std::move(o.shadow);
            o.dma_fd = -1; o.fence_fd = -1;
        }
        return *this;
    }

    /* Delete copy */
    X11Pixmap(const X11Pixmap&) = delete;
    X11Pixmap& operator=(const X11Pixmap&) = delete;
};

struct X11Atom {
    uint32_t id = 0;
    std::string name;
};

struct X11Extension {
    char     name[32] = {};
    uint8_t  major_opcode = 0;
    uint8_t  first_event = 0;
    uint8_t  first_error = 0;
};

struct X11Client {
    int      fd;
    pid_t    pid;            /* peer credentials, captured at accept */
    int      authenticated;  /* completed handshake */
    uint8_t  buf[CLIENT_BUF_SIZE];
    int      buf_len;
    uint16_t sequence;       /* request sequence number */
    int      pending_fds[8]; /* fd queue */
    int      pending_fd_count;
    uint8_t  deferred_reply[512];
    int      deferred_reply_len;
};

struct X11Server {
    int listen_fd;      /* abstract namespace socket */
    int listen_fd2;     /* filesystem socket (fallback) */
    int display_num;

    X11Client clients[MAX_CLIENTS];
    int client_count;

    std::vector<X11Window> windows;
    std::vector<X11Pixmap> pixmaps;
    std::vector<X11Fence> fences;
    std::vector<X11Atom> atoms;
    std::vector<X11Extension> extensions;

    /* MIT-SHM segments attached by clients (shmseg XID → mapped memory).
     * SysV via ShmAttach (is_mmap=0) or POSIX fd via ShmAttachFd (is_mmap=1).
     * ShmGetImage writes captured screen pixels straight into these. */
    struct ShmSeg { void* addr; size_t size; uint8_t is_mmap = 0; };
    std::map<uint32_t, ShmSeg> shm_segments;

    uint32_t next_resource_id;
    uint32_t root_window_id;

    /* Focus tracking */
    uint32_t focus_window_id;
    int      focus_client_idx;

    /* Active pointer grab (XGrabPointer). A menu grabs the pointer so that the
     * click which dismisses it is CONSUMED rather than also landing on whatever
     * sits underneath — without this, dismissing Zoom's app grid also activates
     * the link behind it. Zero window means no grab. */
    uint32_t grab_window;
    int      grab_client;
    int      grab_owner_events;

    uint64_t sync_counter;
    int sync_waiting;

    /* Resize state */
    int resize_timer_fd;
    pthread_mutex_t resize_lock;
    uint32_t resize_target_window;
    uint16_t resize_target_w;
    uint16_t resize_target_h;
    int resize_pending;
    int resize_timer_armed;

    /* VBlank timer */
    int vblank_timer_fd;
    struct {
        uint32_t window;
        uint32_t serial;
        uint32_t eid;
        int      client;
        uint32_t pixmap;
        uint32_t fence_xid;
    } pending_complete[16];
    int pending_complete_count;

    /* Present extension state */
    uint32_t present_event_base;
    uint64_t present_msc;
    uint32_t glx_pbuffer_id;
    uint32_t glx_pbuffer_width;
    uint32_t glx_pbuffer_height;

    /* Pointer state tracking */
    int16_t pointer_x = 0;
    int16_t pointer_y = 0;
    uint16_t button_state = 0;  /* X11 button mask (bit 8 = btn1, bit 9 = btn2, ...) */

    /* Keyboard modifier state — reported in the `state` field of KeyPress/
     * KeyRelease/ButtonPress events. Without it every key looks unmodified, so
     * Shift+key gives lowercase and Ctrl/Alt shortcuts never fire.
     * Bits: ShiftMask 1, LockMask 2, ControlMask 4, Mod1(Alt) 8, Mod4(Super) 64. */
    uint16_t key_mod_state = 0;

    X11ClientConnectCallback on_client_connect;
    void* on_client_connect_userdata;
    int epoll_fd;
    int render_device_fd;

    X11ServerConfig config;

    ~X11Server() {
        for (int i = 0; i < client_count; i++) {
            if (clients[i].fd >= 0) {
                /* Close pending fds for this client */
                for (int f = 0; f < clients[i].pending_fd_count; f++) {
                    if (clients[i].pending_fds[f] >= 0)
                        close(clients[i].pending_fds[f]);
                }
                close(clients[i].fd);
            }
        }
        /* vectors (windows, pixmaps, fences, atoms, extensions) auto-destruct */
        if (render_device_fd >= 0) close(render_device_fd);
        if (resize_timer_fd >= 0) close(resize_timer_fd);
        if (vblank_timer_fd >= 0) close(vblank_timer_fd);
        pthread_mutex_destroy(&resize_lock);
        if (listen_fd >= 0) close(listen_fd);
        if (listen_fd2 >= 0) close(listen_fd2);

        char socket_path[128];
        snprintf(socket_path, sizeof(socket_path),
                 "/tmp/.X11-unix/X%d", display_num);
        unlink(socket_path);
    }
};

/* ========================================================================== */
/* Forward declarations                                                        */
/* ========================================================================== */

static uint32_t x11_timestamp(void);
static void handle_client_data(X11Server* server, int client_idx);
static void handle_connection_setup(X11Server* server, int client_idx);
static void handle_request(X11Server* server, int client_idx,
                           uint8_t opcode, const uint8_t* data, int len);
static void send_xi2_crossing_event(X11Server* server, X11Window* win,
                                     uint16_t evtype, int x, int y);
static void send_to_client(X11Server* server, int client_idx,
                           const void* data, int len);
static uint32_t intern_atom(X11Server* server, const char* name, int only_if_exists);

/* Find the window struct by ID. Returns nullptr if not found. */
static X11Window* find_window(X11Server* server, uint32_t window_id) {
    for (auto& w : server->windows) {
        if (w.id == window_id)
            return &w;
    }
    return nullptr;
}

/* Redirect a pointer event to the grabbing window, per XGrabPointer semantics.
 *
 * With owner_events false the grab window takes the event; with owner_events
 * true, events over a window belonging to the grabbing client are reported
 * normally and only the rest are redirected. The point is that the click which
 * dismisses a menu gets consumed by the menu instead of also reaching the
 * widget underneath.
 *
 * Applied to button press/release only, deliberately. That is the case with a
 * confirmed repro (dismissing Zoom's app grid also activated the link behind
 * it); redirecting motion as well would risk hover regressions across every
 * other X11 app for no demonstrated gain.
 *
 * `*x`/`*y` come in local to `win` and are rewritten local to the grab window,
 * going via root coordinates. Both windows' positions live in the same X
 * coordinate space, so this stays correct even though that space does not match
 * where the shell actually composites them.
 *
 * Returns the window the event should be delivered to. */
static X11Window* apply_pointer_grab(X11Server* server, X11Window* win,
                                      int* x, int* y) {
    if (!server->grab_window) return win;
    X11Window* grab = find_window(server, server->grab_window);
    if (!grab || !grab->mapped) {
        /* Grab window went away without an UngrabPointer — drop the grab
         * rather than swallowing every event from here on. */
        server->grab_window = 0;
        server->grab_client = -1;
        return win;
    }
    if (grab == win) return win;
    if (server->grab_owner_events &&
        win->owner_client == grab->owner_client) {
        return win;
    }
    int root_x = win->x + *x;
    int root_y = win->y + *y;
    *x = root_x - grab->x;
    *y = root_y - grab->y;
    return grab;
}

/* Which ordinary toplevel a menu/tooltip belongs to. X11 gives us no parent for
 * an override-redirect window — its `parent` is the root — so we infer it: the
 * focused window when that belongs to the same client, else that client's most
 * recently mapped ordinary toplevel. The shell anchors the popup to this window,
 * so it follows the right window across spaces and disappears with it. */
static uint32_t popup_parent_for(X11Server* server, const X11Window* popup) {
    X11Window* focus = find_window(server, server->focus_window_id);
    if (focus && !focus->override_redirect && focus->mapped &&
        focus->owner_client == popup->owner_client &&
        focus->parent_id == server->root_window_id) {
        return focus->id;
    }
    uint32_t best = 0;
    for (auto& w : server->windows) {
        if (w.id == popup->id) continue;
        if (w.owner_client != popup->owner_client) continue;
        if (w.override_redirect || !w.mapped) continue;
        if (w.parent_id != server->root_window_id) continue;
        if (w.width <= 1 || w.height <= 1) continue;
        best = w.id;   /* later entries are more recently created */
    }
    return best;
}

/* --------------------------------------------------------------------------
 * Software present path
 *
 * DRI3 clients hand us a dma-buf and we import it as a texture. Raster clients
 * (Qt's xcb backing store, GTK, xclock) instead push pixels with core-X
 * PutImage or MIT-SHM ShmPutImage. Those land here: we keep a per-window CPU
 * shadow, blit each update into it, and hand the whole thing to the shell as
 * RGBA for upload. Without this such clients map a window and never paint.
 * -------------------------------------------------------------------------- */

/* Allocate/resize the window's shadow to its current geometry. Contents are
 * preserved on resize where they overlap, so a client that only repaints a
 * damaged sub-rect after a resize doesn't flash garbage. */
static void ensure_shadow(X11Window* win) {
    if (win->shadow_w == win->width && win->shadow_h == win->height &&
        !win->shadow.empty()) {
        return;
    }
    std::vector<uint8_t> next(static_cast<size_t>(win->width) * win->height * 4, 0);
    if (!win->shadow.empty()) {
        int copy_w = win->shadow_w < win->width ? win->shadow_w : win->width;
        int copy_h = win->shadow_h < win->height ? win->shadow_h : win->height;
        for (int row = 0; row < copy_h; row++) {
            memcpy(next.data() + static_cast<size_t>(row) * win->width * 4,
                   win->shadow.data() + static_cast<size_t>(row) * win->shadow_w * 4,
                   static_cast<size_t>(copy_w) * 4);
        }
    }
    win->shadow.swap(next);
    win->shadow_w = win->width;
    win->shadow_h = win->height;
}

/* Blit a ZPixmap rectangle into the window shadow.
 *
 * X ZPixmap at depth 24/32 on a little-endian server is B,G,R,X per pixel;
 * the texture path wants R,G,B,A. Alpha is forced opaque because depth-24
 * clients leave the pad byte undefined — honouring it renders them invisible. */
static void blit_zpixmap(X11Window* win, const uint8_t* src,
                         int src_w, int src_h, int src_stride,
                         int dst_x, int dst_y) {
    ensure_shadow(win);
    if (win->shadow.empty()) return;

    for (int row = 0; row < src_h; row++) {
        int y = dst_y + row;
        if (y < 0 || y >= win->shadow_h) continue;
        const uint8_t* s = src + static_cast<size_t>(row) * src_stride;
        uint8_t* d = win->shadow.data() + static_cast<size_t>(y) * win->shadow_w * 4;
        for (int col = 0; col < src_w; col++) {
            int x = dst_x + col;
            if (x < 0 || x >= win->shadow_w) continue;
            const uint8_t* sp = s + static_cast<size_t>(col) * 4;
            uint8_t* dp = d + static_cast<size_t>(x) * 4;
            dp[0] = sp[2];
            dp[1] = sp[1];
            dp[2] = sp[0];
            dp[3] = 0xff;
        }
    }
}

/* Hand the shadow to the shell for texture upload. */
static void flush_shadow(X11Server* server, X11Window* win) {
    if (!win->mapped || win->shadow.empty()) return;
    if (!server->config.on_present_image) return;
    server->config.on_present_image(server->config.userdata, win->id,
                                    win->shadow.data(),
                                    win->shadow_w, win->shadow_h);
}

/* Resolve a PutImage/ShmPutImage drawable to the top-level window it should
 * paint into. Clients commonly draw into a child window, and those coordinates
 * are child-relative, so accumulate each child's origin on the way up —
 * without this a child's content lands at the wrong place in the shadow. */
static X11Window* shadow_target(X11Server* server, uint32_t drawable,
                                int* off_x, int* off_y) {
    *off_x = 0;
    *off_y = 0;
    X11Window* win = find_window(server, drawable);
    for (int guard = 0; win && guard < 16; guard++) {
        if (win->parent_id == server->root_window_id) return win;
        X11Window* parent = find_window(server, win->parent_id);
        if (!parent) break;
        *off_x += win->x;
        *off_y += win->y;
        win = parent;
    }
    return win;
}

/* Find a pixmap by ID. Returns nullptr if not found. */
static X11Pixmap* find_pixmap(X11Server* server, uint32_t pixmap_id) {
    for (auto& p : server->pixmaps) {
        if (p.id == pixmap_id)
            return &p;
    }
    return nullptr;
}

/* Server-side pixmap storage: allocate a linear GBM buffer and attach its
 * dmabuf to the pixmap. Used when a client asks DRI3 for the buffers of a
 * pixmap the server owns (NameWindowPixmap backing store — WeChat's Qt GL
 * path) instead of attaching its own via PixmapFromBuffer (Chrome's path).
 * The bo is destroyed right after export: the exported fd keeps the
 * underlying buffer alive, so no gbm bookkeeping outlives this call. */
static int pixmap_allocate_storage(X11Server* server, X11Pixmap* pix) {
    static struct gbm_device* gbm_dev = nullptr;
    if (!gbm_dev && server->render_device_fd >= 0) {
        gbm_dev = gbm_create_device(server->render_device_fd);
    }
    if (!gbm_dev || pix->width == 0 || pix->height == 0) return -1;
    struct gbm_bo* bo = gbm_bo_create(gbm_dev, pix->width, pix->height,
                                      GBM_FORMAT_XRGB8888,
                                      GBM_BO_USE_LINEAR | GBM_BO_USE_RENDERING);
    if (!bo) {
        fprintf(stderr, "[X11Server] pixmap 0x%x: gbm_bo_create %ux%u failed\n",
                pix->id, pix->width, pix->height);
        return -1;
    }
    int fd = gbm_bo_get_fd(bo);
    pix->stride = static_cast<uint16_t>(gbm_bo_get_stride(bo));
    pix->fourcc = DRM_FORMAT_XRGB8888;
    pix->dma_fd = fd;
    pix->server_allocated = 1;
    gbm_bo_destroy(bo);
    fprintf(stderr, "[X11Server] pixmap 0x%x: allocated %ux%u stride=%u fd=%d\n",
            pix->id, pix->width, pix->height, pix->stride, fd);
    return fd;
}

/* Helper: find-or-create a property on a window by atom. Returns reference. */
static X11Property& set_property(X11Window* win, uint32_t atom) {
    for (auto& p : win->properties) {
        if (p.atom == atom) {
            p.data.clear();
            return p;
        }
    }
    win->properties.emplace_back();
    auto& p = win->properties.back();
    p.atom = atom;
    return p;
}

/* Forward declarations for per-extension handlers */
static void handle_dri3(X11Server* server, int client_idx, uint8_t minor,
                        const uint8_t* data, int len, uint16_t seq);
static void handle_present(X11Server* server, int client_idx, uint8_t minor,
                           const uint8_t* data, int len, uint16_t seq);
static void handle_glx(X11Server* server, int client_idx, uint8_t minor,
                       const uint8_t* data, int len, uint16_t seq);
static void handle_render(X11Server* server, int client_idx, uint8_t minor,
                          const uint8_t* data, int len, uint16_t seq);
static void handle_randr(X11Server* server, int client_idx, uint8_t minor,
                         const uint8_t* data, int len, uint16_t seq);
static void handle_composite(X11Server* server, int client_idx, uint8_t minor,
                             const uint8_t* data, int len, uint16_t seq);
static void handle_xfixes(X11Server* server, int client_idx, uint8_t minor,
                          const uint8_t* data, int len, uint16_t seq);
static void handle_shape(X11Server* server, int client_idx, uint8_t minor,
                         const uint8_t* data, int len, uint16_t seq);
static void handle_xi2(X11Server* server, int client_idx, uint8_t minor,
                       const uint8_t* data, int len, uint16_t seq);
static void handle_sync(X11Server* server, int client_idx, uint8_t minor,
                        const uint8_t* data, int len, uint16_t seq);
static void handle_shm(X11Server* server, int client_idx, uint8_t minor,
                       const uint8_t* data, int len, uint16_t seq);
static void handle_xkb(X11Server* server, int client_idx, uint8_t minor,
                       const uint8_t* data, int len, uint16_t seq);
static void handle_xtest(X11Server* server, int client_idx, uint8_t minor,
                         const uint8_t* data, int len, uint16_t seq);
static void send_resize_events(X11Server* server, X11Window* win,
                                uint16_t w, uint16_t h);

/* ========================================================================== */
/* Lifecycle                                                                   */
/* ========================================================================== */

extern "C" {

X11Server* x11_server_create(int display_num, const X11ServerConfig* config) {
    /* Ignore SIGPIPE */
    signal(SIGPIPE, SIG_IGN);

    X11Server* server = new(std::nothrow) X11Server();
    if (!server) return nullptr;

    std::memset(server->clients, 0, sizeof(server->clients));
    for (int i = 0; i < MAX_CLIENTS; i++) {
        server->clients[i].fd = -1;
    }

    server->config = *config;
    server->display_num = display_num;
    server->next_resource_id = 0x00200000;
    server->root_window_id = 0x00000001;
    server->focus_window_id = 0;
    server->focus_client_idx = -1;
    server->grab_window = 0;
    server->grab_client = -1;
    server->grab_owner_events = 0;
    server->client_count = 0;
    server->epoll_fd = -1;
    server->listen_fd = -1;
    server->listen_fd2 = -1;
    server->render_device_fd = open(dri3_render_node_path(), O_RDWR);
    server->sync_counter = 0;
    server->sync_waiting = 0;
    server->resize_pending = 0;
    server->resize_timer_armed = 0;
    server->resize_target_window = 0;
    server->resize_target_w = 0;
    server->resize_target_h = 0;
    server->pending_complete_count = 0;
    server->present_event_base = 0;
    server->present_msc = 0;
    server->glx_pbuffer_id = 0;
    server->glx_pbuffer_width = 0;
    server->glx_pbuffer_height = 0;
    server->on_client_connect = nullptr;
    server->on_client_connect_userdata = nullptr;
    server->vblank_timer_fd = -1;

    server->resize_timer_fd = timerfd_create(CLOCK_MONOTONIC, TFD_NONBLOCK);
    pthread_mutex_init(&server->resize_lock, nullptr);
    server->vblank_timer_fd = timerfd_create(CLOCK_MONOTONIC, TFD_NONBLOCK);

    /* Pre-intern ALL 68 protocol-predefined atoms, in Xatom.h order so they
     * receive their REQUIRED fixed ids (XA_WINDOW=33, XA_WM_NAME=39, ...).
     * intern_atom hands out size+1, so order IS the id assignment. Custom
     * atoms then start at 69. Before this, "WINDOW" interned to 11 — every
     * property type stored through it looked mistyped to clients that use
     * the predefined constants (Chromium), e.g. _NET_SUPPORTING_WM_CHECK
     * read back with type 11 (CUT_BUFFER2) instead of XA_WINDOW. */
    static const char* kPredefinedAtoms[] = {
        "PRIMARY", "SECONDARY", "ARC", "ATOM", "BITMAP", "CARDINAL",
        "COLORMAP", "CURSOR", "CUT_BUFFER0", "CUT_BUFFER1", "CUT_BUFFER2",
        "CUT_BUFFER3", "CUT_BUFFER4", "CUT_BUFFER5", "CUT_BUFFER6",
        "CUT_BUFFER7", "DRAWABLE", "FONT", "INTEGER", "PIXMAP", "POINT",
        "RECTANGLE", "RESOURCE_MANAGER", "RGB_COLOR_MAP", "RGB_BEST_MAP",
        "RGB_BLUE_MAP", "RGB_DEFAULT_MAP", "RGB_GRAY_MAP", "RGB_GREEN_MAP",
        "RGB_RED_MAP", "STRING", "VISUALID", "WINDOW", "WM_COMMAND",
        "WM_HINTS", "WM_CLIENT_MACHINE", "WM_ICON_NAME", "WM_ICON_SIZE",
        "WM_NAME", "WM_NORMAL_HINTS", "WM_SIZE_HINTS", "WM_ZOOM_HINTS",
        "MIN_SPACE", "NORM_SPACE", "MAX_SPACE", "END_SPACE",
        "SUPERSCRIPT_X", "SUPERSCRIPT_Y", "SUBSCRIPT_X", "SUBSCRIPT_Y",
        "UNDERLINE_POSITION", "UNDERLINE_THICKNESS", "STRIKEOUT_ASCENT",
        "STRIKEOUT_DESCENT", "ITALIC_ANGLE", "X_HEIGHT", "QUAD_WIDTH",
        "WEIGHT", "POINT_SIZE", "RESOLUTION", "COPYRIGHT", "NOTICE",
        "FONT_NAME", "FAMILY_NAME", "FULL_NAME", "CAP_HEIGHT", "WM_CLASS",
        "WM_TRANSIENT_FOR",
    };
    for (const char* an : kPredefinedAtoms) intern_atom(server, an, 0);
    intern_atom(server, "WM_PROTOCOLS", 0);
    intern_atom(server, "WM_DELETE_WINDOW", 0);
    intern_atom(server, "UTF8_STRING", 0);
    intern_atom(server, "_NET_WM_NAME", 0);
    intern_atom(server, "_NET_WM_PID", 0);
    intern_atom(server, "_NET_SUPPORTED", 0);
    intern_atom(server, "_NET_SUPPORTING_WM_CHECK", 0);
    intern_atom(server, "_NET_WM_STATE", 0);
    intern_atom(server, "_NET_WM_STATE_FULLSCREEN", 0);
    intern_atom(server, "_NET_WM_STATE_MAXIMIZED_VERT", 0);
    intern_atom(server, "_NET_WM_STATE_MAXIMIZED_HORZ", 0);
    intern_atom(server, "_NET_WM_STATE_FOCUSED", 0);
    intern_atom(server, "_NET_WM_STATE_HIDDEN", 0);
    intern_atom(server, "_NET_WM_WINDOW_TYPE", 0);
    intern_atom(server, "_NET_WM_WINDOW_TYPE_NORMAL", 0);
    intern_atom(server, "_NET_WM_WINDOW_TYPE_DIALOG", 0);
    intern_atom(server, "_NET_WM_WINDOW_TYPE_POPUP_MENU", 0);
    intern_atom(server, "_NET_WM_WINDOW_TYPE_TOOLTIP", 0);
    intern_atom(server, "_NET_WM_WINDOW_TYPE_NOTIFICATION", 0);
    intern_atom(server, "_NET_ACTIVE_WINDOW", 0);
    intern_atom(server, "_NET_CLIENT_LIST", 0);
    intern_atom(server, "_NET_CLIENT_LIST_STACKING", 0);
    intern_atom(server, "_NET_WORKAREA", 0);
    intern_atom(server, "_NET_NUMBER_OF_DESKTOPS", 0);
    intern_atom(server, "_NET_CURRENT_DESKTOP", 0);
    intern_atom(server, "_NET_DESKTOP_VIEWPORT", 0);
    intern_atom(server, "_NET_FRAME_EXTENTS", 0);
    intern_atom(server, "_NET_WM_MOVERESIZE", 0);
    intern_atom(server, "_NET_REQUEST_FRAME_EXTENTS", 0);
    intern_atom(server, "_NET_WM_SYNC_REQUEST", 0);
    intern_atom(server, "_NET_WM_SYNC_REQUEST_COUNTER", 0);
    intern_atom(server, "WM_CHANGE_STATE", 0);
    intern_atom(server, "WM_STATE", 0);
    intern_atom(server, "WM_TAKE_FOCUS", 0);

    /* Create root window */
    {
        X11Window root;
        root.id = server->root_window_id;
        root.parent_id = 0;
        root.x = 0; root.y = 0;
        root.width = static_cast<uint16_t>(config->display_width);
        root.height = static_cast<uint16_t>(config->display_height);
        root.mapped = 1;
        root.owner_client = static_cast<uint32_t>(-1);
        server->windows.push_back(std::move(root));
    }

    /* Set EWMH properties on root window */
    {
        X11Window* root = find_window(server, server->root_window_id);
        uint32_t net_supported_atom = intern_atom(server, "_NET_SUPPORTED", 0);
        uint32_t cardinal_atom = intern_atom(server, "CARDINAL", 0);
        uint32_t atom_atom = intern_atom(server, "ATOM", 0);
        uint32_t workarea_atom = intern_atom(server, "_NET_WORKAREA", 0);
        uint32_t net_wm_name_atom = intern_atom(server, "_NET_WM_NAME", 0);
        uint32_t net_active_atom = intern_atom(server, "_NET_ACTIVE_WINDOW", 0);
        uint32_t net_wm_state_atom = intern_atom(server, "_NET_WM_STATE", 0);
        uint32_t net_frame_atom = intern_atom(server, "_NET_FRAME_EXTENTS", 0);
        uint32_t net_client_list = intern_atom(server, "_NET_CLIENT_LIST", 0);
        uint32_t net_num_desktops = intern_atom(server, "_NET_NUMBER_OF_DESKTOPS", 0);
        uint32_t net_cur_desktop = intern_atom(server, "_NET_CURRENT_DESKTOP", 0);
        uint32_t net_desktop_vp = intern_atom(server, "_NET_DESKTOP_VIEWPORT", 0);
        uint32_t net_wm_check = intern_atom(server, "_NET_SUPPORTING_WM_CHECK", 0);
        uint32_t window_atom = intern_atom(server, "WINDOW", 0);

        /* _NET_SUPPORTED */
        {
            uint32_t supported[] = {
                net_wm_name_atom, net_active_atom, net_wm_state_atom,
                net_frame_atom, net_client_list, workarea_atom,
                net_num_desktops, net_cur_desktop, net_desktop_vp,
            };
            int ns = static_cast<int>(sizeof(supported) / sizeof(supported[0]));
            auto& p = set_property(root, net_supported_atom);
            p.type = atom_atom;
            p.format = 32;
            p.length = static_cast<uint32_t>(ns);
            p.data.assign(reinterpret_cast<uint8_t*>(supported),
                          reinterpret_cast<uint8_t*>(supported) + ns * 4);
        }

        /* _NET_WORKAREA */
        {
            uint32_t workarea[] = { 0, 0, static_cast<uint32_t>(config->display_width),
                                    static_cast<uint32_t>(config->display_height) };
            auto& p = set_property(root, workarea_atom);
            p.type = cardinal_atom;
            p.format = 32;
            p.length = 4;
            p.data.assign(reinterpret_cast<uint8_t*>(workarea),
                          reinterpret_cast<uint8_t*>(workarea) + 16);
        }

        /* _NET_NUMBER_OF_DESKTOPS */
        {
            uint32_t one = 1;
            auto& p = set_property(root, net_num_desktops);
            p.type = cardinal_atom;
            p.format = 32;
            p.length = 1;
            p.data.assign(reinterpret_cast<uint8_t*>(&one),
                          reinterpret_cast<uint8_t*>(&one) + 4);
        }

        /* _NET_CURRENT_DESKTOP */
        {
            uint32_t zero = 0;
            auto& p = set_property(root, net_cur_desktop);
            p.type = cardinal_atom;
            p.format = 32;
            p.length = 1;
            p.data.assign(reinterpret_cast<uint8_t*>(&zero),
                          reinterpret_cast<uint8_t*>(&zero) + 4);
        }

        /* No _NET_SUPPORTING_WM_CHECK on the root: there is no WM here, and
         * claiming one (it used to point at the root itself) sends Chromium
         * down WM-present code paths. Xwayland's bare root — the proven
         * working environment for WeChat/Chrome — has no WM markers. */
        (void)net_wm_check;
        (void)window_atom;

        /* RESOURCE_MANAGER */
        {
            uint32_t resource_mgr_atom = intern_atom(server, "RESOURCE_MANAGER", 0);
            uint32_t string_atom = intern_atom(server, "STRING", 0);
            int screen_mm_w = config->display_width / 4;
            int xft_dpi = (screen_mm_w > 0) ? static_cast<int>(config->display_width * 25.4 / screen_mm_w) : 96;
            const char* dpi_env = getenv("FLUTTER_DRM_DPI");
            if (dpi_env) xft_dpi = static_cast<int>(atof(dpi_env) * 96);
            char resource_str[256];
            int rlen = snprintf(resource_str, sizeof(resource_str),
                                "Xft.dpi:\t%d\n"
                                "Xft.antialias:\t1\n"
                                "Xft.hinting:\t1\n"
                                "Xft.hintstyle:\thintslight\n"
                                "Xft.rgba:\trgb\n", xft_dpi);
            auto& p = set_property(root, resource_mgr_atom);
            p.type = string_atom;
            p.format = 8;
            p.length = static_cast<uint32_t>(rlen);
            p.data.assign(reinterpret_cast<uint8_t*>(resource_str),
                          reinterpret_cast<uint8_t*>(resource_str) + rlen);
        }
    }

    /* Register extensions */
    {
        auto add_ext = [&](const char* n, uint8_t maj, uint8_t fevt, uint8_t ferr) {
            X11Extension ext;
            std::memset(&ext, 0, sizeof(ext));
            strncpy(ext.name, n, sizeof(ext.name) - 1);
            ext.major_opcode = maj;
            ext.first_event = fevt;
            ext.first_error = ferr;
            server->extensions.push_back(ext);
        };
        add_ext("DRI3", 149, 0, 0);
        add_ext("Present", 148, 0, 0);
        add_ext("GLX", 128, 0, 0);
        add_ext("RENDER", 139, 0, 0);
        add_ext("RANDR", 140, 89, 147);
        add_ext("Composite", 142, 0, 0);
        add_ext("XFIXES", 138, 87, 140);
        add_ext("SHAPE", 130, 65, 0);
        add_ext("XInputExtension", 131, 66, 129);
        add_ext("SYNC", 134, 100, 150);
        add_ext("MIT-SHM", 135, 64, 128);
        add_ext("BIG-REQUESTS", 133, 0, 0);
        add_ext("Generic Event Extension", 143, 0, 0);
        add_ext("XTEST", 144, 0, 0);
    }

    /* Create Unix socket */
    char socket_dir[] = "/tmp/.X11-unix";
    mkdir(socket_dir, 0777);

    char socket_path[128];
    snprintf(socket_path, sizeof(socket_path), "%s/X%d", socket_dir, display_num);
    unlink(socket_path);

    /* Abstract namespace socket */
    server->listen_fd = socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK, 0);
    if (server->listen_fd < 0) {
        fprintf(stderr, "[X11Server] socket() failed: %s\n", strerror(errno));
        delete server;
        return nullptr;
    }

    struct sockaddr_un addr;
    std::memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    snprintf(addr.sun_path + 1, sizeof(addr.sun_path) - 1,
             "/tmp/.X11-unix/X%d", display_num);
    socklen_t addr_len = static_cast<socklen_t>(
        offsetof(struct sockaddr_un, sun_path) + 1 + strlen(addr.sun_path + 1));

    if (bind(server->listen_fd, reinterpret_cast<struct sockaddr*>(&addr), addr_len) < 0) {
        fprintf(stderr, "[X11Server] abstract bind failed: %s, trying filesystem\n",
                strerror(errno));
        std::memset(&addr, 0, sizeof(addr));
        addr.sun_family = AF_UNIX;
        strncpy(addr.sun_path, socket_path, sizeof(addr.sun_path) - 1);
        if (bind(server->listen_fd, reinterpret_cast<struct sockaddr*>(&addr), sizeof(addr)) < 0) {
            fprintf(stderr, "[X11Server] bind(%s) failed: %s\n",
                    socket_path, strerror(errno));
            close(server->listen_fd);
            server->listen_fd = -1;
            delete server;
            return nullptr;
        }
        chmod(socket_path, 0777);
    }

    if (listen(server->listen_fd, 32) < 0) {
        fprintf(stderr, "[X11Server] listen() failed: %s\n", strerror(errno));
        close(server->listen_fd);
        server->listen_fd = -1;
        delete server;
        return nullptr;
    }

    /* Also create filesystem socket */
    int fs_fd = socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK, 0);
    if (fs_fd >= 0) {
        std::memset(&addr, 0, sizeof(addr));
        addr.sun_family = AF_UNIX;
        strncpy(addr.sun_path, socket_path, sizeof(addr.sun_path) - 1);
        if (bind(fs_fd, reinterpret_cast<struct sockaddr*>(&addr), sizeof(addr)) == 0) {
            chmod(socket_path, 0777);
            listen(fs_fd, 32);
            server->listen_fd2 = fs_fd;
        } else {
            close(fs_fd);
            server->listen_fd2 = -1;
        }
    } else {
        server->listen_fd2 = -1;
    }

    fprintf(stderr, "[X11Server] Listening on :%d (abstract + %s)\n",
            display_num, socket_path);

    /* Additional EWMH properties on root */
    {
        X11Window* root = find_window(server, server->root_window_id);
        if (root) {
            uint32_t net_supported = intern_atom(server, "_NET_SUPPORTED", 0);
            uint32_t atom_type = intern_atom(server, "ATOM", 0);
            uint32_t supported_atoms[] = {
                intern_atom(server, "_NET_SUPPORTED", 0),
                intern_atom(server, "_NET_WM_NAME", 0),
                intern_atom(server, "_NET_WM_STATE", 0),
                intern_atom(server, "_NET_WM_STATE_FULLSCREEN", 0),
                intern_atom(server, "_NET_WM_STATE_MAXIMIZED_VERT", 0),
                intern_atom(server, "_NET_WM_STATE_MAXIMIZED_HORZ", 0),
                intern_atom(server, "_NET_WM_STATE_FOCUSED", 0),
                intern_atom(server, "_NET_WM_STATE_HIDDEN", 0),
                intern_atom(server, "_NET_WM_WINDOW_TYPE", 0),
                intern_atom(server, "_NET_WM_WINDOW_TYPE_NORMAL", 0),
                intern_atom(server, "_NET_WM_WINDOW_TYPE_DIALOG", 0),
                intern_atom(server, "_NET_WM_WINDOW_TYPE_POPUP_MENU", 0),
                intern_atom(server, "_NET_WM_WINDOW_TYPE_TOOLTIP", 0),
                intern_atom(server, "_NET_WM_WINDOW_TYPE_NOTIFICATION", 0),
                intern_atom(server, "_NET_ACTIVE_WINDOW", 0),
                intern_atom(server, "_NET_CLIENT_LIST", 0),
                intern_atom(server, "_NET_WORKAREA", 0),
                intern_atom(server, "_NET_NUMBER_OF_DESKTOPS", 0),
                intern_atom(server, "_NET_CURRENT_DESKTOP", 0),
                intern_atom(server, "_NET_FRAME_EXTENTS", 0),
                intern_atom(server, "_NET_WM_MOVERESIZE", 0),
            };
            int n_supported = static_cast<int>(sizeof(supported_atoms) / sizeof(supported_atoms[0]));
            {
                auto& prop = set_property(root, net_supported);
                prop.type = atom_type;
                prop.format = 32;
                prop.length = static_cast<uint32_t>(n_supported);
                prop.data.assign(reinterpret_cast<uint8_t*>(supported_atoms),
                                 reinterpret_cast<uint8_t*>(supported_atoms) + n_supported * 4);
            }

            /* No _NET_SUPPORTING_WM_CHECK — see the root-property setup
             * above: no WM here, and claiming one misroutes Chromium. */

            /* _NET_NUMBER_OF_DESKTOPS */
            {
                uint32_t net_num_d = intern_atom(server, "_NET_NUMBER_OF_DESKTOPS", 0);
                uint32_t cardinal_type = intern_atom(server, "CARDINAL", 0);
                auto& prop3 = set_property(root, net_num_d);
                prop3.type = cardinal_type;
                prop3.format = 32;
                prop3.length = 1;
                uint32_t one = 1;
                prop3.data.assign(reinterpret_cast<uint8_t*>(&one),
                                  reinterpret_cast<uint8_t*>(&one) + 4);
            }

            /* _NET_CURRENT_DESKTOP */
            {
                uint32_t net_cur_d = intern_atom(server, "_NET_CURRENT_DESKTOP", 0);
                uint32_t cardinal_type = intern_atom(server, "CARDINAL", 0);
                auto& prop4 = set_property(root, net_cur_d);
                prop4.type = cardinal_type;
                prop4.format = 32;
                prop4.length = 1;
                uint32_t zero = 0;
                prop4.data.assign(reinterpret_cast<uint8_t*>(&zero),
                                  reinterpret_cast<uint8_t*>(&zero) + 4);
            }

            /* _NET_WORKAREA */
            {
                uint32_t net_wa = intern_atom(server, "_NET_WORKAREA", 0);
                uint32_t cardinal_type = intern_atom(server, "CARDINAL", 0);
                auto& prop5 = set_property(root, net_wa);
                prop5.type = cardinal_type;
                prop5.format = 32;
                prop5.length = 4;
                uint32_t wa[4] = { 0, 0, static_cast<uint32_t>(config->display_width),
                                   static_cast<uint32_t>(config->display_height) };
                prop5.data.assign(reinterpret_cast<uint8_t*>(wa),
                                  reinterpret_cast<uint8_t*>(wa) + 16);
            }

            /* _NET_WM_NAME on root */
            {
                uint32_t net_wm_name = intern_atom(server, "_NET_WM_NAME", 0);
                uint32_t utf8_type = intern_atom(server, "UTF8_STRING", 0);
                const char* wm_name = "FlutterShell";
                auto& prop_name = set_property(root, net_wm_name);
                prop_name.type = utf8_type;
                prop_name.format = 8;
                prop_name.length = static_cast<uint32_t>(strlen(wm_name));
                prop_name.data.assign(reinterpret_cast<const uint8_t*>(wm_name),
                                      reinterpret_cast<const uint8_t*>(wm_name) + strlen(wm_name));
            }

            fprintf(stderr, "[X11Server] EWMH: %d atoms in _NET_SUPPORTED\n", n_supported);
        }
    }

    return server;
}

void x11_server_destroy(X11Server* server) {
    if (!server) return;
    delete server;
}

} /* extern "C" */

/* ========================================================================== */
/* Atom management                                                             */
/* ========================================================================== */

static uint32_t intern_atom(X11Server* server, const char* name, int only_if_exists) {
    for (auto& a : server->atoms) {
        if (a.name == name)
            return a.id;
    }

    if (only_if_exists) return 0;

    uint32_t id = static_cast<uint32_t>(server->atoms.size()) + 1;
    X11Atom atom;
    atom.id = id;
    atom.name = name;
    server->atoms.push_back(std::move(atom));
    return id;
}

/* ========================================================================== */
/* Send helpers                                                                */
/* ========================================================================== */

static int consume_pending_fd(X11Client* client) {
    if (client->pending_fd_count <= 0) return -1;
    int fd = client->pending_fds[0];
    client->pending_fd_count--;
    std::memmove(client->pending_fds, client->pending_fds + 1,
            static_cast<size_t>(client->pending_fd_count) * sizeof(int));
    return fd;
}

static void send_to_client(X11Server* server, int client_idx,
                           const void* data, int len) {
    if (client_idx < 0 || client_idx >= server->client_count) return;
    X11Client* client = &server->clients[client_idx];
    if (client->fd < 0) return;

    const uint8_t* d = reinterpret_cast<const uint8_t*>(data);
    if (len >= 8) {
        uint16_t pkt_seq = *reinterpret_cast<const uint16_t*>(d + 2);
        if (d[0] == 1) {
            uint32_t extra = *reinterpret_cast<const uint32_t*>(d + 4);
            fprintf(stderr, "[X11Server] fd=%d SEND REPLY seq=%d len=%d extra=%d "
                    "bytes=[%02x %02x %02x %02x %02x %02x %02x %02x]\n",
                    client->fd, pkt_seq, len, extra,
                    d[0], d[1], d[2], d[3], d[4], d[5], d[6], d[7]);
        } else if (d[0] == 0) {
            fprintf(stderr, "[X11Server] fd=%d SEND ERROR seq=%d code=%d\n",
                    client->fd, pkt_seq, d[1]);
        } else {
            fprintf(stderr, "[X11Server] fd=%d SEND EVENT type=%d seq=%d\n",
                    client->fd, d[0], pkt_seq);
        }
    }

    const uint8_t* p = reinterpret_cast<const uint8_t*>(data);
    int remaining = len;
    while (remaining > 0) {
        ssize_t n = write(client->fd, p, static_cast<size_t>(remaining));
        if (n <= 0) break;
        p += n;
        remaining -= static_cast<int>(n);
    }
}

/* ========================================================================== */
/* Event loop                                                                  */
/* ========================================================================== */

extern "C" {

int x11_server_get_fd(X11Server* server) {
    return server ? server->listen_fd : -1;
}

int x11_server_get_all_fds(X11Server* server, int* fds, int max_fds) {
    if (!server) return 0;
    int count = 0;
    if (count < max_fds && server->listen_fd >= 0)
        fds[count++] = server->listen_fd;
    if (count < max_fds && server->listen_fd2 >= 0)
        fds[count++] = server->listen_fd2;
    for (int i = 0; i < server->client_count && count < max_fds; i++) {
        if (server->clients[i].fd >= 0)
            fds[count++] = server->clients[i].fd;
    }
    return count;
}

/* Defined further down, beside the timer it drives; used by the connect and
 * disconnect paths below. */
static void x11_update_vblank_timer(X11Server* server);

void x11_server_dispatch(X11Server* server) {
    if (!server) return;

    /* Accept new connections from both sockets */
    int listen_fds[] = { server->listen_fd, server->listen_fd2 };
    for (int lf = 0; lf < 2; lf++) {
    if (listen_fds[lf] < 0) continue;
    while (1) {
        int client_fd = accept(listen_fds[lf], nullptr, nullptr);
        if (client_fd < 0) break;

        int slot = -1;
        for (int ci = 0; ci < server->client_count; ci++) {
            if (server->clients[ci].fd < 0) {
                slot = ci;
                break;
            }
        }
        if (slot < 0) {
            if (server->client_count >= MAX_CLIENTS) {
                fprintf(stderr, "[X11Server] Too many clients (%d)\n", server->client_count);
                close(client_fd);
                continue;
            }
            slot = server->client_count++;
        }

        int flags = fcntl(client_fd, F_GETFL, 0);
        if (flags >= 0) {
            fcntl(client_fd, F_SETFL, flags & ~O_NONBLOCK);
        }

        X11Client* client = &server->clients[slot];
        std::memset(client, 0, sizeof(*client));
        client->fd = client_fd;
        client->pending_fd_count = 0;
        /* Peer credentials, captured once at accept: this is the only
         * trustworthy way to learn who is on the other end. _NET_WM_PID is a
         * property the client sets voluntarily — Zoom's xcb windows carry no
         * app_id either, and we are not going to trust a second optional
         * property to decide what to signal. Needed so the dock's Quit can
         * actually terminate an app rather than just forgetting its window. */
        struct ucred cred;
        socklen_t cred_len = sizeof(cred);
        if (getsockopt(client_fd, SOL_SOCKET, SO_PEERCRED, &cred, &cred_len) == 0) {
            client->pid = cred.pid;
        } else {
            client->pid = 0;
        }
        fprintf(stderr, "[X11Server] Client connected (fd=%d pid=%d)\n",
                client_fd, client->pid);
        /* Somebody is here now: the vblank timer has work to do. */
        x11_update_vblank_timer(server);
    }
    }

    /* Poll all client fds */
    struct pollfd pfds[MAX_CLIENTS];
    int npfds = 0;
    for (int i = 0; i < server->client_count; i++) {
        if (server->clients[i].fd >= 0) {
            pfds[npfds].fd = server->clients[i].fd;
            pfds[npfds].events = POLLIN;
            pfds[npfds].revents = 0;
            npfds++;
        }
    }
    if (npfds > 0) poll(pfds, static_cast<nfds_t>(npfds), 0);

    /* Process data from each client */
    for (int i = 0; i < server->client_count; i++) {
        if (server->clients[i].fd < 0) continue;

        int has_data = 0;
        for (int p = 0; p < npfds; p++) {
            if (pfds[p].fd == server->clients[i].fd && (pfds[p].revents & POLLIN)) {
                has_data = 1;
                break;
            }
        }
        if (!has_data && server->clients[i].buf_len == 0) continue;

        int space = CLIENT_BUF_SIZE - server->clients[i].buf_len;
        if (space <= 0) continue;

        struct iovec iov;
        iov.iov_base = server->clients[i].buf + server->clients[i].buf_len;
        iov.iov_len = static_cast<size_t>(space);
        uint8_t cmsg_buf[CMSG_SPACE(sizeof(int) * 4)];
        struct msghdr msg;
        std::memset(&msg, 0, sizeof(msg));
        msg.msg_iov = &iov; msg.msg_iovlen = 1;
        msg.msg_control = cmsg_buf;
        msg.msg_controllen = sizeof(cmsg_buf);

        ssize_t n = recvmsg(server->clients[i].fd, &msg, MSG_DONTWAIT);
        if (n > 0) {
            fprintf(stderr, "[X11Server] fd=%d read %zd bytes (total buf=%d)\n",
                    server->clients[i].fd, n, server->clients[i].buf_len + static_cast<int>(n));
            struct cmsghdr* cmsg;
            for (cmsg = CMSG_FIRSTHDR(&msg); cmsg; cmsg = CMSG_NXTHDR(&msg, cmsg)) {
                if (cmsg->cmsg_level == SOL_SOCKET && cmsg->cmsg_type == SCM_RIGHTS) {
                    int nfds = static_cast<int>((cmsg->cmsg_len - CMSG_LEN(0)) / sizeof(int));
                    int* fds = reinterpret_cast<int*>(CMSG_DATA(cmsg));
                    for (int f = 0; f < nfds; f++) {
                        if (server->clients[i].pending_fd_count < 8) {
                            server->clients[i].pending_fds[server->clients[i].pending_fd_count++] = fds[f];
                        } else {
                            close(fds[f]);
                        }
                        fprintf(stderr, "[X11Server] Received fd=%d from client (queued #%d)\n",
                                fds[f], server->clients[i].pending_fd_count);
                    }
                }
            }

            server->clients[i].buf_len += static_cast<int>(n);
            while (server->clients[i].buf_len < CLIENT_BUF_SIZE) {
                struct iovec iov2;
                iov2.iov_base = server->clients[i].buf + server->clients[i].buf_len;
                iov2.iov_len = static_cast<size_t>(CLIENT_BUF_SIZE - server->clients[i].buf_len);
                /* Must carry cmsg space: without it the kernel silently DROPS
                 * SCM_RIGHTS fds that ride on these drained reads (WeChat's
                 * ShmAttachFd fd arrived here and vanished). */
                uint8_t cmsg_buf2[CMSG_SPACE(sizeof(int) * 4)];
                struct msghdr msg2;
                std::memset(&msg2, 0, sizeof(msg2));
                msg2.msg_iov = &iov2; msg2.msg_iovlen = 1;
                msg2.msg_control = cmsg_buf2;
                msg2.msg_controllen = sizeof(cmsg_buf2);
                ssize_t n2 = recvmsg(server->clients[i].fd, &msg2, MSG_DONTWAIT);
                if (n2 <= 0) break;
                struct cmsghdr* cmsg2;
                for (cmsg2 = CMSG_FIRSTHDR(&msg2); cmsg2; cmsg2 = CMSG_NXTHDR(&msg2, cmsg2)) {
                    if (cmsg2->cmsg_level == SOL_SOCKET && cmsg2->cmsg_type == SCM_RIGHTS) {
                        int nfds2 = static_cast<int>((cmsg2->cmsg_len - CMSG_LEN(0)) / sizeof(int));
                        int* fds2 = reinterpret_cast<int*>(CMSG_DATA(cmsg2));
                        for (int f = 0; f < nfds2; f++) {
                            if (server->clients[i].pending_fd_count < 8) {
                                server->clients[i].pending_fds[server->clients[i].pending_fd_count++] = fds2[f];
                            } else {
                                close(fds2[f]);
                            }
                        }
                    }
                }
                server->clients[i].buf_len += static_cast<int>(n2);
            }
            handle_client_data(server, i);
        } else if (n == 0 || (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK)) {
            fprintf(stderr, "[X11Server] Client disconnected (fd=%d)\n",
                    server->clients[i].fd);
            /* Close pending fds for this client */
            for (int pf = 0; pf < server->clients[i].pending_fd_count; pf++) {
                if (server->clients[i].pending_fds[pf] >= 0)
                    close(server->clients[i].pending_fds[pf]);
            }
            close(server->clients[i].fd);
            server->clients[i].fd = -1;
            /* And if that was the last one, the timer goes quiet again. */
            x11_update_vblank_timer(server);

            /* Clean up Present registrations and XI2 subscriptions */
            for (auto& cwin : server->windows) {
                cwin.present_regs.erase(
                    std::remove_if(cwin.present_regs.begin(), cwin.present_regs.end(),
                        [i](const PresentReg& r) { return r.client == i; }),
                    cwin.present_regs.end());
                cwin.xi2_subs.erase(
                    std::remove_if(cwin.xi2_subs.begin(), cwin.xi2_subs.end(),
                        [i](const XI2Sub& s) { return s.client == i; }),
                    cwin.xi2_subs.end());
            }

            /* Clean up windows owned by this client */
            for (auto it = server->windows.begin(); it != server->windows.end(); ) {
                if (static_cast<int>(it->owner_client) == i &&
                    it->id != server->root_window_id) {
                    uint32_t wid = it->id;
                    int is_toplevel = (it->parent_id == server->root_window_id);
                    int is_override = it->override_redirect;
                    fprintf(stderr, "[X11Server] Cleaning up window 0x%x from disconnected client\n", wid);

                    if (is_toplevel && !is_override && server->config.on_window_destroyed) {
                        server->config.on_window_destroyed(server->config.userdata, wid);
                    }
                    if (server->focus_window_id == wid) {
                        server->focus_window_id = 0;
                        server->focus_client_idx = -1;
                    }
                    /* Properties auto-freed by vector destructor */
                    it = server->windows.erase(it);
                } else {
                    ++it;
                }
            }

            /* Clean up orphaned pixmaps */
            server->pixmaps.erase(
                std::remove_if(server->pixmaps.begin(), server->pixmaps.end(),
                    [server](X11Pixmap& px) {
                        if (px.dma_fd >= 0) {
                            X11Window* pw = find_window(server, px.window_id);
                            if (!pw || pw->id == server->root_window_id) {
                                return true; /* destructor closes fds */
                            }
                        }
                        return false;
                    }),
                server->pixmaps.end());
        }
    }

    /* Flush deferred replies */
    for (int i = 0; i < server->client_count; i++) {
        X11Client* c = &server->clients[i];
        if (c->fd >= 0 && c->deferred_reply_len > 0) {
            const uint8_t* p = c->deferred_reply;
            int rem = c->deferred_reply_len;
            while (rem > 0) { ssize_t nn = write(c->fd, p, static_cast<size_t>(rem)); if (nn<=0) break; p+=nn; rem-=static_cast<int>(nn); }
            c->deferred_reply_len = 0;
        }
    }

    /* Re-poll once */
    if (x11_server_has_clients(server)) {
        struct pollfd rpfds[MAX_CLIENTS];
        int rn = 0;
        for (int i = 0; i < server->client_count; i++) {
            if (server->clients[i].fd >= 0) {
                rpfds[rn].fd = server->clients[i].fd;
                rpfds[rn].events = POLLIN;
                rpfds[rn].revents = 0;
                rn++;
            }
        }
        if (rn > 0 && poll(rpfds, static_cast<nfds_t>(rn), 1) > 0) {
            for (int i = 0; i < server->client_count; i++) {
                if (server->clients[i].fd < 0) continue;
                for (int p = 0; p < rn; p++) {
                    if (rpfds[p].fd == server->clients[i].fd &&
                        (rpfds[p].revents & POLLIN)) {
                        int space = CLIENT_BUF_SIZE - server->clients[i].buf_len;
                        if (space > 0) {
                            struct iovec iov3;
                            iov3.iov_base = server->clients[i].buf + server->clients[i].buf_len;
                            iov3.iov_len = static_cast<size_t>(space);
                            uint8_t cmsg_buf3[CMSG_SPACE(sizeof(int) * 4)];
                            struct msghdr msg3;
                            std::memset(&msg3, 0, sizeof(msg3));
                            msg3.msg_iov = &iov3; msg3.msg_iovlen = 1;
                            msg3.msg_control = cmsg_buf3;
                            msg3.msg_controllen = sizeof(cmsg_buf3);
                            ssize_t n3 = recvmsg(server->clients[i].fd, &msg3, MSG_DONTWAIT);
                            if (n3 > 0) {
                                struct cmsghdr* cm;
                                for (cm = CMSG_FIRSTHDR(&msg3); cm; cm = CMSG_NXTHDR(&msg3, cm)) {
                                    if (cm->cmsg_level == SOL_SOCKET && cm->cmsg_type == SCM_RIGHTS) {
                                        int nfds3 = static_cast<int>((cm->cmsg_len - CMSG_LEN(0)) / sizeof(int));
                                        int* fds3 = reinterpret_cast<int*>(CMSG_DATA(cm));
                                        for (int f = 0; f < nfds3; f++) {
                                            if (server->clients[i].pending_fd_count < 8)
                                                server->clients[i].pending_fds[server->clients[i].pending_fd_count++] = fds3[f];
                                            else close(fds3[f]);
                                        }
                                    }
                                }
                                server->clients[i].buf_len += static_cast<int>(n3);
                                handle_client_data(server, i);
                            }
                        }
                        break;
                    }
                }
            }
        }
    }
}

} /* extern "C" */

/* ========================================================================== */
/* Connection setup                                                            */
/* ========================================================================== */

static void handle_connection_setup(X11Server* server, int client_idx) {
    X11Client* client = &server->clients[client_idx];

    if (client->buf_len < 12) return;

    uint8_t byte_order = client->buf[0];
    (void)byte_order;

    uint16_t auth_name_len = *reinterpret_cast<uint16_t*>(client->buf + 6);
    uint16_t auth_data_len = *reinterpret_cast<uint16_t*>(client->buf + 8);
    int total = 12 + ((auth_name_len + 3) & ~3) + ((auth_data_len + 3) & ~3);

    if (client->buf_len < total) return;

    std::memmove(client->buf, client->buf + total, static_cast<size_t>(client->buf_len - total));
    client->buf_len -= total;

    int screen_w = server->config.display_width;
    int screen_h = server->config.display_height;
    int depth = server->config.depth > 0 ? server->config.depth : 24;
    (void)depth;

    const char* vendor = "The X.Org Foundation";
    int vendor_len = static_cast<int>(strlen(vendor));
    int vendor_pad = (4 - (vendor_len & 3)) & 3;

    int num_formats = 3;

    uint32_t visual_id = 0x22;
    uint32_t visual_id_32 = 0x22;
    uint32_t visual_id_24 = 0x21;
    int num_depths = 2;
    (void)visual_id_32;

    int format_size = num_formats * 8;
    int visual_size = 24;
    int depth24_size = 8 + 1 * visual_size;
    int depth32_size = (num_depths > 1) ? (8 + 1 * visual_size) : 0;
    int screen_size = 40 + depth24_size + depth32_size;

    int additional_data = 32 + vendor_len + vendor_pad + format_size + screen_size;
    int additional_words = additional_data / 4;
    (void)additional_words;

    int reply_size = 8 + additional_data + 64;
    std::vector<uint8_t> reply(static_cast<size_t>(reply_size), 0);
    int off = 0;

    /* Header */
    reply[off++] = 1;  /* Success */
    reply[off++] = 0;  /* Pad */
    *reinterpret_cast<uint16_t*>(&reply[off]) = 11; off += 2;
    *reinterpret_cast<uint16_t*>(&reply[off]) = 0;  off += 2;
    *reinterpret_cast<uint16_t*>(&reply[off]) = 0;  off += 2; /* placeholder */

    /* Server info */
    *reinterpret_cast<uint32_t*>(&reply[off]) = 12101018; off += 4;
    uint32_t id_base = 0x00200000 * static_cast<uint32_t>(client_idx + 1);
    *reinterpret_cast<uint32_t*>(&reply[off]) = id_base; off += 4;
    *reinterpret_cast<uint32_t*>(&reply[off]) = 0x001FFFFF; off += 4;
    *reinterpret_cast<uint32_t*>(&reply[off]) = 256; off += 4;
    *reinterpret_cast<uint16_t*>(&reply[off]) = static_cast<uint16_t>(vendor_len); off += 2;
    *reinterpret_cast<uint16_t*>(&reply[off]) = 65535; off += 2;
    reply[off++] = 1;
    reply[off++] = static_cast<uint8_t>(num_formats);
    reply[off++] = 0;
    reply[off++] = 0;
    reply[off++] = 32;
    reply[off++] = 32;
    reply[off++] = 8;
    reply[off++] = 255;
    *reinterpret_cast<uint32_t*>(&reply[off]) = 0; off += 4;

    /* Vendor string */
    std::memcpy(&reply[off], vendor, static_cast<size_t>(vendor_len));
    off += vendor_len + vendor_pad;

    /* Pixmap formats */
    reply[off] = 1; reply[off+1] = 1; reply[off+2] = 32; off += 8;
    reply[off] = 24; reply[off+1] = 32; reply[off+2] = 32; off += 8;
    reply[off] = 32; reply[off+1] = 32; reply[off+2] = 32; off += 8;

    /* Screen */
    *reinterpret_cast<uint32_t*>(&reply[off]) = server->root_window_id; off += 4;
    *reinterpret_cast<uint32_t*>(&reply[off]) = 0x20; off += 4;
    *reinterpret_cast<uint32_t*>(&reply[off]) = 0xFFFFFF; off += 4;
    *reinterpret_cast<uint32_t*>(&reply[off]) = 0x000000; off += 4;
    *reinterpret_cast<uint32_t*>(&reply[off]) = 0; off += 4;
    *reinterpret_cast<uint16_t*>(&reply[off]) = static_cast<uint16_t>(screen_w); off += 2;
    *reinterpret_cast<uint16_t*>(&reply[off]) = static_cast<uint16_t>(screen_h); off += 2;
    *reinterpret_cast<uint16_t*>(&reply[off]) = static_cast<uint16_t>(screen_w / 4); off += 2;
    *reinterpret_cast<uint16_t*>(&reply[off]) = static_cast<uint16_t>(screen_h / 4); off += 2;
    *reinterpret_cast<uint16_t*>(&reply[off]) = 1; off += 2;
    *reinterpret_cast<uint16_t*>(&reply[off]) = 1; off += 2;
    *reinterpret_cast<uint32_t*>(&reply[off]) = visual_id; off += 4;
    reply[off++] = 0;
    reply[off++] = 1;
    reply[off++] = 32;
    reply[off++] = static_cast<uint8_t>(num_depths);

    /* Depth 32 (root visual) */
    reply[off++] = 32; reply[off++] = 0;
    *reinterpret_cast<uint16_t*>(&reply[off]) = 1; off += 2;
    off += 4;

    *reinterpret_cast<uint32_t*>(&reply[off]) = visual_id; off += 4;
    reply[off++] = 4; reply[off++] = 8;
    *reinterpret_cast<uint16_t*>(&reply[off]) = 256; off += 2;
    *reinterpret_cast<uint32_t*>(&reply[off]) = 0x00FF0000; off += 4;
    *reinterpret_cast<uint32_t*>(&reply[off]) = 0x0000FF00; off += 4;
    *reinterpret_cast<uint32_t*>(&reply[off]) = 0x000000FF; off += 4;
    off += 4;

    /* Depth 24 */
    if (num_depths > 1) {
        reply[off++] = 24; reply[off++] = 0;
        *reinterpret_cast<uint16_t*>(&reply[off]) = 1; off += 2;
        off += 4;

        *reinterpret_cast<uint32_t*>(&reply[off]) = visual_id_24; off += 4;
        reply[off++] = 4; reply[off++] = 8;
        *reinterpret_cast<uint16_t*>(&reply[off]) = 256; off += 2;
        *reinterpret_cast<uint32_t*>(&reply[off]) = 0x00FF0000; off += 4;
        *reinterpret_cast<uint32_t*>(&reply[off]) = 0x0000FF00; off += 4;
        *reinterpret_cast<uint32_t*>(&reply[off]) = 0x000000FF; off += 4;
        off += 4;
    }

    int actual_additional = off - 8;
    *reinterpret_cast<uint16_t*>(&reply[6]) = static_cast<uint16_t>(actual_additional / 4);
    fprintf(stderr, "[X11Server] Setup reply: off=%d bytes (additional=%d words)\n",
            off, actual_additional / 4);
    send_to_client(server, client_idx, reply.data(), off);

    client->authenticated = 1;
    fprintf(stderr, "[X11Server] Client authenticated (fd=%d), buf_len=%d\n",
            client->fd, client->buf_len);

    fprintf(stderr, "[X11Server] on_client_connect callback=%p\n",
            reinterpret_cast<void*>(server->on_client_connect));
    if (server->on_client_connect) {
        fprintf(stderr, "[X11Server] Calling on_client_connect for fd=%d...\n", client->fd);
        server->on_client_connect(client->fd, server->on_client_connect_userdata);
        fprintf(stderr, "[X11Server] on_client_connect returned for fd=%d\n", client->fd);
    }

    if (server->epoll_fd >= 0) {
        struct epoll_event ev = {};
        ev.events = EPOLLIN;
        ev.data.fd = client->fd;
        if (epoll_ctl(server->epoll_fd, EPOLL_CTL_ADD, client->fd, &ev) == 0) {
            fprintf(stderr, "[X11Server] Added client fd=%d to epoll\n", client->fd);
        } else {
            fprintf(stderr, "[X11Server] Failed to add fd=%d to epoll: %s\n",
                    client->fd, strerror(errno));
        }
    }

    if (client->buf_len > 0) {
        handle_client_data(server, client_idx);
    }
}

/* ========================================================================== */
/* Request processing                                                          */
/* ========================================================================== */

static void handle_client_data(X11Server* server, int client_idx) {
    X11Client* client = &server->clients[client_idx];

    if (!client->authenticated) {
        handle_connection_setup(server, client_idx);
        return;
    }

    while (client->buf_len >= 4) {
        uint8_t opcode = client->buf[0];
        uint16_t length16 = *reinterpret_cast<uint16_t*>(client->buf + 2);
        int byte_length;

        if (length16 == 0) {
            if (client->buf_len < 8) break;
            uint32_t length32 = *reinterpret_cast<uint32_t*>(client->buf + 4);
            byte_length = static_cast<int>(length32 * 4);
            if (byte_length < 8) byte_length = 8;
        } else {
            byte_length = length16 * 4;
            if (byte_length < 4) byte_length = 4;
        }

        if (client->buf_len < byte_length) {
            if (byte_length > CLIENT_BUF_SIZE) {
                /* Request too large for buffer — skip it entirely.
                   This handles e.g. _NET_WM_ICON ChangeProperty (~4MB).
                   Drain remaining bytes from socket then discard. */
                int remaining = byte_length - client->buf_len;
                fprintf(stderr, "[X11Server] fd=%d SKIP oversized request: need %d bytes, opcode=%d — draining %d bytes\n",
                        client->fd, byte_length, opcode, remaining);
                client->buf_len = 0;
                while (remaining > 0) {
                    uint8_t drain[65536];
                    int chunk = remaining > (int)sizeof(drain) ? (int)sizeof(drain) : remaining;
                    ssize_t nr = recv(client->fd, drain, static_cast<size_t>(chunk), MSG_WAITALL);
                    if (nr <= 0) break;
                    remaining -= static_cast<int>(nr);
                }
                client->sequence++;
                continue;
            }
            break;
        }

        client->sequence++;

        handle_request(server, client_idx, opcode,
                       client->buf, byte_length);

        std::memmove(client->buf, client->buf + byte_length,
                static_cast<size_t>(client->buf_len - byte_length));
        client->buf_len -= byte_length;
    }
}

/* ========================================================================== */
/* Main request handler — core opcodes + extension dispatch                    */
/* ========================================================================== */

static void handle_request(X11Server* server, int client_idx,
                           uint8_t opcode, const uint8_t* data, int len) {
    X11Client* client = &server->clients[client_idx];
    uint16_t seq = client->sequence;

    if (opcode != X11_NO_OPERATION && opcode != X11_CHANGE_PROPERTY &&
        opcode != X11_CREATE_GC && opcode != X11_FREE_GC &&
        opcode != X11_CREATE_PIXMAP && opcode != X11_FREE_PIXMAP &&
        opcode != X11_INTERN_ATOM) {
        fprintf(stderr, "[X11Server] fd=%d req seq=%d opcode=%d len=%d\n", client->fd, seq, opcode, len);
    }

    switch (opcode) {
    case X11_QUERY_EXTENSION: {
        uint16_t name_len = *reinterpret_cast<const uint16_t*>(data + 4);
        char name[64] = {};
        if (name_len > 63) name_len = 63;
        std::memcpy(name, data + 8, name_len);

        uint8_t reply[32] = {};
        reply[0] = 1;
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        reply[8] = 0;

        for (auto& ext : server->extensions) {
            if (std::strcmp(name, ext.name) == 0) {
                reply[8] = 1;
                reply[9] = ext.major_opcode;
                reply[10] = ext.first_event;
                reply[11] = ext.first_error;
                break;
            }
        }

        fprintf(stderr, "[X11Server] QueryExtension '%s' -> %s\n",
                name, reply[8] ? "present" : "NOT FOUND");
        send_to_client(server, client_idx, reply, 32);
        break;
    }

    case X11_INTERN_ATOM: {
        int only_if_exists = data[1];
        uint16_t name_len = *reinterpret_cast<const uint16_t*>(data + 4);
        char name[128] = {};
        if (name_len > 127) name_len = 127;
        std::memcpy(name, data + 8, name_len);

        uint32_t atom_id = intern_atom(server, name, only_if_exists);

        uint8_t reply[32] = {};
        reply[0] = 1;
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 8) = atom_id;
        send_to_client(server, client_idx, reply, 32);
        break;
    }

    case X11_GET_ATOM_NAME: {
        uint32_t atom_id = *reinterpret_cast<const uint32_t*>(data + 4);
        const char* name = "";
        for (auto& a : server->atoms) {
            if (a.id == atom_id) {
                name = a.name.c_str();
                break;
            }
        }
        int name_len = static_cast<int>(strlen(name));
        int pad = (4 - (name_len & 3)) & 3;
        int reply_len = 32 + name_len + pad;
        std::vector<uint8_t> reply(static_cast<size_t>(reply_len), 0);
        reply[0] = 1;
        *reinterpret_cast<uint16_t*>(&reply[2]) = seq;
        *reinterpret_cast<uint32_t*>(&reply[4]) = static_cast<uint32_t>((name_len + pad) / 4);
        *reinterpret_cast<uint16_t*>(&reply[8]) = static_cast<uint16_t>(name_len);
        std::memcpy(&reply[32], name, static_cast<size_t>(name_len));
        send_to_client(server, client_idx, reply.data(), reply_len);
        break;
    }

    case X11_CREATE_WINDOW: {
        uint32_t wid = *reinterpret_cast<const uint32_t*>(data + 4);
        uint32_t parent = *reinterpret_cast<const uint32_t*>(data + 8);
        int16_t x = *reinterpret_cast<const int16_t*>(data + 12);
        int16_t y = *reinterpret_cast<const int16_t*>(data + 14);
        uint16_t w = *reinterpret_cast<const uint16_t*>(data + 16);
        uint16_t h = *reinterpret_cast<const uint16_t*>(data + 18);
        uint16_t border_width = *reinterpret_cast<const uint16_t*>(data + 20);
        uint32_t visual = *reinterpret_cast<const uint32_t*>(data + 24);
        uint32_t value_mask = *reinterpret_cast<const uint32_t*>(data + 28);

        X11Window win;
        win.id = wid;
        win.parent_id = parent;
        win.x = x; win.y = y;
        win.width = w; win.height = h;
        win.border_width = border_width;
        win.owner_client = static_cast<uint32_t>(client_idx);

        int voff = 32;
        for (int bit = 0; bit < 15 && voff + 4 <= len; bit++) {
            if (!(value_mask & (1u << bit))) continue;
            uint32_t val = *reinterpret_cast<const uint32_t*>(data + voff);
            voff += 4;
            switch (bit) {
            case 9: win.override_redirect = val ? 1 : 0; break;
            case 11: win.event_mask = val; break;
            default: break;
            }
        }

        fprintf(stderr, "[X11Server] CreateWindow: id=0x%x parent=0x%x %dx%d+%d+%d "
                "visual=0x%x mask=0x%x override=%d event_mask=0x%x\n",
                wid, parent, w, h, x, y, visual, value_mask,
                win.override_redirect, win.event_mask);

        server->windows.push_back(std::move(win));
        break;
    }

    case X11_MAP_WINDOW: {
        uint32_t wid = *reinterpret_cast<const uint32_t*>(data + 4);
        X11Window* win = find_window(server, wid);
        if (win) {
            int was_mapped = win->mapped;
            win->mapped = 1;
            int is_toplevel = (win->parent_id == server->root_window_id);
            int is_override = win->override_redirect;
            fprintf(stderr, "[X11Server] MapWindow: id=0x%x parent=0x%x toplevel=%d override=%d %dx%d was_mapped=%d\n",
                    wid, win->parent_id, is_toplevel, is_override, win->width, win->height, was_mapped);
            /* X11 spec: mapping an already-mapped window is a no-op */
            if (was_mapped) break;

            if (is_toplevel && !is_override &&
                win->width > 1 && win->height > 1) {
                if (server->config.on_window_mapped) {
                    fprintf(stderr, "[X11Server] Calling on_window_mapped for 0x%x %dx%d...\n",
                            wid, win->width, win->height);
                    server->config.on_window_mapped(
                        server->config.userdata, wid,
                        win->x, win->y, win->width, win->height);
                    fprintf(stderr, "[X11Server] on_window_mapped returned\n");
                }
                x11_server_set_focus(server, wid);

                /* WM_STATE = NormalState */
                uint32_t wm_state_atom = intern_atom(server, "WM_STATE", 0);
                {
                    auto& wsp = set_property(win, wm_state_atom);
                    wsp.type = wm_state_atom;
                    wsp.format = 32;
                    wsp.length = 2;
                    uint32_t ws_data[2] = { 1, 0 };
                    wsp.data.assign(reinterpret_cast<uint8_t*>(ws_data),
                                    reinterpret_cast<uint8_t*>(ws_data) + 8);
                }
                /* _NET_WM_STATE with _FOCUSED */
                uint32_t net_wm_state = intern_atom(server, "_NET_WM_STATE", 0);
                uint32_t net_focused = intern_atom(server, "_NET_WM_STATE_FOCUSED", 0);
                {
                    auto& nsp = set_property(win, net_wm_state);
                    nsp.type = 4;
                    nsp.format = 32;
                    nsp.length = 1;
                    nsp.data.assign(reinterpret_cast<uint8_t*>(&net_focused),
                                    reinterpret_cast<uint8_t*>(&net_focused) + 4);
                }
                /* _NET_ACTIVE_WINDOW on root */
                uint32_t net_active = intern_atom(server, "_NET_ACTIVE_WINDOW", 0);
                X11Window* root = find_window(server, server->root_window_id);
                if (root) {
                    auto& ap = set_property(root, net_active);
                    ap.type = 33;
                    ap.format = 32;
                    ap.length = 1;
                    ap.data.assign(reinterpret_cast<uint8_t*>(&wid),
                                   reinterpret_cast<uint8_t*>(&wid) + 4);
                }
            } else if (is_toplevel && is_override &&
                       win->width > 1 && win->height > 1) {
                /* A menu, dropdown or tooltip. It bypasses the WM, so we place
                 * it exactly where the client asked and give it no decoration —
                 * but it still has to be composited, or every menu in every X11
                 * app is invisible while sitting perfectly alive in the window
                 * tree. Deliberately no set_focus(): a menu must not steal the
                 * keyboard from the toplevel it belongs to. */
                if (server->config.on_popup_mapped) {
                    uint32_t parent = popup_parent_for(server, win);
                    /* Hand the shell a PARENT-RELATIVE offset, not the root
                     * coordinate. The client positioned this menu in root space
                     * using where *it* believes its toplevel sits (win->x/y as
                     * this server reported them), which is not where the shell
                     * actually composites that window. Differencing the two here
                     * makes the anchor correct no matter how the shell places
                     * or scales the parent. */
                    X11Window* pw = find_window(server, parent);
                    int rel_x = win->x - (pw ? pw->x : 0);
                    int rel_y = win->y - (pw ? pw->y : 0);
                    fprintf(stderr, "[X11Server] popup mapped 0x%x parent=0x%x %dx%d rel=%+d%+d\n",
                            wid, parent, win->width, win->height, rel_x, rel_y);
                    server->config.on_popup_mapped(
                        server->config.userdata, wid, parent,
                        rel_x, rel_y, win->width, win->height);
                }
            }

            /* MapNotify */
            {
                int is_override = win->override_redirect;
                uint8_t event[32] = {};
                event[0] = X11_MAP_NOTIFY_EVENT;
                *reinterpret_cast<uint16_t*>(event + 2) = seq;
                *reinterpret_cast<uint32_t*>(event + 4) = wid;
                *reinterpret_cast<uint32_t*>(event + 8) = wid;
                event[12] = static_cast<uint8_t>(is_override);
                send_to_client(server, client_idx, event, 32);
            }

            /* VisibilityNotify */
            {
                uint8_t vis[32] = {};
                vis[0] = 15;
                *reinterpret_cast<uint16_t*>(vis + 2) = seq;
                *reinterpret_cast<uint32_t*>(vis + 4) = wid;
                vis[8] = 0;
                send_to_client(server, client_idx, vis, 32);
            }

            /* Expose */
            {
                uint8_t expose[32] = {};
                expose[0] = X11_EXPOSE_EVENT;
                *reinterpret_cast<uint16_t*>(expose + 2) = seq;
                *reinterpret_cast<uint32_t*>(expose + 4) = wid;
                *reinterpret_cast<uint16_t*>(expose + 8) = 0;
                *reinterpret_cast<uint16_t*>(expose + 10) = 0;
                *reinterpret_cast<uint16_t*>(expose + 12) = win->width;
                *reinterpret_cast<uint16_t*>(expose + 14) = win->height;
                *reinterpret_cast<uint16_t*>(expose + 16) = 0;
                send_to_client(server, client_idx, expose, 32);
            }
        }
        break;
    }

    case X11_UNMAP_WINDOW: {
        uint32_t wid = *reinterpret_cast<const uint32_t*>(data + 4);
        X11Window* win = find_window(server, wid);
        if (win) {
            int was_mapped = win->mapped;
            int is_toplevel = (win->parent_id == server->root_window_id);
            int is_override = win->override_redirect;
            win->mapped = 0;
            if (was_mapped && is_toplevel && !is_override &&
                server->config.on_window_unmapped) {
                server->config.on_window_unmapped(server->config.userdata, wid);
            }
            if (was_mapped && is_toplevel && is_override &&
                server->config.on_popup_unmapped) {
                server->config.on_popup_unmapped(server->config.userdata, wid);
            }
            if (server->focus_window_id == wid) {
                server->focus_window_id = 0;
                server->focus_client_idx = -1;
            }
        }
        break;
    }

    case X11_DESTROY_WINDOW: {
        uint32_t wid = *reinterpret_cast<const uint32_t*>(data + 4);
        for (auto it = server->windows.begin(); it != server->windows.end(); ++it) {
            if (it->id == wid) {
                int is_toplevel = (it->parent_id == server->root_window_id);
                int is_override = it->override_redirect;
                if (is_toplevel && !is_override && server->config.on_window_destroyed) {
                    server->config.on_window_destroyed(server->config.userdata, wid);
                }
                if (is_toplevel && is_override && server->config.on_popup_unmapped) {
                    server->config.on_popup_unmapped(server->config.userdata, wid);
                }
                if (server->focus_window_id == wid) {
                    server->focus_window_id = 0;
                    server->focus_client_idx = -1;
                }
                server->windows.erase(it);
                break;
            }
        }
        break;
    }

    case X11_CONFIGURE_WINDOW: {
        uint32_t wid = *reinterpret_cast<const uint32_t*>(data + 4);
        uint16_t mask = *reinterpret_cast<const uint16_t*>(data + 8);
        int off = 12;

        X11Window* win = find_window(server, wid);
        if (win) {
            if (mask & 0x01) { win->x = *reinterpret_cast<const int16_t*>(data + off); off += 4; }
            if (mask & 0x02) { win->y = *reinterpret_cast<const int16_t*>(data + off); off += 4; }
            if (mask & 0x04) { win->width = *reinterpret_cast<const uint16_t*>(data + off); off += 4; }
            if (mask & 0x08) { win->height = *reinterpret_cast<const uint16_t*>(data + off); off += 4; }

            if (server->config.on_window_configured) {
                server->config.on_window_configured(
                    server->config.userdata, wid,
                    win->x, win->y, win->width, win->height);
            }

            if (mask & 0x0C) {  /* width or height changed — full resize flow */
                fprintf(stderr, "[X11Server] ConfigureWindow: 0x%x -> %dx%d\n",
                        wid, win->width, win->height);
                send_resize_events(server, win, win->width, win->height);
            } else if (win->event_mask & 0x20000) {
                /* Position-only change — just send ConfigureNotify */
                uint8_t ev[32] = {};
                ev[0] = 22;
                *reinterpret_cast<uint16_t*>(ev + 2) = seq;
                *reinterpret_cast<uint32_t*>(ev + 4) = wid;
                *reinterpret_cast<uint32_t*>(ev + 8) = wid;
                *reinterpret_cast<int16_t*>(ev + 16) = win->x;
                *reinterpret_cast<int16_t*>(ev + 18) = win->y;
                *reinterpret_cast<uint16_t*>(ev + 20) = win->width;
                *reinterpret_cast<uint16_t*>(ev + 22) = win->height;
                *reinterpret_cast<uint16_t*>(ev + 24) = win->border_width;
                ev[26] = static_cast<uint8_t>(win->override_redirect);
                send_to_client(server, client_idx, ev, 32);
            }
        }
        break;
    }

    case X11_GET_WINDOW_ATTRS: {
        uint32_t wid = *reinterpret_cast<const uint32_t*>(data + 4);
        X11Window* win = find_window(server, wid);
        uint8_t reply[44] = {};
        reply[0] = 1; reply[1] = 0;
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 4) = 3;
        *reinterpret_cast<uint32_t*>(reply + 8) = 0x22;
        *reinterpret_cast<uint16_t*>(reply + 12) = 1;
        reply[24] = 0; reply[25] = 1;
        reply[26] = (win && win->mapped) ? 2 : 0;
        reply[27] = win ? static_cast<uint8_t>(win->override_redirect) : 0;
        *reinterpret_cast<uint32_t*>(reply + 28) = 0x20;
        *reinterpret_cast<uint32_t*>(reply + 32) = win ? win->event_mask : 0;
        *reinterpret_cast<uint32_t*>(reply + 36) = win ? win->event_mask : 0;
        *reinterpret_cast<uint16_t*>(reply + 40) = 0;
        send_to_client(server, client_idx, reply, 44);
        break;
    }

    case X11_GET_GEOMETRY: {
        uint32_t drawable = *reinterpret_cast<const uint32_t*>(data + 4);
        uint8_t reply[32] = {};
        reply[0] = 1; reply[1] = 24;
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 8) = server->root_window_id;

        X11Window* win = find_window(server, drawable);
        if (win) {
            *reinterpret_cast<int16_t*>(reply + 12) = win->x;
            *reinterpret_cast<int16_t*>(reply + 14) = win->y;
            *reinterpret_cast<uint16_t*>(reply + 16) = win->width;
            *reinterpret_cast<uint16_t*>(reply + 18) = win->height;
        }
        if (drawable == server->root_window_id) {
            *reinterpret_cast<uint16_t*>(reply + 16) = static_cast<uint16_t>(server->config.display_width);
            *reinterpret_cast<uint16_t*>(reply + 18) = static_cast<uint16_t>(server->config.display_height);
        }
        if (*reinterpret_cast<uint16_t*>(reply + 16) == 0 && *reinterpret_cast<uint16_t*>(reply + 18) == 0) {
            *reinterpret_cast<uint16_t*>(reply + 16) = 1;
            *reinterpret_cast<uint16_t*>(reply + 18) = 1;
        }
        send_to_client(server, client_idx, reply, 32);
        break;
    }

    case X11_QUERY_TREE: {
        uint32_t wid = *reinterpret_cast<const uint32_t*>(data + 4);
        int child_count = 0;
        for (auto& w : server->windows) {
            if (w.parent_id == wid) child_count++;
        }
        int reply_len = 32 + child_count * 4;
        std::vector<uint8_t> reply(static_cast<size_t>(reply_len), 0);
        reply[0] = 1;
        *reinterpret_cast<uint16_t*>(&reply[2]) = seq;
        *reinterpret_cast<uint32_t*>(&reply[4]) = static_cast<uint32_t>(child_count);
        *reinterpret_cast<uint32_t*>(&reply[8]) = server->root_window_id;
        *reinterpret_cast<uint32_t*>(&reply[12]) = 0;
        *reinterpret_cast<uint16_t*>(&reply[16]) = static_cast<uint16_t>(child_count);

        int off2 = 32;
        for (auto& w : server->windows) {
            if (w.parent_id == wid) {
                *reinterpret_cast<uint32_t*>(&reply[off2]) = w.id;
                off2 += 4;
            }
        }
        send_to_client(server, client_idx, reply.data(), reply_len);
        break;
    }

    case X11_CHANGE_PROPERTY: {
        uint8_t mode = data[1];
        uint32_t wid = *reinterpret_cast<const uint32_t*>(data + 4);
        uint32_t property = *reinterpret_cast<const uint32_t*>(data + 8);
        uint32_t type = *reinterpret_cast<const uint32_t*>(data + 12);
        uint8_t format = data[16];
        uint32_t data_len = *reinterpret_cast<const uint32_t*>(data + 20);
        const uint8_t* prop_data = data + 24;
        int byte_len = static_cast<int>(data_len * (format / 8));
        if (byte_len < 0 || byte_len > len - 24) {
            byte_len = (len > 24) ? len - 24 : 0;
        }

        X11Window* win = find_window(server, wid);
        if (win) {
            auto& prop = set_property(win, property);
            prop.type = type;
            prop.format = format;
            prop.length = data_len;
            prop.data.assign(prop_data, prop_data + byte_len);

            /* Check for title changes */
            for (auto& a : server->atoms) {
                if (a.id == property &&
                    (a.name == "WM_NAME" || a.name == "_NET_WM_NAME")) {
                    char title[256] = {};
                    int tlen = byte_len < 255 ? byte_len : 255;
                    std::memcpy(title, prop_data, static_cast<size_t>(tlen));
                    if (server->config.on_title_changed) {
                        server->config.on_title_changed(server->config.userdata, wid, title);
                    }
                }
            }

            /* PropertyNotify to the window's selecting client. Chromium's
             * UI thread learns the X server timestamp by writing a dummy
             * property and BLOCKING on the PropertyNotify echo — without
             * this event it never proceeds to bring up renderers (WeChat
             * login stalled at the spinner on exactly that wait). */
            int oc = static_cast<int>(win->owner_client);
            if ((win->event_mask & 0x400000) &&
                oc >= 0 && oc < server->client_count &&
                server->clients[oc].fd >= 0) {
                uint8_t ev[32] = {};
                ev[0] = 28; /* PropertyNotify */
                *reinterpret_cast<uint16_t*>(ev + 2) = server->clients[oc].sequence;
                *reinterpret_cast<uint32_t*>(ev + 4) = wid;
                *reinterpret_cast<uint32_t*>(ev + 8) = property;
                *reinterpret_cast<uint32_t*>(ev + 12) = x11_timestamp();
                ev[16] = 0; /* NewValue */
                send_to_client(server, oc, ev, 32);
            }
        }
        (void)mode;
        break;
    }

    case X11_GET_PROPERTY: {
        uint32_t wid = *reinterpret_cast<const uint32_t*>(data + 4);
        uint32_t property = *reinterpret_cast<const uint32_t*>(data + 8);

        const char* prop_name = "?";
        for (auto& a : server->atoms) {
            if (a.id == property) { prop_name = a.name.c_str(); break; }
        }
        fprintf(stderr, "[X11Server] GetProperty: wid=0x%x prop=%u (%s)\n", wid, property, prop_name);

        X11Property* prop = nullptr;
        X11Window* win = find_window(server, wid);
        if (win) {
            for (auto& p : win->properties) {
                if (p.atom == property) { prop = &p; break; }
            }
        }

        if (prop && !prop->data.empty()) {
            int byte_len = static_cast<int>(prop->length * (prop->format / 8));
            int pad = (4 - (byte_len & 3)) & 3;
            int reply_len = 32 + byte_len + pad;
            std::vector<uint8_t> reply(static_cast<size_t>(reply_len), 0);
            reply[0] = 1;
            reply[1] = prop->format;
            *reinterpret_cast<uint16_t*>(&reply[2]) = seq;
            *reinterpret_cast<uint32_t*>(&reply[4]) = static_cast<uint32_t>((byte_len + pad) / 4);
            *reinterpret_cast<uint32_t*>(&reply[8]) = prop->type;
            *reinterpret_cast<uint32_t*>(&reply[16]) = prop->length;
            std::memcpy(&reply[32], prop->data.data(), static_cast<size_t>(byte_len));
            send_to_client(server, client_idx, reply.data(), reply_len);
        } else {
            uint8_t reply[32] = {};
            reply[0] = 1;
            *reinterpret_cast<uint16_t*>(reply + 2) = seq;
            send_to_client(server, client_idx, reply, 32);
        }
        break;
    }

    case X11_GRAB_POINTER: {
        /* owner-events(1)@1 grab-window(4)@4 event-mask(2)@8 */
        server->grab_owner_events = data[1] ? 1 : 0;
        server->grab_window = *reinterpret_cast<const uint32_t*>(data + 4);
        server->grab_client = client_idx;
        fprintf(stderr, "[X11Server] GrabPointer win=0x%x owner_events=%d client=%d\n",
                server->grab_window, server->grab_owner_events, client_idx);
        uint8_t reply[32] = {};
        reply[0] = 1; reply[1] = 0;  /* status = GrabSuccess */
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        send_to_client(server, client_idx, reply, 32);
        break;
    }

    case X11_UNGRAB_POINTER:
        if (server->grab_window) {
            fprintf(stderr, "[X11Server] UngrabPointer (was 0x%x)\n", server->grab_window);
            server->grab_window = 0;
            server->grab_client = -1;
        }
        break;

    case X11_CHANGE_WINDOW_ATTRS: {
        uint32_t wid = *reinterpret_cast<const uint32_t*>(data + 4);
        uint32_t value_mask = *reinterpret_cast<const uint32_t*>(data + 8);
        X11Window* win = find_window(server, wid);
        if (win) {
            int voff = 12;
            for (int bit = 0; bit < 15 && voff + 4 <= len; bit++) {
                if (!(value_mask & (1u << bit))) continue;
                uint32_t val = *reinterpret_cast<const uint32_t*>(data + voff);
                voff += 4;
                switch (bit) {
                case 9: win->override_redirect = val ? 1 : 0; break;
                case 11: win->event_mask = val; break;
                default: break;
                }
            }
        }
        break;
    }

    case X11_WARP_POINTER:
    case X11_DELETE_PROPERTY:
    case X11_CREATE_GC:
    case X11_CHANGE_GC:
    case X11_FREE_GC:
    case X11_CREATE_COLORMAP:
    case X11_FREE_COLORMAP:
    case X11_SET_SELECTION_OWNER:
    case X11_GRAB_BUTTON:
    case X11_UNGRAB_BUTTON:
    case X11_GRAB_KEY:
    case X11_UNGRAB_KEY:
    case X11_GRAB_SERVER:
    case X11_UNGRAB_SERVER:
    case X11_SEND_EVENT:
    case X11_CONVERT_SELECTION:
    case X11_KILL_CLIENT:
    case X11_NO_OPERATION:
    case X11_BELL:
    case X11_SET_CLIP_RECTANGLES:
    /* Measured against Zoom and Qt menus: these are never sent — the toolkits
     * we care about paint through PutImage/CopyArea or DRI3, so leaving them
     * unimplemented costs nothing. Do not assume a blank window means these
     * are the gap; check the log before implementing them. */
    case X11_CLEAR_AREA:
    case X11_POLY_FILL_RECT:
    case X11_IMAGE_TEXT8:
    case X11_OPEN_FONT:
    case X11_CLOSE_FONT:
    case X11_CHANGE_KEYBOARD_CTRL:
    case X11_CHANGE_HOSTS:
    case X11_SET_ACCESS_CONTROL:
    case X11_SET_MODIFIER_MAPPING:
        break;

    case X11_GET_KEYBOARD_CTRL: {
        uint8_t reply[52] = {};
        reply[0] = 1; reply[1] = 0;
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 4) = 5;
        reply[12] = 50; reply[13] = 50;
        *reinterpret_cast<uint16_t*>(reply + 14) = 400;
        *reinterpret_cast<uint16_t*>(reply + 16) = 100;
        send_to_client(server, client_idx, reply, 52);
        break;
    }

    case X11_LOOKUP_COLOR: {
        uint8_t reply[32] = {};
        reply[0] = 1;
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        send_to_client(server, client_idx, reply, 32);
        break;
    }

    case 116: { /* SetPointerMapping */
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        send_to_client(server, client_idx, reply, 32);
        break;
    }
    case 117: { /* GetPointerMapping */
        int nm = 5, pd = 3;
        std::vector<uint8_t> reply(static_cast<size_t>(32 + nm + pd), 0);
        reply[0] = 1; reply[1] = static_cast<uint8_t>(nm);
        *reinterpret_cast<uint16_t*>(&reply[2]) = seq;
        *reinterpret_cast<uint32_t*>(&reply[4]) = static_cast<uint32_t>((nm + pd) / 4);
        for (int b = 0; b < nm; b++) reply[static_cast<size_t>(32 + b)] = static_cast<uint8_t>(b + 1);
        send_to_client(server, client_idx, reply.data(), 32 + nm + pd);
        break;
    }
    case X11_LIST_HOSTS: {
        uint8_t reply[32] = {};
        reply[0] = 1; reply[1] = 0;
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint16_t*>(reply + 8) = 0;
        send_to_client(server, client_idx, reply, 32);
        break;
    }

    case X11_CREATE_PIXMAP: {
        uint32_t pid = *reinterpret_cast<const uint32_t*>(data + 4);
        uint32_t drawable = *reinterpret_cast<const uint32_t*>(data + 8);
        uint16_t w = *reinterpret_cast<const uint16_t*>(data + 12);
        uint16_t h = *reinterpret_cast<const uint16_t*>(data + 14);
        X11Pixmap px;
        px.id = pid; px.width = w; px.height = h;
        px.dma_fd = -1; px.fence_fd = -1;
        px.window_id = drawable;
        server->pixmaps.push_back(std::move(px));
        break;
    }

    case X11_FREE_PIXMAP: {
        uint32_t pid = *reinterpret_cast<const uint32_t*>(data + 4);
        fprintf(stderr, "[X11Server] FreePixmap: 0x%x (total=%d)\n", pid, static_cast<int>(server->pixmaps.size()));
        for (auto it = server->pixmaps.begin(); it != server->pixmaps.end(); ++it) {
            if (it->id == pid) {
                fprintf(stderr, "[X11Server]   freed dma_fd=%d fence_fd=%d\n", it->dma_fd, it->fence_fd);
                server->pixmaps.erase(it); /* destructor closes fds */
                break;
            }
        }
        break;
    }

    case X11_GET_INPUT_FOCUS: {
        uint8_t reply[32] = {};
        reply[0] = 1; reply[1] = 1;
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 8) = server->focus_window_id ? server->focus_window_id
                                                                           : server->root_window_id;
        send_to_client(server, client_idx, reply, 32);
        break;
    }

    case X11_SET_INPUT_FOCUS: {
        uint32_t focus = *reinterpret_cast<const uint32_t*>(data + 4);
        x11_server_set_focus(server, focus);
        break;
    }

    case X11_ALLOC_COLOR: {
        uint32_t cmap = *reinterpret_cast<const uint32_t*>(data + 4);
        uint16_t red = *reinterpret_cast<const uint16_t*>(data + 8);
        uint16_t green = *reinterpret_cast<const uint16_t*>(data + 10);
        uint16_t blue = *reinterpret_cast<const uint16_t*>(data + 12);
        uint8_t reply[32] = {};
        reply[0] = 1;
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint16_t*>(reply + 8) = red;
        *reinterpret_cast<uint16_t*>(reply + 10) = green;
        *reinterpret_cast<uint16_t*>(reply + 12) = blue;
        *reinterpret_cast<uint32_t*>(reply + 16) = (static_cast<uint32_t>(red >> 8) << 16) |
                                                    (static_cast<uint32_t>(green >> 8) << 8) |
                                                    static_cast<uint32_t>(blue >> 8);
        send_to_client(server, client_idx, reply, 32);
        (void)cmap;
        break;
    }

    case X11_QUERY_COLORS: {
        uint8_t reply[32] = {};
        reply[0] = 1;
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        send_to_client(server, client_idx, reply, 32);
        break;
    }

    case X11_QUERY_FONT: {
        uint8_t reply[60] = {};
        reply[0] = 1;
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 4) = 7;
        *reinterpret_cast<uint16_t*>(reply + 40) = 8;
        *reinterpret_cast<uint16_t*>(reply + 46) = 255;
        *reinterpret_cast<uint16_t*>(reply + 50) = 12;
        *reinterpret_cast<uint16_t*>(reply + 52) = 4;
        send_to_client(server, client_idx, reply, 60);
        break;
    }

    case X11_LIST_FONTS: {
        uint8_t reply[32] = {};
        reply[0] = 1;
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        send_to_client(server, client_idx, reply, 32);
        break;
    }

    case X11_QUERY_POINTER: {
        uint32_t qp_win = *reinterpret_cast<const uint32_t*>(data + 4);
        uint8_t reply[32] = {};
        reply[0] = 1; reply[1] = 1; /* same_screen = 1 */
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 8) = server->root_window_id;
        /* bytes 12-15: child = focus window (or 0) */
        *reinterpret_cast<uint32_t*>(reply + 12) = server->focus_window_id;
        /* root_x, root_y */
        *reinterpret_cast<int16_t*>(reply + 16) = server->pointer_x;
        *reinterpret_cast<int16_t*>(reply + 18) = server->pointer_y;
        /* win_x, win_y — relative to queried window */
        X11Window* qpw = find_window(server, qp_win);
        *reinterpret_cast<int16_t*>(reply + 20) = static_cast<int16_t>(
            server->pointer_x - (qpw ? qpw->x : 0));
        *reinterpret_cast<int16_t*>(reply + 22) = static_cast<int16_t>(
            server->pointer_y - (qpw ? qpw->y : 0));
        /* bytes 24-25: mask (button/modifier state) */
        *reinterpret_cast<uint16_t*>(reply + 24) = server->button_state;
        send_to_client(server, client_idx, reply, 32);
        break;
    }

    case X11_TRANSLATE_COORDS: {
        uint32_t src_win = *reinterpret_cast<const uint32_t*>(data + 4);
        uint32_t dst_win = *reinterpret_cast<const uint32_t*>(data + 8);
        int16_t src_x = *reinterpret_cast<const int16_t*>(data + 12);
        int16_t src_y = *reinterpret_cast<const int16_t*>(data + 14);
        X11Window* sw = find_window(server, src_win);
        X11Window* dw = find_window(server, dst_win);
        int16_t sx = sw ? sw->x : 0;
        int16_t sy = sw ? sw->y : 0;
        int16_t dx = dw ? dw->x : 0;
        int16_t dy = dw ? dw->y : 0;
        uint8_t reply[32] = {};
        reply[0] = 1; reply[1] = 1;
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 8) = 0;
        *reinterpret_cast<int16_t*>(reply + 12) = static_cast<int16_t>(src_x + sx - dx);
        *reinterpret_cast<int16_t*>(reply + 14) = static_cast<int16_t>(src_y + sy - dy);
        send_to_client(server, client_idx, reply, 32);
        break;
    }

    case X11_GET_KEYBOARD_MAPPING: {
        uint8_t first_keycode = data[4];
        uint8_t count = data[5];
        int keysyms_per_keycode = 4;
        int total_keysyms = count * keysyms_per_keycode;
        int reply_len = 32 + total_keysyms * 4;
        std::vector<uint8_t> reply(static_cast<size_t>(reply_len), 0);
        reply[0] = 1;
        reply[1] = static_cast<uint8_t>(keysyms_per_keycode);
        *reinterpret_cast<uint16_t*>(&reply[2]) = seq;
        *reinterpret_cast<uint32_t*>(&reply[4]) = static_cast<uint32_t>(total_keysyms);

        uint32_t* ks = reinterpret_cast<uint32_t*>(&reply[32]);
        for (int k = 0; k < count; k++) {
            int kc = first_keycode + k;
            int base = k * keysyms_per_keycode;
            switch (kc) {
            case 9:  ks[base] = 0xFF1B; break;
            case 24: ks[base] = 0x0071; ks[base+1] = 0x0051; break;
            case 25: ks[base] = 0x0077; ks[base+1] = 0x0057; break;
            case 26: ks[base] = 0x0065; ks[base+1] = 0x0045; break;
            case 27: ks[base] = 0x0072; ks[base+1] = 0x0052; break;
            case 28: ks[base] = 0x0074; ks[base+1] = 0x0054; break;
            case 29: ks[base] = 0x0079; ks[base+1] = 0x0059; break;
            case 30: ks[base] = 0x0075; ks[base+1] = 0x0055; break;
            case 31: ks[base] = 0x0069; ks[base+1] = 0x0049; break;
            case 32: ks[base] = 0x006f; ks[base+1] = 0x004f; break;
            case 33: ks[base] = 0x0070; ks[base+1] = 0x0050; break;
            case 38: ks[base] = 0x0061; ks[base+1] = 0x0041; break;
            case 39: ks[base] = 0x0073; ks[base+1] = 0x0053; break;
            case 40: ks[base] = 0x0064; ks[base+1] = 0x0044; break;
            case 41: ks[base] = 0x0066; ks[base+1] = 0x0046; break;
            case 42: ks[base] = 0x0067; ks[base+1] = 0x0047; break;
            case 43: ks[base] = 0x0068; ks[base+1] = 0x0048; break;
            case 44: ks[base] = 0x006a; ks[base+1] = 0x004a; break;
            case 45: ks[base] = 0x006b; ks[base+1] = 0x004b; break;
            case 46: ks[base] = 0x006c; ks[base+1] = 0x004c; break;
            case 52: ks[base] = 0x007a; ks[base+1] = 0x005a; break;
            case 53: ks[base] = 0x0078; ks[base+1] = 0x0058; break;
            case 54: ks[base] = 0x0063; ks[base+1] = 0x0043; break;
            case 55: ks[base] = 0x0076; ks[base+1] = 0x0056; break;
            case 56: ks[base] = 0x0062; ks[base+1] = 0x0042; break;
            case 57: ks[base] = 0x006e; ks[base+1] = 0x004e; break;
            case 58: ks[base] = 0x006d; ks[base+1] = 0x004d; break;
            case 10: ks[base] = 0x0031; ks[base+1] = 0x0021; break;
            case 11: ks[base] = 0x0032; ks[base+1] = 0x0040; break;
            case 12: ks[base] = 0x0033; ks[base+1] = 0x0023; break;
            case 13: ks[base] = 0x0034; ks[base+1] = 0x0024; break;
            case 14: ks[base] = 0x0035; ks[base+1] = 0x0025; break;
            case 15: ks[base] = 0x0036; ks[base+1] = 0x005e; break;
            case 16: ks[base] = 0x0037; ks[base+1] = 0x0026; break;
            case 17: ks[base] = 0x0038; ks[base+1] = 0x002a; break;
            case 18: ks[base] = 0x0039; ks[base+1] = 0x0028; break;
            case 19: ks[base] = 0x0030; ks[base+1] = 0x0029; break;
            case 36: ks[base] = 0xFF0D; break;
            case 65: ks[base] = 0x0020; break;
            case 22: ks[base] = 0xFF08; break;
            case 23: ks[base] = 0xFF09; break;
            case 50: ks[base] = 0xFFE1; break;
            case 62: ks[base] = 0xFFE2; break;
            case 37: ks[base] = 0xFFE3; break;
            case 105: ks[base] = 0xFFE4; break;
            case 64: ks[base] = 0xFFE9; break;
            case 108: ks[base] = 0xFFEA; break;
            case 133: ks[base] = 0xFFEB; break;
            case 66: ks[base] = 0xFFE5; break;
            case 111: ks[base] = 0xFF52; break;
            case 116: ks[base] = 0xFF54; break;
            case 113: ks[base] = 0xFF51; break;
            case 114: ks[base] = 0xFF53; break;
            case 110: ks[base] = 0xFF50; break;
            case 115: ks[base] = 0xFF57; break;
            case 117: ks[base] = 0xFF56; break;
            case 112: ks[base] = 0xFF55; break;
            case 119: ks[base] = 0xFFFF; break;
            case 118: ks[base] = 0xFF63; break;
            /* Punctuation (US layout): unshifted + shifted. These were all
             * missing, so every punctuation key produced keysym 0 and did
             * nothing in X11 clients — most visibly '.', which an email needs. */
            case 20: ks[base] = 0x002d; ks[base+1] = 0x005f; break;  /* -  _ */
            case 21: ks[base] = 0x003d; ks[base+1] = 0x002b; break;  /* =  + */
            case 34: ks[base] = 0x005b; ks[base+1] = 0x007b; break;  /* [  { */
            case 35: ks[base] = 0x005d; ks[base+1] = 0x007d; break;  /* ]  } */
            case 47: ks[base] = 0x003b; ks[base+1] = 0x003a; break;  /* ;  : */
            case 48: ks[base] = 0x0027; ks[base+1] = 0x0022; break;  /* '  " */
            case 49: ks[base] = 0x0060; ks[base+1] = 0x007e; break;  /* `  ~ */
            case 51: ks[base] = 0x005c; ks[base+1] = 0x007c; break;  /* \  | */
            case 59: ks[base] = 0x002c; ks[base+1] = 0x003c; break;  /* ,  < */
            case 60: ks[base] = 0x002e; ks[base+1] = 0x003e; break;  /* .  > */
            case 61: ks[base] = 0x002f; ks[base+1] = 0x003f; break;  /* /  ? */
            }
        }
        send_to_client(server, client_idx, reply.data(), reply_len);
        break;
    }

    case X11_LIST_EXTENSIONS: {
        int total_name_bytes = 0;
        for (auto& ext : server->extensions)
            total_name_bytes += 1 + static_cast<int>(strlen(ext.name));
        int pad = (4 - (total_name_bytes & 3)) & 3;
        int reply_len = 32 + total_name_bytes + pad;
        std::vector<uint8_t> reply(static_cast<size_t>(reply_len), 0);
        reply[0] = 1;
        reply[1] = static_cast<uint8_t>(server->extensions.size());
        *reinterpret_cast<uint16_t*>(&reply[2]) = seq;
        *reinterpret_cast<uint32_t*>(&reply[4]) = static_cast<uint32_t>((total_name_bytes + pad) / 4);
        int off2 = 32;
        for (auto& ext : server->extensions) {
            int nlen = static_cast<int>(strlen(ext.name));
            reply[static_cast<size_t>(off2++)] = static_cast<uint8_t>(nlen);
            std::memcpy(&reply[static_cast<size_t>(off2)], ext.name, static_cast<size_t>(nlen));
            off2 += nlen;
        }
        send_to_client(server, client_idx, reply.data(), reply_len);
        break;
    }

    case X11_QUERY_BEST_SIZE: {
        uint8_t reply[32] = {};
        reply[0] = 1;
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint16_t*>(reply + 8) = *reinterpret_cast<const uint16_t*>(data + 8);
        *reinterpret_cast<uint16_t*>(reply + 10) = *reinterpret_cast<const uint16_t*>(data + 10);
        send_to_client(server, client_idx, reply, 32);
        break;
    }

    case X11_LIST_INSTALLED_CMAPS: {
        uint8_t reply[36] = {};
        reply[0] = 1;
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 4) = 1;
        *reinterpret_cast<uint16_t*>(reply + 8) = 1;
        *reinterpret_cast<uint32_t*>(reply + 32) = 0x20;
        send_to_client(server, client_idx, reply, 36);
        break;
    }

    case X11_GET_MODIFIER_MAPPING: {
        uint8_t reply[32 + 16] = {};
        reply[0] = 1; reply[1] = 2;
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 4) = 4;
        send_to_client(server, client_idx, reply, 32 + 16);
        break;
    }

    case X11_GET_SELECTION_OWNER: {
        uint8_t reply[32] = {};
        reply[0] = 1;
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        send_to_client(server, client_idx, reply, 32);
        break;
    }

    case 21: { /* ListProperties */
        uint32_t wid = *reinterpret_cast<const uint32_t*>(data + 4);
        X11Window* win = find_window(server, wid);
        int n_props = win ? static_cast<int>(win->properties.size()) : 0;
        int reply_len = 32 + n_props * 4;
        std::vector<uint8_t> reply(static_cast<size_t>(reply_len), 0);
        reply[0] = 1;
        *reinterpret_cast<uint16_t*>(&reply[2]) = seq;
        *reinterpret_cast<uint32_t*>(&reply[4]) = static_cast<uint32_t>(n_props);
        *reinterpret_cast<uint16_t*>(&reply[8]) = static_cast<uint16_t>(n_props);
        for (int j = 0; j < n_props; j++) {
            *reinterpret_cast<uint32_t*>(&reply[32 + j * 4]) = win->properties[static_cast<size_t>(j)].atom;
        }
        send_to_client(server, client_idx, reply.data(), reply_len);
        break;
    }

    case 72: {
        /* PutImage — the core-X way a raster client paints. Qt's xcb backing
         * store falls back to this when MIT-SHM is unavailable; xclock and
         * friends use it always.
         *
         *   format(1) is data[1]; drawable(4)@4 gc(4)@8 width(2)@12
         *   height(2)@14 dst-x(2)@16 dst-y(2)@18 left-pad(1)@20 depth(1)@21
         *   pad(2)@22, image data from @24.
         *
         * Only ZPixmap (format 2) at depth 24/32 is handled — that is what
         * every toolkit we care about sends. XYPixmap/bitmap would need plane
         * assembly and no observed client asks for it. */
        uint8_t  format = data[1];
        uint32_t drawable = *reinterpret_cast<const uint32_t*>(data + 4);
        uint16_t w = *reinterpret_cast<const uint16_t*>(data + 12);
        uint16_t h = *reinterpret_cast<const uint16_t*>(data + 14);
        int16_t  dst_x = *reinterpret_cast<const int16_t*>(data + 16);
        int16_t  dst_y = *reinterpret_cast<const int16_t*>(data + 18);
        uint8_t  depth = data[21];

        if (format != 2 || (depth != 24 && depth != 32) || w == 0 || h == 0) {
            break;  /* silently ignored: no reply is expected either way */
        }
        /* Rows are padded to 4 bytes; at 4 bytes/pixel that is already exact. */
        int stride = static_cast<int>(w) * 4;
        size_t need = static_cast<size_t>(stride) * h;
        if (24 + need > static_cast<size_t>(len)) break;  /* truncated request */

        /* Pixmap target: Qt's no-SHM backingstore paints PutImage into a
         * pixmap, then CopyAreas it to the window (WeChat's login window
         * takes this path). Keep an RGBA shadow on the pixmap. */
        if (X11Pixmap* pm = find_pixmap(server, drawable)) {
            if (pm->width == 0 || pm->height == 0) break;
            if (pm->shadow.empty())
                pm->shadow.assign(static_cast<size_t>(pm->width) * pm->height * 4, 0);
            for (int row = 0; row < h; row++) {
                int py = dst_y + row;
                if (py < 0 || py >= pm->height) continue;
                const uint8_t* s = data + 24 + static_cast<size_t>(row) * stride;
                uint8_t* d = pm->shadow.data() + static_cast<size_t>(py) * pm->width * 4;
                for (int col = 0; col < w; col++) {
                    int px = dst_x + col;
                    if (px < 0 || px >= pm->width) continue;
                    const uint8_t* sp = s + static_cast<size_t>(col) * 4;
                    uint8_t* dp = d + static_cast<size_t>(px) * 4;
                    dp[0] = sp[2]; dp[1] = sp[1]; dp[2] = sp[0]; dp[3] = 0xff;
                }
            }
            break;
        }

        int off_x = 0, off_y = 0;
        X11Window* win = shadow_target(server, drawable, &off_x, &off_y);
        if (!win) break;
        blit_zpixmap(win, data + 24, w, h, stride, dst_x + off_x, dst_y + off_y);
        flush_shadow(server, win);
        break;
    }

    case X11_COPY_AREA: {
        /* CopyArea: src(4)@4 dst(4)@8 gc(4)@12 src-x(2)@16 src-y(2)@18
         * dst-x(2)@20 dst-y(2)@22 w(2)@24 h(2)@26. Supported flows: CPU
         * pixmap shadow → window shadow (Qt backingstore flush) and pixmap →
         * pixmap. Window→window scrolls are not needed by observed clients. */
        uint32_t src_id = *reinterpret_cast<const uint32_t*>(data + 4);
        uint32_t dst_id = *reinterpret_cast<const uint32_t*>(data + 8);
        int16_t  sx = *reinterpret_cast<const int16_t*>(data + 16);
        int16_t  sy = *reinterpret_cast<const int16_t*>(data + 18);
        int16_t  dx = *reinterpret_cast<const int16_t*>(data + 20);
        int16_t  dy = *reinterpret_cast<const int16_t*>(data + 22);
        uint16_t cw = *reinterpret_cast<const uint16_t*>(data + 24);
        uint16_t ch = *reinterpret_cast<const uint16_t*>(data + 26);
        X11Pixmap* src_pm = find_pixmap(server, src_id);
        if (!src_pm || src_pm->shadow.empty() || cw == 0 || ch == 0) break;

        if (X11Pixmap* dst_pm = find_pixmap(server, dst_id)) {
            if (dst_pm->width == 0 || dst_pm->height == 0) break;
            if (dst_pm->shadow.empty())
                dst_pm->shadow.assign(static_cast<size_t>(dst_pm->width) * dst_pm->height * 4, 0);
            for (int row = 0; row < ch; row++) {
                int syy = sy + row, dyy = dy + row;
                if (syy < 0 || syy >= src_pm->height || dyy < 0 || dyy >= dst_pm->height) continue;
                for (int col = 0; col < cw; col++) {
                    int sxx = sx + col, dxx = dx + col;
                    if (sxx < 0 || sxx >= src_pm->width || dxx < 0 || dxx >= dst_pm->width) continue;
                    std::memcpy(dst_pm->shadow.data() + (static_cast<size_t>(dyy) * dst_pm->width + dxx) * 4,
                                src_pm->shadow.data() + (static_cast<size_t>(syy) * src_pm->width + sxx) * 4, 4);
                }
            }
            break;
        }

        int off_x = 0, off_y = 0;
        X11Window* win = shadow_target(server, dst_id, &off_x, &off_y);
        if (!win) break;
        ensure_shadow(win);
        if (win->shadow.empty()) break;
        for (int row = 0; row < ch; row++) {
            int syy = sy + row, dyy = dy + off_y + row;
            if (syy < 0 || syy >= src_pm->height || dyy < 0 || dyy >= win->shadow_h) continue;
            const uint8_t* s = src_pm->shadow.data() + static_cast<size_t>(syy) * src_pm->width * 4;
            uint8_t* d = win->shadow.data() + static_cast<size_t>(dyy) * win->shadow_w * 4;
            for (int col = 0; col < cw; col++) {
                int sxx = sx + col, dxx = dx + off_x + col;
                if (sxx < 0 || sxx >= src_pm->width || dxx < 0 || dxx >= win->shadow_w) continue;
                std::memcpy(d + static_cast<size_t>(dxx) * 4,
                            s + static_cast<size_t>(sxx) * 4, 4);
            }
        }
        flush_shadow(server, win);
        break;
    }

    case 73: {
        /* GetImage — screen capture (Zoom screen share, xwd, ffmpeg x11grab).
         * Only ZPixmap (format 2) is served; the root/screen visual is
         * depth-32 TrueColor, so each pixel is 4 bytes BGRX. Pixels come from
         * the compositor's presented frame via config.capture_screen. x/y are
         * treated as screen coordinates (grabbers GetImage the root). */
        uint8_t format = data[1];
        int16_t rx = *reinterpret_cast<const int16_t*>(data + 8);
        int16_t ry = *reinterpret_cast<const int16_t*>(data + 10);
        uint16_t rw = *reinterpret_cast<const uint16_t*>(data + 12);
        uint16_t rh = *reinterpret_cast<const uint16_t*>(data + 14);
        fprintf(stderr, "[X11Server] GetImage fmt=%d %ux%u+%d+%d\n",
                format, rw, rh, rx, ry);
        if (format != 2 || rw == 0 || rh == 0) {
            uint8_t reply[32] = {};
            reply[0] = 1;
            *reinterpret_cast<uint16_t*>(reply + 2) = seq;
            send_to_client(server, client_idx, reply, 32);
            break;
        }
        size_t img_bytes = static_cast<size_t>(rw) * rh * 4;
        std::vector<uint8_t> reply(32 + img_bytes, 0);
        reply[0] = 1;    /* Reply */
        reply[1] = 32;   /* depth (root visual is depth 32) */
        *reinterpret_cast<uint16_t*>(&reply[2]) = seq;
        *reinterpret_cast<uint32_t*>(&reply[4]) = static_cast<uint32_t>(img_bytes / 4);
        *reinterpret_cast<uint32_t*>(&reply[8]) = 0x22;  /* root visual id */
        int ok = 0;
        if (server->config.capture_screen) {
            ok = server->config.capture_screen(server->config.userdata,
                                                rx, ry, rw, rh,
                                                reply.data() + 32,
                                                static_cast<int>(img_bytes));
        }
        if (!ok) {
            /* No frame mirrored yet — send a black but opaque frame so the
             * client keeps polling until captures start flowing. */
            for (size_t i = 0; i < img_bytes; i += 4) reply[32 + i + 3] = 0xff;
        }
        send_to_client(server, client_idx, reply.data(),
                       static_cast<int>(reply.size()));
        break;
    }

    default:
        /* Extension dispatch */
        if (opcode == 149) { handle_dri3(server, client_idx, data[1], data, len, seq); }
        else if (opcode == 148) { handle_present(server, client_idx, data[1], data, len, seq); }
        else if (opcode == 128) { handle_glx(server, client_idx, data[1], data, len, seq); }
        else if (opcode == 139) { handle_render(server, client_idx, data[1], data, len, seq); }
        else if (opcode == 140) { handle_randr(server, client_idx, data[1], data, len, seq); }
        else if (opcode == 142) { handle_composite(server, client_idx, data[1], data, len, seq); }
        else if (opcode == 138) { handle_xfixes(server, client_idx, data[1], data, len, seq); }
        else if (opcode == 130) { handle_shape(server, client_idx, data[1], data, len, seq); }
        else if (opcode == 131) { handle_xi2(server, client_idx, data[1], data, len, seq); }
        else if (opcode == 134) { handle_sync(server, client_idx, data[1], data, len, seq); }
        else if (opcode == 135) { handle_shm(server, client_idx, data[1], data, len, seq); }
        else if (opcode == 136) { handle_xkb(server, client_idx, data[1], data, len, seq); }
        else if (opcode == 133) {
            /* BIG-REQUESTS */
            if (data[1] == 0) {
                uint8_t reply[32] = {};
                reply[0] = 1;
                *reinterpret_cast<uint16_t*>(reply + 2) = seq;
                *reinterpret_cast<uint32_t*>(reply + 8) = 4194303;
                send_to_client(server, client_idx, reply, 32);
            }
        }
        else if (opcode == 143) {
            /* GE */
            if (data[1] == 0) {
                uint8_t reply[32] = {};
                reply[0] = 1;
                *reinterpret_cast<uint16_t*>(reply + 2) = seq;
                *reinterpret_cast<uint16_t*>(reply + 8) = 1;
                *reinterpret_cast<uint16_t*>(reply + 10) = 0;
                send_to_client(server, client_idx, reply, 32);
            }
        }
        else if (opcode == 144) { handle_xtest(server, client_idx, data[1], data, len, seq); }
        else if (opcode >= 128) {
            fprintf(stderr, "[X11Server] Extension opcode=%d minor=%d -> error\n", opcode, data[1]);
            uint8_t err[32] = {};
            err[0] = 0; err[1] = 1;
            *reinterpret_cast<uint16_t*>(err + 2) = seq;
            err[10] = opcode; err[11] = data[1];
            send_to_client(server, client_idx, err, 32);
        } else {
            int needs_reply = 0;
            switch (opcode) {
            case 3: case 14: case 15: case 16: case 17: case 20: case 21:
            case 23: case 26: case 38: case 40: case 43: case 47: case 49:
            case 52: case 83: case 84: case 91: case 92: case 97:
            case 98: case 99: case 101: case 103: case 110:
            case 116: case 117: case 119:
                needs_reply = 1; break;
            }
            if (needs_reply) {
                fprintf(stderr, "[X11Server] Unhandled core opcode %d (needs reply) -> empty reply\n", opcode);
                uint8_t reply[32] = {};
                reply[0] = 1;
                *reinterpret_cast<uint16_t*>(reply + 2) = seq;
                send_to_client(server, client_idx, reply, 32);
            } else {
                fprintf(stderr, "[X11Server] Unhandled core opcode %d (void)\n", opcode);
            }
        }
        break;
    }
}

/* ========================================================================== */
/* DRI3 extension handler                                                      */
/* ========================================================================== */

static void handle_dri3(X11Server* server, int client_idx, uint8_t minor,
                        const uint8_t* data, int len, uint16_t seq) {
    X11Client* client = &server->clients[client_idx];
    fprintf(stderr, "[X11Server] DRI3 minor=%d\n", minor);
    switch (minor) {
    case 0: {
        uint8_t reply[32] = {};
        reply[0] = 1;
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 8) = 1;
        *reinterpret_cast<uint32_t*>(reply + 12) = 2;
        send_to_client(server, client_idx, reply, 32);
        break;
    }
    case 1: {
        const char* node = dri3_render_node_path();
        fprintf(stderr, "[X11Server] DRI3Open -> %s\n", node);
        int gpu_fd = open(node, O_RDWR);
        if (gpu_fd < 0) {
            fprintf(stderr, "[X11Server] Failed to open %s: %s\n", node, strerror(errno));
            uint8_t err[32] = {};
            err[0] = 0; err[1] = 4;
            *reinterpret_cast<uint16_t*>(err + 2) = seq;
            send_to_client(server, client_idx, err, 32);
            break;
        }
        uint8_t reply[32] = {};
        reply[0] = 1; reply[1] = 1;
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        struct iovec iov;
        iov.iov_base = reply; iov.iov_len = 32;
        uint8_t cmsg_buf[CMSG_SPACE(sizeof(int))];
        struct msghdr msg;
        std::memset(&msg, 0, sizeof(msg));
        msg.msg_iov = &iov; msg.msg_iovlen = 1;
        msg.msg_control = cmsg_buf; msg.msg_controllen = sizeof(cmsg_buf);
        struct cmsghdr* cmsg = CMSG_FIRSTHDR(&msg);
        cmsg->cmsg_level = SOL_SOCKET;
        cmsg->cmsg_type = SCM_RIGHTS;
        cmsg->cmsg_len = CMSG_LEN(sizeof(int));
        std::memcpy(CMSG_DATA(cmsg), &gpu_fd, sizeof(int));
        sendmsg(client->fd, &msg, 0);
        close(gpu_fd);
        break;
    }
    case 2: {
        uint32_t pixmap_id = *reinterpret_cast<const uint32_t*>(data + 4);
        uint32_t drawable = *reinterpret_cast<const uint32_t*>(data + 8);
        uint16_t width = *reinterpret_cast<const uint16_t*>(data + 16);
        uint16_t height = *reinterpret_cast<const uint16_t*>(data + 18);
        uint16_t stride = *reinterpret_cast<const uint16_t*>(data + 20);
        uint8_t depth = data[22]; uint8_t bpp = data[23];
        int dma_fd = consume_pending_fd(client);
        fprintf(stderr, "[X11Server] DRI3PixmapFromBuffer: pixmap=0x%x %ux%u stride=%u depth=%u bpp=%u fd=%d\n",
                pixmap_id, width, height, stride, depth, bpp, dma_fd);
        uint32_t fourcc = 0;
        if (depth == 24 && bpp == 32) fourcc = DRM_FORMAT_XRGB8888;
        else if (depth == 32 && bpp == 32) fourcc = DRM_FORMAT_ARGB8888;
        X11Pixmap* existing = find_pixmap(server, pixmap_id);
        if (existing) {
            if (existing->dma_fd >= 0 && existing->dma_fd != dma_fd) close(existing->dma_fd);
            if (existing->fence_fd >= 0) close(existing->fence_fd);
            existing->dma_fd = dma_fd; existing->fence_fd = -1; existing->fence_xid = 0;
            existing->width = width; existing->height = height;
            existing->stride = stride; existing->fourcc = fourcc;
            existing->window_id = drawable; existing->last_serial = 0;
        } else {
            X11Pixmap pix;
            pix.id = pixmap_id; pix.dma_fd = dma_fd; pix.fence_fd = -1; pix.fence_xid = 0;
            pix.width = width; pix.height = height; pix.stride = stride;
            pix.fourcc = fourcc; pix.window_id = drawable; pix.last_serial = 0;
            server->pixmaps.push_back(std::move(pix));
        }
        break;
    }
    case 6: {
        /* GetSupportedModifiers — advertise LINEAR only. Mesa then
         * allocates swapchains with an explicit linear layout instead of
         * implicit (tiled on GFX11), which the compositor imports
         * correctly — the same contract the wayland dmabuf feedback
         * gives Chrome. An empty list here sends Mesa down the implicit
         * PixmapFromBuffer path and the composited window is tile
         * garbage. */
        uint8_t reply[48] = {};
        reply[0] = 1;
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 4) = 4;   /* extra length in words */
        *reinterpret_cast<uint32_t*>(reply + 8) = 1;   /* num window modifiers */
        *reinterpret_cast<uint32_t*>(reply + 12) = 1;  /* num screen modifiers */
        /* bytes 32-39 window modifier, 40-47 screen modifier: both
         * DRM_FORMAT_MOD_LINEAR (0) — already zeroed. */
        send_to_client(server, client_idx, reply, 48);
        break;
    }
    case 4: {
        uint32_t fence_xid = *reinterpret_cast<const uint32_t*>(data + 8);
        int fence_fd = consume_pending_fd(client);
        fprintf(stderr, "[X11Server] DRI3FenceFromFD: fence=0x%x fd=%d\n", fence_xid, fence_fd);
        /* Find or create fence entry */
        X11Fence* fslot = nullptr;
        for (auto& f : server->fences) {
            if (f.xid == fence_xid) { fslot = &f; break; }
        }
        if (!fslot) {
            server->fences.emplace_back();
            fslot = &server->fences.back();
            fslot->xid = fence_xid;
            fslot->triggered = 0;
        }
        if (fslot && fence_fd >= 0) {
            fslot->fd = fence_fd;
            fslot->shm_fence = xshmfence_map_shm(fence_fd);
            fprintf(stderr, "[X11Server] Fence 0x%x mapped shm=%p\n",
                    fence_xid, static_cast<void*>(fslot->shm_fence));
        }
        /* Store on the most recent pixmap */
        if (!server->pixmaps.empty()) {
            for (auto it = server->pixmaps.rbegin(); it != server->pixmaps.rend(); ++it) {
                if (it->fence_xid == 0) {
                    it->fence_xid = fence_xid;
                    it->fence_fd = fence_fd;
                    break;
                }
            }
        }
        break;
    }
    case 5: {
        uint8_t reply[32] = {};
        reply[0] = 1; reply[1] = 1;
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        int efd = eventfd(1, EFD_CLOEXEC);
        struct iovec iov;
        iov.iov_base = reply; iov.iov_len = 32;
        uint8_t cmsg_buf[CMSG_SPACE(sizeof(int))];
        struct msghdr msg;
        std::memset(&msg, 0, sizeof(msg));
        msg.msg_iov = &iov; msg.msg_iovlen = 1;
        msg.msg_control = cmsg_buf; msg.msg_controllen = sizeof(cmsg_buf);
        struct cmsghdr* cmsg = CMSG_FIRSTHDR(&msg);
        cmsg->cmsg_level = SOL_SOCKET; cmsg->cmsg_type = SCM_RIGHTS;
        cmsg->cmsg_len = CMSG_LEN(sizeof(int));
        std::memcpy(CMSG_DATA(cmsg), &efd, sizeof(int));
        sendmsg(client->fd, &msg, 0);
        close(efd);
        break;
    }
    case 7: {
        /* PixmapFromBuffers: pixmap(4) window(8) num_buffers(12) pad(13-15)
         * width(16) height(18) stride0(20) offset0(24) ... depth(52)
         * bpp(53) modifier(56). */
        uint32_t pixmap_id = *reinterpret_cast<const uint32_t*>(data + 4);
        uint32_t drawable = *reinterpret_cast<const uint32_t*>(data + 8);
        uint16_t width = *reinterpret_cast<const uint16_t*>(data + 16);
        uint16_t height = *reinterpret_cast<const uint16_t*>(data + 18);
        uint32_t stride0 = *reinterpret_cast<const uint32_t*>(data + 20);
        uint8_t depth = data[52]; uint8_t bpp = data[53];
        uint64_t modifier = (len >= 64)
            ? *reinterpret_cast<const uint64_t*>(data + 56) : 0;
        int dma_fd = consume_pending_fd(client);
        uint32_t fourcc = (depth == 24 && bpp == 32) ? DRM_FORMAT_XRGB8888 :
                          (depth == 32 && bpp == 32) ? DRM_FORMAT_ARGB8888 : 0;
        fprintf(stderr, "[X11Server] DRI3PixmapFromBuffers: 0x%x %ux%u stride=%u mod=0x%llx fd=%d\n",
                pixmap_id, width, height, stride0,
                static_cast<unsigned long long>(modifier), dma_fd);
        X11Pixmap* ex = find_pixmap(server, pixmap_id);
        if (ex) {
            if (ex->dma_fd >= 0 && ex->dma_fd != dma_fd) close(ex->dma_fd);
            ex->dma_fd = dma_fd; ex->width = width; ex->height = height;
            ex->stride = static_cast<uint16_t>(stride0); ex->fourcc = fourcc; ex->window_id = drawable;
        } else {
            X11Pixmap p;
            p.id = pixmap_id; p.dma_fd = dma_fd; p.width = width;
            p.height = height; p.stride = static_cast<uint16_t>(stride0); p.fourcc = fourcc;
            p.window_id = drawable;
            server->pixmaps.push_back(std::move(p));
        }
        break;
    }
    case 8: {
        uint32_t pixmap_id = *reinterpret_cast<const uint32_t*>(data + 4);
        X11Pixmap* pix = find_pixmap(server, pixmap_id);
        /* Mesa asks BuffersFromPixmap for pixmap-like drawables the server
         * owns: NameWindowPixmap backing stores AND GLX pbuffers (which the
         * GLX handler registers as fake windows). Create a pixmap record on
         * the fly for those so they get storage below. */
        if (!pix) {
            X11Window* dw = find_window(server, pixmap_id);
            /* GLX pbuffer fakes (override_redirect): answer like Xwayland —
             * BadPixmap. Mesa then falls back to client-local buffers for
             * the pbuffer, the path WeChatAppEx's GL init survives (it
             * renders offscreen and the Qt process PutImages the result).
             * Handing it a synthesized LINEAR buffer here sent Mesa down a
             * direct-render path that killed GL init → login spinner. */
            if (dw && dw->override_redirect) {
                uint8_t err[32] = {};
                err[0] = 0; err[1] = 4; /* BadPixmap */
                *reinterpret_cast<uint16_t*>(err + 2) = seq;
                *reinterpret_cast<uint32_t*>(err + 4) = pixmap_id;
                *reinterpret_cast<uint16_t*>(err + 8) = 8; /* minor */
                err[10] = 149; /* DRI3 major opcode */
                send_to_client(server, client_idx, err, 32);
                break;
            }
            if (dw && dw->width > 0 && dw->height > 0) {
                X11Pixmap np;
                np.id = pixmap_id;
                np.width = dw->width; np.height = dw->height;
                np.window_id = pixmap_id;
                server->pixmaps.push_back(std::move(np));
                pix = find_pixmap(server, pixmap_id);
            }
        }
        /* Server-owned pixmap with no storage yet: allocate it now and (for
         * window-backed pixmaps) hand the compositor the live dmabuf — the
         * client's GL renders land in it zero-copy from here on. */
        if (pix && pix->dma_fd < 0) {
            if (pixmap_allocate_storage(server, pix) >= 0 &&
                pix->window_id != 0 && server->config.on_present_buffer) {
                server->config.on_present_buffer(server->config.userdata,
                    pix->window_id, pix->dma_fd, pix->width, pix->height,
                    pix->stride, pix->fourcc);
            }
        }
        int has_fd = (pix && pix->dma_fd >= 0);
        int nfd = has_fd ? 1 : 0;
        int extra8 = nfd * 4 + nfd * 4;
        int rlen8 = 32 + extra8;
        uint8_t rpl8[40];
        std::memset(rpl8, 0, static_cast<size_t>(rlen8));
        rpl8[0] = 1; rpl8[1] = static_cast<uint8_t>(nfd);
        *reinterpret_cast<uint16_t*>(rpl8 + 2) = seq;
        *reinterpret_cast<uint32_t*>(rpl8 + 4) = static_cast<uint32_t>(extra8 / 4);
        if (pix) {
            *reinterpret_cast<uint16_t*>(rpl8 + 8) = pix->width;
            *reinterpret_cast<uint16_t*>(rpl8 + 10) = pix->height;
            /* Modifier: LINEAR for storage we allocated (we know its layout);
             * INVALID (implicit) for client-attached buffers as before. */
            *reinterpret_cast<uint64_t*>(rpl8 + 16) = pix->server_allocated
                ? 0ULL : 0x00ffffffffffffffULL;
            /* depth/bpp live AFTER the modifier (xcb_dri3_buffers_from_pixmap
             * _reply_t: pad0[4] at 12, modifier at 16, depth/bpp at 24/25).
             * They were written into the pad at 12/13 before, so Mesa's GLX
             * loader saw depth=0/bpp=0 on its 1x1 probe and silently bailed —
             * WeChatAppEx-GL froze at the spinner while Chrome's EGL path,
             * which ignores the fields, sailed through. */
            rpl8[24] = 24; rpl8[25] = 32;
            if (has_fd) *reinterpret_cast<uint32_t*>(rpl8 + 32) = pix->stride;
        } else {
            X11Window* bfpw = find_window(server, pixmap_id);
            if (bfpw) {
                *reinterpret_cast<uint16_t*>(rpl8 + 8) = bfpw->width;
                *reinterpret_cast<uint16_t*>(rpl8 + 10) = bfpw->height;
                rpl8[24] = 24; rpl8[25] = 32;
            }
        }
        fprintf(stderr, "[X11Server] DRI3BuffersFromPixmap: id=0x%x pix=%p nfd=%d\n",
                pixmap_id, static_cast<void*>(pix), nfd);
        if (has_fd) {
            int dup_fd = dup(pix->dma_fd);
            struct iovec iov;
            iov.iov_base = rpl8; iov.iov_len = static_cast<size_t>(rlen8);
            uint8_t cmsg_buf[CMSG_SPACE(sizeof(int))];
            struct msghdr msg;
            std::memset(&msg, 0, sizeof(msg));
            msg.msg_iov = &iov; msg.msg_iovlen = 1;
            msg.msg_control = cmsg_buf; msg.msg_controllen = sizeof(cmsg_buf);
            struct cmsghdr* cm = CMSG_FIRSTHDR(&msg);
            cm->cmsg_level = SOL_SOCKET; cm->cmsg_type = SCM_RIGHTS;
            cm->cmsg_len = CMSG_LEN(sizeof(int));
            std::memcpy(CMSG_DATA(cm), &dup_fd, sizeof(int));
            sendmsg(client->fd, &msg, 0);
            close(dup_fd);
        } else {
            send_to_client(server, client_idx, rpl8, rlen8);
        }
        break;
    }
    case 3: {
        uint32_t pixmap_id = *reinterpret_cast<const uint32_t*>(data + 4);
        X11Pixmap* pix = find_pixmap(server, pixmap_id);
        int has_fd = (pix && pix->dma_fd >= 0);
        fprintf(stderr, "[X11Server] DRI3BufferFromPixmap: id=0x%x has_fd=%d\n", pixmap_id, has_fd);
        uint8_t rpl3[32] = {};
        rpl3[0] = 1; rpl3[1] = has_fd ? 1 : 0;
        *reinterpret_cast<uint16_t*>(rpl3 + 2) = seq;
        if (pix) {
            /* xcb_dri3_buffer_from_pixmap_reply_t: size@8, width@12,
             * height@14, stride@16, depth@18, bpp@19. */
            *reinterpret_cast<uint32_t*>(rpl3 + 8) =
                static_cast<uint32_t>(pix->stride) * pix->height;
            *reinterpret_cast<uint16_t*>(rpl3 + 12) = pix->width;
            *reinterpret_cast<uint16_t*>(rpl3 + 14) = pix->height;
            *reinterpret_cast<uint16_t*>(rpl3 + 16) = pix->stride;
            rpl3[18] = 24; rpl3[19] = 32;
        }
        if (has_fd) {
            int dup_fd = dup(pix->dma_fd);
            struct iovec iov;
            iov.iov_base = rpl3; iov.iov_len = 32;
            uint8_t cmsg_buf[CMSG_SPACE(sizeof(int))];
            struct msghdr msg;
            std::memset(&msg, 0, sizeof(msg));
            msg.msg_iov = &iov; msg.msg_iovlen = 1;
            msg.msg_control = cmsg_buf; msg.msg_controllen = sizeof(cmsg_buf);
            struct cmsghdr* cm = CMSG_FIRSTHDR(&msg);
            cm->cmsg_level = SOL_SOCKET; cm->cmsg_type = SCM_RIGHTS;
            cm->cmsg_len = CMSG_LEN(sizeof(int));
            std::memcpy(CMSG_DATA(cm), &dup_fd, sizeof(int));
            sendmsg(client->fd, &msg, 0);
            close(dup_fd);
        } else {
            send_to_client(server, client_idx, rpl3, 32);
        }
        break;
    }
    default:
        fprintf(stderr, "[X11Server] DRI3 minor=%d (unhandled)\n", minor);
        if (minor == 9 || minor == 10) {
            uint8_t err[32] = {};
            err[0] = 0; err[1] = 17;
            *reinterpret_cast<uint16_t*>(err + 2) = seq;
            send_to_client(server, client_idx, err, 32);
        }
        break;
    }
}

/* ========================================================================== */
/* Present extension handler                                                   */
/* ========================================================================== */

static void handle_present(X11Server* server, int client_idx, uint8_t minor,
                           const uint8_t* data, int len, uint16_t seq) {
    switch (minor) {
    case 0: {
        uint8_t reply[32] = {};
        reply[0] = 1;
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 8) = 1;
        *reinterpret_cast<uint32_t*>(reply + 12) = 2;
        send_to_client(server, client_idx, reply, 32);
        break;
    }
    case 1: {
        uint32_t window = *reinterpret_cast<const uint32_t*>(data + 4);
        uint32_t pixmap = *reinterpret_cast<const uint32_t*>(data + 8);
        uint32_t serial = *reinterpret_cast<const uint32_t*>(data + 12);
        fprintf(stderr, "[X11Server] PresentPixmap: win=0x%x pix=0x%x serial=%u\n", window, pixmap, serial);

        X11Pixmap* pix = find_pixmap(server, pixmap);
        if (pix && pix->dma_fd >= 0) {
            pix->window_id = window;
            pix->last_serial = serial;
            if (server->config.on_present_buffer) {
                fprintf(stderr, "[X11Server] Calling on_present_buffer: win=0x%x fd=%d %dx%d stride=%d fourcc=0x%x\n",
                        window, pix->dma_fd, pix->width, pix->height, pix->stride, pix->fourcc);
                server->config.on_present_buffer(server->config.userdata, window,
                    pix->dma_fd, pix->width, pix->height, pix->stride, pix->fourcc);
                fprintf(stderr, "[X11Server] on_present_buffer returned\n");
            }
        } else {
            fprintf(stderr, "[X11Server] PresentPixmap: pixmap 0x%x not found or no dma_fd (pix=%p fd=%d)\n",
                    pixmap, static_cast<void*>(pix), pix ? pix->dma_fd : -1);
        }

        X11Window* pwin = find_window(server, window);
        if (pwin && pwin->front_pixmap != 0 && pwin->front_pixmap != pixmap) {
            for (auto& f : server->fences) {
                if (f.xid == pwin->front_fence_xid && f.shm_fence) {
                    xshmfence_trigger(f.shm_fence);
                    break;
                }
            }
        }
        if (pwin) {
            /* A new present superseding a front whose events never went out
             * must still complete the OLD one: queue it for vblank_tick.
             * Dropping it leaks that buffer in the client's swapchain — Mesa
             * waits forever on its IdleNotify (Chrome: serial 1 stall). */
            if (pwin->front_pixmap != 0 && pwin->front_pixmap != pixmap &&
                !pwin->front_idle_sent &&
                server->pending_complete_count <
                    static_cast<int>(sizeof(server->pending_complete) /
                                     sizeof(server->pending_complete[0]))) {
                auto& pc = server->pending_complete[server->pending_complete_count++];
                pc.window = pwin->id;
                pc.serial = pwin->front_serial;
                pc.eid = pwin->front_eid;
                pc.client = pwin->front_client;
                pc.pixmap = pwin->front_pixmap;
                pc.fence_xid = pwin->front_fence_xid;
            }
            pwin->front_pixmap = pixmap;
            pwin->front_serial = serial;
            pwin->front_client = client_idx;
            pwin->front_idle_sent = 0;  /* new front — vblank needs to send events */
            /* Use the LAST active registration (non-zero mask) for this client.
             * Chrome unregisters old eids (mask=0) and registers new ones.
             * Using a stale eid causes libxcb to misroute events to the main
             * queue instead of the special event queue, deadlocking the GPU. */
            for (auto& r : pwin->present_regs) {
                if (r.client == client_idx && r.mask != 0) { pwin->front_eid = r.eid; }
            }
            X11Pixmap* fpix = find_pixmap(server, pixmap);
            pwin->front_fence_xid = fpix ? fpix->fence_xid : 0;
        }
        /* IdleNotify + CompleteNotify deferred to vblank_tick, matching real
         * Xorg which sends these at vblank time, not immediately.  Chrome's
         * ANGLE frame pacing depends on receiving CompleteNotify at vblank
         * cadence — immediate delivery confuses it into a busy-poll loop. */
        break;
    }
    case 3: {
        uint32_t eid = *reinterpret_cast<const uint32_t*>(data + 4);
        uint32_t window = *reinterpret_cast<const uint32_t*>(data + 8);
        uint32_t event_mask = *reinterpret_cast<const uint32_t*>(data + 12);
        X11Window* pwin = find_window(server, window);
        if (pwin) {
            int slot = -1;
            for (int r = 0; r < static_cast<int>(pwin->present_regs.size()); r++) {
                if (pwin->present_regs[static_cast<size_t>(r)].eid == eid) { slot = r; break; }
            }
            if (event_mask == 0) {
                if (slot >= 0) {
                    pwin->present_regs.erase(pwin->present_regs.begin() + slot);
                }
            } else {
                if (slot < 0) {
                    /* Flush IdleNotify for all pixmaps on old eids before adding new eid */
                    for (auto& er : pwin->present_regs) {
                        uint32_t old_eid = er.eid;
                        int old_client = er.client;
                        if (old_client < 0 || old_client >= server->client_count ||
                            server->clients[old_client].fd < 0) continue;
                        uint16_t oseq = server->clients[old_client].sequence;
                        for (auto& p : server->pixmaps) {
                            if (p.window_id != window) continue;
                            uint8_t idle[32] = {};
                            idle[0] = X11_GENERIC_EVENT; idle[1] = 148;
                            *reinterpret_cast<uint16_t*>(idle + 2) = oseq;
                            *reinterpret_cast<uint16_t*>(idle + 8) = PRESENT_IDLE_NOTIFY;
                            *reinterpret_cast<uint32_t*>(idle + 12) = old_eid;
                            *reinterpret_cast<uint32_t*>(idle + 16) = window;
                            *reinterpret_cast<uint32_t*>(idle + 20) = p.last_serial;
                            *reinterpret_cast<uint32_t*>(idle + 24) = p.id;
                            *reinterpret_cast<uint32_t*>(idle + 28) = p.fence_xid;
                            send_to_client(server, old_client, idle, 32);
                            for (auto& f : server->fences) {
                                if (f.xid == p.fence_xid && f.shm_fence) { xshmfence_trigger(f.shm_fence); break; }
                            }
                        }
                    }
                    PresentReg nr;
                    nr.eid = eid; nr.mask = event_mask; nr.client = client_idx;
                    pwin->present_regs.push_back(nr);
                } else {
                    pwin->present_regs[static_cast<size_t>(slot)].mask = event_mask;
                    pwin->present_regs[static_cast<size_t>(slot)].client = client_idx;
                }
            }
            fprintf(stderr, "[X11Server] PresentSelectInput: win=0x%x eid=0x%x mask=0x%x client=%d (regs=%d)\n",
                    window, eid, event_mask, client_idx, static_cast<int>(pwin->present_regs.size()));
        }
        break;
    }
    case 4: {
        uint8_t reply[32] = {};
        reply[0] = 1;
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 8) = 1;
        send_to_client(server, client_idx, reply, 32);
        break;
    }
    case 2: {
        /* PresentNotifyMSC — client wants a CompleteNotify at a target MSC.
         * Send a PresentCompleteNotify immediately with kind=NotifyMSC.
         * This unblocks the GPU process's frame pacing loop. */
        uint32_t window = *reinterpret_cast<const uint32_t*>(data + 4);
        /* serial is at offset 8 (offset 12 is padding — reading it there
         * echoed serial=0, and Chrome matches MSC waits by serial). */
        uint32_t serial = *reinterpret_cast<const uint32_t*>(data + 8);

        X11Window* pwin = find_window(server, window);
        if (pwin) {
            /* Find the active present event registration for this client */
            uint32_t eid = 0;
            for (auto& r : pwin->present_regs) {
                if (r.client == client_idx && r.mask != 0) { eid = r.eid; }
            }
            if (eid != 0) {
                /* Send PresentCompleteNotify with kind=NotifyMSC (1) */
                uint8_t ev[40] = {};
                ev[0] = 35; /* GenericEvent */
                ev[1] = 148; /* Present extension */
                *reinterpret_cast<uint16_t*>(ev + 2) = server->clients[client_idx].sequence;
                *reinterpret_cast<uint32_t*>(ev + 4) = (40 - 32) / 4; /* length = 2 words */
                *reinterpret_cast<uint16_t*>(ev + 8) = 1; /* PresentCompleteNotify */
                *reinterpret_cast<uint16_t*>(ev + 10) = 1; /* kind = NotifyMSC */
                *reinterpret_cast<uint32_t*>(ev + 12) = eid;
                *reinterpret_cast<uint32_t*>(ev + 16) = window;
                *reinterpret_cast<uint32_t*>(ev + 20) = serial;
                /* ust (bytes 24-31): microsecond timestamp */
                struct timespec ts;
                clock_gettime(CLOCK_MONOTONIC, &ts);
                uint64_t ust = static_cast<uint64_t>(ts.tv_sec) * 1000000ULL +
                               static_cast<uint64_t>(ts.tv_nsec) / 1000ULL;
                *reinterpret_cast<uint64_t*>(ev + 24) = ust;
                /* msc (bytes 32-39): same clock as vblank_tick — a constant 0
                 * (present_msc was never advanced) stalled frame pacing. */
                server->present_msc = ust / 16667;
                *reinterpret_cast<uint64_t*>(ev + 32) = server->present_msc;
                send_to_client(server, client_idx, ev, 40);
            }
        }
        break;
    }
    default:
        fprintf(stderr, "[X11Server] Present minor=%d (unhandled)\n", minor);
        break;
    }
}

/* ========================================================================== */
/* GLX extension handler                                                       */
/* ========================================================================== */

static void handle_glx(X11Server* server, int client_idx, uint8_t minor,
                       const uint8_t* data, int len, uint16_t seq) {
    X11Client* client = &server->clients[client_idx];
    fprintf(stderr, "[X11Server] fd=%d GLX minor=%d len=%d hex=[%02x %02x %02x %02x %02x %02x %02x %02x]\n",
            client->fd, minor, len, data[0], data[1], data[2], data[3],
            len > 4 ? data[4] : 0, len > 5 ? data[5] : 0,
            len > 6 ? data[6] : 0, len > 7 ? data[7] : 0);

    if (minor == 7) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 8) = 1;
        *reinterpret_cast<uint32_t*>(reply + 12) = 4;
        send_to_client(server, client_idx, reply, 32);
    } else if (minor == 6) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        reply[8] = 1;
        send_to_client(server, client_idx, reply, 32);
    } else if (minor == 18) {
        const char* exts18 = "GLX_ARB_create_context GLX_ARB_create_context_profile "
            "GLX_EXT_create_context_es2_profile GLX_ARB_multisample "
            "GLX_EXT_visual_info GLX_EXT_visual_rating "
            "GLX_SGIX_fbconfig GLX_SGI_make_current_read "
            "GLX_EXT_texture_from_pixmap GLX_OML_sync_control "
            "GLX_SGI_video_sync GLX_EXT_swap_control "
            "GLX_EXT_swap_control_tear GLX_EXT_buffer_age "
            "GLX_SGIX_pbuffer GLX_ARB_get_proc_address "
            "GLX_MESA_swap_control GLX_MESA_query_renderer";
        int sl18 = static_cast<int>(strlen(exts18)) + 1;
        int pd18 = (4 - (sl18 & 3)) & 3;
        /* GLX single-string reply length is the padded string only; the string
         * count lives in the header at offset 12, NOT as a word before the
         * string. An extra word here overshoots `length`, and a client that
         * reads by the count leaves those bytes unread — xcb then aborts with
         * "Extra reply data still left in queue" (Chromium's GLX probe). */
        int ex18 = sl18 + pd18;
        int rl18 = 32 + ex18;
        std::vector<uint8_t> reply(static_cast<size_t>(rl18), 0);
        reply[0] = 1; *reinterpret_cast<uint16_t*>(&reply[2]) = seq;
        *reinterpret_cast<uint32_t*>(&reply[4]) = static_cast<uint32_t>(ex18 / 4);
        *reinterpret_cast<uint32_t*>(&reply[12]) = static_cast<uint32_t>(sl18);
        std::memcpy(&reply[32], exts18, static_cast<size_t>(sl18));
        send_to_client(server, client_idx, reply.data(), rl18);
    } else if (minor == 19) {
        uint32_t name = *reinterpret_cast<const uint32_t*>(data + 8);
        const char* str = "";
        if (name == 1) str = "FlutterX11";
        else if (name == 2) str = "1.4";
        else if (name == 3) str = "GLX_ARB_create_context GLX_ARB_create_context_profile "
            "GLX_EXT_create_context_es2_profile GLX_EXT_texture_from_pixmap "
            "GLX_OML_sync_control GLX_SGI_video_sync GLX_EXT_swap_control "
            "GLX_EXT_buffer_age GLX_SGIX_pbuffer GLX_ARB_get_proc_address "
            "GLX_MESA_swap_control GLX_MESA_query_renderer";
        int slen = static_cast<int>(strlen(str)) + 1;
        int pad = (4 - (slen & 3)) & 3;
        /* padded string only — see the note in the QueryExtensionsString branch */
        int extra = slen + pad;
        int reply_len = 32 + extra;
        std::vector<uint8_t> reply(static_cast<size_t>(reply_len), 0);
        reply[0] = 1; *reinterpret_cast<uint16_t*>(&reply[2]) = seq;
        *reinterpret_cast<uint32_t*>(&reply[4]) = static_cast<uint32_t>(extra / 4);
        *reinterpret_cast<uint32_t*>(&reply[12]) = static_cast<uint32_t>(slen);
        std::memcpy(&reply[32], str, static_cast<size_t>(slen));
        send_to_client(server, client_idx, reply.data(), reply_len);
    } else if (minor == 14) {
        int nv = 2, np = 18;
        int cfgsz = np * 4;
        int extra14 = nv * cfgsz;
        int rlen14 = 32 + extra14;
        std::vector<uint8_t> reply(static_cast<size_t>(rlen14), 0);
        reply[0] = 1; *reinterpret_cast<uint16_t*>(&reply[2]) = seq;
        *reinterpret_cast<uint32_t*>(&reply[4]) = static_cast<uint32_t>(extra14 / 4);
        *reinterpret_cast<uint32_t*>(&reply[8]) = static_cast<uint32_t>(nv);
        *reinterpret_cast<uint32_t*>(&reply[12]) = static_cast<uint32_t>(np);
        uint32_t* cfg = reinterpret_cast<uint32_t*>(&reply[32]);
        cfg[0]=0x21; cfg[1]=0x8002; cfg[2]=1; cfg[3]=8; cfg[4]=8; cfg[5]=8; cfg[6]=0;
        cfg[7]=0; cfg[8]=0; cfg[9]=0; cfg[10]=0; cfg[11]=1; cfg[12]=0; cfg[13]=24;
        cfg[14]=24; cfg[15]=8; cfg[16]=0; cfg[17]=0;
        cfg[18]=0x22; cfg[19]=0x8002; cfg[20]=1; cfg[21]=8; cfg[22]=8; cfg[23]=8; cfg[24]=8;
        cfg[25]=0; cfg[26]=0; cfg[27]=0; cfg[28]=0; cfg[29]=1; cfg[30]=0; cfg[31]=32;
        cfg[32]=24; cfg[33]=8; cfg[34]=0; cfg[35]=0;
        send_to_client(server, client_idx, reply.data(), rlen14);
    } else if (minor == 21) {
        int np21 = 20;
        struct { int depth; int stencil; int alpha; uint32_t visual; int buf_size; } cfgs[] = {
            { 0,  0, 0, 0x21, 24 }, { 24, 0, 0, 0x21, 24 }, { 24, 8, 0, 0x21, 24 },
            { 0,  0, 8, 0x21, 32 }, { 24, 8, 8, 0x21, 32 },
            { 0,  0, 8, 0x22, 32 }, { 24, 0, 8, 0x22, 32 }, { 24, 8, 8, 0x22, 32 },
            { 0,  0, 0, 0x22, 32 }, { 24, 8, 0, 0x22, 32 },
        };
        int nc = static_cast<int>(sizeof(cfgs) / sizeof(cfgs[0]));
        int cw = np21 * 2;
        int ex21 = nc * cw;
        int rl21 = 32 + ex21 * 4;
        std::vector<uint8_t> reply(static_cast<size_t>(rl21), 0);
        reply[0] = 1; *reinterpret_cast<uint16_t*>(&reply[2]) = seq;
        *reinterpret_cast<uint32_t*>(&reply[4]) = static_cast<uint32_t>(ex21);
        *reinterpret_cast<uint32_t*>(&reply[8]) = static_cast<uint32_t>(nc);
        *reinterpret_cast<uint32_t*>(&reply[12]) = static_cast<uint32_t>(np21);
        uint32_t* p = reinterpret_cast<uint32_t*>(&reply[32]);
        int i = 0;
        for (int c = 0; c < nc; c++) {
            p[i++]=0x8013; p[i++]=static_cast<uint32_t>(c+1);
            p[i++]=0x800B; p[i++]=cfgs[c].visual;
            p[i++]=0x2; p[i++]=static_cast<uint32_t>(cfgs[c].buf_size);
            p[i++]=0x5; p[i++]=1;
            p[i++]=0x8; p[i++]=8;
            p[i++]=0x9; p[i++]=8;
            p[i++]=0xA; p[i++]=8;
            p[i++]=0xB; p[i++]=static_cast<uint32_t>(cfgs[c].alpha);
            p[i++]=0xC; p[i++]=static_cast<uint32_t>(cfgs[c].depth);
            p[i++]=0xD; p[i++]=static_cast<uint32_t>(cfgs[c].stencil);
            p[i++]=0x22; p[i++]=0x8002;
            p[i++]=0x20; p[i++]=0x8000;
            p[i++]=0x8010; p[i++]=7;
            p[i++]=0x8011; p[i++]=0x1;
            p[i++]=0x8012; p[i++]=1;
            p[i++]=0x186A0; p[i++]=0;
            p[i++]=0x186A1; p[i++]=0;
            p[i++]=0x8016; p[i++]=4096;
            p[i++]=0x8017; p[i++]=4096;
            p[i++]=0x8018; p[i++]=4096*4096;
        }
        send_to_client(server, client_idx, reply.data(), rl21);
    } else if (minor == 5 || minor == 26) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        send_to_client(server, client_idx, reply, 32);
    } else if (minor == 25) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        send_to_client(server, client_idx, reply, 32);
    } else if (minor == 29) {
        uint32_t drawable = *reinterpret_cast<const uint32_t*>(data + 4);
        uint32_t w = 1, h = 1;
        if (drawable == server->glx_pbuffer_id) {
            w = server->glx_pbuffer_width; h = server->glx_pbuffer_height;
        } else {
            X11Window* wn = find_window(server, drawable);
            if (wn) { w = wn->width; h = wn->height; }
        }
        int n = 2, rlen = 32 + n * 2 * 4;
        std::vector<uint8_t> rpl(static_cast<size_t>(rlen), 0);
        rpl[0] = 1; *reinterpret_cast<uint16_t*>(&rpl[2]) = seq;
        *reinterpret_cast<uint32_t*>(&rpl[4]) = static_cast<uint32_t>(n * 2);
        *reinterpret_cast<uint32_t*>(&rpl[8]) = static_cast<uint32_t>(n);
        uint32_t* a = reinterpret_cast<uint32_t*>(&rpl[32]);
        a[0] = 0x801D; a[1] = w; a[2] = 0x801E; a[3] = h;
        send_to_client(server, client_idx, rpl.data(), rlen);
    } else if (minor == 27) {
        uint32_t pbid = *reinterpret_cast<const uint32_t*>(data + 12);
        uint32_t na = *reinterpret_cast<const uint32_t*>(data + 16);
        uint32_t pw = 1, ph = 1;
        for (uint32_t ai = 0; ai < na && 20+ai*8+4 <= static_cast<uint32_t>(len); ai++) {
            uint32_t at = *reinterpret_cast<const uint32_t*>(data + 20 + ai*8);
            uint32_t av = *reinterpret_cast<const uint32_t*>(data + 24 + ai*8);
            if (at == 0x801D) pw = av;
            if (at == 0x801E) ph = av;
        }
        server->glx_pbuffer_id = pbid;
        server->glx_pbuffer_width = pw;
        server->glx_pbuffer_height = ph;
        X11Window fpw;
        fpw.id = pbid; fpw.parent_id = server->root_window_id;
        fpw.width = static_cast<uint16_t>(pw); fpw.height = static_cast<uint16_t>(ph);
        fpw.override_redirect = 1; fpw.owner_client = static_cast<uint32_t>(client_idx);
        server->windows.push_back(std::move(fpw));
    } else if (minor == 17) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        send_to_client(server, client_idx, reply, 32);
    }
    /* All other GLX minors are void — no reply needed */
}

/* ========================================================================== */
/* RENDER, Composite, XFIXES, SHAPE, XKB, SHM, XTEST extension handlers       */
/* ========================================================================== */

static void handle_render(X11Server* server, int client_idx, uint8_t minor,
                          const uint8_t* data, int len, uint16_t seq) {
    if (minor == 0) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 8) = 0;
        *reinterpret_cast<uint32_t*>(reply + 12) = 11;
        send_to_client(server, client_idx, reply, 32);
    } else if (minor == 1) {
        /* Both visuals must appear here. 0x22 (depth 32, ARGB) is the ROOT
         * visual, so toolkits routinely ask for its picture format — and
         * XRenderFindVisualFormat returns NULL for a visual we omit, after
         * which XRenderCreatePicture dereferences it and the CLIENT segfaults
         * inside libXrender with no protocol error to show for it. Listing
         * only 0x21 crashed every Java/Swing app at startup. */
        int num_formats = 2;
        int num_depths = 2;
        int num_visuals = 2;
        int format_bytes = num_formats * 28;
        int visual_bytes = num_visuals * 8;
        int depth_bytes = num_depths * 8 + visual_bytes;
        int screen_bytes = 8 + depth_bytes;
        int extra = format_bytes + screen_bytes;
        int reply_len = 32 + extra;
        std::vector<uint8_t> reply(static_cast<size_t>(reply_len), 0);
        reply[0] = 1; *reinterpret_cast<uint16_t*>(&reply[2]) = seq;
        *reinterpret_cast<uint32_t*>(&reply[4]) = static_cast<uint32_t>(extra / 4);
        *reinterpret_cast<uint32_t*>(&reply[8]) = static_cast<uint32_t>(num_formats);
        *reinterpret_cast<uint32_t*>(&reply[12]) = 1; /* screens */
        *reinterpret_cast<uint32_t*>(&reply[16]) = static_cast<uint32_t>(num_depths);
        *reinterpret_cast<uint32_t*>(&reply[20]) = static_cast<uint32_t>(num_visuals);
        int off = 32;
        /* Format 0: ARGB32 */
        *reinterpret_cast<uint32_t*>(&reply[off]) = 0x30; off += 4;
        reply[off] = 1; reply[off+1] = 32; off += 4;
        *reinterpret_cast<uint16_t*>(&reply[off]) = 16; off += 2;
        *reinterpret_cast<uint16_t*>(&reply[off]) = 0xFF; off += 2;
        *reinterpret_cast<uint16_t*>(&reply[off]) = 8; off += 2;
        *reinterpret_cast<uint16_t*>(&reply[off]) = 0xFF; off += 2;
        *reinterpret_cast<uint16_t*>(&reply[off]) = 0; off += 2;
        *reinterpret_cast<uint16_t*>(&reply[off]) = 0xFF; off += 2;
        *reinterpret_cast<uint16_t*>(&reply[off]) = 24; off += 2;
        *reinterpret_cast<uint16_t*>(&reply[off]) = 0xFF; off += 2;
        *reinterpret_cast<uint32_t*>(&reply[off]) = 0; off += 4;
        /* Format 1: RGB24 */
        *reinterpret_cast<uint32_t*>(&reply[off]) = 0x31; off += 4;
        reply[off] = 1; reply[off+1] = 24; off += 4;
        *reinterpret_cast<uint16_t*>(&reply[off]) = 16; off += 2;
        *reinterpret_cast<uint16_t*>(&reply[off]) = 0xFF; off += 2;
        *reinterpret_cast<uint16_t*>(&reply[off]) = 8; off += 2;
        *reinterpret_cast<uint16_t*>(&reply[off]) = 0xFF; off += 2;
        *reinterpret_cast<uint16_t*>(&reply[off]) = 0; off += 2;
        *reinterpret_cast<uint16_t*>(&reply[off]) = 0xFF; off += 2;
        *reinterpret_cast<uint16_t*>(&reply[off]) = 0; off += 2;
        *reinterpret_cast<uint16_t*>(&reply[off]) = 0; off += 2;
        *reinterpret_cast<uint32_t*>(&reply[off]) = 0; off += 4;
        /* Screen 0: depth 24 -> visual 0x21 (RGB24), depth 32 -> visual 0x22 (ARGB32) */
        *reinterpret_cast<uint32_t*>(&reply[off]) = static_cast<uint32_t>(num_depths); off += 4;
        *reinterpret_cast<uint32_t*>(&reply[off]) = 0x31; off += 4; /* fallback format */
        struct { uint8_t depth; uint32_t visual; uint32_t format; } screen_depths[] = {
            { 24, 0x21, 0x31 },
            { 32, 0x22, 0x30 },
        };
        for (const auto& sd : screen_depths) {
            reply[off] = sd.depth; reply[off + 1] = 0;
            *reinterpret_cast<uint16_t*>(&reply[off + 2]) = 1; /* visuals at this depth */
            off += 8;
            *reinterpret_cast<uint32_t*>(&reply[off]) = sd.visual; off += 4;
            *reinterpret_cast<uint32_t*>(&reply[off]) = sd.format; off += 4;
        }
        send_to_client(server, client_idx, reply.data(), reply_len);
    } else if (minor == 29) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        send_to_client(server, client_idx, reply, 32);
    } else {
        fprintf(stderr, "[X11Server] RENDER minor=%d (stub)\n", minor);
    }
}

static void handle_composite(X11Server* server, int client_idx, uint8_t minor,
                             const uint8_t* data, int len, uint16_t seq) {
    fprintf(stderr, "[X11Server] Composite minor=%d\n", minor);
    if (minor == 0) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 8) = 0;
        *reinterpret_cast<uint32_t*>(reply + 12) = 4;
        send_to_client(server, client_idx, reply, 32);
    } else if (minor == 2) {
        /* NameWindowPixmap: window(4)@4 pixmap(4)@8 — give the window's
         * backing store a pixmap id. GL clients (WeChat's Qt) name it and
         * then ask DRI3 BuffersFromPixmap for its backing dmabuf, which we
         * allocate lazily there. Without this entry that lookup fails and
         * the client renders into nothing (invisible window). */
        uint32_t win_id = *reinterpret_cast<const uint32_t*>(data + 4);
        uint32_t pixmap_id = *reinterpret_cast<const uint32_t*>(data + 8);
        X11Window* win = find_window(server, win_id);
        fprintf(stderr, "[X11Server] NameWindowPixmap: win=0x%x pixmap=0x%x (%ux%u)\n",
                win_id, pixmap_id, win ? win->width : 0, win ? win->height : 0);
        if (win) {
            X11Pixmap* ex = find_pixmap(server, pixmap_id);
            if (!ex) {
                X11Pixmap px;
                px.id = pixmap_id;
                px.width = win->width; px.height = win->height;
                px.dma_fd = -1; px.fence_fd = -1;
                px.window_id = win_id;
                server->pixmaps.push_back(std::move(px));
            } else {
                ex->window_id = win_id;
            }
        }
    } else if (minor >= 1 && minor <= 6) {
        /* void */
    } else if (minor == 7) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 8) = server->root_window_id;
        send_to_client(server, client_idx, reply, 32);
    }
}

static void handle_xfixes(X11Server* server, int client_idx, uint8_t minor,
                          const uint8_t* data, int len, uint16_t seq) {
    fprintf(stderr, "[X11Server] XFIXES minor=%d\n", minor);
    if (minor == 0) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 8) = 5;
        *reinterpret_cast<uint32_t*>(reply + 12) = 0;
        send_to_client(server, client_idx, reply, 32);
    } else if (minor == 2 || minor == 3 || minor == 5 || minor == 6 ||
               minor == 10 || minor == 14 || minor == 15 ||
               minor == 29 || minor == 30 || minor == 31) {
        /* void */
    } else if (minor == 4) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint16_t*>(reply + 12) = 1;
        *reinterpret_cast<uint16_t*>(reply + 14) = 1;
        send_to_client(server, client_idx, reply, 32);
    } else if (minor == 7) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        send_to_client(server, client_idx, reply, 32);
    } else {
        fprintf(stderr, "[X11Server] XFIXES minor=%d (stub)\n", minor);
    }
}

static void handle_shape(X11Server* server, int client_idx, uint8_t minor,
                         const uint8_t* data, int len, uint16_t seq) {
    if (minor == 0) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint16_t*>(reply + 8) = 1;
        *reinterpret_cast<uint16_t*>(reply + 10) = 1;
        send_to_client(server, client_idx, reply, 32);
    } else if (minor >= 1 && minor <= 3) {
        /* void */
    } else if (minor == 4) {
        /* void */
    } else if (minor == 5) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        send_to_client(server, client_idx, reply, 32);
    } else if (minor == 6) {
        /* void */
    } else if (minor == 7 || minor == 8) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        send_to_client(server, client_idx, reply, 32);
    }
}

static void handle_shm(X11Server* server, int client_idx, uint8_t minor,
                       const uint8_t* data, int len, uint16_t seq) {
    switch (minor) {
    case 0: {
        /* ShmQueryVersion — advertise 1.2, pixmaps supported, SysV shm. */
        uint8_t reply[32] = {};
        reply[0] = 1; reply[1] = 1;  /* shared pixmaps = true */
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint16_t*>(reply + 8) = 1;   /* major */
        *reinterpret_cast<uint16_t*>(reply + 10) = 2;  /* minor */
        reply[12] = 2;  /* uid pad / shared-pixmap format ZPixmap */
        send_to_client(server, client_idx, reply, 32);
        break;
    }
    case 1: {
        /* ShmAttach: shmseg(4) shmid(4) read-only(1). Map the client's SysV
         * shared memory so ShmGetImage can write pixels into it. */
        uint32_t shmseg = *reinterpret_cast<const uint32_t*>(data + 4);
        uint32_t shmid = *reinterpret_cast<const uint32_t*>(data + 8);
        struct shmid_ds ds;
        size_t size = 0;
        if (shmctl(static_cast<int>(shmid), IPC_STAT, &ds) == 0) {
            size = ds.shm_segsz;
        }
        /* Attach read-write: ShmGetImage writes captured pixels into it. */
        void* addr = shmat(static_cast<int>(shmid), nullptr, 0);
        if (addr == reinterpret_cast<void*>(-1)) {
            fprintf(stderr, "[X11Server] ShmAttach shmid=%u failed: %s\n",
                    shmid, strerror(errno));
            uint8_t err[32] = {};
            err[0] = 0; err[1] = 2;  /* BadValue */
            *reinterpret_cast<uint16_t*>(err + 2) = seq;
            send_to_client(server, client_idx, err, 32);
            break;
        }
        server->shm_segments[shmseg] = {addr, size};
        fprintf(stderr, "[X11Server] ShmAttach shmseg=0x%x shmid=%u size=%zu\n",
                shmseg, shmid, size);
        break;  /* ShmAttach has no reply */
    }
    case 2: {
        /* ShmDetach: shmseg(4). */
        uint32_t shmseg = *reinterpret_cast<const uint32_t*>(data + 4);
        auto it = server->shm_segments.find(shmseg);
        if (it != server->shm_segments.end()) {
            if (it->second.is_mmap) munmap(it->second.addr, it->second.size);
            else shmdt(it->second.addr);
            server->shm_segments.erase(it);
        }
        break;
    }

    case 6: {
        /* ShmAttachFd (MIT-SHM 1.2 minor SIX): shmseg(4)@4 read-only(1)@8,
         * POSIX shm fd via SCM_RIGHTS. Leaving it unhandled both breaks Qt
         * raster painting AND desyncs the pending-fd queue (the unconsumed
         * fd gets mis-taken by a later DRI3 request). */
        uint32_t shmseg = *reinterpret_cast<const uint32_t*>(data + 4);
        int fd = consume_pending_fd(&server->clients[client_idx]);
        struct stat st;
        size_t size = (fd >= 0 && fstat(fd, &st) == 0)
                          ? static_cast<size_t>(st.st_size) : 0;
        void* addr = size ? mmap(nullptr, size, PROT_READ | PROT_WRITE,
                                 MAP_SHARED, fd, 0)
                          : MAP_FAILED;
        if (fd >= 0) close(fd);
        if (addr == MAP_FAILED) {
            fprintf(stderr, "[X11Server] ShmAttachFd shmseg=0x%x failed (fd=%d size=%zu)\n",
                    shmseg, fd, size);
            uint8_t err[32] = {};
            err[0] = 0; err[1] = 2;  /* BadValue */
            *reinterpret_cast<uint16_t*>(err + 2) = seq;
            *reinterpret_cast<uint16_t*>(err + 8) = 6;
            err[10] = 135;
            send_to_client(server, client_idx, err, 32);
            break;
        }
        server->shm_segments[shmseg] = {addr, size, 1};
        fprintf(stderr, "[X11Server] ShmAttachFd shmseg=0x%x size=%zu\n", shmseg, size);
        break;  /* no reply */
    }
    case 7: {
        /* ShmCreateSegment (MIT-SHM 1.2 minor SEVEN): shmseg(4)@4 size(4)@8
         * read-only(1)@12. The SERVER creates the memory and returns an fd
         * in the reply. This was previously handled as AttachFd (consuming
         * a client fd that never existed → BadValue), which is THE reason
         * Qt's whole SHM path failed on this server: Qt 6's backingstore
         * CreateSegments its window buffer, and WeChat's WMPF browser-view
         * pipeline never starts without it (login stuck on the spinner). */
        uint32_t shmseg = *reinterpret_cast<const uint32_t*>(data + 4);
        uint32_t size = *reinterpret_cast<const uint32_t*>(data + 8);
        int fd = static_cast<int>(syscall(SYS_memfd_create, "x11-shm-seg", 0));
        void* addr = MAP_FAILED;
        if (fd >= 0 && size > 0 && ftruncate(fd, static_cast<off_t>(size)) == 0) {
            addr = mmap(nullptr, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        }
        if (addr == MAP_FAILED) {
            fprintf(stderr, "[X11Server] ShmCreateSegment shmseg=0x%x size=%u FAILED\n",
                    shmseg, size);
            if (fd >= 0) close(fd);
            uint8_t err[32] = {};
            err[0] = 0; err[1] = 11; /* BadAlloc */
            *reinterpret_cast<uint16_t*>(err + 2) = seq;
            *reinterpret_cast<uint16_t*>(err + 8) = 7;
            err[10] = 135;
            send_to_client(server, client_idx, err, 32);
            break;
        }
        server->shm_segments[shmseg] = {addr, static_cast<size_t>(size), 1};
        fprintf(stderr, "[X11Server] ShmCreateSegment shmseg=0x%x size=%u fd=%d\n",
                shmseg, size, fd);
        /* Reply carries the fd via SCM_RIGHTS; nfd=1 in byte 1. */
        uint8_t rpl[32] = {};
        rpl[0] = 1; rpl[1] = 1;
        *reinterpret_cast<uint16_t*>(rpl + 2) = seq;
        {
            struct iovec iov;
            iov.iov_base = rpl; iov.iov_len = 32;
            uint8_t cmsg_buf[CMSG_SPACE(sizeof(int))];
            struct msghdr msg;
            std::memset(&msg, 0, sizeof(msg));
            msg.msg_iov = &iov; msg.msg_iovlen = 1;
            msg.msg_control = cmsg_buf; msg.msg_controllen = sizeof(cmsg_buf);
            struct cmsghdr* cm = CMSG_FIRSTHDR(&msg);
            cm->cmsg_level = SOL_SOCKET; cm->cmsg_type = SCM_RIGHTS;
            cm->cmsg_len = CMSG_LEN(sizeof(int));
            std::memcpy(CMSG_DATA(cm), &fd, sizeof(int));
            sendmsg(server->clients[client_idx].fd, &msg, 0);
        }
        close(fd);
        break;
    }
    case 3: {
        /* ShmPutImage — how a raster toolkit paints when MIT-SHM is available,
         * which is the path Qt and GTK take by preference. Pixels are already
         * in the shared segment; we blit the requested sub-rect into the
         * window shadow.
         *
         *   drawable(4)@4 gc(4)@8 total-w(2)@12 total-h(2)@14 src-x(2)@16
         *   src-y(2)@18 src-w(2)@20 src-h(2)@22 dst-x(2)@24 dst-y(2)@26
         *   depth(1)@28 format(1)@29 send-event(1)@30 pad(1)@31
         *   shmseg(4)@32 offset(4)@36
         */
        uint32_t drawable  = *reinterpret_cast<const uint32_t*>(data + 4);
        uint16_t total_w   = *reinterpret_cast<const uint16_t*>(data + 12);
        uint16_t total_h   = *reinterpret_cast<const uint16_t*>(data + 14);
        uint16_t src_x     = *reinterpret_cast<const uint16_t*>(data + 16);
        uint16_t src_y     = *reinterpret_cast<const uint16_t*>(data + 18);
        uint16_t src_w     = *reinterpret_cast<const uint16_t*>(data + 20);
        uint16_t src_h     = *reinterpret_cast<const uint16_t*>(data + 22);
        int16_t  dst_x     = *reinterpret_cast<const int16_t*>(data + 24);
        int16_t  dst_y     = *reinterpret_cast<const int16_t*>(data + 26);
        uint8_t  depth     = data[28];
        uint8_t  format    = data[29];
        uint8_t  send_event = data[30];
        uint32_t shmseg    = *reinterpret_cast<const uint32_t*>(data + 32);
        uint32_t offset    = *reinterpret_cast<const uint32_t*>(data + 36);

        auto it = server->shm_segments.find(shmseg);
        if (it == server->shm_segments.end() || format != 2 ||
            (depth != 24 && depth != 32) || src_w == 0 || src_h == 0) {
            break;
        }
        int stride = static_cast<int>(total_w) * 4;
        size_t first = static_cast<size_t>(offset) +
                       static_cast<size_t>(src_y) * stride +
                       static_cast<size_t>(src_x) * 4;
        size_t span  = static_cast<size_t>(src_h) * stride;
        if (total_h == 0 || first + span > it->second.size) break;

        int off_x = 0, off_y = 0;
        X11Window* win = shadow_target(server, drawable, &off_x, &off_y);
        if (win) {
            const uint8_t* src = static_cast<const uint8_t*>(it->second.addr) + first;
            blit_zpixmap(win, src, src_w, src_h, stride, dst_x + off_x, dst_y + off_y);
            flush_shadow(server, win);
        }

        /* When send_event is set the client is waiting on ShmCompletion before
         * it will reuse the segment — withhold it and the app paints once and
         * then freezes forever. */
        if (send_event) {
            /* ShmCompletion = MIT-SHM first_event + 0; the extension is
             * registered with first_event 64 above. Layout: type, unused,
             * sequence, drawable, minorEvent, majorEvent, pad, shmseg, offset. */
            uint8_t ev[32] = {};
            ev[0] = 64;
            *reinterpret_cast<uint16_t*>(ev + 2) = seq;
            *reinterpret_cast<uint32_t*>(ev + 4) = drawable;
            *reinterpret_cast<uint16_t*>(ev + 8) = 3;    /* minorEvent: ShmPutImage */
            ev[10] = 135;                                 /* majorEvent: MIT-SHM */
            *reinterpret_cast<uint32_t*>(ev + 12) = shmseg;
            *reinterpret_cast<uint32_t*>(ev + 16) = offset;
            send_to_client(server, client_idx, ev, 32);
        }
        break;
    }

    case 4: {
        /* ShmGetImage: drawable(4) x(2) y(2) w(2) h(2) plane-mask(4)
         * format(1) pad(3) shmseg(4) offset(4). Capture the screen rect
         * straight into the client's shared memory, reply with the size. */
        int16_t x = *reinterpret_cast<const int16_t*>(data + 8);
        int16_t y = *reinterpret_cast<const int16_t*>(data + 10);
        uint16_t w = *reinterpret_cast<const uint16_t*>(data + 12);
        uint16_t h = *reinterpret_cast<const uint16_t*>(data + 14);
        uint32_t shmseg = *reinterpret_cast<const uint32_t*>(data + 24);
        uint32_t offset = *reinterpret_cast<const uint32_t*>(data + 28);
        size_t img_bytes = static_cast<size_t>(w) * h * 4;
        auto it = server->shm_segments.find(shmseg);
        if (it == server->shm_segments.end() || w == 0 || h == 0 ||
            offset + img_bytes > it->second.size) {
            fprintf(stderr, "[X11Server] ShmGetImage bad seg/size %ux%u seg=0x%x\n",
                    w, h, shmseg);
            uint8_t err[32] = {};
            err[0] = 0; err[1] = 2;
            *reinterpret_cast<uint16_t*>(err + 2) = seq;
            send_to_client(server, client_idx, err, 32);
            break;
        }
        uint8_t* dst = static_cast<uint8_t*>(it->second.addr) + offset;
        int ok = 0;
        if (server->config.capture_screen) {
            ok = server->config.capture_screen(server->config.userdata, x, y, w, h,
                                                dst, static_cast<int>(img_bytes));
        }
        if (!ok) {
            for (size_t i = 0; i < img_bytes; i += 4) {
                dst[i] = dst[i + 1] = dst[i + 2] = 0;
                dst[i + 3] = 0xff;
            }
        }
        uint8_t reply[32] = {};
        reply[0] = 1; reply[1] = 32;  /* depth */
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 8) = 0x22;  /* visual */
        *reinterpret_cast<uint32_t*>(reply + 12) = static_cast<uint32_t>(img_bytes);
        send_to_client(server, client_idx, reply, 32);
        break;
    }
    default:
        fprintf(stderr, "[X11Server] SHM minor=%d (unhandled)\n", minor);
        break;
    }
}

static void handle_xkb(X11Server* server, int client_idx, uint8_t minor,
                       const uint8_t* data, int len, uint16_t seq) {
    fprintf(stderr, "[X11Server] XKB minor=%d\n", minor);
    if (minor == 0) {
        uint8_t reply[32] = {};
        reply[0] = 1; reply[1] = 1;
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint16_t*>(reply + 8) = 1;
        *reinterpret_cast<uint16_t*>(reply + 10) = 0;
        send_to_client(server, client_idx, reply, 32);
    } else if (minor == 8) {
        int reply_len = 40;
        uint8_t reply[40] = {};
        reply[0] = 1; reply[1] = 0;
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 4) = static_cast<uint32_t>((reply_len - 32) / 4);
        reply[10] = 8; reply[11] = 255;
        send_to_client(server, client_idx, reply, reply_len);
    } else if (minor == 4) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        send_to_client(server, client_idx, reply, 32);
    } else if (minor == 7) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        reply[8] = 8; reply[9] = 255;
        send_to_client(server, client_idx, reply, 32);
    } else if (minor == 1 || minor == 2 || minor == 3 || minor == 9 || minor == 10 || minor == 11) {
        if (minor == 5 || minor == 6) {
            uint8_t reply[32] = {};
            reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
            send_to_client(server, client_idx, reply, 32);
        }
    } else {
        fprintf(stderr, "[X11Server] XKB minor=%d (stub)\n", minor);
        if (minor == 6 || minor == 12 || minor == 13 || minor == 14) {
            uint8_t reply[32] = {};
            reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
            send_to_client(server, client_idx, reply, 32);
        }
    }
}

static void handle_xtest(X11Server* server, int client_idx, uint8_t minor,
                         const uint8_t* data, int len, uint16_t seq) {
    if (minor == 0) {
        uint8_t reply[32] = {};
        reply[0] = 1; reply[1] = 2;
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint16_t*>(reply + 8) = 2;
        send_to_client(server, client_idx, reply, 32);
    } else if (minor == 2) {
        uint8_t etype = data[4]; uint8_t edetail = data[5];
        int16_t rx = *reinterpret_cast<const int16_t*>(data + 24);
        int16_t ry = *reinterpret_cast<const int16_t*>(data + 26);
        fprintf(stderr, "[X11Server] XTEST FakeInput: type=%d detail=%d x=%d y=%d\n", etype, edetail, rx, ry);
        if (etype == 6) x11_server_pointer_motion(server, rx, ry);
        else if (etype == 4) x11_server_pointer_button(server, edetail, 1, rx, ry);
        else if (etype == 5) x11_server_pointer_button(server, edetail, 0, rx, ry);
    } else if (minor == 1) {
        uint8_t reply[32] = {};
        reply[0] = 1; reply[1] = 1;
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        send_to_client(server, client_idx, reply, 32);
    }
}

/* ========================================================================== */
/* RandR extension handler                                                     */
/* ========================================================================== */

static void handle_randr(X11Server* server, int client_idx, uint8_t minor,
                         const uint8_t* data, int len, uint16_t seq) {
    X11Client* client = &server->clients[client_idx];
    fprintf(stderr, "[X11Server] fd=%d RandR minor=%d seq=%d len=%d hex=[%02x %02x %02x %02x %02x %02x %02x %02x]\n",
            client->fd, minor, seq, len, data[0], data[1], data[2], data[3],
            len>4?data[4]:0, len>5?data[5]:0, len>6?data[6]:0, len>7?data[7]:0);

    if (minor == 0) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 8) = 1;
        *reinterpret_cast<uint32_t*>(reply + 12) = 5;
        send_to_client(server, client_idx, reply, 32);
    } else if (minor == 8 || minor == 25) {
        int sw = server->config.display_width;
        int sh = server->config.display_height;
        const char* mode_name = "default";
        int mode_name_len = static_cast<int>(strlen(mode_name));
        int mode_name_pad = (4 - (mode_name_len & 3)) & 3;
        int variable = 1*4 + 1*4 + 1*32 + mode_name_len + mode_name_pad;
        int reply_len = 32 + variable;
        std::vector<uint8_t> reply(static_cast<size_t>(reply_len), 0);
        reply[0] = 1; *reinterpret_cast<uint16_t*>(&reply[2]) = seq;
        *reinterpret_cast<uint32_t*>(&reply[4]) = static_cast<uint32_t>(variable / 4);
        *reinterpret_cast<uint32_t*>(&reply[8]) = x11_timestamp();
        *reinterpret_cast<uint32_t*>(&reply[12]) = x11_timestamp();
        *reinterpret_cast<uint16_t*>(&reply[16]) = 1;
        *reinterpret_cast<uint16_t*>(&reply[18]) = 1;
        *reinterpret_cast<uint16_t*>(&reply[20]) = 1;
        *reinterpret_cast<uint16_t*>(&reply[22]) = static_cast<uint16_t>(mode_name_len + mode_name_pad);
        int off = 32;
        *reinterpret_cast<uint32_t*>(&reply[off]) = 0x30; off += 4;
        *reinterpret_cast<uint32_t*>(&reply[off]) = 0x31; off += 4;
        uint16_t hTotal = static_cast<uint16_t>(sw + sw / 6);
        uint16_t vTotal = static_cast<uint16_t>(sh + sh / 25);
        uint32_t dot_clock = static_cast<uint32_t>(hTotal) * vTotal * 60;
        *reinterpret_cast<uint32_t*>(&reply[off]) = 0x40; off += 4;
        *reinterpret_cast<uint16_t*>(&reply[off]) = static_cast<uint16_t>(sw); off += 2;
        *reinterpret_cast<uint16_t*>(&reply[off]) = static_cast<uint16_t>(sh); off += 2;
        *reinterpret_cast<uint32_t*>(&reply[off]) = dot_clock; off += 4;
        *reinterpret_cast<uint16_t*>(&reply[off]) = static_cast<uint16_t>(sw + sw/12); off += 2;
        *reinterpret_cast<uint16_t*>(&reply[off]) = static_cast<uint16_t>(sw + sw/8); off += 2;
        *reinterpret_cast<uint16_t*>(&reply[off]) = hTotal; off += 2;
        *reinterpret_cast<uint16_t*>(&reply[off]) = 0; off += 2;
        *reinterpret_cast<uint16_t*>(&reply[off]) = static_cast<uint16_t>(sh + sh/80); off += 2;
        *reinterpret_cast<uint16_t*>(&reply[off]) = static_cast<uint16_t>(sh + sh/40); off += 2;
        *reinterpret_cast<uint16_t*>(&reply[off]) = vTotal; off += 2;
        *reinterpret_cast<uint16_t*>(&reply[off]) = static_cast<uint16_t>(mode_name_len); off += 2;
        *reinterpret_cast<uint32_t*>(&reply[off]) = 0; off += 4;
        std::memcpy(&reply[off], mode_name, static_cast<size_t>(mode_name_len));
        off += mode_name_len + mode_name_pad;
        send_to_client(server, client_idx, reply.data(), reply_len);
    } else if (minor == 9 || minor == 20) {
        int sw = server->config.display_width;
        int sh = server->config.display_height;
        if (minor == 20) {
            int variable = 1 * 4;
            int reply_len = 32 + variable;
            std::vector<uint8_t> reply(static_cast<size_t>(reply_len), 0);
            reply[0] = 1; reply[1] = 0;
            *reinterpret_cast<uint16_t*>(&reply[2]) = seq;
            *reinterpret_cast<uint32_t*>(&reply[4]) = static_cast<uint32_t>(variable / 4);
            *reinterpret_cast<uint32_t*>(&reply[8]) = x11_timestamp();
            *reinterpret_cast<uint16_t*>(&reply[16]) = static_cast<uint16_t>(sw);
            *reinterpret_cast<uint16_t*>(&reply[18]) = static_cast<uint16_t>(sh);
            *reinterpret_cast<uint32_t*>(&reply[20]) = 0x40;
            *reinterpret_cast<uint16_t*>(&reply[24]) = 1;
            *reinterpret_cast<uint16_t*>(&reply[26]) = 1;
            *reinterpret_cast<uint16_t*>(&reply[28]) = 1;
            *reinterpret_cast<uint16_t*>(&reply[30]) = 0;
            *reinterpret_cast<uint32_t*>(&reply[32]) = 0x31;
            send_to_client(server, client_idx, reply.data(), reply_len);
        } else {
            const char* name = "HDMI-1";
            int name_len = static_cast<int>(strlen(name));
            int name_pad = (4 - (name_len & 3)) & 3;
            int variable = 1*4 + 1*4 + name_len + name_pad;
            int reply_len = 36 + variable;
            std::vector<uint8_t> reply(static_cast<size_t>(reply_len), 0);
            reply[0] = 1; reply[1] = 0;
            *reinterpret_cast<uint16_t*>(&reply[2]) = seq;
            *reinterpret_cast<uint32_t*>(&reply[4]) = static_cast<uint32_t>((reply_len - 32) / 4);
            *reinterpret_cast<uint32_t*>(&reply[8]) = x11_timestamp();
            *reinterpret_cast<uint32_t*>(&reply[12]) = 0x30;
            *reinterpret_cast<uint32_t*>(&reply[16]) = static_cast<uint32_t>(sw / 4);
            *reinterpret_cast<uint32_t*>(&reply[20]) = static_cast<uint32_t>(sh / 4);
            reply[24] = 0; reply[25] = 1;
            *reinterpret_cast<uint16_t*>(&reply[26]) = 1;
            *reinterpret_cast<uint16_t*>(&reply[28]) = 1;
            *reinterpret_cast<uint16_t*>(&reply[30]) = 1;
            *reinterpret_cast<uint16_t*>(&reply[32]) = 0;
            *reinterpret_cast<uint16_t*>(&reply[34]) = static_cast<uint16_t>(name_len);
            int off = 36;
            *reinterpret_cast<uint32_t*>(&reply[off]) = 0x30; off += 4;
            *reinterpret_cast<uint32_t*>(&reply[off]) = 0x40; off += 4;
            std::memcpy(&reply[off], name, static_cast<size_t>(name_len));
            send_to_client(server, client_idx, reply.data(), reply_len);
        }
    } else if (minor == 2 || minor == 21) {
        uint8_t reply[32] = {};
        reply[0] = 1; reply[1] = 0; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 8) = x11_timestamp();
        send_to_client(server, client_idx, reply, 32);
    } else if (minor == 5) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 8) = x11_timestamp();
        send_to_client(server, client_idx, reply, 32);
    } else if (minor == 31) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 8) = 0x31;
        send_to_client(server, client_idx, reply, 32);
    } else if (minor == 6) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint16_t*>(reply + 8) = 1; *reinterpret_cast<uint16_t*>(reply + 10) = 1;
        *reinterpret_cast<uint16_t*>(reply + 12) = static_cast<uint16_t>(server->config.display_width);
        *reinterpret_cast<uint16_t*>(reply + 14) = static_cast<uint16_t>(server->config.display_height);
        send_to_client(server, client_idx, reply, 32);
    } else if (minor == 10 || minor == 15) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        send_to_client(server, client_idx, reply, 32);
    } else if (minor == 16) {
        uint8_t reply[64] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 4) = 8;
        *reinterpret_cast<uint32_t*>(reply + 8) = 0x41;
        send_to_client(server, client_idx, reply, 64);
    } else if (minor == 22) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint16_t*>(reply + 8) = 256;
        send_to_client(server, client_idx, reply, 32);
    } else if (minor == 32) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 8) = x11_timestamp();
        send_to_client(server, client_idx, reply, 32);
    } else if (minor == 4 || minor == 7 || minor == 12 || minor == 13 ||
               minor == 14 || minor == 17 || minor == 18 || minor == 19 ||
               minor == 24 || minor == 26 || minor == 30 ||
               minor == 34 || minor == 35 || minor == 38 || minor == 39 ||
               minor == 40 || minor == 43 || minor == 44) {
        /* Void */
    } else if (minor == 42) {
        fprintf(stderr, "[X11Server] RRGetMonitors handler entered, fd=%d seq=%d\n", client->fd, seq);
        int sw = server->config.display_width;
        int sh = server->config.display_height;
        uint32_t name_atom = intern_atom(server, "HDMI-1", 0);
        int mon_size = 24 + 1 * 4;
        int variable = mon_size;
        int reply_len = 32 + variable;
        std::vector<uint8_t> reply(static_cast<size_t>(reply_len), 0);
        reply[0] = 1; *reinterpret_cast<uint16_t*>(&reply[2]) = seq;
        *reinterpret_cast<uint32_t*>(&reply[4]) = static_cast<uint32_t>(variable / 4);
        *reinterpret_cast<uint32_t*>(&reply[8]) = x11_timestamp();
        *reinterpret_cast<uint32_t*>(&reply[12]) = 1;
        *reinterpret_cast<uint32_t*>(&reply[16]) = 1;
        int off = 32;
        *reinterpret_cast<uint32_t*>(&reply[off]) = name_atom; off += 4;
        reply[off++] = 1; reply[off++] = 1;
        *reinterpret_cast<uint16_t*>(&reply[off]) = 1; off += 2;
        *reinterpret_cast<int16_t*>(&reply[off]) = 0; off += 2;
        *reinterpret_cast<int16_t*>(&reply[off]) = 0; off += 2;
        *reinterpret_cast<uint16_t*>(&reply[off]) = static_cast<uint16_t>(sw); off += 2;
        *reinterpret_cast<uint16_t*>(&reply[off]) = static_cast<uint16_t>(sh); off += 2;
        *reinterpret_cast<uint32_t*>(&reply[off]) = static_cast<uint32_t>(sw / 4); off += 4;
        *reinterpret_cast<uint32_t*>(&reply[off]) = static_cast<uint32_t>(sh / 4); off += 4;
        *reinterpret_cast<uint32_t*>(&reply[off]) = 0x31; off += 4;
        send_to_client(server, client_idx, reply.data(), reply_len);
    } else {
        fprintf(stderr, "[X11Server] RandR minor=%d (stub)\n", minor);
        if (minor == 11 || minor == 23 || minor == 27 || minor == 28 ||
            minor == 29 || minor == 33 || minor == 36 || minor == 37 ||
            minor == 41 || minor == 45) {
            uint8_t reply[32] = {};
            reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
            send_to_client(server, client_idx, reply, 32);
        }
    }
}

/* ========================================================================== */
/* XI2 extension handler                                                       */
/* ========================================================================== */

static void handle_xi2(X11Server* server, int client_idx, uint8_t minor,
                       const uint8_t* data, int len, uint16_t seq) {
    fprintf(stderr, "[X11Server] XI2 minor=%d\n", minor);
    if (minor == 47) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint16_t*>(reply + 8) = 2;
        *reinterpret_cast<uint16_t*>(reply + 10) = 3;
        send_to_client(server, client_idx, reply, 32);
    } else if (minor == 48) {
        static constexpr int BTN_CLASS_SIZE = 40;
        static constexpr int VAL_CLASS_SIZE = 44;
        static constexpr int PTR_CLASSES_SIZE = BTN_CLASS_SIZE + 2 * VAL_CLASS_SIZE;
        static constexpr int PTR_NUM_CLASSES = 3;
        struct { uint16_t id; uint16_t type; uint16_t attach; const char* name; int has_ptr_classes; } devs[] = {
            { 2, 1, 3, "Virtual core pointer", 1 },
            { 3, 2, 2, "Virtual core keyboard", 0 },
            { 4, 3, 2, "Virtual core XTEST pointer", 1 },
            { 5, 4, 3, "Virtual core XTEST keyboard", 0 },
        };
        int ndevs = static_cast<int>(sizeof(devs) / sizeof(devs[0]));
        int sw = server->config.display_width;
        int sh = server->config.display_height;
        int extra = 0;
        for (int d = 0; d < ndevs; d++) {
            int nlen = static_cast<int>(strlen(devs[d].name));
            int npad = (4 - (nlen & 3)) & 3;
            extra += 12 + nlen + npad;
            if (devs[d].has_ptr_classes) extra += PTR_CLASSES_SIZE;
        }
        int reply_len = 32 + extra;
        std::vector<uint8_t> reply(static_cast<size_t>(reply_len), 0);
        reply[0] = 1; *reinterpret_cast<uint16_t*>(&reply[2]) = seq;
        *reinterpret_cast<uint32_t*>(&reply[4]) = static_cast<uint32_t>(extra / 4);
        *reinterpret_cast<uint16_t*>(&reply[8]) = static_cast<uint16_t>(ndevs);
        int off = 32;
        for (int d = 0; d < ndevs; d++) {
            int nlen = static_cast<int>(strlen(devs[d].name));
            int npad = (4 - (nlen & 3)) & 3;
            int ncls = devs[d].has_ptr_classes ? PTR_NUM_CLASSES : 0;
            *reinterpret_cast<uint16_t*>(&reply[off]) = devs[d].id; off += 2;
            *reinterpret_cast<uint16_t*>(&reply[off]) = devs[d].type; off += 2;
            *reinterpret_cast<uint16_t*>(&reply[off]) = devs[d].attach; off += 2;
            *reinterpret_cast<uint16_t*>(&reply[off]) = static_cast<uint16_t>(ncls); off += 2;
            *reinterpret_cast<uint16_t*>(&reply[off]) = static_cast<uint16_t>(nlen); off += 2;
            reply[off] = 1; off += 1; off += 1;
            std::memcpy(&reply[off], devs[d].name, static_cast<size_t>(nlen));
            off += nlen + npad;
            if (devs[d].has_ptr_classes) {
                uint16_t srcid = devs[d].id;
                *reinterpret_cast<uint16_t*>(&reply[off]) = 1; off += 2;
                *reinterpret_cast<uint16_t*>(&reply[off]) = static_cast<uint16_t>(BTN_CLASS_SIZE / 4); off += 2;
                *reinterpret_cast<uint16_t*>(&reply[off]) = srcid; off += 2;
                *reinterpret_cast<uint16_t*>(&reply[off]) = 7; off += 2;
                *reinterpret_cast<uint32_t*>(&reply[off]) = 0; off += 4;
                for (int b = 0; b < 7; b++) { *reinterpret_cast<uint32_t*>(&reply[off]) = 0; off += 4; }
                /* Valuator X */
                *reinterpret_cast<uint16_t*>(&reply[off]) = 2; off += 2;
                *reinterpret_cast<uint16_t*>(&reply[off]) = static_cast<uint16_t>(VAL_CLASS_SIZE / 4); off += 2;
                *reinterpret_cast<uint16_t*>(&reply[off]) = srcid; off += 2;
                *reinterpret_cast<uint16_t*>(&reply[off]) = 0; off += 2;
                *reinterpret_cast<uint32_t*>(&reply[off]) = 0; off += 4;
                *reinterpret_cast<uint32_t*>(&reply[off]) = 0; off += 4;
                *reinterpret_cast<uint32_t*>(&reply[off]) = 0; off += 4;
                *reinterpret_cast<uint32_t*>(&reply[off]) = static_cast<uint32_t>(sw); off += 4;
                *reinterpret_cast<uint32_t*>(&reply[off]) = 0; off += 4;
                *reinterpret_cast<uint32_t*>(&reply[off]) = 0; off += 4;
                *reinterpret_cast<uint32_t*>(&reply[off]) = 0; off += 4;
                *reinterpret_cast<uint32_t*>(&reply[off]) = 1000; off += 4;
                reply[off] = 0; off += 1; off += 3;
                /* Valuator Y */
                *reinterpret_cast<uint16_t*>(&reply[off]) = 2; off += 2;
                *reinterpret_cast<uint16_t*>(&reply[off]) = static_cast<uint16_t>(VAL_CLASS_SIZE / 4); off += 2;
                *reinterpret_cast<uint16_t*>(&reply[off]) = srcid; off += 2;
                *reinterpret_cast<uint16_t*>(&reply[off]) = 1; off += 2;
                *reinterpret_cast<uint32_t*>(&reply[off]) = 0; off += 4;
                *reinterpret_cast<uint32_t*>(&reply[off]) = 0; off += 4;
                *reinterpret_cast<uint32_t*>(&reply[off]) = 0; off += 4;
                *reinterpret_cast<uint32_t*>(&reply[off]) = static_cast<uint32_t>(sh); off += 4;
                *reinterpret_cast<uint32_t*>(&reply[off]) = 0; off += 4;
                *reinterpret_cast<uint32_t*>(&reply[off]) = 0; off += 4;
                *reinterpret_cast<uint32_t*>(&reply[off]) = 0; off += 4;
                *reinterpret_cast<uint32_t*>(&reply[off]) = 1000; off += 4;
                reply[off] = 0; off += 1; off += 3;
            }
        }
        send_to_client(server, client_idx, reply.data(), reply_len);
    } else if (minor == 56) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        send_to_client(server, client_idx, reply, 32);
    } else if (minor == 45) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        reply[8] = 1; *reinterpret_cast<uint16_t*>(reply + 10) = 2;
        send_to_client(server, client_idx, reply, 32);
    } else if (minor == 1) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint16_t*>(reply + 8) = 2;
        *reinterpret_cast<uint16_t*>(reply + 10) = 0;
        reply[12] = 1;
        send_to_client(server, client_idx, reply, 32);
    } else if (minor == 46) {
        uint32_t xi_win = *reinterpret_cast<const uint32_t*>(data + 4);
        uint16_t num_masks = *reinterpret_cast<const uint16_t*>(data + 8);
        X11Window* xw = find_window(server, xi_win);
        if (xw) {
            int off = 12;
            for (int m = 0; m < num_masks && off + 4 <= len; m++) {
                uint16_t deviceid = *reinterpret_cast<const uint16_t*>(data + off);
                uint16_t mask_len = *reinterpret_cast<const uint16_t*>(data + off + 2);
                uint32_t mask = 0;
                if (mask_len >= 1 && off + 4 + 4 <= len)
                    mask = *reinterpret_cast<const uint32_t*>(data + off + 4);
                off += 4 + mask_len * 4;
                fprintf(stderr, "[X11Server] XISelectEvents: win=0x%x deviceid=%d mask=0x%x "
                        "(motion=%d btnpress=%d btnrel=%d enter=%d leave=%d) client=%d\n",
                        xi_win, deviceid, mask,
                        !!(mask & (1u << 6)), !!(mask & (1u << 4)),
                        !!(mask & (1u << 5)), !!(mask & (1u << 7)),
                        !!(mask & (1u << 8)), client_idx);
                /* Match by (client, deviceid) — not just client! */
                int slot = -1;
                for (int s = 0; s < static_cast<int>(xw->xi2_subs.size()); s++) {
                    if (xw->xi2_subs[static_cast<size_t>(s)].client == client_idx &&
                        xw->xi2_subs[static_cast<size_t>(s)].deviceid == deviceid) { slot = s; break; }
                }
                if (slot < 0) {
                    XI2Sub sub; sub.client = client_idx; sub.deviceid = deviceid; sub.event_mask = mask;
                    xw->xi2_subs.push_back(sub);
                } else {
                    xw->xi2_subs[static_cast<size_t>(slot)].event_mask = mask;
                }
            }
        }
    } else if (minor == 2) {
        /* XI1 ListInputDevices. Java's AWT calls this during toolkit init
         * (XToolkit.getNumberOfButtonsImpl) and BLOCKS on the reply, so
         * treating it as void deadlocked every Swing app before it mapped a
         * single window — that alone kept IntelliJ off this server.
         *
         * Same devices as XIQueryDevice above, in XI1's layout: header, then
         * ndevices xDeviceInfo, then every device's class blocks in device
         * order, then every device's name as a Pascal string. XI2's device
         * types map onto XI1's `use`: master pointer -> IsXPointer, master
         * keyboard -> IsXKeyboard, and the XTEST slaves -> the IsXExtension*
         * pair. Java scans specifically for IsXExtensionPointer to read the
         * button count, so the slave pointer has to carry a ButtonClass. */
        static constexpr int KEY_CLASS_SIZE = 8;
        static constexpr int BTN_CLASS_SIZE = 4;
        static constexpr int AXIS_SIZE = 12;
        static constexpr int NUM_AXES = 2;
        static constexpr int VAL_CLASS_SIZE = 8 + NUM_AXES * AXIS_SIZE;
        struct { uint8_t id; uint8_t use; const char* name; int is_ptr; } devs[] = {
            { 2, 0, "Virtual core pointer", 1 },        /* IsXPointer           */
            { 3, 1, "Virtual core keyboard", 0 },       /* IsXKeyboard          */
            { 4, 4, "Virtual core XTEST pointer", 1 },  /* IsXExtensionPointer  */
            { 5, 3, "Virtual core XTEST keyboard", 0 }, /* IsXExtensionKeyboard */
        };
        int ndevs = static_cast<int>(sizeof(devs) / sizeof(devs[0]));
        int extra = ndevs * 8;
        for (int d = 0; d < ndevs; d++) {
            extra += devs[d].is_ptr ? (BTN_CLASS_SIZE + VAL_CLASS_SIZE) : KEY_CLASS_SIZE;
            extra += 1 + static_cast<int>(strlen(devs[d].name));
        }
        extra += (4 - (extra & 3)) & 3;
        std::vector<uint8_t> reply(static_cast<size_t>(32 + extra), 0);
        reply[0] = 1;
        reply[1] = 2; /* X_ListInputDevices */
        *reinterpret_cast<uint16_t*>(&reply[2]) = seq;
        *reinterpret_cast<uint32_t*>(&reply[4]) = static_cast<uint32_t>(extra / 4);
        reply[8] = static_cast<uint8_t>(ndevs);

        int off = 32;
        for (int d = 0; d < ndevs; d++) {
            off += 4; /* type atom — None, clients key off `use` */
            reply[off++] = devs[d].id;
            reply[off++] = devs[d].is_ptr ? 2 : 1; /* num_classes */
            reply[off++] = devs[d].use;
            reply[off++] = 0; /* attached */
        }
        for (int d = 0; d < ndevs; d++) {
            if (devs[d].is_ptr) {
                reply[off++] = 1; /* ButtonClass */
                reply[off++] = BTN_CLASS_SIZE;
                *reinterpret_cast<uint16_t*>(&reply[off]) = 7; off += 2;

                reply[off++] = 2; /* ValuatorClass */
                reply[off++] = VAL_CLASS_SIZE;
                reply[off++] = NUM_AXES;
                reply[off++] = 0; /* Absolute */
                off += 4;         /* motion_buffer_size */
                int axis_max[NUM_AXES] = { server->config.display_width,
                                           server->config.display_height };
                for (int a = 0; a < NUM_AXES; a++) {
                    *reinterpret_cast<uint32_t*>(&reply[off]) = 1; off += 4; /* resolution */
                    *reinterpret_cast<int32_t*>(&reply[off]) = 0; off += 4;  /* min_value  */
                    *reinterpret_cast<int32_t*>(&reply[off]) = axis_max[a]; off += 4;
                }
            } else {
                reply[off++] = 0; /* KeyClass */
                reply[off++] = KEY_CLASS_SIZE;
                reply[off++] = 8;   /* min_keycode */
                reply[off++] = 255; /* max_keycode */
                *reinterpret_cast<uint16_t*>(&reply[off]) = 248; off += 2; /* num_keys */
                off += 2; /* pad */
            }
        }
        for (int d = 0; d < ndevs; d++) {
            int nlen = static_cast<int>(strlen(devs[d].name));
            reply[off++] = static_cast<uint8_t>(nlen);
            memcpy(&reply[off], devs[d].name, static_cast<size_t>(nlen));
            off += nlen;
        }
        send_to_client(server, client_idx, reply.data(), 32 + extra);
    } else if (minor == 3 || minor == 4 || minor == 41 || minor == 42 ||
               minor == 44 || minor == 49 || minor == 52 || minor == 53 ||
               minor == 55 || minor == 57 || minor == 58) {
        /* void */
    } else if (minor == 51) {
        /* XIQueryPointer reply — uses FP1616 for coordinates (4 bytes each, not FP3232) */
        /* Layout after 32-byte header:
         *   32:    same_screen (1) + pad (1) + buttons_len (2)
         *   36-51: mods (base, latched, locked, effective — 4 bytes each)
         *   52-55: group (base, latched, locked, effective — 1 byte each)
         *   56+:   button_mask (buttons_len * 4 bytes)
         * Header contains: root, child, root_x, root_y, win_x, win_y (all at fixed offsets)
         * With buttons_len=1: extra = 24 + 4 = 28 bytes, length = 7 */
        static constexpr int REPLY_LEN = 32 + 28;
        uint8_t reply[REPLY_LEN] = {};
        reply[0] = 1; /* reply type */
        reply[1] = 0; /* pad */
        *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 4) = (REPLY_LEN - 32) / 4; /* length = 7 */
        *reinterpret_cast<uint32_t*>(reply + 8) = server->root_window_id;
        *reinterpret_cast<uint32_t*>(reply + 12) = server->focus_window_id; /* child */

        /* Coordinates as FP1616 (integer << 16) */
        *reinterpret_cast<int32_t*>(reply + 16) = static_cast<int32_t>(server->pointer_x) << 16;
        *reinterpret_cast<int32_t*>(reply + 20) = static_cast<int32_t>(server->pointer_y) << 16;

        X11Window* focus_win = find_window(server, server->focus_window_id);
        int16_t win_x = server->pointer_x;
        int16_t win_y = server->pointer_y;
        if (focus_win) {
            win_x = static_cast<int16_t>(server->pointer_x - focus_win->x);
            win_y = static_cast<int16_t>(server->pointer_y - focus_win->y);
        }
        *reinterpret_cast<int32_t*>(reply + 24) = static_cast<int32_t>(win_x) << 16;
        *reinterpret_cast<int32_t*>(reply + 28) = static_cast<int32_t>(win_y) << 16;

        /* After header (32 bytes): same_screen, pad, buttons_len */
        reply[32] = 1; /* same_screen */
        *reinterpret_cast<uint16_t*>(reply + 34) = 1; /* buttons_len = 1 */
        /* mods at 36-51: all zero (no modifiers) */
        /* group at 52-55: all zero */
        /* button_mask at 56-59 */
        uint16_t bs = server->button_state;
        if (bs & 0x100) reply[56] |= 0x01; /* btn1 */
        if (bs & 0x200) reply[56] |= 0x02; /* btn2 */
        if (bs & 0x400) reply[56] |= 0x04; /* btn3 */

        fprintf(stderr, "[X11Server] XIQueryPointer reply: root=0x%x ptr=(%d,%d) win=(%d,%d) btn=0x%x len=%d\n",
                server->root_window_id, server->pointer_x, server->pointer_y, win_x, win_y, bs, REPLY_LEN);
        send_to_client(server, client_idx, reply, REPLY_LEN);
    } else if (minor == 54) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint16_t*>(reply + 8) = 0;
        send_to_client(server, client_idx, reply, 32);
    } else if (minor == 40) {
        uint8_t reply[56] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 4) = 6;
        *reinterpret_cast<uint32_t*>(reply + 8) = server->root_window_id;
        reply[12] = 1;
        send_to_client(server, client_idx, reply, 56);
    } else if (minor == 50) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 8) = server->focus_window_id ?
            server->focus_window_id : server->root_window_id;
        send_to_client(server, client_idx, reply, 32);
    } else if (minor == 60 || minor == 59) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        send_to_client(server, client_idx, reply, 32);
    } else {
        fprintf(stderr, "[X11Server] XI2 minor=%d UNHANDLED len=%d\n", minor, len);
    }
}

/* ========================================================================== */
/* SYNC extension handler                                                      */
/* ========================================================================== */

static void handle_sync(X11Server* server, int client_idx, uint8_t minor,
                        const uint8_t* data, int len, uint16_t seq) {
    fprintf(stderr, "[X11Server] SYNC minor=%d\n", minor);
    if (minor == 0) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        reply[8] = 3; reply[9] = 1;
        send_to_client(server, client_idx, reply, 32);
    } else if (minor == 1) {
        const char* cname = "SERVERTIME";
        int nlen = static_cast<int>(strlen(cname));
        int npad = (4 - (nlen & 3)) & 3;
        int info_size = 2 + 2 + 4 + 4 + 4 + nlen + npad;
        int reply_len = 32 + info_size;
        std::vector<uint8_t> reply(static_cast<size_t>(reply_len), 0);
        reply[0] = 1; *reinterpret_cast<uint16_t*>(&reply[2]) = seq;
        *reinterpret_cast<uint32_t*>(&reply[4]) = static_cast<uint32_t>(info_size / 4);
        *reinterpret_cast<uint32_t*>(&reply[8]) = 1;
        int off = 32;
        *reinterpret_cast<uint32_t*>(&reply[off]) = 0x50; off += 4;
        *reinterpret_cast<uint32_t*>(&reply[off]) = 1; off += 4;
        *reinterpret_cast<uint32_t*>(&reply[off]) = 0; off += 4;
        *reinterpret_cast<uint16_t*>(&reply[off]) = static_cast<uint16_t>(nlen); off += 2;
        std::memcpy(&reply[off], cname, static_cast<size_t>(nlen));
        send_to_client(server, client_idx, reply.data(), reply_len);
    } else if (minor == 2 || minor == 4 || minor == 6 || minor == 7 ||
               minor == 8 || minor == 9 || minor == 11) {
        if (minor == 4) server->sync_waiting = 0;
        /* void */
    } else if (minor == 3) {
        server->sync_waiting = 0;
        pthread_mutex_lock(&server->resize_lock);
        int has_pending = server->resize_pending;
        uint32_t pw = server->resize_target_w;
        uint32_t ph = server->resize_target_h;
        uint32_t pwid = server->resize_target_window;
        if (has_pending) {
            server->resize_pending = 0;
            server->resize_timer_armed = 0;
            if (server->resize_timer_fd >= 0) {
                struct itimerspec ts = {};
                timerfd_settime(server->resize_timer_fd, 0, &ts, nullptr);
            }
        }
        pthread_mutex_unlock(&server->resize_lock);
        if (has_pending) {
            X11Window* rwin = find_window(server, pwid);
            if (rwin) {
                rwin->width = static_cast<uint16_t>(pw);
                rwin->height = static_cast<uint16_t>(ph);
                send_resize_events(server, rwin, static_cast<uint16_t>(pw), static_cast<uint16_t>(ph));
            }
        }
    } else if (minor == 5) {
        uint8_t reply[32] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        send_to_client(server, client_idx, reply, 32);
    } else if (minor == 10) {
        uint8_t reply[40] = {};
        reply[0] = 1; *reinterpret_cast<uint16_t*>(reply + 2) = seq;
        *reinterpret_cast<uint32_t*>(reply + 4) = 2;
        send_to_client(server, client_idx, reply, 40);
    } else if (minor == 14) {
        uint32_t fence_xid = *reinterpret_cast<const uint32_t*>(data + 8);
        int initially = data[12];
        X11Fence nf;
        nf.xid = fence_xid; nf.triggered = initially ? 1 : 0;
        server->fences.push_back(std::move(nf));
    } else if (minor == 15) {
        uint32_t fence_xid = *reinterpret_cast<const uint32_t*>(data + 4);
        for (auto& f : server->fences) {
            if (f.xid == fence_xid) {
                f.triggered = 1;
                if (f.fd >= 0 && f.shm_fence) xshmfence_trigger(f.shm_fence);
                break;
            }
        }
    } else if (minor == 16) {
        uint32_t fence_xid = *reinterpret_cast<const uint32_t*>(data + 4);
        for (auto& f : server->fences) {
            if (f.xid == fence_xid) {
                f.triggered = 0;
                if (f.shm_fence) {
                    xshmfence_reset(f.shm_fence);
                    xshmfence_trigger(f.shm_fence);
                }
                break;
            }
        }
    } else if (minor == 17) {
        uint32_t fence_xid = *reinterpret_cast<const uint32_t*>(data + 4);
        for (auto it = server->fences.begin(); it != server->fences.end(); ++it) {
            if (it->xid == fence_xid) {
                server->fences.erase(it); /* destructor handles cleanup */
                break;
            }
        }
    } else {
        fprintf(stderr, "[X11Server] SYNC minor=%d (stub)\n", minor);
    }
}

/* ========================================================================== */
/* Input forwarding & public API                                               */
/* ========================================================================== */

extern "C" {

int x11_server_has_clients(X11Server* server) {
    if (!server) return 0;
    for (int i = 0; i < server->client_count; i++) {
        if (server->clients[i].fd >= 0) return 1;
    }
    return 0;
}

void x11_server_set_epoll_fd(X11Server* server, int epoll_fd) {
    if (server) server->epoll_fd = epoll_fd;
}

void x11_server_set_client_connect_callback(X11Server* server,
                                             X11ClientConnectCallback callback,
                                             void* userdata) {
    if (server) {
        server->on_client_connect = callback;
        server->on_client_connect_userdata = userdata;
    }
}

} /* extern "C" */

static uint32_t x11_timestamp(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return static_cast<uint32_t>(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

extern "C" {

void x11_server_set_focus(X11Server* server, uint32_t window_id) {
    if (!server) return;
    uint32_t old_focus = server->focus_window_id;
    if (old_focus == window_id) return;
    uint32_t timestamp = x11_timestamp();
    (void)timestamp;

    if (old_focus != 0 && server->focus_client_idx >= 0) {
        uint16_t fseq = server->clients[server->focus_client_idx].sequence;
        uint8_t event[32] = {};
        event[0] = X11_FOCUS_OUT_EVENT; event[1] = 0;
        *reinterpret_cast<uint16_t*>(event + 2) = fseq;
        *reinterpret_cast<uint32_t*>(event + 4) = old_focus;
        event[8] = 0;
        send_to_client(server, server->focus_client_idx, event, 32);
    }

    server->focus_window_id = window_id;
    server->focus_client_idx = -1;

    if (window_id != 0) {
        X11Window* win = find_window(server, window_id);
        if (win) {
            server->focus_client_idx = static_cast<int>(win->owner_client);
            uint16_t fseq = (static_cast<int>(win->owner_client) >= 0 &&
                             static_cast<int>(win->owner_client) < server->client_count)
                ? server->clients[win->owner_client].sequence : 0;
            uint8_t event[32] = {};
            event[0] = X11_FOCUS_IN_EVENT; event[1] = 0;
            *reinterpret_cast<uint16_t*>(event + 2) = fseq;
            *reinterpret_cast<uint32_t*>(event + 4) = window_id;
            event[8] = 0;
            send_to_client(server, static_cast<int>(win->owner_client), event, 32);
            send_xi2_crossing_event(server, win, 9, 0, 0);
        }
    }
}

} /* extern "C" */

static void send_xi2_crossing_event(X11Server* server, X11Window* win,
                                     uint16_t evtype, int x, int y) {
    int ci = static_cast<int>(win->owner_client);
    if (ci < 0 || ci >= server->client_count || server->clients[ci].fd < 0)
        return;
    uint8_t ev[72];
    std::memset(ev, 0, sizeof(ev));
    ev[0] = 35; ev[1] = 131;
    *reinterpret_cast<uint16_t*>(ev + 2) = server->clients[ci].sequence;
    *reinterpret_cast<uint32_t*>(ev + 4) = 10;
    *reinterpret_cast<uint16_t*>(ev + 8) = evtype;
    *reinterpret_cast<uint16_t*>(ev + 10) = 2;
    *reinterpret_cast<uint32_t*>(ev + 12) = x11_timestamp();
    *reinterpret_cast<uint16_t*>(ev + 16) = 2;
    ev[18] = 0; ev[19] = 3;
    *reinterpret_cast<uint32_t*>(ev + 20) = server->root_window_id;
    *reinterpret_cast<uint32_t*>(ev + 24) = win->id;
    *reinterpret_cast<int32_t*>(ev + 32) = static_cast<int32_t>((win->x + x) << 16);
    *reinterpret_cast<int32_t*>(ev + 36) = static_cast<int32_t>((win->y + y) << 16);
    *reinterpret_cast<int32_t*>(ev + 40) = static_cast<int32_t>(x << 16);
    *reinterpret_cast<int32_t*>(ev + 44) = static_cast<int32_t>(y << 16);
    ev[48] = 1; ev[49] = 1;
    send_to_client(server, ci, ev, 72);
}

/* Helper to fill an 84-byte XI2 DeviceEvent and send it */
static void fill_and_send_xi2_device_event(X11Server* server, int ci,
        uint16_t evtype, uint32_t detail,
        uint32_t event_win, uint32_t child_win,
        int x, int y, int root_x, int root_y, uint16_t btn_state) {
    uint8_t ev[84];
    std::memset(ev, 0, sizeof(ev));
    ev[0] = 35; ev[1] = 131;
    *reinterpret_cast<uint16_t*>(ev + 2) = server->clients[ci].sequence;
    *reinterpret_cast<uint32_t*>(ev + 4) = (84 - 32) / 4;
    *reinterpret_cast<uint16_t*>(ev + 8) = evtype;
    *reinterpret_cast<uint16_t*>(ev + 10) = 2; /* deviceid = virtual core pointer */
    *reinterpret_cast<uint32_t*>(ev + 12) = x11_timestamp();
    *reinterpret_cast<uint32_t*>(ev + 16) = detail;
    *reinterpret_cast<uint32_t*>(ev + 20) = server->root_window_id;
    *reinterpret_cast<uint32_t*>(ev + 24) = event_win;
    *reinterpret_cast<uint32_t*>(ev + 28) = child_win;
    *reinterpret_cast<int32_t*>(ev + 32) = static_cast<int32_t>(root_x << 16);
    *reinterpret_cast<int32_t*>(ev + 36) = static_cast<int32_t>(root_y << 16);
    *reinterpret_cast<int32_t*>(ev + 40) = static_cast<int32_t>(x << 16);
    *reinterpret_cast<int32_t*>(ev + 44) = static_cast<int32_t>(y << 16);
    *reinterpret_cast<uint16_t*>(ev + 48) = 1; /* buttons_len = 1 (4 bytes) */
    *reinterpret_cast<uint16_t*>(ev + 52) = 2; /* sourceid = virtual core pointer */
    /* Button state in button mask at offset 80 (after mods/group fields) */
    /* X11 button mask: bit 8=btn1, bit 9=btn2, bit 10=btn3 → XI2 button mask: bit 0=btn1, etc */
    if (btn_state & 0x100) ev[80] |= 0x01; /* btn1 */
    if (btn_state & 0x200) ev[80] |= 0x02; /* btn2 */
    if (btn_state & 0x400) ev[80] |= 0x04; /* btn3 */
    /* For ButtonPress, also set the pressed button bit */
    if (evtype == 4 && detail > 0 && detail <= 32)
        ev[80 + (detail - 1) / 8] |= static_cast<uint8_t>(1 << ((detail - 1) % 8));
    send_to_client(server, ci, ev, 84);
}

/* Our pointer device is ID 2 (virtual core pointer, a master device).
 * XI2 deviceid matching: 0=XIAllDevices, 1=XIAllMasterDevices, 2=exact match */
static bool xi2_matches_device(uint16_t sub_devid) {
    return sub_devid == 0 || sub_devid == 1 || sub_devid == 2;
}

/* True when `client` selected `evtype` via XISelectEvents on this very window.
 *
 * XI2 selection takes PRECEDENCE over core delivery: a client that asked for an
 * event through XI2 must not also be sent the core event for it. Sending both
 * makes a toolkit see every click twice, and Qt's QPushButton never completes
 * its press/release pairing — dialog buttons look dead while press-only widgets
 * (links, labels) still work, which is exactly how this presented. Keyboard is
 * unaffected because Qt selects XI2 for pointer/touch only, which is why Enter
 * activated a button that a click could not. */
static bool client_selected_xi2(const X11Window* win, int client, uint16_t evtype) {
    if (client < 0) return false;
    for (const auto& s : win->xi2_subs) {
        if (s.client != client) continue;
        if (!xi2_matches_device(s.deviceid)) continue;
        if (s.event_mask & (1u << evtype)) return true;
    }
    return false;
}

static void send_xi2_device_event(X11Server* server, X11Window* win,
                                   uint16_t evtype, uint32_t detail,
                                   int x, int y, uint32_t button_state) {
    int root_x = win->x + x;
    int root_y = win->y + y;
    uint16_t bs = static_cast<uint16_t>(button_state);

    /* 1) Check subscriptions on the focused window */
    for (auto& s : win->xi2_subs) {
        int ci = s.client;
        if (ci < 0 || ci >= server->client_count || server->clients[ci].fd < 0) continue;
        if (!xi2_matches_device(s.deviceid)) continue;
        if (!(s.event_mask & (1u << evtype))) continue;
        fill_and_send_xi2_device_event(server, ci, evtype, detail,
            win->id, 0, x, y, root_x, root_y, bs);
    }

    /* 2) Also check subscriptions on the ROOT window — Chromium/Electron subscribes on root */
    X11Window* root = find_window(server, server->root_window_id);
    if (root) {
        for (auto& s : root->xi2_subs) {
            int ci = s.client;
            if (ci < 0 || ci >= server->client_count || server->clients[ci].fd < 0) continue;
            if (!xi2_matches_device(s.deviceid)) continue;
            if (!(s.event_mask & (1u << evtype))) continue;
            /* For root subscriptions: event=root, child=focused window */
            fill_and_send_xi2_device_event(server, ci, evtype, detail,
                server->root_window_id, win->id, root_x, root_y, root_x, root_y, bs);
        }
    }

    /* There is deliberately NO "send it anyway to the window owner" fallback.
     * A client that never called XISelectEvents is a core-input client and is
     * already getting the core event from the caller; synthesising an XI2 event
     * it never asked for is the same duplicate-delivery bug from the other side. */
}

static int motion_log_count = 0;

extern "C" {

void x11_server_pointer_motion(X11Server* server, int x, int y) {
    if (!server || server->focus_window_id == 0 || server->focus_client_idx < 0) {
        if (motion_log_count++ < 5)
            fprintf(stderr, "[X11Server] pointer_motion DROPPED: focus=0x%x client=%d\n",
                    server ? server->focus_window_id : 0, server ? server->focus_client_idx : -99);
        return;
    }
    X11Window* win = find_window(server, server->focus_window_id);
    if (!win || !win->mapped) return;
    if (motion_log_count++ < 10)
        fprintf(stderr, "[X11Server] pointer_motion: x=%d y=%d xi2_subs=%d\n", x, y, static_cast<int>(win->xi2_subs.size()));

    uint32_t timestamp = x11_timestamp();
    uint16_t seq = server->clients[server->focus_client_idx].sequence;
    int16_t root_x = static_cast<int16_t>(win->x + x);
    int16_t root_y = static_cast<int16_t>(win->y + y);

    /* Track pointer position for QueryPointer */
    server->pointer_x = root_x;
    server->pointer_y = root_y;

    if (!win->pointer_entered) {
        win->pointer_entered = 1;
        uint8_t enter[32] = {};
        enter[0] = 7; enter[1] = 0; /* EnterNotify, detail=Ancestor */
        *reinterpret_cast<uint16_t*>(enter + 2) = seq;
        *reinterpret_cast<uint32_t*>(enter + 4) = timestamp;
        *reinterpret_cast<uint32_t*>(enter + 8) = server->root_window_id;
        *reinterpret_cast<uint32_t*>(enter + 12) = win->id;
        /* bytes 16-19: child window = 0 (none) */
        *reinterpret_cast<int16_t*>(enter + 20) = root_x;
        *reinterpret_cast<int16_t*>(enter + 22) = root_y;
        *reinterpret_cast<int16_t*>(enter + 24) = static_cast<int16_t>(x);
        *reinterpret_cast<int16_t*>(enter + 26) = static_cast<int16_t>(y);
        *reinterpret_cast<uint16_t*>(enter + 28) = server->button_state;
        enter[30] = 1; /* mode=Normal | same_screen=1 */
        enter[31] = 1; /* focus=1 (pointer is in focus window) */
        send_to_client(server, server->focus_client_idx, enter, 32);
        send_xi2_crossing_event(server, win, 7, x, y);
    }

    uint8_t event[32] = {};
    event[0] = X11_MOTION_NOTIFY_EVENT;
    /* event[1] = detail (0 = normal motion) */
    *reinterpret_cast<uint16_t*>(event + 2) = seq;
    *reinterpret_cast<uint32_t*>(event + 4) = timestamp;
    *reinterpret_cast<uint32_t*>(event + 8) = server->root_window_id;
    *reinterpret_cast<uint32_t*>(event + 12) = win->id;
    /* bytes 16-19: child window = 0 */
    *reinterpret_cast<int16_t*>(event + 20) = root_x;
    *reinterpret_cast<int16_t*>(event + 22) = root_y;
    *reinterpret_cast<int16_t*>(event + 24) = static_cast<int16_t>(x);
    *reinterpret_cast<int16_t*>(event + 26) = static_cast<int16_t>(y);
    *reinterpret_cast<uint16_t*>(event + 28) = server->button_state | server->key_mod_state;
    event[30] = 1; /* same_screen */
    /* Core only when the client did not select XI2 motion here — see
     * client_selected_xi2(). */
    if (!client_selected_xi2(win, server->focus_client_idx, 6))
        send_to_client(server, server->focus_client_idx, event, 32);
    send_xi2_device_event(server, win, 6, 0, x, y, server->button_state);
}

/* WM_DELETE_WINDOW — the ICCCM "please close" ClientMessage, the same thing a
 * real WM sends when you click a title bar's X. Toolkits run their normal quit
 * path on it. Advisory only: a client may ignore it or put up an "unsaved
 * changes" dialog, so the caller must be prepared to escalate to a signal. */
void x11_server_close_window(X11Server* server, uint32_t window_id) {
    if (!server) return;
    X11Window* win = find_window(server, window_id);
    if (!win) return;
    int owner = static_cast<int>(win->owner_client);
    if (owner < 0 || owner >= server->client_count) return;
    if (server->clients[owner].fd < 0) return;

    uint32_t wm_protocols = 0, wm_delete = 0;
    for (auto& a : server->atoms) {
        if (a.name == "WM_PROTOCOLS") wm_protocols = a.id;
        else if (a.name == "WM_DELETE_WINDOW") wm_delete = a.id;
    }
    if (!wm_protocols || !wm_delete) return;

    uint8_t cm[32] = {};
    cm[0] = 33;  /* ClientMessage */
    cm[1] = 32;  /* format */
    *reinterpret_cast<uint16_t*>(cm + 2) = server->clients[owner].sequence;
    *reinterpret_cast<uint32_t*>(cm + 4) = win->id;
    *reinterpret_cast<uint32_t*>(cm + 8) = wm_protocols;
    *reinterpret_cast<uint32_t*>(cm + 12) = wm_delete;
    *reinterpret_cast<uint32_t*>(cm + 16) = x11_timestamp();
    send_to_client(server, owner, cm, 32);
}

/* pid of the client that owns a window, from the credentials captured when it
 * connected. 0 when the window is unknown or its client has gone. */
pid_t x11_server_window_pid(X11Server* server, uint32_t window_id) {
    if (!server) return 0;
    X11Window* win = find_window(server, window_id);
    if (!win) return 0;
    int owner = static_cast<int>(win->owner_client);
    if (owner < 0 || owner >= server->client_count) return 0;
    if (server->clients[owner].fd < 0) return 0;
    return server->clients[owner].pid;
}

void x11_server_pointer_button(X11Server* server, uint32_t button,
                                int pressed, int x, int y) {
    if (!server || server->focus_window_id == 0 || server->focus_client_idx < 0) return;
    X11Window* win = find_window(server, server->focus_window_id);
    if (!win || !win->mapped) return;
    if (pressed) x11_server_pointer_motion(server, x, y);

    /* An active grab (an open menu) takes the event, coordinates and all. */
    win = apply_pointer_grab(server, win, &x, &y);
    int target_client = static_cast<int>(win->owner_client);
    if (target_client < 0 || target_client >= server->client_count) return;
    fprintf(stderr, "[X11Server] pointer_button: btn=%d pressed=%d x=%d y=%d -> fd=%d%s\n",
            button, pressed, x, y, server->clients[target_client].fd,
            server->grab_window ? " (grabbed)" : "");

    /* Update button state mask — X11 uses bits 8+ for buttons (bit 8 = btn1, bit 9 = btn2, ...) */
    if (button >= 1 && button <= 5) {
        uint16_t bit = static_cast<uint16_t>(1u << (7 + button));
        if (pressed) server->button_state |= bit;
        else         server->button_state &= ~bit;
    }

    uint16_t seq = server->clients[target_client].sequence;
    int16_t root_x = static_cast<int16_t>(win->x + x);
    int16_t root_y = static_cast<int16_t>(win->y + y);
    server->pointer_x = root_x;
    server->pointer_y = root_y;

    uint8_t event[32] = {};
    event[0] = pressed ? X11_BUTTON_PRESS_EVENT : X11_BUTTON_RELEASE_EVENT;
    event[1] = static_cast<uint8_t>(button);
    *reinterpret_cast<uint16_t*>(event + 2) = seq;
    *reinterpret_cast<uint32_t*>(event + 4) = x11_timestamp();
    *reinterpret_cast<uint32_t*>(event + 8) = server->root_window_id;
    *reinterpret_cast<uint32_t*>(event + 12) = win->id;
    /* bytes 16-19: child window = 0 */
    *reinterpret_cast<int16_t*>(event + 20) = root_x;
    *reinterpret_cast<int16_t*>(event + 22) = root_y;
    *reinterpret_cast<int16_t*>(event + 24) = static_cast<int16_t>(x);
    *reinterpret_cast<int16_t*>(event + 26) = static_cast<int16_t>(y);
    *reinterpret_cast<uint16_t*>(event + 28) = server->button_state | server->key_mod_state;
    event[30] = 1; /* same_screen */
    uint16_t xi2_evtype = pressed ? 4 : 5;
    /* Core only when the client did not select XI2 for this button event on this
     * window. Delivering both is what made Qt dialog buttons ignore clicks. */
    if (!client_selected_xi2(win, target_client, xi2_evtype))
        send_to_client(server, target_client, event, 32);
    send_xi2_device_event(server, win, xi2_evtype, button, x, y, server->button_state);
}

void x11_server_key_event(X11Server* server, uint32_t keycode, int pressed) {
    if (!server || server->focus_window_id == 0 || server->focus_client_idx < 0) return;
    X11Window* win = find_window(server, server->focus_window_id);
    if (!win) return;
    uint8_t x11_keycode = static_cast<uint8_t>(keycode + 8);

    /* `keycode` is the evdev code. Map the modifier keys to their X11 mask bit
     * and update server state. The event carries the modifier state as it was
     * JUST BEFORE this event (X11 semantics), so snapshot before applying a
     * press but after applying a release — i.e. report the pre-event value and
     * update afterward. Caps Lock toggles its lock bit on press. */
    uint16_t mod_bit = 0;
    switch (keycode) {
        case 42: case 54: mod_bit = (1 << 0); break;  /* Shift_L / Shift_R  */
        case 29: case 97: mod_bit = (1 << 2); break;  /* Control_L / Control_R */
        case 56: case 100: mod_bit = (1 << 3); break; /* Alt_L / Alt_R (Mod1) */
        case 125: case 126: mod_bit = (1 << 6); break;/* Super_L / Super_R (Mod4) */
        default: break;
    }
    uint16_t state_before = server->key_mod_state;
    if (keycode == 58) {                    /* Caps Lock: toggle lock on press */
        if (pressed) server->key_mod_state ^= (1 << 1);
    } else if (mod_bit) {
        if (pressed) server->key_mod_state |= mod_bit;
        else         server->key_mod_state &= ~mod_bit;
    }

    uint8_t event[32] = {};
    event[0] = pressed ? X11_KEY_PRESS_EVENT : X11_KEY_RELEASE_EVENT;
    event[1] = x11_keycode;
    *reinterpret_cast<uint16_t*>(event + 2) =
        server->clients[server->focus_client_idx].sequence;
    *reinterpret_cast<uint32_t*>(event + 4) = x11_timestamp();
    *reinterpret_cast<uint32_t*>(event + 8) = server->root_window_id;
    *reinterpret_cast<uint32_t*>(event + 12) = win->id;
    *reinterpret_cast<uint16_t*>(event + 28) = state_before;  /* modifier mask */
    event[30] = 1;
    send_to_client(server, server->focus_client_idx, event, 32);
}

void x11_server_enter_notify(X11Server* server, uint32_t window_id, int x, int y) {
    if (!server) return;
    X11Window* win = find_window(server, window_id);
    if (!win || !win->mapped) return;
    int oc = static_cast<int>(win->owner_client);
    uint8_t event[32] = {};
    event[0] = X11_ENTER_NOTIFY_EVENT; event[1] = 0;
    if (oc >= 0 && oc < server->client_count)
        *reinterpret_cast<uint16_t*>(event + 2) = server->clients[oc].sequence;
    *reinterpret_cast<uint32_t*>(event + 4) = x11_timestamp();
    *reinterpret_cast<uint32_t*>(event + 8) = server->root_window_id;
    *reinterpret_cast<uint32_t*>(event + 12) = win->id;
    *reinterpret_cast<int16_t*>(event + 20) = static_cast<int16_t>(win->x + x);
    *reinterpret_cast<int16_t*>(event + 22) = static_cast<int16_t>(win->y + y);
    *reinterpret_cast<int16_t*>(event + 24) = static_cast<int16_t>(x);
    *reinterpret_cast<int16_t*>(event + 26) = static_cast<int16_t>(y);
    event[31] = 1;
    send_to_client(server, static_cast<int>(win->owner_client), event, 32);
}

void x11_server_leave_notify(X11Server* server, uint32_t window_id, int x, int y) {
    if (!server) return;
    X11Window* win = find_window(server, window_id);
    if (!win || !win->mapped) return;
    int oc = static_cast<int>(win->owner_client);
    uint8_t event[32] = {};
    event[0] = X11_LEAVE_NOTIFY_EVENT; event[1] = 0;
    if (oc >= 0 && oc < server->client_count)
        *reinterpret_cast<uint16_t*>(event + 2) = server->clients[oc].sequence;
    *reinterpret_cast<uint32_t*>(event + 4) = x11_timestamp();
    *reinterpret_cast<uint32_t*>(event + 8) = server->root_window_id;
    *reinterpret_cast<uint32_t*>(event + 12) = win->id;
    *reinterpret_cast<int16_t*>(event + 20) = static_cast<int16_t>(win->x + x);
    *reinterpret_cast<int16_t*>(event + 22) = static_cast<int16_t>(win->y + y);
    *reinterpret_cast<int16_t*>(event + 24) = static_cast<int16_t>(x);
    *reinterpret_cast<int16_t*>(event + 26) = static_cast<int16_t>(y);
    event[31] = 1;
    send_to_client(server, static_cast<int>(win->owner_client), event, 32);
}

} /* extern "C" */

static void send_resize_events(X11Server* server, X11Window* win,
                                uint16_t w, uint16_t h) {
    for (auto& px : server->pixmaps) {
        if (px.window_id != win->id) continue;
        uint32_t fxid = px.fence_xid;
        for (auto& f : server->fences) {
            if (f.xid == fxid && f.shm_fence) { xshmfence_trigger(f.shm_fence); break; }
        }
        for (auto& r : win->present_regs) {
            if (!(r.mask & 0x4)) continue;
            int pc = r.client;
            if (pc < 0 || pc >= server->client_count || server->clients[pc].fd < 0) continue;
            uint16_t pseq = server->clients[pc].sequence;
            uint8_t idle[32] = {};
            idle[0] = X11_GENERIC_EVENT; idle[1] = 148;
            *reinterpret_cast<uint16_t*>(idle + 2) = pseq;
            *reinterpret_cast<uint16_t*>(idle + 8) = PRESENT_IDLE_NOTIFY;
            *reinterpret_cast<uint32_t*>(idle + 12) = r.eid;
            *reinterpret_cast<uint32_t*>(idle + 16) = win->id;
            *reinterpret_cast<uint32_t*>(idle + 20) = px.last_serial;
            *reinterpret_cast<uint32_t*>(idle + 24) = px.id;
            *reinterpret_cast<uint32_t*>(idle + 28) = fxid;
            send_to_client(server, pc, idle, 32);
        }
    }
    uint16_t cseq = (static_cast<int>(win->owner_client) >= 0 && static_cast<int>(win->owner_client) < server->client_count)
        ? server->clients[win->owner_client].sequence : 0;

    uint32_t wm_protocols = 0, sync_request = 0;
    for (auto& a : server->atoms) {
        if (a.name == "WM_PROTOCOLS") wm_protocols = a.id;
        else if (a.name == "_NET_WM_SYNC_REQUEST") sync_request = a.id;
    }
    if (wm_protocols && sync_request) {
        server->sync_counter++;
        uint8_t cm[32] = {};
        cm[0] = 33; cm[1] = 32;
        *reinterpret_cast<uint16_t*>(cm + 2) = cseq;
        *reinterpret_cast<uint32_t*>(cm + 4) = win->id;
        *reinterpret_cast<uint32_t*>(cm + 8) = wm_protocols;
        *reinterpret_cast<uint32_t*>(cm + 12) = sync_request;
        *reinterpret_cast<uint32_t*>(cm + 16) = x11_timestamp();
        *reinterpret_cast<uint32_t*>(cm + 20) = static_cast<uint32_t>(server->sync_counter & 0xFFFFFFFF);
        *reinterpret_cast<uint32_t*>(cm + 24) = static_cast<uint32_t>(server->sync_counter >> 32);
        send_to_client(server, static_cast<int>(win->owner_client), cm, 32);
        server->sync_waiting = 1;
    }
    uint8_t cfg[32] = {};
    cfg[0] = X11_CONFIGURE_NOTIFY;
    *reinterpret_cast<uint16_t*>(cfg + 2) = cseq;
    *reinterpret_cast<uint32_t*>(cfg + 4) = win->id;
    *reinterpret_cast<uint32_t*>(cfg + 8) = win->id;
    *reinterpret_cast<int16_t*>(cfg + 16) = win->x;
    *reinterpret_cast<int16_t*>(cfg + 18) = win->y;
    *reinterpret_cast<uint16_t*>(cfg + 20) = w;
    *reinterpret_cast<uint16_t*>(cfg + 22) = h;
    *reinterpret_cast<uint16_t*>(cfg + 24) = win->border_width;
    cfg[26] = static_cast<uint8_t>(win->override_redirect);
    send_to_client(server, static_cast<int>(win->owner_client), cfg, 32);

    for (auto& r : win->present_regs) {
        if (!(r.mask & 0x1)) continue;
        int pc = r.client;
        if (pc < 0 || pc >= server->client_count || server->clients[pc].fd < 0) continue;
        uint16_t present_seq = server->clients[pc].sequence;
        uint8_t pge[32] = {};
        pge[0] = X11_GENERIC_EVENT; pge[1] = 148;
        *reinterpret_cast<uint16_t*>(pge + 2) = present_seq;
        *reinterpret_cast<uint16_t*>(pge + 8) = PRESENT_CONFIGURE_NOTIFY;
        *reinterpret_cast<uint32_t*>(pge + 12) = r.eid;
        *reinterpret_cast<uint32_t*>(pge + 16) = win->id;
        *reinterpret_cast<int16_t*>(pge + 20) = win->x;
        *reinterpret_cast<int16_t*>(pge + 22) = win->y;
        *reinterpret_cast<uint16_t*>(pge + 24) = w;
        *reinterpret_cast<uint16_t*>(pge + 26) = h;
        send_to_client(server, pc, pge, 32);
    }

    uint8_t expose[32] = {};
    expose[0] = X11_EXPOSE_EVENT;
    *reinterpret_cast<uint16_t*>(expose + 2) = cseq;
    *reinterpret_cast<uint32_t*>(expose + 4) = win->id;
    *reinterpret_cast<uint16_t*>(expose + 12) = w;
    *reinterpret_cast<uint16_t*>(expose + 14) = h;
    send_to_client(server, static_cast<int>(win->owner_client), expose, 32);
    fprintf(stderr, "[X11Server] resize %dx%d sync=%llu\n", w, h,
            static_cast<unsigned long long>(server->sync_counter));
}

extern "C" {

void x11_server_configure_window(X11Server* server, uint32_t window_id,
                                  int width, int height) {
    if (!server) return;
    X11Window* win = find_window(server, window_id);
    if (!win) return;
    win->width = static_cast<uint16_t>(width);
    win->height = static_cast<uint16_t>(height);

    /* Always send resize events immediately — sync_waiting is not used because
     * the resize timer fd is not monitored by the DRM shell's epoll loop.
     * Swift-side throttle in X11Integration.sendResize() handles rate limiting. */
    server->sync_waiting = 0;
    send_resize_events(server, win, static_cast<uint16_t>(width), static_cast<uint16_t>(height));
}

void x11_server_release_buffer(X11Server* server, uint32_t window_id) {
    if (!server) return;
    X11Window* win = find_window(server, window_id);
    if (!win || win->present_regs.empty()) return;
    for (auto& pix : server->pixmaps) {
        if (pix.window_id == window_id && pix.last_serial != 0) {
            for (auto& r : win->present_regs) {
                if (r.mask != 0 && !(r.mask & 0x4)) continue;
                uint8_t ge2[32] = {};
                ge2[0] = X11_GENERIC_EVENT; ge2[1] = 148;
                if (r.client >= 0 && r.client < server->client_count)
                    *reinterpret_cast<uint16_t*>(ge2 + 2) =
                        server->clients[r.client].sequence;
                *reinterpret_cast<uint16_t*>(ge2 + 8) = PRESENT_IDLE_NOTIFY;
                *reinterpret_cast<uint32_t*>(ge2 + 12) = r.eid;
                *reinterpret_cast<uint32_t*>(ge2 + 16) = window_id;
                *reinterpret_cast<uint32_t*>(ge2 + 20) = pix.last_serial;
                *reinterpret_cast<uint32_t*>(ge2 + 24) = pix.id;
                send_to_client(server, r.client, ge2, 32);
            }
            pix.last_serial = 0;
        }
    }
}

int x11_server_get_resize_timer_fd(X11Server* server) {
    return server ? server->resize_timer_fd : -1;
}

void x11_server_flush_resize(X11Server* server) {
    if (!server) return;
    uint64_t expirations;
    read(server->resize_timer_fd, &expirations, sizeof(expirations));
    server->sync_waiting = 0;
    pthread_mutex_lock(&server->resize_lock);
    server->resize_timer_armed = 0;
    if (!server->resize_pending) { pthread_mutex_unlock(&server->resize_lock); return; }
    uint32_t wid = server->resize_target_window;
    uint16_t w = server->resize_target_w;
    uint16_t h = server->resize_target_h;
    server->resize_pending = 0;
    pthread_mutex_unlock(&server->resize_lock);
    X11Window* win = find_window(server, wid);
    if (!win) return;
    fprintf(stderr, "[X11Server] flush_resize(fallback) %dx%d\n", w, h);
    win->width = w; win->height = h;
    send_resize_events(server, win, w, h);
}

int x11_server_get_vblank_timer_fd(X11Server* server) {
    return server ? server->vblank_timer_fd : -1;
}

void x11_server_arm_vblank_timer(X11Server* server) {
    if (!server || server->vblank_timer_fd < 0) return;
    struct itimerspec its = {};
    its.it_value.tv_nsec = 16000000;     /* 16ms initial */
    its.it_interval.tv_nsec = 16000000;  /* 16ms repeat (~60fps) */
    timerfd_settime(server->vblank_timer_fd, 0, &its, nullptr);
}

void x11_server_disarm_vblank_timer(X11Server* server) {
    if (!server || server->vblank_timer_fd < 0) return;
    struct itimerspec off = {};          /* all zero disarms a timerfd */
    timerfd_settime(server->vblank_timer_fd, 0, &off, nullptr);
}

/* The vblank timer runs only while somebody is connected.
 *
 * It exists so a DRI3 client's fences get triggered and its Present requests
 * get their IdleNotify/CompleteNotify -- real work, but only ever on behalf of
 * a client. Armed unconditionally at startup it was the desktop's single
 * largest idle cost: 62.5 wakeups a second forever, each one dispatching, and
 * each dispatch calling accept() on both listening sockets. On a Wayland-only
 * desktop nothing ever connects, so all of it was doomed -- measured at 1252
 * failed accept() calls in ten idle seconds, over half the shell's entire idle
 * CPU.
 *
 * Driven off the live client count here rather than from a connect callback on
 * the Swift side, because a count kept in two places is a count that will
 * eventually disagree with itself. */
static void x11_update_vblank_timer(X11Server* server) {
    if (!server) return;
    int live = 0;
    for (int i = 0; i < server->client_count; i++) {
        if (server->clients[i].fd >= 0) { live = 1; break; }
    }
    if (live) x11_server_arm_vblank_timer(server);
    else      x11_server_disarm_vblank_timer(server);
}

void x11_server_vblank_tick(X11Server* server) {
    if (!server) return;
    uint64_t expirations;
    read(server->vblank_timer_fd, &expirations, sizeof(expirations));

    /* Trigger ALL shm_fences — DRI3 buffers become available. */
    for (auto& f : server->fences) {
        if (f.shm_fence) xshmfence_trigger(f.shm_fence);
    }

    /* Send IdleNotify + CompleteNotify for each window's front buffer.
     * Matches real Xorg: at vblank, present_copy_region() completes,
     * present_pixmap_idle() sends IdleNotify, then CompleteNotify.
     * Without this, Chrome's DRI3 path deadlocks waiting for IdleNotify. */
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    uint64_t ust = static_cast<uint64_t>(ts.tv_sec) * 1000000 +
                   static_cast<uint64_t>(ts.tv_nsec) / 1000;
    uint64_t msc = ust / 16667;
    server->present_msc = msc;
    for (auto& win : server->windows) {
        if (win.front_pixmap == 0 || win.front_idle_sent) continue;
        win.front_idle_sent = 1;  /* send once per present, at next vblank */
        int fc = win.front_client;
        if (fc < 0 || fc >= server->client_count || server->clients[fc].fd < 0) {
            fprintf(stderr, "[X11Server] vblank_tick: win=0x%x SKIP bad client fc=%d count=%d\n",
                    win.id, fc, server->client_count);
            continue;
        }
        uint16_t eseq = server->clients[fc].sequence;
        int matched = 0;
        for (auto& r : win.present_regs) {
            if (r.client != fc) continue;
            matched = 1;
            /* IdleNotify for front buffer */
            if (r.mask & 0x4) {
                uint8_t idle[32] = {};
                idle[0] = X11_GENERIC_EVENT; idle[1] = 148;
                *reinterpret_cast<uint16_t*>(idle + 2) = eseq;
                *reinterpret_cast<uint16_t*>(idle + 8) = PRESENT_IDLE_NOTIFY;
                *reinterpret_cast<uint32_t*>(idle + 12) = r.eid;
                *reinterpret_cast<uint32_t*>(idle + 16) = win.id;
                *reinterpret_cast<uint32_t*>(idle + 20) = win.front_serial;
                *reinterpret_cast<uint32_t*>(idle + 24) = win.front_pixmap;
                *reinterpret_cast<uint32_t*>(idle + 28) = win.front_fence_xid;
                send_to_client(server, fc, idle, 32);
                fprintf(stderr, "[X11Server] vblank: IdleNotify win=0x%x serial=%u pix=0x%x -> fd=%d\n",
                        win.id, win.front_serial, win.front_pixmap, server->clients[fc].fd);
            }
            /* CompleteNotify for front buffer */
            if (r.mask & 0x2) {
                uint8_t ge[40] = {};
                ge[0] = X11_GENERIC_EVENT; ge[1] = 148;
                *reinterpret_cast<uint16_t*>(ge + 2) = eseq;
                *reinterpret_cast<uint32_t*>(ge + 4) = 2;
                *reinterpret_cast<uint16_t*>(ge + 8) = PRESENT_COMPLETE_NOTIFY;
                ge[10] = 0; ge[11] = 0;
                *reinterpret_cast<uint32_t*>(ge + 12) = r.eid;
                *reinterpret_cast<uint32_t*>(ge + 16) = win.id;
                *reinterpret_cast<uint32_t*>(ge + 20) = win.front_serial;
                *reinterpret_cast<uint64_t*>(ge + 24) = ust;
                *reinterpret_cast<uint64_t*>(ge + 32) = msc;
                send_to_client(server, fc, ge, 40);
            }
        }
        if (!matched) {
            fprintf(stderr, "[X11Server] vblank: win=0x%x NO matching reg for fc=%d (regs=%zu)\n",
                    win.id, fc, win.present_regs.size());
            for (size_t ri = 0; ri < win.present_regs.size(); ri++) {
                fprintf(stderr, "  reg[%zu]: client=%d eid=0x%x mask=0x%x\n",
                        ri, win.present_regs[ri].client, win.present_regs[ri].eid, win.present_regs[ri].mask);
            }
        }
    }

    for (int i = 0; i < server->pending_complete_count; i++) {
        uint32_t win_id = server->pending_complete[i].window;
        uint32_t serial = server->pending_complete[i].serial;
        uint32_t eid    = server->pending_complete[i].eid;
        int      client = server->pending_complete[i].client;
        uint32_t pixmap = server->pending_complete[i].pixmap;
        uint32_t fxid   = server->pending_complete[i].fence_xid;
        if (client < 0 || client >= server->client_count || server->clients[client].fd < 0) continue;
        uint16_t cseq = server->clients[client].sequence;
        {
            for (auto& f : server->fences) {
                if (f.xid == fxid && f.shm_fence) { xshmfence_trigger(f.shm_fence); break; }
            }
            uint8_t idle[32] = {};
            idle[0] = X11_GENERIC_EVENT; idle[1] = 148;
            *reinterpret_cast<uint16_t*>(idle + 2) = cseq;
            *reinterpret_cast<uint16_t*>(idle + 8) = PRESENT_IDLE_NOTIFY;
            *reinterpret_cast<uint32_t*>(idle + 12) = eid;
            *reinterpret_cast<uint32_t*>(idle + 16) = win_id;
            *reinterpret_cast<uint32_t*>(idle + 20) = serial;
            *reinterpret_cast<uint32_t*>(idle + 24) = pixmap;
            *reinterpret_cast<uint32_t*>(idle + 28) = fxid;
            send_to_client(server, client, idle, 32);
        }
        /* CompleteNotify is a 40-byte GenericEvent (length=2): kind/mode at
         * 10/11, ust at 24, msc at 32 — the old 32-byte form had length=0
         * and no msc, which libxcb misparses. */
        uint8_t ge[40] = {};
        ge[0] = X11_GENERIC_EVENT; ge[1] = 148;
        *reinterpret_cast<uint16_t*>(ge + 2) = cseq;
        *reinterpret_cast<uint32_t*>(ge + 4) = 2;
        *reinterpret_cast<uint16_t*>(ge + 8) = PRESENT_COMPLETE_NOTIFY;
        ge[10] = 0; ge[11] = 0;
        *reinterpret_cast<uint32_t*>(ge + 12) = eid;
        *reinterpret_cast<uint32_t*>(ge + 16) = win_id;
        *reinterpret_cast<uint32_t*>(ge + 20) = serial;
        *reinterpret_cast<uint64_t*>(ge + 24) = ust;
        *reinterpret_cast<uint64_t*>(ge + 32) = msc;
        send_to_client(server, client, ge, 40);
    }
    server->pending_complete_count = 0;
}

} /* extern "C" */
