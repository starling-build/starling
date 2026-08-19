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
#include <stdlib.h>
#include <string.h>

#include "include/FlutterWin32Bridge.h"

#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "ole32.lib")

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
