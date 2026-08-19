// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// redirect_std_to_log_file uses plain _wfreopen deliberately (see the comment
// there); keep the CRT from warning us toward the _s variant that caused the
// bug. Must precede the first CRT include.
#ifndef _CRT_SECURE_NO_WARNINGS
#define _CRT_SECURE_NO_WARNINGS
#endif

#include "include/FlutterWin32Bridge.h"

#include <fcntl.h>
#include <io.h>
#include <stdio.h>
#include <stdlib.h>

// Before <windows.h>: this file calls the -W entry points throughout, and the
// resource macros follow UNICODE rather than the call. Without it IDC_ARROW
// expands to MAKEINTRESOURCEA — an LPSTR — and passing that to LoadCursorW is
// a pointer-type mismatch the compiler only warns about.
#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <windows.h>
#include <shellapi.h>  // SHAppBarMessage, APPBARDATA
#include <shellscalingapi.h>  // GetDpiForMonitor
#include <dwmapi.h>           // DwmSetWindowAttribute, for rounded corners

// DWMWA_WINDOW_CORNER_PREFERENCE is an ENUMERATOR, not a macro, so it cannot
// be tested with #ifndef — a fallback definition guarded that way is compiled
// unconditionally and collides with the SDK's. The Windows 11 SDK is a
// requirement of this tree anyway, and on Windows 10 the call fails at
// runtime and leaves the corners square, which is the right outcome.

#pragma comment(lib, "dwmapi.lib")

// Direct inclusion of the vendored embedder headers, the same way the GTK
// bridge includes flutter_linux. Their cross-references are quoted-relative,
// so no include path is needed.
#include "flutter_windows/flutter_windows.h"

// Startup tracing, on STARLING_TRACE=1.
//
// Timed from PROCESS CREATION rather than from any point in main, because the
// image load is a real part of "how long until the launcher is there" and is
// invisible to every clock started inside the program: this executable is
// ~42MB and drags flutter_engine.dll (12MB), _FoundationICU.dll (35MB) and the
// Swift runtime in behind it.
static int trace_enabled(void) {
  static int state = -1;
  if (state < 0) {
    wchar_t buf[8];
    DWORD n = GetEnvironmentVariableW(L"STARLING_TRACE", buf, 8);
    state = (n > 0 && buf[0] != L'0') ? 1 : 0;
  }
  return state;
}

double flwin32_uptime_ms(void) {
  FILETIME created, exited, kernel, user;
  if (!GetProcessTimes(GetCurrentProcess(), &created, &exited, &kernel, &user)) {
    return 0.0;
  }
  FILETIME now;
  GetSystemTimeAsFileTime(&now);
  ULARGE_INTEGER a, b;
  a.LowPart = created.dwLowDateTime;
  a.HighPart = created.dwHighDateTime;
  b.LowPart = now.dwLowDateTime;
  b.HighPart = now.dwHighDateTime;
  return (double)(b.QuadPart - a.QuadPart) / 10000.0;  // 100ns ticks -> ms
}

void flwin32_trace(const char* label) {
  if (!trace_enabled()) return;
  fprintf(stderr, "[trace] %8.1f ms  %s\n", flwin32_uptime_ms(),
          label != NULL ? label : "");
  fflush(stderr);
}

// The engine's own Win32 embedder owns the child window; ours is only the
// top-level frame that hosts it, so the state here is small.
struct FlWin32Host {
  HWND window;
  HWND child;  // the view's HWND, owned by the view controller
  FlutterDesktopViewControllerRef controller;
  int fullscreen;
  WINDOWPLACEMENT saved_placement;  // to restore from fullscreen
  // Appbar registration: what makes Windows RESERVE the strip, so maximized
  // windows stop at the bar instead of going under it. The placement is kept
  // because the reservation has to be recomputed from scratch every time the
  // desktop changes shape (see WM_STARLING_APPBAR).
  int appbar_registered;
  int appbar_edge;
  int appbar_thickness;
  int appbar_overhang;
  // Panel placement, kept in the terms the CALLER gave it: a screen edge, a
  // thickness in logical points, and a monitor. Physical pixels are derived
  // from these every time, because the number that matters changes under us —
  // a display scale change, or the bar's monitor being replugged at another
  // DPI, both leave any remembered pixel count wrong.
  int panel_active;
  int panel_edge;
  int panel_thickness_pt;
  int panel_overhang_pt;
  int panel_monitor;
  int panel_takes_focus;
  int panel_transparent;
  // Overlay mode: a full-screen surface that is hidden until something asks
  // for it — the launcher, and later Mission Control.
  int overlay_active;
  int overlay_monitor;
  int overlay_shown;
  int overlay_alpha;  // the configured opacity; parking drops it to zero
  // A sized overlay is a floating panel above the dock; 0 means full screen.
  int overlay_width_pt;
  int overlay_height_pt;
  int overlay_margin_pt;
  RECT overlay_rect;
  void (*toggle_callback)(void* user);
  void* toggle_user;
  // External textures we handed the engine, so their pixel buffers can be
  // freed on unregister. Swift only ever sees the int64 id.
  struct HostTextureSlot* textures;
  int texture_count;
  int texture_capacity;
};

// Private callback message for the appbar. Windows sends notifications
// (ABN_*) to this id on our window; the value only has to be unique within
// this window class.
#define WM_STARLING_APPBAR (WM_USER + 0x51)

// Escape, while an overlay is on screen.
//
// A global hotkey rather than a key handler in the tree: keyboard messages go
// to the engine's CHILD window, so the top-level procedure never sees them,
// and the framework's own focus plumbing is not somewhere to be relying on
// for "the launcher must always close". Registered only while the overlay is
// up, so Escape belongs to everyone else the rest of the time.
#define kOverlayEscapeHotkey 0xA51

// A system-wide message id, the documented way for unrelated processes to
// talk without a socket or a pipe: every process that registers the same
// STRING gets the same id back, and it survives being broadcast. The bar and
// the launcher are separate processes (one widget root per process), so this
// is how a click on the bar opens the launcher.
static UINT starling_toggle_message(void) {
  static UINT id = 0;
  if (id == 0) id = RegisterWindowMessageW(L"StarlingShellToggleOverlay");
  return id;
}

static const wchar_t kWindowClass[] = L"FlutterSwiftWin32Host";

// Defined with the rest of the shell-chrome code at the end of this file;
// host_wnd_proc has to call both and comes first.
static void appbar_apply_position(FlWin32Host* host);
static void panel_apply_placement(FlWin32Host* host);
static void overlay_park(FlWin32Host* host);
static void overlay_rederive(FlWin32Host* host);
static int overlay_area(FlWin32Host* host, RECT* out);
static void install_child_cursor_proc(HWND child);
static void apply_colour_key(FlWin32Host* host);

// Timer draining libdispatch's main queue so @MainActor code and
// DispatchQueue.main.async blocks run on the Win32 message thread. Same
// arrangement as the GTK host's GLib timer. Resolved dynamically because the
// symbol is a libdispatch implementation detail with no public header.
#define kDrainTimerId 1
#define kDrainTimerMs 8


static void drain_gcd_main_queue(void) {
  static void (*drain)(void*) = NULL;
  static int looked_up = 0;
  if (!looked_up) {
    looked_up = 1;
    // Swift on Windows ships libdispatch as dispatch.dll. GetModuleHandleW,
    // not LoadLibrary: if it is not already loaded nothing has queued work,
    // and loading a second copy would be worse than doing nothing.
    HMODULE d = GetModuleHandleW(L"dispatch.dll");
    if (d != NULL) {
      drain = (void (*)(void*))GetProcAddress(
          d, "_dispatch_main_queue_callback_4CF");
    }
  }
  if (drain != NULL) {
    drain(NULL);
  }
}

static LRESULT CALLBACK host_wnd_proc(HWND hwnd,
                                      UINT message,
                                      WPARAM wparam,
                                      LPARAM lparam) {
  FlWin32Host* host =
      (FlWin32Host*)GetWindowLongPtrW(hwnd, GWLP_USERDATA);

  if (host != NULL && host->controller != NULL) {
    // Give the engine and any plugins first refusal — this is what routes
    // keyboard, IME and accessibility messages the embedder cares about.
    LRESULT result = 0;
    if (FlutterDesktopViewControllerHandleTopLevelWindowProc(
            host->controller, hwnd, message, wparam, lparam, &result)) {
      return result;
    }
  }

  if (host != NULL && message == starling_toggle_message()) {
    // The toggle is handled HERE, in C, and not by the widget tree — because
    // while the overlay is hidden there IS no widget tree.
    //
    // A hidden window is never asked for a frame, and this framework builds
    // its tree on the first frame request rather than at runApp. So a
    // launcher that comes up hidden has never run initState, has registered
    // nothing, and cannot be the thing that decides to show itself. The host
    // owns the visibility; the tree finds out afterwards, through the
    // callback, and mounts on the frame that showing it produces.
    if (host->overlay_active) {
      flwin32_host_set_visible(host, flwin32_host_is_visible(host) ? 0 : 1);
    }
    if (host->toggle_callback != NULL) host->toggle_callback(host->toggle_user);
    return 0;
  }

  switch (message) {
    case WM_STARLING_APPBAR:
      // Windows telling us the desktop changed shape under us.
      switch ((UINT)wparam) {
        case ABN_POSCHANGED:
          // Another appbar appeared/moved/resized, or the resolution
          // changed. The reservation is not sticky — recompute it.
          appbar_apply_position(host);
          break;
        case ABN_FULLSCREENAPP:
          // A fullscreen app opened (lparam != 0) or closed. A topmost bar
          // would otherwise sit over a game or a video; drop out of the
          // topmost band for the duration and come back after.
          if (host != NULL) {
            SetWindowPos(host->window,
                         lparam != 0 ? HWND_BOTTOM : HWND_TOPMOST, 0, 0, 0, 0,
                         SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
          }
          break;
        default:
          break;
      }
      return 0;

    case WM_SIZE:
      // Keep the engine's child window filling the frame.
      if (host != NULL && host->child != NULL) {
        RECT frame;
        GetClientRect(hwnd, &frame);
        MoveWindow(host->child, 0, 0, frame.right - frame.left,
                   frame.bottom - frame.top, TRUE);
      }
      return 0;

    case WM_DPICHANGED:
      // The frame has to resize ITSELF here. flwin32_host_create asks for
      // PER_MONITOR_AWARE_V2, which is a promise that this window handles its
      // own scaling — so Windows stops stretching it for us and merely says
      // "you are now at this DPI, here is the rectangle you should occupy"
      // (lparam). Ignore it and the window keeps its old *physical* size
      // across the change: dragged onto a 150% monitor it stays small with
      // the content laid out for the other scale, and maximized onto one it
      // covers the wrong area. Flutter's own Win32 runner does exactly this;
      // the WM_SIZE that follows carries the new client size down to the
      // engine's child.
      //
      // A PANEL is the exception: the suggested rectangle is the old one
      // scaled, which for edge-anchored chrome is not what we want at all —
      // a top bar would keep its old width in the new scale and stop short
      // of the screen edge. Re-derive from the monitor instead, which also
      // picks up the new points-to-pixels ratio for the thickness.
      if (host != NULL && host->panel_active) {
        panel_apply_placement(host);
        return 0;
      }
      if (lparam != 0) {
        const RECT* suggested = (const RECT*)lparam;
        SetWindowPos(hwnd, NULL, suggested->left, suggested->top,
                     suggested->right - suggested->left,
                     suggested->bottom - suggested->top,
                     SWP_NOZORDER | SWP_NOACTIVATE);
      }
      return 0;

    case WM_HOTKEY:
      if (host != NULL && wparam == kOverlayEscapeHotkey) {
        flwin32_host_set_visible(host, 0);
        if (host->toggle_callback != NULL) host->toggle_callback(host->toggle_user);
        return 0;
      }
      break;

    case WM_DISPLAYCHANGE:
      // A monitor was plugged, unplugged, or changed resolution. A panel is
      // anchored to a monitor's edge, so its rectangle is now wrong in a way
      // nothing else will correct: WM_DPICHANGED does not fire for a mode
      // change at the same scale, and the appbar's ABN_POSCHANGED only
      // arrives if a reservation already exists. Re-derive, which also moves
      // the bar back onto a monitor that came and went.
      if (host != NULL && host->panel_active) {
        panel_apply_placement(host);
      }
      // An overlay covers a whole monitor, so a mode change leaves it the
      // wrong size in the most visible way there is. The SHOW path already
      // re-derives, which covers a launcher that was hidden through the
      // change; this is the other half — one that was on screen while it
      // happened, which otherwise sits there as a window-sized rectangle in
      // the corner of a bigger desktop. A parked overlay is re-parked rather
      // than left at coordinates that may no longer be on any monitor.
      if (host != NULL && host->overlay_active) {
        overlay_rederive(host);
        if (host->overlay_shown) {
          SetWindowPos(host->window, HWND_TOPMOST,
                       host->overlay_rect.left, host->overlay_rect.top,
                       host->overlay_rect.right - host->overlay_rect.left,
                       host->overlay_rect.bottom - host->overlay_rect.top,
                       SWP_NOACTIVATE);
        } else {
          overlay_park(host);
        }
      }
      break;

    case WM_MOUSEACTIVATE:
      // Chrome that does not steal the keyboard. WS_EX_NOACTIVATE already
      // stops the click from activating us, but say it here too: this is the
      // message the shell sends before the click is dispatched, and answering
      // MA_NOACTIVATE is what every real taskbar does. The click still
      // arrives — only the activation is refused.
      if (host != NULL && host->panel_active && !host->panel_takes_focus) {
        return MA_NOACTIVATE;
      }
      break;

    case WM_SETFOCUS:
      // Hand keyboard focus down to the engine's view. Activating the frame
      // focuses the frame, and the view is a child window — without this the
      // key messages are delivered to a window the embedder is not listening
      // on, so the app renders and takes mouse input but silently ignores
      // every keystroke. Flutter's own Win32 runner does exactly this.
      if (host != NULL && host->child != NULL) {
        SetFocus(host->child);
      }
      return 0;

    case WM_FONTCHANGE:
      if (host != NULL && host->controller != NULL) {
        FlutterDesktopEngineReloadSystemFonts(
            FlutterDesktopViewControllerGetEngine(host->controller));
      }
      return 0;

    case WM_DESTROY:
      // Unregister the appbar FIRST. Leaving a registration behind means
      // Windows keeps the strip reserved after we are gone: every maximized
      // window stays short of an edge with nothing on it, until a shell
      // restart.
      if (host != NULL && host->appbar_registered) {
        APPBARDATA abd = {sizeof(APPBARDATA)};
        abd.hWnd = hwnd;
        SHAppBarMessage(ABM_REMOVE, &abd);
        host->appbar_registered = 0;
      }
      PostQuitMessage(0);
      return 0;

    case WM_ACTIVATE:
      // A floating launcher closes when you click away from it. That is what
      // every menu on the system does, and with a panel there is now an
      // "away" to click — the full-screen version had none, so this had
      // nothing to do and did not exist.
      //
      // Only for a SIZED overlay, and only on the way down: a full-screen
      // overlay covers everything anyway, and the dock must not vanish when
      // the user clicks the window it just raised.
      if (host != NULL && host->overlay_active && host->overlay_shown
          && host->overlay_width_pt > 0 && LOWORD(wparam) == WA_INACTIVE) {
        overlay_park(host);
        if (host->toggle_callback != NULL) host->toggle_callback(host->toggle_user);
        return 0;
      }
      break;

    case WM_TIMER:
      if (wparam == kDrainTimerId) {
        drain_gcd_main_queue();
        return 0;
      }
      break;

    default:
      break;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

// UTF-8 -> UTF-16. Caller frees.
static wchar_t* to_wide(const char* utf8) {
  if (utf8 == NULL) {
    return NULL;
  }
  int n = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, NULL, 0);
  if (n <= 0) {
    return NULL;
  }
  wchar_t* out = (wchar_t*)calloc((size_t)n, sizeof(wchar_t));
  if (out == NULL) {
    return NULL;
  }
  MultiByteToWideChar(CP_UTF8, 0, utf8, -1, out, n);
  return out;
}

FlWin32Host* flwin32_host_create(const char* title,
                                 int32_t width,
                                 int32_t height,
                                 const void* runtime_controller) {
  HINSTANCE instance = GetModuleHandleW(NULL);
  flwin32_process_init();
  flwin32_trace("host_create: begin");

  WNDCLASSEXW wc = {0};
  wc.cbSize = sizeof(WNDCLASSEXW);
  wc.style = CS_HREDRAW | CS_VREDRAW;
  wc.lpfnWndProc = host_wnd_proc;
  wc.hInstance = instance;
  wc.hCursor = LoadCursorW(NULL, IDC_ARROW);
  // BLACK, not COLOR_WINDOW, and this is user-visible.
  //
  // The class brush is what Windows paints over any part of the window that
  // becomes valid before the engine has presented a frame for it, and the
  // overlay path hits that on every open: the launcher parks as 1x1 and is
  // shown by resizing to the whole screen, so at 3840x2160 there is a real
  // gap while the swap chain is rebuilt and the grid is laid out again. With
  // COLOR_WINDOW that gap was a full-screen WHITE FLASH before the apps
  // appeared. Black is the colour both surfaces are actually built on, so the
  // same gap now reads as the overlay arriving rather than as a fault -- and
  // on the dock, whose transparency is a colour key on pure black, an erase
  // in the key colour is a hole instead of an opaque white band.
  //
  // It costs one diagnostic: "the surface came up as the class's white brush"
  // was the tell for "the tree never mounted" (see the overlay parking notes
  // below). That failure is now a BLANK BLACK surface. It is still perfectly
  // visible -- a launcher with no tiles, a dock with no icons -- but it no
  // longer announces itself in white.
  wc.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);
  wc.lpszClassName = kWindowClass;
  // Ignore "already registered" — a second host in one process is fine.
  RegisterClassExW(&wc);

  wchar_t* wtitle = to_wide(title != NULL ? title : "Flutter");

  // Size the frame so the *client* area is the requested size.
  RECT frame = {0, 0, (LONG)width, (LONG)height};
  AdjustWindowRect(&frame, WS_OVERLAPPEDWINDOW, FALSE);

  HWND window = CreateWindowExW(
      0, kWindowClass, wtitle != NULL ? wtitle : L"Flutter",
      WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT,
      frame.right - frame.left, frame.bottom - frame.top, NULL, NULL,
      instance, NULL);
  free(wtitle);

  if (window == NULL) {
    fprintf(stderr, "[FlWin32Host] CreateWindowExW failed (%lu)\n",
            GetLastError());
    return NULL;
  }

  // Engine data files resolve the standard Flutter bundle way:
  // <executable dir>/data/{icudtl.dat,flutter_assets}. These paths are
  // documented as relative to the executable's directory, so no absolute
  // path is needed here.
  FlutterDesktopEngineProperties properties = {0};
  properties.assets_path = L"data\\flutter_assets";
  properties.icu_data_path = L"data\\icudtl.dat";
  // The Swift framework is main-thread-bound (MainActor): runtime callbacks
  // and platform messages must arrive on the message thread, not the engine's
  // own UI thread. The embedder already merges them unless asked not to, but
  // say so explicitly — the enum's Default is documented as changing.
  properties.ui_thread_policy = RunOnPlatformThread;

  flwin32_trace("FlutterDesktopEngineCreate: begin");
  FlutterDesktopEngineRef engine = FlutterDesktopEngineCreate(&properties);
  flwin32_trace("FlutterDesktopEngineCreate: end");
  if (engine == NULL) {
    fprintf(stderr, "[FlWin32Host] FlutterDesktopEngineCreate failed\n");
    DestroyWindow(window);
    return NULL;
  }

  // Swift mode must be set before the engine runs, and creating the view
  // controller is what runs it.
  FlutterDesktopEngineSetSwiftRuntime(engine, runtime_controller);

  RECT client;
  GetClientRect(window, &client);
  flwin32_trace("FlutterDesktopViewControllerCreate: begin");
  FlutterDesktopViewControllerRef controller = FlutterDesktopViewControllerCreate(
      client.right - client.left, client.bottom - client.top, engine);
  if (controller == NULL) {
    // The engine is destroyed for us when view controller creation fails.
    fprintf(stderr,
            "[FlWin32Host] FlutterDesktopViewControllerCreate failed\n");
    DestroyWindow(window);
    return NULL;
  }

  FlWin32Host* host = (FlWin32Host*)calloc(1, sizeof(FlWin32Host));
  if (host == NULL) {
    FlutterDesktopViewControllerDestroy(controller);
    DestroyWindow(window);
    return NULL;
  }
  host->window = window;
  host->controller = controller;
  host->child =
      FlutterDesktopViewGetHWND(FlutterDesktopViewControllerGetView(controller));
  host->saved_placement.length = sizeof(WINDOWPLACEMENT);

  // The Win32 embedder documents that view hookup is the caller's job. This is
  // exactly what the engine's own SetChildContent (host_window.cc) does — in
  // particular it does NOT rewrite the child's GWL_STYLE, because the view is
  // already created as a child and overwriting the style word would drop the
  // other bits the embedder set on it.
  SetParent(host->child, window);
  MoveWindow(host->child, client.left, client.top, client.right - client.left,
             client.bottom - client.top, TRUE);
  install_child_cursor_proc(host->child);

  SetWindowLongPtrW(window, GWLP_USERDATA, (LONG_PTR)host);
  flwin32_trace("host_create: end");
  return host;
}

// Last resort when there is no console and no redirection: send stdout and
// stderr to %LOCALAPPDATA%\Starling\<exe>.log.
//
// Without this a GUI-subsystem app double-clicked in Explorer has nowhere to
// write, and the one message that matters is the one you lose: Swift prints
// "Fatal error: <reason>: file X, line N" to stderr and *then* executes its
// trap instruction, so a crash that would name its own cause instead shows up
// only as an illegal-instruction bucket in the Windows event log, pointing at
// swiftCore.dll with no reason attached. That is exactly how one real crash
// here cost a night of guessing.
static void redirect_std_to_log_file(void) {
  wchar_t dir[MAX_PATH];
  DWORD n = GetEnvironmentVariableW(L"LOCALAPPDATA", dir, MAX_PATH);
  if (n == 0 || n >= MAX_PATH - 32) {
    return;
  }
  if (wcscat_s(dir, MAX_PATH, L"\\Starling") != 0) {
    return;
  }
  // Already-exists is the normal case and not an error.
  CreateDirectoryW(dir, NULL);

  wchar_t exe[MAX_PATH];
  if (GetModuleFileNameW(NULL, exe, MAX_PATH) == 0) {
    return;
  }
  wchar_t* base = wcsrchr(exe, L'\\');
  base = (base != NULL) ? base + 1 : exe;
  wchar_t* dot = wcsrchr(base, L'.');
  if (dot != NULL) {
    *dot = L'\0';
  }

  wchar_t path[MAX_PATH];
  if (swprintf_s(path, MAX_PATH, L"%s\\%s.log", dir, base) < 0) {
    return;
  }

  // ONE kernel-append handle, and every descriptor in the process that can
  // reach the log is a duplicate of it. The writers do not agree on how to
  // write — Swift print and printf go through the CRT FILE streams, the
  // Swift runtime's "Fatal error: <reason>" is a bare _write(2, …), and
  // Foundation's FileHandle resolves a descriptor to its OS handle and calls
  // raw WriteFile — and only FILE_APPEND_DATA makes the KERNEL pin all of
  // them to end-of-file. Anything less loses data in practice, twice over:
  //
  //   - _wfreopen_s for the streams (_SH_SECURE — exclusive write) made the
  //     second reopen of the same path fail with a sharing violation, and
  //     freopen closes its stream even when the new open fails; the first
  //     print through the dead stdout then fast-failed the whole process
  //     (exit 0xc0000409) with the log created and empty.
  //   - plain _wfreopen(path, "a") for the streams worked for CRT writers
  //     (the CRT seeks to end before its own writes) but left the handles
  //     plain GENERIC_WRITE, so Foundation's first raw WriteFile landed at
  //     the handle's stored position — 0 — and erased the log's head
  //     (observed: the startup line vanished the moment the first [Adapter]
  //     line was written).
  //
  // CREATE_ALWAYS: fresh log each launch.
  HANDLE append = CreateFileW(path, FILE_APPEND_DATA,
                              FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
                              CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
  if (append == INVALID_HANDLE_VALUE) {
    // Streams stay detached; prints remain silent no-ops, which is safe.
    return;
  }
  int afd = _open_osfhandle((intptr_t)append, _O_APPEND | _O_TEXT);
  if (afd < 0) {
    CloseHandle(append);
    return;
  }

  // Rebind the FILE streams. freopen to NUL first, because that is the only
  // supported way to give a detached stream (_fileno == -2) a real
  // descriptor again; then point that descriptor at the log with _dup2,
  // which installs a duplicate of the append handle (flags included) under
  // the same fd number. NUL, not the log path, so no plain-write handle to
  // the log ever exists for Foundation to find via the stream's fd.
  FILE* f = _wfreopen(L"NUL", L"w", stderr);
  if (f != NULL) {
    // Unbuffered, or a crash takes the buffered tail with it — defeating
    // the whole point of the file.
    setvbuf(stderr, NULL, _IONBF, 0);
    int fd = _fileno(stderr);
    if (fd >= 0 && fd != afd) {
      _dup2(afd, fd);
    }
  }
  FILE* g = _wfreopen(L"NUL", L"w", stdout);
  if (g != NULL) {
    setvbuf(stdout, NULL, _IONBF, 0);
    int fd = _fileno(stdout);
    if (fd >= 0 && fd != afd) {
      _dup2(afd, fd);
    }
  }

  // Descriptors 1 and 2 as well — the freopens above land on the lowest
  // free fds (3 and 4 in practice, never 1 and 2), and the Swift runtime's
  // fatal-error report writes to fd 2 by number.
  _dup2(afd, 1);
  _dup2(afd, 2);
  if (afd > 2 && (f == NULL || afd != _fileno(stderr))
      && (g == NULL || afd != _fileno(stdout))) {
    _close(afd);
  }

  // And the Win32-level handles, for anything that asks GetStdHandle.
  SetStdHandle(STD_OUTPUT_HANDLE, (HANDLE)_get_osfhandle(1));
  SetStdHandle(STD_ERROR_HANDLE, (HANDLE)_get_osfhandle(2));
}

void flwin32_process_init(void) {
  flwin32_com_mark_ui_thread();
  // Per-monitor DPI, and as EARLY as possible.
  //
  // Until this runs, the process is DPI-UNAWARE and Windows virtualizes
  // everything it is told about the display: on a 4K screen at 200% it
  // reports 1920x1080 and 96 dpi, and every one of those numbers is wrong by
  // exactly the scale factor. Setting it inside host_create was too late —
  // anything that read the monitor list first (a shell asking how wide the
  // screen is, before it makes a window) got the virtualized answer, and the
  // symptom is not a crash but a plausible-looking wrong number.
  //
  // Best effort: a manifest may have set awareness already, in which case
  // this fails and the existing setting stands. Idempotent, so host_create
  // calls it again for anyone who never called install().
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
}

void flwin32_attach_parent_console(void) {
  // A console-subsystem build already owns one, and AttachConsole would fail
  // on it anyway.
  if (GetConsoleWindow() != NULL) {
    return;
  }

  // Read before attaching, not after. A redirected stream (`app.exe >
  // log.txt`, or the bench scripts' Start-Process -RedirectStandardOutput)
  // arrives as a real file handle; reopening CONOUT$ over it would put the
  // output on the console and leave the file empty — a silent loss, since the
  // file is created either way.
  HANDLE out = GetStdHandle(STD_OUTPUT_HANDLE);
  HANDLE err = GetStdHandle(STD_ERROR_HANDLE);

  // Fails, harmlessly, when the launcher had no console — Explorer, the
  // Start menu, a shortcut. That is the common case and wants no console, but
  // it still wants somewhere for a crash to say why.
  if (!AttachConsole(ATTACH_PARENT_PROCESS)) {
    if ((out == NULL || out == INVALID_HANDLE_VALUE) &&
        (err == NULL || err == INVALID_HANDLE_VALUE)) {
      redirect_std_to_log_file();
    }
    return;
  }

  // Attaching gives the process a console but not CRT streams pointing at it:
  // stdout is still the closed/absent handle the process started with, so
  // both printf and Swift's print stay silent until the FILE* is reopened.
  FILE* reopened = NULL;
  if (out == NULL || out == INVALID_HANDLE_VALUE) {
    freopen_s(&reopened, "CONOUT$", "w", stdout);
  }
  if (err == NULL || err == INVALID_HANDLE_VALUE) {
    freopen_s(&reopened, "CONOUT$", "w", stderr);
  }
}

void flwin32_host_show(FlWin32Host* host) {
  if (host == NULL) {
    return;
  }
  ShowWindow(host->window, SW_SHOW);
  UpdateWindow(host->window);
  SetFocus(host->child);
}

void flwin32_host_run(FlWin32Host* host) {
  // Kick the first frame, so the widget tree mounts NOW rather than whenever
  // the window next happens to change size.
  //
  // The tree builds on the first frame request, and the only thing that asks
  // for one is a window-metrics event. The embedder sends metrics once, from
  // inside FlutterDesktopViewControllerCreate -- which is before the root
  // widget has been attached, so it lands on an empty engine and nothing
  // builds. After that, metrics come only from WM_SIZE.
  //
  // For an ordinary window that is invisible: it gets resized on its way to
  // the screen. For an overlay parked at its final size it never happens at
  // all, and the launcher stayed unmounted until something resized it -- which
  // is what the old 1x1 park did, at 161ms of synchronous 4K surface resize.
  //
  // A same-size WM_SIZE is the whole fix. OnWindowSizeChanged compares the
  // requested size against the surface's and takes the blocking raster-thread
  // path only when they differ (SurfaceWillUpdate); when they match it sends
  // the metrics and returns. So this delivers the frame request and costs
  // nothing.
  if (host != NULL && host->child != NULL) {
    RECT client;
    if (GetClientRect(host->child, &client)) {
      SendMessageW(host->child, WM_SIZE, SIZE_RESTORED,
                   MAKELPARAM(client.right - client.left,
                              client.bottom - client.top));
    }
  }
  flwin32_trace("message loop: begin");
  if (host == NULL) {
    return;
  }
  SetTimer(host->window, kDrainTimerId, kDrainTimerMs, NULL);

  MSG message;
  while (GetMessageW(&message, NULL, 0, 0) > 0) {
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }

  KillTimer(host->window, kDrainTimerId);
}

void flwin32_host_set_fullscreen(FlWin32Host* host, int32_t fullscreen) {
  if (host == NULL || (host->fullscreen != 0) == (fullscreen != 0)) {
    return;
  }
  if (fullscreen) {
    // Borderless window covering the monitor the window is currently on --
    // the ordinary Win32 idiom, and it keeps the engine's child window and
    // its swap chain intact.
    GetWindowPlacement(host->window, &host->saved_placement);
    MONITORINFO mi = {sizeof(MONITORINFO)};
    if (GetMonitorInfoW(MonitorFromWindow(host->window, MONITOR_DEFAULTTONEAREST),
                        &mi)) {
      SetWindowLongPtrW(host->window, GWL_STYLE, WS_POPUP | WS_VISIBLE);
      SetWindowPos(host->window, HWND_TOP, mi.rcMonitor.left, mi.rcMonitor.top,
                   mi.rcMonitor.right - mi.rcMonitor.left,
                   mi.rcMonitor.bottom - mi.rcMonitor.top,
                   SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
    }
  } else {
    SetWindowLongPtrW(host->window, GWL_STYLE, WS_OVERLAPPEDWINDOW | WS_VISIBLE);
    SetWindowPlacement(host->window, &host->saved_placement);
    SetWindowPos(host->window, NULL, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER |
                     SWP_FRAMECHANGED);
  }
  host->fullscreen = fullscreen ? 1 : 0;
}

// ── shell chrome: panel windows and monitor geometry ────────────────────────
//
// What a desktop shell needs from a window and an ordinary app does not: no
// decoration, always on top, and pinned to an edge of a named monitor. The
// engine's embedder has no opinion about any of it — it owns the view and the
// swap chain, and is happy inside whatever HWND we hand it — so this is pure
// Win32 restyling applied after flwin32_host_create.
//
// This is the Windows counterpart of wlr-layer-shell, and the comparison is
// worth keeping in mind: layer shell asks the COMPOSITOR to place and reserve
// space, while here we place ourselves and (later) ask the shell to reserve
// via SHAppBarMessage. Reserving is deliberately not done yet — an appbar has
// a message-callback contract (ABM_NEW/ABM_QUERYPOS/ABM_SETPOS on every
// resolution and taskbar change) that wants its own change.

typedef struct {
  int32_t want;   // index to find, or -1 to count
  int32_t seen;
  RECT rect;
  HMONITOR hmonitor;
  int32_t primary;
  int32_t found;
} MonitorPick;

static BOOL CALLBACK monitor_pick_cb(HMONITOR monitor,
                                     HDC dc,
                                     LPRECT clip,
                                     LPARAM data) {
  (void)dc;
  (void)clip;
  MonitorPick* pick = (MonitorPick*)data;
  MONITORINFO mi = {sizeof(MONITORINFO)};
  if (!GetMonitorInfoW(monitor, &mi)) return TRUE;
  if (pick->want >= 0 && pick->seen == pick->want) {
    pick->rect = mi.rcMonitor;
    pick->hmonitor = monitor;
    pick->primary = (mi.dwFlags & MONITORINFOF_PRIMARY) != 0;
    pick->found = 1;
    return FALSE;  // stop; we have the one we were asked for
  }
  pick->seen++;
  return TRUE;
}

int32_t flwin32_monitor_count(void) {
  MonitorPick pick = {0};
  pick.want = -1;
  EnumDisplayMonitors(NULL, NULL, monitor_pick_cb, (LPARAM)&pick);
  return pick.seen;
}

int32_t flwin32_monitor_rect(int32_t index,
                             int32_t* x,
                             int32_t* y,
                             int32_t* width,
                             int32_t* height,
                             int32_t* primary) {
  MonitorPick pick = {0};
  pick.want = index;
  EnumDisplayMonitors(NULL, NULL, monitor_pick_cb, (LPARAM)&pick);
  if (!pick.found) return 0;
  if (x != NULL) *x = pick.rect.left;
  if (y != NULL) *y = pick.rect.top;
  if (width != NULL) *width = pick.rect.right - pick.rect.left;
  if (height != NULL) *height = pick.rect.bottom - pick.rect.top;
  if (primary != NULL) *primary = pick.primary;
  return 1;
}

// The monitor's scale, as a DPI where 96 is 100%. GetDpiForMonitor rather
// than GetDpiForWindow: a panel has to know the scale of a monitor it is not
// on yet, and the two disagree for exactly the length of the move.
int32_t flwin32_monitor_dpi(int32_t index) {
  MonitorPick pick = {0};
  pick.want = index;
  HMONITOR monitor = NULL;
  if (index >= 0) {
    pick.hmonitor = NULL;
    EnumDisplayMonitors(NULL, NULL, monitor_pick_cb, (LPARAM)&pick);
    if (pick.found) monitor = pick.hmonitor;
  }
  if (monitor == NULL) {
    POINT origin = {0, 0};
    monitor = MonitorFromPoint(origin, MONITOR_DEFAULTTOPRIMARY);
  }
  if (monitor == NULL) return USER_DEFAULT_SCREEN_DPI;

  UINT dpi_x = 0, dpi_y = 0;
  if (FAILED(GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &dpi_x, &dpi_y)) ||
      dpi_x == 0) {
    return USER_DEFAULT_SCREEN_DPI;
  }
  return (int32_t)dpi_x;
}

// Places the panel from the state on the host. Called on every set_panel, and
// again on every WM_DPICHANGED — see the comment there for why a panel cannot
// take Windows' suggested rectangle.
static void panel_apply_placement(FlWin32Host* host) {
  if (host == NULL || host->window == NULL) return;

  RECT area;
  MonitorPick pick = {0};
  pick.want = host->panel_monitor;
  if (host->panel_monitor >= 0) {
    EnumDisplayMonitors(NULL, NULL, monitor_pick_cb, (LPARAM)&pick);
  }
  if (pick.found) {
    area = pick.rect;
  } else {
    // No monitor asked for, or an index that no longer exists — a monitor can
    // be unplugged between the caller reading the list and acting on it, and
    // a bar that vanishes is worse than a bar on the wrong screen.
    MONITORINFO mi = {sizeof(MONITORINFO)};
    if (!GetMonitorInfoW(
            MonitorFromWindow(host->window, MONITOR_DEFAULTTOPRIMARY), &mi)) {
      return;
    }
    area = mi.rcMonitor;
  }

  // Points to pixels, at the scale of the monitor the bar is going TO. This
  // is the whole reason the thickness is stored in points: a 44pt bar is 44px
  // at 100% and 88px at 200%, and hardcoding either one gives a bar that is
  // half-height on one of the two machines this has to run on.
  int32_t dpi = flwin32_monitor_dpi(host->panel_monitor);
  int32_t thickness =
      (host->panel_thickness_pt * dpi + USER_DEFAULT_SCREEN_DPI / 2) /
      USER_DEFAULT_SCREEN_DPI;
  if (thickness < 1) thickness = 1;

  // The OVERHANG is the difference between the strip the panel reserves and
  // the window it actually occupies: the window extends this much further in
  // from the edge, and reserves none of it.
  //
  // It exists because a dock needs to draw ABOVE itself — a hover label, a
  // right-click menu — and a window is a hard clip. Without it those would be
  // cut off at the edge of the strip. The overhang is transparent (the
  // panel's colour key), so it is invisible and clicks fall straight through
  // it to whatever is behind, right up until a menu paints there.
  int32_t overhang =
      (host->panel_overhang_pt * dpi + USER_DEFAULT_SCREEN_DPI / 2) /
      USER_DEFAULT_SCREEN_DPI;
  if (overhang < 0) overhang = 0;
  int32_t span = thickness + overhang;

  int32_t x, y, w, h;
  switch (host->panel_edge) {
    case 1:  // bottom
      x = area.left;
      y = area.bottom - span;
      w = area.right - area.left;
      h = span;
      break;
    case 2:  // left
      x = area.left;
      y = area.top;
      w = span;
      h = area.bottom - area.top;
      break;
    case 3:  // right
      x = area.right - span;
      y = area.top;
      w = span;
      h = area.bottom - area.top;
      break;
    default:  // top
      x = area.left;
      y = area.top;
      w = area.right - area.left;
      h = span;
      break;
  }

  // WS_POPUP rather than clearing bits off WS_OVERLAPPEDWINDOW: the client
  // area then IS the window, so the engine's view fills it exactly and the
  // Flutter tree's (0,0) is the screen corner. AdjustWindowRect is not needed
  // and must not be used — it would inset the bar by a frame that is no
  // longer there.
  SetWindowLongPtrW(host->window, GWL_STYLE, WS_POPUP | WS_VISIBLE);
  // TOOLWINDOW keeps the bar out of Alt+Tab and off the taskbar, which is
  // what makes it read as chrome rather than as an app. TOPMOST is the
  // z-order half; SetWindowPos below is what actually applies it.
  //
  // NOACTIVATE is the difference between chrome and an app window: without
  // it, clicking a taskbar button takes the keyboard away from the very
  // window the click is about to raise, and the user's caret goes with it.
  // It also makes flwin32_wm_activate's AttachThreadInput path load-bearing
  // rather than decorative — we are no longer the foreground process when we
  // ask for the foreground to move.
  LONG_PTR ex = GetWindowLongPtrW(host->window, GWL_EXSTYLE);
  ex |= WS_EX_TOOLWINDOW | WS_EX_TOPMOST;
  if (host->panel_takes_focus) {
    ex &= ~(LONG_PTR)WS_EX_NOACTIVATE;
  } else {
    ex |= WS_EX_NOACTIVATE;
  }
  if (host->panel_transparent) ex |= WS_EX_LAYERED;
  SetWindowLongPtrW(host->window, GWL_EXSTYLE, ex);

  // Transparency by COLOUR KEY, and pure black is the key.
  //
  // A dock is a slab floating over the wallpaper, not a bar welded to the
  // edge — so the panel window is the full strip and most of it has to
  // disappear. The engine's swap chain is opaque, so per-pixel alpha is not
  // on offer; LWA_COLORKEY is, and it costs nothing. Anything the tree paints
  // as 0x00000000 vanishes, and clicks there fall through to whatever is
  // behind, which is what an empty stretch of dock strip should do.
  //
  // The cost is that pure black is now unpaintable in a transparent panel.
  // Every Starling surface is a near-black (0x1B1D22), so nothing real is
  // lost — but a panel that wants true black has to say transparent: false.
  SetWindowPos(host->window, HWND_TOPMOST, x, y, w, h,
               SWP_FRAMECHANGED | SWP_SHOWWINDOW | SWP_NOACTIVATE);
  // AFTER the move, and again after the appbar moves it: SWP_FRAMECHANGED
  // re-runs the non-client calculation, and the colour key does not reliably
  // survive it. The symptom is not "no transparency" — the strip that was
  // sized before the call still keys out, and only the part added afterwards
  // paints solid black, which reads as a layout bug rather than a lost
  // attribute.
  apply_colour_key(host);

  // Remember the placement in the shell's OWN terms, translated to the ABE_*
  // the appbar API speaks. Kept even when no appbar is registered, so
  // flwin32_host_set_appbar can be called later without repeating itself.
  switch (host->panel_edge) {
    case 1:  host->appbar_edge = ABE_BOTTOM; break;
    case 2:  host->appbar_edge = ABE_LEFT;   break;
    case 3:  host->appbar_edge = ABE_RIGHT;  break;
    default: host->appbar_edge = ABE_TOP;    break;
  }
  // The RESERVED thickness, not the window's — reserving the overhang too
  // would push every maximized window in by the height of a menu that is not
  // being shown.
  host->appbar_thickness = thickness;
  host->appbar_overhang = overhang;
  // Already an appbar (a monitor change, or a second call): re-reserve at the
  // new geometry rather than leaving the old strip reserved.
  if (host->appbar_registered) appbar_apply_position(host);
}

// Moves an existing panel to another edge, at runtime.
//
// Everything that makes a panel a panel is already re-derived by
// panel_apply_placement — the window geometry, the colour key, and the appbar
// reservation, which it re-registers at the new edge rather than leaving the
// old strip reserved. So a move is the edge plus that call.
//
// The tree relayouts on its own: the window changes shape, which is a WM_SIZE,
// which is a metrics event. A bottom bar and a left bar are not the same shape
// at all — one is the screen's width by 56pt, the other 56pt by its height —
// so this is a real resize and the surface is expected to lay itself out
// differently on the other side of it.
void flwin32_host_move_panel(FlWin32Host* host, int32_t edge) {
  if (host == NULL || !host->panel_active) return;
  host->panel_edge = edge;
  panel_apply_placement(host);
}

void flwin32_host_set_panel(FlWin32Host* host,
                            int32_t edge,
                            int32_t thickness,
                            int32_t monitor,
                            int32_t takes_focus,
                            int32_t transparent,
                            int32_t overhang) {
  if (host == NULL || host->window == NULL) return;
  host->panel_active = 1;
  host->panel_edge = edge;
  host->panel_thickness_pt = thickness;
  host->panel_overhang_pt = overhang;
  host->panel_monitor = monitor;
  host->panel_takes_focus = takes_focus ? 1 : 0;
  host->panel_transparent = transparent ? 1 : 0;
  panel_apply_placement(host);
}

// ── appbar: asking Windows to reserve the strip ─────────────────────────────
//
// A topmost window is only an OVERLAY — maximize anything and it goes
// underneath. An appbar is the documented way to make the strip part of the
// desktop's work area, and it is the Windows analogue of layer shell's
// exclusive zone.
//
// The protocol is a conversation, not a setting, and all three steps are
// required every time: ABM_QUERYPOS asks "if I want this rectangle, what do I
// actually get" (Windows moves it clear of the taskbar and any other appbar),
// ABM_SETPOS commits the answer, and only then do we move the window to
// match. Skipping QUERYPOS puts the bar on top of the taskbar; skipping the
// final move leaves the reservation and the window in different places.

// Re-establishes the panel's transparency. Called after every geometry
// change, because SWP_FRAMECHANGED can drop it.
static void apply_colour_key(FlWin32Host* host) {
  if (host == NULL || host->window == NULL || !host->panel_transparent) return;
  SetLayeredWindowAttributes(host->window, RGB(0, 0, 0), 255, LWA_COLORKEY);
}

static void appbar_apply_position(FlWin32Host* host) {
  if (host == NULL || !host->appbar_registered) return;

  // The monitor the bar is currently on — recomputed rather than remembered,
  // because this runs again on every resolution change and monitor hotplug.
  MONITORINFO mi = {sizeof(MONITORINFO)};
  if (!GetMonitorInfoW(MonitorFromWindow(host->window, MONITOR_DEFAULTTOPRIMARY),
                       &mi)) {
    return;
  }

  APPBARDATA abd = {sizeof(APPBARDATA)};
  abd.hWnd = host->window;
  abd.uEdge = (UINT)host->appbar_edge;
  abd.rc = mi.rcMonitor;
  switch (host->appbar_edge) {
    case ABE_BOTTOM: abd.rc.top = abd.rc.bottom - host->appbar_thickness; break;
    case ABE_LEFT:   abd.rc.right = abd.rc.left + host->appbar_thickness; break;
    case ABE_RIGHT:  abd.rc.left = abd.rc.right - host->appbar_thickness; break;
    default:         abd.rc.bottom = abd.rc.top + host->appbar_thickness; break;
  }

  SHAppBarMessage(ABM_QUERYPOS, &abd);
  // QUERYPOS only slides the edge we are anchored to; re-apply the thickness
  // along that axis or the bar grows to whatever slab was left over.
  switch (host->appbar_edge) {
    case ABE_BOTTOM: abd.rc.top = abd.rc.bottom - host->appbar_thickness; break;
    case ABE_LEFT:   abd.rc.right = abd.rc.left + host->appbar_thickness; break;
    case ABE_RIGHT:  abd.rc.left = abd.rc.right - host->appbar_thickness; break;
    default:         abd.rc.bottom = abd.rc.top + host->appbar_thickness; break;
  }

  SHAppBarMessage(ABM_SETPOS, &abd);

  // The window is the reserved strip PLUS the overhang, and this is the place
  // that gets it wrong if you forget: ABM_SETPOS answers with the RESERVED
  // rectangle, and moving the window straight onto it silently throws the
  // overhang away — the dock keeps working and its hover label and menu are
  // clipped out of existence, with nothing to suggest the appbar did it.
  RECT frame = abd.rc;
  switch (host->appbar_edge) {
    case ABE_BOTTOM: frame.top -= host->appbar_overhang; break;
    case ABE_LEFT:   frame.right += host->appbar_overhang; break;
    case ABE_RIGHT:  frame.left -= host->appbar_overhang; break;
    default:         frame.bottom += host->appbar_overhang; break;
  }
  MoveWindow(host->window, frame.left, frame.top,
             frame.right - frame.left, frame.bottom - frame.top, TRUE);
  apply_colour_key(host);
}

int32_t flwin32_host_set_appbar(FlWin32Host* host, int32_t enable) {
  if (host == NULL || host->window == NULL) return 0;

  if (!enable) {
    if (host->appbar_registered) {
      APPBARDATA abd = {sizeof(APPBARDATA)};
      abd.hWnd = host->window;
      SHAppBarMessage(ABM_REMOVE, &abd);
      host->appbar_registered = 0;
    }
    return 1;
  }
  if (host->appbar_registered) return 1;

  APPBARDATA abd = {sizeof(APPBARDATA)};
  abd.hWnd = host->window;
  abd.uCallbackMessage = WM_STARLING_APPBAR;
  if (!SHAppBarMessage(ABM_NEW, &abd)) return 0;
  host->appbar_registered = 1;
  appbar_apply_position(host);
  return 1;
}

// ── external textures: an app icon the widget tree can draw ─────────────────
//
// The engine's pixel-buffer texture is a PULL: it calls back on the render
// thread asking for the current buffer, rather than being handed frames. An
// icon never changes, so the callback returns the same buffer forever and the
// only real work is keeping it alive exactly as long as the texture — which
// is what the slot table below is for. Freeing on unregister rather than in
// the per-frame release_callback is deliberate: the buffer is not per-frame,
// and a release_callback that freed it would free it after the first paint.

typedef struct {
  uint8_t* pixels;
  FlutterDesktopPixelBuffer buffer;
} HostTexture;

struct HostTextureSlot {
  int64_t id;
  HostTexture* texture;
};

static const FlutterDesktopPixelBuffer* host_texture_callback(size_t width,
                                                              size_t height,
                                                              void* user) {
  // The engine passes the size it INTENDS to draw at; a pixel-buffer texture
  // answers with what it has and lets the compositor scale.
  (void)width;
  (void)height;
  HostTexture* texture = (HostTexture*)user;
  return texture != NULL ? &texture->buffer : NULL;
}

static void host_texture_free(void* user) {
  HostTexture* texture = (HostTexture*)user;
  if (texture == NULL) return;
  flwin32_icon_free(texture->pixels);
  free(texture);
}

static FlutterDesktopTextureRegistrarRef host_texture_registrar(
    FlWin32Host* host) {
  if (host == NULL || host->controller == NULL) return NULL;
  FlutterDesktopEngineRef engine =
      FlutterDesktopViewControllerGetEngine(host->controller);
  if (engine == NULL) return NULL;
  return FlutterDesktopEngineGetTextureRegistrar(engine);
}

// Both icon entry points land here; only the rasterize call differs.
static int64_t register_pixels(FlWin32Host* host,
                               uint8_t* pixels,
                               int32_t width,
                               int32_t height) {
  FlutterDesktopTextureRegistrarRef registrar = host_texture_registrar(host);
  if (registrar == NULL) {
    flwin32_icon_free(pixels);
    return -1;
  }

  HostTexture* texture = (HostTexture*)calloc(1, sizeof(HostTexture));
  if (texture == NULL) {
    flwin32_icon_free(pixels);
    return -1;
  }
  texture->pixels = pixels;
  texture->buffer.buffer = pixels;
  texture->buffer.width = (size_t)width;
  texture->buffer.height = (size_t)height;

  FlutterDesktopTextureInfo info;
  memset(&info, 0, sizeof(info));
  info.type = kFlutterDesktopPixelBufferTexture;
  info.pixel_buffer_config.callback = host_texture_callback;
  info.pixel_buffer_config.user_data = texture;

  int64_t id =
      FlutterDesktopTextureRegistrarRegisterExternalTexture(registrar, &info);
  if (id <= 0) {
    host_texture_free(texture);
    return -1;
  }

  if (host->texture_count == host->texture_capacity) {
    int grown = host->texture_capacity == 0 ? 8 : host->texture_capacity * 2;
    struct HostTextureSlot* slots = (struct HostTextureSlot*)realloc(
        host->textures, (size_t)grown * sizeof(struct HostTextureSlot));
    if (slots == NULL) {
      // Registered but untracked: leak the buffer rather than free something
      // the engine is about to call back into.
      return id;
    }
    host->textures = slots;
    host->texture_capacity = grown;
  }
  host->textures[host->texture_count].id = id;
  host->textures[host->texture_count].texture = texture;
  host->texture_count++;

  // Without this the texture is registered and never painted: the engine only
  // pulls a buffer once it has been told there is one.
  FlutterDesktopTextureRegistrarMarkExternalTextureFrameAvailable(registrar, id);
  return id;
}

// Register pixels that were rasterized SOMEWHERE ELSE.
//
// The two halves of making an icon have very different rules: rasterizing is
// GDI and the shell, thread-safe and slow (measured 607ms for the launcher's
// 79 icons); registering is the engine's texture registrar and belongs to the
// platform thread. Keeping them in one call forced both onto the UI thread.
//
// Takes ownership of `pixels` either way: on success the texture frees it, on
// failure this does.
int64_t flwin32_host_register_pixels(FlWin32Host* host,
                                     uint8_t* pixels,
                                     int32_t width,
                                     int32_t height) {
  if (host == NULL || pixels == NULL) {
    flwin32_icon_free(pixels);
    return -1;
  }
  return register_pixels(host, pixels, width, height);
}

int64_t flwin32_host_register_icon_texture(FlWin32Host* host,
                                           uint64_t window,
                                           int32_t size) {
  if (host == NULL) return -1;
  uint8_t* pixels = NULL;
  int32_t width = 0, height = 0;
  if (!flwin32_icon_rasterize(window, size, &pixels, &width, &height)) return -1;
  return register_pixels(host, pixels, width, height);
}

int64_t flwin32_host_register_icon_texture_path(FlWin32Host* host,
                                                const char* path,
                                                int32_t size) {
  if (host == NULL) return -1;
  uint8_t* pixels = NULL;
  int32_t width = 0, height = 0;
  if (!flwin32_icon_rasterize_path(path, size, &pixels, &width, &height)) {
    return -1;
  }
  return register_pixels(host, pixels, width, height);
}

void flwin32_host_unregister_texture(FlWin32Host* host, int64_t texture_id) {
  FlutterDesktopTextureRegistrarRef registrar = host_texture_registrar(host);
  if (registrar == NULL) return;

  for (int i = 0; i < host->texture_count; i++) {
    if (host->textures[i].id != texture_id) continue;
    HostTexture* texture = host->textures[i].texture;
    host->textures[i] = host->textures[host->texture_count - 1];
    host->texture_count--;
    FlutterDesktopTextureRegistrarUnregisterExternalTexture(
        registrar, texture_id, host_texture_free, texture);
    return;
  }
}

// ── the cursor over the view ───────────────────────────────────────────────
//
// Nobody sets the cursor, so it keeps whatever shape it had on the way in.
//
// The engine's FLUTTERVIEW class registers IDC_ARROW like any other, but its
// wndproc answers WM_SETCURSOR over the client area with a bare `return TRUE`
// and no SetCursor at all — deliberately, and the comment there says why: it
// is stopping DefWindowProc from applying the class cursor, because in real
// Flutter the DART framework owns the pointer and pushes a cursor over the
// `flutter/mousecursor` channel on every mouse-tracker update.
//
// This port has no Dart VM and does not yet drive that channel (the same gap
// that leaves MouseRegion.onEnter/onExit silent), so the SetCursor at the end
// of that chain is never reached by anyone. The cursor therefore holds the
// shape it happened to have when it crossed into our window — and for a shell
// surface launched at login that is the busy ring, which then spins over the
// dock forever. It looks like a hung process and measures as a responsive one.
//
// So the frame puts the class cursor back: subclass the view and answer
// WM_SETCURSOR the way DefWindowProc would have. This is the DEFAULT, not a
// policy — when the mouse tracker is ported, the cursor it chooses should be
// set here rather than by reinstating the engine's silence.
static const wchar_t kChildProcProp[] = L"StarlingChildWndProc";

static LRESULT CALLBACK child_cursor_wnd_proc(HWND hwnd, UINT message,
                                              WPARAM wparam, LPARAM lparam) {
  WNDPROC original = (WNDPROC)GetPropW(hwnd, kChildProcProp);

  if (message == WM_PAINT) {
    static int first = 1;
    if (first) { first = 0; flwin32_trace("child window: first WM_PAINT"); }
  }

  if (message == WM_SETCURSOR && LOWORD(lparam) == HTCLIENT) {
    SetCursor(LoadCursorW(NULL, IDC_ARROW));
    return TRUE;
  }

  // Undo the subclass while the window still exists: WM_NCDESTROY is the last
  // message it receives, and a property left behind outlives the HWND.
  if (message == WM_NCDESTROY) {
    if (original != NULL) {
      SetWindowLongPtrW(hwnd, GWLP_WNDPROC, (LONG_PTR)original);
    }
    RemovePropW(hwnd, kChildProcProp);
  }

  return original != NULL
             ? CallWindowProcW(original, hwnd, message, wparam, lparam)
             : DefWindowProcW(hwnd, message, wparam, lparam);
}

// Subclass by GWLP_WNDPROC with the original kept in a window PROPERTY rather
// than a static: the embedder already owns the child's GWLP_USERDATA (it
// stores its FlutterWindow* there), and a static would tie this to one host
// per process, which is a constraint the rest of this file does not have.
static void install_child_cursor_proc(HWND child) {
  if (child == NULL || GetPropW(child, kChildProcProp) != NULL) return;
  WNDPROC original =
      (WNDPROC)SetWindowLongPtrW(child, GWLP_WNDPROC, (LONG_PTR)child_cursor_wnd_proc);
  if (original == NULL) return;
  if (!SetPropW(child, kChildProcProp, (HANDLE)original)) {
    // Could not record the original, so do not leave ours in its place.
    SetWindowLongPtrW(child, GWLP_WNDPROC, (LONG_PTR)original);
  }
}

// ── overlays: a full-screen surface that is usually not there ───────────────
//
// The launcher, and later Mission Control. Different from a panel in every
// way that matters: it covers the whole monitor rather than an edge, it
// reserves nothing, it TAKES focus (a launcher you cannot type into is a
// picture of a launcher), and it spends most of its life hidden.
//
// Hidden, not dead. Starting an engine costs a second or so, which is fine
// for an app and unacceptable for something the user expects to appear the
// instant they ask. So the process stays up with its window hidden, and
// showing it is a ShowWindow.


void flwin32_host_set_overlay(FlWin32Host* host, int32_t monitor, int32_t alpha,
                              int32_t width_pt, int32_t height_pt,
                              int32_t margin_pt) {
  if (host == NULL || host->window == NULL) return;
  host->overlay_active = 1;
  host->overlay_monitor = monitor;

  host->overlay_width_pt = width_pt;
  host->overlay_height_pt = height_pt;
  host->overlay_margin_pt = margin_pt;

  // Rounded corners on a floating panel, square on a full-screen one.
  //
  // DWM does the rounding, which is the only way to get it: the swap chain is
  // opaque and the window is layered with a uniform alpha, so we cannot cut
  // the corners out ourselves without per-pixel alpha we do not have. Best
  // effort — the attribute is Windows 11 and simply fails on 10.
  if (width_pt > 0 && height_pt > 0) {
    DWM_WINDOW_CORNER_PREFERENCE corner = DWMWCP_ROUND;
    DwmSetWindowAttribute(host->window, DWMWA_WINDOW_CORNER_PREFERENCE,
                          &corner, sizeof(corner));
  }

  RECT area;
  if (!overlay_area(host, &area)) return;

  // WS_VISIBLE in the style, exactly as the panel path sets it, and NOT an
  // oversight to tidy away: a restyle that leaves it out stops the embedder
  // scheduling frames, so the tree never builds, initState never runs and the
  // surface comes up blank, in the window class's brush. The panel path had it
  // from the start, which is why the bar and the dock never showed this.
  SetWindowLongPtrW(host->window, GWL_STYLE, WS_POPUP | WS_VISIBLE);
  LONG_PTR ex = GetWindowLongPtrW(host->window, GWL_EXSTYLE);
  // TOOLWINDOW keeps it out of Alt+Tab; no NOACTIVATE, because this one wants
  // the keyboard. LAYERED is what gives the whole surface a uniform alpha —
  // the frosted-panel look, without a blur we have no cheap way to do.
  ex |= WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_LAYERED;
  ex &= ~(LONG_PTR)WS_EX_NOACTIVATE;
  SetWindowLongPtrW(host->window, GWL_EXSTYLE, ex);
  if (alpha < 0) alpha = 255;
  if (alpha > 255) alpha = 255;
  host->overlay_alpha = alpha;
  SetLayeredWindowAttributes(host->window, 0, (BYTE)alpha, LWA_ALPHA);

  host->overlay_rect = area;
  overlay_park(host);
}

// Parking: on screen at full size, and completely transparent.
//
// Three ways to keep a surface off screen, and only one of them works here.
//
// SW_HIDE and parking OFF-SCREEN both stop the embedder scheduling frames,
// and this framework builds its widget tree on the first FRAME REQUEST rather
// than at runApp -- so a launcher parked either way has never run initState
// and comes up blank. (Asking for a frame explicitly with
// FlutterDesktopViewControllerForceRedraw does not rescue it: measured, a
// hidden view stays unmounted.)
//
// This was therefore parked as a 1x1 window in the corner. That is genuinely
// on screen, but a one-pixel surface turns out to be no better: a launcher
// parked at 1x1 for 54 SECONDS had still never mounted its tree. What it did
// do was make showing the launcher a resize from 1x1 to 3840x2160 -- and the
// Windows embedder resizes its surface SYNCHRONOUSLY on WM_SIZE, so that one
// SetWindowPos cost 161ms of the 167ms it took to open.
//
// So: FULL SIZE, on screen, at layer alpha ZERO and click-through. Nothing to
// see and nothing to click, but a real full-size surface that is composited,
// so frames flow and the tree mounts at STARTUP. Showing it is then an alpha
// change and a z-order raise -- no resize, nothing synchronous, nothing to
// build. The window is created at the monitor's size in the first place
// (runStarlingApp is handed the screen geometry), so it is never resized at
// any point in its life.
//
// The cost is one permanently composited full-screen layer. It is fully
// transparent and sits at the bottom of the z-order, and DWM only recomposites
// on change, so on an idle desktop it is not redrawing anything.

// The overlay's rectangle, recomputed from the monitor it was placed on.
//
// Only the rectangle -- going through flwin32_host_set_overlay again would
// re-park it, and this runs both on the way up and while the surface is
// already on screen.
// Where the overlay sits: the whole monitor, or a floating panel above the
// dock.
//
// A sized overlay is anchored to the WORK AREA rather than the monitor, and
// that is the whole trick — the dock registers itself as an appbar, so the
// work area already stops where the dock starts. Anchoring here means the
// panel sits above the dock with no arithmetic about how tall the dock is and
// nothing to keep in step when that changes.
//
// Points, not pixels: the caller says 720x640 and this multiplies by the
// monitor's scale, so the panel is the same physical size on a 4K laptop
// panel as on a 1080p external.
static int overlay_area(FlWin32Host* host, RECT* out) {
  MONITORINFO mi = {sizeof(MONITORINFO)};
  MonitorPick pick = {0};
  pick.want = host->overlay_monitor;
  if (host->overlay_monitor >= 0) {
    EnumDisplayMonitors(NULL, NULL, monitor_pick_cb, (LPARAM)&pick);
  }
  HMONITOR mon;
  if (pick.found) {
    POINT centre = {(pick.rect.left + pick.rect.right) / 2,
                    (pick.rect.top + pick.rect.bottom) / 2};
    mon = MonitorFromPoint(centre, MONITOR_DEFAULTTOPRIMARY);
  } else {
    mon = MonitorFromWindow(host->window, MONITOR_DEFAULTTOPRIMARY);
  }
  if (!GetMonitorInfoW(mon, &mi)) return 0;

  // Unsized: the whole monitor, as before.
  if (host->overlay_width_pt <= 0 || host->overlay_height_pt <= 0) {
    *out = pick.found ? pick.rect : mi.rcMonitor;
    return 1;
  }

  UINT dpi_x = 0, dpi_y = 0;
  double scale = 1.0;
  if (SUCCEEDED(GetDpiForMonitor(mon, MDT_EFFECTIVE_DPI, &dpi_x, &dpi_y))
      && dpi_x != 0) {
    scale = (double)dpi_x / (double)USER_DEFAULT_SCREEN_DPI;
  }
  LONG w = (LONG)(host->overlay_width_pt * scale);
  LONG h = (LONG)(host->overlay_height_pt * scale);
  LONG margin = (LONG)(host->overlay_margin_pt * scale);

  RECT work = mi.rcWork;
  LONG avail_w = work.right - work.left;
  LONG avail_h = work.bottom - work.top;
  if (w > avail_w) w = avail_w;
  if (h > avail_h - margin) h = avail_h - margin;

  // Centred horizontally, sitting just above the bottom of the work area —
  // where Windows 11 puts its own Start menu, and where the dock is.
  out->left = work.left + (avail_w - w) / 2;
  out->right = out->left + w;
  out->bottom = work.bottom - margin;
  out->top = out->bottom - h;
  return 1;
}

static void overlay_rederive(FlWin32Host* host) {
  RECT area;
  if (overlay_area(host, &area)) host->overlay_rect = area;
}

static void overlay_park(FlWin32Host* host) {
  flwin32_trace("overlay_park");
  UnregisterHotKey(host->window, kOverlayEscapeHotkey);
  LONG_PTR ex = GetWindowLongPtrW(host->window, GWL_EXSTYLE);
  SetWindowLongPtrW(host->window, GWL_EXSTYLE, ex | WS_EX_TRANSPARENT);
  // Hidden, and still at its full size, so showing it is never a resize.
  SetWindowPos(host->window, HWND_BOTTOM,
               host->overlay_rect.left, host->overlay_rect.top,
               host->overlay_rect.right - host->overlay_rect.left,
               host->overlay_rect.bottom - host->overlay_rect.top,
               SWP_FRAMECHANGED | SWP_HIDEWINDOW | SWP_NOACTIVATE);
  host->overlay_shown = 0;
}

int32_t flwin32_host_is_visible(FlWin32Host* host) {
  if (host == NULL || host->window == NULL) return 0;
  // A parked overlay is hidden, and a shown one may still be mid-transition,
  // so its own flag is the only truthful answer.
  if (host->overlay_active) return host->overlay_shown;
  return IsWindowVisible(host->window) ? 1 : 0;
}

void flwin32_host_set_visible(FlWin32Host* host, int32_t visible) {
  if (host == NULL || host->window == NULL) return;
  if (!host->overlay_active) {
    ShowWindow(host->window, visible ? SW_SHOW : SW_HIDE);
    return;
  }

  if (!visible) {
    overlay_park(host);
    return;
  }

  flwin32_trace("set_visible(1): begin");
  // Re-derive the geometry on the way up: the monitor may have changed size,
  // or gone, since the last time this was shown.
  overlay_rederive(host);

  LONG_PTR ex = GetWindowLongPtrW(host->window, GWL_EXSTYLE);
  SetWindowLongPtrW(host->window, GWL_EXSTYLE, ex & ~(LONG_PTR)WS_EX_TRANSPARENT);
  // Opacity back before the raise, for the same reason the park drops it
  // after: whichever of the two happens first must not be the visible one.
  SetLayeredWindowAttributes(host->window, 0, (BYTE)host->overlay_alpha,
                             LWA_ALPHA);
  SetWindowPos(host->window, HWND_TOPMOST,
               host->overlay_rect.left, host->overlay_rect.top,
               host->overlay_rect.right - host->overlay_rect.left,
               host->overlay_rect.bottom - host->overlay_rect.top,
               SWP_FRAMECHANGED | SWP_SHOWWINDOW | SWP_NOACTIVATE);
  host->overlay_shown = 1;
  flwin32_trace("set_visible(1): window shown");
  // Ask for a frame explicitly.
  //
  // Nothing else will. The window is shown at the size it already had, so
  // there is no WM_SIZE and no resize-driven render; and a window coming back
  // from SW_HIDE gets no WM_PAINT of its own either, because its client area
  // was never invalidated. Without this the launcher appears and stays blank
  // -- which is exactly what the old 1x1 park was working around, at the cost
  // of a 161ms synchronous 4K resize on every first open. This is the same
  // path WM_PAINT would have taken (OnPaint -> OnWindowRepaint -> ForceRedraw),
  // just asked for directly.
  FlutterDesktopViewControllerForceRedraw(host->controller);
  flwin32_trace("set_visible(1): redraw requested");
  RegisterHotKey(host->window, kOverlayEscapeHotkey, 0, VK_ESCAPE);
  // Through the window manager's own activate, which owns the
  // AttachThreadInput dance: the process asking for this is usually the BAR,
  // not us, so we are not the foreground process and a bare
  // SetForegroundWindow would be refused.
  flwin32_wm_activate((uint64_t)(uintptr_t)host->window);
}

void flwin32_host_on_toggle(FlWin32Host* host,
                            void (*callback)(void* user),
                            void* user) {
  if (host == NULL) return;
  host->toggle_callback = callback;
  host->toggle_user = user;
}

void flwin32_shell_broadcast_toggle(void) {
  // HWND_BROADCAST reaches every top-level window in the session, and only
  // the process that registered the same string recognises the id. PostMessage
  // rather than Send: a broadcast Send blocks on every hung window on the
  // desktop, which is the whole shell's responsiveness bet on other people's
  // apps.
  PostMessageW(HWND_BROADCAST, starling_toggle_message(), 0, 0);
}
