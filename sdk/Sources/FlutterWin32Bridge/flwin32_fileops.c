// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/*
 * flwin32_fileops.c -- the file operations behind Paste, Rename and Delete,
 * through the shell's own machinery.
 *
 * IFileOperation rather than MoveFileW/DeleteFileW, and the difference is
 * everything the user can see: the recycle bin instead of oblivion, the
 * shell's conflict dialog instead of a silent overwrite, a progress dialog
 * for the copy that turns out to be four gigabytes, and an entry in
 * Explorer's own undo stack. Rebuilding any of that around the raw file
 * APIs is building a worse copy of something already installed -- the same
 * argument the context menu makes for hosting the shell's verbs.
 *
 * THE CLIPBOARD SIDE MATCHES EXPLORER'S CONVENTIONS, which are subtler than
 * "put the paths somewhere":
 *
 *  - Copy and Cut both put a CF_HDROP data object on the clipboard; what
 *    distinguishes them is CFSTR_PREFERREDDROPEFFECT (DROPEFFECT_COPY
 *    against DROPEFFECT_MOVE). A paste that ignores the effect turns every
 *    cut into a copy, and the original never disappears.
 *  - After a MOVE paste the clipboard is cleared -- pasting a cut twice
 *    would otherwise try to move a file that is no longer there. A COPY
 *    paste leaves the clipboard alone; pasting twice is normal.
 *
 * EVERY ENTRY POINT HERE BLOCKS and expects to be called on a worker: each
 * initializes an STA, does the operation, and uninitializes. PerformOperations
 * runs the shell's own dialogs (progress, conflicts) from that thread and
 * pumps for itself -- what it needs is an apartment, not our message loop.
 * The Swift side runs these on a serial queue and hops back to the main
 * thread with the result.
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
#include <stdlib.h>
#include <string.h>

#include "include/FlutterWin32Bridge.h"

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "uuid.lib")

static wchar_t* fo_utf8_to_wide(const char* utf8) {
    if (utf8 == NULL) return NULL;
    int n = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, NULL, 0);
    if (n <= 0) return NULL;
    wchar_t* out = (wchar_t*)calloc((size_t)n, sizeof(wchar_t));
    if (out == NULL) return NULL;
    MultiByteToWideChar(CP_UTF8, 0, utf8, -1, out, n);
    return out;
}

/* EVERY COM OPERATION RUNS ON A THREAD OF ITS OWN, because the thread the
 * Swift side calls from is not ours to configure: dispatch-queue workers can
 * arrive already initialized as MTA, and OleInitialize on such a thread
 * fails with RPC_E_CHANGED_MODE -- a Copy that silently copies nothing.
 * (The same reasoning gave the context-menu session its own threads; see
 * flwin32_shellmenu.c.) The caller blocks on the join, which is fine: the
 * Swift wrapper is already on a worker queue. */
typedef int (*FoBody)(void* arg);
typedef struct {
    FoBody body;
    void* arg;
    int result;
} FoRun;

static DWORD WINAPI fo_thread(LPVOID param) {
    FoRun* run = (FoRun*)param;
    HRESULT co = OleInitialize(NULL);
    if (FAILED(co)) return 0;
    run->result = run->body(run->arg);
    OleUninitialize();
    return 0;
}

static int fo_run_sta(FoBody body, void* arg) {
    FoRun run = { body, arg, 0 };
    HANDLE thread = CreateThread(NULL, 0, fo_thread, &run, 0, NULL);
    if (thread == NULL) return 0;
    WaitForSingleObject(thread, INFINITE);
    CloseHandle(thread);
    return run.result;
}

/* Whether a paste would have anything to paste. IsClipboardFormatAvailable
 * needs no open clipboard and no COM, so this is cheap enough to ask at
 * every menu open. */
int32_t flwin32_clipboard_has_files(void) {
    return IsClipboardFormatAvailable(CF_HDROP) ? 1 : 0;
}

/* The preferred drop effect of the clipboard's current contents, or
 * DROPEFFECT_COPY when nobody said. Reads the raw clipboard rather than
 * OleGetClipboard so it can be asked outside an apartment. */
static DWORD fo_clipboard_effect(void) {
    DWORD effect = DROPEFFECT_COPY;
    UINT format = RegisterClipboardFormatW(CFSTR_PREFERREDDROPEFFECT);
    if (!OpenClipboard(NULL)) return effect;
    HANDLE handle = GetClipboardData(format);
    if (handle != NULL) {
        DWORD* value = (DWORD*)GlobalLock(handle);
        if (value != NULL) {
            effect = *value;
            GlobalUnlock(handle);
        }
    }
    CloseClipboard();
    return effect;
}

/* An IFileOperation configured the way Explorer's own operations are:
 * undoable, recycle-bin-honouring, with dialogs parented to the owner. */
static HRESULT fo_create(HWND owner, IFileOperation** out) {
    IFileOperation* op = NULL;
    HRESULT hr = CoCreateInstance(&CLSID_FileOperation, NULL, CLSCTX_ALL,
                                  &IID_IFileOperation, (void**)&op);
    if (FAILED(hr) || op == NULL) return FAILED(hr) ? hr : E_FAIL;
    op->lpVtbl->SetOperationFlags(op, FOF_ALLOWUNDO | FOFX_ADDUNDORECORD);
    if (owner != NULL) op->lpVtbl->SetOwnerWindow(op, owner);
    *out = op;
    return S_OK;
}

/* Paste the clipboard's files into `target_dir`, honouring the preferred
 * drop effect. Returns 1 when the operation ran (which for the shell's
 * dialogs includes "the user cancelled it" -- that is their choice, not an
 * error), 0 when there was nothing to paste or the setup failed. */
typedef struct {
    wchar_t* dir;
    HWND owner;
    int move;
} FoPasteArgs;

static int fo_paste_body(void* arg) {
    FoPasteArgs* a = (FoPasteArgs*)arg;
    wchar_t* dir = a->dir;
    int move = a->move;
    int ok = 0;

    IDataObject* data = NULL;
    IShellItem* target = NULL;
    IShellItemArray* items = NULL;
    IFileOperation* op = NULL;

    if (SUCCEEDED(OleGetClipboard(&data)) && data != NULL
        && SUCCEEDED(SHCreateItemFromParsingName(dir, NULL, &IID_IShellItem,
                                                 (void**)&target))
        && SUCCEEDED(SHCreateShellItemArrayFromDataObject(
               data, &IID_IShellItemArray, (void**)&items))
        && SUCCEEDED(fo_create(a->owner, &op))) {
        HRESULT hr = move
            ? op->lpVtbl->MoveItems(op, (IUnknown*)items, target)
            : op->lpVtbl->CopyItems(op, (IUnknown*)items, target);
        if (SUCCEEDED(hr) && SUCCEEDED(op->lpVtbl->PerformOperations(op))) {
            ok = 1;
            if (move) {
                /* A cut has been consumed. Explorer clears the clipboard
                 * here too: pasting it again would move files that are no
                 * longer where the clipboard says. */
                OleSetClipboard(NULL);
            }
        }
    }

    if (op != NULL) op->lpVtbl->Release(op);
    if (items != NULL) items->lpVtbl->Release(items);
    if (target != NULL) target->lpVtbl->Release(target);
    if (data != NULL) data->lpVtbl->Release(data);
    return ok;
}

int32_t flwin32_fileop_paste(const char* target_dir, uint64_t owner) {
    if (target_dir == NULL || target_dir[0] == 0) return 0;
    FoPasteArgs args;
    args.dir = fo_utf8_to_wide(target_dir);
    if (args.dir == NULL) return 0;
    args.owner = (HWND)(ULONG_PTR)owner;
    /* The effect is read before the apartment: a MOVE clears the clipboard
     * afterwards, and knowing which branch we are in shapes the whole call. */
    DWORD effect = fo_clipboard_effect();
    args.move = (effect & DROPEFFECT_MOVE) != 0
             && (effect & DROPEFFECT_COPY) == 0;
    int ok = fo_run_sta(fo_paste_body, &args);
    free(args.dir);
    return ok;
}

/* Rename one item in place. `new_name` is a NAME, not a path -- that is
 * IFileOperation's contract, and it is the right one: the shell handles the
 * collision dialog, extension warnings, and the undo entry. */
typedef struct {
    wchar_t* path;
    wchar_t* name;
    HWND owner;
} FoRenameArgs;

static int fo_rename_body(void* arg) {
    FoRenameArgs* a = (FoRenameArgs*)arg;
    int ok = 0;
    IShellItem* item = NULL;
    IFileOperation* op = NULL;
    if (SUCCEEDED(SHCreateItemFromParsingName(a->path, NULL, &IID_IShellItem,
                                              (void**)&item))
        && SUCCEEDED(fo_create(a->owner, &op))) {
        if (SUCCEEDED(op->lpVtbl->RenameItem(op, item, a->name, NULL))
            && SUCCEEDED(op->lpVtbl->PerformOperations(op))) {
            ok = 1;
        }
    }
    if (op != NULL) op->lpVtbl->Release(op);
    if (item != NULL) item->lpVtbl->Release(item);
    return ok;
}

int32_t flwin32_fileop_rename(const char* path, const char* new_name,
                              uint64_t owner) {
    if (path == NULL || new_name == NULL || new_name[0] == 0) return 0;
    FoRenameArgs args;
    args.path = fo_utf8_to_wide(path);
    args.name = fo_utf8_to_wide(new_name);
    args.owner = (HWND)(ULONG_PTR)owner;
    if (args.path == NULL || args.name == NULL) {
        free(args.path);
        free(args.name);
        return 0;
    }
    int ok = fo_run_sta(fo_rename_body, &args);
    free(args.path);
    free(args.name);
    return ok;
}

/* Delete to the recycle bin (FOF_ALLOWUNDO makes it the bin, not oblivion),
 * with the shell's own confirmation and progress. */
typedef struct {
    wchar_t* path;
    HWND owner;
} FoDeleteArgs;

static int fo_delete_body(void* arg) {
    FoDeleteArgs* a = (FoDeleteArgs*)arg;
    int ok = 0;
    IShellItem* item = NULL;
    IFileOperation* op = NULL;
    if (SUCCEEDED(SHCreateItemFromParsingName(a->path, NULL, &IID_IShellItem,
                                              (void**)&item))
        && SUCCEEDED(fo_create(a->owner, &op))) {
        if (SUCCEEDED(op->lpVtbl->DeleteItem(op, item, NULL))
            && SUCCEEDED(op->lpVtbl->PerformOperations(op))) {
            ok = 1;
        }
    }
    if (op != NULL) op->lpVtbl->Release(op);
    if (item != NULL) item->lpVtbl->Release(item);
    return ok;
}

int32_t flwin32_fileop_delete(const char* path, uint64_t owner) {
    if (path == NULL || path[0] == 0) return 0;
    FoDeleteArgs args;
    args.path = fo_utf8_to_wide(path);
    if (args.path == NULL) return 0;
    args.owner = (HWND)(ULONG_PTR)owner;
    int ok = fo_run_sta(fo_delete_body, &args);
    free(args.path);
    return ok;
}

/* Put one item on the clipboard as a copy or a cut.
 *
 * The data object is the SHELL'S, from the item's parent folder -- the same
 * object Explorer would put up, carrying CF_HDROP and the shell's richer
 * formats -- with CFSTR_PREFERREDDROPEFFECT written over it to say which of
 * copy and cut this is. OleFlushClipboard before returning: the object
 * lives in this apartment, and this apartment is about to end -- the flush
 * renders the formats into the clipboard itself, the same lesson the menu
 * session learned (see release_tier in flwin32_shellmenu.c). */
typedef struct {
    wchar_t* path;
    int is_cut;
} FoClipArgs;

static int fo_clip_body(void* arg) {
    FoClipArgs* a = (FoClipArgs*)arg;
    wchar_t* wpath = a->path;
    int is_cut = a->is_cut;
    int ok = 0;

    LPITEMIDLIST pidl = NULL;
    if (SUCCEEDED(SHParseDisplayName(wpath, NULL, &pidl, 0, NULL))) {
        IShellFolder* parent = NULL;
        LPCITEMIDLIST child = NULL;
        if (SUCCEEDED(SHBindToParent(pidl, &IID_IShellFolder, (void**)&parent,
                                     &child))) {
            IDataObject* data = NULL;
            if (SUCCEEDED(parent->lpVtbl->GetUIObjectOf(
                    parent, NULL, 1, &child, &IID_IDataObject, NULL,
                    (void**)&data)) && data != NULL) {
                /* The effect rides the data object as its own format. */
                FORMATETC fmt = {
                    (CLIPFORMAT)RegisterClipboardFormatW(
                        CFSTR_PREFERREDDROPEFFECT),
                    NULL, DVASPECT_CONTENT, -1, TYMED_HGLOBAL };
                HGLOBAL mem = GlobalAlloc(GMEM_MOVEABLE, sizeof(DWORD));
                if (mem != NULL) {
                    DWORD* value = (DWORD*)GlobalLock(mem);
                    if (value != NULL) {
                        *value = is_cut ? DROPEFFECT_MOVE : DROPEFFECT_COPY;
                        GlobalUnlock(mem);
                        STGMEDIUM medium;
                        medium.tymed = TYMED_HGLOBAL;
                        medium.hGlobal = mem;
                        medium.pUnkForRelease = NULL;
                        /* fRelease TRUE: the object owns `mem` now. */
                        data->lpVtbl->SetData(data, &fmt, &medium, TRUE);
                    } else {
                        GlobalFree(mem);
                    }
                }
                if (SUCCEEDED(OleSetClipboard(data))) {
                    OleFlushClipboard();
                    ok = 1;
                }
                data->lpVtbl->Release(data);
            }
            parent->lpVtbl->Release(parent);
        }
        CoTaskMemFree(pidl);
    }
    return ok;
}

int32_t flwin32_fileop_clip(const char* path, int32_t is_cut) {
    if (path == NULL || path[0] == 0) return 0;
    FoClipArgs args;
    args.path = fo_utf8_to_wide(path);
    if (args.path == NULL) return 0;
    args.is_cut = is_cut;
    int ok = fo_run_sta(fo_clip_body, &args);
    free(args.path);
    return ok;
}

/* The item's property sheet, by the shell's front door -- the same
 * SHObjectProperties the context menu uses for its properties verb, exposed
 * so Alt+Enter can reach it without a menu session. */
int32_t flwin32_fileop_properties(const char* path, uint64_t owner) {
    if (path == NULL || path[0] == 0) return 0;
    wchar_t* wpath = fo_utf8_to_wide(path);
    if (wpath == NULL) return 0;
    int ok = SHObjectProperties((HWND)(ULONG_PTR)owner, SHOP_FILEPATH, wpath,
                                NULL) ? 1 : 0;
    free(wpath);
    return ok;
}
