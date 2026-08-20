// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/*
 * flwin32_staticverbs.c -- the verbs that cost nothing to find.
 *
 * A context menu has two kinds of entry, and --menu-handlers showed they are
 * nothing alike in price:
 *
 *  - COM HANDLERS. An IContextMenu implementation per entry, instantiated and
 *    asked. Defender's costs 40ms on a folder, shell32's Library Location
 *    19ms, and they are two thirds of QueryContextMenu.
 *  - STATIC VERBS. A registry key with a command line under it --
 *    `HKCR\<class>\shell\<verb>\command`. "Open Git Bash here" is one, and so
 *    are Open, Edit and Print. Nothing is instantiated to find them.
 *
 * The whole menu waits for the first kind. This reads the second kind on its
 * own so a caller can draw them immediately, and is here to establish what
 * that is worth: how many verbs it actually yields for a real file, and how
 * long the reading takes.
 *
 * WHAT IS SKIPPED, and why each would be a lie on screen:
 *  - LegacyDisable / ProgrammaticAccessOnly: the registry saying "do not show
 *    this to a person".
 *  - Extended: shift-only. Windows hides these; showing them always would be
 *    a menu that disagrees with every other one on the machine.
 *  - A verb with no `command` subkey and no DelegateExecute: nothing to run.
 *
 * MUIVerb resolution is the one cost in here. A modern verb's label is an
 * indirect string ("@%SystemRoot%\\system32\\shell32.dll,-8506") that has to be
 * loaded out of a binary; SHLoadIndirectString does it, and it is why this is
 * measured rather than assumed to be free.
 *
 * Plain ASCII throughout, same reason as the neighbouring files.
 */

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <windows.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <wchar.h>

#include "include/FlutterWin32Bridge.h"

#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "shell32.lib")

static void sv_wide_to_utf8(const wchar_t* w, char* out, int out_size) {
    if (out == NULL || out_size <= 0) return;
    out[0] = 0;
    if (w == NULL) return;
    WideCharToMultiByte(CP_UTF8, 0, w, -1, out, out_size, NULL, NULL);
    out[out_size - 1] = 0;
}

static int sv_has_value(HKEY key, const wchar_t* name) {
    return RegQueryValueExW(key, name, NULL, NULL, NULL, NULL) == ERROR_SUCCESS;
}

static int sv_has_subkey(HKEY key, const wchar_t* name) {
    HKEY sub;
    if (RegOpenKeyExW(key, name, 0, KEY_READ, &sub) != ERROR_SUCCESS) return 0;
    RegCloseKey(sub);
    return 1;
}

/* An "@binary,-id" indirect string, turned into words.
 *
 * Applies to the default value as much as to MUIVerb, which is what the first
 * cut got wrong: Visual Studio stores its indirect string in the DEFAULT
 * value, so the menu showed
 * "@C:\Program Files (x86)\...\VSLauncherUI.dll,-1002" verbatim.
 *
 * SHLoadIndirectString declines that one, so there is a hand-rolled path
 * behind it: split at the last comma, expand the environment strings, open
 * the binary as data and LoadString the negated id. */
static int sv_resolve(wchar_t* text, char* out, int out_size) {
    if (text[0] != L'@') return 0;
    wchar_t resolved[260];
    if (SUCCEEDED(SHLoadIndirectString(text, resolved, 260, NULL))
            && resolved[0] != 0 && resolved[0] != L'@') {
        sv_wide_to_utf8(resolved, out, out_size);
        return 1;
    }
    wchar_t* comma = wcsrchr(text, L',');
    if (comma == NULL) return 0;
    *comma = 0;
    int id = _wtoi(comma + 1);
    if (id < 0) id = -id;
    wchar_t expanded[MAX_PATH];
    ExpandEnvironmentStringsW(text + 1, expanded, MAX_PATH);
    HMODULE module = LoadLibraryExW(expanded, NULL, LOAD_LIBRARY_AS_DATAFILE);
    int done = 0;
    if (module != NULL) {
        wchar_t loaded[260];
        int n = LoadStringW(module, (UINT)id, loaded, 260);
        FreeLibrary(module);
        if (n > 0) {
            sv_wide_to_utf8(loaded, out, out_size);
            done = 1;
        }
    }
    *comma = L',';
    return done;
}

/* The label a person should see: the default value, or MUIVerb, either of
 * which may be an indirect string -- and the key name when there is neither.
 *
 * THAT LAST CASE IS THE INTERESTING ONE. `open` and `runas` carry no label at
 * all: the shell knows them as "Open" and "Run as administrator" from its own
 * string table, and a caller reading the registry directly gets the bare verb.
 * Which is the limit of what this tier can draw on its own. */
static void sv_label(HKEY verb, const wchar_t* name, char* out, int out_size) {
    wchar_t text[260];
    DWORD size = sizeof(text);
    if (RegGetValueW(verb, NULL, NULL, RRF_RT_REG_SZ, NULL, text, &size)
            == ERROR_SUCCESS && text[0] != 0) {
        if (sv_resolve(text, out, out_size)) return;
        sv_wide_to_utf8(text, out, out_size);
        return;
    }
    size = sizeof(text);
    if (RegGetValueW(verb, NULL, L"MUIVerb", RRF_RT_REG_SZ, NULL, text, &size)
            == ERROR_SUCCESS && text[0] != 0) {
        if (sv_resolve(text, out, out_size)) return;
        sv_wide_to_utf8(text, out, out_size);
        return;
    }
    sv_wide_to_utf8(name, out, out_size);
}

static int sv_read_class(const wchar_t* cls, FlWin32StaticVerb* out,
                         int count, int max) {
    wchar_t key[200];
    swprintf(key, 200, L"%s\\shell", cls);
    HKEY hkey;
    if (RegOpenKeyExW(HKEY_CLASSES_ROOT, key, 0, KEY_READ, &hkey)
            != ERROR_SUCCESS) {
        return count;
    }
    for (DWORD i = 0; count < max; i++) {
        wchar_t name[128];
        DWORD name_len = 128;
        if (RegEnumKeyExW(hkey, i, name, &name_len, NULL, NULL, NULL, NULL)
                != ERROR_SUCCESS) {
            break;
        }
        HKEY verb;
        if (RegOpenKeyExW(hkey, name, 0, KEY_READ, &verb) != ERROR_SUCCESS) {
            continue;
        }
        int skip = sv_has_value(verb, L"LegacyDisable")
                || sv_has_value(verb, L"ProgrammaticAccessOnly")
                || sv_has_value(verb, L"Extended");
        int runnable = sv_has_subkey(verb, L"command")
                    || sv_has_value(verb, L"DelegateExecute");
        if (!skip && runnable) {
            FlWin32StaticVerb* v = &out[count];
            memset(v, 0, sizeof(*v));
            sv_wide_to_utf8(name, v->verb, (int)sizeof(v->verb));
            sv_label(verb, name, v->label, (int)sizeof(v->label));
            sv_wide_to_utf8(cls, v->source, (int)sizeof(v->source));
            count++;
        }
        RegCloseKey(verb);
    }
    RegCloseKey(hkey);
    return count;
}

int32_t flwin32_static_verbs(const char* path, FlWin32StaticVerb* out,
                             int32_t max) {
    if (path == NULL || out == NULL || max <= 0) return 0;

    int wlen = MultiByteToWideChar(CP_UTF8, 0, path, -1, NULL, 0);
    wchar_t* wpath = (wchar_t*)calloc((size_t)(wlen > 0 ? wlen : 1), sizeof(wchar_t));
    if (wpath == NULL) return 0;
    MultiByteToWideChar(CP_UTF8, 0, path, -1, wpath, wlen);

    DWORD attrs = GetFileAttributesW(wpath);
    int is_directory = (attrs != INVALID_FILE_ATTRIBUTES)
                    && (attrs & FILE_ATTRIBUTE_DIRECTORY);
    int count = 0;

    /* The ProgID first: an application's own verbs are the ones a person is
     * most likely to want, and they should be at the top when they are all
     * that is on screen yet. */
    if (!is_directory) {
        const wchar_t* dot = wcsrchr(wpath, L'.');
        if (dot != NULL) {
            wchar_t progid[80];
            DWORD size = sizeof(progid);
            if (RegGetValueW(HKEY_CLASSES_ROOT, dot, NULL, RRF_RT_REG_SZ, NULL,
                             progid, &size) == ERROR_SUCCESS && progid[0] != 0) {
                count = sv_read_class(progid, out, count, max);
            }
            count = sv_read_class(dot, out, count, max);
        }
        count = sv_read_class(L"*", out, count, max);
    } else {
        count = sv_read_class(L"Directory", out, count, max);
        count = sv_read_class(L"Folder", out, count, max);
    }
    count = sv_read_class(L"AllFilesystemObjects", out, count, max);

    free(wpath);
    return (int32_t)count;
}
