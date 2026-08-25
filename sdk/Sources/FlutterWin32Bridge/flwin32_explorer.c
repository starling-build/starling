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
#include <objbase.h>
#include <shellapi.h>
#include <tlhelp32.h>
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

/* Set when WE started explorer (the packaged-app service). Its desktop then
 * has to stay down: we draw our own, and two full-screen desktops both
 * clamping themselves to the bottom of the z-order is a coin toss decided per
 * activation -- on the box it came up as explorer's wallpaper and explorer's
 * icons over ours. NOT tied to the ordinary taskbar hide: in trial mode
 * explorer IS the shell, our desktop surface deliberately does not run, and
 * hiding Progman there would leave the machine with no desktop at all. */
static int g_hide_desktop = 0;

static int hide_desktop_now(void) {
  HWND w = NULL;
  int touched = 0;
  if (!g_hide_desktop) return 0;
  while ((w = FindWindowExW(NULL, w, L"Progman", NULL)) != NULL) {
    if (!IsWindowVisible(w)) continue;
    ShowWindow(w, SW_HIDE);
    touched++;
  }
  return touched;
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
  if (is_tray_class(hwnd)) {
    ShowWindow(hwnd, SW_HIDE);
    return;
  }
  /* And explorer's desktop, when it is ours to suppress. Explorer re-shows
   * Progman on its own -- a theme change, a display change, its own restart
   * -- and a desktop that comes back over ours reads as "the shell lost its
   * wallpaper". */
  if (g_hide_desktop) {
    wchar_t cls[64];
    if (GetClassNameW(hwnd, cls, 64) > 0 && wcscmp(cls, L"Progman") == 0) {
      ShowWindow(hwnd, SW_HIDE);
    }
  }
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

/* "Is this process acting as the shell chrome" -- asked by the appbar service
 * next door, which has to know whether the work area is ours to compute.
 *
 * Hiding explorer's taskbar is the declaration: a process that did it has put
 * its own bar on that edge and taken the minimize target, and one that did
 * not (--keep-taskbar, or any process that is not the dock) has no business
 * touching the work area. The flag is set whether or not a taskbar was
 * actually found, because "explorer is not running" and "explorer's taskbar
 * is hidden" are the same intent and the same answer. */
int32_t flwin32_explorer_taskbar_hidden_by_us(void) {
  return g_hidden ? 1 : 0;
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

/* ------------------------------------------------- explorer as a SERVICE */

/*
 * Keeping explorer.exe alive without letting it be the shell.
 *
 * Packaged apps of the old CoreWindow kind -- Calculator, the Store, Windows
 * Security, anything whose window class is Windows.UI.Core.CoreWindow -- do
 * not run with explorer absent. Measured on the box, one A/B in one session,
 * activating Calculator through IApplicationActivationManager each time:
 *
 *   explorer absent   -> hr=0x80040900, the process is created and dies in
 *                        under two seconds, no window ever appears
 *   explorer running  -> hr=0, alive, ApplicationFrameWindow + CoreWindow
 *   explorer running,
 *   taskbar hidden    -> hr=0, alive, identical
 *
 * The AppModel log tells the same story from the other side: a working
 * activation logs "Created process" AND "Added process ... to Desktop AppX
 * container"; the failing one logs only the first. So this is not about which
 * process holds the shell role, it is about explorer.exe being alive to host
 * the frame -- which is also why the app comes back as an
 * ApplicationFrameWindow, the window our own list already accepts.
 *
 * Not every packaged app needs it: Photos (a WinUI desktop app, class
 * WinUIDesktopWin32WindowClass) activates fine with explorer absent, and so
 * does Windows Terminal. It is specifically the CoreWindow generation.
 *
 * Started WITHOUT the shell role: Winlogon has already started us as the
 * session's shell, so an explorer launched here creates no Progman and no
 * desktop -- verified, Progman stays NULL -- and hiding its taskbar is the
 * same job flwin32_explorer_taskbar_hide already does, hook and all. This is
 * what every third-party Windows shell does, and it is the configuration this
 * file was originally written for.
 */
/* The handle of the explorer we are keeping alive, so the tick does not have
 * to go looking.
 *
 * "Is explorer running" answered by a Toolhelp snapshot is a walk of every
 * process on the machine, and the supervisor asks every five seconds --
 * measured at 0.23% of a core against 0.00% before, which is most of an idle
 * shell's entire budget spent on a question whose answer is almost always
 * yes. A handle answers it in a syscall: WAIT_TIMEOUT means still running. */
static HANDLE g_explorer = NULL;

static int explorer_still_alive(void) {
    if (g_explorer == NULL) return 0;
    if (WaitForSingleObject(g_explorer, 0) == WAIT_TIMEOUT) return 1;
    CloseHandle(g_explorer);
    g_explorer = NULL;
    return 0;
}

static int explorer_running_in_session(void) {
    DWORD our_session = 0;
    ProcessIdToSessionId(GetCurrentProcessId(), &our_session);

    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return 0;

    PROCESSENTRY32W entry;
    entry.dwSize = sizeof(entry);
    int found = 0;
    if (Process32FirstW(snapshot, &entry)) {
        do {
            if (_wcsicmp(entry.szExeFile, L"explorer.exe") != 0) continue;
            /* Another user's explorer on a shared machine is not ours to
             * count: the apps we care about activate into THIS session. */
            DWORD session = 0;
            if (ProcessIdToSessionId(entry.th32ProcessID, &session) &&
                session == our_session) {
                found = 1;
                /* Hold it open, so this walk happens once rather than every
                 * tick. SYNCHRONIZE is all a liveness check needs. */
                if (g_explorer == NULL) {
                    g_explorer = OpenProcess(SYNCHRONIZE, FALSE,
                                             entry.th32ProcessID);
                }
                break;
            }
        } while (Process32NextW(snapshot, &entry));
    }
    CloseHandle(snapshot);
    return found;
}

int32_t flwin32_shell_ensure_explorer_service(void) {
    /* OPT-IN, and no longer the way packaged apps get launched.
     *
     * Keeping an explorer alive for the whole session is what made CoreWindow
     * packaged apps -- Settings, Calculator, the Store generation -- launch at
     * all. It cost about 227 MB permanently for a process the user never sees.
     * Measured on the box, that trade was unnecessary: explorer is needed only
     * for the ACTIVATION, not for running the app. Starting one takes 1.2 s to
     * make activation succeed, and once the app is up explorer can be killed
     * and the app carries on working indefinitely. So the shell borrows one per
     * launch (flwin32_shell_borrow_explorer) and idles with none.
     *
     * This is still here because a machine that launches packaged apps
     * constantly may prefer to pay the memory once rather than the 1.2 s every
     * time. Only an explicit "1" asks for it. Empty is not an instruction, and
     * reading it as one has already gone wrong in the other direction: while
     * this was written as "anything non-empty means on", the control run of an
     * A/B set it to "0", quietly started explorer, and measured the same
     * configuration twice. */
    wchar_t on[8];
    if (GetEnvironmentVariableW(L"STARLING_EXPLORER_SERVICE", on, 8) == 0 ||
        on[0] != L'1') {
        return 0;
    }

    /* Set BEFORE the early return: on a shell restart the service explorer is
     * already there (we started it last time round), and its chrome still has
     * to stay down. The caller is the supervisor, and it only asks when it is
     * the shell -- in trial mode explorer's desktop is the user's desktop and
     * nothing here may touch it. */
    g_hide_desktop = 1;
    /* The cheap question first: the handle we already hold. Only when that
     * says the explorer we started is gone does this walk the process list. */
    if (explorer_still_alive() || explorer_running_in_session()) {
        flwin32_shell_suppress_explorer_chrome();
        return 0;
    }

    wchar_t path[MAX_PATH];
    UINT n = GetWindowsDirectoryW(path, MAX_PATH);
    if (n == 0 || n >= MAX_PATH - 16) return 0;
    wcscat_s(path, MAX_PATH, L"\\explorer.exe");

    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    memset(&si, 0, sizeof(si));
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;
    if (!CreateProcessW(path, NULL, NULL, NULL, FALSE, 0, NULL, NULL, &si,
                        &pi)) {
        return 0;
    }
    CloseHandle(pi.hThread);
    /* Kept, not closed: this is the handle the tick asks. */
    if (g_explorer != NULL) CloseHandle(g_explorer);
    g_explorer = pi.hProcess;

    /* Its chrome goes straight back down. Explorer does not have a taskbar or
     * a desktop the instant CreateProcess returns -- both arrive a second or
     * two later -- so a single hide here would hide nothing and the user
     * would watch somebody else's taskbar slide over the dock. Hold it for
     * three seconds, which covers every start measured on the box; the
     * EVENT_OBJECT_SHOW hook and the dock's own check carry it from there. */
    for (int i = 0; i < 12; i++) {
        Sleep(250);
        flwin32_explorer_taskbar_hide();
        hide_desktop_now();
    }
    return 1;
}

/* Idempotent, cheap, and safe to call on a timer: what the supervisor's tick
 * uses to keep explorer's chrome down between the hook's notifications. */
void flwin32_shell_suppress_explorer_chrome(void) {
    if (!g_hide_desktop) return;
    /* ...and keep our tray window above explorer's while it is up. It is not
     * only a matter of what the user sees: the topmost Shell_TrayWnd is the
     * one SHAppBarMessage talks to, so losing that position hands the appbar
     * protocol -- and with it the dock's own reservation -- to explorer. */
    flwin32_tray_raise();
    if (flwin32_explorer_taskbar_visible()) flwin32_explorer_taskbar_hide();
    hide_desktop_now();
}

/* ── borrowing explorer for the length of one launch ──────────────────────
 *
 * CoreWindow packaged apps -- Settings and Calculator among them -- cannot be
 * activated unless explorer is running. Not because the app needs it, and not
 * because of anything on screen: explorer publishes a background COM component
 * that the activation machinery asks for by identity, the component exists only
 * while explorer runs, and without it the launch is refused outright. The app
 * process is never created at all.
 *
 * The whole dependency is at LAUNCH TIME, which is what makes this cheap.
 * Measured on the box, with our shell running and no explorer:
 *
 *     start explorer, poll activation  -> succeeds after 1.2 s
 *     kill explorer, watch the app     -> window visible and its thread still
 *                                         answering 25 s later
 *     activate again with none running -> refused, exactly as before
 *
 * So explorer is borrowed for a couple of seconds per launch and dropped, and
 * an idle session runs none. The alternative was to implement that component
 * ourselves: it is unnamed, undocumented, has no stable contract, and getting
 * past its first method call only reveals the next one.
 *
 * We borrow ONLY when no explorer is running. One that is already there is
 * somebody else's -- the opt-in service above, or a user who started it -- and
 * killing it is not ours to do.
 */
static HANDLE g_borrowed = NULL;
static int g_borrow_saved_hide = 0;

/* Is the borrowed explorer far enough along to serve an activation?
 *
 * Two wrong answers were measured before this one. Retrying the ACTIVATION as
 * the readiness test costs about a second per refusal, so the launch took 46
 * seconds. Asking COM whether the class exists yet is worse, not better: the
 * failing create goes to the service control manager and takes most of a
 * second too, so that timed at 53.
 *
 * Explorer's desktop window is the cheap signal. It appears when explorer has
 * started as the session's shell, which is the same moment the rest of its
 * shell side comes up, and FindWindow answers instantly whether it is there or
 * not. It stays findable after we hide it -- hiding is ShowWindow, not
 * destruction -- so the suppression running alongside this does not blind it.
 */
static int32_t explorer_shell_up(void) {
    return FindWindowW(L"Progman", NULL) != NULL ? 1 : 0;
}

int32_t flwin32_shell_services_ready(void) {
    return explorer_shell_up();
}

int32_t flwin32_shell_borrow_explorer(void) {
    if (g_borrowed != NULL) return 0;
    if (explorer_still_alive() || explorer_running_in_session()) return 0;

    wchar_t path[MAX_PATH];
    UINT n = GetWindowsDirectoryW(path, MAX_PATH);
    if (n == 0 || n >= MAX_PATH - 16) return 0;
    wcscat_s(path, MAX_PATH, L"\\explorer.exe");

    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    memset(&si, 0, sizeof(si));
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;
    if (!CreateProcessW(path, NULL, NULL, NULL, FALSE, 0, NULL, NULL, &si,
                        &pi)) {
        return 0;
    }
    CloseHandle(pi.hThread);
    g_borrowed = pi.hProcess;
    /* Its chrome has to stay down for the seconds it is up, and that is the
     * same suppression the opt-in service uses -- so turn that on for the
     * duration even when the service is off, and put the flag back after. */
    g_borrow_saved_hide = g_hide_desktop;
    g_hide_desktop = 1;
    return 1;
}

/* Hand it back. The kill runs on its own thread after a grace period, because
 * the caller is a launch: holding it open for three seconds to watch a process
 * we are about to kill would put that delay in front of the user's app. The
 * grace period is not superstition -- activation returning success means the
 * app was STARTED, and it is still talking to the shell for a moment after. */
static DWORD WINAPI borrow_end(LPVOID param) {
    HANDLE h = (HANDLE)param;
    int i;
    /* TEN SECONDS, not three. Activation returning success means the app was
     * started, not that it is finished starting: a packaged app's window frame
     * is built by ApplicationFrameHost in concert with the shell, and dropping
     * explorer before that lands leaves the app running with no frame -- on the
     * box, Calculator came up as a bare full-screen surface instead of a window
     * you can move, and only sometimes, which is what a race looks like.
     * The cost of being generous is an explorer alive for ten seconds after a
     * launch; the cost of being tight is an app in the wrong shape. Idle is
     * unaffected either way -- nothing is running when nothing was launched. */
    for (i = 0; i < 40; i++) {
        Sleep(250);
        flwin32_shell_suppress_explorer_chrome();
    }
    TerminateProcess(h, 0);
    CloseHandle(h);
    g_hide_desktop = g_borrow_saved_hide;
    /* The show-hook was watching a process that no longer exists. */
    unhook_explorer();
    /* Its taskbar was a registered appbar and took work area from the dock's.
     * Nothing announces a bar whose window died with its process, so the
     * reservation has to be recomputed by hand or the desktop stays short by
     * a taskbar's height. No-op in a process that does not host the tray. */
    /* A SWEEP, not one shot. The last word on the work area does not always
     * land while explorer is still alive -- a single repair 400 ms after the
     * kill put the reservation back for one app and not for the next, which is
     * the signature of racing something rather than of a wrong answer. Each
     * pass is a comparison and writes nothing when the answer already agrees,
     * so the cost of covering three seconds is three comparisons.
     *
     * Locally AND by broadcast: the local call is the one that definitely
     * arrives, and the broadcast is the one that reaches the dock when the
     * process that borrowed is somebody else (a one-shot launcher, a test). */
    {
        UINT recheck = RegisterWindowMessageW(L"StarlingWorkAreaRecheck");
        static const int kAt[] = {400, 700, 1000, 1500, 2000, 3000};
        int prev = 0;
        int k;
        for (k = 0; k < (int)(sizeof(kAt) / sizeof(kAt[0])); k++) {
            Sleep((DWORD)(kAt[k] - prev));
            prev = kAt[k];
            flwin32_tray_raise();
            flwin32_tray_reapply_workarea();
            SendNotifyMessageW(HWND_BROADCAST, recheck, 0, 0);
        }
    }
    return 0;
}

void flwin32_shell_return_explorer(void) {
    HANDLE h = g_borrowed;
    HANDLE t;
    if (h == NULL) return;
    g_borrowed = NULL;
    t = CreateThread(NULL, 0, borrow_end, h, 0, NULL);
    if (t != NULL) {
        CloseHandle(t);
    } else {
        TerminateProcess(h, 0);
        CloseHandle(h);
        g_hide_desktop = g_borrow_saved_hide;
    }
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
