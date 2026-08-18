// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/*
 * flwin32_wm.c -- window management for the Windows shell port.
 *
 * On Linux, Starling IS the compositor: it owns every client's buffer and
 * decides where the pixels land. On Windows DWM owns that and cannot be
 * replaced, so the shell's other half -- deciding which windows exist, where
 * they sit, and which one has the keyboard -- is all we get, and all of it is
 * plain user32. This file is that half. `WindowManager.swift` in the desktop
 * shell (1,092 lines, zero platform code) is what eventually sits on top.
 *
 * Deliberately plain ASCII, comments included, for the same reason as
 * flwin32_clipboard.c: this tree has lost time to MSVC and PowerShell
 * disagreeing about non-ASCII bytes.
 *
 * Three things here are not obvious, and each is a bug someone else shipped:
 *
 *  1. "Every top-level window" is not the window list. A logged-in Windows
 *     session carries dozens of invisible top-level windows -- suspended UWP
 *     frames, windows on other virtual desktops, tool palettes, the shell's
 *     own furniture. The DWM CLOAKED attribute is the one that matters and
 *     the one most naive taskbars miss, because those windows answer
 *     IsWindowVisible with TRUE.
 *
 *  2. GetWindowRect is not the visible frame. Since Windows 10 a window's
 *     rect includes an invisible resize border, ~7px per side at 100%. Tile
 *     with those numbers and every window overlaps its neighbour by 14px
 *     while looking like it has a gap. DWMWA_EXTENDED_FRAME_BOUNDS is the
 *     true one; the difference between the two is the correction to apply
 *     when moving.
 *
 *  3. SetForegroundWindow refuses unless the caller already owns the
 *     foreground. A bar the user just clicked does own it -- but a hotkey or
 *     a hook does not, hence the AttachThreadInput dance.
 */

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <windows.h>
#include <dwmapi.h>
#include <stdlib.h>
#include <string.h>

#include "include/FlutterWin32Bridge.h"

/* DwmGetWindowAttribute. The pragma is what actually links it under the Swift
 * driver's clang; Package.swift names it too, so a toolchain that ignores
 * #pragma comment still resolves. */
#pragma comment(lib, "dwmapi.lib")

/* Windows 8 added DWMWA_CLOAKED; the vendored SDK headers have it, but a
 * mismatched one would leave the most important filter silently out. */
#ifndef DWMWA_CLOAKED
#define DWMWA_CLOAKED 14
#endif

/* ---------------------------------------------------------------- strings */

/* UTF-16 -> freshly allocated UTF-8. Never returns NULL for a valid input;
 * an empty string comes back as "". */
static char* wide_to_utf8(const wchar_t* w) {
    if (w == NULL) {
        char* empty = (char*)malloc(1);
        if (empty) empty[0] = '\0';
        return empty;
    }
    int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, NULL, 0, NULL, NULL);
    if (n <= 0) {
        char* empty = (char*)malloc(1);
        if (empty) empty[0] = '\0';
        return empty;
    }
    char* out = (char*)malloc((size_t)n);
    if (out == NULL) return NULL;
    WideCharToMultiByte(CP_UTF8, 0, w, -1, out, n, NULL, NULL);
    return out;
}

/* The copy-out convention shared with flwin32_clipboard_get_text: bytes
 * written including the terminator, or -1 when the caller's buffer is short. */
static int32_t copy_out(const char* s, char* out, int32_t out_size) {
    if (s == NULL) s = "";
    size_t need = strlen(s) + 1;
    if (out == NULL || out_size <= 0 || (size_t)out_size < need) return -1;
    memcpy(out, s, need);
    return (int32_t)need;
}

/* --------------------------------------------------------------- monitors */

/* Index order has to match flwin32_monitor_rect's, which is
 * EnumDisplayMonitors order, so both walk the monitors the same way. */

#define kMaxMonitors 16

typedef struct {
    HMONITOR handles[kMaxMonitors];
    int count;
} MonitorTable;

static BOOL CALLBACK monitor_collect_cb(HMONITOR monitor,
                                        HDC dc,
                                        LPRECT clip,
                                        LPARAM data) {
    (void)dc;
    (void)clip;
    MonitorTable* table = (MonitorTable*)data;
    if (table->count < kMaxMonitors) {
        table->handles[table->count++] = monitor;
    }
    return TRUE;
}

static void monitor_table_fill(MonitorTable* table) {
    table->count = 0;
    EnumDisplayMonitors(NULL, NULL, monitor_collect_cb, (LPARAM)table);
}

static int32_t monitor_index_of(const MonitorTable* table, HMONITOR monitor) {
    for (int i = 0; i < table->count; i++) {
        if (table->handles[i] == monitor) return i;
    }
    return -1;
}

int32_t flwin32_wm_work_area(int32_t monitor,
                             int32_t* x,
                             int32_t* y,
                             int32_t* width,
                             int32_t* height) {
    MonitorTable table;
    monitor_table_fill(&table);

    HMONITOR target = NULL;
    if (monitor >= 0 && monitor < table.count) {
        target = table.handles[monitor];
    } else {
        /* The primary is the monitor containing the origin, by definition:
         * Windows lays the virtual desktop out around it. */
        POINT origin = {0, 0};
        target = MonitorFromPoint(origin, MONITOR_DEFAULTTOPRIMARY);
    }
    if (target == NULL) return 0;

    MONITORINFO mi = {sizeof(MONITORINFO)};
    if (!GetMonitorInfoW(target, &mi)) return 0;
    if (x) *x = mi.rcWork.left;
    if (y) *y = mi.rcWork.top;
    if (width) *width = mi.rcWork.right - mi.rcWork.left;
    if (height) *height = mi.rcWork.bottom - mi.rcWork.top;
    return 1;
}

/* -------------------------------------------------------------- filtering */

/* The visible frame, falling back to GetWindowRect when DWM has no answer
 * (it does not for a minimized window, and would not on a machine with
 * composition off, which no longer exists but costs nothing to survive). */
static BOOL visible_frame(HWND hwnd, RECT* out) {
    RECT dwm;
    if (SUCCEEDED(DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS,
                                        &dwm, sizeof(dwm))) &&
        dwm.right > dwm.left && dwm.bottom > dwm.top) {
        *out = dwm;
        return TRUE;
    }
    return GetWindowRect(hwnd, out);
}

static BOOL is_cloaked(HWND hwnd) {
    DWORD cloaked = 0;
    if (FAILED(DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, &cloaked,
                                     sizeof(cloaked)))) {
        return FALSE;
    }
    return cloaked != 0;
}

/* The shell's own furniture, which is visible, owner-less and titled, and so
 * passes every structural test above. Progman and WorkerW are the desktop
 * itself; the tray classes are explorer's taskbar. */
static BOOL is_shell_furniture(const wchar_t* cls) {
    return wcscmp(cls, L"Progman") == 0 ||
           wcscmp(cls, L"WorkerW") == 0 ||
           wcscmp(cls, L"Shell_TrayWnd") == 0 ||
           wcscmp(cls, L"Shell_SecondaryTrayWnd") == 0 ||
           wcscmp(cls, L"Windows.UI.Core.CoreWindow") == 0 ||
           wcscmp(cls, L"ForegroundStaging") == 0 ||
           wcscmp(cls, L"MultitaskingViewFrame") == 0 ||
           wcscmp(cls, L"XamlExplorerHostIslandWindow") == 0;
}

/* Would a taskbar show this window? */
static BOOL is_manageable(HWND hwnd) {
    if (hwnd == NULL || !IsWindow(hwnd)) return FALSE;
    if (!IsWindowVisible(hwnd)) return FALSE;

    LONG_PTR ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    /* WS_EX_APPWINDOW is the documented "show me anyway" override, and it
     * wins over both of the tests it precedes. */
    if (!(ex & WS_EX_APPWINDOW)) {
        /* An owned window is a dialog or a palette OF something; the owner is
         * the entry a taskbar shows, not this. */
        if (GetWindow(hwnd, GW_OWNER) != NULL) return FALSE;
        if (ex & WS_EX_TOOLWINDOW) return FALSE;
    }

    /* Suspended UWP apps and windows on another virtual desktop. This is the
     * filter that turns ~40 candidates into the ~6 the user can see. */
    if (is_cloaked(hwnd)) return FALSE;

    if (GetWindowTextLengthW(hwnd) == 0) return FALSE;

    wchar_t cls[256];
    if (GetClassNameW(hwnd, cls, 256) == 0) return FALSE;
    if (is_shell_furniture(cls)) return FALSE;

    RECT r;
    if (!visible_frame(hwnd, &r)) return FALSE;
    if (r.right - r.left <= 0 || r.bottom - r.top <= 0) return FALSE;

    return TRUE;
}

/* ------------------------------------------------------------- the snapshot */

typedef struct {
    FlWin32WindowInfo info;
    char* title;
    char* cls;
    char* exe;
} WindowEntry;

struct FlWin32WindowList {
    WindowEntry* items;
    int count;
    int capacity;
    MonitorTable monitors;
    HWND foreground;
};

static char* process_image_path(DWORD pid) {
    /* QUERY_LIMITED_INFORMATION rather than QUERY_INFORMATION: the limited
     * right is granted for processes at a higher integrity level, so an
     * elevated app still yields its path to an unelevated shell. */
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (process == NULL) return wide_to_utf8(NULL);
    wchar_t path[MAX_PATH];
    DWORD len = MAX_PATH;
    char* out;
    if (QueryFullProcessImageNameW(process, 0, path, &len)) {
        out = wide_to_utf8(path);
    } else {
        out = wide_to_utf8(NULL);
    }
    CloseHandle(process);
    return out;
}

static BOOL CALLBACK enum_windows_cb(HWND hwnd, LPARAM data) {
    FlWin32WindowList* list = (FlWin32WindowList*)data;
    if (!is_manageable(hwnd)) return TRUE;

    if (list->count == list->capacity) {
        int grown = list->capacity == 0 ? 16 : list->capacity * 2;
        WindowEntry* items =
            (WindowEntry*)realloc(list->items, (size_t)grown * sizeof(WindowEntry));
        if (items == NULL) return FALSE;  /* out of memory: stop, keep what we have */
        list->items = items;
        list->capacity = grown;
    }

    WindowEntry* entry = &list->items[list->count];
    memset(entry, 0, sizeof(*entry));

    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);

    RECT frame;
    visible_frame(hwnd, &frame);

    WINDOWPLACEMENT placement = {sizeof(WINDOWPLACEMENT)};
    GetWindowPlacement(hwnd, &placement);

    entry->info.handle = (uint64_t)(uintptr_t)hwnd;
    entry->info.pid = (uint32_t)pid;
    entry->info.x = frame.left;
    entry->info.y = frame.top;
    entry->info.width = frame.right - frame.left;
    entry->info.height = frame.bottom - frame.top;
    entry->info.monitor = monitor_index_of(
        &list->monitors, MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST));
    entry->info.minimized = IsIconic(hwnd) ? 1 : 0;
    entry->info.maximized = IsZoomed(hwnd) ? 1 : 0;
    entry->info.foreground = (hwnd == list->foreground) ? 1 : 0;

    wchar_t title[512];
    int n = GetWindowTextW(hwnd, title, 512);
    title[n < 0 ? 0 : (n < 512 ? n : 511)] = L'\0';
    entry->title = wide_to_utf8(title);

    wchar_t cls[256];
    if (GetClassNameW(hwnd, cls, 256) == 0) cls[0] = L'\0';
    entry->cls = wide_to_utf8(cls);

    entry->exe = process_image_path(pid);

    list->count++;
    return TRUE;
}

FlWin32WindowList* flwin32_wm_snapshot(void) {
    FlWin32WindowList* list =
        (FlWin32WindowList*)calloc(1, sizeof(FlWin32WindowList));
    if (list == NULL) return NULL;
    monitor_table_fill(&list->monitors);
    /* Read once, before enumerating: the foreground can change mid-walk, and
     * a list with two windows flagged foreground reads as a bug in the UI. */
    list->foreground = GetForegroundWindow();
    /* EnumWindows walks in z-order, topmost first, which is the order a
     * taskbar wants for "most recently used" and the order Alt+Tab shows. */
    EnumWindows(enum_windows_cb, (LPARAM)list);
    return list;
}

int32_t flwin32_wm_count(FlWin32WindowList* list) {
    return list == NULL ? 0 : (int32_t)list->count;
}

int32_t flwin32_wm_info(FlWin32WindowList* list,
                        int32_t index,
                        FlWin32WindowInfo* out) {
    if (list == NULL || out == NULL || index < 0 || index >= list->count) {
        return 0;
    }
    *out = list->items[index].info;
    return 1;
}

int32_t flwin32_wm_title(FlWin32WindowList* list,
                         int32_t index,
                         char* out,
                         int32_t out_size) {
    if (list == NULL || index < 0 || index >= list->count) return -1;
    return copy_out(list->items[index].title, out, out_size);
}

int32_t flwin32_wm_class(FlWin32WindowList* list,
                         int32_t index,
                         char* out,
                         int32_t out_size) {
    if (list == NULL || index < 0 || index >= list->count) return -1;
    return copy_out(list->items[index].cls, out, out_size);
}

int32_t flwin32_wm_exe(FlWin32WindowList* list,
                       int32_t index,
                       char* out,
                       int32_t out_size) {
    if (list == NULL || index < 0 || index >= list->count) return -1;
    return copy_out(list->items[index].exe, out, out_size);
}

void flwin32_wm_release(FlWin32WindowList* list) {
    if (list == NULL) return;
    for (int i = 0; i < list->count; i++) {
        free(list->items[i].title);
        free(list->items[i].cls);
        free(list->items[i].exe);
    }
    free(list->items);
    free(list);
}

/* ---------------------------------------------------------------- actions */

int32_t flwin32_wm_activate(uint64_t handle) {
    HWND hwnd = (HWND)(uintptr_t)handle;
    if (hwnd == NULL || !IsWindow(hwnd)) return 0;

    /* Restore first: a minimized window can be made foreground and stay
     * minimized, which looks exactly like the click did nothing. */
    if (IsIconic(hwnd)) ShowWindow(hwnd, SW_RESTORE);

    HWND foreground = GetForegroundWindow();
    if (foreground == hwnd) {
        SetFocus(hwnd);
        return 1;
    }

    /* Windows only lets the process that already owns the foreground hand it
     * away. Sharing an input queue with the current owner (AttachThreadInput)
     * makes us count as that process for the length of the call. When the bar
     * itself was just clicked this is redundant -- and harmless. */
    DWORD current = GetWindowThreadProcessId(foreground, NULL);
    DWORD mine = GetCurrentThreadId();
    BOOL attached = FALSE;
    if (current != 0 && current != mine) {
        attached = AttachThreadInput(mine, current, TRUE);
    }

    BringWindowToTop(hwnd);
    BOOL ok = SetForegroundWindow(hwnd);
    SetFocus(hwnd);

    if (attached) AttachThreadInput(mine, current, FALSE);
    return ok ? 1 : 0;
}

int32_t flwin32_wm_move(uint64_t handle,
                        int32_t x,
                        int32_t y,
                        int32_t width,
                        int32_t height) {
    HWND hwnd = (HWND)(uintptr_t)handle;
    if (hwnd == NULL || !IsWindow(hwnd)) return 0;

    /* A maximized or minimized window ignores SetWindowPos geometry -- it
     * snaps back the moment anything repaints. Restore, then place. */
    if (IsZoomed(hwnd) || IsIconic(hwnd)) ShowWindow(hwnd, SW_RESTORE);

    /* The correction from trap 2 in the file header: ask for the rectangle
     * that puts the VISIBLE frame where the caller wants it. */
    RECT raw, shown;
    if (GetWindowRect(hwnd, &raw) &&
        SUCCEEDED(DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS,
                                        &shown, sizeof(shown))) &&
        shown.right > shown.left && shown.bottom > shown.top) {
        x -= (int32_t)(shown.left - raw.left);
        y -= (int32_t)(shown.top - raw.top);
        width += (int32_t)((raw.right - raw.left) - (shown.right - shown.left));
        height += (int32_t)((raw.bottom - raw.top) - (shown.bottom - shown.top));
    }

    return SetWindowPos(hwnd, NULL, x, y, width, height,
                        SWP_NOACTIVATE | SWP_NOZORDER | SWP_NOOWNERZORDER)
               ? 1
               : 0;
}

int32_t flwin32_wm_set_state(uint64_t handle, int32_t state) {
    HWND hwnd = (HWND)(uintptr_t)handle;
    if (hwnd == NULL || !IsWindow(hwnd)) return 0;
    int show;
    switch (state) {
        case 1:  show = SW_MINIMIZE; break;
        case 2:  show = SW_MAXIMIZE; break;
        default: show = SW_RESTORE;  break;
    }
    ShowWindow(hwnd, show);
    return 1;
}

int32_t flwin32_wm_close(uint64_t handle) {
    HWND hwnd = (HWND)(uintptr_t)handle;
    if (hwnd == NULL || !IsWindow(hwnd)) return 0;
    /* Post, never Send: SendMessage blocks our UI thread on the target app's
     * "save changes?" dialog, and the shell would appear to hang. */
    return PostMessageW(hwnd, WM_CLOSE, 0, 0) ? 1 : 0;
}

uint64_t flwin32_wm_foreground(void) {
    return (uint64_t)(uintptr_t)GetForegroundWindow();
}

/* ----------------------------------------------------------------- events */

/* WinEvent hooks, installed OUT_OF_CONTEXT so nothing of ours is injected
 * into other processes: the events are queued to the installing thread and
 * arrive through its message loop, which is the host's. */

#define kMaxHooks 8
static HWINEVENTHOOK g_hooks[kMaxHooks];
static int g_hook_count = 0;
static FlWin32WmEventCallback g_callback = NULL;
static void* g_callback_user = NULL;

static void CALLBACK win_event_cb(HWINEVENTHOOK hook,
                                  DWORD event,
                                  HWND hwnd,
                                  LONG id_object,
                                  LONG id_child,
                                  DWORD thread,
                                  DWORD time) {
    (void)hook;
    (void)thread;
    (void)time;
    if (g_callback == NULL) return;
    /* Only whole windows. Without this every caret move, menu item and list
     * row in every running app arrives here. */
    if (id_object != OBJID_WINDOW || id_child != CHILDID_SELF) return;
    if (hwnd == NULL) return;

    int32_t kind = 0;
    switch (event) {
        case EVENT_OBJECT_CREATE:
        case EVENT_OBJECT_SHOW:
        case EVENT_OBJECT_UNCLOAKED:
            /* Checked here rather than in Swift: a create for a window that
             * is not manageable is the overwhelming majority of this traffic,
             * and dropping it in C keeps the UI thread out of it. */
            if (!is_manageable(hwnd)) return;
            kind = FLWIN32_WM_EVENT_ADDED;
            break;
        case EVENT_OBJECT_DESTROY:
        case EVENT_OBJECT_HIDE:
        case EVENT_OBJECT_CLOAKED:
            /* No manageability test: the window is already gone, so every
             * test would fail and we would report nothing. The listener
             * reconciles against its own list. */
            kind = FLWIN32_WM_EVENT_REMOVED;
            break;
        case EVENT_SYSTEM_FOREGROUND:
            kind = FLWIN32_WM_EVENT_FOREGROUND;
            break;
        case EVENT_OBJECT_NAMECHANGE:
            if (!is_manageable(hwnd)) return;
            kind = FLWIN32_WM_EVENT_TITLE;
            break;
        case EVENT_SYSTEM_MOVESIZEEND:
            kind = FLWIN32_WM_EVENT_MOVED;
            break;
        case EVENT_SYSTEM_MINIMIZESTART:
        case EVENT_SYSTEM_MINIMIZEEND:
            kind = FLWIN32_WM_EVENT_MINIMIZED;
            break;
        default:
            return;
    }
    g_callback(kind, (uint64_t)(uintptr_t)hwnd, g_callback_user);
}

static void install_hook(DWORD min_event, DWORD max_event) {
    if (g_hook_count >= kMaxHooks) return;
    HWINEVENTHOOK hook = SetWinEventHook(
        min_event, max_event, NULL, win_event_cb, 0, 0,
        WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
    if (hook != NULL) g_hooks[g_hook_count++] = hook;
}

int32_t flwin32_wm_watch(FlWin32WmEventCallback callback, void* user) {
    if (callback == NULL) return 0;
    flwin32_wm_unwatch();
    g_callback = callback;
    g_callback_user = user;

    /* Narrow ranges rather than EVENT_MIN..EVENT_MAX: the full range carries
     * every accessibility event in every process on the machine, which is a
     * measurable share of a core on a busy desktop. */
    install_hook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND);
    install_hook(EVENT_SYSTEM_MOVESIZEEND, EVENT_SYSTEM_MOVESIZEEND);
    install_hook(EVENT_SYSTEM_MINIMIZESTART, EVENT_SYSTEM_MINIMIZEEND);
    install_hook(EVENT_OBJECT_CREATE, EVENT_OBJECT_HIDE);
    install_hook(EVENT_OBJECT_NAMECHANGE, EVENT_OBJECT_NAMECHANGE);
    install_hook(EVENT_OBJECT_CLOAKED, EVENT_OBJECT_UNCLOAKED);

    if (g_hook_count == 0) {
        g_callback = NULL;
        g_callback_user = NULL;
        return 0;
    }
    return 1;
}

void flwin32_wm_unwatch(void) {
    for (int i = 0; i < g_hook_count; i++) {
        UnhookWinEvent(g_hooks[i]);
    }
    g_hook_count = 0;
    g_callback = NULL;
    g_callback_user = NULL;
}
