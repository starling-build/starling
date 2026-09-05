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

static void (*app_closed_cb)(void* user, int64_t view_id);
static void* app_closed_user;

static void app_notify_closed(SurfaceSlot* slot) {
  if (app_closed_cb != NULL && slot != NULL) {
    app_closed_cb(app_closed_user, slot->view_id);
  }
}

void flwin32_surface_on_app_closed(void (*cb)(void* user, int64_t view_id),
                                   void* user) {
  app_closed_cb = cb;
  app_closed_user = user;
}

/* The desktop's heal, as timers on its own window: shrink by one pixel,
 * restore a quarter second later (back to back the two coalesce into "same
 * size" and rebuild nothing), and the pair again four seconds on. */
enum {
  kHealTimerShrink1 = 0x5741,
  kHealTimerRestore1,
  kHealTimerShrink2,
  kHealTimerRestore2,
};

static void nudge_width(HWND window, int delta) {
  RECT r;
  if (!GetWindowRect(window, &r)) return;
  int w = (int)(r.right - r.left) + delta;
  int h = (int)(r.bottom - r.top);
  if (w < 1 || h < 1) return;
  SetWindowPos(window, NULL, 0, 0, w, h,
               SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
}

/* Fill the desktop surface's monitor. The window is sized to its monitor once,
 * at creation (flwin32_surface_open, FLWIN32_SURFACE_DESKTOP -> rcMonitor);
 * a later MODE CHANGE — a monitor swapped, or a VM console attaching and
 * bumping the guest from its headless boot resolution to the host's screen —
 * moves nothing, so the wallpaper covers only the boot-sized top-left and the
 * rest of the screen shows as bare black desktop. The dock re-parks on the
 * same WM_DISPLAYCHANGE (panel_apply_placement, flwin32_host.c); this is the
 * desktop's half of it. The WM_SIZE this triggers carries the new size down to
 * the view and reloads the wallpaper (Desktop.loadWallpaper keys on the window
 * size), exactly as the manual resize that healed it did. */
static void desktop_fill_monitor(HWND window) {
  HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info = {sizeof(MONITORINFO)};
  if (!GetMonitorInfoW(monitor, &info)) return;
  RECT m = info.rcMonitor;
  MoveWindow(window, m.left, m.top, m.right - m.left, m.bottom - m.top, TRUE);
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

  // The app surface draws its own titlebar, exactly as the process-per-window
  // file explorer does -- the handlers are shared (flwin32_caption_handle).
  //
  // NOT gated on the slot: WM_NCCALCSIZE arrives during CreateWindowExW and
  // during the SWP_FRAMECHANGED that claims the caption, both of which happen
  // BEFORE the slot is filled in. Gating on the slot meant the takeover was
  // skipped exactly when it mattered and the window kept a system caption.
  // The handler is keyed on a property of the window, so it is safe to ask
  // for any message on any of our windows.
  {
    int64_t answer = 0;
    if (flwin32_caption_handle(hwnd, message, (uint64_t)wparam,
                               (int64_t)lparam, &answer)) {
      return (LRESULT)answer;
    }
  }
  if (slot != NULL && slot->kind == FLWIN32_SURFACE_APP) {
    if (message == WM_CLOSE) {
      // HIDE, do not destroy: the whole point of living in the shell process
      // is that reopening is a ShowWindow on a tree that is already built and
      // already composited. Destroying the view would give that back and make
      // the next open pay for a tree mount and a fresh directory read.
      ShowWindow(hwnd, SW_HIDE);
      app_notify_closed(slot);
      return 0;
    }
  }
  if (slot != NULL && slot->kind == FLWIN32_SURFACE_DESKTOP) {
    // The wallpaper plane ignores polite closes outright — DefWindowProc
    // would destroy it and leave the session with no desktop under the
    // chrome. Same refusal as the host's shell windows (kDeliberateClose
    // in flwin32_host.c); nothing legitimate closes this window.
    if (message == WM_CLOSE) return 0;
    if (message == WM_SYSCOMMAND && (wparam & 0xFFF0) == SC_CLOSE) return 0;
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
    case WM_TIMER:
      if (slot != NULL && slot->kind == FLWIN32_SURFACE_DESKTOP) {
        switch (wparam) {
          case kHealTimerShrink1:
          case kHealTimerShrink2:
            KillTimer(hwnd, (UINT_PTR)wparam);
            nudge_width(hwnd, -1);
            SetTimer(hwnd, (UINT_PTR)wparam + 1, 250, NULL);
            return 0;
          case kHealTimerRestore1:
          case kHealTimerRestore2:
            KillTimer(hwnd, (UINT_PTR)wparam);
            nudge_width(hwnd, 1);
            return 0;
          default:
            break;
        }
      }
      break;
    case WM_DISPLAYCHANGE:
      // A monitor changed resolution, or was added/removed. The desktop is
      // pinned to the whole monitor and nothing else corrects its size, so
      // re-derive it here — see desktop_fill_monitor.
      if (slot != NULL && slot->kind == FLWIN32_SURFACE_DESKTOP) {
        desktop_fill_monitor(hwnd);
        return 0;
      }
      break;
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
                             double bottom_margin_pt,
                             const char* title_utf8) {
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
  if (kind == FLWIN32_SURFACE_APP) {
    // An ordinary application window: resizable, in the taskbar, and its own
    // thing in Alt-Tab. WS_EX_APPWINDOW because the surface class is
    // TOOLWINDOW by default for the chrome surfaces, and a tool window is
    // exactly what a file explorer is not.
    LONG w = (LONG)(width_pt * scale + 0.5);
    LONG h = (LONG)(height_pt * scale + 0.5);
    r.left = info.rcWork.left + ((info.rcWork.right - info.rcWork.left) - w) / 2;
    r.top = info.rcWork.top + ((info.rcWork.bottom - info.rcWork.top) - h) / 2;
    r.right = r.left + w;
    r.bottom = r.top + h;
    style = WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN;
    exstyle = WS_EX_APPWINDOW;
  } else if (kind == FLWIN32_SURFACE_DESKTOP) {
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

  // The TITLE, which for an app surface is load-bearing rather than cosmetic.
  // The shell's own window list drops any window whose title is empty
  // (is_manageable, flwin32_wm.c), so an untitled app surface is invisible to
  // the dock that is supposed to hold its tile -- no icon, no running
  // indicator, and no way to raise it. The file explorer lived that way and it
  // only ever showed while Windows was leaving minimized windows as stubs on
  // the desktop. The chrome kinds stay untitled on purpose: the desktop and
  // the launcher are not apps and must NOT appear in that list.
  wchar_t title[256];
  title[0] = L'\0';
  if (title_utf8 != NULL && title_utf8[0] != '\0') {
    MultiByteToWideChar(CP_UTF8, 0, title_utf8, -1, title, 256);
    title[255] = L'\0';
  }

  HWND window = CreateWindowExW(
      exstyle, kSurfaceClass, title,
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
  if (kind == FLWIN32_SURFACE_APP) {
    // BEFORE the view controller exists. Claiming the caption afterwards is a
    // client-area resize, and the embedder answers a resize by blocking the
    // platform thread until the raster thread returns a frame at the new size
    // -- ~90 ms on a 29 Hz panel, and here it would block the SHELL's thread.
    flwin32_caption_mark(window, 1);
    GetClientRect(window, &r);
    MapWindowPoints(window, NULL, (POINT*)&r, 2);
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


/* ---- keeping the desktop UNDER everything ---------------------------------
 *
 * The WM_WINDOWPOSCHANGING clamp below only fires when something asks to move
 * OUR window. Nothing asks when a FOREIGN window is inserted BENEATH us --
 * which Windows does when the app being launched cannot take the foreground,
 * and most reliably when the desktop itself is the foreground window (which
 * it becomes the moment the last app window closes). The result is a real
 * app window that `IsWindowVisible` calls visible, at the right rect, not
 * cloaked, and completely invisible to the user because our full-screen
 * desktop is painted over it. With explorer absent there is nothing else to
 * repaint the screen and reveal it, so it stays lost until something else
 * happens to change the z-order.
 *
 * A shell cannot leave that to chance. This watches for any window being
 * shown or taking the foreground anywhere else on the machine and puts the
 * desktop back on the floor. EVENT_OBJECT_SHOW is the one that matters:
 * a window can appear without ever becoming foreground, which is exactly the
 * case the clamp misses.
 */
static HWINEVENTHOOK g_bottom_hook;
static HWND g_desktop_window;

static void sink_desktop(void) {
  if (g_desktop_window == NULL || !IsWindow(g_desktop_window)) return;
  /* Already on the floor: nothing below us in the z-order. Cheap enough to
   * check on every show, and it keeps this off the frame path entirely. */
  if (GetWindow(g_desktop_window, GW_HWNDNEXT) == NULL) return;
  SetWindowPos(g_desktop_window, HWND_BOTTOM, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOSENDCHANGING);
}

static void CALLBACK on_foreign_window(HWINEVENTHOOK hook, DWORD event,
                                       HWND hwnd, LONG object_id,
                                       LONG child_id, DWORD thread_id,
                                       DWORD time) {
  (void)hook; (void)event; (void)thread_id; (void)time;
  if (hwnd == NULL || object_id != OBJID_WINDOW || child_id != CHILDID_SELF) {
    return;
  }
  /* Top-level only: a child window being shown says nothing about z-order. */
  if (GetAncestor(hwnd, GA_ROOT) != hwnd) return;
  sink_desktop();
  /* EXPLORER STARTING. Its Progman being shown is the one signal every
   * explorer gives -- a service explorer restarted hidden after a crash
   * shows no taskbar and broadcasts nothing we hear -- and an explorer
   * starting beside the running shell takes the desktop surface's frame off
   * the screen: measured on a Hyper-V Windows 10 VM (2026-09-04), black
   * within three seconds of a new explorer and black until the surface is
   * RESIZED (see flwin32_surface_nudge_width). So a new Progman schedules
   * the resize, twice: explorer's desktop initialisation runs on for a few
   * seconds after Progman exists, and a heal that lands before the damage
   * heals nothing. */
  if (event == EVENT_OBJECT_SHOW && g_desktop_window != NULL) {
    wchar_t cls[32];
    if (GetClassNameW(hwnd, cls, 32) > 0 && wcscmp(cls, L"Progman") == 0) {
      static const char note[] =
          "[surface] explorer's Progman appeared; re-presenting the desktop "
          "in 2s and 6s\n";
      DWORD wrote = 0;
      WriteFile(GetStdHandle(STD_ERROR_HANDLE), note, sizeof(note) - 1,
                &wrote, NULL);
      SetTimer(g_desktop_window, kHealTimerShrink1, 2000, NULL);
      SetTimer(g_desktop_window, kHealTimerShrink2, 6000, NULL);
    }
  }
}

void flwin32_desktop_pin_to_bottom(uint64_t desktop_hwnd) {
  HWND desktop = (HWND)(uintptr_t)desktop_hwnd;
  if (desktop == NULL) return;
  g_desktop_window = desktop;
  if (g_bottom_hook != NULL) return;
  /* SKIPOWNPROCESS: our own surfaces and popups come and go constantly and
   * none of them can bury the desktop. */
  g_bottom_hook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_OBJECT_SHOW,
                                  NULL, on_foreign_window, 0, 0,
                                  WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
}

static void watch_for_windows_above(HWND desktop) {
  flwin32_desktop_pin_to_bottom((uint64_t)(uintptr_t)desktop);
}

/* Resize a surface window's width by `delta` pixels, in place. A one-pixel
 * shrink and a one-pixel restore, a moment apart, is how the desktop surface
 * gets its first frame onto the screen on a display stack that never shows
 * buffers made while the window was hidden. Measured on a Hyper-V VM
 * (2026-09-04) with the desktop up and BLACK: RedrawWindow changed nothing,
 * forcing another composite changed nothing, shrinking the window by one
 * pixel brought the wallpaper up, hiding and re-showing it made it black
 * again. A resize is what makes the engine rebuild the view's swapchain
 * buffers -- a plain present reuses the ones it made while hidden. The two
 * steps are separate calls a moment apart on purpose: back to back they
 * coalesce into "same size", which rebuilds nothing. */
void flwin32_surface_nudge_width(FlWin32Host* host, int64_t view_id,
                                 int32_t delta) {
  SurfaceSlot* slot = surface_for_view(view_id);
  if (slot == NULL || slot->host != host) return;
  nudge_width(slot->window, (int)delta);
}

void flwin32_surface_show(FlWin32Host* host, int64_t view_id) {
  SurfaceSlot* slot = surface_for_view(view_id);
  if (slot == NULL || slot->host != host) return;

  if (slot->kind == FLWIN32_SURFACE_APP) {
    // THREE STATES, ONE ENTRY POINT: minimized, hidden, or on screen behind
    // something. The file explorer's tile, Win+E and the dock menu all land
    // here, and each state needs a different call.
    //
    // What was here before was `if (IsWindowVisible(w)) return;` followed by
    // SW_SHOW, and both halves were wrong for a minimized window. A minimized
    // window KEEPS WS_VISIBLE, so the guard returned without touching it, and
    // SW_SHOW would not have helped anyway -- it shows a window in its
    // CURRENT state, so an iconic window stays iconic. That is the same trap
    // flwin32_wm_activate documents for other people's windows.
    //
    // It survived only because Windows was leaving minimized windows as
    // title-bar stubs on the desktop, which was itself our bug (nothing had
    // claimed SetTaskmanWindow -- see flwin32_explorer.c). Clicking the stub
    // was the only thing that ever brought the file explorer back; fixing the
    // stubs took that away and left it unreachable.
    if (IsIconic(slot->window)) {
      ShowWindow(slot->window, SW_RESTORE);
    } else if (!IsWindowVisible(slot->window)) {
      ShowWindow(slot->window, SW_SHOW);
    } else {
      BringWindowToTop(slot->window);
    }
    SetForegroundWindow(slot->window);
    HWND child = GetWindow(slot->window, GW_CHILD);
    if (child != NULL) SetFocus(child);
    // AND FORCE A REDRAW. The view composited while hidden -- that is the
    // point of building it at startup -- but nothing has asked the newly
    // visible window for a frame, and with explorer absent nothing else will:
    // the window stays the blank rectangle Windows painted. The overlay gets
    // this for free because overlay_notify makes its tree rebuild; an app
    // surface has no such signal, so ask the engine directly. Same call, same
    // reason, as the desktop's in flwin32_host.c.
    //
    // NOT SUFFICIENT ON ITS OWN, measured: this schedules a frame, and the
    // frame composites a secondary view only when THAT view's pipeline has
    // work -- which a window that merely became visible does not. The
    // caller (Win32Surfaces.show) sets the framework's force-composite flag
    // for exactly this reason; without it the window shows the frame it
    // composited while hidden, which for the file explorer is the empty page
    // it had before its first listing arrived. It is also why the dock must
    // raise this window through here rather than through the generic window
    // manager: a raise that skips the flag paints it blank.
    FlutterDesktopViewControllerForceRedraw(slot->controller);
    return;
  }

  // The chrome kinds are never minimized (no caption, no minimize box), but
  // restoring costs nothing and beats a silent no-op if one ever is.
  if (IsIconic(slot->window)) {
    ShowWindow(slot->window, SW_RESTORE);
    return;
  }
  if (IsWindowVisible(slot->window)) return;
  if (slot->kind == FLWIN32_SURFACE_DESKTOP) {
    // Bottom of the z-order, no activation — and the window only exists on
    // screen once its view has composited, so there is no empty first
    // paint to rescue. (What there IS to rescue, on some display stacks, is
    // that composited frame itself: see flwin32_surface_nudge_width, which
    // the Swift side calls right after this.)
    ShowWindow(slot->window, SW_SHOWNOACTIVATE);
    SetWindowPos(slot->window, HWND_BOTTOM, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    // ...and keep it there, against windows that arrive underneath.
    watch_for_windows_above(slot->window);
  } else {
    overlay_show(slot);
  }
}

/* WHERE A SURFACE'S CLIENT AREA SITS, in the HOST window's client logical
 * points.
 *
 * Popup geometry crosses the boundary in the host window's client space
 * (flwin32_popup.c says so, and converts with the host's own DPI). A tree
 * hosted in a SURFACE does not live in that window: in the shell the host
 * window is the DOCK, full screen, while the file explorer's view is a
 * window of its own wherever the user last dragged it. Everything such a
 * tree computes -- a menu at the pointer, a flyout under a row -- is in its
 * OWN client points, so it has to add this offset on the way out.
 *
 * Without it the menu opens at the pointer's coordinates measured from the
 * wrong window's corner, which looks like "the menu appears in the wrong
 * place" and reads like a layout bug: measured, a pointer at screen
 * (1700,1000) with the explorer's client origin at (893,344) put the menu at
 * (807,656).
 *
 * Zero for a view that is not a surface, so an unhosted caller can add it
 * unconditionally. */
void flwin32_surface_client_offset(FlWin32Host* host, int64_t view_id,
                                   double* x_pt, double* y_pt) {
  if (x_pt != NULL) *x_pt = 0;
  if (y_pt != NULL) *y_pt = 0;
  SurfaceSlot* slot = surface_for_view(view_id);
  if (slot == NULL || slot->host != host || slot->window == NULL) return;
  HWND hostw = (HWND)flwin32_host_window(host);
  if (hostw == NULL) return;
  /* The HOST's dpi, because that is the scale flwin32_popup.c multiplies
   * these points back up with -- the two conversions have to agree, and a
   * surface on another monitor would otherwise disagree by its scale. */
  UINT dpi = GetDpiForWindow(hostw);
  double scale = dpi > 0 ? (double)dpi / 96.0 : 1.0;
  POINT host_origin = {0, 0};
  POINT surface_origin = {0, 0};
  ClientToScreen(hostw, &host_origin);
  ClientToScreen(slot->window, &surface_origin);
  if (x_pt != NULL) *x_pt = (surface_origin.x - host_origin.x) / scale;
  if (y_pt != NULL) *y_pt = (surface_origin.y - host_origin.y) / scale;
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
