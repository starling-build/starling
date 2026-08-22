// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Surface views: the one-app shell exploration (branch winshell-oneapp).
//
// The popup work (flwin32_popup.c) proved the mechanism — a second engine
// view in its own top-level window, with a widget tree of its own keyed by
// view id. This file generalizes it from menu-shaped popups to SHELL
// SURFACES, so the dock's process can also own the desktop (wallpaper +
// icon grid) and the launcher (Start) instead of spawning a process per
// surface: one engine, one Swift runtime, one icon cache, and a toggle
// that is a window message to a window that already exists.
//
// Two kinds, because the shell has two window shapes left once the panel
// (the process's own implicit view) is taken:
//
//  - DESKTOP: the full monitor, pinned to the BOTTOM of the z-order through
//    every activation by the same WM_WINDOWPOSCHANGING clamp the
//    single-process desktop uses, shown without activation and only after
//    its view's first composite — the 7c8cc9a lesson (a desktop shown
//    before its first frame paints an empty tree and nothing ever
//    invalidates it with explorer gone) solved the way popups solved it,
//    by never showing an uncomposited surface at all.
//
//  - OVERLAY: a sized panel centred at the bottom of the WORK area (the
//    launcher's geometry), rounded by DWM, created HIDDEN at its final
//    size. Unlike a popup it ACTIVATES: the launcher owns a search field,
//    so showing it takes the foreground and focuses the view child — which
//    is also what makes click-away dismissal an ordinary WA_INACTIVE. It
//    listens for the launcher toggle broadcast itself, so the dock tile,
//    the Windows key, and any external driver keep working unchanged.
//
// A hidden surface still composites: the multi-view path builds and
// commits scenes for every engine view regardless of window visibility
// (popups depend on this — they are shown only after their first
// composite). That retires the entire parked-overlay dance the
// process-per-surface world needed (full-size parks, same-size WM_SIZE
// kicks, LauncherPreload): a surface view's tree mounts at process start,
// hidden, for free.

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include "include/FlutterWin32Bridge.h"

#include <windows.h>
#include <dwmapi.h>
#include <stdio.h>

#include "flutter_windows/flutter_windows.h"

// Same declaration as flwin32_popup.c: exported from flutter_windows.dll,
// declared only in upstream's internal header.
typedef struct {
  int width;
  int height;
} FlutterDesktopViewControllerProperties;

FLUTTER_EXPORT FlutterDesktopViewControllerRef
FlutterDesktopEngineCreateViewController(
    FlutterDesktopEngineRef engine,
    const FlutterDesktopViewControllerProperties* properties);

#define kMaxSurfaces 4

typedef struct {
  int64_t view_id;  // 0 = slot free
  int32_t kind;     // FLWIN32_SURFACE_DESKTOP / _OVERLAY
  HWND window;
  FlutterDesktopViewControllerRef controller;
  FlWin32Host* host;
} SurfaceSlot;

static SurfaceSlot surfaces[kMaxSurfaces];

static void (*overlay_toggled_cb)(void* user, int64_t view_id,
                                  int32_t visible) = NULL;
static void* overlay_toggled_user = NULL;

static const wchar_t kSurfaceClass[] = L"StarlingSurfaceView";

// The launcher toggle broadcast. Registered per string process-wide, so this
// is the same id flwin32_host.c and every external driver resolves.
static UINT surface_toggle_message(void) {
  static UINT id = 0;
  if (id == 0) id = RegisterWindowMessageW(L"StarlingShellToggleOverlay");
  return id;
}

static SurfaceSlot* surface_for_view(int64_t view_id) {
  for (int i = 0; i < kMaxSurfaces; i++) {
    if (surfaces[i].view_id == view_id && surfaces[i].view_id != 0) {
      return &surfaces[i];
    }
  }
  return NULL;
}

static SurfaceSlot* surface_for_window(HWND hwnd) {
  for (int i = 0; i < kMaxSurfaces; i++) {
    if (surfaces[i].view_id != 0 && surfaces[i].window == hwnd) {
      return &surfaces[i];
    }
  }
  return NULL;
}

static void overlay_notify(SurfaceSlot* slot, int visible) {
  if (overlay_toggled_cb != NULL) {
    overlay_toggled_cb(overlay_toggled_user, slot->view_id, visible);
  }
}

static void overlay_show(SurfaceSlot* slot) {
  ShowWindow(slot->window, SW_SHOW);
  // Foreground + child focus: the launcher's keyboard (search, arrows,
  // Escape) rides ordinary Win32 focus on the view child, which tags its
  // key events with this view — no global hotkeys, no broadcast replies.
  SetForegroundWindow(slot->window);
  HWND child = GetWindow(slot->window, GW_CHILD);
  if (child != NULL) SetFocus(child);
  overlay_notify(slot, 1);
}

static void overlay_hide(SurfaceSlot* slot) {
  if (!IsWindowVisible(slot->window)) return;
  ShowWindow(slot->window, SW_HIDE);
  overlay_notify(slot, 0);
}

static LRESULT CALLBACK surface_wnd_proc(HWND hwnd, UINT message,
                                         WPARAM wparam, LPARAM lparam) {
  SurfaceSlot* slot = surface_for_window(hwnd);

  if (slot != NULL && slot->kind == FLWIN32_SURFACE_OVERLAY &&
      message == surface_toggle_message()) {
    if (IsWindowVisible(hwnd)) {
      overlay_hide(slot);
    } else {
      overlay_show(slot);
    }
    return 0;
  }

  switch (message) {
    case WM_WINDOWPOSCHANGING:
      // The desktop holds the BOTTOM of the z-order whatever asks otherwise
      // — same clamp, same reason as flwin32_host.c's desktop mode.
      if (slot != NULL && slot->kind == FLWIN32_SURFACE_DESKTOP) {
        WINDOWPOS* pos = (WINDOWPOS*)lparam;
        if (pos != NULL && !(pos->flags & SWP_NOZORDER)) {
          pos->hwndInsertAfter = HWND_BOTTOM;
        }
        return 0;
      }
      break;
    case WM_ACTIVATE:
      // Click-away dismissal for the overlay: losing activation IS the
      // "user engaged something else" signal, the same rule the
      // process-per-surface launcher used.
      if (slot != NULL && slot->kind == FLWIN32_SURFACE_OVERLAY &&
          LOWORD(wparam) == WA_INACTIVE) {
        overlay_hide(slot);
        return 0;
      }
      break;
    case WM_ERASEBKGND: {
      // Theme-coloured for the overlay (the popup lesson: a black flash
      // announces the gap before the first present), black for the desktop
      // (wallpaper covers every pixel).
      if (slot != NULL && slot->kind == FLWIN32_SURFACE_OVERLAY) {
        COLORREF fill = flwin32_apps_use_light_theme() ? RGB(0xF3, 0xF3, 0xF3)
                                                       : RGB(0x20, 0x20, 0x20);
        HBRUSH brush = CreateSolidBrush(fill);
        RECT frame;
        GetClientRect(hwnd, &frame);
        FillRect((HDC)wparam, &frame, brush);
        DeleteObject(brush);
        return 1;
      }
      break;
    }
    case WM_SIZE: {
      HWND child = GetWindow(hwnd, GW_CHILD);
      if (child != NULL) {
        RECT frame;
        GetClientRect(hwnd, &frame);
        MoveWindow(child, 0, 0, frame.right - frame.left,
                   frame.bottom - frame.top, TRUE);
      }
      return 0;
    }
    default:
      break;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

static void ensure_surface_class(void) {
  static int registered = 0;
  if (registered) return;
  registered = 1;
  WNDCLASSEXW wc = {0};
  wc.cbSize = sizeof(WNDCLASSEXW);
  wc.lpfnWndProc = surface_wnd_proc;
  wc.hInstance = GetModuleHandleW(NULL);
  wc.hCursor = LoadCursorW(NULL, IDC_ARROW);
  wc.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);
  wc.lpszClassName = kSurfaceClass;
  RegisterClassExW(&wc);
}

int64_t flwin32_surface_open(FlWin32Host* host, int32_t kind,
                             double width_pt, double height_pt,
                             double bottom_margin_pt) {
  if (host == NULL) return -1;
  SurfaceSlot* slot = NULL;
  for (int i = 0; i < kMaxSurfaces; i++) {
    if (surfaces[i].view_id == 0) {
      slot = &surfaces[i];
      break;
    }
  }
  if (slot == NULL) {
    fprintf(stderr, "[flwin32_surface] all %d slots in use\n", kMaxSurfaces);
    return -1;
  }

  FlutterDesktopEngineRef engine =
      (FlutterDesktopEngineRef)flwin32_host_engine(host);
  if (engine == NULL) return -1;

  ensure_surface_class();

  // The host's monitor — the one-monitor assumption the whole prototype
  // makes, matching the popup layer. Multi-monitor is the follow-up.
  HWND hostw = (HWND)flwin32_host_window(host);
  HMONITOR monitor = MonitorFromWindow(hostw, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info = {sizeof(MONITORINFO)};
  if (!GetMonitorInfoW(monitor, &info)) return -1;
  UINT dpi = GetDpiForWindow(hostw);
  double scale = (double)dpi / 96.0;

  RECT r;
  DWORD style = WS_POPUP;
  DWORD exstyle = WS_EX_TOOLWINDOW;
  if (kind == FLWIN32_SURFACE_DESKTOP) {
    // The whole monitor: the wallpaper runs under the dock, exactly as the
    // process-per-surface desktop does.
    r = info.rcMonitor;
  } else {
    // Centred at the bottom of the WORK area — the dock is an appbar, so
    // the work area already stops where the dock starts (the launcher's
    // own anchoring rule, kept).
    LONG w = (LONG)(width_pt * scale + 0.5);
    LONG h = (LONG)(height_pt * scale + 0.5);
    LONG margin = (LONG)(bottom_margin_pt * scale + 0.5);
    r.left = info.rcWork.left + ((info.rcWork.right - info.rcWork.left) - w) / 2;
    r.bottom = info.rcWork.bottom - margin;
    r.top = r.bottom - h;
    r.right = r.left + w;
    exstyle |= WS_EX_TOPMOST;
  }

  HWND window = CreateWindowExW(
      exstyle, kSurfaceClass, L"",
      style, r.left, r.top, r.right - r.left, r.bottom - r.top,
      // UNOWNED, both kinds — and for the overlay that is load-bearing:
      // PostMessage(HWND_BROADCAST) reaches invisible UNOWNED windows but
      // NOT invisible owned ones, so an owned launcher never hears the
      // toggle while hidden and Start silently does nothing. (The
      // process-per-surface launcher's window was unowned for free.)
      // Being TOPMOST and activated on show is what puts it above the dock.
      NULL,
      NULL, GetModuleHandleW(NULL), NULL);
  if (window == NULL) {
    fprintf(stderr, "[flwin32_surface] CreateWindowExW failed (%lu)\n",
            GetLastError());
    return -1;
  }

  if (kind == FLWIN32_SURFACE_OVERLAY) {
    DWM_WINDOW_CORNER_PREFERENCE corner = DWMWCP_ROUND;
    DwmSetWindowAttribute(window, DWMWA_WINDOW_CORNER_PREFERENCE, &corner,
                          sizeof(corner));
  }

  FlutterDesktopViewControllerProperties properties;
  properties.width = (int)(r.right - r.left);
  properties.height = (int)(r.bottom - r.top);
  FlutterDesktopViewControllerRef controller =
      FlutterDesktopEngineCreateViewController(engine, &properties);
  if (controller == NULL) {
    fprintf(stderr,
            "[flwin32_surface] CreateViewController failed\n");
    DestroyWindow(window);
    return -1;
  }

  HWND child =
      FlutterDesktopViewGetHWND(FlutterDesktopViewControllerGetView(controller));
  SetParent(child, window);
  MoveWindow(child, 0, 0, (int)(r.right - r.left), (int)(r.bottom - r.top),
             TRUE);
  flwin32_install_child_cursor_proc(child);

  // Neither kind is shown here. The desktop shows on its first composite
  // (flwin32_surface_show, from the Swift side); the overlay shows on its
  // first toggle.

  int64_t view_id = (int64_t)FlutterDesktopViewControllerGetViewId(controller);
  slot->view_id = view_id;
  slot->kind = kind;
  slot->window = window;
  slot->controller = controller;
  slot->host = host;
  return view_id;
}

void flwin32_surface_show(FlWin32Host* host, int64_t view_id) {
  SurfaceSlot* slot = surface_for_view(view_id);
  if (slot == NULL || slot->host != host) return;
  if (IsWindowVisible(slot->window)) return;
  if (slot->kind == FLWIN32_SURFACE_DESKTOP) {
    // Bottom of the z-order, no activation — and the window only exists on
    // screen once its view has composited, so there is no empty first
    // paint to rescue.
    ShowWindow(slot->window, SW_SHOWNOACTIVATE);
    SetWindowPos(slot->window, HWND_BOTTOM, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  } else {
    overlay_show(slot);
  }
}

int32_t flwin32_surface_is_visible(FlWin32Host* host, int64_t view_id) {
  SurfaceSlot* slot = surface_for_view(view_id);
  if (slot == NULL || slot->host != host) return 0;
  return IsWindowVisible(slot->window) ? 1 : 0;
}

void flwin32_surface_set_visible(FlWin32Host* host, int64_t view_id,
                                 int32_t visible) {
  SurfaceSlot* slot = surface_for_view(view_id);
  if (slot == NULL || slot->host != host) return;
  if (slot->kind == FLWIN32_SURFACE_OVERLAY) {
    if (visible) {
      overlay_show(slot);
    } else {
      overlay_hide(slot);
    }
  } else {
    ShowWindow(slot->window, visible ? SW_SHOWNOACTIVATE : SW_HIDE);
  }
}

void flwin32_surface_close(FlWin32Host* host, int64_t view_id) {
  SurfaceSlot* slot = surface_for_view(view_id);
  if (slot == NULL || slot->host != host) return;
  FlutterDesktopViewControllerDestroy(slot->controller);
  DestroyWindow(slot->window);
  slot->view_id = 0;
  slot->kind = 0;
  slot->window = NULL;
  slot->controller = NULL;
  slot->host = NULL;
}

void flwin32_surface_on_overlay_toggled(void (*cb)(void* user, int64_t view_id,
                                                   int32_t visible),
                                        void* user) {
  overlay_toggled_cb = cb;
  overlay_toggled_user = user;
}

int32_t flwin32_surface_client_size(FlWin32Host* host, int64_t view_id,
                                    double* width_pt, double* height_pt) {
  *width_pt = 0;
  *height_pt = 0;
  SurfaceSlot* slot = surface_for_view(view_id);
  if (slot == NULL || slot->host != host) return 0;
  RECT r;
  if (!GetClientRect(slot->window, &r)) return 0;
  UINT dpi = GetDpiForWindow(slot->window);
  if (dpi == 0) return 0;
  double scale = (double)dpi / 96.0;
  *width_pt = (double)(r.right - r.left) / scale;
  *height_pt = (double)(r.bottom - r.top) / scale;
  return 1;
}

uint64_t flwin32_surface_window(FlWin32Host* host, int64_t view_id) {
  SurfaceSlot* slot = surface_for_view(view_id);
  if (slot == NULL || slot->host != host) return 0;
  return (uint64_t)(uintptr_t)slot->window;
}
