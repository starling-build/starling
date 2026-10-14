// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/*
 * flwin32_clipboard.c -- the system clipboard for the Win32 host.
 *
 * Deliberately plain ASCII throughout, comments included: this tree has a long
 * history of MSVC/PowerShell trouble with non-ASCII bytes, and a clipboard
 * shim is not the place to find another one.
 *
 * Win32's clipboard is a handoff, not a negotiation: the data is copied into
 * global memory at set time and read straight back at get time. So unlike the
 * Wayland and GTK backends there is no owner to ask, nothing to wait on, and
 * no way for another process to stall a paste -- which is why this is
 * synchronous and needs no thread of its own.
 *
 * Rich flavours (HTML, RTF, PNG) are plain bytes under a registered format
 * name; CF_HTML's header is written and stripped on the Swift side
 * (Win32ClipboardProvider.swift), where strings are easier.
 */

#include <windows.h>
#include <string.h>

#include "include/FlutterWin32Bridge.h"

int32_t flwin32_clipboard_set_text(const char* text) {
    if (!text) return 0;

    /* Size first: the count includes the terminator. */
    int wlen = MultiByteToWideChar(CP_UTF8, 0, text, -1, NULL, 0);
    if (wlen <= 0) return 0;

    if (!OpenClipboard(NULL)) return 0;
    EmptyClipboard();

    HGLOBAL block = GlobalAlloc(GMEM_MOVEABLE, (SIZE_T)wlen * sizeof(WCHAR));
    if (!block) {
        CloseClipboard();
        return 0;
    }
    WCHAR* dst = (WCHAR*)GlobalLock(block);
    if (!dst) {
        GlobalFree(block);
        CloseClipboard();
        return 0;
    }
    MultiByteToWideChar(CP_UTF8, 0, text, -1, dst, wlen);
    GlobalUnlock(block);

    /* SetClipboardData takes ownership on success -- freeing the block after
     * that hands the clipboard a dangling handle. On failure it is still ours
     * and must be released here. */
    if (!SetClipboardData(CF_UNICODETEXT, block)) {
        GlobalFree(block);
        CloseClipboard();
        return 0;
    }
    CloseClipboard();
    return 1;
}

/* Several flavours at once: begin (open + empty), put each, end (close).
 * Office, browsers and mail clients each take the richest they read --
 * "HTML Format" for a table with its formatting, "Rich Text Format", "PNG" --
 * and plain text is there for everything else. */
static int fl_clip_open = 0;

int32_t flwin32_clipboard_begin(void) {
    if (fl_clip_open) return 1;
    if (!OpenClipboard(NULL)) return 0;
    EmptyClipboard();
    fl_clip_open = 1;
    return 1;
}

static int32_t fl_clip_put_block(UINT format, const void* bytes, SIZE_T len) {
    HGLOBAL block = GlobalAlloc(GMEM_MOVEABLE, len ? len : 1);
    if (!block) return 0;
    void* dst = GlobalLock(block);
    if (!dst) { GlobalFree(block); return 0; }
    if (len) memcpy(dst, bytes, len);
    GlobalUnlock(block);
    /* Ownership passes to the clipboard on success only (see set_text). */
    if (!SetClipboardData(format, block)) { GlobalFree(block); return 0; }
    return 1;
}

int32_t flwin32_clipboard_put(const char* format, const uint8_t* bytes, int32_t len) {
    if (!fl_clip_open || len < 0) return 0;
    if (!format) {
        /* Plain text: UTF-8 bytes in, UTF-16 with a terminator out. */
        int wlen = MultiByteToWideChar(CP_UTF8, 0, (const char*)bytes, len, NULL, 0);
        if (wlen < 0) return 0;
        WCHAR* w = (WCHAR*)HeapAlloc(GetProcessHeap(), 0, ((SIZE_T)wlen + 1) * sizeof(WCHAR));
        if (!w) return 0;
        if (wlen) MultiByteToWideChar(CP_UTF8, 0, (const char*)bytes, len, w, wlen);
        w[wlen] = 0;
        int32_t ok = fl_clip_put_block(CF_UNICODETEXT, w, ((SIZE_T)wlen + 1) * sizeof(WCHAR));
        HeapFree(GetProcessHeap(), 0, w);
        return ok;
    }
    UINT id = RegisterClipboardFormatA(format);
    if (!id) return 0;
    return fl_clip_put_block(id, bytes, (SIZE_T)len);
}

void flwin32_clipboard_end(void) {
    if (!fl_clip_open) return;
    CloseClipboard();
    fl_clip_open = 0;
}

int32_t flwin32_clipboard_get_format(const char* format, uint8_t* out, int32_t out_size) {
    if (!format) return 0;
    UINT id = RegisterClipboardFormatA(format);
    if (!id || !IsClipboardFormatAvailable(id)) return 0;
    if (!OpenClipboard(NULL)) return 0;
    HANDLE handle = GetClipboardData(id);
    if (!handle) { CloseClipboard(); return 0; }
    SIZE_T size = GlobalSize(handle);
    const uint8_t* src = (const uint8_t*)GlobalLock(handle);
    int32_t result;
    if (!src || size == 0 || size > 0x7FFFFFFF) {
        result = 0;
    } else if (!out || (SIZE_T)out_size < size) {
        result = -(int32_t)size;     /* caller retries with this many bytes */
    } else {
        memcpy(out, src, size);
        result = (int32_t)size;
    }
    if (src) GlobalUnlock(handle);
    CloseClipboard();
    return result;
}

int32_t flwin32_clipboard_get_text(char* out, int32_t out_size) {
    if (!out || out_size <= 0) return -1;
    out[0] = '\0';

    if (!IsClipboardFormatAvailable(CF_UNICODETEXT)) return 0;
    if (!OpenClipboard(NULL)) return 0;

    /* The handle belongs to the clipboard: lock and copy, never free it. */
    HANDLE handle = GetClipboardData(CF_UNICODETEXT);
    if (!handle) {
        CloseClipboard();
        return 0;
    }
    const WCHAR* src = (const WCHAR*)GlobalLock(handle);
    if (!src) {
        CloseClipboard();
        return 0;
    }

    int32_t result;
    int need = WideCharToMultiByte(CP_UTF8, 0, src, -1, NULL, 0, NULL, NULL);
    if (need <= 0) {
        result = 0;
    } else if (need > out_size) {
        result = -1;                 /* caller retries with a bigger buffer */
    } else {
        result = (int32_t)WideCharToMultiByte(CP_UTF8, 0, src, -1,
                                              out, out_size, NULL, NULL);
    }

    GlobalUnlock(handle);
    CloseClipboard();
    return result;
}
