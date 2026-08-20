// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/*
 * flwin32_thumb.c -- live window thumbnails, the way the taskbar does them.
 *
 * The preview card used to be PrintWindow into a DIB, uploaded as an external
 * texture (flwin32_capture.c). That is a PRINTING api doing a compositing
 * job, and every one of its symptoms followed from that: it costs a full
 * re-render of the target window, so it had to be throttled to once a second;
 * a minimized window paints nothing, so it came back empty and needed an icon
 * drawn over the hole; and our own window comes back black.
 *
 * DWM already has those pixels -- it is compositing them right now -- and
 * DwmRegisterThumbnail is the documented way to ask for them. It is what
 * Windows' own taskbar preview is. Live for free, correct for occluded
 * windows, and correct for MINIMIZED ones, because DWM keeps the last frame.
 *
 * WHAT IT COSTS, and it is not nothing: a thumbnail is not a bitmap. DWM
 * composites it into a RECTANGLE OF A DESTINATION WINDOW WE OWN, and we never
 * see a pixel of it. So it cannot live inside the widget tree the way a
 * texture did -- the card draws its own chrome and DWM paints the picture
 * over the top. Anything we wanted to draw ON the thumbnail is no longer
 * possible; anything drawn BEHIND it is simply hidden.
 *
 * The destination is the dock's own panel window, which is WS_EX_LAYERED with
 * a colour key (see flwin32_host.c). Whether DWM will composite a thumbnail
 * onto a layered destination at all is not documented either way, which is
 * what flwin32_thumb_probe is for.
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
#include <stdio.h>

#include "include/FlutterWin32Bridge.h"

#pragma comment(lib, "dwmapi.lib")

int32_t flwin32_thumb_register(uint64_t dest, uint64_t src, uint64_t* out) {
    HTHUMBNAIL thumb = NULL;
    HRESULT hr;
    if (out == NULL) return 0;
    *out = 0;
    if (dest == 0 || src == 0) return 0;
    /* A source that has gone away between the hover and here is ordinary,
     * not exceptional: windows close while a preview is open. */
    if (!IsWindow((HWND)(UINT_PTR)src) || !IsWindow((HWND)(UINT_PTR)dest)) {
        return 0;
    }
    hr = DwmRegisterThumbnail((HWND)(UINT_PTR)dest, (HWND)(UINT_PTR)src, &thumb);
    if (FAILED(hr) || thumb == NULL) return 0;
    *out = (uint64_t)(UINT_PTR)thumb;
    return 1;
}

int32_t flwin32_thumb_place(uint64_t handle,
                            int32_t x,
                            int32_t y,
                            int32_t width,
                            int32_t height,
                            int32_t opacity,
                            int32_t client_only) {
    DWM_THUMBNAIL_PROPERTIES props;
    HRESULT hr;
    if (handle == 0 || width <= 0 || height <= 0) return 0;

    ZeroMemory(&props, sizeof(props));
    /* The destination rectangle is in the DESTINATION WINDOW's client
     * coordinates, in PHYSICAL pixels. The dock lays its card out in logical
     * points, so the caller multiplies by the screen scale before it gets
     * here -- passing points would put the picture at half size on this
     * machine and be exactly right on a 100% one, which is the failure that
     * hides until someone plugs in a second monitor. */
    props.rcDestination.left = x;
    props.rcDestination.top = y;
    props.rcDestination.right = x + width;
    props.rcDestination.bottom = y + height;
    props.opacity = (BYTE)(opacity < 0 ? 0 : (opacity > 255 ? 255 : opacity));
    props.fVisible = TRUE;
    /* Client area only: the source's title bar and border are chrome the card
     * is already drawing for itself, and including them makes every thumbnail
     * a picture of a window rather than of its contents. */
    props.fSourceClientAreaOnly = client_only ? TRUE : FALSE;
    props.dwFlags = DWM_TNP_RECTDESTINATION | DWM_TNP_OPACITY |
                    DWM_TNP_VISIBLE | DWM_TNP_SOURCECLIENTAREAONLY;

    hr = DwmUpdateThumbnailProperties((HTHUMBNAIL)(UINT_PTR)handle, &props);
    return SUCCEEDED(hr) ? 1 : 0;
}

int32_t flwin32_thumb_hide(uint64_t handle) {
    DWM_THUMBNAIL_PROPERTIES props;
    HRESULT hr;
    if (handle == 0) return 0;
    ZeroMemory(&props, sizeof(props));
    props.fVisible = FALSE;
    props.dwFlags = DWM_TNP_VISIBLE;
    hr = DwmUpdateThumbnailProperties((HTHUMBNAIL)(UINT_PTR)handle, &props);
    return SUCCEEDED(hr) ? 1 : 0;
}

int32_t flwin32_thumb_unregister(uint64_t handle) {
    if (handle == 0) return 0;
    return SUCCEEDED(DwmUnregisterThumbnail((HTHUMBNAIL)(UINT_PTR)handle)) ? 1 : 0;
}

/* Takes a THUMBNAIL handle, not a window: DwmQueryThumbnailSourceSize is a
 * property of the registration, and there is no window-only form of it. So a
 * caller asks after registering, which is also when it needs the answer. */
int32_t flwin32_thumb_source_size(uint64_t handle, int32_t* width, int32_t* height) {
    SIZE size;
    if (width == NULL || height == NULL) return 0;
    *width = 0;
    *height = 0;
    if (handle == 0) return 0;
    /* The source's size as DWM sees it, which is what the card needs to fit a
     * thumbnail into its slot without distorting it. Not GetWindowRect: a
     * minimized window's rect is off-screen nonsense, while DWM still knows
     * how big the frame it kept is. */
    if (FAILED(DwmQueryThumbnailSourceSize((HTHUMBNAIL)(UINT_PTR)handle, &size))) {
        return 0;
    }
    *width = (int32_t)size.cx;
    *height = (int32_t)size.cy;
    return 1;
}

/* ------------------------------------------------------------------------ */
/* The probe.                                                               */
/*                                                                          */
/* None of the following is documented and all of it decides whether the    */
/* feature is buildable at all, so it is established on a real machine       */
/* rather than assumed -- the same reason --tray-probe is in the tree:       */
/*                                                                          */
/*   - does DWM composite a thumbnail onto a WS_EX_LAYERED destination, or   */
/*     does the colour key eat it?                                          */
/*   - does it composite onto a plain (unlayered) destination?              */
/*   - does a MINIMIZED source produce a picture, as the taskbar's does?     */
/*                                                                          */
/* Two windows side by side, same source in both, one layered one not.      */
/* ------------------------------------------------------------------------ */

static LRESULT CALLBACK thumb_probe_proc(HWND hwnd, UINT msg, WPARAM w, LPARAM l) {
    if (msg == WM_PAINT) {
        PAINTSTRUCT ps;
        HDC dc = BeginPaint(hwnd, &ps);
        RECT rc;
        HBRUSH brush = CreateSolidBrush(RGB(0x1B, 0x1D, 0x22));
        GetClientRect(hwnd, &rc);
        FillRect(dc, &rc, brush);
        DeleteObject(brush);
        EndPaint(hwnd, &ps);
        return 0;
    }
    return DefWindowProcW(hwnd, msg, w, l);
}

static HWND thumb_probe_window(const wchar_t* cls, int x, int layered) {
    WNDCLASSEXW wc;
    HWND hwnd;
    ZeroMemory(&wc, sizeof(wc));
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = thumb_probe_proc;
    wc.hInstance = GetModuleHandleW(NULL);
    wc.lpszClassName = cls;
    wc.hCursor = LoadCursorW(NULL, IDC_ARROW);
    RegisterClassExW(&wc);

    hwnd = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW, cls, cls,
                           WS_POPUP, x, 200, 520, 340,
                           NULL, NULL, GetModuleHandleW(NULL), NULL);
    if (hwnd == NULL) return NULL;
    if (layered) {
        /* Exactly what the dock does: layered, keyed on pure black. */
        SetWindowLongPtrW(hwnd, GWL_EXSTYLE,
                          GetWindowLongPtrW(hwnd, GWL_EXSTYLE) | WS_EX_LAYERED);
        SetLayeredWindowAttributes(hwnd, RGB(0, 0, 0), 255, LWA_COLORKEY);
    }
    ShowWindow(hwnd, SW_SHOWNOACTIVATE);
    UpdateWindow(hwnd);
    return hwnd;
}

void flwin32_thumb_probe(uint64_t src, int32_t seconds) {
    HWND plain, layered;
    uint64_t t_plain = 0, t_layered = 0;
    int32_t sw = 0, sh = 0;
    DWORD ticks;

    if (src == 0 || !IsWindow((HWND)(UINT_PTR)src)) {
        wprintf(L"[thumb-probe] no such source window\n");
        return;
    }

    wprintf(L"[thumb-probe] source hwnd=0x%llX minimized=%d\n",
            (unsigned long long)src, IsIconic((HWND)(UINT_PTR)src) ? 1 : 0);

    plain = thumb_probe_window(L"StarlingThumbProbePlain", 200, 0);
    layered = thumb_probe_window(L"StarlingThumbProbeLayered", 760, 1);
    wprintf(L"[thumb-probe] dest plain=0x%llX layered=0x%llX\n",
            (unsigned long long)(UINT_PTR)plain,
            (unsigned long long)(UINT_PTR)layered);

    wprintf(L"[thumb-probe] register plain   = %d\n",
            flwin32_thumb_register((uint64_t)(UINT_PTR)plain, src, &t_plain));
    wprintf(L"[thumb-probe] register layered = %d\n",
            flwin32_thumb_register((uint64_t)(UINT_PTR)layered, src, &t_layered));

    if (flwin32_thumb_source_size(t_plain, &sw, &sh)) {
        wprintf(L"[thumb-probe] source size = %dx%d\n", sw, sh);
    } else {
        wprintf(L"[thumb-probe] source size unavailable\n");
    }

    wprintf(L"[thumb-probe] place plain   = %d\n",
            flwin32_thumb_place(t_plain, 20, 20, 480, 300, 255, 1));
    wprintf(L"[thumb-probe] place layered = %d\n",
            flwin32_thumb_place(t_layered, 20, 20, 480, 300, 255, 1));

    wprintf(L"[thumb-probe] holding %d seconds -- screenshot now\n", seconds);
    ticks = GetTickCount();
    while (GetTickCount() - ticks < (DWORD)(seconds * 1000)) {
        MSG msg;
        while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        Sleep(16);
    }

    flwin32_thumb_unregister(t_plain);
    flwin32_thumb_unregister(t_layered);
    if (plain) DestroyWindow(plain);
    if (layered) DestroyWindow(layered);
    wprintf(L"[thumb-probe] done\n");
}
