// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/*
 * flwin32_files.c -- the places a file explorer starts from, and what it
 * needs to know about a file that a directory read does not tell it.
 *
 * The listing itself is Foundation's, in Swift: FileManager enumerates a
 * directory perfectly well on Windows and there is nothing to gain from
 * reimplementing FindFirstFileW around it. What is NOT in Foundation is the
 * shell's view of the world, and that is what lives here:
 *
 *  - The KNOWN FOLDERS. "Downloads" is not %USERPROFILE%\Downloads on a
 *    machine where the user moved it, and the registry is not the API --
 *    SHGetKnownFolderPath is, and it is the only thing that follows a
 *    relocated folder.
 *  - The TYPE NAME. "PNG File", "Microsoft Word Document": the string
 *    Explorer shows in its Type column, which comes from the association
 *    database rather than the extension.
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
#include <shellapi.h>
#include <shlwapi.h>
#define SECURITY_WIN32
#include <security.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#include "include/FlutterWin32Bridge.h"

#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "secur32.lib")

static int32_t wide_out(const wchar_t* w, char* out, int32_t out_size) {
    if (w == NULL || out == NULL || out_size <= 0) return 0;
    int need = WideCharToMultiByte(CP_UTF8, 0, w, -1, NULL, 0, NULL, NULL);
    if (need <= 0 || need > out_size) return 0;
    WideCharToMultiByte(CP_UTF8, 0, w, -1, out, out_size, NULL, NULL);
    return need;
}

/* The places the sidebar offers, in the order it offers them. Kept as an
 * index rather than a GUID across the boundary so the Swift side does not
 * have to carry Windows' GUID table around. */
int32_t flwin32_known_path(int32_t which, char* out, int32_t out_size) {
    const KNOWNFOLDERID* id;
    switch (which) {
        case 0: id = &FOLDERID_Profile;   break;
        case 1: id = &FOLDERID_Desktop;   break;
        case 2: id = &FOLDERID_Documents; break;
        case 3: id = &FOLDERID_Downloads; break;
        case 4: id = &FOLDERID_Pictures;  break;
        case 5: id = &FOLDERID_Music;     break;
        case 6: id = &FOLDERID_Videos;    break;
        /* The Recent folder: a directory of .lnk files Windows writes every
         * time a document is opened, which is where Start's "Recommended"
         * gets its list. Reading it needs no hook and no telemetry — it is
         * the shell's own record, on disk, for this user. */
        case 7: id = &FOLDERID_Recent;    break;
        default: return 0;
    }
    PWSTR path = NULL;
    if (FAILED(SHGetKnownFolderPath(id, 0, NULL, &path))) return 0;
    int32_t n = wide_out(path, out, out_size);
    CoTaskMemFree(path);
    return n;
}

/* What Explorer's Type column says. Falls back to nothing rather than
 * inventing "FOO File" -- the caller can do that itself and knows whether it
 * wants to. */
/* A date-time the way WINDOWS formats it -- GetDateFormatEx/GetTimeFormatEx
 * with the user's own locale settings, which is what Explorer's Date
 * modified column shows. Foundation's formatter answers from its own locale
 * data and disagrees with the machine ("17/08/2026, 5:59 PM" against
 * Explorer's "8/17/2026 5:59 PM" on this very box), and a column that
 * formats dates differently from the Explorer beside it looks broken even
 * when both are defensible. Takes Unix seconds. */
int32_t flwin32_format_datetime(int64_t unix_seconds, char* out,
                                int32_t out_size) {
    if (out == NULL || out_size <= 0) return 0;
    /* Unix epoch in FILETIME ticks: 1601 to 1970 is 11644473600 seconds. */
    long long ticks = (unix_seconds + 11644473600LL) * 10000000LL;
    FILETIME ft;
    ft.dwLowDateTime = (DWORD)(ticks & 0xFFFFFFFF);
    ft.dwHighDateTime = (DWORD)(ticks >> 32);
    FILETIME local;
    if (!FileTimeToLocalFileTime(&ft, &local)) return 0;
    SYSTEMTIME st;
    if (!FileTimeToSystemTime(&local, &st)) return 0;

    wchar_t date[80];
    wchar_t time[80];
    if (GetDateFormatEx(LOCALE_NAME_USER_DEFAULT, DATE_SHORTDATE, &st, NULL,
                        date, 80, NULL) == 0) {
        return 0;
    }
    if (GetTimeFormatEx(LOCALE_NAME_USER_DEFAULT, TIME_NOSECONDS, &st, NULL,
                        time, 80) == 0) {
        return 0;
    }
    wchar_t joined[170];
    wcscpy_s(joined, 170, date);
    wcscat_s(joined, 170, L" ");
    wcscat_s(joined, 170, time);
    return wide_out(joined, out, out_size);
}

/* The shell's DISPLAY name for a path: "Local Disk (C:)" for a drive root,
 * the localized "Documents" for a known folder -- the strings Explorer's
 * sidebar and breadcrumb show, which are not the file system's names. */
int32_t flwin32_file_display_name(const char* path, char* out,
                                  int32_t out_size) {
    if (path == NULL) return 0;
    int n = MultiByteToWideChar(CP_UTF8, 0, path, -1, NULL, 0);
    if (n <= 0) return 0;
    wchar_t* wide = (wchar_t*)calloc((size_t)n, sizeof(wchar_t));
    if (wide == NULL) return 0;
    MultiByteToWideChar(CP_UTF8, 0, path, -1, wide, n);

    SHFILEINFOW info;
    ZeroMemory(&info, sizeof(info));
    DWORD_PTR ok = SHGetFileInfoW(wide, 0, &info, sizeof(info),
                                  SHGFI_DISPLAYNAME);
    free(wide);
    if (!ok) return 0;
    return wide_out(info.szDisplayName, out, out_size);
}

int32_t flwin32_file_type_name(const char* path, char* out, int32_t out_size) {
    if (path == NULL) return 0;
    int n = MultiByteToWideChar(CP_UTF8, 0, path, -1, NULL, 0);
    if (n <= 0) return 0;
    wchar_t* wide = (wchar_t*)calloc((size_t)n, sizeof(wchar_t));
    if (wide == NULL) return 0;
    MultiByteToWideChar(CP_UTF8, 0, path, -1, wide, n);

    SHFILEINFOW info;
    ZeroMemory(&info, sizeof(info));
    /* USEFILEATTRIBUTES so this answers for an extension without touching the
     * disk -- a listing asks once per TYPE, not once per file, and half of
     * those files may be on a sleeping drive. */
    DWORD_PTR ok = SHGetFileInfoW(wide, FILE_ATTRIBUTE_NORMAL, &info,
                                  sizeof(info),
                                  SHGFI_TYPENAME | SHGFI_USEFILEATTRIBUTES);
    free(wide);
    if (!ok) return 0;
    return wide_out(info.szTypeName, out, out_size);
}

/* Explorer's own window on a folder, for "Open in Windows Explorer". Ours is
 * not going to grow a right-click menu with forty verbs on it, and there is
 * no shame in handing the user back to the tool that has one. */
int32_t flwin32_open_in_explorer(const char* path) {
    if (path == NULL) return 0;
    int n = MultiByteToWideChar(CP_UTF8, 0, path, -1, NULL, 0);
    if (n <= 0) return 0;
    wchar_t* wide = (wchar_t*)calloc((size_t)n, sizeof(wchar_t));
    if (wide == NULL) return 0;
    MultiByteToWideChar(CP_UTF8, 0, path, -1, wide, n);
    HINSTANCE rc = ShellExecuteW(NULL, L"explore", wide, NULL, NULL, SW_SHOWNORMAL);
    free(wide);
    return ((INT_PTR)rc > 32) ? 1 : 0;
}

/* ----------------------------------------------------- file associations */

/*
 * What opens a file, and letting the user change it.
 *
 * The limit worth knowing before reading further: on Windows 8 and later an
 * application CANNOT set the default handler for a file type. The choice
 * lives in HKCU\...\FileExts\<ext>\UserChoice, and that key is protected by
 * a hash over the extension, the user's SID and a timestamp -- writing it
 * without the hash is ignored, and computing the hash means reimplementing an
 * undocumented algorithm that Microsoft changes. Every "set default browser"
 * tool that still works does it by asking the USER through the shell's own
 * UI.
 *
 * So this offers the two things that ARE supported: read what the default is,
 * and put up the shell's own "Open with" dialog, which is where the user can
 * make something the default with a checkbox. The same line the audio
 * default-device switcher is on: Windows does not offer it, so we do not fake
 * it.
 */

/* The friendly name of whatever currently opens this file -- "Notepad",
 * "Microsoft Edge". Empty when nothing is associated, which is a real answer
 * and the caller says so. */
int32_t flwin32_default_app_name(const char* path, char* out, int32_t out_size) {
    if (path == NULL) return 0;
    int n = MultiByteToWideChar(CP_UTF8, 0, path, -1, NULL, 0);
    if (n <= 0) return 0;
    wchar_t* wide = (wchar_t*)calloc((size_t)n, sizeof(wchar_t));
    if (wide == NULL) return 0;
    MultiByteToWideChar(CP_UTF8, 0, path, -1, wide, n);

    const wchar_t* dot = wcsrchr(wide, L'.');
    int32_t written = 0;
    if (dot != NULL && dot[1] != L'\0') {
        wchar_t name[512];
        DWORD size = 512;
        /* ASSOCSTR_FRIENDLYAPPNAME resolves through the UserChoice the user
         * actually made, which is the point -- ASSOCSTR_EXECUTABLE gives a
         * path, and on a Store app that path is a stub nobody recognises. */
        if (AssocQueryStringW(ASSOCF_NONE, ASSOCSTR_FRIENDLYAPPNAME, dot, NULL,
                              name, &size) == S_OK) {
            written = wide_out(name, out, out_size);
        }
    }
    free(wide);
    return written;
}

/* The shell's own "How do you want to open this file?" dialog.
 *
 * SHOpenWithDialog rather than ShellExecuteEx with the "openas" verb: the
 * verb form opens the same dialog but goes through association lookup first
 * and does nothing at all for a file type that has no handler -- which is
 * precisely when the user needs the dialog.
 *
 * BLOCKS until the user answers. Background thread only. */
int32_t flwin32_open_with_dialog(const char* path) {
    if (path == NULL) return 0;
    int n = MultiByteToWideChar(CP_UTF8, 0, path, -1, NULL, 0);
    if (n <= 0) return 0;
    wchar_t* wide = (wchar_t*)calloc((size_t)n, sizeof(wchar_t));
    if (wide == NULL) return 0;
    MultiByteToWideChar(CP_UTF8, 0, path, -1, wide, n);

    OPENASINFO info;
    ZeroMemory(&info, sizeof(info));
    info.pcszFile = wide;
    info.pcszClass = NULL;
    /* EXEC so the file opens once chosen, and ALLOW_REGISTRATION so the
     * dialog offers "Always use this app" -- which is the ONLY supported way
     * for the default to change, and the whole reason this dialog is here. */
    info.oaifInFlags = OAIF_EXEC | OAIF_ALLOW_REGISTRATION;

    HRESULT hr = SHOpenWithDialog(NULL, &info);
    free(wide);
    /* Cancelled is not a failure: the user answered, and the answer was no. */
    return (hr == S_OK || hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) ? 1 : 0;
}

/* -------------------------------------------------------------- the user */

/* The display name -- "Ada Lovelace" -- falling back to the account name.
 *
 * GetUserNameExW(NameDisplay) is the one that knows the friendly name, and it
 * FAILS on a machine that is not domain-joined and has a local account with
 * no display name set, which is most home machines. The fallback is not an
 * error path, it is the common one. */
int32_t flwin32_user_display_name(char* out, int32_t out_size) {
    wchar_t name[256];
    ULONG size = 256;
    if (GetUserNameExW(NameDisplay, name, &size) && name[0] != L'\0') {
        return wide_out(name, out, out_size);
    }
    DWORD basic = 256;
    if (GetUserNameW(name, &basic)) return wide_out(name, out, out_size);
    return 0;
}

/* --------------------------------------------------------------- ShellNew */

/* Appends UTF-8 to out at *used, NUL-terminating; 0 if it will not fit. */
static int sn_append(char* out, int32_t out_size, int32_t* used,
                     const char* s) {
    int len = (int)strlen(s);
    if (*used + len + 1 > out_size) return 0;
    memcpy(out + *used, s, (size_t)len);
    *used += len;
    out[*used] = 0;
    return 1;
}

static int sn_append_wide(char* out, int32_t out_size, int32_t* used,
                          const wchar_t* w) {
    char buf[1024];
    if (wide_out(w, buf, (int32_t)sizeof(buf)) == 0) return 0;
    return sn_append(out, out_size, used, buf);
}

/* Whether `key` holds a usable ShellNew recipe, and which. Command entries
 * are wizards that launch a program rather than describe a file, and
 * Handler entries (.lnk, .library-ms) delegate creation to a COM object --
 * an empty file where either was expected is broken, so both are skipped.
 * kind: 1 = NullFile, 2 = FileName (template copied), 3 = Data (bytes). */
static int sn_recipe(HKEY key, int* kind, wchar_t* file, DWORD file_chars,
                     BYTE* data, DWORD* data_size) {
    if (RegQueryValueExW(key, L"Command", NULL, NULL, NULL, NULL)
            == ERROR_SUCCESS
        || RegQueryValueExW(key, L"Handler", NULL, NULL, NULL, NULL)
            == ERROR_SUCCESS) {
        return 0;
    }
    if (RegQueryValueExW(key, L"NullFile", NULL, NULL, NULL, NULL)
            == ERROR_SUCCESS) {
        *kind = 1;
        return 1;
    }
    DWORD bytes = file_chars * sizeof(wchar_t);
    if (RegGetValueW(key, NULL, L"FileName", RRF_RT_REG_SZ, NULL, file,
                     &bytes) == ERROR_SUCCESS && file[0] != L'\0') {
        *kind = 2;
        return 1;
    }
    if (RegGetValueW(key, NULL, L"Data", RRF_RT_REG_BINARY, NULL, data,
                     data_size) == ERROR_SUCCESS && *data_size > 0) {
        *kind = 3;
        return 1;
    }
    return 0;
}

/* Resolves a ShellNew FileName to the template on disk: an absolute path is
 * itself; a bare name is looked for in the user's Templates folder and then
 * the system's ShellNew directory, which is where Windows keeps its own. */
static int sn_template_path(const wchar_t* name, wchar_t* out,
                            DWORD out_chars) {
    if (wcschr(name, L':') != NULL) {
        wcsncpy(out, name, out_chars - 1);
        out[out_chars - 1] = 0;
        return GetFileAttributesW(out) != INVALID_FILE_ATTRIBUTES;
    }
    PWSTR templates = NULL;
    if (SUCCEEDED(SHGetKnownFolderPath(&FOLDERID_Templates, 0, NULL,
                                       &templates))) {
        _snwprintf(out, out_chars, L"%s\\%s", templates, name);
        CoTaskMemFree(templates);
        if (GetFileAttributesW(out) != INVALID_FILE_ATTRIBUTES) return 1;
    }
    wchar_t windir[MAX_PATH];
    if (GetWindowsDirectoryW(windir, MAX_PATH) > 0) {
        _snwprintf(out, out_chars, L"%s\\ShellNew\\%s", windir, name);
        if (GetFileAttributesW(out) != INVALID_FILE_ATTRIBUTES) return 1;
    }
    return 0;
}

/* The templates behind Explorer's New submenu, read the way Explorer reads
 * them: every extension key in HKCR whose ShellNew subkey (bare, or under
 * the extension's progid) describes a file this caller can create. Writes
 * one template per line:
 *
 *     ext<TAB>type name<TAB>kind<TAB>source
 *
 * kind "null" makes an empty file, "file" copies `source` (a resolved
 * template path), "data" writes `source` decoded from hex. Type names come
 * from the progid's default value, through SHLoadIndirectString when the
 * value is a @resource reference. Returns the bytes written. A registry
 * walk over all of HKCR -- call it off the UI thread and cache it. */
int32_t flwin32_shellnew_templates(char* out, int32_t out_size) {
    if (out == NULL || out_size <= 0) return 0;
    out[0] = 0;
    int32_t used = 0;
    for (DWORD i = 0;; i++) {
        wchar_t ext[260];
        DWORD ext_chars = 260;
        LSTATUS st = RegEnumKeyExW(HKEY_CLASSES_ROOT, i, ext, &ext_chars,
                                   NULL, NULL, NULL, NULL);
        if (st == ERROR_NO_MORE_ITEMS) break;
        if (st != ERROR_SUCCESS || ext[0] != L'.') continue;

        wchar_t progid[260] = L"";
        DWORD progid_bytes = sizeof(progid);
        RegGetValueW(HKEY_CLASSES_ROOT, ext, NULL, RRF_RT_REG_SZ, NULL,
                     progid, &progid_bytes);

        /* The recipe: `.ext\<progid>\ShellNew` wins over `.ext\ShellNew`,
         * because that is where an app that took over the extension put
         * its own. */
        wchar_t subkey[560];
        HKEY key = NULL;
        int kind = 0;
        wchar_t file[MAX_PATH] = L"";
        BYTE data[2048];
        DWORD data_size = sizeof(data);
        if (progid[0] != L'\0') {
            _snwprintf(subkey, 560, L"%s\\%s\\ShellNew", ext, progid);
            if (RegOpenKeyExW(HKEY_CLASSES_ROOT, subkey, 0, KEY_READ, &key)
                    != ERROR_SUCCESS) {
                key = NULL;
            }
        }
        if (key == NULL) {
            _snwprintf(subkey, 560, L"%s\\ShellNew", ext);
            if (RegOpenKeyExW(HKEY_CLASSES_ROOT, subkey, 0, KEY_READ, &key)
                    != ERROR_SUCCESS) {
                continue;
            }
        }
        int usable = sn_recipe(key, &kind, file, MAX_PATH, data, &data_size);
        RegCloseKey(key);
        if (!usable) continue;

        /* A FileName that resolves nowhere is an uninstalled app's
         * leftover; a row for it would create nothing. */
        wchar_t source[MAX_PATH] = L"";
        if (kind == 2 && !sn_template_path(file, source, MAX_PATH)) continue;

        /* The type's display name, from the progid. No progid or no name
         * means no honest label -- skip rather than show ".xyz file". */
        if (progid[0] == L'\0') continue;
        wchar_t name[260] = L"";
        DWORD name_bytes = sizeof(name);
        if (RegGetValueW(HKEY_CLASSES_ROOT, progid, NULL, RRF_RT_REG_SZ,
                         NULL, name, &name_bytes) != ERROR_SUCCESS
                || name[0] == L'\0') {
            continue;
        }
        if (name[0] == L'@') {
            wchar_t resolved[260];
            if (SUCCEEDED(SHLoadIndirectString(name, resolved, 260, NULL))) {
                wcsncpy(name, resolved, 259);
                name[259] = 0;
            } else {
                continue;
            }
        }

        int32_t mark = used;
        int ok = sn_append_wide(out, out_size, &used, ext)
              && sn_append(out, out_size, &used, "\t")
              && sn_append_wide(out, out_size, &used, name)
              && sn_append(out, out_size, &used, "\t");
        if (ok) {
            if (kind == 1) {
                ok = sn_append(out, out_size, &used, "null\t");
            } else if (kind == 2) {
                ok = sn_append(out, out_size, &used, "file\t")
                  && sn_append_wide(out, out_size, &used, source);
            } else {
                ok = sn_append(out, out_size, &used, "data\t");
                for (DWORD b = 0; ok && b < data_size; b++) {
                    char hex[3];
                    snprintf(hex, 3, "%02x", data[b]);
                    ok = sn_append(out, out_size, &used, hex);
                }
            }
        }
        ok = ok && sn_append(out, out_size, &used, "\n");
        if (!ok) {
            /* Did not fit: drop the half-written line, keep what did. */
            used = mark;
            out[used] = 0;
            break;
        }
    }
    return used;
}
