// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// portal_service.c — XDG Desktop Portal service implementation
//
// Claims org.freedesktop.portal.Desktop on the session bus and implements:
//   - org.freedesktop.portal.Settings  (Read, ReadAll, SettingChanged)
//   - org.freedesktop.portal.FileChooser (OpenFile, SaveFile, SaveFiles)
//   - org.freedesktop.portal.Request   (Close + Response signal)
//
// FileChooser launches a helper process (FileExplorerApp --picker) that
// appears as a Wayland client window. Helper prints file:// URIs to stdout.

#define _GNU_SOURCE
#include "include/portal_service.h"

#include <errno.h>
#include <time.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

#include <systemd/sd-bus.h>

#define PORTAL_BUS_NAME   "org.freedesktop.portal.Desktop"
#define PORTAL_OBJ_PATH   "/org/freedesktop/portal/desktop"
#define SETTINGS_IFACE    "org.freedesktop.portal.Settings"
#define FILECHOOSER_IFACE "org.freedesktop.portal.FileChooser"
#define REQUEST_IFACE     "org.freedesktop.portal.Request"
#define SCREENCAST_IFACE  "org.freedesktop.portal.ScreenCast"
#define SESSION_IFACE     "org.freedesktop.portal.Session"

#define MAX_PENDING_REQUESTS 8

// --- Pending file chooser request ---

typedef struct {
    char handle[256];
    char sender[64];        // the caller, for the directed Response
    sd_bus_slot *slot;
    pid_t child_pid;        // helper process PID
    int stdout_fd;          // read end of helper's stdout pipe
    int active;
} PendingRequest;

// --- Internal pipe commands ---

enum {
    CMD_SETTINGS_CHANGED     = 1,
    CMD_SHUTDOWN             = 3,
    CMD_COMPLETE_REQUEST     = 4,
    CMD_SCREENCAST_COMPLETE  = 5,
};

// --- Async chooser completion (shell thread -> portal thread) ---

typedef struct {
    char handle[256];
    char **uris;       // heap array of heap strings
    int num_uris;
    uint32_t response;
} CompletionMsg;

// --- PortalService ---

struct PortalService {
    sd_bus *bus;
    pthread_t thread;
    int running;

    int pipe_fd[2];  // [0]=read, [1]=write (cross-thread signaling)

    // Settings
    uint32_t color_scheme;
    double accent_r, accent_g, accent_b;
    uint32_t contrast;
    int settings_color_scheme_changed;
    int settings_accent_color_changed;
    int settings_contrast_changed;

    // FileChooser
    PendingRequest requests[MAX_PENDING_REQUESTS];
    char *chooser_command;
    portal_launch_chooser_fn chooser_launcher;
    void *chooser_launcher_userdata;
    uint64_t request_counter;

    // Async completions queued by portal_service_complete_request (any thread),
    // drained on the portal thread via CMD_COMPLETE_REQUEST.
    CompletionMsg *completions[MAX_PENDING_REQUESTS];

    // ScreenCast — one session at a time (one screen, one capture
    // pipeline); a new CreateSession replaces the previous session.
    // Sender identity is deliberately NOT checked on session calls: every
    // client on the private session bus is the user's own, and one-shot
    // busctl connections (each a fresh unique name) drive the functional
    // check.
    struct {
        int active;
        int started;               // Start completed, stream live
        char path[256];            // session object path
        char sender[64];           // session owner, for directed signals
        sd_bus_slot *slot;         // session vtable slot
        uint32_t cursor_mode;
        char start_handle[256];    // pending Start request path ("" = none)
    } scast;
    portal_screencast_start_fn scast_start;
    portal_screencast_stop_fn scast_stop;
    void *scast_userdata;

    // Async ScreenCast start completion (shell thread -> portal thread).
    // Single slot — there is at most one pending Start.
    struct {
        int pending;
        char handle[256];
        uint32_t node_id, width, height;
        uint32_t response;
    } scast_completion;

    // Thread init
    uid_t target_uid;
    char *bus_address;
    int init_result;
    int init_done;
    pthread_mutex_t init_mutex;
    pthread_cond_t init_cond;

    pthread_mutex_t mutex;
};

// Forward declarations
static int _settings_read(sd_bus_message *m, void *userdata, sd_bus_error *ret_error);
static int _settings_read_all(sd_bus_message *m, void *userdata, sd_bus_error *ret_error);
static int _filechooser_open_file(sd_bus_message *m, void *userdata, sd_bus_error *ret_error);
static int _filechooser_save_file(sd_bus_message *m, void *userdata, sd_bus_error *ret_error);
static int _filechooser_save_files(sd_bus_message *m, void *userdata, sd_bus_error *ret_error);
static int _request_close(sd_bus_message *m, void *userdata, sd_bus_error *ret_error);
static int _scast_create_session(sd_bus_message *m, void *userdata, sd_bus_error *ret_error);
static int _scast_select_sources(sd_bus_message *m, void *userdata, sd_bus_error *ret_error);
static int _scast_start(sd_bus_message *m, void *userdata, sd_bus_error *ret_error);
static int _scast_open_remote(sd_bus_message *m, void *userdata, sd_bus_error *ret_error);
static int _session_close(sd_bus_message *m, void *userdata, sd_bus_error *ret_error);
static void _send_cmd(PortalService *ps, uint8_t cmd);

// --- Property getters ---

static int _settings_version_get(sd_bus *bus, const char *path, const char *interface,
                                  const char *property, sd_bus_message *reply,
                                  void *userdata, sd_bus_error *ret_error) {
    return sd_bus_message_append(reply, "u", (uint32_t)2);
}

static int _filechooser_version_get(sd_bus *bus, const char *path, const char *interface,
                                     const char *property, sd_bus_message *reply,
                                     void *userdata, sd_bus_error *ret_error) {
    return sd_bus_message_append(reply, "u", (uint32_t)3);
}

// --- D-Bus vtables ---

static const sd_bus_vtable settings_vtable[] = {
    SD_BUS_VTABLE_START(0),
    SD_BUS_METHOD("Read", "ss", "v", _settings_read, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("ReadAll", "as", "a{sa{sv}}", _settings_read_all, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_SIGNAL("SettingChanged", "ssv", 0),
    SD_BUS_PROPERTY("version", "u", _settings_version_get, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_VTABLE_END
};

static const sd_bus_vtable filechooser_vtable[] = {
    SD_BUS_VTABLE_START(0),
    SD_BUS_METHOD("OpenFile", "ssa{sv}", "o", _filechooser_open_file, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("SaveFile", "ssa{sv}", "o", _filechooser_save_file, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("SaveFiles", "ssa{sv}", "o", _filechooser_save_files, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_PROPERTY("version", "u", _filechooser_version_get, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_VTABLE_END
};

static const sd_bus_vtable request_vtable[] = {
    SD_BUS_VTABLE_START(0),
    SD_BUS_METHOD("Close", "", "", _request_close, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_SIGNAL("Response", "ua{sv}", 0),
    SD_BUS_VTABLE_END
};

static int _scast_source_types_get(sd_bus *bus, const char *path, const char *interface,
                                    const char *property, sd_bus_message *reply,
                                    void *userdata, sd_bus_error *ret_error) {
    return sd_bus_message_append(reply, "u", (uint32_t)1);  // MONITOR
}

static int _scast_cursor_modes_get(sd_bus *bus, const char *path, const char *interface,
                                    const char *property, sd_bus_message *reply,
                                    void *userdata, sd_bus_error *ret_error) {
    // EMBEDDED only: the engine composites the hardware cursor into every
    // captured frame, so that is the one mode we can deliver honestly.
    return sd_bus_message_append(reply, "u", (uint32_t)2);
}

static int _scast_version_get(sd_bus *bus, const char *path, const char *interface,
                               const char *property, sd_bus_message *reply,
                               void *userdata, sd_bus_error *ret_error) {
    return sd_bus_message_append(reply, "u", (uint32_t)4);
}

static int _session_version_get(sd_bus *bus, const char *path, const char *interface,
                                 const char *property, sd_bus_message *reply,
                                 void *userdata, sd_bus_error *ret_error) {
    return sd_bus_message_append(reply, "u", (uint32_t)1);
}

static const sd_bus_vtable screencast_vtable[] = {
    SD_BUS_VTABLE_START(0),
    SD_BUS_METHOD("CreateSession", "a{sv}", "o", _scast_create_session, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("SelectSources", "oa{sv}", "o", _scast_select_sources, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("Start", "osa{sv}", "o", _scast_start, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("OpenPipeWireRemote", "oa{sv}", "h", _scast_open_remote, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_PROPERTY("AvailableSourceTypes", "u", _scast_source_types_get, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_PROPERTY("AvailableCursorModes", "u", _scast_cursor_modes_get, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_PROPERTY("version", "u", _scast_version_get, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_VTABLE_END
};

static const sd_bus_vtable session_vtable[] = {
    SD_BUS_VTABLE_START(0),
    SD_BUS_METHOD("Close", "", "", _session_close, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_SIGNAL("Closed", "a{sv}", 0),
    SD_BUS_PROPERTY("version", "u", _session_version_get, 0, SD_BUS_VTABLE_PROPERTY_CONST),
    SD_BUS_VTABLE_END
};

// ============================================================================
// Settings handlers
// ============================================================================

static void _append_appearance_namespace(sd_bus_message *reply, PortalService *ps) {
    sd_bus_message_open_container(reply, 'e', "sa{sv}");
    sd_bus_message_append(reply, "s", "org.freedesktop.appearance");
    sd_bus_message_open_container(reply, 'a', "{sv}");

    sd_bus_message_open_container(reply, 'e', "sv");
    sd_bus_message_append(reply, "s", "color-scheme");
    sd_bus_message_open_container(reply, 'v', "u");
    sd_bus_message_append(reply, "u", ps->color_scheme);
    sd_bus_message_close_container(reply);
    sd_bus_message_close_container(reply);

    sd_bus_message_open_container(reply, 'e', "sv");
    sd_bus_message_append(reply, "s", "accent-color");
    sd_bus_message_open_container(reply, 'v', "(ddd)");
    sd_bus_message_open_container(reply, 'r', "ddd");
    sd_bus_message_append(reply, "ddd", ps->accent_r, ps->accent_g, ps->accent_b);
    sd_bus_message_close_container(reply);
    sd_bus_message_close_container(reply);
    sd_bus_message_close_container(reply);

    sd_bus_message_open_container(reply, 'e', "sv");
    sd_bus_message_append(reply, "s", "contrast");
    sd_bus_message_open_container(reply, 'v', "u");
    sd_bus_message_append(reply, "u", ps->contrast);
    sd_bus_message_close_container(reply);
    sd_bus_message_close_container(reply);

    sd_bus_message_close_container(reply);
    sd_bus_message_close_container(reply);
}

static int _settings_read(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    PortalService *ps = userdata;
    const char *ns, *key;
    sd_bus_message_read(m, "ss", &ns, &key);

    fprintf(stderr, "[PortalService] Settings.Read: %s / %s\n", ns, key);

    if (strcmp(ns, "org.freedesktop.appearance") != 0)
        return sd_bus_error_setf(ret_error, "org.freedesktop.portal.Error.NotFound",
                                 "Namespace %s not found", ns);

    sd_bus_message *reply = NULL;
    sd_bus_message_new_method_return(m, &reply);

    // xdg-desktop-portal wraps Read responses in a double variant: v(v(value)).
    // Chromium's dark_mode_manager_linux.cc expects this format.
    pthread_mutex_lock(&ps->mutex);
    if (strcmp(key, "color-scheme") == 0) {
        sd_bus_message_open_container(reply, 'v', "v");
        sd_bus_message_open_container(reply, 'v', "u");
        sd_bus_message_append(reply, "u", ps->color_scheme);
        sd_bus_message_close_container(reply);
        sd_bus_message_close_container(reply);
    } else if (strcmp(key, "accent-color") == 0) {
        sd_bus_message_open_container(reply, 'v', "v");
        sd_bus_message_open_container(reply, 'v', "(ddd)");
        sd_bus_message_open_container(reply, 'r', "ddd");
        sd_bus_message_append(reply, "ddd", ps->accent_r, ps->accent_g, ps->accent_b);
        sd_bus_message_close_container(reply);
        sd_bus_message_close_container(reply);
        sd_bus_message_close_container(reply);
    } else if (strcmp(key, "contrast") == 0) {
        sd_bus_message_open_container(reply, 'v', "v");
        sd_bus_message_open_container(reply, 'v', "u");
        sd_bus_message_append(reply, "u", ps->contrast);
        sd_bus_message_close_container(reply);
        sd_bus_message_close_container(reply);
    } else {
        pthread_mutex_unlock(&ps->mutex);
        sd_bus_message_unref(reply);
        return sd_bus_error_setf(ret_error, "org.freedesktop.portal.Error.NotFound",
                                 "Key %s not found", key);
    }
    pthread_mutex_unlock(&ps->mutex);
    return sd_bus_send(NULL, reply, NULL);
}

static int _settings_read_all(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    PortalService *ps = userdata;
    sd_bus_message_enter_container(m, 'a', "s");
    const char *ns;
    while (sd_bus_message_read(m, "s", &ns) > 0) {}
    sd_bus_message_exit_container(m);

    sd_bus_message *reply = NULL;
    sd_bus_message_new_method_return(m, &reply);
    sd_bus_message_open_container(reply, 'a', "{sa{sv}}");
    pthread_mutex_lock(&ps->mutex);
    _append_appearance_namespace(reply, ps);
    pthread_mutex_unlock(&ps->mutex);
    sd_bus_message_close_container(reply);
    return sd_bus_send(NULL, reply, NULL);
}

// ============================================================================
// FileChooser — helper process management
// ============================================================================

static void _parse_options(sd_bus_message *m, char *handle_token, int ht_sz,
                           int *multiple, int *directory,
                           char *current_folder, int f_sz,
                           char *accept_label, int l_sz,
                           char *suggested_name, int n_sz) {
    handle_token[0] = current_folder[0] = accept_label[0] = suggested_name[0] = 0;
    *multiple = *directory = 0;

    if (sd_bus_message_enter_container(m, 'a', "{sv}") < 0) return;
    while (sd_bus_message_enter_container(m, 'e', "sv") > 0) {
        const char *key;
        if (sd_bus_message_read(m, "s", &key) < 0) goto next;

        if (strcmp(key, "handle_token") == 0) {
            const char *v;
            if (sd_bus_message_enter_container(m, 'v', "s") >= 0) {
                if (sd_bus_message_read(m, "s", &v) >= 0)
                    snprintf(handle_token, ht_sz, "%s", v);
                sd_bus_message_exit_container(m);
            }
        } else if (strcmp(key, "multiple") == 0) {
            int v;
            if (sd_bus_message_enter_container(m, 'v', "b") >= 0) {
                if (sd_bus_message_read(m, "b", &v) >= 0) *multiple = v;
                sd_bus_message_exit_container(m);
            }
        } else if (strcmp(key, "directory") == 0) {
            int v;
            if (sd_bus_message_enter_container(m, 'v', "b") >= 0) {
                if (sd_bus_message_read(m, "b", &v) >= 0) *directory = v;
                sd_bus_message_exit_container(m);
            }
        } else if (strcmp(key, "accept_label") == 0) {
            const char *v;
            if (sd_bus_message_enter_container(m, 'v', "s") >= 0) {
                if (sd_bus_message_read(m, "s", &v) >= 0)
                    snprintf(accept_label, l_sz, "%s", v);
                sd_bus_message_exit_container(m);
            }
        } else if (strcmp(key, "current_folder") == 0) {
            if (sd_bus_message_enter_container(m, 'v', "ay") >= 0) {
                const void *data; size_t len;
                if (sd_bus_message_read_array(m, 'y', &data, &len) >= 0 && len > 0) {
                    size_t c = len < (size_t)(f_sz-1) ? len : (size_t)(f_sz-1);
                    memcpy(current_folder, data, c);
                    current_folder[c] = 0;
                }
                sd_bus_message_exit_container(m);
            }
        } else if (strcmp(key, "current_name") == 0) {
            const char *v;
            if (sd_bus_message_enter_container(m, 'v', "s") >= 0) {
                if (sd_bus_message_read(m, "s", &v) >= 0)
                    snprintf(suggested_name, n_sz, "%s", v);
                sd_bus_message_exit_container(m);
            }
        } else {
            sd_bus_message_skip(m, "v");
        }
    next:
        sd_bus_message_exit_container(m);
    }
    sd_bus_message_exit_container(m);
}

/// kind: "request" or "session" — the two object families the portal mints.
/// Spec escaping: the sender's initial ':' is REMOVED (not replaced), then
/// '.' becomes '_'. Clients derive these paths on their own to subscribe
/// for Response BEFORE calling — with an instantly-answered method, a
/// divergence here makes them miss the signal forever. The old ':'→'_'
/// dialect survived in FileChooser only because its responses wait on a
/// human, so clients had time to re-subscribe on the returned path.
static void _build_portal_path(char *buf, int bufsz, const char *kind,
                               const char *sender, const char *token) {
    char esc[128];
    const char *s = sender; char *d = esc;
    if (*s == ':') s++;
    while (*s && (d - esc) < (int)sizeof(esc) - 1) {
        *d++ = (*s == '.' || *s == ':') ? '_' : *s;
        s++;
    }
    *d = 0;
    snprintf(buf, bufsz, "/org/freedesktop/portal/desktop/%s/%s/%s", kind, esc, token);
}

static void _build_handle_path(char *buf, int bufsz, const char *sender, const char *token) {
    _build_portal_path(buf, bufsz, "request", sender, token);
}

static PendingRequest *_find_free_request(PortalService *ps) {
    for (int i = 0; i < MAX_PENDING_REQUESTS; i++)
        if (!ps->requests[i].active) return &ps->requests[i];
    return NULL;
}

static PendingRequest *_find_request(PortalService *ps, const char *handle) {
    for (int i = 0; i < MAX_PENDING_REQUESTS; i++)
        if (ps->requests[i].active && strcmp(ps->requests[i].handle, handle) == 0)
            return &ps->requests[i];
    return NULL;
}

/// Launch the file chooser helper via fork/exec (fallback path — used only
/// when no async launcher is set). Returns the PID or -1 on error. Sets
/// stdout_fd to the read end of the pipe; _check_children reaps + reads it.
static pid_t _launch_chooser(PortalService *ps, const char *title,
                              int multiple, int directory, int save_mode,
                              const char *current_folder, const char *accept_label,
                              const char *suggested_name, int *stdout_fd) {
    if (!ps->chooser_command) {
        fprintf(stderr, "[PortalService] No file chooser command configured\n");
        return -1;
    }

    int pipefd[2];
    if (pipe(pipefd) < 0) return -1;

    pid_t pid = fork();
    if (pid < 0) {
        close(pipefd[0]); close(pipefd[1]);
        return -1;
    }

    if (pid == 0) {
        // Child process
        close(pipefd[0]);
        dup2(pipefd[1], STDOUT_FILENO);
        close(pipefd[1]);

        // Pass parameters via environment
        if (title) setenv("PORTAL_TITLE", title, 1);
        if (multiple) setenv("PORTAL_MULTIPLE", "1", 1);
        if (directory) setenv("PORTAL_DIRECTORY", "1", 1);
        if (save_mode) setenv("PORTAL_SAVE", "1", 1);
        if (current_folder && current_folder[0])
            setenv("PORTAL_FOLDER", current_folder, 1);
        if (accept_label && accept_label[0])
            setenv("PORTAL_ACCEPT_LABEL", accept_label, 1);
        if (suggested_name && suggested_name[0])
            setenv("PORTAL_SUGGESTED_NAME", suggested_name, 1);

        // Ensure the child can find engine libraries and connect to Wayland
        // LD_LIBRARY_PATH, WAYLAND_DISPLAY, XDG_RUNTIME_DIR are inherited

        // Redirect stderr to a log file for debugging
        int logfd = open("/tmp/portal_chooser.log", O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (logfd >= 0) { dup2(logfd, STDERR_FILENO); close(logfd); }

        execl(ps->chooser_command, ps->chooser_command, "--picker", NULL);
        fprintf(stderr, "[PortalService] execl(%s) failed: %s\n",
                ps->chooser_command, strerror(errno));
        _exit(127);
    }

    // Parent
    close(pipefd[1]);
    *stdout_fd = pipefd[0];
    // Make non-blocking so we can poll it
    int flags = fcntl(pipefd[0], F_GETFL, 0);
    fcntl(pipefd[0], F_SETFL, flags | O_NONBLOCK);

    fprintf(stderr, "[PortalService] Launched chooser pid=%d cmd=%s\n",
            (int)pid, ps->chooser_command);
    return pid;
}

/// Emit the Response signal on a request object and clean it up.
static void _emit_response(PortalService *ps, PendingRequest *req,
                            uint32_t response, char **uris, int num_uris) {
    sd_bus_message *sig = NULL;
    int r = sd_bus_message_new_signal(ps->bus, &sig, req->handle,
                                      REQUEST_IFACE, "Response");
    if (r >= 0) {
        // Directed like the ScreenCast responses (_scast_emit_response):
        // an instant Response (launcher failure, Close) races the
        // caller's AddMatch and a broadcast can be dropped unheard.
        if (req->sender[0]) sd_bus_message_set_destination(sig, req->sender);
        sd_bus_message_append(sig, "u", response);
        sd_bus_message_open_container(sig, 'a', "{sv}");
        if (response == 0 && num_uris > 0) {
            sd_bus_message_open_container(sig, 'e', "sv");
            sd_bus_message_append(sig, "s", "uris");
            sd_bus_message_open_container(sig, 'v', "as");
            sd_bus_message_open_container(sig, 'a', "s");
            for (int i = 0; i < num_uris; i++)
                sd_bus_message_append(sig, "s", uris[i]);
            sd_bus_message_close_container(sig);
            sd_bus_message_close_container(sig);
            sd_bus_message_close_container(sig);
        }
        sd_bus_message_close_container(sig);
        sd_bus_send(ps->bus, sig, NULL);
        sd_bus_message_unref(sig);
    }

    fprintf(stderr, "[PortalService] Response(%u) on %s, %d URIs\n",
            response, req->handle, num_uris);

    if (req->stdout_fd >= 0) { close(req->stdout_fd); req->stdout_fd = -1; }
    sd_bus_slot_unref(req->slot); req->slot = NULL;
    req->active = 0;
}

/// Common handler for OpenFile/SaveFile/SaveFiles.
static int _filechooser_common(sd_bus_message *m, void *userdata,
                                sd_bus_error *ret_error, int save_mode) {
    PortalService *ps = userdata;
    const char *parent_window, *title;
    sd_bus_message_read(m, "ss", &parent_window, &title);

    char handle_token[128], current_folder[1024], accept_label[256], suggested_name[256];
    int multiple = 0, directory = 0;
    _parse_options(m, handle_token, sizeof(handle_token),
                   &multiple, &directory,
                   current_folder, sizeof(current_folder),
                   accept_label, sizeof(accept_label),
                   suggested_name, sizeof(suggested_name));

    const char *sender = sd_bus_message_get_sender(m);
    if (!handle_token[0])
        snprintf(handle_token, sizeof(handle_token), "flutter%lu",
                 (unsigned long)__sync_fetch_and_add(&ps->request_counter, 1));

    char handle_path[256];
    _build_handle_path(handle_path, sizeof(handle_path), sender, handle_token);

    fprintf(stderr, "[PortalService] FileChooser.%s: \"%s\" handle=%s\n",
            save_mode ? "SaveFile" : "OpenFile", title, handle_path);

    pthread_mutex_lock(&ps->mutex);
    PendingRequest *req = _find_free_request(ps);
    if (!req) {
        pthread_mutex_unlock(&ps->mutex);
        return sd_bus_error_setf(ret_error, SD_BUS_ERROR_LIMITS_EXCEEDED,
                                 "Too many pending requests");
    }

    snprintf(req->handle, sizeof(req->handle), "%s", handle_path);
    snprintf(req->sender, sizeof(req->sender), "%s", sender);
    req->active = 1;
    req->slot = NULL;
    req->child_pid = -1;
    req->stdout_fd = -1;

    // WHO asked. The kernel supplies this and the client cannot forge it —
    // the same credential read that authenticates the agent socket. The shell
    // turns it into an owner: a dialog opened by an agent's browser belongs to
    // that agent, not to the human whose desktop it would otherwise appear on.
    int caller_pid = 0;
    {
        sd_bus_creds *creds = NULL;
        if (sd_bus_query_sender_creds(m, SD_BUS_CREDS_PID, &creds) >= 0 && creds) {
            pid_t p = 0;
            if (sd_bus_creds_get_pid(creds, &p) >= 0) caller_pid = (int)p;
            sd_bus_creds_unref(creds);
        }
    }

    sd_bus_add_object_vtable(ps->bus, &req->slot, handle_path,
                              REQUEST_IFACE, request_vtable, ps);

    portal_launch_chooser_fn launcher = ps->chooser_launcher;
    void *launcher_ud = ps->chooser_launcher_userdata;
    char *cmd = ps->chooser_command ? strdup(ps->chooser_command) : NULL;
    pthread_mutex_unlock(&ps->mutex);

    if (launcher) {
        // Async path: the launcher composites the helper and later delivers
        // the result via portal_service_complete_request(handle). The portal
        // neither reaps nor reads the child (child_pid/stdout_fd stay -1).
        int r = launcher(launcher_ud, handle_path, cmd, caller_pid, title,
                         multiple, directory, save_mode,
                         current_folder[0] ? current_folder : NULL,
                         accept_label[0] ? accept_label : NULL,
                         suggested_name[0] ? suggested_name : NULL);
        free(cmd);
        if (r < 0) {
            pthread_mutex_lock(&ps->mutex);
            _emit_response(ps, req, 2, NULL, 0);
            pthread_mutex_unlock(&ps->mutex);
        }
    } else {
        // Fallback: fork/exec + stdout reap (_check_children).
        free(cmd);
        int stdout_fd = -1;
        pthread_mutex_lock(&ps->mutex);
        pid_t pid = _launch_chooser(ps, title, multiple, directory, save_mode,
                                     current_folder[0] ? current_folder : NULL,
                                     accept_label[0] ? accept_label : NULL,
                                     suggested_name[0] ? suggested_name : NULL,
                                     &stdout_fd);
        req->child_pid = pid;
        req->stdout_fd = stdout_fd;
        if (pid < 0)
            _emit_response(ps, req, 2, NULL, 0);
        pthread_mutex_unlock(&ps->mutex);
    }

    return sd_bus_reply_method_return(m, "o", handle_path);
}

static int _filechooser_open_file(sd_bus_message *m, void *u, sd_bus_error *e) {
    return _filechooser_common(m, u, e, 0);
}
static int _filechooser_save_file(sd_bus_message *m, void *u, sd_bus_error *e) {
    return _filechooser_common(m, u, e, 1);
}
static int _filechooser_save_files(sd_bus_message *m, void *u, sd_bus_error *e) {
    return _filechooser_common(m, u, e, 1);
}

// ============================================================================
// Request.Close
// ============================================================================

static int _request_close(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    PortalService *ps = userdata;
    const char *path = sd_bus_message_get_path(m);

    pthread_mutex_lock(&ps->mutex);
    PendingRequest *req = _find_request(ps, path);
    if (req) {
        // Kill the helper if running
        if (req->child_pid > 0) {
            kill(req->child_pid, SIGTERM);
            req->child_pid = -1;
        }
        _emit_response(ps, req, 1, NULL, 0);
    }
    pthread_mutex_unlock(&ps->mutex);

    return sd_bus_reply_method_return(m, "");
}

// ============================================================================
// ScreenCast
// ============================================================================

/// Emit Response(response, results) on a request path, DIRECTED at the
/// caller. Directed matters: a broadcast is only delivered to clients
/// whose AddMatch the daemon has already seen, and Chromium's webrtc
/// subscribes AFTER the method returns — our instant Response fired into
/// a match-less void and Chrome waited forever. A unicast signal is
/// delivered regardless of match rules (and is what the reference
/// xdg-desktop-portal sends). A successful Start (response 0 with a
/// node) carries the one stream: (node, {position, size, source_type});
/// everything else, empty results.
static void _scast_emit_response(PortalService *ps, const char *handle,
                                 const char *dest,
                                 uint32_t response, uint32_t node,
                                 uint32_t width, uint32_t height) {
    sd_bus_message *sig = NULL;
    if (sd_bus_message_new_signal(ps->bus, &sig, handle,
                                  REQUEST_IFACE, "Response") < 0) return;
    if (dest && dest[0]) sd_bus_message_set_destination(sig, dest);
    sd_bus_message_append(sig, "u", response);
    sd_bus_message_open_container(sig, 'a', "{sv}");
    if (response == 0 && node != 0) {
        sd_bus_message_open_container(sig, 'e', "sv");
        sd_bus_message_append(sig, "s", "streams");
        sd_bus_message_open_container(sig, 'v', "a(ua{sv})");
        sd_bus_message_open_container(sig, 'a', "(ua{sv})");
        sd_bus_message_open_container(sig, 'r', "ua{sv}");
        sd_bus_message_append(sig, "u", node);
        sd_bus_message_open_container(sig, 'a', "{sv}");
        sd_bus_message_open_container(sig, 'e', "sv");
        sd_bus_message_append(sig, "s", "position");
        sd_bus_message_open_container(sig, 'v', "(ii)");
        sd_bus_message_append(sig, "(ii)", (int32_t)0, (int32_t)0);
        sd_bus_message_close_container(sig);
        sd_bus_message_close_container(sig);
        sd_bus_message_open_container(sig, 'e', "sv");
        sd_bus_message_append(sig, "s", "size");
        sd_bus_message_open_container(sig, 'v', "(ii)");
        sd_bus_message_append(sig, "(ii)", (int32_t)width, (int32_t)height);
        sd_bus_message_close_container(sig);
        sd_bus_message_close_container(sig);
        sd_bus_message_open_container(sig, 'e', "sv");
        sd_bus_message_append(sig, "s", "source_type");
        sd_bus_message_open_container(sig, 'v', "u");
        sd_bus_message_append(sig, "u", (uint32_t)1);  // MONITOR
        sd_bus_message_close_container(sig);
        sd_bus_message_close_container(sig);
        sd_bus_message_close_container(sig);
        sd_bus_message_close_container(sig);
        sd_bus_message_close_container(sig);
        sd_bus_message_close_container(sig);
        sd_bus_message_close_container(sig);
    }
    sd_bus_message_close_container(sig);
    sd_bus_send(ps->bus, sig, NULL);
    sd_bus_message_unref(sig);
}

/// Tear down the active session (portal thread): cancel a pending Start,
/// stop the shell's capture, unregister the session object. emit_closed:
/// a replaced/abandoned session gets the Closed signal so its client
/// learns; a client-driven Session.Close does not need one.
static void _scast_teardown(PortalService *ps, int emit_closed) {
    pthread_mutex_lock(&ps->mutex);
    if (!ps->scast.active) { pthread_mutex_unlock(&ps->mutex); return; }
    int had_stream = ps->scast.started || ps->scast.start_handle[0];
    char start_handle[256];
    snprintf(start_handle, sizeof(start_handle), "%s", ps->scast.start_handle);
    char path[256];
    snprintf(path, sizeof(path), "%s", ps->scast.path);
    char sender[64];
    snprintf(sender, sizeof(sender), "%s", ps->scast.sender);
    sd_bus_slot *slot = ps->scast.slot;
    memset(&ps->scast, 0, sizeof(ps->scast));
    ps->scast_completion.pending = 0;  // a late completion must not revive it
    portal_screencast_stop_fn stop = ps->scast_stop;
    void *ud = ps->scast_userdata;
    pthread_mutex_unlock(&ps->mutex);

    if (start_handle[0])
        _scast_emit_response(ps, start_handle, sender, 1, 0, 0, 0);  // cancelled
    // The stop hook blocks until the capture drains — call it OUTSIDE the
    // mutex: the shell side may call complete_screencast_start meanwhile,
    // which takes it.
    if (had_stream && stop) stop(ud);

    if (emit_closed) {
        sd_bus_message *sig = NULL;
        if (sd_bus_message_new_signal(ps->bus, &sig, path,
                                      SESSION_IFACE, "Closed") >= 0) {
            if (sender[0]) sd_bus_message_set_destination(sig, sender);
            sd_bus_message_open_container(sig, 'a', "{sv}");
            sd_bus_message_close_container(sig);
            sd_bus_send(ps->bus, sig, NULL);
            sd_bus_message_unref(sig);
        }
    }
    sd_bus_slot_unref(slot);
    fprintf(stderr, "[PortalService] ScreenCast session %s closed\n", path);
}

static void _scast_parse_options(sd_bus_message *m,
                                 char *handle_token, int ht_sz,
                                 char *session_token, int st_sz,
                                 uint32_t *cursor_mode) {
    if (handle_token) handle_token[0] = 0;
    if (session_token) session_token[0] = 0;

    if (sd_bus_message_enter_container(m, 'a', "{sv}") < 0) return;
    while (sd_bus_message_enter_container(m, 'e', "sv") > 0) {
        const char *key;
        if (sd_bus_message_read(m, "s", &key) < 0) goto next;
        if (handle_token && strcmp(key, "handle_token") == 0) {
            const char *v;
            if (sd_bus_message_enter_container(m, 'v', "s") >= 0) {
                if (sd_bus_message_read(m, "s", &v) >= 0)
                    snprintf(handle_token, ht_sz, "%s", v);
                sd_bus_message_exit_container(m);
            }
        } else if (session_token && strcmp(key, "session_handle_token") == 0) {
            const char *v;
            if (sd_bus_message_enter_container(m, 'v', "s") >= 0) {
                if (sd_bus_message_read(m, "s", &v) >= 0)
                    snprintf(session_token, st_sz, "%s", v);
                sd_bus_message_exit_container(m);
            }
        } else if (cursor_mode && strcmp(key, "cursor_mode") == 0) {
            uint32_t v;
            if (sd_bus_message_enter_container(m, 'v', "u") >= 0) {
                if (sd_bus_message_read(m, "u", &v) >= 0) *cursor_mode = v;
                sd_bus_message_exit_container(m);
            }
        } else {
            sd_bus_message_skip(m, "v");
        }
    next:
        sd_bus_message_exit_container(m);
    }
    sd_bus_message_exit_container(m);
}

static void _ensure_token(PortalService *ps, char *token, int sz) {
    if (!token[0])
        snprintf(token, sz, "starling%lu",
                 (unsigned long)__sync_fetch_and_add(&ps->request_counter, 1));
}

static int _scast_create_session(sd_bus_message *m, void *userdata,
                                 sd_bus_error *ret_error) {
    PortalService *ps = userdata;
    char handle_token[128], session_token[128];
    _scast_parse_options(m, handle_token, sizeof(handle_token),
                         session_token, sizeof(session_token), NULL);
    const char *sender = sd_bus_message_get_sender(m);
    _ensure_token(ps, handle_token, sizeof(handle_token));
    _ensure_token(ps, session_token, sizeof(session_token));

    // One session: a new one replaces (and Closes) whatever was live.
    _scast_teardown(ps, 1);

    char session_path[256], handle_path[256];
    _build_portal_path(session_path, sizeof(session_path), "session",
                       sender, session_token);
    _build_handle_path(handle_path, sizeof(handle_path), sender, handle_token);

    sd_bus_slot *slot = NULL;
    int r = sd_bus_add_object_vtable(ps->bus, &slot, session_path,
                                     SESSION_IFACE, session_vtable, ps);
    if (r < 0)
        return sd_bus_error_setf(ret_error, "org.freedesktop.DBus.Error.Failed",
                                 "session object: %s", strerror(-r));

    pthread_mutex_lock(&ps->mutex);
    ps->scast.active = 1;
    ps->scast.slot = slot;
    snprintf(ps->scast.path, sizeof(ps->scast.path), "%s", session_path);
    snprintf(ps->scast.sender, sizeof(ps->scast.sender), "%s", sender);
    pthread_mutex_unlock(&ps->mutex);

    fprintf(stderr, "[PortalService] ScreenCast.CreateSession: %s\n", session_path);

    r = sd_bus_reply_method_return(m, "o", handle_path);

    // Instant Response — the client derived the request path from its own
    // handle_token before calling, so the signal cannot beat its match.
    // session_handle is typed "s", matching the reference implementation
    // (a long-standing divergence from the spec's "o" that every consumer
    // is written against).
    sd_bus_message *sig = NULL;
    if (sd_bus_message_new_signal(ps->bus, &sig, handle_path,
                                  REQUEST_IFACE, "Response") >= 0) {
        sd_bus_message_set_destination(sig, sender);
        sd_bus_message_append(sig, "u", (uint32_t)0);
        sd_bus_message_open_container(sig, 'a', "{sv}");
        sd_bus_message_open_container(sig, 'e', "sv");
        sd_bus_message_append(sig, "s", "session_handle");
        sd_bus_message_open_container(sig, 'v', "s");
        sd_bus_message_append(sig, "s", session_path);
        sd_bus_message_close_container(sig);
        sd_bus_message_close_container(sig);
        sd_bus_message_close_container(sig);
        sd_bus_send(ps->bus, sig, NULL);
        sd_bus_message_unref(sig);
    }
    return r;
}

/// Read the session object path argument and check it names the live
/// session. Returns 0 on match, <0 after setting the error.
static int _scast_check_session(PortalService *ps, sd_bus_message *m,
                                sd_bus_error *ret_error) {
    const char *session;
    if (sd_bus_message_read(m, "o", &session) < 0)
        return sd_bus_error_setf(ret_error, "org.freedesktop.DBus.Error.InvalidArgs",
                                 "no session handle");
    pthread_mutex_lock(&ps->mutex);
    int ok = ps->scast.active && strcmp(session, ps->scast.path) == 0;
    pthread_mutex_unlock(&ps->mutex);
    if (!ok)
        return sd_bus_error_setf(ret_error, "org.freedesktop.portal.Error.NotFound",
                                 "no such session: %s", session);
    return 0;
}

static int _scast_select_sources(sd_bus_message *m, void *userdata,
                                 sd_bus_error *ret_error) {
    PortalService *ps = userdata;
    int r = _scast_check_session(ps, m, ret_error);
    if (r < 0) return r;

    char handle_token[128];
    uint32_t cursor_mode = 2;
    _scast_parse_options(m, handle_token, sizeof(handle_token), NULL, 0,
                         &cursor_mode);
    const char *sender = sd_bus_message_get_sender(m);
    _ensure_token(ps, handle_token, sizeof(handle_token));

    pthread_mutex_lock(&ps->mutex);
    ps->scast.cursor_mode = cursor_mode;
    pthread_mutex_unlock(&ps->mutex);

    // The one source we offer is the monitor, so there is nothing to
    // choose: accept immediately. (types is parsed and ignored — a client
    // asking for WINDOW still gets the monitor, which is what the
    // AvailableSourceTypes property told it to expect.)
    char handle_path[256];
    _build_handle_path(handle_path, sizeof(handle_path), sender, handle_token);
    r = sd_bus_reply_method_return(m, "o", handle_path);
    _scast_emit_response(ps, handle_path, sender, 0, 0, 0, 0);
    return r;
}

static int _scast_start(sd_bus_message *m, void *userdata,
                        sd_bus_error *ret_error) {
    PortalService *ps = userdata;
    int r = _scast_check_session(ps, m, ret_error);
    if (r < 0) return r;

    const char *parent_window;
    sd_bus_message_read(m, "s", &parent_window);
    char handle_token[128];
    _scast_parse_options(m, handle_token, sizeof(handle_token), NULL, 0, NULL);
    const char *sender = sd_bus_message_get_sender(m);
    _ensure_token(ps, handle_token, sizeof(handle_token));

    char handle_path[256];
    _build_handle_path(handle_path, sizeof(handle_path), sender, handle_token);

    pthread_mutex_lock(&ps->mutex);
    if (ps->scast.started || ps->scast.start_handle[0]) {
        pthread_mutex_unlock(&ps->mutex);
        return sd_bus_error_setf(ret_error, "org.freedesktop.DBus.Error.Failed",
                                 "session already started");
    }
    snprintf(ps->scast.start_handle, sizeof(ps->scast.start_handle),
             "%s", handle_path);
    portal_screencast_start_fn start = ps->scast_start;
    void *ud = ps->scast_userdata;
    pthread_mutex_unlock(&ps->mutex);

    fprintf(stderr, "[PortalService] ScreenCast.Start: handle=%s\n", handle_path);
    r = sd_bus_reply_method_return(m, "o", handle_path);

    int started = start ? start(ud, handle_path) : -1;
    if (started < 0) {
        pthread_mutex_lock(&ps->mutex);
        ps->scast.start_handle[0] = 0;
        pthread_mutex_unlock(&ps->mutex);
        _scast_emit_response(ps, handle_path, sender, 2, 0, 0, 0);
    }
    return r;
}

static int _scast_open_remote(sd_bus_message *m, void *userdata,
                              sd_bus_error *ret_error) {
    PortalService *ps = userdata;
    int r = _scast_check_session(ps, m, ret_error);
    if (r < 0) return r;

    // A PipeWire "remote" is a connected daemon socket the client library
    // takes over (pw_context_connect_fd). Resolution mirrors libpipewire:
    // PIPEWIRE_RUNTIME_DIR first — the launchers point it at the real user
    // runtime dir, because XDG_RUNTIME_DIR here is the private session dir.
    const char *dir = getenv("PIPEWIRE_RUNTIME_DIR");
    if (!dir || !dir[0]) dir = getenv("XDG_RUNTIME_DIR");
    const char *name = getenv("PIPEWIRE_REMOTE");
    if (!name || !name[0]) name = "pipewire-0";
    if (!dir || !dir[0])
        return sd_bus_error_setf(ret_error, "org.freedesktop.DBus.Error.Failed",
                                 "no runtime dir for the PipeWire socket");

    struct sockaddr_un addr = { .sun_family = AF_UNIX };
    snprintf(addr.sun_path, sizeof(addr.sun_path), "%s/%s", dir, name);
    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0 || connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        if (fd >= 0) close(fd);
        return sd_bus_error_setf(ret_error, "org.freedesktop.DBus.Error.Failed",
                                 "PipeWire daemon unreachable at %s", addr.sun_path);
    }
    r = sd_bus_reply_method_return(m, "h", fd);
    close(fd);  // sd-bus dup'd it into the reply
    return r;
}

static int _session_close(sd_bus_message *m, void *userdata,
                          sd_bus_error *ret_error) {
    PortalService *ps = userdata;
    const char *path = sd_bus_message_get_path(m);

    pthread_mutex_lock(&ps->mutex);
    int is_scast = ps->scast.active && strcmp(path, ps->scast.path) == 0;
    pthread_mutex_unlock(&ps->mutex);
    if (is_scast) _scast_teardown(ps, 0);

    return sd_bus_reply_method_return(m, "");
}

/// Drain the pending ScreenCast start completion (portal thread).
static void _drain_scast_completion(PortalService *ps) {
    pthread_mutex_lock(&ps->mutex);
    if (!ps->scast_completion.pending) {
        pthread_mutex_unlock(&ps->mutex);
        return;
    }
    ps->scast_completion.pending = 0;
    char handle[256];
    snprintf(handle, sizeof(handle), "%s", ps->scast_completion.handle);
    uint32_t node = ps->scast_completion.node_id;
    uint32_t w = ps->scast_completion.width, h = ps->scast_completion.height;
    uint32_t response = ps->scast_completion.response;
    // Stale completion (the session was torn down while starting): ignore.
    if (!ps->scast.active || strcmp(handle, ps->scast.start_handle) != 0) {
        pthread_mutex_unlock(&ps->mutex);
        return;
    }
    ps->scast.start_handle[0] = 0;
    if (response == 0) ps->scast.started = 1;
    char dest[64];
    snprintf(dest, sizeof(dest), "%s", ps->scast.sender);
    pthread_mutex_unlock(&ps->mutex);

    _scast_emit_response(ps, handle, dest, response, node, w, h);
    if (response == 0)
        fprintf(stderr, "[PortalService] ScreenCast started: node %u (%ux%u)\n",
                node, w, h);
}

// ============================================================================
// Settings signal emission
// ============================================================================

static void _emit_setting_changed(PortalService *ps, const char *key) {
    sd_bus_message *sig = NULL;
    if (sd_bus_message_new_signal(ps->bus, &sig, PORTAL_OBJ_PATH,
                                  SETTINGS_IFACE, "SettingChanged") < 0) return;

    sd_bus_message_append(sig, "ss", "org.freedesktop.appearance", key);
    if (strcmp(key, "color-scheme") == 0) {
        sd_bus_message_open_container(sig, 'v', "u");
        sd_bus_message_append(sig, "u", ps->color_scheme);
        sd_bus_message_close_container(sig);
    } else if (strcmp(key, "accent-color") == 0) {
        sd_bus_message_open_container(sig, 'v', "(ddd)");
        sd_bus_message_open_container(sig, 'r', "ddd");
        sd_bus_message_append(sig, "ddd", ps->accent_r, ps->accent_g, ps->accent_b);
        sd_bus_message_close_container(sig);
        sd_bus_message_close_container(sig);
    } else if (strcmp(key, "contrast") == 0) {
        sd_bus_message_open_container(sig, 'v', "u");
        sd_bus_message_append(sig, "u", ps->contrast);
        sd_bus_message_close_container(sig);
    }
    sd_bus_send(ps->bus, sig, NULL);
    sd_bus_message_unref(sig);
}

static void _send_cmd(PortalService *ps, uint8_t cmd) {
    (void)write(ps->pipe_fd[1], &cmd, 1);
}

// Drain async chooser completions (portal thread): match each to its pending
// request and emit the D-Bus Response.
static void _drain_completions(PortalService *ps) {
    for (;;) {
        pthread_mutex_lock(&ps->mutex);
        CompletionMsg *msg = NULL;
        for (int i = 0; i < MAX_PENDING_REQUESTS; i++) {
            if (ps->completions[i]) {
                msg = ps->completions[i];
                ps->completions[i] = NULL;
                break;
            }
        }
        if (!msg) { pthread_mutex_unlock(&ps->mutex); break; }
        PendingRequest *req = _find_request(ps, msg->handle);
        if (req)
            _emit_response(ps, req, msg->response, msg->uris, msg->num_uris);
        pthread_mutex_unlock(&ps->mutex);

        for (int i = 0; i < msg->num_uris; i++) free(msg->uris[i]);
        free(msg->uris);
        free(msg);
    }
}

// ============================================================================
// Helper process reaping — check if any chooser child exited
// ============================================================================

static void _check_children(PortalService *ps) {
    for (int i = 0; i < MAX_PENDING_REQUESTS; i++) {
        PendingRequest *req = &ps->requests[i];
        if (!req->active || req->child_pid <= 0) continue;

        int status;
        pid_t w = waitpid(req->child_pid, &status, WNOHANG);
        if (w <= 0) continue;  // still running or error

        req->child_pid = -1;

        // Read all output from the helper's stdout
        char buf[8192];
        int total = 0;
        while (total < (int)sizeof(buf) - 1) {
            int n = read(req->stdout_fd, buf + total, sizeof(buf) - 1 - total);
            if (n <= 0) break;
            total += n;
        }
        buf[total] = 0;

        if (WIFEXITED(status) && WEXITSTATUS(status) == 0 && total > 0) {
            // Parse URIs (one per line)
            char *uris[256];
            int num_uris = 0;
            char *line = strtok(buf, "\n");
            while (line && num_uris < 256) {
                // Trim whitespace
                while (*line == ' ' || *line == '\t') line++;
                if (*line) uris[num_uris++] = line;
                line = strtok(NULL, "\n");
            }
            _emit_response(ps, req, 0, uris, num_uris);
        } else {
            // Cancelled or error
            _emit_response(ps, req, 1, NULL, 0);
        }
    }
}

// ============================================================================
// Thread
// ============================================================================

static int _thread_set_euid(uid_t euid) {
    return syscall(SYS_setresuid, (uid_t)-1, euid, (uid_t)-1);
}

/* org.freedesktop.DBus.NameLost — we no longer own a name we claimed. */
static int _on_name_lost(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    const char *name = NULL;
    if (sd_bus_message_read(m, "s", &name) < 0 || !name)
        return 0;
    if (strcmp(name, PORTAL_BUS_NAME) == 0)
        fprintf(stderr, "[PortalService] LOST %s — another portal took it; "
                        "file dialogs and appearance settings will now be "
                        "served by that process, not by the shell\n",
                PORTAL_BUS_NAME);
    return 0;
}

static int _setup_bus(PortalService *ps) {
    int r;

    if (ps->target_uid != 0 && geteuid() != ps->target_uid) {
        if (_thread_set_euid(ps->target_uid) < 0) {
            fprintf(stderr, "[PortalService] seteuid(%u): %s\n",
                    (unsigned)ps->target_uid, strerror(errno));
            return -errno;
        }
        fprintf(stderr, "[PortalService] Portal thread euid=%u\n", (unsigned)ps->target_uid);
    }

    if (ps->bus_address) {
        r = sd_bus_new(&ps->bus);
        if (r < 0) return r;
        r = sd_bus_set_address(ps->bus, ps->bus_address);
        if (r < 0) return r;
        r = sd_bus_set_bus_client(ps->bus, 1);
        if (r < 0) return r;
        r = sd_bus_start(ps->bus);
        if (r < 0) return r;
    } else {
        r = sd_bus_open_user(&ps->bus);
        if (r < 0) return r;
    }

    r = sd_bus_add_object_vtable(ps->bus, NULL, PORTAL_OBJ_PATH,
                                 SETTINGS_IFACE, settings_vtable, ps);
    if (r < 0) {
        fprintf(stderr, "[PortalService] Failed to register %s: %s\n",
                SETTINGS_IFACE, strerror(-r));
        return r;
    }
    r = sd_bus_add_object_vtable(ps->bus, NULL, PORTAL_OBJ_PATH,
                                 FILECHOOSER_IFACE, filechooser_vtable, ps);
    if (r < 0) {
        fprintf(stderr, "[PortalService] Failed to register %s: %s\n",
                FILECHOOSER_IFACE, strerror(-r));
        return r;
    }
    r = sd_bus_add_object_vtable(ps->bus, NULL, PORTAL_OBJ_PATH,
                                 SCREENCAST_IFACE, screencast_vtable, ps);
    if (r < 0) {
        fprintf(stderr, "[PortalService] Failed to register %s: %s\n",
                SCREENCAST_IFACE, strerror(-r));
        return r;
    }

    // Losing the name is silent otherwise, and looks exactly like "the portal
    // is broken": whoever takes it answers instead, and a stock
    // xdg-desktop-portal that finds no Starling backend answers
    // "No such interface org.freedesktop.portal.FileChooser". The session
    // launchers mask that service so it cannot be activated on our bus; this
    // says so out loud if something claims the name anyway.
    r = sd_bus_match_signal(ps->bus, NULL, "org.freedesktop.DBus",
                            "/org/freedesktop/DBus", "org.freedesktop.DBus",
                            "NameLost", _on_name_lost, ps);
    if (r < 0)
        fprintf(stderr, "[PortalService] NameLost match failed: %s\n", strerror(-r));

    // ALLOW_REPLACEMENT | REPLACE_EXISTING: a restarted shell forcibly takes
    // the name over from a previous instance whose bus connection is still
    // lingering on a persistent session bus, and in turn yields to the next.
    r = sd_bus_request_name(ps->bus, PORTAL_BUS_NAME,
                            SD_BUS_NAME_ALLOW_REPLACEMENT | SD_BUS_NAME_REPLACE_EXISTING);
    if (r < 0) {
        fprintf(stderr, "[PortalService] Failed to claim %s: %s\n",
                PORTAL_BUS_NAME, strerror(-r));
        return r;
    }
    fprintf(stderr, "[PortalService] Claimed %s\n", PORTAL_BUS_NAME);
    return 0;
}

/* Block until the bus, the command pipe, or a helper's exit needs attention.
 *
 * The sd-bus event-loop integration, as documented: take the connection's fd,
 * the events it wants and its next deadline, and poll them yourself alongside
 * everything else the loop cares about. UINT64_MAX from sd_bus_get_timeout
 * means nothing is due, which is the idle case and where the -1 comes from.
 *
 * The notification service has the same loop with one fewer fd -- see
 * shell/Sources/NotificationService/notification_service.c. */
static int _portal_wait(PortalService *ps) {
    int fd = sd_bus_get_fd(ps->bus);
    int events = sd_bus_get_events(ps->bus);
    if (fd < 0 || events < 0) return 0;

    uint64_t deadline_usec = 0;
    if (sd_bus_get_timeout(ps->bus, &deadline_usec) < 0) return 0;

    int timeout_ms = -1;
    if (deadline_usec != UINT64_MAX) {
        struct timespec ts;
        clock_gettime(CLOCK_MONOTONIC, &ts);
        uint64_t now_usec = (uint64_t)ts.tv_sec * 1000000ULL + ts.tv_nsec / 1000;
        timeout_ms = deadline_usec > now_usec
            ? (int)((deadline_usec - now_usec + 999) / 1000)
            : 0;
    }

    struct pollfd fds[2 + MAX_PENDING_REQUESTS];
    int pidfds[MAX_PENDING_REQUESTS];
    int n = 0;
    fds[n].fd = fd;              fds[n].events = (short)events; fds[n++].revents = 0;
    fds[n].fd = ps->pipe_fd[0];  fds[n].events = POLLIN;        fds[n++].revents = 0;

    int npid = 0;
    for (int i = 0; i < MAX_PENDING_REQUESTS; i++) {
        PendingRequest *req = &ps->requests[i];
        if (!req->active || req->child_pid <= 0) continue;
        int pfd = (int)syscall(SYS_pidfd_open, req->child_pid, 0);
        if (pfd < 0) {
            // No pidfd (old kernel, or the child is already gone): fall back
            // to a bounded wait so the reap still happens promptly. Never
            // block indefinitely with a child outstanding.
            timeout_ms = (timeout_ms < 0 || timeout_ms > 200) ? 200 : timeout_ms;
            continue;
        }
        pidfds[npid++] = pfd;
        fds[n].fd = pfd; fds[n].events = POLLIN; fds[n++].revents = 0;
    }

    int r = poll(fds, n, timeout_ms);
    for (int i = 0; i < npid; i++) close(pidfds[i]);
    if (r < 0 && errno != EINTR) return 0;
    return 1;
}

static void *_portal_thread(void *arg) {
    PortalService *ps = arg;
    int r = _setup_bus(ps);

    pthread_mutex_lock(&ps->init_mutex);
    ps->init_result = r;
    ps->init_done = 1;
    pthread_cond_signal(&ps->init_cond);
    pthread_mutex_unlock(&ps->init_mutex);

    if (r < 0) return NULL;

    fprintf(stderr, "[PortalService] Event loop running\n");

    while (ps->running) {
        for (;;) {
            r = sd_bus_process(ps->bus, NULL);
            if (r <= 0) break;
        }

        // Check pipe commands
        {
            uint8_t cmd;
            while (read(ps->pipe_fd[0], &cmd, 1) == 1) {
                if (cmd == CMD_SETTINGS_CHANGED) {
                    pthread_mutex_lock(&ps->mutex);
                    if (ps->settings_color_scheme_changed) {
                        ps->settings_color_scheme_changed = 0;
                        pthread_mutex_unlock(&ps->mutex);
                        _emit_setting_changed(ps, "color-scheme");
                    } else if (ps->settings_accent_color_changed) {
                        ps->settings_accent_color_changed = 0;
                        pthread_mutex_unlock(&ps->mutex);
                        _emit_setting_changed(ps, "accent-color");
                    } else if (ps->settings_contrast_changed) {
                        ps->settings_contrast_changed = 0;
                        pthread_mutex_unlock(&ps->mutex);
                        _emit_setting_changed(ps, "contrast");
                    } else {
                        pthread_mutex_unlock(&ps->mutex);
                    }
                } else if (cmd == CMD_COMPLETE_REQUEST) {
                    _drain_completions(ps);
                } else if (cmd == CMD_SCREENCAST_COMPLETE) {
                    _drain_scast_completion(ps);
                } else if (cmd == CMD_SHUTDOWN) {
                    goto done;
                }
            }
        }

        // Check if any file chooser helper exited
        _check_children(ps);

        // Wait on the bus, the command pipe, and any running helper, for as
        // long as sd-bus says nothing is due.
        //
        // This used to be `sd_bus_wait(bus, 200ms)`, which watches only the
        // bus fd. The other two things this loop must notice -- a command
        // from the shell, and a file-chooser helper exiting -- had no way in,
        // so the 200 ms cap stood in for both: five wakeups a second forever,
        // on a desktop where nobody is opening a file dialog. Both have a
        // real event. The command pipe is an fd already; a helper's exit
        // becomes one through pidfd_open, which is readable exactly when the
        // process dies. (Its STDOUT would be the tempting fd to poll and is
        // the wrong one: the helper writes its answer before exiting, so a
        // readable stdout would wake this loop into a waitpid that says
        // "still running", over and over, as fast as poll can return.)
        if (!_portal_wait(ps)) break;
    }

done:
    fprintf(stderr, "[PortalService] Event loop exited\n");
    return NULL;
}

// ============================================================================
// Public API
// ============================================================================

PortalService *portal_service_create(void) {
    PortalService *ps = calloc(1, sizeof(PortalService));
    if (!ps) return NULL;
    ps->pipe_fd[0] = ps->pipe_fd[1] = -1;
    ps->color_scheme = 1;  // dark
    pthread_mutex_init(&ps->mutex, NULL);
    return ps;
}

void portal_service_destroy(PortalService *ps) {
    if (!ps) return;
    portal_service_stop(ps);
    if (ps->pipe_fd[0] >= 0) close(ps->pipe_fd[0]);
    if (ps->pipe_fd[1] >= 0) close(ps->pipe_fd[1]);
    free(ps->bus_address);
    free(ps->chooser_command);
    pthread_mutex_destroy(&ps->mutex);
    pthread_mutex_destroy(&ps->init_mutex);
    pthread_cond_destroy(&ps->init_cond);
    free(ps);
}

int portal_service_start(PortalService *ps, const char *bus_address, unsigned int target_uid) {
    if (pipe(ps->pipe_fd) < 0) return -errno;
    int flags = fcntl(ps->pipe_fd[0], F_GETFL, 0);
    fcntl(ps->pipe_fd[0], F_SETFL, flags | O_NONBLOCK);

    ps->bus_address = bus_address ? strdup(bus_address) : NULL;
    ps->target_uid = (uid_t)target_uid;
    ps->init_done = 0;
    pthread_mutex_init(&ps->init_mutex, NULL);
    pthread_cond_init(&ps->init_cond, NULL);

    ps->running = 1;
    int r = pthread_create(&ps->thread, NULL, _portal_thread, ps);
    if (r != 0) { ps->running = 0; return -r; }

    pthread_mutex_lock(&ps->init_mutex);
    while (!ps->init_done)
        pthread_cond_wait(&ps->init_cond, &ps->init_mutex);
    r = ps->init_result;
    pthread_mutex_unlock(&ps->init_mutex);

    if (r < 0) { pthread_join(ps->thread, NULL); ps->running = 0; return r; }
    return 0;
}

void portal_service_stop(PortalService *ps) {
    if (!ps || !ps->running) return;
    _send_cmd(ps, CMD_SHUTDOWN);
    pthread_join(ps->thread, NULL);
    ps->running = 0;

    // The portal thread is gone, so this thread is the only one touching
    // the bus now; tell the session's client it is over.
    _scast_teardown(ps, 1);

    for (int i = 0; i < MAX_PENDING_REQUESTS; i++) {
        if (ps->requests[i].active) {
            if (ps->requests[i].child_pid > 0)
                kill(ps->requests[i].child_pid, SIGTERM);
            if (ps->requests[i].stdout_fd >= 0)
                close(ps->requests[i].stdout_fd);
            sd_bus_slot_unref(ps->requests[i].slot);
            ps->requests[i].active = 0;
        }
    }
    sd_bus_release_name(ps->bus, PORTAL_BUS_NAME);
    sd_bus_unref(ps->bus);
    ps->bus = NULL;
}

void portal_service_set_file_chooser_command(PortalService *ps, const char *path) {
    pthread_mutex_lock(&ps->mutex);
    free(ps->chooser_command);
    ps->chooser_command = path ? strdup(path) : NULL;
    pthread_mutex_unlock(&ps->mutex);
}

void portal_service_set_chooser_launcher(PortalService *ps,
                                          portal_launch_chooser_fn launcher,
                                          void *userdata) {
    pthread_mutex_lock(&ps->mutex);
    ps->chooser_launcher = launcher;
    ps->chooser_launcher_userdata = userdata;
    pthread_mutex_unlock(&ps->mutex);
}

void portal_service_complete_request(PortalService *ps, const char *handle,
                                     const char *const *uris, int num_uris,
                                     unsigned int response) {
    if (!ps || !handle) return;

    CompletionMsg *msg = calloc(1, sizeof(CompletionMsg));
    if (!msg) return;
    snprintf(msg->handle, sizeof(msg->handle), "%s", handle);
    msg->response = response;
    if (response == 0 && num_uris > 0 && uris) {
        msg->uris = calloc((size_t)num_uris, sizeof(char *));
        if (msg->uris) {
            for (int i = 0; i < num_uris; i++)
                msg->uris[i] = strdup(uris[i] ? uris[i] : "");
            msg->num_uris = num_uris;
        }
    }

    pthread_mutex_lock(&ps->mutex);
    int queued = 0;
    for (int i = 0; i < MAX_PENDING_REQUESTS; i++) {
        if (!ps->completions[i]) { ps->completions[i] = msg; queued = 1; break; }
    }
    pthread_mutex_unlock(&ps->mutex);

    if (!queued) {
        for (int i = 0; i < msg->num_uris; i++) free(msg->uris[i]);
        free(msg->uris);
        free(msg);
        return;
    }
    _send_cmd(ps, CMD_COMPLETE_REQUEST);
}

void portal_service_set_screencast_hooks(PortalService *ps,
                                         portal_screencast_start_fn start,
                                         portal_screencast_stop_fn stop,
                                         void *userdata) {
    pthread_mutex_lock(&ps->mutex);
    ps->scast_start = start;
    ps->scast_stop = stop;
    ps->scast_userdata = userdata;
    pthread_mutex_unlock(&ps->mutex);
}

void portal_service_complete_screencast_start(PortalService *ps,
                                              const char *handle,
                                              uint32_t node_id,
                                              uint32_t width, uint32_t height,
                                              unsigned int response) {
    if (!ps || !handle) return;
    pthread_mutex_lock(&ps->mutex);
    snprintf(ps->scast_completion.handle, sizeof(ps->scast_completion.handle),
             "%s", handle);
    ps->scast_completion.node_id = node_id;
    ps->scast_completion.width = width;
    ps->scast_completion.height = height;
    ps->scast_completion.response = response;
    ps->scast_completion.pending = 1;
    pthread_mutex_unlock(&ps->mutex);
    _send_cmd(ps, CMD_SCREENCAST_COMPLETE);
}

void portal_service_set_color_scheme(PortalService *ps, uint32_t scheme) {
    pthread_mutex_lock(&ps->mutex);
    ps->color_scheme = scheme;
    ps->settings_color_scheme_changed = 1;
    pthread_mutex_unlock(&ps->mutex);
    _send_cmd(ps, CMD_SETTINGS_CHANGED);
}

void portal_service_set_accent_color(PortalService *ps, double r, double g, double b) {
    pthread_mutex_lock(&ps->mutex);
    ps->accent_r = r; ps->accent_g = g; ps->accent_b = b;
    ps->settings_accent_color_changed = 1;
    pthread_mutex_unlock(&ps->mutex);
    _send_cmd(ps, CMD_SETTINGS_CHANGED);
}

void portal_service_set_contrast(PortalService *ps, uint32_t contrast) {
    pthread_mutex_lock(&ps->mutex);
    ps->contrast = contrast;
    ps->settings_contrast_changed = 1;
    pthread_mutex_unlock(&ps->mutex);
    _send_cmd(ps, CMD_SETTINGS_CHANGED);
}
