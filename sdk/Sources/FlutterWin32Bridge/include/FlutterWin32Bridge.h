// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// The Win32 host for a FlutterSwift app: the engine's real Windows embedder
// (flutter_windows.dll — the view controller, input, IME, a11y) inside an
// ordinary top-level window, with the engine started in Swift mode so the
// Swift framework drives frames instead of a Dart isolate.
//
// This header is the whole Swift-visible surface. <windows.h> and the
// flutter_windows types stay behind it — the C glue includes them, the
// C++-interop importer never sees them. That matters more here than on Linux:
// windows.h defines several thousand macros, and letting it reach the importer
// collides with ordinary Swift names.

#ifndef FLUTTER_WIN32_BRIDGE_H
#define FLUTTER_WIN32_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct FlWin32Host FlWin32Host;

// Registers the window class, creates the top-level window and the engine,
// puts the engine into Swift mode with `runtime_controller` (a
// SwiftRuntimeCallbacks*, which must outlive the host), and creates the view
// controller — which is what starts the engine.
//
// `title` is UTF-8 and is converted to UTF-16 internally.
//
// Returns NULL if the window or the engine could not be created; the reason
// lands on stderr.
FlWin32Host* flwin32_host_create(const char* title,
                                 int32_t width,
                                 int32_t height,
                                 const void* runtime_controller);

// Borrows the launching console, if the app was launched from one.
//
// A GUI-subsystem binary (which is what an app with a window should be —
// see the /SUBSYSTEM:WINDOWS note in the app's Package.swift) starts with no
// console, so `printf` and Swift's `print` go nowhere. Run from a shell that
// is a problem; run from Explorer it is the entire point. This resolves both:
// attach to the parent's console when there is one, leave a redirected stream
// alone, and do nothing at all under Explorer.
//
// Call once, before anything prints. Safe to call from a console-subsystem
// build, where it returns immediately.
// Process-wide setup that must happen before ANYTHING asks Windows about the
// display: per-monitor DPI awareness. Until it runs, a 4K screen at 200%
// reports itself as 1920x1080 at 96 dpi and every derived number is wrong by
// the scale factor — plausibly, not obviously. Call once, first.
void flwin32_process_init(void);

void flwin32_attach_parent_console(void);

// Shows the window.
void flwin32_host_show(FlWin32Host* host);

// Runs the Win32 message loop (with the GCD main queue drained on a timer so
// @MainActor / DispatchQueue.main work). Returns when the window is closed.
void flwin32_host_run(FlWin32Host* host);

// Fullscreens or restores the window.
void flwin32_host_set_fullscreen(FlWin32Host* host, int32_t fullscreen);

// Shell chrome. `edge` is 0=top 1=bottom 2=left 3=right; `monitor` is an
// index into flwin32_monitor_rect, or -1 for the primary.
//
// `thickness` is in LOGICAL POINTS, not pixels: it is multiplied by the
// target monitor's scale here, and re-derived on every WM_DPICHANGED. A bar
// asking for 44 is 44px at 100% and 88px at 200%, and its widget tree sees
// 44 either way. Pixels would have been the smaller change and are wrong on
// exactly the machines this has to look right on.
//
// `takes_focus` = 0 gives the window WS_EX_NOACTIVATE, which is what makes it
// chrome: clicking it does not move the keyboard away from whatever the user
// was typing in. Pass non-zero only for a panel that has a text field.
//
// `transparent` makes anything the tree paints as pure black disappear, and
// lets clicks there fall through — how a dock floats over the wallpaper
// instead of sitting in a black strip. It costs the ability to paint true
// black in that panel.
//
// `overhang` (logical points) makes the WINDOW extend that much further in
// from the edge than the strip it reserves. A dock needs it to draw above
// itself — a hover label, a right-click menu — because a window is a hard
// clip. It is transparent and click-through until something paints there.
// Moves an existing panel to another edge at runtime. The window changes
// shape, so the tree is expected to lay itself out differently.
void flwin32_host_move_panel(FlWin32Host* host, int32_t edge);

void flwin32_host_set_panel(FlWin32Host* host,
                            int32_t edge,
                            int32_t thickness,
                            int32_t monitor,
                            int32_t takes_focus,
                            int32_t transparent,
                            int32_t overhang);

// Register (or remove) the window as an appbar, so Windows reserves the strip
// and maximized windows stop at it. Call after flwin32_host_set_panel, which
// is where the edge and thickness come from. Returns non-zero on success.
int32_t flwin32_host_set_appbar(FlWin32Host* host, int32_t enable);

// ── network adapters, for the Settings app ──────────────────────────────────
//
// The whole enumeration, unlike flwin32_network_status which answers "am I
// online" from the first thing that is up. Reads only: changing an address or
// an adapter's state needs administrator rights, so the page hands those to
// Windows rather than putting up controls that fail.

int32_t flwin32_adapter_count(void);

// kind: 0 other, 1 ethernet, 2 wifi. speed is bits/second.
int32_t flwin32_adapter_info(int32_t index,
                             char* name, int32_t name_size,
                             char* description, int32_t description_size,
                             char* ipv4, int32_t ipv4_size,
                             char* gateway, int32_t gateway_size,
                             char* dns, int32_t dns_size,
                             char* mac, int32_t mac_size,
                             int32_t* kind, int32_t* up,
                             int64_t* speed, int32_t* dhcp);

int32_t flwin32_open_network_settings(void);

// ── files ───────────────────────────────────────────────────────────────────

// A known folder by index: 0 profile, 1 desktop, 2 documents, 3 downloads,
// 4 pictures, 5 music, 6 videos, 7 recent. SHGetKnownFolderPath, so a relocated folder
// is followed rather than guessed at under %USERPROFILE%.
int32_t flwin32_known_path(int32_t which, char* out, int32_t out_size);

// What Explorer's Type column says for this path's extension. Answers from
// the association database without touching the disk.
int32_t flwin32_file_type_name(const char* path, char* out, int32_t out_size);

// The friendly name of whatever opens this file — "Notepad", "Paint". Empty
// when the type has no handler.
int32_t flwin32_default_app_name(const char* path, char* out, int32_t out_size);

// The shell's own "Open with" dialog, which is the ONLY supported way for the
// default handler to change: since Windows 8 an application cannot write the
// association itself. BLOCKS — background thread only.
int32_t flwin32_open_with_dialog(const char* path);

// The user's display name, falling back to the account name — which on a
// local account with no display name set is the usual answer, not an error.
int32_t flwin32_user_display_name(char* out, int32_t out_size);

// Hands the folder to Windows' own Explorer.
int32_t flwin32_open_in_explorer(const char* path);

// Opens Starling's Settings surface, or raises the one already open.
void flwin32_shell_open_settings(void);

// Opens Starling's file explorer, or raises the one already open.
void flwin32_shell_open_files(void);

// -- the shell's own context menu, asked for off the drawing thread ---------
//
// What Explorer puts in a right-click: the static verbs from the association
// database plus every registered IContextMenu handler -- OneDrive, Defender,
// an archiver, "Copy as path", "Properties". Measured, assembling that set
// costs Explorer 370ms and it draws NOTHING until the slowest handler has
// answered. So a session here is a thread: open() returns at once, items()
// blocks whoever asks until the shell is done, and the caller draws its own
// verbs meanwhile. See flwin32_shellmenu.c.
//
// Every call below must come from ONE thread at a time -- they are a
// ping-pong with the session's thread, not re-entrant.

// One row. `id` is what invoke() takes, or -1 for a separator or a submenu;
// `submenu` is a token for expand(), or 0. `verb` is the canonical name
// ("open", "copy", "properties") and is empty for the many handlers that do
// not publish one -- it exists so a caller can tell that the shell's Open is
// the Open it has already drawn itself.
#define FLWIN32_SHELLMENU_MAX 128

typedef struct FlWin32ShellVerb {
    int32_t id;
    int32_t submenu;
    int32_t is_separator;
    int32_t is_submenu;
    int32_t is_enabled;
    int32_t is_default;
    char label[128];
    char verb[64];
} FlWin32ShellVerb;

typedef struct FlWin32ShellMenu FlWin32ShellMenu;

// Starts a session for one path. `background` asks for the FOLDER's menu --
// what a right-click on empty space gets, and where "New" and "Paste" live --
// rather than the item's. `extended` is Shift+right-click (CMF_EXTENDEDVERBS).
// `owner` is the window any dialog a verb opens will be parented to. Returns
// immediately; nothing is queried yet.
FlWin32ShellMenu* flwin32_shellmenu_open(const char* path,
                                         int32_t background,
                                         int32_t extended,
                                         uint64_t owner);

// The top-level rows. BLOCKS until the shell has answered -- background
// thread only, which is the entire point of the session. -1 if the menu could
// not be built at all.
int32_t flwin32_shellmenu_items(FlWin32ShellMenu* menu, FlWin32ShellVerb* out,
                                int32_t max);

// The rows inside a submenu, by the token from `submenu`. A submenu arrives
// EMPTY and is populated by the WM_INITMENUPOPUP its handler is waiting for,
// so this is not a read -- it is work, and it BLOCKS.
int32_t flwin32_shellmenu_expand(FlWin32ShellMenu* menu, int32_t token,
                                 FlWin32ShellVerb* out, int32_t max);

// Runs a verb, on the session's thread and in its apartment. BLOCKS for as
// long as the verb does, which for one that opens a dialog is until the
// dialog is answered.
int32_t flwin32_shellmenu_invoke(FlWin32ShellMenu* menu, int32_t id);

// Where the assembly's time went, in milliseconds: binding the shell item and
// creating the IContextMenu (which is also when handler DLLs load cold),
// QueryContextMenu itself, walking the resulting HMENU, and -- inside that
// walk -- the per-row GetCommandString calls, which are calls into the
// handlers and are counted separately because they are not free. For the
// probe; a menu that is only being drawn has no use for them.
void flwin32_shellmenu_timings(FlWin32ShellMenu* menu, double* bind, double* query,
                               double* walk, double* verbs);

// WHICH HANDLER is costing the time inside QueryContextMenu.
//
// The stage timings above say QueryContextMenu is 84-99% of the assembly, and
// that is where the answer stops being useful: QueryContextMenu is a loop over
// every shell extension registered for the item, and nothing reports a
// per-handler cost. So this runs the shell's own loop by hand -- registry ->
// CoCreateInstance -> IShellExtInit::Initialize -> QueryContextMenu, one at a
// time, with a clock around each. Read-only, diagnostic, --menu-handlers only.
//
// The static verbs (registry `shell\<verb>\command` entries -- Open, Edit,
// "Open with Visual Studio") are the shell's own work rather than a handler's,
// so they are not in this table; the gap between its total and the monolithic
// figure is them.
typedef struct FlWin32HandlerCost {
    char key[80];       // "AllFilesystemObjects\FileSyncEx"
    char clsid[48];
    char dll[96];       // the leaf of InprocServer32 -- who this actually is
    double create_ms;   // CoCreateInstance, which is where a cold DLL loads
    double init_ms;     // IShellExtInit::Initialize
    double query_ms;    // the handler's own QueryContextMenu
    int32_t items;      // how many rows it contributed
    int32_t failed;     // no IContextMenu, or would not instantiate
} FlWin32HandlerCost;

int32_t flwin32_shellmenu_handler_costs(const char* path,
                                        FlWin32HandlerCost* out,
                                        int32_t max);

// THE VERBS THAT COST NOTHING TO FIND: the static registry ones
// (`HKCR\<class>\shell\<verb>\command`), read directly rather than waited for.
// Open, Edit, Print, "Open Git Bash here" and "Open with Visual Studio" are
// all of this kind; none of them instantiates anything. The expensive half of
// a menu is the COM handlers, which this deliberately does not touch.
typedef struct FlWin32StaticVerb {
    char verb[64];    // the key name -- "open", "runas", "AnyCode"
    char label[128];  // MUIVerb resolved where there is one
    char source[64];  // which class it came from, for ordering
} FlWin32StaticVerb;

int32_t flwin32_static_verbs(const char* path, FlWin32StaticVerb* out,
                             int32_t max);

// Ends the session and releases the handlers. Safe while the query is still
// running; blocks until the thread is gone.
void flwin32_shellmenu_close(FlWin32ShellMenu* menu);

// ── system information, for the Settings app ────────────────────────────────
//
// Reads are cheap but not free (registry, WMI-free adapter enumeration); the
// display and wallpaper WRITES talk to the whole desktop. None of it belongs
// on the UI thread.

int32_t flwin32_os_name(char* out, int32_t out_size);
int32_t flwin32_os_build(char* out, int32_t out_size);
int32_t flwin32_device_name(char* out, int32_t out_size);
int32_t flwin32_cpu_name(char* out, int32_t out_size);
int32_t flwin32_cpu_cores(void);
int64_t flwin32_total_ram(void);
int64_t flwin32_available_ram(void);
int32_t flwin32_gpu_name(char* out, int32_t out_size);

int32_t flwin32_display_current(int32_t* width, int32_t* height, int32_t* refresh);
// Distinct width/height/refresh triples into `out` (3 ints each). Returns the
// count.
int32_t flwin32_display_modes(int32_t* out, int32_t max_modes);
int32_t flwin32_display_set(int32_t width, int32_t height, int32_t refresh);

// Fixed drives: letters as "C\0D\0...", plus total and free bytes.
int32_t flwin32_drives(char* letters, int32_t letters_size,
                       int64_t* totals, int64_t* frees, int32_t max_drives);

int32_t flwin32_power_scheme(char* out, int32_t out_size);

// The shell's open dialog, for picking a wallpaper. BLOCKS until answered —
// never from the UI thread.
int32_t flwin32_pick_image(char* out, int32_t out_size);

int32_t flwin32_set_wallpaper(const char* path);
int32_t flwin32_get_wallpaper(char* out, int32_t out_size);

// ── ending the session ──────────────────────────────────────────────────────

#define FLWIN32_SESSION_LOCK      0
#define FLWIN32_SESSION_SIGN_OUT  1
#define FLWIN32_SESSION_SLEEP     2
#define FLWIN32_SESSION_RESTART   3
#define FLWIN32_SESSION_SHUT_DOWN 4

// Whether this account may power the machine off — SE_SHUTDOWN_NAME can be
// enabled. Every process HAS the privilege and none has it enabled, so this
// both answers the question and does the enabling.
int32_t flwin32_session_can_power_off(void);

// Does it. Returns 0 if the call was refused; if it succeeds, the session is
// already going away.
int32_t flwin32_session_action(int32_t action);

// ── startup tracing ─────────────────────────────────────────────────────────

// Milliseconds since the PROCESS was created, so the figure includes image
// loading. Enabled by STARLING_TRACE=1; flwin32_trace is a no-op otherwise.
double flwin32_uptime_ms(void);
// The performance counter in milliseconds — the one clock every process on
// the machine agrees on, so a posted message can be timed across processes.
double flwin32_qpc_ms(void);

void flwin32_trace(const char* label);

// ── overlays ────────────────────────────────────────────────────────────────
//
// A full-screen surface that is usually not there: the launcher, and later
// Mission Control. Unlike a panel it covers the monitor, reserves nothing,
// TAKES focus, and spends most of its life hidden — hidden rather than not
// running, because starting an engine takes about a second and a launcher has
// to appear the instant it is asked for.
//
// `alpha` is the whole surface's opacity, 0-255; -1 keeps the current one.
// A full-screen overlay when width/height are 0, otherwise a floating panel
// of that size IN POINTS, centred horizontally and sitting `margin_pt` above
// the bottom of the monitor's WORK AREA — which the dock's appbar already
// shortened, so the panel clears the dock without knowing how tall it is.
void flwin32_host_set_overlay(FlWin32Host* host, int32_t monitor, int32_t alpha,
                              int32_t width_pt, int32_t height_pt,
                              int32_t margin_pt);
void flwin32_host_set_visible(FlWin32Host* host, int32_t visible);
int32_t flwin32_host_is_visible(FlWin32Host* host);

// Cross-process toggle. The bar and the launcher are separate processes (the
// framework mounts one widget root per process), so a click on the bar
// reaches the launcher as a broadcast of a registered window message — the
// documented way for unrelated processes to talk with no socket or pipe.
// Rasterize now, visible or not — so a hidden overlay can be brought up to
// date before it is shown.
// The host's top-level window, for calls that need an HWND (thumbnails).
uint64_t flwin32_host_window(FlWin32Host* host);

// The client area in LOGICAL POINTS, for a tree that has to lay something out
// against its own window rather than against the screen. 0 if it cannot be
// read.
int32_t flwin32_host_client_size(FlWin32Host* host, int32_t* width,
                                 int32_t* height);

void flwin32_host_request_redraw(FlWin32Host* host);

void flwin32_host_on_toggle(FlWin32Host* host,
                            void (*callback)(void* user),
                            void* user);
void flwin32_shell_broadcast_toggle(void);

// ── the Windows key ─────────────────────────────────────────────────────────
//
// A bare tap of either Windows key, turned into `callback`. Every Win+<key>
// combination is left alone — the keydown is never swallowed, so the system's
// own shortcut table keeps working without us knowing what is in it.
//
// Must be called on the thread that pumps the message loop: a WH_KEYBOARD_LL
// hook is called back on the thread that installed it, and the callback is
// posted to a message-only window so it runs on the loop rather than inside
// the hook (a hook that overruns LowLevelHooksTimeout is silently removed).
// Returns non-zero if the hook is installed.
int32_t flwin32_winkey_capture(void (*callback)(void* user), void* user);
void flwin32_winkey_release(void);

// ── the notification area ───────────────────────────────────────────────────
//
// Hosting the tray means BEING the window Shell_NotifyIcon looks up: a window
// of class "Shell_TrayWnd". Nothing registers and nothing is granted — the
// class name is the whole contract — so `start` takes it from explorer, whose
// taskbar the shell has already hidden, and `stop` gives it back.
//
// There is no way to enumerate the icons that already exist. Starting
// broadcasts "TaskbarCreated", which every app is obliged to answer by
// re-adding its own; that is the only way in, and it is why the tray fills up
// over a second or two rather than at once.
//
// `changed` is called on the UI thread whenever the set changes; the shell
// then asks for a fresh list. See flwin32_tray.c for the wire format and for
// what else arrives on the same channel.
int32_t flwin32_tray_start(void (*changed)(void* user), void* user);
void flwin32_tray_stop(void);

// A snapshot. Icons in it are copies owned by the list, so the shell can take
// as long as it likes rasterizing them while apps carry on changing theirs.
typedef struct FlWin32TrayList FlWin32TrayList;
FlWin32TrayList* flwin32_tray_list(void);
void flwin32_tray_list_free(FlWin32TrayList* list);
int32_t flwin32_tray_list_count(FlWin32TrayList* list);
// Stable for as long as the icon exists — identity for the shell, since
// neither the window nor the id is dependable (an icon registered with a GUID
// sends its later changes with no window and no id at all).
uint64_t flwin32_tray_list_key(FlWin32TrayList* list, int32_t index);
// An HICON belonging to the list. Rasterize it with flwin32_icon_rasterize_handle.
uint64_t flwin32_tray_list_icon(FlWin32TrayList* list, int32_t index);
// Whether WINDOWS' own setting puts this icon on the bar rather than behind
// the chevron (HKCU\Control Panel\NotifyIconSettings). A new icon nobody has
// promoted is hidden — that is Windows 11's default, not an omission.
int32_t flwin32_tray_list_promoted(FlWin32TrayList* list, int32_t index);
// Bumped every time the icon's picture changes while its identity does not —
// an app showing sync progress or an unread badge redraws constantly. A cache
// keyed on the key alone would show the first frame forever.
uint32_t flwin32_tray_list_generation(FlWin32TrayList* list, int32_t index);
// Takes the icon OUT of the list: the caller owns it now and must destroy it
// with flwin32_icon_destroy. For handing one to a background thread that will
// outlive the snapshot.
uint64_t flwin32_tray_list_take_icon(FlWin32TrayList* list, int32_t index);
int32_t flwin32_tray_list_tip(FlWin32TrayList* list, int32_t index, char* out,
                              int32_t out_size);

// Tells the icon's owner the mouse was over it: button 0 left, 1 right,
// 2 middle. The position it is told is the CURSOR's, which is the icon's —
// the pointer is on the icon, because that is what a click is.
void flwin32_tray_click(uint64_t key, int32_t button);

// Moves whenever the icon set or the promoted/hidden split changes. Poll it —
// the user promotes and demotes icons in Windows' own Settings, which tells
// the shell nothing — and take a fresh list only when it moves. The registry
// read behind it is throttled, so calling this on a one-second tick is cheap.
uint64_t flwin32_tray_revision(void);

// Asks every app to re-add its icon, by broadcasting "TaskbarCreated". The
// only way to repopulate a notification area — needed after a shell that was
// KILLED rather than closed, which leaves every icon registered to a window
// that no longer exists and a tray that nothing will refill on its own.
void flwin32_tray_reannounce(void);

// A diagnostic: takes the class, prints every message that arrives for
// `seconds` with the wire bytes decoded, then hands it back. This is how the
// format above was established and how to re-check it on a new Windows build.
void flwin32_tray_probe(int32_t seconds);

int32_t flwin32_monitor_count(void);
int32_t flwin32_monitor_rect(int32_t index,
                             int32_t* x,
                             int32_t* y,
                             int32_t* width,
                             int32_t* height,
                             int32_t* primary);
// The monitor's DPI, where 96 is 100%. Falls back to 96 rather than failing:
// a wrong scale draws a bar at the wrong size, no scale at all draws nothing.
int32_t flwin32_monitor_dpi(int32_t index);

// Clipboard. Text is UTF-8 on this boundary and converted to/from UTF-16
// inside, so the Swift side never handles wide strings.
//
// Unlike the Wayland and GTK backends this is synchronous: Win32 hands over
// the data itself rather than asking the current owner to write it, so there
// is nothing to wait on and no way for another process to stall a paste.

// Puts UTF-8 `text` on the clipboard. Returns 1 on success.
int32_t flwin32_clipboard_set_text(const char* text);

// Reads the clipboard as UTF-8 into `out`. Returns the number of bytes
// written including the terminator, 0 when the clipboard holds no text, or
// -1 if `out` is too small (retry with a larger buffer).
int32_t flwin32_clipboard_get_text(char* out, int32_t out_size);

// ── window management ───────────────────────────────────────────────────────
//
// Starling on Windows cannot own other people's pixels — DWM is not
// replaceable — so it manages their windows instead: enumerate them, move
// them, raise them, and watch them come and go. This is the half of the port
// that stands in for the compositor, and everything below is plain user32.
//
// The window LIST is a snapshot object rather than a callback or an array of
// structs: enumerating twice (once to count, once to fill) races against
// windows opening, and a struct carrying fixed-size char arrays imports into
// Swift as tuples. So enumerate once, hold the result, read scalars and
// strings out of it by index, release it.

typedef struct FlWin32WindowList FlWin32WindowList;

// Scalars for one window in a snapshot. Strings come out separately, through
// flwin32_wm_title / _class / _exe.
typedef struct {
  uint64_t handle;  // the HWND, opaque on this side of the boundary
  uint32_t pid;
  // The VISIBLE frame, in virtual-desktop pixels: DWM's extended frame
  // bounds, not GetWindowRect, which on Windows 10+ includes an invisible
  // resize border ~7px wide on each side. A tiler that uses the raw rect
  // leaves gaps it cannot explain.
  int32_t x;
  int32_t y;
  int32_t width;
  int32_t height;
  int32_t monitor;  // index into flwin32_monitor_rect, or -1
  int32_t minimized;
  int32_t maximized;
  int32_t foreground;
} FlWin32WindowInfo;

// Enumerates the manageable top-level windows — what a taskbar would show.
// Never NULL unless allocation failed. Release with flwin32_wm_release.
FlWin32WindowList* flwin32_wm_snapshot(void);
int32_t flwin32_wm_count(FlWin32WindowList* list);
int32_t flwin32_wm_info(FlWin32WindowList* list,
                        int32_t index,
                        FlWin32WindowInfo* out);
// UTF-8 out, same convention as flwin32_clipboard_get_text: bytes written
// including the terminator, or -1 if `out` is too small.
int32_t flwin32_wm_title(FlWin32WindowList* list,
                         int32_t index,
                         char* out,
                         int32_t out_size);
int32_t flwin32_wm_class(FlWin32WindowList* list,
                         int32_t index,
                         char* out,
                         int32_t out_size);
int32_t flwin32_wm_exe(FlWin32WindowList* list,
                       int32_t index,
                       char* out,
                       int32_t out_size);
void flwin32_wm_release(FlWin32WindowList* list);

// Raises `handle` and gives it the keyboard. Returns non-zero on success.
int32_t flwin32_wm_activate(uint64_t handle);

// Moves and resizes so the VISIBLE frame lands on the given rectangle — the
// DWM correction described above is applied here, so callers can hand this
// the rectangle they actually want covered. Un-maximizes first; a maximized
// window ignores SetWindowPos.
int32_t flwin32_wm_move(uint64_t handle,
                        int32_t x,
                        int32_t y,
                        int32_t width,
                        int32_t height);

// 0 = restore, 1 = minimize, 2 = maximize.
int32_t flwin32_wm_set_state(uint64_t handle, int32_t state);

// Asks the window to close (WM_CLOSE), the way clicking its X does — the
// app may refuse or prompt. Never TerminateProcess.
int32_t flwin32_wm_close(uint64_t handle);

uint64_t flwin32_wm_foreground(void);

// The work area of a monitor: its rectangle minus the taskbar and any
// appbars, i.e. where a tiler should lay windows out. `monitor` is an index
// into flwin32_monitor_rect, or -1 for the primary.
int32_t flwin32_wm_work_area(int32_t monitor,
                             int32_t* x,
                             int32_t* y,
                             int32_t* width,
                             int32_t* height);

// Window-list changes. The event ids:
#define FLWIN32_WM_EVENT_ADDED 1       // a manageable window appeared
#define FLWIN32_WM_EVENT_REMOVED 2     // destroyed or hidden
#define FLWIN32_WM_EVENT_FOREGROUND 3  // focus moved (handle = the new one)
#define FLWIN32_WM_EVENT_TITLE 4       // title changed
#define FLWIN32_WM_EVENT_MOVED 5       // a user drag/resize finished
#define FLWIN32_WM_EVENT_MINIMIZED 6   // minimized or restored

typedef void (*FlWin32WmEventCallback)(int32_t event,
                                       uint64_t handle,
                                       void* user);

// Installs the WinEvent hooks. Delivery is on the thread that calls this,
// through its message loop — so call it from the UI thread, after the host
// exists, and the callback arrives where the widget tree lives.
//
// Deliberately NOT hooked: EVENT_OBJECT_LOCATIONCHANGE, which fires per
// mouse-move for the whole drag and would rebuild the tree hundreds of times
// a second. MOVESIZEEND is the useful edge.
int32_t flwin32_wm_watch(FlWin32WmEventCallback callback, void* user);
void flwin32_wm_unwatch(void);

// ── app icons ───────────────────────────────────────────────────────────────
//
// The other half of a dock: the app's OWN icon rather than a glyph guessed
// from its executable name. Windows keeps it inside the window or inside the
// exe and hands it out as an HICON — a GDI object, not an image — so it has
// to be rasterized.

// Rasterizes `window`'s icon to premultiplied RGBA at `size` x `size`.
// Returns 1 and sets `*out_pixels` to a buffer the caller owns (release it
// with flwin32_icon_free), or 0 when the window has no icon to give.
int32_t flwin32_icon_rasterize(uint64_t window,
                               int32_t size,
                               uint8_t** out_pixels,
                               int32_t* out_width,
                               int32_t* out_height);
// The same, for a file — an .exe, or (usually) a Start Menu .lnk, whose icon
// is a property of the shortcut rather than of what it starts.
int32_t flwin32_icon_rasterize_path(const char* path,
                                    int32_t size,
                                    uint8_t** out_pixels,
                                    int32_t* out_width,
                                    int32_t* out_height);
// Rasterizes an icon handle the caller already has — a tray icon, which
// arrives as a handle and never as a path. Borrows it: the handle is still
// the caller's to destroy.
int32_t flwin32_icon_rasterize_handle(uint64_t icon,
                                      int32_t size,
                                      uint8_t** out_pixels,
                                      int32_t* out_width,
                                      int32_t* out_height);

// ── capturing another window ────────────────────────────────────────────────
//
// A thumbnail of `window`, scaled so its longest side is `max_side`, as
// premultiplied-opaque RGBA the caller owns (release with flwin32_icon_free).
// Returns 0 for a minimized window, one that refused to render, or our own
// surfaces — see flwin32_capture.c for what this can and cannot photograph.
//
// Not free: it asks the window to render itself at full size. Call it when a
// preview opens, not per frame.
int32_t flwin32_capture_window(uint64_t window,
                               int32_t max_side,
                               uint8_t** out_pixels,
                               int32_t* out_width,
                               int32_t* out_height);

// ── live window thumbnails (DwmRegisterThumbnail) ──────────────────────
//
// What the taskbar's own preview is. Unlike flwin32_capture_window these are
// LIVE and cost us nothing -- DWM is already compositing those pixels -- and
// they work for a minimized source, because DWM keeps its last frame.
//
// The price: a thumbnail is not a bitmap. DWM paints it into a rectangle of a
// destination window WE OWN and we never see the pixels, so it cannot go in
// the widget tree. The card draws its chrome; DWM draws the picture on top.
//
// Register once per (destination, source) while a preview is open, place it
// on every layout, unregister when it closes. `dest` must belong to this
// process.
int32_t flwin32_thumb_register(uint64_t dest, uint64_t src, uint64_t* out_handle);

// The destination rectangle is in `dest`'s CLIENT coordinates and PHYSICAL
// pixels -- multiply logical points by the screen scale before calling, or the
// picture lands at half size on a 200% display and is exactly right on a 100%
// one. `client_only` drops the source's own title bar and border.
int32_t flwin32_thumb_place(uint64_t handle,
                            int32_t x,
                            int32_t y,
                            int32_t width,
                            int32_t height,
                            int32_t opacity,
                            int32_t client_only);

int32_t flwin32_thumb_hide(uint64_t handle);
int32_t flwin32_thumb_unregister(uint64_t handle);

// The source's size as DWM knows it, for fitting a thumbnail into a slot
// without distorting it. Takes a registration handle, not a window: there is
// no window-only form of this call.
int32_t flwin32_thumb_source_size(uint64_t handle, int32_t* width, int32_t* height);

// Establishes, on a real machine, whether DWM will composite onto the layered
// colour-keyed window the dock actually is. See flwin32_thumb.c.
void flwin32_thumb_probe(uint64_t src, int32_t seconds);

void flwin32_icon_free(uint8_t* pixels);
// For an icon handle the caller took ownership of (flwin32_tray_list_take_icon).
void flwin32_icon_destroy(uint64_t icon);

// Rasterizes the icon and registers it with the engine as an external
// texture, so a `TextureWidget` can draw it. Returns the texture id, or -1.
// The pixels are held for the texture's lifetime and released when it is
// unregistered — the engine's own release_callback is not used, because the
// buffer is not per-frame.
// Registers pixels rasterized elsewhere (flwin32_icon_rasterize*). Takes
// ownership of the buffer. PLATFORM THREAD ONLY — the rasterizing half is
// what is safe to do off it.
int64_t flwin32_host_register_pixels(FlWin32Host* host,
                                     uint8_t* pixels,
                                     int32_t width,
                                     int32_t height);

int64_t flwin32_host_register_icon_texture(FlWin32Host* host,
                                           uint64_t window,
                                           int32_t size);

// Unregisters a texture from flwin32_host_register_icon_texture and frees its
// pixels. Unregistration is asynchronous inside the engine; the free happens
// in its completion callback, so the buffer outlives any frame still in
// flight.
int64_t flwin32_host_register_icon_texture_path(FlWin32Host* host,
                                                const char* path,
                                                int32_t size);

void flwin32_host_unregister_texture(FlWin32Host* host, int64_t texture_id);

// ── system status ───────────────────────────────────────────────────────────
//
// What a status bar is supposed to show, read from the system rather than
// drawn as decoration. Each comes from a different place and none of them is
// the obvious one — see flwin32_status.c.

// Battery. `present` is 0 on a desktop; `percent` is -1 when Windows will not
// say; `charging` means "on mains", which is what a bar should show even for
// a full battery. Returns non-zero if the status could be read at all.
int32_t flwin32_power_status(int32_t* present, int32_t* percent, int32_t* charging);

// Network. `kind` is 0 none, 1 ethernet, 2 wifi; `signal` is 0-100 and only
// meaningful for wifi; `ssid` is UTF-8 and may be empty.
// The primary monitor's backlight, over DDC/CI. Returns 0 when no monitor
// answers — plenty do not, and a control that cannot change anything should
// not be drawn. SLOW (an I2C round trip to the monitor's firmware): never
// call either of these from the UI thread.
int32_t flwin32_brightness_get(int32_t* percent);
int32_t flwin32_brightness_set(int32_t percent);

int32_t flwin32_network_status(int32_t* kind,
                               int32_t* signal,
                               char* ssid,
                               int32_t ssid_size,
                               // 1 when the machine has a WLAN interface at
                               // all, which is not the same as being on one:
                               // a desktop has none, a laptop with the radio
                               // off has one. The status bar shows a signal
                               // meter only in the second case.
                               int32_t* has_wifi);

// The default output device's volume, 0-100, and whether it is muted.
int32_t flwin32_volume_status(int32_t* percent, int32_t* muted);

// -- and the control centre's half: changing what the three above read ------

// The same endpoint the reader uses, on the same scalar scale.
int32_t flwin32_volume_set(int32_t percent);
int32_t flwin32_volume_set_muted(int32_t muted);

// The Wi-Fi RADIO, which is the softer of the two switches behind "turn the
// network off" and the only one the interactive user owns -- disabling the
// ADAPTER needs administrator rights. Symmetric: what turns it off turns it
// back on, or the toggle is a trap. Returns non-zero if any interface took
// the change; 0 on a machine with no Wi-Fi at all.
int32_t flwin32_wifi_set_radio(int32_t on);

// Windows' own light/dark setting. Two registry values plus a broadcast --
// see flwin32_status.c for why one of each is not enough.
int32_t flwin32_dark_mode(void);
int32_t flwin32_set_dark_mode(int32_t dark);

// ── installed applications ──────────────────────────────────────────────────
//
// Windows has no app registry the way Starling does on Linux. What it has is
// the START MENU: a tree of .lnk shortcuts in a machine-wide folder and a
// per-user one. That is the catalog Explorer itself reads, and the one the
// dock and the launcher enumerate.

// Resolves a .lnk to the path it starts. UTF-8 out, the usual convention:
// bytes written including the terminator, 0 when it is not a shortcut we can
// read, -1 when `out` is too small.
//
// A .lnk is a structured binary file, not a symlink; IShellLink is the only
// supported way to read one, and the target may be an item-ID list rather
// than a path, which nothing but the shell can resolve.
// Initializes COM on the CALLING thread, once per thread. Anything here that
// reaches the shell needs it, and an apartment belongs to a thread — so a
// background thread doing icon or shortcut work must call this itself.
void flwin32_com_ensure(void);

// Records the calling thread as the UI thread, so flwin32_com_ensure gives it
// an STA and every other thread an MTA. Called from flwin32_process_init.
void flwin32_com_mark_ui_thread(void);

// Target, arguments and working directory of a .lnk, in one load.
int32_t flwin32_shortcut_info(const char* shortcut_path,
                              char* target, int32_t target_size,
                              char* arguments, int32_t arguments_size,
                              char* workdir, int32_t workdir_size);

int32_t flwin32_shortcut_target(const char* shortcut_path,
                                char* out,
                                int32_t out_size);

// The Start Menu program folders: 0 = machine-wide, 1 = this user's. Both are
// needed — an app installed for all users is only in the first, and one
// installed for the current user only in the second, which on a modern
// Windows is most of them.
// The icon a shortcut DECLARES — a file path and an index into it, which is
// what most .lnk files carry. Worth asking before the shell's own answer:
// SHGetFileInfo on a shortcut composes the little overlay arrow into the
// icon, and in a dock that badge means nothing.
int32_t flwin32_shortcut_icon(const char* shortcut_path,
                              char* out,
                              int32_t out_size,
                              int32_t* index);

int32_t flwin32_known_folder(int32_t which, char* out, int32_t out_size);

// Starts an app, document or URL through the shell (ShellExecuteW), which is
// the only thing that knows how to open a .lnk. `arguments` may be NULL.
// Returns non-zero on success.
int32_t flwin32_launch(const char* path, const char* arguments,
                       const char* directory);

// -- Explorer's own shell chrome ---------------------------------------------
//
// Starling is a SECOND taskbar until this runs. Hiding Explorer's costs
// nothing that cannot be given back: explorer.exe keeps running and keeps
// owning the desktop, the tray plumbing and shell dialogs, and the taskbar
// comes back on request. What it does NOT give back is the notification
// tray's icons, which live in the taskbar window and go with it until the
// shell hosts them itself.
//
// Two operations, both required -- SW_HIDE on the taskbar windows for the
// visible half, ABS_AUTOHIDE for the reserved half. See flwin32_explorer.c.
//
// Idempotent and cheap: call it again on a timer, because explorer re-shows
// its taskbar on a display change and after it restarts. Returns non-zero
// when no taskbar is visible afterwards.
int32_t flwin32_explorer_taskbar_hide(void);

// Puts it back, with the appbar state the user had before the first hide.
// Called from atexit for the ordinary exit path; `--restore-taskbar` exists
// for the path atexit cannot cover, which is this process being killed.
int32_t flwin32_explorer_taskbar_show(void);

int32_t flwin32_explorer_taskbar_visible(void);

#ifdef __cplusplus
}
#endif

#endif  // FLUTTER_WIN32_BRIDGE_H
