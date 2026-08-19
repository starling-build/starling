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
#include <stdlib.h>
#include <string.h>

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
