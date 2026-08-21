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

/* Lists the children of `location` -- a parsing name: a filesystem path, a
 * ::{CLSID} virtual folder, or a .zip. NULL when the location does not
 * resolve or cannot enumerate. Free with flwin32_ns_list_free. */
FlWin32NsList* flwin32_ns_list(const char* location) {
    if (location == NULL || location[0] == 0) return NULL;
    int wide_len = MultiByteToWideChar(CP_UTF8, 0, location, -1, NULL, 0);
    if (wide_len <= 0) return NULL;
    wchar_t* wide = (wchar_t*)calloc((size_t)wide_len, sizeof(wchar_t));
    if (wide == NULL) return NULL;
    MultiByteToWideChar(CP_UTF8, 0, location, -1, wide, wide_len);

    HRESULT init = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    FlWin32NsList* list = NULL;
    IShellItem* root = NULL;
    if (SUCCEEDED(SHCreateItemFromParsingName(wide, NULL, &IID_IShellItem,
                                              (void**)&root))) {
        IEnumShellItems* iter = NULL;
        if (SUCCEEDED(root->lpVtbl->BindToHandler(root, NULL, &kBHID_EnumItems,
                                                  &IID_IEnumShellItems,
                                                  (void**)&iter))) {
            int32_t capacity = 64;
            NsEntry* entries = (NsEntry*)calloc((size_t)capacity,
                                                sizeof(NsEntry));
            int32_t count = 0;
            IShellItem* child = NULL;
            while (entries != NULL &&
                   iter->lpVtbl->Next(iter, 1, &child, NULL) == S_OK) {
                if (count == capacity) {
                    capacity *= 2;
                    NsEntry* grown = (NsEntry*)realloc(
                        entries, (size_t)capacity * sizeof(NsEntry));
                    if (grown == NULL) {
                        child->lpVtbl->Release(child);
                        break;
                    }
                    entries = grown;
                }
                NsEntry* e = &entries[count];
                memset(e, 0, sizeof(*e));
                e->parsing = ns_name(child, SIGDN_DESKTOPABSOLUTEPARSING);
                e->display = ns_name(child, SIGDN_NORMALDISPLAY);

                SFGAOF attrs = 0;
                child->lpVtbl->GetAttributes(
                    child, SFGAO_FOLDER | SFGAO_FILESYSTEM | SFGAO_STREAM,
                    &attrs);
                /* A zip is FOLDER|STREAM at once; the caller decides which
                 * face to show, so both bits cross the boundary honestly:
                 * is_folder means "the shell can enumerate inside". */
                e->is_folder = (attrs & SFGAO_FOLDER) ? 1 : 0;
                e->is_filesystem = (attrs & SFGAO_FILESYSTEM) ? 1 : 0;
                if (attrs & SFGAO_STREAM) e->is_folder = 0;

                IShellItem2* item2 = NULL;
                if (SUCCEEDED(child->lpVtbl->QueryInterface(
                        child, &IID_IShellItem2, (void**)&item2))) {
                    ULONGLONG bytes = 0;
                    if (SUCCEEDED(item2->lpVtbl->GetUInt64(item2, &PKEY_Size,
                                                           &bytes))) {
                        e->size = (int64_t)bytes;
                    }
                    FILETIME ft;
                    if (SUCCEEDED(item2->lpVtbl->GetFileTime(
                            item2, &PKEY_DateModified, &ft))) {
                        long long ticks = ((long long)ft.dwHighDateTime << 32)
                            | ft.dwLowDateTime;
                        if (ticks > 0) {
                            e->mtime = ticks / 10000000LL - 11644473600LL;
                        }
                    }
                    LPWSTR type_w = NULL;
                    if (SUCCEEDED(item2->lpVtbl->GetString(
                            item2, &PKEY_ItemTypeText, &type_w))) {
                        e->type_name = ns_utf8_dup(type_w);
                        CoTaskMemFree(type_w);
                    }
                    item2->lpVtbl->Release(item2);
                }
                if (e->type_name == NULL) e->type_name = _strdup("");
                count++;
                child->lpVtbl->Release(child);
            }
            iter->lpVtbl->Release(iter);
            if (entries != NULL) {
                list = (FlWin32NsList*)calloc(1, sizeof(FlWin32NsList));
                if (list != NULL) {
                    list->entries = entries;
                    list->count = count;
                } else {
                    free(entries);
                }
            }
        }
        root->lpVtbl->Release(root);
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
