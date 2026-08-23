// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/*
 * flwin32_dragdrop.c -- the window as an OLE drop target.
 *
 * The landing half of drag and drop: files dragged out of any drag source
 * (native Explorer, a browser's download, another of our windows) can be
 * dropped on the host window. This file owns the OLE protocol -- the
 * IDropTarget vtable, the data-object plumbing, coordinate conversion --
 * and hands the UI four simple callbacks in LOGICAL client coordinates:
 * enter (with the dragged paths), over, leave, drop. What the UI returns
 * from enter/over is the effect to show (none/copy/move), because only the
 * UI knows what is under the pointer -- a folder row takes a drop, the
 * sidebar's Home does not.
 *
 * The DROP ITSELF IS NOT PERFORMED HERE. The callback gets the paths and
 * the final effect and routes them to flwin32_fileop_transfer on a worker;
 * doing the IFileOperation from inside IDropTarget::Drop would run the
 * shell's progress dialog from the UI thread's pump, and a big copy would
 * freeze the window that accepted it.
 *
 * Paths are extracted from CF_HDROP once, at DragEnter. A data object with
 * no CF_HDROP (dragged text, an Outlook attachment) refuses the whole drag
 * with DROPEFFECT_NONE -- honest, since the transfer op below could not
 * land it anyway.
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
#include <ole2.h>
#include <shellapi.h>
#include <shlobj.h>
#include <stdlib.h>
#include <string.h>

#include "include/FlutterWin32Bridge.h"

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")

typedef struct {
    IDropTargetVtbl* lpVtbl;
    LONG refs;
    HWND hwnd;
    FlWin32DropEnterCallback on_enter;
    FlWin32DropOverCallback on_over;
    FlWin32DropLeaveCallback on_leave;
    FlWin32DropDropCallback on_drop;
    void* user;
    char* paths;        /* the current drag's files, "\n"-joined UTF-8 */
    DWORD last_effect;  /* what the UI last chose, reported by Drop */
} DropTarget;

static char* dd_wide_to_utf8(const wchar_t* wide) {
    int n = WideCharToMultiByte(CP_UTF8, 0, wide, -1, NULL, 0, NULL, NULL);
    if (n <= 0) return NULL;
    char* out = (char*)malloc((size_t)n);
    if (out == NULL) return NULL;
    WideCharToMultiByte(CP_UTF8, 0, wide, -1, out, n, NULL, NULL);
    return out;
}

/* The dragged files, "\n"-joined, or NULL when the data object carries no
 * CF_HDROP. Extracted once per drag: GetData renders the format, which for
 * some sources (a zip folder, an MTP device) is not free. */
static char* dd_paths_from(IDataObject* data) {
    FORMATETC fmt = { CF_HDROP, NULL, DVASPECT_CONTENT, -1, TYMED_HGLOBAL };
    STGMEDIUM medium;
    if (FAILED(data->lpVtbl->GetData(data, &fmt, &medium))) return NULL;

    char* joined = NULL;
    HDROP drop = (HDROP)GlobalLock(medium.hGlobal);
    if (drop != NULL) {
        UINT count = DragQueryFileW(drop, 0xFFFFFFFF, NULL, 0);
        size_t used = 0, cap = 0;
        for (UINT i = 0; i < count; i++) {
            wchar_t wide[MAX_PATH * 2];
            if (DragQueryFileW(drop, i, wide, MAX_PATH * 2) == 0) continue;
            char* utf8 = dd_wide_to_utf8(wide);
            if (utf8 == NULL) continue;
            size_t len = strlen(utf8);
            if (used + len + 2 > cap) {
                cap = (used + len + 2) * 2;
                char* grown = (char*)realloc(joined, cap);
                if (grown == NULL) { free(utf8); break; }
                joined = grown;
            }
            if (used > 0) joined[used++] = '\n';
            memcpy(joined + used, utf8, len + 1);
            used += len;
            free(utf8);
        }
        GlobalUnlock(medium.hGlobal);
    }
    ReleaseStgMedium(&medium);
    return joined;
}

/* Screen POINTL to logical client coordinates -- the UI's own space, so its
 * row arithmetic works unchanged. */
static void dd_point(DropTarget* t, POINTL where, double* x, double* y) {
    POINT p = { where.x, where.y };
    ScreenToClient(t->hwnd, &p);
    UINT dpi = GetDpiForWindow(t->hwnd);
    double scale = dpi > 0 ? (double)dpi / 96.0 : 1.0;
    *x = (double)p.x / scale;
    *y = (double)p.y / scale;
}

static DWORD dd_effect(int32_t choice) {
    if (choice == 1) return DROPEFFECT_COPY;
    if (choice == 2) return DROPEFFECT_MOVE;
    return DROPEFFECT_NONE;
}

static HRESULT STDMETHODCALLTYPE dd_QueryInterface(IDropTarget* self,
                                                   REFIID riid, void** out) {
    if (out == NULL) return E_POINTER;
    if (IsEqualIID(riid, &IID_IUnknown) || IsEqualIID(riid, &IID_IDropTarget)) {
        *out = self;
        self->lpVtbl->AddRef(self);
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE dd_AddRef(IDropTarget* self) {
    return (ULONG)InterlockedIncrement(&((DropTarget*)self)->refs);
}

static ULONG STDMETHODCALLTYPE dd_Release(IDropTarget* self) {
    /* The target lives for the window; the count never really reaches 0. */
    return (ULONG)InterlockedDecrement(&((DropTarget*)self)->refs);
}

static HRESULT STDMETHODCALLTYPE dd_DragEnter(IDropTarget* self,
                                              IDataObject* data,
                                              DWORD keys, POINTL where,
                                              DWORD* effect) {
    DropTarget* t = (DropTarget*)self;
    free(t->paths);
    t->paths = data != NULL ? dd_paths_from(data) : NULL;
    t->last_effect = DROPEFFECT_NONE;
    if (t->paths == NULL) {
        *effect = DROPEFFECT_NONE;
        return S_OK;
    }
    double x, y;
    dd_point(t, where, &x, &y);
    t->last_effect = dd_effect(t->on_enter(t->paths, x, y, keys, t->user));
    *effect = t->last_effect;
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE dd_DragOver(IDropTarget* self, DWORD keys,
                                             POINTL where, DWORD* effect) {
    DropTarget* t = (DropTarget*)self;
    if (t->paths == NULL) {
        *effect = DROPEFFECT_NONE;
        return S_OK;
    }
    double x, y;
    dd_point(t, where, &x, &y);
    t->last_effect = dd_effect(t->on_over(x, y, keys, t->user));
    *effect = t->last_effect;
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE dd_DragLeave(IDropTarget* self) {
    DropTarget* t = (DropTarget*)self;
    free(t->paths);
    t->paths = NULL;
    t->on_leave(t->user);
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE dd_Drop(IDropTarget* self, IDataObject* data,
                                         DWORD keys, POINTL where,
                                         DWORD* effect) {
    DropTarget* t = (DropTarget*)self;
    (void)data;
    if (t->paths == NULL) {
        *effect = DROPEFFECT_NONE;
        return S_OK;
    }
    double x, y;
    dd_point(t, where, &x, &y);
    /* The callback owns what happens next (it copies the paths before
     * returning); the effect reported back to the source is the one the UI
     * last showed, so a move-source knows to expect its files gone. */
    t->on_drop(t->paths, x, y, keys,
               t->last_effect == DROPEFFECT_MOVE ? 1 : 0, t->user);
    *effect = t->last_effect;
    free(t->paths);
    t->paths = NULL;
    return S_OK;
}

static IDropTargetVtbl dd_vtbl = {
    dd_QueryInterface, dd_AddRef, dd_Release,
    dd_DragEnter, dd_DragOver, dd_DragLeave, dd_Drop,
};

static DropTarget dd_target;

int32_t flwin32_dragdrop_register(uint64_t hwnd,
                                  FlWin32DropEnterCallback on_enter,
                                  FlWin32DropOverCallback on_over,
                                  FlWin32DropLeaveCallback on_leave,
                                  FlWin32DropDropCallback on_drop,
                                  void* user) {
    if (hwnd == 0 || on_enter == NULL || on_over == NULL
        || on_leave == NULL || on_drop == NULL) return 0;
    /* RegisterDragDrop wants OLE on the calling thread -- which must be the
     * UI thread, because the callbacks arrive through its message pump.
     * S_FALSE (already initialized) is fine; RPC_E_CHANGED_MODE (someone
     * made this thread MTA) is not. */
    HRESULT ole = OleInitialize(NULL);
    if (FAILED(ole) && ole != RPC_E_CHANGED_MODE) return 0;
    if (ole == RPC_E_CHANGED_MODE) return 0;

    dd_target.lpVtbl = &dd_vtbl;
    dd_target.refs = 1;
    dd_target.hwnd = (HWND)(ULONG_PTR)hwnd;
    dd_target.on_enter = on_enter;
    dd_target.on_over = on_over;
    dd_target.on_leave = on_leave;
    dd_target.on_drop = on_drop;
    dd_target.user = user;
    dd_target.paths = NULL;
    dd_target.last_effect = DROPEFFECT_NONE;
    return SUCCEEDED(RegisterDragDrop(dd_target.hwnd,
                                      (IDropTarget*)&dd_target)) ? 1 : 0;
}

/* ── drag OUT ──────────────────────────────────────────────────────────────
 *
 * The other direction: our rows as an OLE drag source. DoDragDrop blocks
 * and pumps its own modal loop, so this is called on the UI thread, from a
 * deferred hop rather than the middle of pointer dispatch. The data object
 * is the shell's own (BHID_DataObject over the item array), which matters
 * for the move handshake: when Explorer is the target of a MOVE it performs
 * an optimized move -- it relocates the files itself and reports the effect
 * back as NONE precisely so a naive source does not also delete them. We
 * therefore do nothing after the drop but report what happened. */

typedef struct {
    IDropSourceVtbl* lpVtbl;
    LONG refs;
} DragSource;

static HRESULT STDMETHODCALLTYPE ds_QueryInterface(IDropSource* self,
                                                   REFIID riid, void** out) {
    if (out == NULL) return E_POINTER;
    if (IsEqualIID(riid, &IID_IUnknown) || IsEqualIID(riid, &IID_IDropSource)) {
        *out = self;
        self->lpVtbl->AddRef(self);
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE ds_AddRef(IDropSource* self) {
    return (ULONG)InterlockedIncrement(&((DragSource*)self)->refs);
}

static ULONG STDMETHODCALLTYPE ds_Release(IDropSource* self) {
    return (ULONG)InterlockedDecrement(&((DragSource*)self)->refs);
}

static HRESULT STDMETHODCALLTYPE ds_QueryContinueDrag(IDropSource* self,
                                                      BOOL escape,
                                                      DWORD keys) {
    (void)self;
    if (escape) return DRAGDROP_S_CANCEL;
    if (!(keys & MK_LBUTTON)) return DRAGDROP_S_DROP;
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE ds_GiveFeedback(IDropSource* self,
                                                 DWORD effect) {
    (void)self;
    (void)effect;
    return DRAGDROP_S_USEDEFAULTCURSORS;
}

static IDropSourceVtbl ds_vtbl = {
    ds_QueryInterface, ds_AddRef, ds_Release,
    ds_QueryContinueDrag, ds_GiveFeedback,
};

IShellItemArray* flwin32_fo_item_array(const char* paths_nl);

/* Runs a full drag-and-drop of `paths_nl` from the calling (UI) thread.
 * Blocks until the user drops or cancels. Returns what the drop reported:
 * 0 cancelled or none, 1 copy, 2 move -- with the optimized-move caveat
 * above, so 0 after a move onto Explorer is normal and means "done". */
int32_t flwin32_dragdrop_begin(const char* paths_nl) {
    if (paths_nl == NULL || paths_nl[0] == 0) return 0;
    IShellItemArray* items = flwin32_fo_item_array(paths_nl);
    if (items == NULL) return 0;

    int32_t result = 0;
    IDataObject* data = NULL;
    if (SUCCEEDED(items->lpVtbl->BindToHandler(items, NULL, &BHID_DataObject,
                                               &IID_IDataObject,
                                               (void**)&data)) && data != NULL) {
        DragSource source;
        source.lpVtbl = &ds_vtbl;
        source.refs = 1;
        DWORD effect = DROPEFFECT_NONE;
        HRESULT hr = DoDragDrop(data, (IDropSource*)&source,
                                DROPEFFECT_COPY | DROPEFFECT_MOVE
                                    | DROPEFFECT_LINK,
                                &effect);
        if (hr == DRAGDROP_S_DROP) {
            if (effect & DROPEFFECT_MOVE) result = 2;
            else if (effect & DROPEFFECT_COPY) result = 1;
        }
        data->lpVtbl->Release(data);
    }
    items->lpVtbl->Release(items);
    return result;
}
