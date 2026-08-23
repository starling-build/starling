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

/* ── the journal ─────────────────────────────────────────────────────────
 *
 * What the operation ACTUALLY did, one record per item, captured through an
 * IFileOperationProgressSink. It exists because Ctrl+Z cannot be delegated:
 * FOFX_ADDUNDORECORD above writes into the shell's undo stack, but that
 * stack is Explorer's private property -- there is no API to replay it, so
 * an app that wants undo keeps its own inverse journal. And the journal has
 * to come from the sink rather than from the request, because the shell
 * rewrites names en route: a copy into the same folder lands as
 * "a - Copy.txt", a collision resolved with "Keep both" lands as "a (2).txt",
 * and undoing the name we ASKED for instead of the name we GOT deletes the
 * wrong file or nothing.
 *
 * One static journal, reset at fo_create and read immediately after the
 * blocking call returns. Safe without a lock for the same reason the whole
 * file is: the Swift side serializes every operation on one queue, and
 * fo_run_sta joins the STA thread before returning, so writer and reader
 * never overlap. */

#define FO_JOURNAL_MAX 256

/* kind: 1 copy, 2 move, 3 rename, 4 delete, 5 new. For a delete, `dst` is
 * the item's new parsing name INSIDE the recycle bin (the $R... slot) --
 * which is exactly what a restore needs -- or empty when the delete was
 * permanent and there is nothing to undo. */
typedef struct {
    int32_t kind;
    char src[1024];
    char dst[1024];
} FoJournalRec;

static FoJournalRec fo_journal[FO_JOURNAL_MAX];
static int32_t fo_journal_count = 0;

static void fo_journal_path(IShellItem* item, char* out, int32_t out_size) {
    out[0] = 0;
    if (item == NULL) return;
    LPWSTR w = NULL;
    /* FILESYSPATH first -- it is what every undo executor consumes -- and
     * the parsing name for the rare item without one. A recycled item HAS a
     * filesystem path (the slot really is a file), which doubles as its
     * parsing name in the bin; see flwin32_namespace.c. */
    if (FAILED(item->lpVtbl->GetDisplayName(item, SIGDN_FILESYSPATH, &w))
        && FAILED(item->lpVtbl->GetDisplayName(
               item, SIGDN_DESKTOPABSOLUTEPARSING, &w))) {
        return;
    }
    WideCharToMultiByte(CP_UTF8, 0, w, -1, out, out_size, NULL, NULL);
    out[out_size - 1] = 0;
    CoTaskMemFree(w);
}

static void fo_journal_add(int32_t kind, IShellItem* src, IShellItem* dst) {
    if (fo_journal_count >= FO_JOURNAL_MAX) return;
    FoJournalRec* rec = &fo_journal[fo_journal_count];
    rec->kind = kind;
    fo_journal_path(src, rec->src, sizeof(rec->src));
    fo_journal_path(dst, rec->dst, sizeof(rec->dst));
    fo_journal_count++;
}

/* The sink itself: a static COM object in C. Refcounting is a formality
 * (the object is static; Release never frees), and every Pre* hook approves
 * by returning S_OK -- this sink observes, it never vetoes. */
typedef struct {
    IFileOperationProgressSinkVtbl* lpVtbl;
} FoSink;

static HRESULT STDMETHODCALLTYPE fo_sink_qi(IFileOperationProgressSink* self,
                                            REFIID riid, void** out) {
    if (out == NULL) return E_POINTER;
    if (IsEqualIID(riid, &IID_IUnknown)
        || IsEqualIID(riid, &IID_IFileOperationProgressSink)) {
        *out = self;
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}
static ULONG STDMETHODCALLTYPE fo_sink_addref(
    IFileOperationProgressSink* self) { (void)self; return 2; }
static ULONG STDMETHODCALLTYPE fo_sink_release(
    IFileOperationProgressSink* self) { (void)self; return 1; }
static HRESULT STDMETHODCALLTYPE fo_sink_start(
    IFileOperationProgressSink* self) { (void)self; return S_OK; }
static HRESULT STDMETHODCALLTYPE fo_sink_finish(
    IFileOperationProgressSink* self, HRESULT hr) {
    (void)self; (void)hr; return S_OK;
}
static HRESULT STDMETHODCALLTYPE fo_sink_pre_rename(
    IFileOperationProgressSink* self, DWORD flags, IShellItem* item,
    LPCWSTR name) {
    (void)self; (void)flags; (void)item; (void)name; return S_OK;
}
static HRESULT STDMETHODCALLTYPE fo_sink_post_rename(
    IFileOperationProgressSink* self, DWORD flags, IShellItem* item,
    LPCWSTR name, HRESULT hr, IShellItem* created) {
    (void)self; (void)flags; (void)name;
    if (SUCCEEDED(hr) && created != NULL) fo_journal_add(3, item, created);
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE fo_sink_pre_move(
    IFileOperationProgressSink* self, DWORD flags, IShellItem* item,
    IShellItem* folder, LPCWSTR name) {
    (void)self; (void)flags; (void)item; (void)folder; (void)name;
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE fo_sink_post_move(
    IFileOperationProgressSink* self, DWORD flags, IShellItem* item,
    IShellItem* folder, LPCWSTR name, HRESULT hr, IShellItem* created) {
    (void)self; (void)flags; (void)folder; (void)name;
    if (SUCCEEDED(hr) && created != NULL) fo_journal_add(2, item, created);
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE fo_sink_pre_copy(
    IFileOperationProgressSink* self, DWORD flags, IShellItem* item,
    IShellItem* folder, LPCWSTR name) {
    (void)self; (void)flags; (void)item; (void)folder; (void)name;
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE fo_sink_post_copy(
    IFileOperationProgressSink* self, DWORD flags, IShellItem* item,
    IShellItem* folder, LPCWSTR name, HRESULT hr, IShellItem* created) {
    (void)self; (void)flags; (void)folder; (void)name;
    if (SUCCEEDED(hr) && created != NULL) fo_journal_add(1, item, created);
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE fo_sink_pre_delete(
    IFileOperationProgressSink* self, DWORD flags, IShellItem* item) {
    (void)self; (void)flags; (void)item; return S_OK;
}
static HRESULT STDMETHODCALLTYPE fo_sink_post_delete(
    IFileOperationProgressSink* self, DWORD flags, IShellItem* item,
    HRESULT hr, IShellItem* created) {
    (void)self; (void)flags;
    /* `created` is the item's new incarnation in the recycle bin, present
     * exactly when the delete was a recycle. A permanent delete records an
     * empty dst, which the undo side reads as "gone for real". */
    if (SUCCEEDED(hr)) fo_journal_add(4, item, created);
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE fo_sink_pre_new(
    IFileOperationProgressSink* self, DWORD flags, IShellItem* folder,
    LPCWSTR name) {
    (void)self; (void)flags; (void)folder; (void)name; return S_OK;
}
static HRESULT STDMETHODCALLTYPE fo_sink_post_new(
    IFileOperationProgressSink* self, DWORD flags, IShellItem* folder,
    LPCWSTR name, LPCWSTR template_name, DWORD attrs, HRESULT hr,
    IShellItem* created) {
    (void)self; (void)flags; (void)folder; (void)name; (void)template_name;
    (void)attrs;
    if (SUCCEEDED(hr) && created != NULL) fo_journal_add(5, NULL, created);
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE fo_sink_progress(
    IFileOperationProgressSink* self, UINT total, UINT done) {
    (void)self; (void)total; (void)done; return S_OK;
}
static HRESULT STDMETHODCALLTYPE fo_sink_reset_timer(
    IFileOperationProgressSink* self) { (void)self; return S_OK; }
static HRESULT STDMETHODCALLTYPE fo_sink_pause_timer(
    IFileOperationProgressSink* self) { (void)self; return S_OK; }
static HRESULT STDMETHODCALLTYPE fo_sink_resume_timer(
    IFileOperationProgressSink* self) { (void)self; return S_OK; }

static IFileOperationProgressSinkVtbl fo_sink_vtbl = {
    fo_sink_qi, fo_sink_addref, fo_sink_release,
    fo_sink_start, fo_sink_finish,
    fo_sink_pre_rename, fo_sink_post_rename,
    fo_sink_pre_move, fo_sink_post_move,
    fo_sink_pre_copy, fo_sink_post_copy,
    fo_sink_pre_delete, fo_sink_post_delete,
    fo_sink_pre_new, fo_sink_post_new,
    fo_sink_progress, fo_sink_reset_timer, fo_sink_pause_timer,
    fo_sink_resume_timer,
};
static FoSink fo_sink = { &fo_sink_vtbl };

int32_t flwin32_fileop_journal_count(void) {
    return fo_journal_count;
}

int32_t flwin32_fileop_journal_get(int32_t index, int32_t* kind,
                                   char* src, int32_t src_size,
                                   char* dst, int32_t dst_size) {
    if (index < 0 || index >= fo_journal_count) return 0;
    const FoJournalRec* rec = &fo_journal[index];
    if (kind != NULL) *kind = rec->kind;
    if (src != NULL && src_size > 0) {
        strncpy_s(src, (size_t)src_size, rec->src, _TRUNCATE);
    }
    if (dst != NULL && dst_size > 0) {
        strncpy_s(dst, (size_t)dst_size, rec->dst, _TRUNCATE);
    }
    return 1;
}

/* An IFileOperation configured the way Explorer's own operations are:
 * undoable, recycle-bin-honouring, with dialogs parented to the owner --
 * and observed: the journal above is reset here and filled by the sink as
 * the operation runs, so every entry point in this file reports what it
 * really did without any of them asking for it. */
static HRESULT fo_create(HWND owner, IFileOperation** out) {
    IFileOperation* op = NULL;
    HRESULT hr = CoCreateInstance(&CLSID_FileOperation, NULL, CLSCTX_ALL,
                                  &IID_IFileOperation, (void**)&op);
    if (FAILED(hr) || op == NULL) return FAILED(hr) ? hr : E_FAIL;
    op->lpVtbl->SetOperationFlags(op, FOF_ALLOWUNDO | FOFX_ADDUNDORECORD);
    if (owner != NULL) op->lpVtbl->SetOwnerWindow(op, owner);
    fo_journal_count = 0;
    DWORD cookie = 0;
    /* The advise cookie is never revoked: the op object is released at the
     * end of each body, which drops its reference to the (static) sink. */
    op->lpVtbl->Advise(op, (IFileOperationProgressSink*)&fo_sink, &cookie);
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
        /* Explorer's same-folder rules need to know whether every item is
         * being pasted back where it came from: a copy then lands as
         * " - Copy" (FOF_RENAMEONCOLLISION) instead of raising the
         * conflict dialog, and a cut moves nothing at all. */
        int same_parent = 0;
        DWORD count = 0;
        if (SUCCEEDED(items->lpVtbl->GetCount(items, &count)) && count > 0) {
            same_parent = 1;
            for (DWORD i = 0; i < count && same_parent; i++) {
                IShellItem* item = NULL;
                IShellItem* parent = NULL;
                wchar_t* ppath = NULL;
                same_parent = 0;
                if (SUCCEEDED(items->lpVtbl->GetItemAt(items, i, &item))
                    && SUCCEEDED(item->lpVtbl->GetParent(item, &parent))
                    && SUCCEEDED(parent->lpVtbl->GetDisplayName(
                           parent, SIGDN_FILESYSPATH, &ppath))
                    && ppath != NULL) {
                    /* Trailing backslashes differ by source ("C:\" vs a
                     * plain directory); compare with them trimmed, but
                     * never trim a root's. */
                    size_t dl = wcslen(dir), pl = wcslen(ppath);
                    while (dl > 3 && dir[dl - 1] == L'\\') dl--;
                    while (pl > 3 && ppath[pl - 1] == L'\\') pl--;
                    same_parent = dl == pl && _wcsnicmp(dir, ppath, dl) == 0;
                }
                if (ppath != NULL) CoTaskMemFree(ppath);
                if (parent != NULL) parent->lpVtbl->Release(parent);
                if (item != NULL) item->lpVtbl->Release(item);
            }
        }
        if (move && same_parent) {
            /* Cut, pasted in place: Explorer moves nothing and keeps the
             * clipboard. Success, by doing nothing. */
            ok = 1;
        } else {
            if (!move && same_parent) {
                op->lpVtbl->SetOperationFlags(
                    op, FOF_ALLOWUNDO | FOFX_ADDUNDORECORD
                            | FOF_RENAMEONCOLLISION);
            }
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

/* Parses a newline-separated UTF-8 path list into an IShellItemArray.
 * Item arrays are parent-agnostic (unlike GetUIObjectOf, which wants
 * children of one folder), which keeps the contract honest even though a
 * listing's selection does in fact share a parent. Caller releases. */
/* Shared with flwin32_dragdrop.c (drag-out builds its data object from the
 * same array); internal linkage otherwise -- not in the public header. */
IShellItemArray* flwin32_fo_item_array(const char* paths_nl);

IShellItemArray* flwin32_fo_item_array(const char* paths_nl) {
    wchar_t* wide = fo_utf8_to_wide(paths_nl);
    if (wide == NULL) return NULL;

    LPITEMIDLIST pidls[256];
    int count = 0;
    wchar_t* cursor = wide;
    while (cursor != NULL && *cursor != 0 && count < 256) {
        wchar_t* newline = wcschr(cursor, L'\n');
        if (newline != NULL) *newline = 0;
        if (*cursor != 0) {
            LPITEMIDLIST pidl = NULL;
            if (SUCCEEDED(SHParseDisplayName(cursor, NULL, &pidl, 0, NULL))) {
                pidls[count++] = pidl;
            }
        }
        cursor = newline != NULL ? newline + 1 : NULL;
    }
    free(wide);
    if (count == 0) return NULL;

    IShellItemArray* items = NULL;
    HRESULT hr = SHCreateShellItemArrayFromIDLists(
        (UINT)count, (LPCITEMIDLIST*)pidls, &items);
    for (int i = 0; i < count; i++) CoTaskMemFree(pidls[i]);
    return SUCCEEDED(hr) ? items : NULL;
}

/* Delete a SELECTION to the recycle bin: one IFileOperation over the whole
 * set, so it is one progress dialog, one confirmation, and one entry in
 * the undo stack -- exactly what Explorer does with a multi-selection,
 * and what N separate operations would not be. */
typedef struct {
    const char* paths;
    HWND owner;
} FoDeleteMultiArgs;

static int fo_delete_multi_body(void* arg) {
    FoDeleteMultiArgs* a = (FoDeleteMultiArgs*)arg;
    int ok = 0;
    IShellItemArray* items = flwin32_fo_item_array(a->paths);
    IFileOperation* op = NULL;
    if (items != NULL && SUCCEEDED(fo_create(a->owner, &op))) {
        if (SUCCEEDED(op->lpVtbl->DeleteItems(op, (IUnknown*)items))
            && SUCCEEDED(op->lpVtbl->PerformOperations(op))) {
            ok = 1;
        }
    }
    if (op != NULL) op->lpVtbl->Release(op);
    if (items != NULL) items->lpVtbl->Release(items);
    return ok;
}

int32_t flwin32_fileop_delete_multi(const char* paths_nl, uint64_t owner) {
    if (paths_nl == NULL || paths_nl[0] == 0) return 0;
    FoDeleteMultiArgs args = { paths_nl, (HWND)(ULONG_PTR)owner };
    return fo_run_sta(fo_delete_multi_body, &args);
}

/* Put a SELECTION on the clipboard as one copy or cut. The data object is
 * the item array's own (BHID_DataObject), carrying every item, with the
 * preferred drop effect written over it -- the multi-item twin of
 * flwin32_fileop_clip, and pasting it lands the whole selection. */
typedef struct {
    const char* paths;
    int is_cut;
} FoClipMultiArgs;

static int fo_clip_multi_body(void* arg) {
    FoClipMultiArgs* a = (FoClipMultiArgs*)arg;
    int ok = 0;
    IShellItemArray* items = flwin32_fo_item_array(a->paths);
    if (items == NULL) return 0;

    IDataObject* data = NULL;
    if (SUCCEEDED(items->lpVtbl->BindToHandler(items, NULL, &BHID_DataObject,
                                               &IID_IDataObject,
                                               (void**)&data)) && data != NULL) {
        FORMATETC fmt = {
            (CLIPFORMAT)RegisterClipboardFormatW(CFSTR_PREFERREDDROPEFFECT),
            NULL, DVASPECT_CONTENT, -1, TYMED_HGLOBAL };
        HGLOBAL mem = GlobalAlloc(GMEM_MOVEABLE, sizeof(DWORD));
        if (mem != NULL) {
            DWORD* value = (DWORD*)GlobalLock(mem);
            if (value != NULL) {
                *value = a->is_cut ? DROPEFFECT_MOVE : DROPEFFECT_COPY;
                GlobalUnlock(mem);
                STGMEDIUM medium;
                medium.tymed = TYMED_HGLOBAL;
                medium.hGlobal = mem;
                medium.pUnkForRelease = NULL;
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
    items->lpVtbl->Release(items);
    return ok;
}

int32_t flwin32_fileop_clip_multi(const char* paths_nl, int32_t is_cut) {
    if (paths_nl == NULL || paths_nl[0] == 0) return 0;
    FoClipMultiArgs args = { paths_nl, is_cut };
    return fo_run_sta(fo_clip_multi_body, &args);
}

/* Create one folder. The NAME is the caller's problem on purpose:
 * IFileOperation::NewItem does not auto-unique a colliding name the way
 * Explorer's New does, and the caller needs to know the final name anyway
 * -- Explorer follows a create immediately with an inline rename, and a
 * rename needs a path. So the Swift side picks "New folder (2)" itself and
 * hands the settled name down. */
typedef struct {
    wchar_t* dir;
    wchar_t* name;
    HWND owner;
} FoNewFolderArgs;

static int fo_new_folder_body(void* arg) {
    FoNewFolderArgs* a = (FoNewFolderArgs*)arg;
    int ok = 0;
    IShellItem* parent = NULL;
    IFileOperation* op = NULL;
    if (SUCCEEDED(SHCreateItemFromParsingName(a->dir, NULL, &IID_IShellItem,
                                              (void**)&parent))
        && SUCCEEDED(fo_create(a->owner, &op))) {
        if (SUCCEEDED(op->lpVtbl->NewItem(op, parent, FILE_ATTRIBUTE_DIRECTORY,
                                          a->name, NULL, NULL))
            && SUCCEEDED(op->lpVtbl->PerformOperations(op))) {
            ok = 1;
        }
    }
    if (op != NULL) op->lpVtbl->Release(op);
    if (parent != NULL) parent->lpVtbl->Release(parent);
    return ok;
}

int32_t flwin32_fileop_new_folder(const char* dir, const char* name,
                                  uint64_t owner) {
    if (dir == NULL || dir[0] == 0 || name == NULL || name[0] == 0) return 0;
    FoNewFolderArgs args;
    args.dir = fo_utf8_to_wide(dir);
    args.name = fo_utf8_to_wide(name);
    args.owner = (HWND)(ULONG_PTR)owner;
    if (args.dir == NULL || args.name == NULL) {
        free(args.dir);
        free(args.name);
        return 0;
    }
    int ok = fo_run_sta(fo_new_folder_body, &args);
    free(args.dir);
    free(args.name);
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

/* Copy or move a set of files into a directory -- the landing half of drag
 * and drop, and deliberately the same machinery as everything above: one
 * IFileOperation over the whole set, so a forty-file drop is one progress
 * dialog and one undo entry. */
typedef struct {
    const char* paths;
    wchar_t* dir;
    int move;
    HWND owner;
} FoTransferArgs;

static int fo_transfer_body(void* arg) {
    FoTransferArgs* a = (FoTransferArgs*)arg;
    int ok = 0;
    IShellItemArray* items = flwin32_fo_item_array(a->paths);
    if (items == NULL) return 0;

    IShellItem* target = NULL;
    IFileOperation* op = NULL;
    if (SUCCEEDED(SHCreateItemFromParsingName(a->dir, NULL, &IID_IShellItem,
                                              (void**)&target))
        && SUCCEEDED(fo_create(a->owner, &op))) {
        HRESULT hr = a->move
            ? op->lpVtbl->MoveItems(op, (IUnknown*)items, target)
            : op->lpVtbl->CopyItems(op, (IUnknown*)items, target);
        if (SUCCEEDED(hr) && SUCCEEDED(op->lpVtbl->PerformOperations(op))) {
            ok = 1;
        }
    }
    if (op != NULL) op->lpVtbl->Release(op);
    if (target != NULL) target->lpVtbl->Release(target);
    items->lpVtbl->Release(items);
    return ok;
}

int32_t flwin32_fileop_transfer(const char* paths_nl, const char* target_dir,
                                int32_t is_move, uint64_t owner) {
    if (paths_nl == NULL || paths_nl[0] == 0) return 0;
    if (target_dir == NULL || target_dir[0] == 0) return 0;
    FoTransferArgs args;
    args.paths = paths_nl;
    args.dir = fo_utf8_to_wide(target_dir);
    if (args.dir == NULL) return 0;
    args.move = is_move != 0;
    args.owner = (HWND)(ULONG_PTR)owner;
    int ok = fo_run_sta(fo_transfer_body, &args);
    free(args.dir);
    return ok;
}

/* ── the undo executors ──────────────────────────────────────────────────
 *
 * The two inverses the journal cannot express through the entry points
 * above. Undoing a rename is a rename and undoing a copy is a delete, but
 * undoing a MOVE needs each item sent back to its own folder under its own
 * name in ONE operation, and undoing a DELETE needs the recycle bin's own
 * restore verb -- moving the $R... slot back by hand would leave the $I
 * record beside it orphaned. */

/* Moves each item back where it came from: one line per item,
 * "current-path<TAB>target-dir<TAB>target-name". One IFileOperation over
 * the whole set -- one progress dialog, one conflict pass -- exactly the
 * shape the forward operation had. */
typedef struct {
    const char* lines;
    HWND owner;
} FoUndoMovesArgs;

static int fo_undo_moves_body(void* arg) {
    FoUndoMovesArgs* a = (FoUndoMovesArgs*)arg;
    wchar_t* wide = fo_utf8_to_wide(a->lines);
    if (wide == NULL) return 0;

    int ok = 0;
    int queued = 0;
    IFileOperation* op = NULL;
    if (SUCCEEDED(fo_create(a->owner, &op))) {
        wchar_t* cursor = wide;
        while (cursor != NULL && *cursor != 0) {
            wchar_t* newline = wcschr(cursor, L'\n');
            if (newline != NULL) *newline = 0;
            wchar_t* tab1 = wcschr(cursor, L'\t');
            wchar_t* tab2 = tab1 != NULL ? wcschr(tab1 + 1, L'\t') : NULL;
            if (tab1 != NULL && tab2 != NULL) {
                *tab1 = 0;
                *tab2 = 0;
                IShellItem* item = NULL;
                IShellItem* dir = NULL;
                if (SUCCEEDED(SHCreateItemFromParsingName(
                        cursor, NULL, &IID_IShellItem, (void**)&item))
                    && SUCCEEDED(SHCreateItemFromParsingName(
                        tab1 + 1, NULL, &IID_IShellItem, (void**)&dir))) {
                    if (SUCCEEDED(op->lpVtbl->MoveItem(op, item, dir,
                                                       tab2 + 1, NULL))) {
                        queued++;
                    }
                }
                if (dir != NULL) dir->lpVtbl->Release(dir);
                if (item != NULL) item->lpVtbl->Release(item);
            }
            cursor = newline != NULL ? newline + 1 : NULL;
        }
        if (queued > 0 && SUCCEEDED(op->lpVtbl->PerformOperations(op))) {
            ok = 1;
        }
    }
    if (op != NULL) op->lpVtbl->Release(op);
    free(wide);
    return ok;
}

int32_t flwin32_fileop_undo_moves(const char* lines_nl, uint64_t owner) {
    if (lines_nl == NULL || lines_nl[0] == 0) return 0;
    FoUndoMovesArgs args = { lines_nl, (HWND)(ULONG_PTR)owner };
    return fo_run_sta(fo_undo_moves_body, &args);
}

/* Restores recycled items by their $R... slot paths -- the `dst` a delete
 * record carries -- through the bin's own "undelete" verb, which is the
 * only whole restore: it moves the slot back to the original location AND
 * retires the $I record that names it. Addressed by ENUMERATION, the same
 * lesson flwin32_shellmenu.c's resolve_item paid for: no string parses to
 * a bin item, so the folder is walked and children matched by parsing name.
 * Classic IShellFolder here rather than IShellItem, because GetUIObjectOf
 * wants child pidls of one folder -- and it takes ALL the matches at once,
 * so a ten-item restore is one verb, one conflict pass. */
typedef struct {
    const char* paths;
    HWND owner;
} FoBinRestoreArgs;

static int fo_bin_restore_body(void* arg) {
    FoBinRestoreArgs* a = (FoBinRestoreArgs*)arg;
    wchar_t* wanted = fo_utf8_to_wide(a->paths);
    if (wanted == NULL) return 0;

    int ok = 0;
    LPITEMIDLIST bin_pidl = NULL;
    IShellFolder* bin = NULL;
    IEnumIDList* iter = NULL;
    LPITEMIDLIST matched[256];
    int matched_count = 0;

    if (SUCCEEDED(SHParseDisplayName(
            L"::{645FF040-5081-101B-9F08-00AA002F954E}", NULL, &bin_pidl, 0,
            NULL))
        && SUCCEEDED(SHBindToObject(NULL, bin_pidl, NULL, &IID_IShellFolder,
                                    (void**)&bin))
        && SUCCEEDED(bin->lpVtbl->EnumObjects(
               bin, NULL, SHCONTF_FOLDERS | SHCONTF_NONFOLDERS, &iter))
        && iter != NULL) {
        LPITEMIDLIST child = NULL;
        while (matched_count < 256
               && iter->lpVtbl->Next(iter, 1, &child, NULL) == S_OK) {
            STRRET ret;
            wchar_t name[1024];
            int keep = 0;
            if (SUCCEEDED(bin->lpVtbl->GetDisplayNameOf(
                    bin, child, SHGDN_FORPARSING, &ret))
                && SUCCEEDED(StrRetToBufW(&ret, child, name, 1024))) {
                const wchar_t* line = wanted;
                while (line != NULL && *line != 0 && !keep) {
                    const wchar_t* end = wcschr(line, L'\n');
                    size_t len = end != NULL ? (size_t)(end - line)
                                             : wcslen(line);
                    keep = wcslen(name) == len
                        && _wcsnicmp(name, line, len) == 0;
                    line = end != NULL ? end + 1 : NULL;
                }
            }
            if (keep) {
                matched[matched_count++] = child;
            } else {
                CoTaskMemFree(child);
            }
        }

        if (matched_count > 0) {
            IContextMenu* cm = NULL;
            if (SUCCEEDED(bin->lpVtbl->GetUIObjectOf(
                    bin, a->owner, (UINT)matched_count,
                    (LPCITEMIDLIST*)matched, &IID_IContextMenu, NULL,
                    (void**)&cm)) && cm != NULL) {
                /* QueryContextMenu before InvokeCommand: handlers may build
                 * their verb table there, and the bin's is one of them. */
                HMENU menu = CreatePopupMenu();
                if (menu != NULL) {
                    cm->lpVtbl->QueryContextMenu(cm, menu, 0, 1, 0x7000,
                                                 CMF_NORMAL);
                    CMINVOKECOMMANDINFO info;
                    ZeroMemory(&info, sizeof(info));
                    info.cbSize = sizeof(info);
                    info.hwnd = a->owner;
                    info.lpVerb = "undelete";
                    info.nShow = SW_SHOWNORMAL;
                    if (SUCCEEDED(cm->lpVtbl->InvokeCommand(cm, &info))) {
                        ok = 1;
                    }
                    DestroyMenu(menu);
                }
                cm->lpVtbl->Release(cm);
            }
        }
    }

    for (int i = 0; i < matched_count; i++) CoTaskMemFree(matched[i]);
    if (iter != NULL) iter->lpVtbl->Release(iter);
    if (bin != NULL) bin->lpVtbl->Release(bin);
    if (bin_pidl != NULL) CoTaskMemFree(bin_pidl);
    free(wanted);
    return ok;
}

int32_t flwin32_fileop_bin_restore(const char* slot_paths_nl,
                                   uint64_t owner) {
    if (slot_paths_nl == NULL || slot_paths_nl[0] == 0) return 0;
    FoBinRestoreArgs args = { slot_paths_nl, (HWND)(ULONG_PTR)owner };
    return fo_run_sta(fo_bin_restore_body, &args);
}
