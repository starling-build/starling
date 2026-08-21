// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Popup surfaces: a second engine view in its own WS_POPUP window, so a menu
// can overhang the window it was opened from, stand taller than it, and later
// stand on nothing at all (tray flyouts, toast banners, the desktop's menu —
// the wave-2 consumers this file exists for).
//
// The whole trick is that the engine is MULTI-VIEW already:
// FlutterDesktopEngineCreateViewController hangs a second FlutterWindowsView
// off the running engine (owns_engine=false, so destroying it removes one
// view and nothing else), the view's HWND handles its own input tagged with
// its view id, and the Swift adapter builds a widget tree per view through
// multiViewContentBuilder. This file only owns the Win32 frame around that:
// a popup-styled top-level window the view child is parented into.
//
// The frame is WS_EX_NOACTIVATE and answers WM_MOUSEACTIVATE with
// MA_NOACTIVATE — a menu that stole activation would repaint the owner's
// titlebar inactive on every open, which native menus never do. Clicks still
// arrive (mouse input routes by position, not activation), and the keyboard
// stays with the host window, which is where the menu's arrow keys and
// Escape are handled anyway. Verified against the embedder: the view never
// takes focus on its own — FlutterWindow::Focus runs only on an explicit
// view-focus-change request, never from a click.
//
// Coordinates at this boundary are the HOST window's client area in LOGICAL
// POINTS — the one space the widget tree already thinks in — converted here
// with the host's own DPI. A popup may land outside the window; that is the
// point. Clamping is the caller's job (flwin32_host_popup_frame hands it the
// monitor's bounds in the same space), because only the caller knows a
// menu's anchor corner from its overflow edge.

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

// From flutter_windows_internal.h (engine repo), not the vendored public
// header: the multi-view entry point is exported from flutter_windows.dll
// (checked in the DLL's export table) but upstream still declares it in the
// internal header. Declared here verbatim rather than vendoring that header,
// which drags platform-view types this file has no use for.
typedef struct {
  int width;
  int height;
} FlutterDesktopViewControllerProperties;

FLUTTER_EXPORT FlutterDesktopViewControllerRef
FlutterDesktopEngineCreateViewController(
    FlutterDesktopEngineRef engine,
    const FlutterDesktopViewControllerProperties* properties);

// ── the popup table ────────────────────────────────────────────────────────
//
// A static table rather than fields on FlWin32Host: the host struct is
// private to flwin32_host.c, and a process has one host, so "per host" and
// "per process" are the same set. Eight is a ceiling, not a budget — a menu
// plus its submenu is two.

#define kMaxPopups 8

typedef struct {
  int64_t view_id;  // 0 = slot free (the implicit view is 0, never a popup)
  HWND window;
  FlutterDesktopViewControllerRef controller;
  FlWin32Host* host;
} PopupSlot;

static PopupSlot popups[kMaxPopups];

static void (*dismiss_callback)(void* user) = NULL;
static void* dismiss_user = NULL;

static const wchar_t kPopupClass[] = L"StarlingPopupSurface";

// The brush behind each popup, kept per window: whatever part of the surface
// becomes valid before the engine presents — the gap at open, and the new
// region a resize exposes — is painted with this. The host window uses BLACK
// there, which is right for colorkeyed chrome and was visibly wrong here: a
// menu popping over a light listing announced itself as a black rectangle
// for the frames before its first present. Menu-coloured, the same gap reads
// as the panel arriving.
static const wchar_t kPopupBrushProp[] = L"StarlingPopupBrush";

static PopupSlot* slot_for(int64_t view_id) {
  for (int i = 0; i < kMaxPopups; i++) {
    if (popups[i].view_id == view_id && popups[i].view_id != 0) {
      return &popups[i];
    }
  }
  return NULL;
}

static LRESULT CALLBACK popup_wnd_proc(HWND hwnd, UINT message, WPARAM wparam,
                                       LPARAM lparam) {
  switch (message) {
    case WM_MOUSEACTIVATE:
      // The reason this window class exists: take the click, refuse the
      // activation, exactly as a native menu window does.
      return MA_NOACTIVATE;
    case WM_ERASEBKGND: {
      HBRUSH brush = (HBRUSH)GetPropW(hwnd, kPopupBrushProp);
      if (brush != NULL) {
        RECT frame;
        GetClientRect(hwnd, &frame);
        FillRect((HDC)wparam, &frame, brush);
        return 1;
      }
      break;
    }
    case WM_NCDESTROY: {
      HBRUSH brush = (HBRUSH)GetPropW(hwnd, kPopupBrushProp);
      if (brush != NULL) {
        DeleteObject(brush);
        RemovePropW(hwnd, kPopupBrushProp);
      }
      break;
    }
    case WM_SIZE: {
      // Keep the view child filling the frame (flwin32_popup_place resizes
      // the frame; the child follows here, and its own proc carries the new
      // metrics to the engine).
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

static void ensure_popup_class(void) {
  static int registered = 0;
  if (registered) return;
  registered = 1;
  WNDCLASSEXW wc = {0};
  wc.cbSize = sizeof(WNDCLASSEXW);
  wc.lpfnWndProc = popup_wnd_proc;
  wc.hInstance = GetModuleHandleW(NULL);
  wc.hCursor = LoadCursorW(NULL, IDC_ARROW);
  // No class brush: WM_ERASEBKGND paints the per-window menu-coloured brush
  // (kPopupBrushProp) instead, because the right colour depends on the
  // theme at open time and a class has one brush for every popup.
  wc.hbrBackground = NULL;
  wc.lpszClassName = kPopupClass;
  RegisterClassExW(&wc);
}

// Host-client logical points → a screen-pixel rect.
static RECT popup_screen_rect(FlWin32Host* host, double x_pt, double y_pt,
                              double w_pt, double h_pt) {
  HWND hostw = (HWND)flwin32_host_window(host);
  UINT dpi = GetDpiForWindow(hostw);
  double scale = (double)dpi / 96.0;
  POINT origin = {0, 0};
  ClientToScreen(hostw, &origin);
  RECT r;
  r.left = origin.x + (LONG)(x_pt * scale + 0.5);
  r.top = origin.y + (LONG)(y_pt * scale + 0.5);
  r.right = r.left + (LONG)(w_pt * scale + 0.5);
  r.bottom = r.top + (LONG)(h_pt * scale + 0.5);
  return r;
}

int64_t flwin32_popup_open(FlWin32Host* host, double x_pt, double y_pt,
                           double w_pt, double h_pt) {
  if (host == NULL) return -1;
  PopupSlot* slot = NULL;
  for (int i = 0; i < kMaxPopups; i++) {
    if (popups[i].view_id == 0) {
      slot = &popups[i];
      break;
    }
  }
  if (slot == NULL) {
    fprintf(stderr, "[flwin32_popup] all %d popup slots in use\n", kMaxPopups);
    return -1;
  }

  FlutterDesktopEngineRef engine =
      (FlutterDesktopEngineRef)flwin32_host_engine(host);
  if (engine == NULL) return -1;

  ensure_popup_class();
  RECT r = popup_screen_rect(host, x_pt, y_pt, w_pt, h_pt);

  // NOACTIVATE so the owner's titlebar stays lit; TOOLWINDOW so no taskbar
  // entry and no Alt-Tab row; TOPMOST because a menu outranks every ordinary
  // window while it is up (it is dismissed the moment anything else is
  // engaged, so the flag never outstays a gesture).
  HWND window = CreateWindowExW(
      WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST, kPopupClass, L"",
      WS_POPUP, r.left, r.top, r.right - r.left, r.bottom - r.top,
      /*parent=*/(HWND)flwin32_host_window(host), NULL, GetModuleHandleW(NULL),
      NULL);
  if (window == NULL) {
    fprintf(stderr, "[flwin32_popup] CreateWindowExW failed (%lu)\n",
            GetLastError());
    return -1;
  }

  // The menu surface's own fill, per the theme AT OPEN (Win11.menuBgOpaque's
  // twin — 0xFCFCFC light, 0x2C2C2C dark). Owned by the window, freed in
  // WM_NCDESTROY.
  COLORREF fill = flwin32_apps_use_light_theme()
                      ? RGB(0xFC, 0xFC, 0xFC)
                      : RGB(0x2C, 0x2C, 0x2C);
  SetPropW(window, kPopupBrushProp, (HANDLE)CreateSolidBrush(fill));

  // The system's own rounding, which also buys the popup the DWM shadow a
  // native menu wears — this pair IS what a Windows 11 menu window is: DWM
  // clips the surface to the radius and shades outside it, and the content
  // fills its rectangle none the wiser. Failure (Windows 10) leaves the
  // corners square, which is what its menus look like anyway.
  DWM_WINDOW_CORNER_PREFERENCE corner = DWMWCP_ROUND;
  DwmSetWindowAttribute(window, DWMWA_WINDOW_CORNER_PREFERENCE, &corner,
                        sizeof(corner));

  FlutterDesktopViewControllerProperties properties;
  properties.width = (int)(r.right - r.left);
  properties.height = (int)(r.bottom - r.top);
  FlutterDesktopViewControllerRef controller =
      FlutterDesktopEngineCreateViewController(engine, &properties);
  if (controller == NULL) {
    fprintf(stderr,
            "[flwin32_popup] FlutterDesktopEngineCreateViewController failed\n");
    DestroyWindow(window);
    return -1;
  }

  HWND child =
      FlutterDesktopViewGetHWND(FlutterDesktopViewControllerGetView(controller));
  SetParent(child, window);
  MoveWindow(child, 0, 0, (int)(r.right - r.left), (int)(r.bottom - r.top),
             TRUE);
  flwin32_install_child_cursor_proc(child);

  // NOT shown here. The view has composited nothing yet, and a shown window
  // spends the frames until its first present as a flat rectangle — the
  // erase brush above makes that menu-coloured instead of black, and
  // flwin32_popup_show (called from the Swift side once the view's first
  // scene has been composited) shrinks it to nearly nothing.

  int64_t view_id =
      (int64_t)FlutterDesktopViewControllerGetViewId(controller);
  slot->view_id = view_id;
  slot->window = window;
  slot->controller = controller;
  slot->host = host;
  return view_id;
}

void flwin32_popup_show(FlWin32Host* host, int64_t view_id) {
  PopupSlot* slot = slot_for(view_id);
  if (slot == NULL || slot->host != host) return;
  if (!IsWindowVisible(slot->window)) {
    ShowWindow(slot->window, SW_SHOWNOACTIVATE);
  }
}

void flwin32_popup_place(FlWin32Host* host, int64_t view_id, double x_pt,
                         double y_pt, double w_pt, double h_pt) {
  PopupSlot* slot = slot_for(view_id);
  if (slot == NULL || slot->host != host) return;
  RECT r = popup_screen_rect(host, x_pt, y_pt, w_pt, h_pt);
  // The WM_SIZE this produces resizes the child, whose own proc hands the
  // engine the new metrics — the same route the host window's resize takes.
  SetWindowPos(slot->window, NULL, r.left, r.top, r.right - r.left,
               r.bottom - r.top, SWP_NOACTIVATE | SWP_NOZORDER);
}

void flwin32_popup_close(FlWin32Host* host, int64_t view_id) {
  PopupSlot* slot = slot_for(view_id);
  if (slot == NULL || slot->host != host) return;
  // Destroy the view first: owns_engine=false, so this removes exactly one
  // view (the engine tells the Swift side, which unmounts that view's tree)
  // and takes the child HWND with it. Then the frame.
  FlutterDesktopViewControllerDestroy(slot->controller);
  DestroyWindow(slot->window);
  slot->view_id = 0;
  slot->window = NULL;
  slot->controller = NULL;
  slot->host = NULL;
}

void flwin32_popup_close_all(FlWin32Host* host) {
  for (int i = 0; i < kMaxPopups; i++) {
    if (popups[i].view_id != 0 && popups[i].host == host) {
      flwin32_popup_close(host, popups[i].view_id);
    }
  }
}

int32_t flwin32_popup_count(FlWin32Host* host) {
  int32_t n = 0;
  for (int i = 0; i < kMaxPopups; i++) {
    if (popups[i].view_id != 0 && popups[i].host == host) n++;
  }
  return n;
}

void flwin32_popup_frame(FlWin32Host* host, double* left, double* top,
                         double* right, double* bottom) {
  *left = 0;
  *top = 0;
  *right = 0;
  *bottom = 0;
  if (host == NULL) return;
  HWND hostw = (HWND)flwin32_host_window(host);
  HMONITOR monitor = MonitorFromWindow(hostw, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info = {sizeof(MONITORINFO)};
  if (!GetMonitorInfoW(monitor, &info)) return;
  UINT dpi = GetDpiForWindow(hostw);
  double scale = (double)dpi / 96.0;
  if (scale <= 0) return;
  POINT origin = {0, 0};
  ClientToScreen(hostw, &origin);
  // The WORK area, not the monitor: a menu that opens under the taskbar is
  // a menu the user cannot read the bottom of.
  *left = (double)(info.rcWork.left - origin.x) / scale;
  *top = (double)(info.rcWork.top - origin.y) / scale;
  *right = (double)(info.rcWork.right - origin.x) / scale;
  *bottom = (double)(info.rcWork.bottom - origin.y) / scale;
}

void flwin32_popup_on_dismiss(void (*callback)(void* user), void* user) {
  dismiss_callback = callback;
  dismiss_user = user;
}

void flwin32_popup_notify_host_event(FlWin32Host* host) {
  if (flwin32_popup_count(host) == 0) return;
  if (dismiss_callback != NULL) dismiss_callback(dismiss_user);
}
