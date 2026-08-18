// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/*
 * flwin32_icon.c -- an application's own icon, as RGBA pixels.
 *
 * A dock that draws a guessed glyph per app is a mock-up; a dock that draws
 * the app's real icon is a dock. On Linux the shell gets there by reading a
 * path out of a .desktop file and decoding a PNG. Windows keeps the icon
 * inside the executable, or inside the window, and hands it out as an HICON --
 * a GDI object, not an image -- so getting pixels means rasterizing it
 * ourselves.
 *
 * Plain ASCII throughout, comments included, for the same reason as
 * flwin32_clipboard.c.
 *
 * Two things here are worth knowing before changing any of it:
 *
 *  1. WM_GETICON is a message to ANOTHER PROCESS, and a shell that sends it
 *     with SendMessage inherits every hung app's hang. SendMessageTimeoutW
 *     with SMTO_ABORTIFHUNG is the only safe spelling, and the timeout has to
 *     be short: this runs while the window list is being rebuilt.
 *
 *  2. DrawIconEx into a zeroed 32-bit DIB gives premultiplied RGBA for a
 *     modern icon and a FULLY TRANSPARENT image for a legacy one, because a
 *     pre-XP icon carries no alpha channel at all and GDI leaves those bytes
 *     alone. The result looks like "the icon failed to load" rather than like
 *     a format problem. The mask pass below is what rescues those.
 */

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <windows.h>
#include <shellapi.h>  /* ExtractIconExW */
#include <stdlib.h>
#include <string.h>

#include "include/FlutterWin32Bridge.h"

/* The window's own icon. Borrowed -- owned by the window or its class, so it
 * must NOT be destroyed. *owned is set when the fallback path had to load one
 * out of the executable, which the caller then does own. */
static HICON icon_for_window(HWND hwnd, int* owned) {
    *owned = 0;
    DWORD_PTR result = 0;

    /* ICON_SMALL2 before ICON_BIG: the shell asks for it at taskbar size, and
     * unlike ICON_SMALL, Windows synthesizes one from the class icon when the
     * window has none of its own. */
    const WPARAM which[] = {ICON_SMALL2, ICON_BIG, ICON_SMALL};
    for (int i = 0; i < 3; i++) {
        if (SendMessageTimeoutW(hwnd, WM_GETICON, which[i], 0,
                                SMTO_ABORTIFHUNG, 120, &result) &&
            result != 0) {
            return (HICON)result;
        }
    }

    HICON from_class = (HICON)GetClassLongPtrW(hwnd, GCLP_HICON);
    if (from_class == NULL) {
        from_class = (HICON)GetClassLongPtrW(hwnd, GCLP_HICONSM);
    }
    if (from_class != NULL) return from_class;

    /* Nothing on the window: go to the executable. Electron and Java windows
     * routinely land here, and it is the icon Explorer shows for them too. */
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    if (pid == 0) return NULL;
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (process == NULL) return NULL;
    wchar_t path[MAX_PATH];
    DWORD len = MAX_PATH;
    /* Not `large`/`small`: rpcndr.h, which windows.h drags in, has
     * `#define small char`, so a local of that name fails to parse with an
     * error that points at the SDK header rather than at this line. */
    HICON icon_large = NULL, icon_small = NULL;
    if (QueryFullProcessImageNameW(process, 0, path, &len)) {
        ExtractIconExW(path, 0, &icon_large, &icon_small, 1);
    }
    CloseHandle(process);
    if (icon_large != NULL) {
        if (icon_small != NULL) DestroyIcon(icon_small);
        *owned = 1;
        return icon_large;
    }
    if (icon_small != NULL) {
        *owned = 1;
        return icon_small;
    }
    return NULL;
}

/* A top-down 32bpp DIB of the given side, with the icon drawn into it by the
 * given DrawIconEx flags. Returns the bitmap and its bits, or NULL. */
static HBITMAP draw_icon_dib(HICON icon, int size, UINT flags, void** out_bits) {
    BITMAPINFO info;
    memset(&info, 0, sizeof(info));
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = size;
    info.bmiHeader.biHeight = -size;  /* negative: top-down, like everyone else */
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;

    HDC screen = GetDC(NULL);
    if (screen == NULL) return NULL;
    HDC mem = CreateCompatibleDC(screen);
    if (mem == NULL) {
        ReleaseDC(NULL, screen);
        return NULL;
    }
    void* bits = NULL;
    HBITMAP dib = CreateDIBSection(screen, &info, DIB_RGB_COLORS, &bits, NULL, 0);
    if (dib != NULL && bits != NULL) {
        HGDIOBJ previous = SelectObject(mem, dib);
        /* CreateDIBSection hands back zeroed memory, which is what makes the
         * DI_NORMAL blend produce premultiplied colour over transparency. */
        DrawIconEx(mem, 0, 0, icon, size, size, 0, NULL, flags);
        SelectObject(mem, previous);
        GdiFlush();  /* the bits are written by the GDI batch, not by us */
    } else if (dib != NULL) {
        DeleteObject(dib);
        dib = NULL;
    }
    DeleteDC(mem);
    ReleaseDC(NULL, screen);
    *out_bits = bits;
    return dib;
}

int32_t flwin32_icon_rasterize(uint64_t window,
                               int32_t size,
                               uint8_t** out_pixels,
                               int32_t* out_width,
                               int32_t* out_height) {
    HWND hwnd = (HWND)(uintptr_t)window;
    if (hwnd == NULL || !IsWindow(hwnd) || out_pixels == NULL) return 0;
    if (size <= 0 || size > 512) size = 32;

    int owned = 0;
    HICON icon = icon_for_window(hwnd, &owned);
    if (icon == NULL) return 0;

    void* colour_bits = NULL;
    HBITMAP colour = draw_icon_dib(icon, size, DI_NORMAL, &colour_bits);
    if (colour == NULL || colour_bits == NULL) {
        if (colour != NULL) DeleteObject(colour);
        if (owned) DestroyIcon(icon);
        return 0;
    }

    const size_t count = (size_t)size * (size_t)size;
    uint8_t* src = (uint8_t*)colour_bits;

    /* Trap 2: a legacy icon leaves every alpha byte at zero, and the image
     * would composite as nothing. Rebuild the alpha from the AND mask, where
     * white means "let the background through". */
    int has_alpha = 0;
    for (size_t i = 0; i < count; i++) {
        if (src[i * 4 + 3] != 0) { has_alpha = 1; break; }
    }
    uint8_t* mask_bits = NULL;
    HBITMAP mask = NULL;
    if (!has_alpha) {
        void* bits = NULL;
        mask = draw_icon_dib(icon, size, DI_MASK, &bits);
        mask_bits = (uint8_t*)bits;
    }

    uint8_t* out = (uint8_t*)malloc(count * 4);
    if (out == NULL) {
        DeleteObject(colour);
        if (mask != NULL) DeleteObject(mask);
        if (owned) DestroyIcon(icon);
        return 0;
    }

    /* GDI's 32bpp is B,G,R,A in memory; the engine's pixel buffer is RGBA. */
    for (size_t i = 0; i < count; i++) {
        uint8_t b = src[i * 4 + 0];
        uint8_t g = src[i * 4 + 1];
        uint8_t r = src[i * 4 + 2];
        uint8_t a = src[i * 4 + 3];
        if (!has_alpha) {
            /* The mask is drawn as black/white; anything not white is opaque. */
            a = (mask_bits != NULL && mask_bits[i * 4 + 0] > 127) ? 0 : 255;
            /* DI_NORMAL over a zeroed destination already left the colour
             * multiplied by nothing, so premultiply by the alpha we just
             * decided -- which for 0/255 means clearing the transparent
             * pixels rather than leaving black fringes around the glyph. */
            if (a == 0) { r = g = b = 0; }
        }
        out[i * 4 + 0] = r;
        out[i * 4 + 1] = g;
        out[i * 4 + 2] = b;
        out[i * 4 + 3] = a;
    }

    DeleteObject(colour);
    if (mask != NULL) DeleteObject(mask);
    if (owned) DestroyIcon(icon);

    *out_pixels = out;
    if (out_width != NULL) *out_width = size;
    if (out_height != NULL) *out_height = size;
    return 1;
}

void flwin32_icon_free(uint8_t* pixels) {
    free(pixels);
}
