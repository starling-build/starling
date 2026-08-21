// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/*
 * flwin32_namespace.c -- listing the shell's NAMESPACE, not the filesystem.
 *
 * The file explorer's ordinary listing is FileManager over a directory
 * path, and for real folders that is the right tool. But half of what
 * Explorer can stand inside has no directory behind it at all: the Recycle
 * Bin, Network, Quick Access -- and a .zip file, which the shell treats as
 * a folder. Those are SHELL ITEMS, addressed by parsing names
 * ("::{645FF040-...}" for the bin, a plain path for a zip), enumerated
 * through IEnumShellItems, and named by properties rather than by their
 * path's last component (a recycled file's parsing name is its $R... slot;
 * its display name is what the user deleted).
 *
 * Snapshot-object shape, like the tray list: one call walks the folder and
 * resolves EVERYTHING into plain C data -- strings, numbers -- and releases
 * every COM object before returning, so the caller never holds an
 * apartment-bound pointer. Enumerating Network can block on discovery;
 * call this off the UI thread, which is also where the listing already
 * lives.
 *
 * COM-inits its own apartment (tolerating a caller's), same as
 * flwin32_wallpaper_average and for the same reason: the callers are
 * detached tasks with no apartment of their own.
 */

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <initguid.h>
#include <windows.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <propkey.h>
#include <propsys.h>   /* PSGetPropertyKeyFromName */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "include/FlutterWin32Bridge.h"

#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "propsys.lib")

/* BHID_EnumItems is declared __declspec(selectany) in C++ builds of
 * shobjidl_core.h but never defined for plain C even under INITGUID; the
 * GUID is documented and frozen (94f60519-2850-4924-aa5a-d15e84868039). */
DEFINE_GUID(kBHID_EnumItems, 0x94f60519, 0x2850, 0x4924, 0xaa, 0x5a, 0xd1,
            0x5e, 0x84, 0x86, 0x80, 0x39);

typedef struct {
    char* parsing;     /* re-addressable name (UTF-8) */
    char* display;     /* what the user sees (UTF-8) */
    char* type_name;   /* Explorer's Type column (UTF-8), may be empty */
    int32_t is_folder;
    int32_t is_filesystem;
    int32_t is_pinned;  /* 1/0 from System.Home.IsPinned, -1 not answered --
                         * only Quick Access children answer it at all */
    int64_t size;      /* bytes, 0 when the item will not say */
    int64_t mtime;     /* unix seconds, 0 when unknown */
} NsEntry;

struct FlWin32NsList {
    NsEntry* entries;
    int32_t count;
};

static char* ns_utf8_dup(const wchar_t* w) {
    if (w == NULL) return _strdup("");
    int need = WideCharToMultiByte(CP_UTF8, 0, w, -1, NULL, 0, NULL, NULL);
    if (need <= 0) return _strdup("");
    char* out = (char*)malloc((size_t)need);
    if (out == NULL) return NULL;
    WideCharToMultiByte(CP_UTF8, 0, w, -1, out, need, NULL, NULL);
    return out;
}

static char* ns_name(IShellItem* item, SIGDN which) {
    LPWSTR w = NULL;
    if (FAILED(item->lpVtbl->GetDisplayName(item, which, &w))) {
        return _strdup("");
    }
    char* out = ns_utf8_dup(w);
    CoTaskMemFree(w);
    return out;
}

/* The growing list plus the one piece of per-call state the extraction
 * needs: the System.Home.IsPinned key, resolved by NAME at runtime
 * (PSGetPropertyKeyFromName) because the SDK headers ship no PKEY_ for it
 * -- it is the property Explorer's own Home view groups by, and the only
 * honest way to split Quick Access into pinned and merely-frequent. */
typedef struct {
    NsEntry* entries;
    int32_t count;
    int32_t capacity;
    PROPERTYKEY pinned_key;
    int has_pinned_key;
} NsBuild;

/* Extracts one child into the build. Returns 0 only on allocation failure;
 * an item that answers nothing still lands, with empty fields. */
static int ns_collect(NsBuild* b, IShellItem* child) {
    if (b->count == b->capacity) {
        int32_t grown_cap = b->capacity * 2;
        NsEntry* grown = (NsEntry*)realloc(
            b->entries, (size_t)grown_cap * sizeof(NsEntry));
        if (grown == NULL) return 0;
        b->entries = grown;
        b->capacity = grown_cap;
    }
    NsEntry* e = &b->entries[b->count];
    memset(e, 0, sizeof(*e));
    e->is_pinned = -1;
    e->parsing = ns_name(child, SIGDN_DESKTOPABSOLUTEPARSING);
    /* PARENTRELATIVE, not NORMALDISPLAY: a Name column wants what the item
     * is called INSIDE this folder. They agree for most locations and
     * disagree exactly where it matters -- a recycled item's NORMALDISPLAY
     * is its original FULL PATH ("C:\Users\...\Downloads\notes.txt"), which
     * filled the bin's Name column with paths. Explorer shows "notes.txt"
     * there and puts the path in its own Original Location column, which
     * this window does not have yet. */
    e->display = ns_name(child, SIGDN_PARENTRELATIVE);

    SFGAOF attrs = 0;
    child->lpVtbl->GetAttributes(
        child, SFGAO_FOLDER | SFGAO_FILESYSTEM | SFGAO_STREAM, &attrs);
    /* A zip is FOLDER|STREAM at once; the caller decides which face to
     * show, so both bits cross the boundary honestly: is_folder means "the
     * shell can enumerate inside". */
    e->is_folder = (attrs & SFGAO_FOLDER) ? 1 : 0;
    e->is_filesystem = (attrs & SFGAO_FILESYSTEM) ? 1 : 0;
    if (attrs & SFGAO_STREAM) e->is_folder = 0;

    IShellItem2* item2 = NULL;
    if (SUCCEEDED(child->lpVtbl->QueryInterface(
            child, &IID_IShellItem2, (void**)&item2))) {
        ULONGLONG bytes = 0;
        if (SUCCEEDED(item2->lpVtbl->GetUInt64(item2, &PKEY_Size, &bytes))) {
            e->size = (int64_t)bytes;
        }
        FILETIME ft;
        if (SUCCEEDED(item2->lpVtbl->GetFileTime(item2, &PKEY_DateModified,
                                                 &ft))) {
            long long ticks = ((long long)ft.dwHighDateTime << 32)
                | ft.dwLowDateTime;
            if (ticks > 0) {
                e->mtime = ticks / 10000000LL - 11644473600LL;
            }
        }
        LPWSTR type_w = NULL;
        if (SUCCEEDED(item2->lpVtbl->GetString(item2, &PKEY_ItemTypeText,
                                               &type_w))) {
            e->type_name = ns_utf8_dup(type_w);
            CoTaskMemFree(type_w);
        }
        if (b->has_pinned_key) {
            BOOL pinned = FALSE;
            if (SUCCEEDED(item2->lpVtbl->GetBool(item2, &b->pinned_key,
                                                 &pinned))) {
                e->is_pinned = pinned ? 1 : 0;
            }
        }
        item2->lpVtbl->Release(item2);
    }
    if (e->type_name == NULL) e->type_name = _strdup("");
    b->count++;
    return 1;
}

/* Lists the children of `location` -- a parsing name: a filesystem path, a
 * ::{CLSID} virtual folder, or a .zip. NULL when the location does not
 * resolve or cannot enumerate. Free with flwin32_ns_list_free.
 *
 * TWO enumeration routes, because the shell's folders do not agree on one.
 * IEnumShellItems (BHID_EnumItems) is the modern spelling and works for the
 * filesystem, the Recycle Bin, Network and zips -- and QUICK ACCESS refuses
 * it outright, while answering the classic IShellFolder::EnumObjects that
 * predates it. So the classic walk is the fallback, feeding the same
 * per-item extraction through SHCreateItemWithParent. (Verified with
 * --ns-probe: BHID on ::{679f85cb-...} yields nothing on Windows 11 24H2;
 * EnumObjects yields the same items Explorer's Home shows.) */
FlWin32NsList* flwin32_ns_list(const char* location) {
    if (location == NULL || location[0] == 0) return NULL;
    int wide_len = MultiByteToWideChar(CP_UTF8, 0, location, -1, NULL, 0);
    if (wide_len <= 0) return NULL;
    wchar_t* wide = (wchar_t*)calloc((size_t)wide_len, sizeof(wchar_t));
    if (wide == NULL) return NULL;
    MultiByteToWideChar(CP_UTF8, 0, location, -1, wide, wide_len);

    HRESULT init = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    FlWin32NsList* list = NULL;
    NsBuild build;
    memset(&build, 0, sizeof(build));
    build.capacity = 64;
    build.entries = (NsEntry*)calloc((size_t)build.capacity, sizeof(NsEntry));
    build.has_pinned_key = SUCCEEDED(PSGetPropertyKeyFromName(
        L"System.Home.IsPinned", &build.pinned_key));
    int enumerated = 0;

    IShellItem* root = NULL;
    if (build.entries != NULL
        && SUCCEEDED(SHCreateItemFromParsingName(wide, NULL, &IID_IShellItem,
                                                 (void**)&root))) {
        IEnumShellItems* iter = NULL;
        if (SUCCEEDED(root->lpVtbl->BindToHandler(root, NULL, &kBHID_EnumItems,
                                                  &IID_IEnumShellItems,
                                                  (void**)&iter))) {
            enumerated = 1;
            IShellItem* child = NULL;
            while (iter->lpVtbl->Next(iter, 1, &child, NULL) == S_OK) {
                int ok = ns_collect(&build, child);
                child->lpVtbl->Release(child);
                if (!ok) break;
            }
            iter->lpVtbl->Release(iter);
        }
        root->lpVtbl->Release(root);
    }

    if (build.entries != NULL && !enumerated) {
        /* The classic route, for the folders the modern one refuses. */
        LPITEMIDLIST pidl = NULL;
        IShellFolder* folder = NULL;
        IEnumIDList* ids = NULL;
        if (SUCCEEDED(SHParseDisplayName(wide, NULL, &pidl, 0, NULL))
            && SUCCEEDED(SHBindToObject(NULL, pidl, NULL, &IID_IShellFolder,
                                        (void**)&folder))
            && SUCCEEDED(folder->lpVtbl->EnumObjects(
                   folder, NULL, SHCONTF_FOLDERS | SHCONTF_NONFOLDERS, &ids))
            && ids != NULL) {
            enumerated = 1;
            LPITEMIDLIST child_pidl = NULL;
            while (ids->lpVtbl->Next(ids, 1, &child_pidl, NULL) == S_OK) {
                IShellItem* child = NULL;
                int ok = 1;
                if (SUCCEEDED(SHCreateItemWithParent(
                        NULL, folder, child_pidl, &IID_IShellItem,
                        (void**)&child))) {
                    ok = ns_collect(&build, child);
                    child->lpVtbl->Release(child);
                }
                CoTaskMemFree(child_pidl);
                if (!ok) break;
            }
            ids->lpVtbl->Release(ids);
        }
        if (folder != NULL) folder->lpVtbl->Release(folder);
        if (pidl != NULL) CoTaskMemFree(pidl);
    }

    if (build.entries != NULL && enumerated) {
        list = (FlWin32NsList*)calloc(1, sizeof(FlWin32NsList));
        if (list != NULL) {
            list->entries = build.entries;
            list->count = build.count;
            build.entries = NULL;
        }
    }
    if (build.entries != NULL) {
        for (int32_t i = 0; i < build.count; i++) {
            free(build.entries[i].parsing);
            free(build.entries[i].display);
            free(build.entries[i].type_name);
        }
        free(build.entries);
    }
    free(wide);
    if (init == S_OK || init == S_FALSE) CoUninitialize();
    return list;
}

void flwin32_ns_list_free(FlWin32NsList* list) {
    if (list == NULL) return;
    for (int32_t i = 0; i < list->count; i++) {
        free(list->entries[i].parsing);
        free(list->entries[i].display);
        free(list->entries[i].type_name);
    }
    free(list->entries);
    free(list);
}

int32_t flwin32_ns_count(FlWin32NsList* list) {
    return list == NULL ? 0 : list->count;
}

/* field: 0 parsing name, 1 display name, 2 type name. */
int32_t flwin32_ns_field(FlWin32NsList* list, int32_t index, int32_t field,
                         char* out, int32_t out_size) {
    if (list == NULL || index < 0 || index >= list->count || out == NULL
        || out_size <= 0) {
        return 0;
    }
    const char* s = field == 0 ? list->entries[index].parsing
        : field == 1 ? list->entries[index].display
        : list->entries[index].type_name;
    if (s == NULL) s = "";
    int len = (int)strlen(s);
    if (len + 1 > out_size) len = out_size - 1;
    memcpy(out, s, (size_t)len);
    out[len] = 0;
    return len + 1;
}

/* One location's OWN display name. flwin32_file_display_name is the wrong
 * tool for a ::{CLSID}: SHGetFileInfoW parses a filesystem path and a
 * parsing name is not one, so it fails and the caller falls back to the raw
 * "::{645FF040-...}" as a label. Resolving the item and asking it works for
 * every parsing name, and answers in the machine's own language. */
int32_t flwin32_ns_display_name(const char* location, char* out,
                                int32_t out_size) {
    if (location == NULL || location[0] == 0 || out == NULL || out_size <= 0) {
        return 0;
    }
    int wide_len = MultiByteToWideChar(CP_UTF8, 0, location, -1, NULL, 0);
    if (wide_len <= 0) return 0;
    wchar_t* wide = (wchar_t*)calloc((size_t)wide_len, sizeof(wchar_t));
    if (wide == NULL) return 0;
    MultiByteToWideChar(CP_UTF8, 0, location, -1, wide, wide_len);

    HRESULT init = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    int32_t written = 0;
    IShellItem* item = NULL;
    if (SUCCEEDED(SHCreateItemFromParsingName(wide, NULL, &IID_IShellItem,
                                              (void**)&item))) {
        LPWSTR name = NULL;
        if (SUCCEEDED(item->lpVtbl->GetDisplayName(item, SIGDN_NORMALDISPLAY,
                                                   &name))) {
            int need = WideCharToMultiByte(CP_UTF8, 0, name, -1, NULL, 0,
                                           NULL, NULL);
            if (need > 0 && need <= out_size) {
                WideCharToMultiByte(CP_UTF8, 0, name, -1, out, out_size,
                                    NULL, NULL);
                written = need;
            }
            CoTaskMemFree(name);
        }
        item->lpVtbl->Release(item);
    }
    free(wide);
    if (init == S_OK || init == S_FALSE) CoUninitialize();
    return written;
}

int32_t flwin32_ns_attrs(FlWin32NsList* list, int32_t index,
                         int32_t* is_folder, int32_t* is_filesystem,
                         int64_t* size, int64_t* mtime_unix) {
    if (list == NULL || index < 0 || index >= list->count) return 0;
    const NsEntry* e = &list->entries[index];
    if (is_folder != NULL) *is_folder = e->is_folder;
    if (is_filesystem != NULL) *is_filesystem = e->is_filesystem;
    if (size != NULL) *size = e->size;
    if (mtime_unix != NULL) *mtime_unix = e->mtime;
    return 1;
}

/* System.Home.IsPinned: 1 pinned, 0 not, -1 the item did not answer --
 * which is every item outside Quick Access, so -1 is the ordinary value
 * everywhere else and callers must not read it as "not pinned". */
int32_t flwin32_ns_pinned(FlWin32NsList* list, int32_t index) {
    if (list == NULL || index < 0 || index >= list->count) return -1;
    return list->entries[index].is_pinned;
}
