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

/* One menu built over a CHOSEN SET OF CLASS KEYS, timed.
 *
 * This is the lever the CMF_ flags are not. SHCreateDefaultContextMenu takes
 * a DEFCONTEXTMENU whose aKeys array says which class keys the shell should
 * consult -- and since the cost is per-handler and handlers are registered
 * PER CLASS, restricting the classes restricts the cost. The expensive ones
 * measured (Defender, OneDrive, Sharing, WorkFolders) are all registered
 * under `*` and AllFilesystemObjects; an application's own verbs are under
 * its ProgID.
 *
 * So `mode` picks how much of the world to ask about:
 *
 *   0  the item's own ProgID and extension only -- the cheap classes
 *   1  everything the shell would normally consult
 *
 * The point of the comparison: mode 0 is still the SHELL building the menu.
 * Its labels are the shell's ("Open", "Run as administrator" -- the strings
 * that are not in the registry), its built-in verbs are there, and nothing is
 * reimplemented. If it is fast and its rows are useful, a two-tier menu costs
 * no duplication at all.
 */
double flwin32_shellmenu_time_keys(const char* path, int32_t mode,
                                   int32_t* items) {
    if (items != NULL) *items = 0;
    if (path == NULL) return -1.0;

    HRESULT co = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);

    int wlen = MultiByteToWideChar(CP_UTF8, 0, path, -1, NULL, 0);
    wchar_t* wpath = (wchar_t*)calloc((size_t)(wlen > 0 ? wlen : 1), sizeof(wchar_t));
    if (wpath == NULL) return -1.0;
    MultiByteToWideChar(CP_UTF8, 0, path, -1, wpath, wlen);

    DWORD attrs = GetFileAttributesW(wpath);
    int is_directory = (attrs != INVALID_FILE_ATTRIBUTES)
                    && (attrs & FILE_ATTRIBUTE_DIRECTORY);

    /* The classes, in the order the shell consults them. */
    wchar_t names[8][80];
    int n = 0;
    if (is_directory) {
        wcscpy_s(names[n++], 80, L"Directory");
        wcscpy_s(names[n++], 80, L"Folder");
    } else {
        const wchar_t* dot = wcsrchr(wpath, L'.');
        if (dot != NULL && wcslen(dot) < 60) {
            wchar_t progid[80];
            DWORD size = sizeof(progid);
            if (RegGetValueW(HKEY_CLASSES_ROOT, dot, NULL, RRF_RT_REG_SZ, NULL,
                             progid, &size) == ERROR_SUCCESS && progid[0] != 0) {
                wcscpy_s(names[n++], 80, progid);
            }
            wcscpy_s(names[n++], 80, dot);
        }
    }
    int cheap = n;                       /* everything above is cheap */
    wcscpy_s(names[n++], 80, L"AllFilesystemObjects");
    wcscpy_s(names[n++], 80, L"*");

    /* mode 2: NO class keys at all. The shell then contributes only its own
     * built-in verbs -- Open, Cut, Copy, Delete, Rename, Create shortcut,
     * Properties -- with its own localized strings, and consults no handler
     * at all. If that is fast, the "cheap tier" needs no hardcoded labels and
     * no registry reading: it is the shell, asked a smaller question. */
    int wanted = (mode == 2) ? 0 : ((mode == 0) ? cheap : n);
    HKEY keys[8];
    int key_count = 0;
    for (int i = 0; i < wanted; i++) {
        HKEY k;
        if (RegOpenKeyExW(HKEY_CLASSES_ROOT, names[i], 0, KEY_READ, &k)
                == ERROR_SUCCESS) {
            keys[key_count++] = k;
        }
    }

    LPITEMIDLIST pidl = NULL;
    IShellFolder* parent = NULL;
    LPCITEMIDLIST child = NULL;
    double elapsed = -1.0;

    if (SUCCEEDED(SHParseDisplayName(wpath, NULL, &pidl, 0, NULL))
            && SUCCEEDED(SHBindToParent(pidl, &IID_IShellFolder,
                                        (void**)&parent, &child))
            && parent != NULL) {
        DEFCONTEXTMENU dcm;
        ZeroMemory(&dcm, sizeof(dcm));
        dcm.hwnd = NULL;
        dcm.psf = parent;
        dcm.cidl = 1;
        dcm.apidl = &child;
        dcm.cKeys = (UINT)key_count;
        dcm.aKeys = keys;

        IContextMenu* cm = NULL;
        double t0 = hc_now_ms();
        if (SUCCEEDED(SHCreateDefaultContextMenu(&dcm, &IID_IContextMenu,
                                                 (void**)&cm)) && cm != NULL) {
            HMENU menu = CreatePopupMenu();
            HRESULT hr = cm->lpVtbl->QueryContextMenu(cm, menu, 0, 1, 0x7000,
                                                      CMF_NORMAL | CMF_EXPLORE);
            elapsed = hc_now_ms() - t0;
            if (items != NULL) *items = SUCCEEDED(hr) ? GetMenuItemCount(menu) : -1;
            DestroyMenu(menu);
            cm->lpVtbl->Release(cm);
        }
        parent->lpVtbl->Release(parent);
    }

    for (int i = 0; i < key_count; i++) RegCloseKey(keys[i]);
    if (pidl != NULL) CoTaskMemFree(pidl);
    free(wpath);
    if (SUCCEEDED(co)) CoUninitialize();
    return elapsed;
}

/* The ROWS a restricted key set produces, so the fast tier can be compared
 * with the full menu item by item.
 *
 * The property that decides whether a two-tier menu is safe: is the cheap set
 * a SUBSET of the full one? If it is, the second tier only ever ADDS rows and
 * nothing already on screen changes meaning. A tier assembled by hand from the
 * registry carried no such guarantee -- it produced `opennewtab`, which the
 * shell's own menu for the same folder does not contain.
 */
int32_t flwin32_shellmenu_keys_rows(const char* path, int32_t mode,
                                    FlWin32StaticVerb* out, int32_t max) {
    if (path == NULL || out == NULL || max <= 0) return 0;
    HRESULT co = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);

    int wlen = MultiByteToWideChar(CP_UTF8, 0, path, -1, NULL, 0);
    wchar_t* wpath = (wchar_t*)calloc((size_t)(wlen > 0 ? wlen : 1), sizeof(wchar_t));
    if (wpath == NULL) return 0;
    MultiByteToWideChar(CP_UTF8, 0, path, -1, wpath, wlen);

    DWORD attrs = GetFileAttributesW(wpath);
    int is_directory = (attrs != INVALID_FILE_ATTRIBUTES)
                    && (attrs & FILE_ATTRIBUTE_DIRECTORY);
    wchar_t names[8][80];
    int n = 0;
    if (is_directory) {
        wcscpy_s(names[n++], 80, L"Directory");
        wcscpy_s(names[n++], 80, L"Folder");
    } else {
        const wchar_t* dot = wcsrchr(wpath, L'.');
        if (dot != NULL && wcslen(dot) < 60) {
            wchar_t progid[80];
            DWORD size = sizeof(progid);
            if (RegGetValueW(HKEY_CLASSES_ROOT, dot, NULL, RRF_RT_REG_SZ, NULL,
                             progid, &size) == ERROR_SUCCESS && progid[0] != 0) {
                wcscpy_s(names[n++], 80, progid);
            }
            wcscpy_s(names[n++], 80, dot);
        }
    }
    int cheap = n;
    wcscpy_s(names[n++], 80, L"AllFilesystemObjects");
    wcscpy_s(names[n++], 80, L"*");
    int wanted = (mode == 0) ? cheap : n;

    HKEY keys[8];
    int key_count = 0;
    for (int i = 0; i < wanted; i++) {
        HKEY k;
        if (RegOpenKeyExW(HKEY_CLASSES_ROOT, names[i], 0, KEY_READ, &k)
                == ERROR_SUCCESS) {
            keys[key_count++] = k;
        }
    }

    LPITEMIDLIST pidl = NULL;
    IShellFolder* parent = NULL;
    LPCITEMIDLIST child = NULL;
    int count = 0;

    if (SUCCEEDED(SHParseDisplayName(wpath, NULL, &pidl, 0, NULL))
            && SUCCEEDED(SHBindToParent(pidl, &IID_IShellFolder,
                                        (void**)&parent, &child))
            && parent != NULL) {
        DEFCONTEXTMENU dcm;
        ZeroMemory(&dcm, sizeof(dcm));
        dcm.psf = parent;
        dcm.cidl = 1;
        dcm.apidl = &child;
        dcm.cKeys = (UINT)key_count;
        dcm.aKeys = keys;
        IContextMenu* cm = NULL;
        if (SUCCEEDED(SHCreateDefaultContextMenu(&dcm, &IID_IContextMenu,
                                                 (void**)&cm)) && cm != NULL) {
            HMENU menu = CreatePopupMenu();
            if (SUCCEEDED(cm->lpVtbl->QueryContextMenu(cm, menu, 0, 1, 0x7000,
                                                       CMF_NORMAL | CMF_EXPLORE))) {
                int total = GetMenuItemCount(menu);
                for (int i = 0; i < total && count < max; i++) {
                    wchar_t text[256];
                    text[0] = 0;
                    MENUITEMINFOW mi;
                    ZeroMemory(&mi, sizeof(mi));
                    mi.cbSize = sizeof(mi);
                    mi.fMask = MIIM_FTYPE | MIIM_ID | MIIM_STRING | MIIM_SUBMENU;
                    mi.dwTypeData = text;
                    mi.cch = 255;
                    if (!GetMenuItemInfoW(menu, (UINT)i, TRUE, &mi)) continue;
                    if (mi.fType & MFT_SEPARATOR) continue;
                    if (text[0] == 0) continue;
                    FlWin32StaticVerb* v = &out[count];
                    memset(v, 0, sizeof(*v));
                    /* Ampersands and accelerator text off, so the two lists
                     * can be compared as strings. */
                    wchar_t clean[256];
                    size_t o = 0;
                    for (size_t k = 0; text[k] != 0 && o + 1 < 256; k++) {
                        if (text[k] == (wchar_t)'\t') break;
                        if (text[k] == (wchar_t)'&') continue;
                        clean[o++] = text[k];
                    }
                    clean[o] = 0;
                    hc_wide_to_utf8(clean, v->label, (int)sizeof(v->label));
                    if (mi.hSubMenu == NULL && mi.wID >= 1) {
                        wchar_t verb[96];
                        verb[0] = 0;
                        if (SUCCEEDED(cm->lpVtbl->GetCommandString(
                                cm, (UINT_PTR)(mi.wID - 1), GCS_VERBW, NULL,
                                (CHAR*)verb, 96))) {
                            verb[95] = 0;
                            hc_wide_to_utf8(verb, v->verb, (int)sizeof(v->verb));
                        }
                    }
                    count++;
                }
            }
            DestroyMenu(menu);
            cm->lpVtbl->Release(cm);
        }
        parent->lpVtbl->Release(parent);
    }

    for (int i = 0; i < key_count; i++) RegCloseKey(keys[i]);
    if (pidl != NULL) CoTaskMemFree(pidl);
    free(wpath);
    if (SUCCEEDED(co)) CoUninitialize();
    return (int32_t)count;
}

/* One QueryContextMenu under one CMF_ flag set, timed.
 *
 * The flags are the only documented lever on the call itself, and two of them
 * claim to skip work: CMF_ASYNCVERBSTATE ("do not block computing whether a
 * verb is enabled") and CMF_OPTIMIZEFORINVOKE ("this menu is being built to
 * invoke through, not to show"). What they actually cost is published
 * nowhere, and the answer decides whether any of the tiering ideas are needed
 * at all -- a flag that halves the call is worth more than a tier that
 * duplicates the shell.
 *
 * A FRESH IContextMenu for every run, because a handler may cache what it was
 * asked the first time, and the caller is expected to have run one query
 * already so that nobody pays the cold DLL load inside a measurement.
 */
double flwin32_shellmenu_time_flags(const char* path, uint32_t flags,
                                    int32_t* items) {
    if (items != NULL) *items = 0;
    if (path == NULL) return -1.0;

    HRESULT co = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);

    int wlen = MultiByteToWideChar(CP_UTF8, 0, path, -1, NULL, 0);
    wchar_t* wpath = (wchar_t*)calloc((size_t)(wlen > 0 ? wlen : 1), sizeof(wchar_t));
    if (wpath == NULL) return -1.0;
    MultiByteToWideChar(CP_UTF8, 0, path, -1, wpath, wlen);

    LPITEMIDLIST pidl = NULL;
    IShellFolder* parent = NULL;
    LPCITEMIDLIST child = NULL;
    double elapsed = -1.0;

    if (SUCCEEDED(SHParseDisplayName(wpath, NULL, &pidl, 0, NULL))
            && SUCCEEDED(SHBindToParent(pidl, &IID_IShellFolder,
                                        (void**)&parent, &child))
            && parent != NULL) {
        IContextMenu* cm = NULL;
        if (SUCCEEDED(parent->lpVtbl->GetUIObjectOf(parent, NULL, 1, &child,
                                                    &IID_IContextMenu, NULL,
                                                    (void**)&cm)) && cm != NULL) {
            HMENU menu = CreatePopupMenu();
            double t0 = hc_now_ms();
            HRESULT hr = cm->lpVtbl->QueryContextMenu(cm, menu, 0, 1, 0x7000,
                                                      (UINT)flags);
            elapsed = hc_now_ms() - t0;
            if (items != NULL) *items = SUCCEEDED(hr) ? GetMenuItemCount(menu) : -1;
            DestroyMenu(menu);
            cm->lpVtbl->Release(cm);
        }
        parent->lpVtbl->Release(parent);
    }
    if (pidl != NULL) CoTaskMemFree(pidl);
    free(wpath);
    if (SUCCEEDED(co)) CoUninitialize();
    return elapsed;
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
