// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/*
 * flwin32_explorer.c -- getting Explorer's own shell chrome out of the way.
 *
 * The Windows shell is explorer.exe, and it is FOUR things at once: the
 * taskbar, the Start menu, the notification tray, and the desktop (wallpaper
 * plus icons plus drag-and-drop plus every file dialog's view). The usual
 * framing -- "replace the shell" -- means the registry's Winlogon\Shell key,
 * which replaces all four and leaves the user with no desktop at all if we
 * crash. That is the last phase of this port, not the first, and it needs an
 * EV-signed binary to get past SmartScreen.
 *
 * This file is the useful 90% of it with none of that risk. Explorer keeps
 * running -- it keeps owning the desktop, the tray plumbing, and shell
 * dialogs -- but its taskbar is HIDDEN, so Starling's bar and dock are the
 * only shell chrome on screen. That is what every serious third-party
 * Windows shell does (Cairo, RetroBar); komorebi and GlazeWM leave the
 * taskbar up only because they are window managers and never drew one.
 *
 * Hiding a taskbar is two operations, and doing only the obvious one is the
 * mistake:
 *
 *  1. ShowWindow(SW_HIDE) on Shell_TrayWnd -- and on every
 *     Shell_SecondaryTrayWnd, because Windows makes one per extra monitor.
 *     This is the visible half.
 *  2. ABM_SETSTATE with ABS_AUTOHIDE -- the reserved half. The taskbar is an
 *     APPBAR, so the work area is short by its height whether or not its
 *     window is visible; hiding it alone leaves a maximized window stopping
 *     at a strip of empty wallpaper, and leaves our own bottom dock pushed up
 *     by it (ABM_QUERYPOS moves any new appbar clear of the taskbar's claim).
 *     Autohide is the documented way to make a taskbar reserve nothing, and
 *     it applies to the taskbar even though our process does not own it.
 *
 * Reversibility is not optional here. A machine left with neither taskbar is
 * the Windows equivalent of a DRM connector forced off: the user cannot get
 * to their own desktop. So the state is saved on the way in, restored by
 * flwin32_explorer_taskbar_show, and restored again from atexit for the
 * ordinary exit path. `WinShellBar.exe --restore-taskbar` is the escape hatch
 * for the path atexit cannot cover, which is our process being killed.
 *
 * Deliberately plain ASCII, comments included -- same reason as
 * flwin32_wm.c.
 */

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <windows.h>
#include <shellapi.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#include "include/FlutterWin32Bridge.h"

/* The primary taskbar, and one secondary per additional monitor. Both classes
 * have been stable since Windows 7 and are still the classes Windows 11 uses
 * -- its taskbar is XAML islands hosted INSIDE Shell_TrayWnd, so hiding the
 * host hides the lot. */
static const wchar_t* const kTrayClasses[] = {
    L"Shell_TrayWnd",
    L"Shell_SecondaryTrayWnd",
};
static const int kTrayClassCount = 2;

/* The appbar state before we touched it, so restoring puts back what the user
 * had rather than what we assume they had -- someone who runs their taskbar
 * on autohide should still have it on autohide afterwards. -1 = unread. */
static int g_saved_state = -1;
static int g_hidden = 0;
static int g_atexit_installed = 0;

/* Explorer SHOWS ITS TASKBAR BACK, and a poll is not fast enough.
 *
 * Autohide is not a static reservation the way our own appbar is: it hands
 * explorer an active job, and explorer does it by calling ShowWindow on the
 * taskbar every time the pointer reaches that screen edge -- which, with a
 * dock sitting on the same edge, is constantly. A one-second re-assert
 * therefore does not mean "the taskbar stays hidden", it means "the taskbar
 * flashes for up to a second at a time". This hook is what makes the hide
 * hold: EVENT_OBJECT_SHOW, scoped to explorer's own process, re-hiding within
 * a frame of the show.
 *
 * The poll is still worth keeping. It covers what the hook cannot: explorer
 * restarting under a new pid, which leaves this hook watching a dead process.
 */
static HWINEVENTHOOK g_show_hook = NULL;
static DWORD g_hook_pid = 0;

/* Walk the top-level windows of one class. FindWindowEx with a NULL parent
 * searches top-level windows by class, which is far cheaper than EnumWindows
 * plus a GetClassName per window -- and this runs on the bar's one-second
 * tick, because explorer re-shows its taskbar on its own (a display change, a
 * settings round-trip, or explorer restarting after a crash). */
static int for_each_tray(int (*fn)(HWND)) {
  int touched = 0;
  int i;
  for (i = 0; i < kTrayClassCount; i++) {
    HWND w = NULL;
    while ((w = FindWindowExW(NULL, w, kTrayClasses[i], NULL)) != NULL) {
      touched += fn(w);
    }
  }
  return touched;
}

static int hide_one(HWND w) {
  if (!IsWindowVisible(w)) return 0;
  ShowWindow(w, SW_HIDE);
  return 1;
}

static int show_one(HWND w) {
  if (IsWindowVisible(w)) return 0;
  /* SHOWNA, not SHOW: putting the taskbar back should not also hand it the
   * keyboard and pull the user out of whatever they were typing in. */
  ShowWindow(w, SW_SHOWNA);
  return 1;
}

static int appbar_state(void) {
  APPBARDATA abd;
  ZeroMemory(&abd, sizeof(abd));
  abd.cbSize = sizeof(abd);
  return (int)SHAppBarMessage(ABM_GETSTATE, &abd);
}

static void set_appbar_state(int state) {
  APPBARDATA abd;
  if (appbar_state() == state) return;
  ZeroMemory(&abd, sizeof(abd));
  abd.cbSize = sizeof(abd);
  abd.lParam = (LPARAM)state;
  SHAppBarMessage(ABM_SETSTATE, &abd);
}

static int is_tray_class(HWND w) {
  wchar_t cls[64];
  int i;
  if (GetClassNameW(w, cls, (int)(sizeof(cls) / sizeof(cls[0]))) <= 0) return 0;
  for (i = 0; i < kTrayClassCount; i++) {
    if (wcscmp(cls, kTrayClasses[i]) == 0) return 1;
  }
  return 0;
}

static void CALLBACK on_explorer_show(HWINEVENTHOOK hook,
                                      DWORD event,
                                      HWND hwnd,
                                      LONG object_id,
                                      LONG child_id,
                                      DWORD thread_id,
                                      DWORD time) {
  (void)hook; (void)event; (void)thread_id; (void)time;
  if (!g_hidden || hwnd == NULL) return;
  /* Explorer shows a great many things; only the window itself, and only if
   * it is one of the two taskbar classes. GetClassName on every OBJID_WINDOW
   * show from one process is cheap, and the alternative -- caching the HWNDs
   * -- goes stale the moment a monitor is plugged in. */
  if (object_id != OBJID_WINDOW || child_id != CHILDID_SELF) return;
  if (is_tray_class(hwnd)) ShowWindow(hwnd, SW_HIDE);
}

/* Watch the process that owns the taskbar, all of its threads. Re-hooks when
 * the pid changes, which is explorer having restarted. */
static void hook_explorer(void) {
  HWND tray = FindWindowW(kTrayClasses[0], NULL);
  DWORD pid = 0;
  if (tray != NULL) GetWindowThreadProcessId(tray, &pid);
  if (pid == 0 || pid == g_hook_pid) return;
  if (g_show_hook != NULL) UnhookWinEvent(g_show_hook);
  g_show_hook = SetWinEventHook(EVENT_OBJECT_SHOW, EVENT_OBJECT_SHOW, NULL,
                                on_explorer_show, pid, 0, WINEVENT_OUTOFCONTEXT);
  g_hook_pid = g_show_hook != NULL ? pid : 0;
}

static void unhook_explorer(void) {
  if (g_show_hook != NULL) UnhookWinEvent(g_show_hook);
  g_show_hook = NULL;
  g_hook_pid = 0;
}

static void restore_at_exit(void) {
  if (g_hidden) flwin32_explorer_taskbar_show();
}

int32_t flwin32_explorer_taskbar_hide(void) {
  if (g_saved_state < 0) g_saved_state = appbar_state();
  if (!g_atexit_installed) {
    atexit(restore_at_exit);
    g_atexit_installed = 1;
  }
  /* ALWAYSONTOP is kept so the state we restore differs from the saved one in
   * exactly one bit. AUTOHIDE is the bit that frees the work area. */
  set_appbar_state(ABS_AUTOHIDE | ABS_ALWAYSONTOP);
  g_hidden = 1;
  /* Hook BEFORE hiding: between the two there is a window in which explorer
   * can show the taskbar and nothing would catch it. */
  hook_explorer();
  for_each_tray(hide_one);
  /* Success is "the taskbar is not visible", not "we hid something": on a
   * re-assert tick there is usually nothing left to hide, and that is the
   * good case, not a failure. */
  return flwin32_explorer_taskbar_visible() ? 0 : 1;
}

int32_t flwin32_explorer_taskbar_show(void) {
  g_hidden = 0;
  unhook_explorer();
  for_each_tray(show_one);
  /* ALWAYSONTOP is the Windows default and the right fallback when we were
   * never asked to hide in the first place (--restore-taskbar in a fresh
   * process, which is the whole point of that flag). */
  set_appbar_state(g_saved_state < 0 ? ABS_ALWAYSONTOP : g_saved_state);
  return 1;
}

int32_t flwin32_explorer_taskbar_visible(void) {
  int i;
  for (i = 0; i < kTrayClassCount; i++) {
    HWND w = NULL;
    while ((w = FindWindowExW(NULL, w, kTrayClasses[i], NULL)) != NULL) {
      if (IsWindowVisible(w)) return 1;
    }
  }
  return 0;
}

/* ------------------------------------------------------- Starling settings */

/* Opens the Settings surface, or raises the one already open.
 *
 * A second run of this same executable, which is how every Starling surface on
 * Windows works -- one widget root per process. GetModuleFileNameW rather than
 * a recorded path: the shell runs from a staging tree during development and
 * from a package afterwards, and hardcoding either is wrong somewhere.
 *
 * Raising an existing window rather than starting a second process is not
 * politeness: two Settings windows would each hold their own idea of the
 * display mode and the volume, and the second one to be touched would win. */
/* Start another run of this executable with `argument`, and NO console.
 *
 * CreateProcessW rather than ShellExecuteW, purely for CREATE_NO_WINDOW:
 * this is a console-subsystem binary, so Windows pops a console for every
 * child that does not say otherwise. The one it popped for a Files window
 * was a full-screen terminal sitting BEHIND that window -- engine log text
 * spilling out around its edges, and a second tile in our own dock for a
 * window the user never opened. The supervisor spawns the dock and the
 * desktop this way for the same reason; see flwin32_sessionslot_spawn_self.
 *
 * Passing SW_HIDE to ShellExecuteW looks like the smaller fix and is a trap.
 * It suppresses the console by setting STARTUPINFO.wShowWindow, and Windows
 * applies THAT to the process's first ShowWindow call whatever nCmdShow the
 * call itself passes -- so the surface's own window never appears either.
 * Measured on the box before this went in: the --files process came up with
 * zero visible windows, console gone and Files gone with it. */
static void spawn_surface(const wchar_t* argument) {
    wchar_t exe[MAX_PATH];
    if (GetModuleFileNameW(NULL, exe, MAX_PATH) == 0) return;

    /* CreateProcessW mutates the command line it is given, so it cannot be a
     * literal: build a writable "exe args". */
    size_t len = wcslen(exe) + wcslen(argument) + 4;
    wchar_t* cmd = (wchar_t*)malloc(len * sizeof(wchar_t));
    if (cmd == NULL) return;
    swprintf(cmd, len, L"\"%s\" %s", exe, argument);

    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    memset(&si, 0, sizeof(si));
    si.cb = sizeof(si);
    if (CreateProcessW(exe, cmd, NULL, NULL, FALSE, CREATE_NO_WINDOW,
                       NULL, NULL, &si, &pi)) {
        /* Nothing here waits on the child -- it is a sibling surface, not a
         * subprocess. Both handles go back now or the entry leaks until we
         * exit. */
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
    }
    free(cmd);
}

static void open_surface(const wchar_t* title, const wchar_t* argument) {
    HWND existing = FindWindowW(L"FlutterSwiftWin32Host", title);
    if (existing != NULL) {
        if (IsIconic(existing)) ShowWindow(existing, SW_RESTORE);
        SetForegroundWindow(existing);
        return;
    }

    spawn_surface(argument);
}

void flwin32_shell_open_settings(void) {
    open_surface(L"Starling Settings", L"--settings");
}

/* Start the notification centre PROCESS if it is not running -- parked, like
 * the launcher, so the first Win+N is a show rather than an engine boot. No
 * raise: a parked overlay has nothing to raise, its toggle channel does the
 * showing. */
void flwin32_shell_ensure_notification_center(void) {
    if (FindWindowW(L"FlutterSwiftWin32Host", L"Starling Notifications") != NULL) {
        return;
    }
    wchar_t exe[MAX_PATH];
    if (GetModuleFileNameW(NULL, exe, MAX_PATH) == 0) return;
    /* SW_HIDE: this exe is a console-subsystem binary, and the show command
     * applies to the console Windows would otherwise pop for it. The
     * surface's own window is created by the host and parked regardless. */
    ShellExecuteW(NULL, L"open", exe, L"--notifications", NULL, SW_HIDE);
}

void flwin32_shell_open_files(void) {
    open_surface(L"Starling Files", L"--files");
}

/* Files' own File > New window, which means a SECOND window on a directory
 * of its choosing -- so no FindWindowW raise here, unlike open_surface: the
 * one window that already exists is the one asking. Console-less for the
 * same reason as everything else spawned here.
 *
 * The directory is quoted because a path with a space in it (C:\Program
 * Files, and every "OneDrive - <company>") would otherwise reach the child
 * as two arguments and FilesBloc.requestedDirectory would read the first
 * half. */
void flwin32_shell_open_files_at(const char* dir_utf8) {
    if (dir_utf8 == NULL || dir_utf8[0] == '\0') {
        flwin32_shell_open_files();
        return;
    }

    int n = MultiByteToWideChar(CP_UTF8, 0, dir_utf8, -1, NULL, 0);
    if (n <= 0) return;
    wchar_t* dir = (wchar_t*)malloc((size_t)n * sizeof(wchar_t));
    if (dir == NULL) return;
    if (MultiByteToWideChar(CP_UTF8, 0, dir_utf8, -1, dir, n) == 0) {
        free(dir);
        return;
    }

    size_t len = wcslen(dir) + 16;
    wchar_t* argument = (wchar_t*)malloc(len * sizeof(wchar_t));
    if (argument != NULL) {
        swprintf(argument, len, L"--files \"%s\"", dir);
        spawn_surface(argument);
        free(argument);
    }
    free(dir);
}

/* Start the banner PROCESS if it is not running -- parked like the others.
 * Banners are the one surface with no user gesture to boot on: the engine
 * has to be warm before the first toast arrives or the toast waits a second
 * for it. */
void flwin32_shell_ensure_banners(void) {
    if (FindWindowW(L"FlutterSwiftWin32Host", L"Starling Banners") != NULL) {
        return;
    }
    wchar_t exe[MAX_PATH];
    if (GetModuleFileNameW(NULL, exe, MAX_PATH) == 0) return;
    ShellExecuteW(NULL, L"open", exe, L"--banners", NULL, SW_HIDE);
}

/* Start the Run-dialog process if it is not running -- parked, so Win+R is a
 * show rather than an engine boot. */
void flwin32_shell_ensure_run(void) {
    if (FindWindowW(L"FlutterSwiftWin32Host", L"Starling Run") != NULL) {
        return;
    }
    wchar_t exe[MAX_PATH];
    if (GetModuleFileNameW(NULL, exe, MAX_PATH) == 0) return;
    ShellExecuteW(NULL, L"open", exe, L"--run", NULL, SW_HIDE);
}

/* Start the launcher (Start menu) process if it is not running -- parked,
 * so the Windows key and the dock's launcher tile are a SHOW rather than an
 * engine boot. The manual dev launcher (starling.cmd) started `--launcher`
 * as a second process explicitly; the supervised `--session` shell has no
 * such second line, so without this the Start menu never had a process to
 * receive its toggle broadcast at all -- Win/tile did nothing. Same parked
 * idiom as the notification centre, banners and Run above. */
void flwin32_shell_ensure_launcher(void) {
    if (FindWindowW(L"FlutterSwiftWin32Host", L"Starling Launcher") != NULL) {
        return;
    }
    wchar_t exe[MAX_PATH];
    if (GetModuleFileNameW(NULL, exe, MAX_PATH) == 0) return;
    ShellExecuteW(NULL, L"open", exe, L"--launcher", NULL, SW_HIDE);
}

/* Whether explorer is running as the shell, by its desktop window. Progman
 * exists exactly as long as explorer does, and unlike Shell_TrayWnd it is a
 * class we never take -- so it stays an honest tell after the tray and the
 * appbar service are ours. */
int32_t flwin32_shell_explorer_present(void) {
    return FindWindowW(L"Progman", NULL) != NULL ? 1 : 0;
}

/* ---------------------------------------------------------- minimize target */

/*
 * Where a minimized window GOES, which is not a thing the shell draws.
 *
 * With no taskbar registered, user32 falls back to its pre-Win95 iconic
 * placement: a minimized window becomes a bare title-bar stub, 160x31 logical,
 * tiled left to right along the bottom of the WORK AREA -- which, because our
 * appbar reserves the dock's strip, is a neat row of stubs sitting directly on
 * top of the dock. It is stock user32 behaviour and nothing we draw, so no
 * amount of dock code makes it go away.
 *
 * The switch is SetTaskmanWindow, and only that. Measured on the shipping
 * shell, one probe window minimized five times in one session:
 *
 *     baseline (our shell)     -> (1570,1998)-(1884,2048)   stub, on screen
 *     a Shell_TrayWnd exists   -> (1570,1998)-(1884,2048)   no change
 *     SetTaskmanWindow(w)      -> (-32000,-32000)           off screen
 *     + SetShellWindow(w)      -> (-32000,-32000)           no further change
 *     probe destroyed          -> (1570,1998)-(1884,2048)   back again
 *
 * So owning Shell_TrayWnd -- which the tray already does -- is NOT enough, and
 * neither is being the shell window. The same probe under explorer parks at
 * -32000 on the first try, which is what "the native behaviour" means here:
 * the taskbar button is the entire restore affordance and the desktop stays
 * clean. shell32.dll is the module that references SetTaskmanWindow; explorer
 * itself does not, which is why grepping the wrong binary makes this look like
 * folklore.
 *
 * The window this registers is our own hidden one rather than the dock's, for
 * two reasons: the dock's HWND is a different window in every mode (panel,
 * one-view chrome), and the registration has to outlive any of them being
 * re-made. It is invisible and titled nothing, so the shell's own window list
 * filters it out without being told about it.
 *
 * Undocumented, so it is resolved at run time: a Windows that drops the export
 * should cost us the stubs, not the process.
 */

typedef BOOL(WINAPI* SetTaskmanWindowFn)(HWND);

static HWND g_taskman = NULL;

static LRESULT CALLBACK taskman_wndproc(HWND hwnd, UINT msg, WPARAM w,
                                        LPARAM l) {
    /* Ctrl+Esc. Windows posts SC_TASKLIST to whoever holds this window, which
     * is how the taskbar opens Start from a key it never registered. Taking
     * the window and ignoring the message would leave Ctrl+Esc dead, so it
     * goes where the Windows key already goes. */
    if (msg == WM_SYSCOMMAND && (w & 0xFFF0) == SC_TASKLIST) {
        flwin32_shell_broadcast_toggle();
        return 0;
    }
    return DefWindowProcW(hwnd, msg, w, l);
}

int32_t flwin32_shell_take_taskman_window(void) {
    HMODULE user32 = GetModuleHandleW(L"user32.dll");
    SetTaskmanWindowFn set_taskman =
        user32 == NULL
            ? NULL
            : (SetTaskmanWindowFn)GetProcAddress(user32, "SetTaskmanWindow");
    if (set_taskman == NULL) return 0;

    if (g_taskman == NULL || !IsWindow(g_taskman)) {
        WNDCLASSEXW wc;
        memset(&wc, 0, sizeof(wc));
        wc.cbSize = sizeof(wc);
        wc.lpfnWndProc = taskman_wndproc;
        wc.hInstance = GetModuleHandleW(NULL);
        wc.lpszClassName = L"StarlingTaskmanWindow";
        /* A second registration fails with ERROR_CLASS_ALREADY_EXISTS, which
         * is the right outcome for an idempotent call. */
        RegisterClassExW(&wc);
        g_taskman = CreateWindowExW(WS_EX_TOOLWINDOW, L"StarlingTaskmanWindow",
                                    L"", WS_POPUP, 0, 0, 16, 16, NULL, NULL,
                                    GetModuleHandleW(NULL), NULL);
        if (g_taskman == NULL) return 0;
    }
    /* Re-asserted rather than remembered: explorer's shell32 takes this window
     * for itself the moment explorer starts, so a session where explorer came
     * back (and was hidden again) has to claim it a second time. */
    return set_taskman(g_taskman) ? 1 : 0;
}

/* Whether a named Starling surface is currently on screen -- the banner asks
 * about the notification centre, because popping a banner under an open
 * centre that already shows the same toast is what the native shell
 * suppresses too. */
int32_t flwin32_shell_surface_visible(const char* title_utf8) {
    if (title_utf8 == NULL) return 0;
    wchar_t title[256];
    if (MultiByteToWideChar(CP_UTF8, 0, title_utf8, -1, title, 256) == 0) {
        return 0;
    }
    HWND w = FindWindowW(L"FlutterSwiftWin32Host", title);
    return (w != NULL && IsWindowVisible(w)) ? 1 : 0;
}
