// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/*
 * flwin32_sessionslot.c -- the session slot (shell-replacement Phase 5).
 *
 * The primitives behind `WinShellBar.exe --session`: spawn a surface of this
 * same binary and get a HANDLE back (ShellExecuteW, which the ensure_*
 * helpers use, hands out none -- a supervisor that cannot wait on its
 * children is a supervisor in name only), wait on the set, read and write
 * the per-user Winlogon\Shell value, and enumerate the Run/RunOnce keys the
 * startup runner replays.
 *
 * Policy lives in Swift (Session.swift): the startup ORDER, RunOnce's
 * delete-before-run semantics, the crash-loop arithmetic. This file is only
 * the Win32 that Swift cannot spell.
 */

#include "include/FlutterWin32Bridge.h"

#ifdef _WIN32

#include <windows.h>
#include <tlhelp32.h>
#include <shellapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

/* ------------------------------------------------------------- utf8 <-> wide */

static wchar_t* sess_utf8_to_wide(const char* utf8) {
    if (utf8 == NULL) return NULL;
    int n = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, NULL, 0);
    if (n <= 0) return NULL;
    wchar_t* out = (wchar_t*)malloc((size_t)n * sizeof(wchar_t));
    if (out == NULL) return NULL;
    MultiByteToWideChar(CP_UTF8, 0, utf8, -1, out, n);
    return out;
}

static int32_t sess_wide_out(const wchar_t* wide, char* out, int32_t out_size) {
    if (wide == NULL || out == NULL || out_size <= 0) return 0;
    int n = WideCharToMultiByte(CP_UTF8, 0, wide, -1, out, out_size, NULL, NULL);
    return n > 0 ? n - 1 : 0;
}

/* ------------------------------------------------------------------ children */

/* Spawn this same executable with `args`, console-less, and return the
 * process handle for the supervisor to wait on. CreateProcessW rather than
 * ShellExecuteW for exactly that handle; CREATE_NO_WINDOW because this is a
 * console-subsystem binary and each child would otherwise pop one. */
/* Kill any shell process of ours that is already running, before starting a
 * session's children.
 *
 * A supervisor that dies does NOT take its children with it, and Winlogon
 * starts a replacement within a second (AutoRestartShell). The replacement
 * spawns its own dock, the orphaned one keeps running, and now the session has
 * two -- two appbar services, two tray windows, two answers to "how much of
 * the screen is reserved", and which one Windows talks to is decided by window
 * stacking order. Left to accumulate it reached FIVE docks on the box, and
 * every measurement taken in that state was noise: the work area moved on its
 * own between two reads, and four correct-looking fixes for it each appeared
 * to work once and then not.
 *
 * A job object with kill-on-close is the tidier-looking answer and is a trap:
 * everything a child starts joins the job too, so quitting the shell would
 * take the user's browser with it. Reaping at startup has no such reach -- the
 * only claim being made is that when a session begins, no shell of ours should
 * already be running, which is true by construction.
 *
 * Scoped to THIS logon session and to processes with our own image name, so a
 * second user's shell on the same machine is not ours to end. */
/* ONE SUPERVISOR PER SESSION, and this is what makes the reaper safe.
 *
 * The reaper below clears out children left by a supervisor that died. That is
 * only ever the right thing to do if no OTHER supervisor is alive -- otherwise
 * it is killing a running shell's children, that shell notices them die,
 * restarts them, decides it is in a crash loop, and hands the desktop back to
 * explorer. Measured, twice: two supervisors at logon, both reaping, and the
 * session ending with our shell unregistered.
 *
 * A named mutex settles it without anybody having to kill anybody. The second
 * supervisor stands down; the name is released when the owner's handles close,
 * which a dying process does for free, so there is nothing to reset. */
static HANDLE g_supervisor_mutex = NULL;

int32_t flwin32_sessionslot_claim_supervisor(void) {
    if (g_supervisor_mutex != NULL) return 1;
    g_supervisor_mutex = CreateMutexW(NULL, TRUE,
                                      L"Local\\StarlingSessionSupervisor");
    /* Cannot tell -- proceed rather than refuse to be a shell at all. */
    if (g_supervisor_mutex == NULL) return 1;
    if (GetLastError() == ERROR_ALREADY_EXISTS) {
        CloseHandle(g_supervisor_mutex);
        g_supervisor_mutex = NULL;
        return 0;
    }
    return 1;
}

/* A CHILD SAYS SO ITSELF, because the reaper has to tell a child from another
 * supervisor and cannot do it by process name -- every one of them is this
 * same binary.
 *
 * Getting that wrong is not a small bug. A reaper that kills supervisors kills
 * the one Winlogon is watching; Winlogon restarts it; the restarted one reaps
 * the reaper. Measured, once: a new session every thirteen seconds, each
 * reaping five processes and priming afresh, forever.
 *
 * A named event is enough. The child creates one keyed on its own process id
 * and never touches it again; anyone can ask whether it exists, and it goes
 * away with the process, so there is nothing to clean up and nothing to go
 * stale. */
static HANDLE g_child_mark = NULL;

void flwin32_sessionslot_mark_child(void) {
    wchar_t name[64];
    if (g_child_mark != NULL) return;
    _snwprintf_s(name, 64, _TRUNCATE, L"Local\\StarlingShellChild-%lu",
                 (unsigned long)GetCurrentProcessId());
    g_child_mark = CreateEventW(NULL, TRUE, FALSE, name);
}

static int is_marked_child(DWORD pid) {
    wchar_t name[64];
    HANDLE h;
    _snwprintf_s(name, 64, _TRUNCATE, L"Local\\StarlingShellChild-%lu",
                 (unsigned long)pid);
    h = OpenEventW(SYNCHRONIZE, FALSE, name);
    if (h == NULL) return 0;
    CloseHandle(h);
    return 1;
}

int32_t flwin32_sessionslot_reap_strays(void) {
    DWORD self = GetCurrentProcessId();
    DWORD our_session = 0;
    wchar_t path[MAX_PATH];
    const wchar_t* leaf;
    HANDLE snap;
    PROCESSENTRY32W entry;
    int32_t killed = 0;

    ProcessIdToSessionId(self, &our_session);
    if (GetModuleFileNameW(NULL, path, MAX_PATH) == 0) return 0;
    leaf = wcsrchr(path, L'\\');
    leaf = (leaf != NULL) ? leaf + 1 : path;

    snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) return 0;
    entry.dwSize = sizeof(entry);
    if (Process32FirstW(snap, &entry)) {
        do {
            DWORD session = 0;
            HANDLE proc;
            if (entry.th32ProcessID == self) continue;
            if (_wcsicmp(entry.szExeFile, leaf) != 0) continue;
            if (!ProcessIdToSessionId(entry.th32ProcessID, &session)) continue;
            if (session != our_session) continue;
            /* Children only. Another supervisor is not ours to end. */
            if (!is_marked_child(entry.th32ProcessID)) continue;
            proc = OpenProcess(PROCESS_TERMINATE, FALSE, entry.th32ProcessID);
            if (proc == NULL) continue;
            if (TerminateProcess(proc, 0)) killed++;
            CloseHandle(proc);
        } while (Process32NextW(snap, &entry));
    }
    CloseHandle(snap);
    return killed;
}

uint64_t flwin32_sessionslot_spawn_self(const char* args_utf8) {
    wchar_t exe[MAX_PATH];
    if (GetModuleFileNameW(NULL, exe, MAX_PATH) == 0) return 0;

    wchar_t* wargs = sess_utf8_to_wide(args_utf8 ? args_utf8 : "");
    if (wargs == NULL) return 0;

    /* CreateProcessW mutates the command line; build "exe args" writable. */
    size_t len = wcslen(exe) + wcslen(wargs) + 4;
    wchar_t* cmd = (wchar_t*)malloc(len * sizeof(wchar_t));
    if (cmd == NULL) { free(wargs); return 0; }
    swprintf(cmd, len, L"\"%s\" %s", exe, wargs);
    free(wargs);

    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    memset(&si, 0, sizeof(si));
    si.cb = sizeof(si);
    BOOL ok = CreateProcessW(exe, cmd, NULL, NULL, FALSE, CREATE_NO_WINDOW,
                             NULL, NULL, &si, &pi);
    free(cmd);
    if (!ok) return 0;
    CloseHandle(pi.hThread);
    return (uint64_t)(uintptr_t)pi.hProcess;
}

/* Wait for any of the handles to exit, or the timeout. Returns the index of
 * the exited child, -1 on timeout, -2 on error.
 *
 * Does NOT pump messages, so nothing message-delivered may depend on this
 * thread -- which is why the explorer taskbar re-hide hook lives on its own
 * pumping thread (flwin32_explorer.c) rather than on whichever thread asked
 * for it. */
int32_t flwin32_sessionslot_wait_any(const uint64_t* handles, int32_t count,
                                 int32_t timeout_ms) {
    HANDLE hs[MAXIMUM_WAIT_OBJECTS];
    int32_t i;
    if (handles == NULL || count <= 0 || count > MAXIMUM_WAIT_OBJECTS) return -2;
    for (i = 0; i < count; i++) hs[i] = (HANDLE)(uintptr_t)handles[i];
    DWORD r = WaitForMultipleObjects((DWORD)count, hs, FALSE,
                                     timeout_ms < 0 ? INFINITE
                                                    : (DWORD)timeout_ms);
    if (r >= WAIT_OBJECT_0 && r < WAIT_OBJECT_0 + (DWORD)count) {
        return (int32_t)(r - WAIT_OBJECT_0);
    }
    if (r == WAIT_TIMEOUT) return -1;
    return -2;
}

void flwin32_sessionslot_close_handle(uint64_t handle) {
    if (handle != 0) CloseHandle((HANDLE)(uintptr_t)handle);
}

/* The exit code of a child the wait just reported, for the supervisor's log
 * line. The one number that separates the families at a glance: 0 is the
 * polite-close path (a WM_CLOSE the window obeyed), 1 an explicit bail,
 * 0xC000001D a Swift trap, 0xC00000FD a stack overflow, and anything else
 * an outside TerminateProcess wearing that caller's code. -1: could not
 * read. */
int64_t flwin32_sessionslot_exit_code(uint64_t handle) {
    DWORD code = 0;
    if (handle == 0) return -1;
    if (!GetExitCodeProcess((HANDLE)(uintptr_t)handle, &code)) return -1;
    return (int64_t)code;
}

/* The bail-out's reaper: a child left running would fight the returning
 * explorer for the surface it draws (the desktop plane above all). Hard
 * terminate -- the children hold no state worth a graceful anything. */
void flwin32_sessionslot_kill(uint64_t handle) {
    if (handle != 0) TerminateProcess((HANDLE)(uintptr_t)handle, 1);
}

int32_t flwin32_sessionslot_alive(uint64_t handle) {
    DWORD code = 0;
    if (handle == 0) return 0;
    if (!GetExitCodeProcess((HANDLE)(uintptr_t)handle, &code)) return 0;
    return code == STILL_ACTIVE ? 1 : 0;
}

/* ------------------------------------------------------- the Winlogon slot */

static const wchar_t kWinlogonKey[] =
    L"Software\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon";

/* The per-user Shell value. Chars written, 0 when the value is absent --
 * which means the machine default (explorer.exe) and is the healthy
 * unregistered state, not an error. */
int32_t flwin32_sessionslot_shell_get(char* out, int32_t out_size) {
    HKEY key;
    wchar_t value[1024];
    DWORD size = sizeof(value);
    DWORD type = 0;
    LONG r;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, kWinlogonKey, 0, KEY_READ, &key)
        != ERROR_SUCCESS) {
        return 0;
    }
    r = RegQueryValueExW(key, L"Shell", NULL, &type, (LPBYTE)value, &size);
    RegCloseKey(key);
    if (r != ERROR_SUCCESS || (type != REG_SZ && type != REG_EXPAND_SZ)) {
        return 0;
    }
    value[(sizeof(value) / sizeof(wchar_t)) - 1] = L'\0';
    return sess_wide_out(value, out, out_size);
}

/* Write the per-user Shell value; NULL deletes it, restoring the machine
 * default. HKCU only, by design -- machine-wide registration is a decision
 * this code refuses to be able to make. */
int32_t flwin32_sessionslot_shell_set(const char* cmdline_utf8) {
    HKEY key;
    LONG r;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, kWinlogonKey, 0, NULL, 0,
                        KEY_SET_VALUE, NULL, &key, NULL) != ERROR_SUCCESS) {
        return 0;
    }
    if (cmdline_utf8 == NULL) {
        r = RegDeleteValueW(key, L"Shell");
        RegCloseKey(key);
        return (r == ERROR_SUCCESS || r == ERROR_FILE_NOT_FOUND) ? 1 : 0;
    }
    {
        wchar_t* wide = sess_utf8_to_wide(cmdline_utf8);
        if (wide == NULL) { RegCloseKey(key); return 0; }
        r = RegSetValueExW(key, L"Shell", 0, REG_SZ, (const BYTE*)wide,
                           (DWORD)((wcslen(wide) + 1) * sizeof(wchar_t)));
        free(wide);
    }
    RegCloseKey(key);
    return r == ERROR_SUCCESS ? 1 : 0;
}

/* ------------------------------------------------------------ startup keys */

static const wchar_t kRunKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
static const wchar_t kRunOnceKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\RunOnce";

/* which -> hive/key/view. HKLM Run is enumerated in BOTH registry views
 * (64-bit and Wow6432Node): explorer processes both, and a 32-bit app's
 * autostart lives only in the second. */
static int sess_startup_open(int32_t which, int view32, HKEY* out) {
    HKEY hive = (which == 0 || which == 1) ? HKEY_LOCAL_MACHINE
                                          : HKEY_CURRENT_USER;
    const wchar_t* key = (which == 0 || which == 5) ? kRunOnceKey : kRunKey;
    REGSAM sam = KEY_READ | (view32 ? KEY_WOW64_32KEY : KEY_WOW64_64KEY);
    return RegOpenKeyExW(hive, key, 0, sam, out) == ERROR_SUCCESS;
}

/* One source's entries as "name\tcommand\n" lines. which: 0 HKLM RunOnce,
 * 1 HKLM Run, 2 HKCU Run, 5 HKCU RunOnce (3/4 are the Startup folders,
 * listed by the caller from flwin32_known_folder). Empty commands are
 * skipped, as explorer skips them. */
int32_t flwin32_sessionslot_startup_list(int32_t which, char* out,
                                     int32_t out_size) {
    int32_t used = 0;
    int views = (which == 0 || which == 1) ? 2 : 1;
    int v;
    if (out == NULL || out_size <= 0) return 0;
    out[0] = '\0';
    for (v = 0; v < views; v++) {
        HKEY key;
        DWORD index = 0;
        if (!sess_startup_open(which, v, &key)) continue;
        for (;;) {
            wchar_t name[256];
            wchar_t data[2048];
            DWORD name_len = sizeof(name) / sizeof(wchar_t);
            DWORD data_len = sizeof(data);
            DWORD type = 0;
            LONG r = RegEnumValueW(key, index++, name, &name_len, NULL, &type,
                                   (LPBYTE)data, &data_len);
            if (r == ERROR_NO_MORE_ITEMS) break;
            if (r != ERROR_SUCCESS) continue;
            if (type != REG_SZ && type != REG_EXPAND_SZ) continue;
            data[(sizeof(data) / sizeof(wchar_t)) - 1] = L'\0';
            if (data[0] == L'\0') continue;
            {
                wchar_t expanded[2048];
                const wchar_t* cmd = data;
                if (type == REG_EXPAND_SZ &&
                    ExpandEnvironmentStringsW(data, expanded,
                        sizeof(expanded) / sizeof(wchar_t)) > 0) {
                    cmd = expanded;
                }
                {
                    char n8[768], c8[4096];
                    int wrote;
                    if (sess_wide_out(name, n8, sizeof(n8)) == 0 && name[0]) continue;
                    sess_wide_out(name, n8, sizeof(n8));
                    sess_wide_out(cmd, c8, sizeof(c8));
                    wrote = _snprintf_s(out + used, (size_t)(out_size - used),
                                        _TRUNCATE, "%s\t%s\n", n8, c8);
                    if (wrote < 0) { RegCloseKey(key); return used; }
                    used += wrote;
                }
            }
        }
        RegCloseKey(key);
    }
    return used;
}

/* Delete one RunOnce value -- the delete-BEFORE-run half of explorer's
 * semantics (the "!" prefix, delete-after, is the caller's to sequence).
 * which: 0 HKLM (needs rights; failure means DO NOT run the entry, or it
 * runs again every logon), 5 HKCU. */
int32_t flwin32_sessionslot_runonce_delete(int32_t which, const char* name_utf8) {
    HKEY hive = which == 0 ? HKEY_LOCAL_MACHINE : HKEY_CURRENT_USER;
    int views = which == 0 ? 2 : 1;
    int v;
    int deleted = 0;
    wchar_t* wname = sess_utf8_to_wide(name_utf8);
    if (wname == NULL) return 0;
    for (v = 0; v < views; v++) {
        HKEY key;
        REGSAM sam = KEY_SET_VALUE | (v ? KEY_WOW64_32KEY : KEY_WOW64_64KEY);
        if (RegOpenKeyExW(hive, kRunOnceKey, 0, sam, &key) != ERROR_SUCCESS) {
            continue;
        }
        if (RegDeleteValueW(key, wname) == ERROR_SUCCESS) deleted = 1;
        RegCloseKey(key);
    }
    free(wname);
    return deleted;
}

/* Run one registry startup entry. CreateProcessW on the raw command line
 * first -- that is how explorer runs these, and how their quoting expects to
 * be read -- with a ShellExecuteW fallback for values that are a bare
 * document path. */
int32_t flwin32_sessionslot_exec_command(const char* cmdline_utf8) {
    wchar_t* cmd = sess_utf8_to_wide(cmdline_utf8);
    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    if (cmd == NULL) return 0;
    memset(&si, 0, sizeof(si));
    si.cb = sizeof(si);
    if (CreateProcessW(NULL, cmd, NULL, NULL, FALSE, 0, NULL, NULL,
                       &si, &pi)) {
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
        free(cmd);
        return 1;
    }
    {
        HINSTANCE r = ShellExecuteW(NULL, L"open", cmd, NULL, NULL,
                                    SW_SHOWNORMAL);
        free(cmd);
        return (INT_PTR)r > 32 ? 1 : 0;
    }
}

/* Hide this process's console window -- but only when the process OWNS it
 * (attached process count 1: started by Winlogon or a double-click, which
 * pops a fresh console for a console-subsystem binary). Run from a
 * terminal, the console is the terminal, and hiding the window the user
 * typed into is not a fix for anything. The VM soak found this: Shell=
 * started the supervisor and the session came up wearing a console. */
/* The console host's own window, which is NOT what GetConsoleWindow answers
 * with when Windows Terminal is the host -- and on Windows 11 it is. There the
 * call hands back a hidden stand-in belonging to the pseudoconsole, so hiding
 * it hides something nobody could see while Terminal's window stays on screen.
 * On the box it came up minimized in the bottom-left corner: a visible stub on
 * the desktop, which is the one thing this shell exists to prevent.
 *
 * Detaching from the console instead (FreeConsole) is the tidy-looking answer
 * and it takes the whole session down -- 0 of 10 checks, nothing on screen at
 * all. Whatever the supervisor does afterwards needs its console.
 *
 * So: find the host's window by the one thing that identifies it as ours, the
 * title, which the host sets to our command line verbatim. */
static BOOL CALLBACK hide_console_host(HWND hwnd, LPARAM param) {
    const wchar_t* mine = (const wchar_t*)param;
    wchar_t title[512];
    wchar_t cls[64];
    if (GetClassNameW(hwnd, cls, 64) <= 0) return TRUE;
    if (wcscmp(cls, L"CASCADIA_HOSTING_WINDOW_CLASS") != 0 &&
        wcscmp(cls, L"ConsoleWindowClass") != 0) {
        return TRUE;
    }
    if (GetWindowTextW(hwnd, title, 512) <= 0) return TRUE;
    if (wcscmp(title, mine) != 0) return TRUE;
    ShowWindow(hwnd, SW_HIDE);
    return TRUE;
}

void flwin32_sessionslot_hide_own_console(void) {
    HWND console = GetConsoleWindow();
    DWORD pids[4];
    const wchar_t* mine;
    if (console == NULL) return;
    if (GetConsoleProcessList(pids, 4) != 1) return;
    ShowWindow(console, SW_HIDE);
    mine = GetCommandLineW();
    if (mine != NULL) EnumWindows(hide_console_host, (LPARAM)mine);
}

/* The supervisor's bail-out: explorer back as the running shell. A plain
 * spawn -- when Winlogon's Shell slot is ours and we are giving up, starting
 * explorer.exe IS restoring the desktop; the registry write that stops the
 * next logon from repeating this is the caller's, first. */
int32_t flwin32_sessionslot_start_explorer(void) {
    wchar_t path[MAX_PATH];
    UINT n = GetWindowsDirectoryW(path, MAX_PATH);
    if (n == 0 || n > MAX_PATH - 14) return 0;
    wcscat_s(path, MAX_PATH, L"\\explorer.exe");
    {
        HINSTANCE r = ShellExecuteW(NULL, L"open", path, NULL, NULL,
                                    SW_SHOWNORMAL);
        return (INT_PTR)r > 32 ? 1 : 0;
    }
}

#endif  /* _WIN32 */
