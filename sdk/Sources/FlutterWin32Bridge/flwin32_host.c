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

// Direct inclusion of the vendored embedder headers, the same way the GTK
// bridge includes flutter_linux. Their cross-references are quoted-relative,
// so no include path is needed.
#include "flutter_windows/flutter_windows.h"

// The engine's own Win32 embedder owns the child window; ours is only the
// top-level frame that hosts it, so the state here is small.
struct FlWin32Host {
  HWND window;
  HWND child;  // the view's HWND, owned by the view controller
  FlutterDesktopViewControllerRef controller;
  int fullscreen;
  WINDOWPLACEMENT saved_placement;  // to restore from fullscreen
};

static const wchar_t kWindowClass[] = L"FlutterSwiftWin32Host";

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

  switch (message) {
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
      if (lparam != 0) {
        const RECT* suggested = (const RECT*)lparam;
        SetWindowPos(hwnd, NULL, suggested->left, suggested->top,
                     suggested->right - suggested->left,
                     suggested->bottom - suggested->top,
                     SWP_NOZORDER | SWP_NOACTIVATE);
      }
      return 0;

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
      PostQuitMessage(0);
      return 0;

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

  // Per-monitor DPI so the engine sees a truthful pixel ratio. Best effort:
  // a manifest may have set awareness already, in which case this fails and
  // the existing setting stands.
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

  WNDCLASSEXW wc = {0};
  wc.cbSize = sizeof(WNDCLASSEXW);
  wc.style = CS_HREDRAW | CS_VREDRAW;
  wc.lpfnWndProc = host_wnd_proc;
  wc.hInstance = instance;
  wc.hCursor = LoadCursorW(NULL, IDC_ARROW);
  wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
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

  FlutterDesktopEngineRef engine = FlutterDesktopEngineCreate(&properties);
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

  SetWindowLongPtrW(window, GWLP_USERDATA, (LONG_PTR)host);
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

void flwin32_host_set_panel(FlWin32Host* host,
                            int32_t edge,
                            int32_t thickness,
                            int32_t monitor) {
  if (host == NULL || host->window == NULL) return;

  RECT area;
  MonitorPick pick = {0};
  pick.want = monitor;
  if (monitor >= 0) {
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

  int32_t x, y, w, h;
  switch (edge) {
    case 1:  // bottom
      x = area.left;
      y = area.bottom - thickness;
      w = area.right - area.left;
      h = thickness;
      break;
    case 2:  // left
      x = area.left;
      y = area.top;
      w = thickness;
      h = area.bottom - area.top;
      break;
    case 3:  // right
      x = area.right - thickness;
      y = area.top;
      w = thickness;
      h = area.bottom - area.top;
      break;
    default:  // top
      x = area.left;
      y = area.top;
      w = area.right - area.left;
      h = thickness;
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
  LONG_PTR ex = GetWindowLongPtrW(host->window, GWL_EXSTYLE);
  SetWindowLongPtrW(host->window, GWL_EXSTYLE,
                    ex | WS_EX_TOOLWINDOW | WS_EX_TOPMOST);
  SetWindowPos(host->window, HWND_TOPMOST, x, y, w, h,
               SWP_FRAMECHANGED | SWP_SHOWWINDOW | SWP_NOACTIVATE);
}
