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
#include <shobjidl.h>  /* IShellItemImageFactory, for thumbnails */
#include <shlobj.h>
#include <stdlib.h>
#include <string.h>

#pragma comment(lib, "ole32.lib")

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

/* The shared core: an HICON to premultiplied RGBA. `owned` says whether this
 * function should destroy the icon when it is done with it. */
static int32_t rasterize(HICON icon,
                         int owned,
                         int32_t size,
                         uint8_t** out_pixels,
                         int32_t* out_width,
                         int32_t* out_height) {
    if (icon == NULL || out_pixels == NULL) return 0;
    if (size <= 0 || size > 512) size = 32;

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

int32_t flwin32_icon_rasterize(uint64_t window,
                               int32_t size,
                               uint8_t** out_pixels,
                               int32_t* out_width,
                               int32_t* out_height) {
    /* This can run on any thread now, and the shell paths below need an
     * apartment on whichever one it is. */
    flwin32_com_ensure();
    HWND hwnd = (HWND)(uintptr_t)window;
    if (hwnd == NULL || !IsWindow(hwnd)) return 0;
    int owned = 0;
    HICON icon = icon_for_window(hwnd, &owned);
    return rasterize(icon, owned, size, out_pixels, out_width, out_height);
}

int32_t flwin32_icon_rasterize_path(const char* path,
                                    int32_t size,
                                    uint8_t** out_pixels,
                                    int32_t* out_width,
                                    int32_t* out_height) {
    /* This can run on any thread now, and the shell paths below need an
     * apartment on whichever one it is. */
    flwin32_com_ensure();
    if (path == NULL) return 0;
    int n = MultiByteToWideChar(CP_UTF8, 0, path, -1, NULL, 0);
    if (n <= 0) return 0;
    wchar_t* wide = (wchar_t*)calloc((size_t)n, sizeof(wchar_t));
    if (wide == NULL) return 0;
    MultiByteToWideChar(CP_UTF8, 0, path, -1, wide, n);

    /* SHGetFileInfoW rather than ExtractIconEx: the path is usually a .lnk,
     * and a shortcut's icon is a property of the shortcut (it may point at a
     * different file, or carry an overlay) rather than of whatever it starts.
     * This is the icon Explorer draws for that entry. */
    /* A .lnk gets one more chance first: the shortcut's DECLARED icon.
     *
     * SHGetFileInfoW on a shortcut returns the shell's composed icon, which
     * has the little curved ARROW baked into it -- in Explorer that badge
     * means "this is a shortcut", and in a dock it means nothing and every
     * entry wears one. Most shortcuts name an icon file and index outright
     * (File Explorer's points into imageres.dll), and ExtractIconEx on that
     * gives the artwork with no overlay. */
    size_t length = strlen(path);
    if (length > 4 && _stricmp(path + length - 4, ".lnk") == 0) {
        char icon_path[1024];
        int32_t icon_index = 0;
        if (flwin32_shortcut_icon(path, icon_path, 1024, &icon_index) > 0) {
            int n2 = MultiByteToWideChar(CP_UTF8, 0, icon_path, -1, NULL, 0);
            if (n2 > 0) {
                wchar_t* wicon = (wchar_t*)calloc((size_t)n2, sizeof(wchar_t));
                if (wicon != NULL) {
                    MultiByteToWideChar(CP_UTF8, 0, icon_path, -1, wicon, n2);
                    HICON large = NULL, small_icon = NULL;
                    UINT got = ExtractIconExW(wicon, icon_index, &large,
                                              &small_icon, 1);
                    free(wicon);
                    if (got > 0 && (large != NULL || small_icon != NULL)) {
                        HICON chosen = large != NULL ? large : small_icon;
                        if (large != NULL && small_icon != NULL) {
                            DestroyIcon(small_icon);
                        }
                        free(wide);
                        return rasterize(chosen, 1, size, out_pixels,
                                         out_width, out_height);
                    }
                }
            }
        }
    }

    SHFILEINFOW info;
    memset(&info, 0, sizeof(info));
    UINT flags = SHGFI_ICON | (size > 24 ? SHGFI_LARGEICON : SHGFI_SMALLICON);
    DWORD_PTR ok = SHGetFileInfoW(wide, 0, &info, sizeof(info), flags);
    free(wide);
    if (ok == 0 || info.hIcon == NULL) return 0;

    /* SHGetFileInfo's icon is the caller's to destroy. */
    return rasterize(info.hIcon, 1, size, out_pixels, out_width, out_height);
}

int32_t flwin32_icon_rasterize_handle(uint64_t icon,
                                      int32_t size,
                                      uint8_t** out_pixels,
                                      int32_t* out_width,
                                      int32_t* out_height) {
    /* Borrowed, not owned: a tray icon handle belongs to the snapshot that
     * handed it over, and destroying it here would blank the icon the moment
     * the shell drew it. */
    return rasterize((HICON)(uintptr_t)icon, 0, size, out_pixels, out_width,
                     out_height);
}

/* A file's THUMBNAIL -- the picture itself for an image, a frame for a
 * video -- through IShellItemImageFactory, which is the machinery behind
 * Explorer's own thumbnails and its on-disk thumbnail cache: a folder the
 * user has seen in Explorer answers from cache, the same speed Explorer
 * gets. SIIGBF_THUMBNAILONLY on purpose -- a file type with no thumbnail
 * handler FAILS here instead of answering with its icon, and the caller
 * keeps drawing the type icon it already has; asking this for a .txt would
 * just be the slow route to the same picture.
 *
 * The result is LETTERBOXED onto a transparent side-by-side square: the
 * factory preserves aspect (a 3:2 photo comes back 96x64), and the caller's
 * texture slot is square -- stretching is what a wrong thumbnail looks
 * like, and centring is what Explorer does. Same output contract as every
 * rasterizer here: premultiplied RGBA, malloc'd, freed by
 * flwin32_icon_free.
 *
 * COM-inits its own apartment (tolerating a caller's) -- callers are the
 * icon queue's worker, same situation as flwin32_wallpaper_average. */
int32_t flwin32_icon_thumbnail(const char* path, int32_t side,
                               uint8_t** out_pixels, int32_t* out_width,
                               int32_t* out_height) {
    if (path == NULL || path[0] == 0 || side <= 0 || out_pixels == NULL) {
        return 0;
    }
    int n = MultiByteToWideChar(CP_UTF8, 0, path, -1, NULL, 0);
    if (n <= 0) return 0;
    wchar_t* wide = (wchar_t*)calloc((size_t)n, sizeof(wchar_t));
    if (wide == NULL) return 0;
    MultiByteToWideChar(CP_UTF8, 0, path, -1, wide, n);

    HRESULT init = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    int ok = 0;
    IShellItem* item = NULL;
    if (SUCCEEDED(SHCreateItemFromParsingName(wide, NULL, &IID_IShellItem,
                                              (void**)&item))) {
        IShellItemImageFactory* factory = NULL;
        if (SUCCEEDED(item->lpVtbl->QueryInterface(
                item, &IID_IShellItemImageFactory, (void**)&factory))) {
            SIZE want;
            want.cx = side;
            want.cy = side;
            HBITMAP bitmap = NULL;
            if (SUCCEEDED(factory->lpVtbl->GetImage(
                    factory, want,
                    SIIGBF_THUMBNAILONLY | SIIGBF_RESIZETOFIT, &bitmap))
                && bitmap != NULL) {
                BITMAP info;
                if (GetObjectW(bitmap, sizeof(info), &info)
                    && info.bmWidth > 0 && info.bmWidth <= side
                    && info.bmHeight > 0 && info.bmHeight <= side) {
                    int w = info.bmWidth;
                    int h = info.bmHeight;
                    BITMAPINFO bi;
                    ZeroMemory(&bi, sizeof(bi));
                    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
                    bi.bmiHeader.biWidth = w;
                    bi.bmiHeader.biHeight = -h; /* top-down */
                    bi.bmiHeader.biPlanes = 1;
                    bi.bmiHeader.biBitCount = 32;
                    bi.bmiHeader.biCompression = BI_RGB;
                    uint8_t* src = (uint8_t*)malloc((size_t)w * (size_t)h * 4);
                    uint8_t* dst = (uint8_t*)calloc(
                        (size_t)side * (size_t)side, 4);
                    HDC dc = GetDC(NULL);
                    if (src != NULL && dst != NULL && dc != NULL
                        && GetDIBits(dc, bitmap, 0, (UINT)h, src, &bi,
                                     DIB_RGB_COLORS) == h) {
                        /* A photo's DIB routinely reports alpha 0 across
                         * the board (BI_RGB with the fourth byte unused);
                         * all-zero alpha composites as nothing, so it is
                         * rebuilt as opaque. Any nonzero alpha means the
                         * handler really produced transparency, taken as
                         * premultiplied -- which is what DrawIconEx-style
                         * 32bpp DIBs carry. */
                        int has_alpha = 0;
                        for (int i = 0; i < w * h; i++) {
                            if (src[i * 4 + 3] != 0) { has_alpha = 1; break; }
                        }
                        int off_x = (side - w) / 2;
                        int off_y = (side - h) / 2;
                        for (int y = 0; y < h; y++) {
                            for (int x = 0; x < w; x++) {
                                const uint8_t* p = src + ((size_t)y * w + x) * 4;
                                uint8_t* q = dst
                                    + (((size_t)(y + off_y)) * side
                                       + (size_t)(x + off_x)) * 4;
                                q[0] = p[2];             /* B,G,R,A -> RGBA */
                                q[1] = p[1];
                                q[2] = p[0];
                                q[3] = has_alpha ? p[3] : 255;
                            }
                        }
                        *out_pixels = dst;
                        dst = NULL;
                        if (out_width != NULL) *out_width = side;
                        if (out_height != NULL) *out_height = side;
                        ok = 1;
                    }
                    if (dc != NULL) ReleaseDC(NULL, dc);
                    free(src);
                    free(dst);
                }
                DeleteObject(bitmap);
            }
            factory->lpVtbl->Release(factory);
        }
        item->lpVtbl->Release(item);
    }
    free(wide);
    if (init == S_OK || init == S_FALSE) CoUninitialize();
    return ok;
}

/* The wallpaper, rastered to COVER exactly want_w x want_h -- the desktop
 * surface's backdrop. The shell's image factory does the decode (same as
 * the thumbnail above, minus THUMBNAILONLY: the wallpaper is exactly the
 * file we want extracted, at the biggest size the factory will serve), and
 * a HALFTONE StretchBlt does the cover-crop -- scale so the image fills the
 * target, centred, overflow cropped, which is Windows' own "Fill" fit. The
 * factory caps its output (~2560 on this machine's cache tiers), so a 4K
 * target may be an upscale of a 2560 decode; for a photo behind a grid of
 * icons that is invisible, and the VM it must also look right on is 1024
 * wide. Returns opaque RGBA the caller frees with flwin32_icon_free. */
int32_t flwin32_wallpaper_raster(int32_t want_w, int32_t want_h,
                                 uint8_t** out_pixels) {
    if (want_w <= 0 || want_h <= 0 || out_pixels == NULL) return 0;
    wchar_t path[MAX_PATH];
    path[0] = L'\0';
    if (!SystemParametersInfoW(SPI_GETDESKWALLPAPER, MAX_PATH, path, 0)
        || path[0] == L'\0') {
        return 0;
    }

    HRESULT init = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    int ok = 0;
    IShellItem* item = NULL;
    if (SUCCEEDED(SHCreateItemFromParsingName(path, NULL, &IID_IShellItem,
                                              (void**)&item))) {
        IShellItemImageFactory* factory = NULL;
        if (SUCCEEDED(item->lpVtbl->QueryInterface(
                item, &IID_IShellItemImageFactory, (void**)&factory))) {
            SIZE want;
            want.cx = want_w;
            want.cy = want_h;
            HBITMAP bitmap = NULL;
            if (SUCCEEDED(factory->lpVtbl->GetImage(
                    factory, want, SIIGBF_RESIZETOFIT, &bitmap))
                && bitmap != NULL) {
                BITMAP info;
                if (GetObjectW(bitmap, sizeof(info), &info)
                    && info.bmWidth > 0 && info.bmHeight > 0) {
                    int sw = info.bmWidth;
                    int sh = info.bmHeight;
                    /* GetDIBits with a NEGATIVE height request normalizes
                     * the rows to top-down whatever the factory's section
                     * held -- the same contract the thumbnail above leans
                     * on. (A StretchBlt between DIB sections was tried
                     * first and came out vertically flipped: the factory's
                     * sections are top-down, and GDI's blit orientation
                     * semantics between mixed sections are exactly the
                     * kind of thing to stop depending on.) */
                    BITMAPINFO bi;
                    ZeroMemory(&bi, sizeof(bi));
                    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
                    bi.bmiHeader.biWidth = sw;
                    bi.bmiHeader.biHeight = -sh; /* top-down */
                    bi.bmiHeader.biPlanes = 1;
                    bi.bmiHeader.biBitCount = 32;
                    bi.bmiHeader.biCompression = BI_RGB;
                    uint8_t* src = (uint8_t*)malloc((size_t)sw
                                                    * (size_t)sh * 4);
                    HDC dc = GetDC(NULL);
                    if (src != NULL && dc != NULL
                        && GetDIBits(dc, bitmap, 0, (UINT)sh, src, &bi,
                                     DIB_RGB_COLORS) == sh) {
                        /* Cover: sample the target through the scale that
                         * fills it, centred, overflow cropped. Bilinear by
                         * hand -- deterministic, orientation-proof, and a
                         * wallpaper decode runs once per session. */
                        double sx = (double)want_w / sw;
                        double sy = (double)want_h / sh;
                        double scale = sx > sy ? sx : sy;
                        double span_w = (double)want_w / scale;
                        double span_h = (double)want_h / scale;
                        double off_x = ((double)sw - span_w) / 2.0;
                        double off_y = ((double)sh - span_h) / 2.0;
                        uint8_t* dst = (uint8_t*)malloc(
                            (size_t)want_w * (size_t)want_h * 4);
                        if (dst != NULL) {
                            for (int y = 0; y < want_h; y++) {
                                /* Rows read BOTTOM-UP, found empirically:
                                 * this factory's DIB hands GetDIBits rows
                                 * that arrive inverted even against a
                                 * top-down request (the palace hung from
                                 * the sky through two prior "fixes"), so
                                 * the sampler walks the source upside down
                                 * and the output comes out upright. If a
                                 * future wallpaper renders flipped, the
                                 * factory changed its mind -- probe before
                                 * believing either orientation. */
                                double fy = off_y
                                    + ((double)(want_h - 1 - y) + 0.5)
                                      / scale - 0.5;
                                if (fy < 0) fy = 0;
                                if (fy > sh - 1) fy = sh - 1;
                                int y0 = (int)fy;
                                int y1 = y0 + 1 < sh ? y0 + 1 : y0;
                                double wy = fy - y0;
                                uint8_t* q = dst
                                    + (size_t)y * (size_t)want_w * 4;
                                for (int x = 0; x < want_w; x++) {
                                    double fx = off_x
                                        + ((double)x + 0.5) / scale - 0.5;
                                    if (fx < 0) fx = 0;
                                    if (fx > sw - 1) fx = sw - 1;
                                    int x0 = (int)fx;
                                    int x1 = x0 + 1 < sw ? x0 + 1 : x0;
                                    double wx = fx - x0;
                                    const uint8_t* p00 = src
                                        + ((size_t)y0 * sw + x0) * 4;
                                    const uint8_t* p01 = src
                                        + ((size_t)y0 * sw + x1) * 4;
                                    const uint8_t* p10 = src
                                        + ((size_t)y1 * sw + x0) * 4;
                                    const uint8_t* p11 = src
                                        + ((size_t)y1 * sw + x1) * 4;
                                    for (int c = 0; c < 3; c++) {
                                        double top = p00[c] * (1 - wx)
                                            + p01[c] * wx;
                                        double bot = p10[c] * (1 - wx)
                                            + p11[c] * wx;
                                        double v = top * (1 - wy) + bot * wy;
                                        /* BGR -> RGB while writing. */
                                        q[x * 4 + (2 - c)] =
                                            (uint8_t)(v + 0.5);
                                    }
                                    q[x * 4 + 3] = 255;
                                }
                            }
                            *out_pixels = dst;
                            ok = 1;
                        }
                    }
                    if (dc != NULL) ReleaseDC(NULL, dc);
                    free(src);
                }
                DeleteObject(bitmap);
            }
            factory->lpVtbl->Release(factory);
        }
        item->lpVtbl->Release(item);
    }
    if (init == S_OK || init == S_FALSE) CoUninitialize();
    return ok;
}

void flwin32_icon_destroy(uint64_t icon) {
    if (icon != 0) DestroyIcon((HICON)(uintptr_t)icon);
}

void flwin32_icon_free(uint8_t* pixels) {
    free(pixels);
}
