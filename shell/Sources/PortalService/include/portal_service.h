// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// portal_service.h — XDG Desktop Portal service (Settings + FileChooser)
//
// Implements org.freedesktop.portal.Desktop on the D-Bus session bus,
// replacing xdg-desktop-portal for the Flutter desktop shell.
// Uses libsystemd sd-bus. Runs its own event loop on a background thread.
//
// Settings: returns shell appearance preferences directly.
// FileChooser: launches a helper process (FileExplorerApp --picker) as a
//   Wayland client window. Reads selected file:// URIs from its stdout,
//   sends D-Bus Response signal.

#ifndef PORTAL_SERVICE_H
#define PORTAL_SERVICE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct PortalService PortalService;

// --- Lifecycle ---

PortalService *portal_service_create(void);
void portal_service_destroy(PortalService *ps);

/// Start the portal service on a background thread.
/// bus_address: D-Bus session bus address (e.g. "unix:path=/run/user/1000/bus").
///              If NULL, uses DBUS_SESSION_BUS_ADDRESS env var or sd-bus default.
/// target_uid: UID to seteuid() to before connecting (for root → user bus).
///             Pass 0 to skip privilege change.
/// Returns 0 on success, negative errno on error.
int portal_service_start(PortalService *ps, const char *bus_address, unsigned int target_uid);

/// Stop the service and join the background thread.
void portal_service_stop(PortalService *ps);

/// Set the path to the file chooser helper executable.
/// When a FileChooser request arrives, this binary is launched with --picker
/// and environment variables for parameters. It must print selected file://
/// URIs to stdout (one per line) and exit 0 on success, 1 on cancel.
void portal_service_set_file_chooser_command(PortalService *ps, const char *path);

/// Callback to launch the file chooser as a managed app (e.g. via DMA-BUF
/// compositor). Called on the portal thread. It should start the helper
/// (composited window) and return immediately: 0 if the launch is under way
/// (the result is delivered later via portal_service_complete_request with
/// this same `handle`), or negative on failure. Because completion is async,
/// the launcher does NOT return a pid/stdout fd — the portal never reaps or
/// reads the helper, avoiding a double-owner over the child process.
typedef int (*portal_launch_chooser_fn)(
    void *userdata,
    const char *handle,          // request object path — echo back in completion
    const char *executable,      // path to helper binary
    int caller_pid,              // the D-Bus client that asked (see below)
    const char *title,
    int multiple,
    int directory,
    int save_mode,
    const char *current_folder,
    const char *accept_label,
    const char *suggested_name
);

/// `caller_pid` is the process that made the D-Bus call, from the kernel's own
/// peer credentials. It exists so the shell can decide WHOSE dialog this is:
/// a chooser opened by an agent's browser has to land in that agent's
/// workspace, where the agent can drive it, rather than appearing on the
/// human's desktop where it blocks the agent forever and shows the human's
/// files to a window they never asked for. 0 when the bus will not say.

/// Set a custom launcher for the file chooser helper. If set, this async
/// launcher is used instead of the built-in fork/exec+stdout-reap path.
void portal_service_set_chooser_launcher(
    PortalService *ps,
    portal_launch_chooser_fn launcher,
    void *userdata
);

/// Deliver the result of an async chooser launch (see portal_launch_chooser_fn).
/// Thread-safe — may be called from any thread; the D-Bus Response is emitted
/// on the portal thread. `handle` is the value passed to the launcher.
/// response: 0 = success (uris used), 1 = cancelled, 2 = error.
/// The uris array and its strings are copied; the caller retains ownership.
void portal_service_complete_request(
    PortalService *ps,
    const char *handle,
    const char *const *uris,
    int num_uris,
    unsigned int response
);

// --- Settings (org.freedesktop.portal.Settings) ---

void portal_service_set_color_scheme(PortalService *ps, uint32_t scheme);
void portal_service_set_accent_color(PortalService *ps, double r, double g, double b);
void portal_service_set_contrast(PortalService *ps, uint32_t contrast);

// --- ScreenCast (org.freedesktop.portal.ScreenCast) ---
//
// One session at a time: the shell has one screen and one capture
// pipeline, and a new CreateSession replaces (and Closes) the previous
// session. Start is asynchronous like the file chooser: the hook returns
// immediately and the shell later delivers the PipeWire node through
// portal_service_complete_screencast_start.

/// Start the capture and stand up the PipeWire stream. Portal thread.
/// Return 0 if the start is under way (complete later with `handle`),
/// negative to fail the request immediately.
typedef int (*portal_screencast_start_fn)(void *userdata, const char *handle);

/// The session ended (client Closed it, or a new session replaced it).
/// Portal thread. Stop the capture and free the stream.
typedef void (*portal_screencast_stop_fn)(void *userdata);

void portal_service_set_screencast_hooks(PortalService *ps,
                                         portal_screencast_start_fn start,
                                         portal_screencast_stop_fn stop,
                                         void *userdata);

/// Deliver the result of an async ScreenCast start. Thread-safe.
/// response: 0 = success (node_id/width/height describe the live stream),
/// 2 = the capture could not start.
void portal_service_complete_screencast_start(PortalService *ps,
                                              const char *handle,
                                              uint32_t node_id,
                                              uint32_t width, uint32_t height,
                                              unsigned int response);

#ifdef __cplusplus
}
#endif

#endif // PORTAL_SERVICE_H
