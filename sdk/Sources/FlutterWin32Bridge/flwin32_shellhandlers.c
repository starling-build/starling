// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/*
 * flwin32_shellhandlers.c -- which context-menu handler is costing the time.
 *
 * flwin32_shellmenu.c times the assembly in stages and says QueryContextMenu
 * is 84-99% of it. That names the CALL, not the cost: QueryContextMenu is a
 * loop over every shell extension registered for the item, and "the shell is
 * slow" is not a finding anyone can act on. There is no API that reports a
 * per-handler breakdown, and shell32 is not ours to instrument.
 *
 * So this does what the shell does, by hand, one handler at a time and with a
 * clock around each: read the registered handlers out of the registry,
 * CoCreateInstance each CLSID, IShellExtInit::Initialize it with the same
 * folder and data object the shell would, ask it to QueryContextMenu into a
 * scratch menu, count what it added, and release it.
 *
 * READ-ONLY, and diagnostic only. It registers nothing, changes nothing, and
 * is reached only from --menu-handlers. The handlers it instantiates are the
 * same objects the real menu instantiates a moment later; running them twice
 * costs a little time and nothing else.
 *
 * THE `items` COLUMN IS WEAKER THAN THE TIMINGS, and should be read as "what
 * this handler offered under our initialization". The shell also passes a
 * ProgID key and, in Explorer, a site; a handler that wants either may add
 * nothing here and a row in the real menu -- Defender's does exactly that. The
 * clock is the trustworthy column.
 *
 * WHAT IT CANNOT SEE, stated so the totals are read correctly: the static
 * verbs (the ones in the registry as `shell\<verb>\command`, which is where
 * Open, Edit, Print and "Open with Visual Studio" come from) are the shell's
 * own work inside CDefFolderMenu, not a handler, so they are not in this
 * table. The gap between the sum here and the monolithic QueryContextMenu
 * figure is that work plus the shell's own bookkeeping.
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

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "uuid.lib")

static double hc_now_ms(void) {
    LARGE_INTEGER f, c;
    QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&c);
    return (double)c.QuadPart * 1000.0 / (double)f.QuadPart;
}

static void hc_wide_to_utf8(const wchar_t* w, char* out, int out_size) {
    if (out == NULL || out_size <= 0) return;
    out[0] = 0;
    if (w == NULL) return;
    WideCharToMultiByte(CP_UTF8, 0, w, -1, out, out_size, NULL, NULL);
    out[out_size - 1] = 0;
}

/* The DLL behind a CLSID, for naming the culprit in the output. A handler
 * called "FileSyncEx" means nothing; FileSyncShell64.dll is OneDrive. */
static void hc_server_of(const wchar_t* clsid, char* out, int out_size) {
    out[0] = 0;
    wchar_t key[160];
    swprintf(key, 160, L"CLSID\\%s\\InprocServer32", clsid);
    wchar_t value[MAX_PATH];
    DWORD size = sizeof(value);
    if (RegGetValueW(HKEY_CLASSES_ROOT, key, NULL, RRF_RT_REG_SZ, NULL,
                     value, &size) != ERROR_SUCCESS) {
        return;
    }
    const wchar_t* leaf = wcsrchr(value, L'\\');
    hc_wide_to_utf8(leaf != NULL ? leaf + 1 : value, out, out_size);
}

/* One handler, timed. */
static int hc_measure(const wchar_t* subkey, const wchar_t* clsid_text,
                      IShellFolder* parent, LPCITEMIDLIST child,
                      LPCITEMIDLIST folder_pidl, LPCITEMIDLIST item_pidl,
                      HWND owner, FlWin32HandlerCost* out) {
    memset(out, 0, sizeof(*out));
    hc_wide_to_utf8(subkey, out->key, (int)sizeof(out->key));
    hc_wide_to_utf8(clsid_text, out->clsid, (int)sizeof(out->clsid));
    hc_server_of(clsid_text, out->dll, (int)sizeof(out->dll));

    CLSID clsid;
    if (FAILED(CLSIDFromString(clsid_text, &clsid))) return 0;

    /* The same data object the shell hands a handler: the selection, as an
     * IDataObject over (parent folder, child pidl). A handler that cannot get
     * one usually does nothing at all -- which is itself worth seeing. */
    IDataObject* data = NULL;
    if (parent != NULL && child != NULL) {
        SHCreateDataObject(item_pidl, 1, &child, NULL, &IID_IDataObject,
                           (void**)&data);
    }

    double t0 = hc_now_ms();
    IShellExtInit* init = NULL;
    HRESULT hr = CoCreateInstance(&clsid, NULL, CLSCTX_INPROC_SERVER,
                                  &IID_IShellExtInit, (void**)&init);
    out->create_ms = hc_now_ms() - t0;
    if (FAILED(hr) || init == NULL) {
        if (data != NULL) data->lpVtbl->Release(data);
        out->failed = 1;
        return 1;
    }

    double t1 = hc_now_ms();
    hr = init->lpVtbl->Initialize(init, folder_pidl, data, NULL);
    out->init_ms = hc_now_ms() - t1;

    IContextMenu* cm = NULL;
    if (SUCCEEDED(init->lpVtbl->QueryInterface(init, &IID_IContextMenu,
                                               (void**)&cm)) && cm != NULL) {
        HMENU menu = CreatePopupMenu();
        double t2 = hc_now_ms();
        HRESULT qr = cm->lpVtbl->QueryContextMenu(cm, menu, 0, 1, 0x7000,
                                                  CMF_NORMAL | CMF_EXPLORE);
        out->query_ms = hc_now_ms() - t2;
        out->items = SUCCEEDED(qr) ? GetMenuItemCount(menu) : 0;
        DestroyMenu(menu);
        cm->lpVtbl->Release(cm);
    } else {
        out->failed = 1;
    }

    init->lpVtbl->Release(init);
    if (data != NULL) data->lpVtbl->Release(data);
    (void)owner;
    return 1;
}

/* Every class whose handlers apply to this item, in the order the shell
 * consults them. `*` and AllFilesystemObjects apply to everything, which is
 * why the expensive ones tend to live there. */
static int hc_classes(const wchar_t* path, int is_directory,
                      wchar_t classes[8][80]) {
    int n = 0;
    wcscpy_s(classes[n++], 80, L"*");
    wcscpy_s(classes[n++], 80, L"AllFilesystemObjects");
    if (is_directory) {
        wcscpy_s(classes[n++], 80, L"Directory");
        wcscpy_s(classes[n++], 80, L"Folder");
    } else {
        const wchar_t* dot = wcsrchr(path, L'.');
        if (dot != NULL && wcslen(dot) < 60) {
            wcscpy_s(classes[n], 80, dot);
            n++;
            /* And the ProgID the extension points at, which is where a real
             * application's handlers are registered. */
            wchar_t progid[80];
            DWORD size = sizeof(progid);
            if (RegGetValueW(HKEY_CLASSES_ROOT, dot, NULL, RRF_RT_REG_SZ, NULL,
                             progid, &size) == ERROR_SUCCESS && progid[0] != 0) {
                wcscpy_s(classes[n++], 80, progid);
            }
        }
    }
    return n;
}

int32_t flwin32_shellmenu_handler_costs(const char* path,
                                        FlWin32HandlerCost* out,
                                        int32_t max) {
    if (path == NULL || out == NULL || max <= 0) return 0;

    HRESULT co = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);

    int wlen = MultiByteToWideChar(CP_UTF8, 0, path, -1, NULL, 0);
    wchar_t* wpath = (wchar_t*)calloc((size_t)(wlen > 0 ? wlen : 1), sizeof(wchar_t));
    if (wpath == NULL) return 0;
    MultiByteToWideChar(CP_UTF8, 0, path, -1, wpath, wlen);

    DWORD attrs = GetFileAttributesW(wpath);
    int is_directory = (attrs != INVALID_FILE_ATTRIBUTES)
                    && (attrs & FILE_ATTRIBUTE_DIRECTORY);

    /* The same binding the real menu uses: the item as a child of its folder. */
    LPITEMIDLIST pidl = NULL;
    IShellFolder* parent = NULL;
    LPCITEMIDLIST child = NULL;
    LPITEMIDLIST folder_pidl = NULL;
    if (SUCCEEDED(SHParseDisplayName(wpath, NULL, &pidl, 0, NULL))) {
        SHBindToParent(pidl, &IID_IShellFolder, (void**)&parent, &child);
        /* IShellExtInit::Initialize's first argument is the FOLDER the items
         * are in, not the item -- handing it the item's own pidl is a subtle
         * lie that most handlers ignore and some do not. Defender's took 38ms
         * and contributed nothing under it, while the real menu shows its
         * "Scan with Microsoft Defender" for the same folder. */
        folder_pidl = ILClone(pidl);
        if (folder_pidl != NULL) ILRemoveLastID(folder_pidl);
    }

    wchar_t classes[8][80];
    int class_count = hc_classes(wpath, is_directory, classes);
    int count = 0;

    for (int c = 0; c < class_count && count < max; c++) {
        wchar_t key[200];
        swprintf(key, 200, L"%s\\shellex\\ContextMenuHandlers", classes[c]);
        HKEY hkey;
        if (RegOpenKeyExW(HKEY_CLASSES_ROOT, key, 0, KEY_READ, &hkey)
                != ERROR_SUCCESS) {
            continue;
        }
        for (DWORD i = 0; count < max; i++) {
            wchar_t name[128];
            DWORD name_len = 128;
            if (RegEnumKeyExW(hkey, i, name, &name_len, NULL, NULL, NULL, NULL)
                    != ERROR_SUCCESS) {
                break;
            }
            /* The CLSID is the subkey's default value -- or the subkey name
             * itself, when the name IS a CLSID. */
            wchar_t clsid[80];
            DWORD size = sizeof(clsid);
            if (RegGetValueW(hkey, name, NULL, RRF_RT_REG_SZ, NULL, clsid, &size)
                    != ERROR_SUCCESS || clsid[0] != L'{') {
                if (name[0] != L'{') continue;
                wcscpy_s(clsid, 80, name);
            }
            wchar_t labelled[160];
            swprintf(labelled, 160, L"%s\\%s", classes[c], name);
            if (hc_measure(labelled, clsid, parent, child, folder_pidl, pidl,
                           NULL, &out[count])) {
                count++;
            }
        }
        RegCloseKey(hkey);
    }

    if (parent != NULL) parent->lpVtbl->Release(parent);
    if (folder_pidl != NULL) CoTaskMemFree(folder_pidl);
    if (pidl != NULL) CoTaskMemFree(pidl);
    free(wpath);
    if (SUCCEEDED(co)) CoUninitialize();
    return (int32_t)count;
}
