// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/*
 * flwin32_sysinfo.c -- what the Settings app reports and changes.
 *
 * Everything here is a documented Windows call. Where Windows has no public
 * API for something people expect to configure, the setting is left out
 * rather than done through an undocumented interface -- the same line drawn
 * for the audio default-device switcher in flwin32_status.c.
 *
 * The awkward ones, and why they are written the way they are:
 *
 *  - OS VERSION. GetVersionExW lies to any process without a compatibility
 *    manifest claiming the newer Windows -- it reports 6.2 on Windows 11.
 *    RtlGetVersion does not, and is what every version check that works uses.
 *    The marketing name ("Windows 11 Pro") and the display version ("24H2")
 *    are not in either; they live in the registry.
 *  - CPU NAME comes from the registry too. There is no API for the brand
 *    string other than the CPUID instruction, and the registry value is what
 *    Windows itself shows.
 *  - DISPLAY MODES are enumerated per adapter, and the same mode appears many
 *    times over at different colour depths and refresh rates. Deduplicated on
 *    the way out, or the list is hundreds of rows of the same few sizes.
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
#include <commdlg.h>
#include <powrprof.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "include/FlutterWin32Bridge.h"

#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "powrprof.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "comdlg32.lib")

/* UTF-16 -> UTF-8 into the caller's buffer. Bytes written, or 0. */
static int32_t out_utf8(const wchar_t* w, char* out, int32_t out_size) {
    if (w == NULL || out == NULL || out_size <= 0) return 0;
    int need = WideCharToMultiByte(CP_UTF8, 0, w, -1, NULL, 0, NULL, NULL);
    if (need <= 0 || need > out_size) return 0;
    WideCharToMultiByte(CP_UTF8, 0, w, -1, out, out_size, NULL, NULL);
    return need;
}

/* A REG_SZ from HKLM, as UTF-8. */
static int32_t reg_string(const wchar_t* key, const wchar_t* value,
                          char* out, int32_t out_size) {
    wchar_t buffer[512];
    DWORD size = sizeof(buffer);
    DWORD type = 0;
    if (RegGetValueW(HKEY_LOCAL_MACHINE, key, value, RRF_RT_REG_SZ, &type,
                     buffer, &size) != ERROR_SUCCESS) {
        return 0;
    }
    return out_utf8(buffer, out, out_size);
}

static DWORD reg_dword(const wchar_t* key, const wchar_t* value) {
    DWORD data = 0;
    DWORD size = sizeof(data);
    if (RegGetValueW(HKEY_LOCAL_MACHINE, key, value, RRF_RT_REG_DWORD, NULL,
                     &data, &size) != ERROR_SUCCESS) {
        return 0;
    }
    return data;
}

/* -------------------------------------------------------------- app theme */

/* 1 for light, 0 for dark. HKCU rather than HKLM -- the theme is per-user --
 * and the value ABSENT means light: a fresh profile has no Personalize key
 * at all, and Windows defaults its apps to the light theme. This is the
 * APPS theme (AppsUseLightTheme), the value Explorer's own chrome follows,
 * not SystemUsesLightTheme, which is only the taskbar. */
int32_t flwin32_apps_use_light_theme(void) {
    DWORD data = 0;
    DWORD size = sizeof(data);
    if (RegGetValueW(HKEY_CURRENT_USER,
                     L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes"
                     L"\\Personalize",
                     L"AppsUseLightTheme", RRF_RT_REG_DWORD, NULL,
                     &data, &size) != ERROR_SUCCESS) {
        return 1;
    }
    return data != 0 ? 1 : 0;
}

/* ------------------------------------------------------------------ about */

static const wchar_t* kCurrentVersion =
    L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion";

int32_t flwin32_os_name(char* out, int32_t out_size) {
    /* "Windows 11 Pro" as Windows itself writes it. ProductName still says
     * "Windows 10" on 11 -- the build number is what tells them apart, and
     * 22000 is the first 11. */
    char product[256] = {0};
    if (reg_string(kCurrentVersion, L"ProductName", product, sizeof(product)) == 0) {
        return out_utf8(L"Windows", out, out_size);
    }
    DWORD build = 0;
    char build_str[64] = {0};
    if (reg_string(kCurrentVersion, L"CurrentBuildNumber", build_str,
                   sizeof(build_str)) > 0) {
        build = (DWORD)atoi(build_str);
    }
    if (build >= 22000) {
        char* ten = strstr(product, "Windows 10");
        if (ten != NULL) ten[9] = '1';  /* "Windows 10 Pro" -> "Windows 11 Pro" */
    }

    char display[64] = {0};
    if (reg_string(kCurrentVersion, L"DisplayVersion", display, sizeof(display)) == 0) {
        reg_string(kCurrentVersion, L"ReleaseId", display, sizeof(display));
    }

    char joined[512];
    if (display[0] != '\0') {
        snprintf(joined, sizeof(joined), "%s  %s", product, display);
    } else {
        snprintf(joined, sizeof(joined), "%s", product);
    }
    if (out == NULL || (int32_t)strlen(joined) + 1 > out_size) return 0;
    memcpy(out, joined, strlen(joined) + 1);
    return (int32_t)strlen(joined) + 1;
}

int32_t flwin32_os_build(char* out, int32_t out_size) {
    char build[64] = {0}, ubr_text[64] = {0};
    reg_string(kCurrentVersion, L"CurrentBuildNumber", build, sizeof(build));
    DWORD ubr = reg_dword(kCurrentVersion, L"UBR");
    snprintf(ubr_text, sizeof(ubr_text), "%s.%lu", build, (unsigned long)ubr);
    if (out == NULL || (int32_t)strlen(ubr_text) + 1 > out_size) return 0;
    memcpy(out, ubr_text, strlen(ubr_text) + 1);
    return (int32_t)strlen(ubr_text) + 1;
}

int32_t flwin32_device_name(char* out, int32_t out_size) {
    wchar_t name[256];
    DWORD size = 256;
    if (!GetComputerNameExW(ComputerNameDnsHostname, name, &size)) return 0;
    return out_utf8(name, out, out_size);
}

int32_t flwin32_cpu_name(char* out, int32_t out_size) {
    return reg_string(
        L"HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0",
        L"ProcessorNameString", out, out_size);
}

int32_t flwin32_cpu_cores(void) {
    SYSTEM_INFO info;
    GetSystemInfo(&info);
    return (int32_t)info.dwNumberOfProcessors;
}

int64_t flwin32_total_ram(void) {
    MEMORYSTATUSEX status;
    status.dwLength = sizeof(status);
    if (!GlobalMemoryStatusEx(&status)) return 0;
    return (int64_t)status.ullTotalPhys;
}

int64_t flwin32_available_ram(void) {
    MEMORYSTATUSEX status;
    status.dwLength = sizeof(status);
    if (!GlobalMemoryStatusEx(&status)) return 0;
    return (int64_t)status.ullAvailPhys;
}

int32_t flwin32_gpu_name(char* out, int32_t out_size) {
    /* The adapter attached to the desktop, not merely the first enumerated:
     * a laptop lists the integrated and the discrete one, and only one of
     * them is drawing anything. */
    DISPLAY_DEVICEW device;
    ZeroMemory(&device, sizeof(device));
    device.cb = sizeof(device);
    for (DWORD i = 0; EnumDisplayDevicesW(NULL, i, &device, 0); i++) {
        if (device.StateFlags & DISPLAY_DEVICE_ATTACHED_TO_DESKTOP) {
            return out_utf8(device.DeviceString, out, out_size);
        }
        ZeroMemory(&device, sizeof(device));
        device.cb = sizeof(device);
    }
    return 0;
}

/* ---------------------------------------------------------------- display */

int32_t flwin32_display_current(int32_t* width, int32_t* height,
                                int32_t* refresh) {
    DEVMODEW mode;
    ZeroMemory(&mode, sizeof(mode));
    mode.dmSize = sizeof(mode);
    if (!EnumDisplaySettingsW(NULL, ENUM_CURRENT_SETTINGS, &mode)) return 0;
    if (width) *width = (int32_t)mode.dmPelsWidth;
    if (height) *height = (int32_t)mode.dmPelsHeight;
    if (refresh) *refresh = (int32_t)mode.dmDisplayFrequency;
    return 1;
}

/* The distinct width x height x refresh the primary adapter offers, newest
 * API be damned: EnumDisplaySettings is still the way, and it repeats every
 * mode once per colour depth. */
int32_t flwin32_display_modes(int32_t* out, int32_t max_modes) {
    if (out == NULL || max_modes <= 0) return 0;
    int32_t count = 0;
    DEVMODEW mode;
    ZeroMemory(&mode, sizeof(mode));
    mode.dmSize = sizeof(mode);

    for (DWORD i = 0; EnumDisplaySettingsW(NULL, i, &mode) && count < max_modes; i++) {
        if (mode.dmBitsPerPel < 32) continue;
        int32_t w = (int32_t)mode.dmPelsWidth;
        int32_t h = (int32_t)mode.dmPelsHeight;
        int32_t hz = (int32_t)mode.dmDisplayFrequency;
        /* Anything smaller than this is not a mode anyone chooses on a
         * desktop, and they crowd out the ones that are. */
        if (w < 1024 || h < 768) continue;

        int duplicate = 0;
        for (int32_t j = 0; j < count; j++) {
            if (out[j * 3] == w && out[j * 3 + 1] == h && out[j * 3 + 2] == hz) {
                duplicate = 1;
                break;
            }
        }
        if (duplicate) continue;

        out[count * 3] = w;
        out[count * 3 + 1] = h;
        out[count * 3 + 2] = hz;
        count++;
    }
    return count;
}

int32_t flwin32_display_set(int32_t width, int32_t height, int32_t refresh) {
    DEVMODEW mode;
    ZeroMemory(&mode, sizeof(mode));
    mode.dmSize = sizeof(mode);
    mode.dmPelsWidth = (DWORD)width;
    mode.dmPelsHeight = (DWORD)height;
    mode.dmDisplayFrequency = (DWORD)refresh;
    mode.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYFREQUENCY;
    /* Applied and remembered. CDS_UPDATEREGISTRY without CDS_GLOBAL sticks
     * for this user, which is what a Settings app means by "change it". */
    LONG rc = ChangeDisplaySettingsExW(NULL, &mode, NULL, CDS_UPDATEREGISTRY, NULL);
    return rc == DISP_CHANGE_SUCCESSFUL ? 1 : 0;
}

/* ---------------------------------------------------------------- storage */

/* Fixed drives only: a Settings page listing every mapped network share and
 * every mounted ISO is a page nobody reads. */
int32_t flwin32_drives(char* letters, int32_t letters_size,
                       int64_t* totals, int64_t* frees, int32_t max_drives) {
    if (letters == NULL || totals == NULL || frees == NULL) return 0;
    DWORD mask = GetLogicalDrives();
    int32_t count = 0;
    for (int i = 0; i < 26 && count < max_drives; i++) {
        if (!(mask & (1u << i))) continue;
        wchar_t root[4] = {(wchar_t)(L'A' + i), L':', L'\\', 0};
        if (GetDriveTypeW(root) != DRIVE_FIXED) continue;

        ULARGE_INTEGER available, total, free_bytes;
        if (!GetDiskFreeSpaceExW(root, &available, &total, &free_bytes)) continue;
        if (count * 2 + 1 >= letters_size) break;
        letters[count * 2] = (char)('A' + i);
        letters[count * 2 + 1] = '\0';
        totals[count] = (int64_t)total.QuadPart;
        frees[count] = (int64_t)available.QuadPart;
        count++;
    }
    return count;
}

/* ------------------------------------------------------------------ power */

int32_t flwin32_power_scheme(char* out, int32_t out_size) {
    GUID* active = NULL;
    if (PowerGetActiveScheme(NULL, &active) != ERROR_SUCCESS || active == NULL) {
        return 0;
    }
    UCHAR buffer[512];
    DWORD size = sizeof(buffer);
    int32_t written = 0;
    if (PowerReadFriendlyName(NULL, active, NULL, NULL, buffer, &size)
            == ERROR_SUCCESS) {
        written = out_utf8((const wchar_t*)buffer, out, out_size);
    }
    LocalFree(active);
    return written;
}

/* -------------------------------------------------------------- wallpaper */

int32_t flwin32_set_wallpaper(const char* path) {
    if (path == NULL) return 0;
    int n = MultiByteToWideChar(CP_UTF8, 0, path, -1, NULL, 0);
    if (n <= 0) return 0;
    wchar_t* wide = (wchar_t*)calloc((size_t)n, sizeof(wchar_t));
    if (wide == NULL) return 0;
    MultiByteToWideChar(CP_UTF8, 0, path, -1, wide, n);
    /* UPDATEINIFILE so it survives a logout, SENDWININICHANGE so every other
     * process hears about it -- without the second, explorer keeps drawing
     * the old one until something else makes it repaint. */
    BOOL ok = SystemParametersInfoW(SPI_SETDESKWALLPAPER, 0, wide,
                                    SPIF_UPDATEINIFILE | SPIF_SENDWININICHANGE);
    free(wide);
    return ok ? 1 : 0;
}

int32_t flwin32_get_wallpaper(char* out, int32_t out_size) {
    wchar_t path[MAX_PATH];
    path[0] = L'\0';
    if (!SystemParametersInfoW(SPI_GETDESKWALLPAPER, MAX_PATH, path, 0)) return 0;
    return out_utf8(path, out, out_size);
}

/* The wallpaper's average colour, as 0xAARRGGBB -- the mica ingredient.
 * Real mica is DWM compositing a blurred desktop behind transparent window
 * regions, which an opaque GL swap chain cannot show; what the eye mostly
 * reads off Explorer's chrome is the TINT, and the average of a thumbnail
 * is that tint. The shell's own image factory does the decode (the same
 * machinery behind Explorer's thumbnails), so every format the desktop can
 * be set to is covered without linking an image library. COM-inits its own
 * apartment: callers run this off the UI thread, where the decode belongs. */
int32_t flwin32_wallpaper_average(uint32_t* out_argb) {
    if (out_argb == NULL) return 0;
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
            want.cx = 16;
            want.cy = 16;
            HBITMAP bitmap = NULL;
            if (SUCCEEDED(factory->lpVtbl->GetImage(
                    factory, want, SIIGBF_RESIZETOFIT, &bitmap))
                && bitmap != NULL) {
                BITMAP info;
                if (GetObjectW(bitmap, sizeof(info), &info)
                    && info.bmWidth > 0 && info.bmHeight > 0) {
                    int w = info.bmWidth;
                    int h = info.bmHeight;
                    BITMAPINFO bi;
                    ZeroMemory(&bi, sizeof(bi));
                    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
                    bi.bmiHeader.biWidth = w;
                    bi.bmiHeader.biHeight = -h;
                    bi.bmiHeader.biPlanes = 1;
                    bi.bmiHeader.biBitCount = 32;
                    bi.bmiHeader.biCompression = BI_RGB;
                    unsigned char* pixels =
                        (unsigned char*)malloc((size_t)w * (size_t)h * 4);
                    HDC dc = GetDC(NULL);
                    if (pixels != NULL && dc != NULL
                        && GetDIBits(dc, bitmap, 0, (UINT)h, pixels, &bi,
                                     DIB_RGB_COLORS) == h) {
                        unsigned long long r = 0, g = 0, b = 0;
                        int n = w * h;
                        for (int i = 0; i < n; i++) {
                            b += pixels[i * 4];
                            g += pixels[i * 4 + 1];
                            r += pixels[i * 4 + 2];
                        }
                        *out_argb = 0xFF000000u
                            | ((uint32_t)(r / (unsigned)n) << 16)
                            | ((uint32_t)(g / (unsigned)n) << 8)
                            | (uint32_t)(b / (unsigned)n);
                        ok = 1;
                    }
                    if (dc != NULL) ReleaseDC(NULL, dc);
                    free(pixels);
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

/* ----------------------------------------------------------------- dialog */

/* The shell's own open dialog, for picking a wallpaper.
 *
 * GetOpenFileNameW rather than IFileOpenDialog: this needs no COM apartment
 * on the calling thread, which matters because the Settings app calls it from
 * a background task -- and the modern dialog buys nothing for one file with a
 * fixed filter.
 *
 * BLOCKS until the user answers, which is exactly why it must not be called
 * from the thread drawing the app. */
int32_t flwin32_pick_image(char* out, int32_t out_size) {
    wchar_t path[MAX_PATH];
    path[0] = L'\0';

    OPENFILENAMEW ofn;
    ZeroMemory(&ofn, sizeof(ofn));
    ofn.lStructSize = sizeof(ofn);
    ofn.lpstrFilter = L"Images\0*.jpg;*.jpeg;*.png;*.bmp\0All files\0*.*\0";
    ofn.lpstrFile = path;
    ofn.nMaxFile = MAX_PATH;
    ofn.lpstrTitle = L"Choose a wallpaper";
    /* NOCHANGEDIR: a file dialog that leaves the process sitting in whatever
     * folder the user browsed to is how a later relative path resolves
     * somewhere surprising. */
    ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR
                | OFN_EXPLORER;

    if (!GetOpenFileNameW(&ofn)) return 0;
    return out_utf8(path, out, out_size);
}
