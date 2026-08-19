// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/*
 * flwin32_apps.c -- the installed applications, and how to start one.
 *
 * On Linux the Starling shell reads the app registry: catalog.d/*.app plus the
 * .desktop entries app-install records. Windows has no such registry -- what it
 * has is the START MENU, a directory tree of .lnk shortcuts, one per app, in a
 * machine-wide location and a per-user one. That IS the catalog every Windows
 * shell reads, Explorer included, and it is what the dock and the launcher
 * enumerate here.
 *
 * Plain ASCII throughout, same reason as the neighbouring files.
 *
 * The one thing worth knowing: a .lnk is a structured binary file, not a
 * symlink, and the only supported way to read one is the IShellLink COM
 * interface. Parsing the format by hand is a known-bad idea -- the target can
 * be stored as an item-ID list rather than a path, and resolving that needs
 * the shell anyway.
 */

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <windows.h>
#include <shlobj.h>    /* IShellLinkW, SHGetKnownFolderPath */
#include <shobjidl.h>
#include <objbase.h>
#include <shellapi.h>  /* ShellExecuteW */
#include <stdlib.h>
#include <string.h>

#include "include/FlutterWin32Bridge.h"

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")

/* UTF-16 -> UTF-8 into the caller's buffer, with the shared convention:
 * bytes written including the terminator, or -1 when the buffer is short. */
static int32_t wide_copy_out(const wchar_t* w, char* out, int32_t out_size) {
    if (w == NULL) return 0;
    int need = WideCharToMultiByte(CP_UTF8, 0, w, -1, NULL, 0, NULL, NULL);
    if (need <= 0) return 0;
    if (out == NULL || out_size < need) return -1;
    WideCharToMultiByte(CP_UTF8, 0, w, -1, out, out_size, NULL, NULL);
    return need;
}

static wchar_t* utf8_to_wide(const char* utf8) {
    if (utf8 == NULL) return NULL;
    int n = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, NULL, 0);
    if (n <= 0) return NULL;
    wchar_t* out = (wchar_t*)calloc((size_t)n, sizeof(wchar_t));
    if (out == NULL) return NULL;
    MultiByteToWideChar(CP_UTF8, 0, utf8, -1, out, n);
    return out;
}

/* COM on this thread, once. The UI thread is an STA as far as the shell is
 * concerned, and re-initializing it per call would be both wasteful and, if
 * the apartment ever disagreed, a failure that only shows up on the second
 * call. */
static void ensure_com(void) {
    static int done = 0;
    if (done) return;
    done = 1;
    CoInitializeEx(NULL, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
}

int32_t flwin32_shortcut_target(const char* shortcut_path,
                                char* out,
                                int32_t out_size) {
    if (shortcut_path == NULL) return 0;
    ensure_com();

    wchar_t* wpath = utf8_to_wide(shortcut_path);
    if (wpath == NULL) return 0;

    IShellLinkW* link = NULL;
    int32_t result = 0;
    if (SUCCEEDED(CoCreateInstance(&CLSID_ShellLink, NULL, CLSCTX_INPROC_SERVER,
                                   &IID_IShellLinkW, (void**)&link))) {
        IPersistFile* file = NULL;
        if (SUCCEEDED(link->lpVtbl->QueryInterface(link, &IID_IPersistFile,
                                                   (void**)&file))) {
            if (SUCCEEDED(file->lpVtbl->Load(file, wpath, STGM_READ))) {
                wchar_t target[MAX_PATH];
                target[0] = L'\0';
                /* No SLGP_UNCPRIORITY / no resolve: Resolve() would go looking
                 * for a moved target, which puts a network timeout in the
                 * middle of building a dock. The stored path is what Explorer
                 * shows. */
                if (SUCCEEDED(link->lpVtbl->GetPath(link, target, MAX_PATH, NULL,
                                                    SLGP_RAWPATH))) {
                    /* SLGP_RAWPATH means literally raw: a great many Windows
                     * shortcuts store "%windir%\\system32\\charmap.exe"
                     * rather than a resolved path, and every one of those
                     * fails to open, fails to yield an icon, and fails to
                     * match a running window's executable -- silently, and
                     * only for the built-in tools, which is what makes it
                     * look like a font or a rendering problem rather than a
                     * path one. */
                    wchar_t expanded[MAX_PATH];
                    DWORD n = ExpandEnvironmentStringsW(target, expanded, MAX_PATH);
                    result = wide_copy_out(
                        (n > 0 && n <= MAX_PATH) ? expanded : target,
                        out, out_size);
                }
            }
            file->lpVtbl->Release(file);
        }
        link->lpVtbl->Release(link);
    }
    free(wpath);
    return result;
}

/* Target, arguments and working directory in ONE link load.
 *
 * Not three calls: the catalog walk already loads every .lnk once, and the
 * load is the expensive half. And not just the target, because launching the
 * target without the shortcut's arguments silently starts the wrong thing --
 * a great many Start Menu entries are one exe plus a switch (control panel
 * applets, the PowerShell profiles, anything with an -ExecutionPolicy). */
int32_t flwin32_shortcut_info(const char* shortcut_path,
                              char* target, int32_t target_size,
                              char* arguments, int32_t arguments_size,
                              char* workdir, int32_t workdir_size) {
    if (shortcut_path == NULL) return 0;
    ensure_com();

    wchar_t* wpath = utf8_to_wide(shortcut_path);
    if (wpath == NULL) return 0;

    if (target != NULL && target_size > 0) target[0] = '\0';
    if (arguments != NULL && arguments_size > 0) arguments[0] = '\0';
    if (workdir != NULL && workdir_size > 0) workdir[0] = '\0';

    IShellLinkW* link = NULL;
    int32_t result = 0;
    if (SUCCEEDED(CoCreateInstance(&CLSID_ShellLink, NULL, CLSCTX_INPROC_SERVER,
                                   &IID_IShellLinkW, (void**)&link))) {
        IPersistFile* file = NULL;
        if (SUCCEEDED(link->lpVtbl->QueryInterface(link, &IID_IPersistFile,
                                                   (void**)&file))) {
            if (SUCCEEDED(file->lpVtbl->Load(file, wpath, STGM_READ))) {
                wchar_t buf[MAX_PATH];
                wchar_t expanded[MAX_PATH];
                DWORD n;

                buf[0] = L'\0';
                /* SLGP_RAWPATH and then expand by hand -- see the comment in
                 * flwin32_shortcut_target for why both halves are needed. */
                if (SUCCEEDED(link->lpVtbl->GetPath(link, buf, MAX_PATH, NULL,
                                                    SLGP_RAWPATH))) {
                    n = ExpandEnvironmentStringsW(buf, expanded, MAX_PATH);
                    result = wide_copy_out((n > 0 && n <= MAX_PATH) ? expanded : buf,
                                           target, target_size);
                }

                buf[0] = L'\0';
                if (SUCCEEDED(link->lpVtbl->GetArguments(link, buf, MAX_PATH))
                    && buf[0] != L'\0') {
                    n = ExpandEnvironmentStringsW(buf, expanded, MAX_PATH);
                    wide_copy_out((n > 0 && n <= MAX_PATH) ? expanded : buf,
                                  arguments, arguments_size);
                }

                buf[0] = L'\0';
                if (SUCCEEDED(link->lpVtbl->GetWorkingDirectory(link, buf, MAX_PATH))
                    && buf[0] != L'\0') {
                    n = ExpandEnvironmentStringsW(buf, expanded, MAX_PATH);
                    wide_copy_out((n > 0 && n <= MAX_PATH) ? expanded : buf,
                                  workdir, workdir_size);
                }
            }
            file->lpVtbl->Release(file);
        }
        link->lpVtbl->Release(link);
    }
    free(wpath);
    return result;
}

int32_t flwin32_shortcut_icon(const char* shortcut_path,
                              char* out,
                              int32_t out_size,
                              int32_t* index) {
    if (shortcut_path == NULL) return 0;
    ensure_com();
    if (index != NULL) *index = 0;

    wchar_t* wpath = utf8_to_wide(shortcut_path);
    if (wpath == NULL) return 0;

    IShellLinkW* link = NULL;
    int32_t result = 0;
    if (SUCCEEDED(CoCreateInstance(&CLSID_ShellLink, NULL, CLSCTX_INPROC_SERVER,
                                   &IID_IShellLinkW, (void**)&link))) {
        IPersistFile* file = NULL;
        if (SUCCEEDED(link->lpVtbl->QueryInterface(link, &IID_IPersistFile,
                                                   (void**)&file))) {
            if (SUCCEEDED(file->lpVtbl->Load(file, wpath, STGM_READ))) {
                wchar_t icon[MAX_PATH];
                int icon_index = 0;
                icon[0] = L'\0';
                if (SUCCEEDED(link->lpVtbl->GetIconLocation(link, icon, MAX_PATH,
                                                            &icon_index)) &&
                    icon[0] != L'\0') {
                    /* Same expansion as the target: these are stored raw too,
                     * and "%SystemRoot%\\system32\\imageres.dll" opens as
                     * nothing at all. */
                    wchar_t expanded[MAX_PATH];
                    DWORD n = ExpandEnvironmentStringsW(icon, expanded, MAX_PATH);
                    result = wide_copy_out(
                        (n > 0 && n <= MAX_PATH) ? expanded : icon, out, out_size);
                    if (index != NULL) *index = (int32_t)icon_index;
                }
            }
            file->lpVtbl->Release(file);
        }
        link->lpVtbl->Release(link);
    }
    free(wpath);
    return result;
}

int32_t flwin32_known_folder(int32_t which, char* out, int32_t out_size) {
    /* 0 = the machine-wide Start Menu programs, 1 = this user's. Two folders,
     * not one: an app installed for all users lands in the first and one
     * installed for the current user in the second, and a dock that reads
     * only ProgramData silently misses everything installed per-user --
     * which on a modern Windows is most things. */
    const KNOWNFOLDERID* id =
        (which == 1) ? &FOLDERID_Programs : &FOLDERID_CommonPrograms;
    PWSTR path = NULL;
    if (FAILED(SHGetKnownFolderPath(id, 0, NULL, &path))) return 0;
    int32_t n = wide_copy_out(path, out, out_size);
    CoTaskMemFree(path);
    return n;
}

int32_t flwin32_launch(const char* path, const char* arguments,
                       const char* directory) {
    if (path == NULL) return 0;
    ensure_com();
    wchar_t* wpath = utf8_to_wide(path);
    wchar_t* wargs = utf8_to_wide(arguments);
    wchar_t* wdir = utf8_to_wide(directory);
    if (wpath == NULL) {
        free(wargs);
        free(wdir);
        return 0;
    }
    /* ShellExecuteW, not CreateProcess: what arrives here can be a URL or a
     * document as well as a program, and only the shell knows how to start
     * those. SW_SHOWNORMAL so a launched app does not inherit the shell's own
     * window state.
     *
     * Callers should hand this the shortcut's TARGET rather than the .lnk
     * wherever they have one. Measured on this machine, opening a .lnk costs
     * 484ms the first time in a process and 73ms after; opening the exe it
     * points at costs 8ms, cold or warm. The difference is the shell's link
     * resolution machinery, and it is charged to whatever thread asks.
     *
     * The return is a legacy HINSTANCE-shaped error code: anything <= 32 is a
     * failure. */
    flwin32_trace("launch: ShellExecuteW begin");
    HINSTANCE rc = ShellExecuteW(NULL, L"open", wpath, wargs, wdir, SW_SHOWNORMAL);
    flwin32_trace("launch: ShellExecuteW end");
    free(wpath);
    free(wargs);
    free(wdir);
    return ((INT_PTR)rc > 32) ? 1 : 0;
}
