// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/*
 * flwin32_capture.c -- another window's pixels, as a thumbnail.
 *
 * DWM cannot be replaced, so this shell never owns anyone's pixels. It can
 * still ASK for them, and it has to: a taskbar preview, and later a window
 * overview, are pictures of other people's windows.
 *
 * PrintWindow with PW_RENDERFULLCONTENT, not BitBlt from the screen. BitBlt
 * copies whatever is on the glass, so an occluded window comes back as the
 * window in front of it -- which is exactly the case a preview exists for.
 * PW_RENDERFULLCONTENT is the flag that makes this work for DWM-composited
 * windows at all; without it the modern ones are black.
 *
 * WHAT IT CAPTURES, measured on this machine rather than assumed, because the
 * received wisdom is that GPU-presented windows come back black:
 *
 *   Chromium (Edge)                     full content
 *   Windows Terminal (XAML + D3D)       full content
 *   UWP/XAML (Windows Security)         full content
 *   the desktop                         full content
 *   OUR OWN Flutter window              BLACK
 *
 * So the one thing it cannot photograph is the shell itself, which is the one
 * window a shell never needs a thumbnail of. Windows.Graphics.Capture is the
 * answer for anything that must be continuously live -- it is what OBS uses --
 * and it is a great deal of WinRT for a picture that is redrawn when a preview
 * opens.
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
#include <dwmapi.h>
#include <stdlib.h>

#include "include/FlutterWin32Bridge.h"

#pragma comment(lib, "dwmapi.lib")

#ifndef PW_RENDERFULLCONTENT
#define PW_RENDERFULLCONTENT 0x00000002
#endif

/* A 32bpp top-down DIB and the bits behind it. */
static HBITMAP make_dib(int width, int height, void** bits) {
    BITMAPINFO info;
    ZeroMemory(&info, sizeof(info));
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = width;
    info.bmiHeader.biHeight = -height;  /* top-down: rows in reading order */
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    *bits = NULL;
    return CreateDIBSection(NULL, &info, DIB_RGB_COLORS, bits, NULL, 0);
}

int32_t flwin32_capture_window(uint64_t window,
                               int32_t max_side,
                               uint8_t** out_pixels,
                               int32_t* out_width,
                               int32_t* out_height) {
    HWND hwnd = (HWND)(uintptr_t)window;
    if (hwnd == NULL || !IsWindow(hwnd) || out_pixels == NULL) return 0;
    if (IsIconic(hwnd)) return 0;  /* minimized: nothing to render */

    RECT frame;
    if (!GetWindowRect(hwnd, &frame)) return 0;
    int full_w = frame.right - frame.left;
    int full_h = frame.bottom - frame.top;
    if (full_w < 8 || full_h < 8 || full_w > 16384 || full_h > 16384) return 0;

    /* Windows 10+ puts an INVISIBLE resize border outside the frame the user
     * sees. PrintWindow renders it, so a thumbnail taken from GetWindowRect
     * has a transparent margin on three sides and looks mis-centred. The
     * extended bounds are the real frame; the difference is the crop. */
    RECT visible = frame;
    DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, &visible,
                          sizeof(visible));
    int crop_x = visible.left - frame.left;
    int crop_y = visible.top - frame.top;
    int crop_w = visible.right - visible.left;
    int crop_h = visible.bottom - visible.top;
    if (crop_x < 0 || crop_y < 0 || crop_w < 8 || crop_h < 8 ||
        crop_x + crop_w > full_w || crop_y + crop_h > full_h) {
        crop_x = 0; crop_y = 0; crop_w = full_w; crop_h = full_h;
    }

    if (max_side < 16) max_side = 16;
    double scale = (double)max_side / (double)(crop_w > crop_h ? crop_w : crop_h);
    if (scale > 1.0) scale = 1.0;
    int thumb_w = (int)(crop_w * scale);
    int thumb_h = (int)(crop_h * scale);
    if (thumb_w < 1) thumb_w = 1;
    if (thumb_h < 1) thumb_h = 1;

    HDC screen = GetDC(NULL);
    HDC full_dc = CreateCompatibleDC(screen);
    HDC thumb_dc = CreateCompatibleDC(screen);
    void* full_bits = NULL;
    void* thumb_bits = NULL;
    HBITMAP full_bmp = make_dib(full_w, full_h, &full_bits);
    HBITMAP thumb_bmp = make_dib(thumb_w, thumb_h, &thumb_bits);
    int ok = 0;

    if (full_bmp != NULL && thumb_bmp != NULL && full_bits != NULL &&
        thumb_bits != NULL) {
        HGDIOBJ prev_full = SelectObject(full_dc, full_bmp);
        HGDIOBJ prev_thumb = SelectObject(thumb_dc, thumb_bmp);
        if (PrintWindow(hwnd, full_dc, PW_RENDERFULLCONTENT)) {
            /* HALFTONE is the only StretchBlt mode that averages rather than
             * dropping rows, which at thumbnail scale is the difference
             * between a picture and a moire. */
            SetStretchBltMode(thumb_dc, HALFTONE);
            SetBrushOrgEx(thumb_dc, 0, 0, NULL);
            ok = StretchBlt(thumb_dc, 0, 0, thumb_w, thumb_h, full_dc,
                            crop_x, crop_y, crop_w, crop_h, SRCCOPY);
            GdiFlush();
        }
        SelectObject(full_dc, prev_full);
        SelectObject(thumb_dc, prev_thumb);
    }

    uint8_t* out = NULL;
    if (ok) {
        out = (uint8_t*)malloc((size_t)thumb_w * (size_t)thumb_h * 4);
        if (out != NULL) {
            uint8_t* src = (uint8_t*)thumb_bits;
            /* BOTTOM-UP, despite the negative biHeight on both DIBs.
             *
             * A top-down DIB section is supposed to put row 0 first, and for
             * the icon path it does. Through PrintWindow and StretchBlt it
             * does not: the picture comes out mirrored top to bottom, which
             * on a browser window shows as the tab bar along the BOTTOM of
             * the thumbnail. Read the rows back the way they actually are
             * rather than the way the header says they should be. */
            for (int row = 0; row < thumb_h; row++) {
              const uint8_t* line = src + (size_t)(thumb_h - 1 - row) * (size_t)thumb_w * 4;
              uint8_t* dst = out + (size_t)row * (size_t)thumb_w * 4;
              for (int col = 0; col < thumb_w; col++) {
                dst[col * 4 + 0] = line[col * 4 + 2];
                dst[col * 4 + 1] = line[col * 4 + 1];
                dst[col * 4 + 2] = line[col * 4 + 0];
                dst[col * 4 + 3] = 255;
              }
            }
        } else {
            ok = 0;
        }
    }

    if (full_bmp != NULL) DeleteObject(full_bmp);
    if (thumb_bmp != NULL) DeleteObject(thumb_bmp);
    DeleteDC(full_dc);
    DeleteDC(thumb_dc);
    ReleaseDC(NULL, screen);

    if (!ok || out == NULL) {
        free(out);
        return 0;
    }
    *out_pixels = out;
    if (out_width != NULL) *out_width = thumb_w;
    if (out_height != NULL) *out_height = thumb_h;
    return 1;
}
