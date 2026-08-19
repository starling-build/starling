// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/*
 * flwin32_status.c -- what a status bar is supposed to show, and what a
 * control centre is supposed to change.
 *
 * Network, power and volume, read from the system rather than drawn as
 * decoration. A menu bar with a fixed wifi glyph and a fixed battery glyph is
 * a picture of a status bar; these are the three things that make it one.
 *
 * Plain ASCII throughout, same reason as the neighbouring files.
 *
 * Each of the three comes from a different place, and none of them is the
 * obvious one:
 *
 *  - POWER is the easy one: GetSystemPowerStatus, straight out of kernel32.
 *  - NETWORK has no single call. Wi-Fi signal strength only exists in
 *    wlanapi, and a machine on Ethernet has no Wi-Fi interface at all, so the
 *    answer is "ask wlanapi, and if it has nothing, ask iphlpapi whether any
 *    other adapter is up".
 *  - VOLUME is COM: the endpoint volume of the default render device. There
 *    is no Win32 call for the modern per-device volume -- waveOutGetVolume
 *    still exists and still compiles and reports something unrelated to what
 *    the user's volume slider says.
 *
 * The setters at the bottom are the control centre's half. They live here
 * rather than in a file of their own so that the audio endpoint's three GUIDs
 * and its open-activate-release dance are written once: a second copy of
 * those constants is exactly the kind of thing that goes stale.
 */

/* dxva2 for the monitor's backlight over DDC/CI. */
#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

/* winsock2 BEFORE windows.h, and iphlpapi after both.
 *
 * <windows.h> drags in the 1.1 winsock headers on its own, and <iphlpapi.h>
 * is built on the 2.x ones -- include them the other way round and every
 * IP_ADAPTER_ADDRESSES and GAA_FLAG_* comes back "undeclared identifier",
 * pointing at this file rather than at the ordering. */
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <iphlpapi.h>
#include <wlanapi.h>
#include <mmdeviceapi.h>
#include <endpointvolume.h>
#include <highlevelmonitorconfigurationapi.h>  /* Get/SetMonitorBrightness */
#include <physicalmonitorenumerationapi.h>       /* PHYSICAL_MONITOR */
#include <objbase.h>
#include <stdlib.h>
#include <string.h>

#include "include/FlutterWin32Bridge.h"

/* The Core Audio GUIDs, spelled out.
 *
 * mmdeviceapi.h only DECLARES them (EXTERN_C const CLSID ...); the definitions
 * live in a MIDL-generated object that ships in no import library, so a C
 * build links clean right up to "undefined symbol: CLSID_MMDeviceEnumerator".
 * <initguid.h> is the usual answer and does not help here, because these are
 * not DEFINE_GUIDs to begin with. Three constants is cheaper than the hunt. */
static const CLSID kCLSID_MMDeviceEnumerator = {
    0xBCDE0395, 0xE52F, 0x467C, {0x8E, 0x3D, 0xC4, 0x57, 0x92, 0x91, 0x69, 0x2E}};
static const IID kIID_IMMDeviceEnumerator = {
    0xA95664D2, 0x9614, 0x4F35, {0xA7, 0x46, 0xDE, 0x8D, 0xB6, 0x36, 0x17, 0xE6}};
static const IID kIID_IAudioEndpointVolume = {
    0x5CDF2C82, 0x841E, 0x4546, {0x97, 0x22, 0x0C, 0xF7, 0x40, 0x78, 0x22, 0x9A}};

#pragma comment(lib, "wlanapi.lib")
#pragma comment(lib, "iphlpapi.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "dxva2.lib")

/* ------------------------------------------------------------------ power */

int32_t flwin32_power_status(int32_t* present, int32_t* percent, int32_t* charging) {
    SYSTEM_POWER_STATUS status;
    if (!GetSystemPowerStatus(&status)) return 0;

    /* BatteryFlag 128 is the documented "no system battery" bit, and it is
     * the only reliable way to tell a desktop from a laptop at 100%: a
     * desktop reports BatteryLifePercent 255 (unknown), not 100. */
    int has_battery = (status.BatteryFlag != 128) && (status.BatteryFlag != 255);
    if (present) *present = has_battery ? 1 : 0;
    if (percent) {
        *percent = (status.BatteryLifePercent == 255)
                       ? -1
                       : (int32_t)status.BatteryLifePercent;
    }
    /* ACLineStatus 1 = on mains. Charging is really "plugged in", which is
     * what a status bar wants to show -- a full battery on mains is not
     * charging but should still show the bolt. */
    if (charging) *charging = (status.ACLineStatus == 1) ? 1 : 0;
    return 1;
}

/* ------------------------------------------------------------- brightness */

/* DDC/CI, which is the monitor's own backlight over an I2C channel in the
 * video cable -- the same thing the buttons on the front of the monitor do.
 *
 * Not the laptop path: WmiMonitorBrightnessMethods only covers an internal
 * panel, and this is a desktop with a Dell over DisplayPort. dxva2 covers
 * both, because Windows routes an internal panel through it too.
 *
 * SLOW, and that matters more than it looks. Every call here is a round trip
 * to the monitor's firmware -- tens to hundreds of milliseconds, and entirely
 * outside our control. It must never be called from the thread that draws,
 * which is why the shell reads it once at startup and after a change rather
 * than on the status tick: polling a monitor over I2C once a second is rude
 * to the hardware as well as to the frame budget.
 *
 * Handles are opened and destroyed per call rather than cached. A cached
 * physical monitor handle goes stale on a mode change, a cable swap or a
 * monitor sleeping, and the failure is a silent no-op. */

static int with_first_monitor(int (*use)(HANDLE, void*), void* user) {
    POINT origin = {0, 0};
    HMONITOR monitor = MonitorFromPoint(origin, MONITOR_DEFAULTTOPRIMARY);
    if (monitor == NULL) return 0;

    DWORD count = 0;
    if (!GetNumberOfPhysicalMonitorsFromHMONITOR(monitor, &count) || count == 0) {
        return 0;
    }
    PHYSICAL_MONITOR* monitors =
        (PHYSICAL_MONITOR*)calloc(count, sizeof(PHYSICAL_MONITOR));
    if (monitors == NULL) return 0;

    int result = 0;
    if (GetPhysicalMonitorsFromHMONITOR(monitor, count, monitors)) {
        /* The first one that answers. A machine with two monitors has two
         * backlights and no single "the" brightness; the primary is the one
         * the user means, and is where the control centre is drawn. */
        for (DWORD i = 0; i < count; i++) {
            if (use(monitors[i].hPhysicalMonitor, user)) { result = 1; break; }
        }
        DestroyPhysicalMonitors(count, monitors);
    }
    free(monitors);
    return result;
}

struct BrightnessRead { int32_t percent; };

static int read_brightness(HANDLE monitor, void* user) {
    struct BrightnessRead* out = (struct BrightnessRead*)user;
    DWORD minimum = 0, current = 0, maximum = 0;
    if (!GetMonitorBrightness(monitor, &minimum, &current, &maximum)) return 0;
    if (maximum <= minimum) return 0;
    /* Reported in the monitor's own units, which are not required to be
     * 0-100 -- normalise, or a monitor with a 0-255 range reads as 30%. */
    out->percent = (int32_t)(((double)(current - minimum) * 100.0)
                             / (double)(maximum - minimum) + 0.5);
    return 1;
}

int32_t flwin32_brightness_get(int32_t* percent) {
    struct BrightnessRead out = {0};
    if (!with_first_monitor(read_brightness, &out)) return 0;
    if (percent) *percent = out.percent;
    return 1;
}

static int write_brightness(HANDLE monitor, void* user) {
    int32_t wanted = *(int32_t*)user;
    DWORD minimum = 0, current = 0, maximum = 0;
    if (!GetMonitorBrightness(monitor, &minimum, &current, &maximum)) return 0;
    if (maximum <= minimum) return 0;
    if (wanted < 0) wanted = 0;
    if (wanted > 100) wanted = 100;
    DWORD value = minimum + (DWORD)(((double)(maximum - minimum) * wanted) / 100.0 + 0.5);
    return SetMonitorBrightness(monitor, value) ? 1 : 0;
}

int32_t flwin32_brightness_set(int32_t percent) {
    return with_first_monitor(write_brightness, &percent) ? 1 : 0;
}

/* ---------------------------------------------------------------- network */

/* Any non-loopback adapter that is up and has a gateway. "Up" alone is not
 * enough: a machine with Hyper-V, WSL or a VPN client has several adapters
 * permanently up and going nowhere, which is how a disconnected laptop ends
 * up claiming it is on Ethernet. */
static int ethernet_connected(void) {
    ULONG size = 15000;
    IP_ADAPTER_ADDRESSES* buffer = (IP_ADAPTER_ADDRESSES*)malloc(size);
    if (buffer == NULL) return 0;

    ULONG flags = GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST |
                  GAA_FLAG_SKIP_DNS_SERVER | GAA_FLAG_INCLUDE_GATEWAYS;
    ULONG rc = GetAdaptersAddresses(AF_UNSPEC, flags, NULL, buffer, &size);
    if (rc == ERROR_BUFFER_OVERFLOW) {
        IP_ADAPTER_ADDRESSES* grown = (IP_ADAPTER_ADDRESSES*)realloc(buffer, size);
        if (grown == NULL) {
            free(buffer);
            return 0;
        }
        buffer = grown;
        rc = GetAdaptersAddresses(AF_UNSPEC, flags, NULL, buffer, &size);
    }
    if (rc != NO_ERROR) {
        free(buffer);
        return 0;
    }

    int connected = 0;
    for (IP_ADAPTER_ADDRESSES* a = buffer; a != NULL; a = a->Next) {
        if (a->IfType == IF_TYPE_SOFTWARE_LOOPBACK) continue;
        if (a->OperStatus != IfOperStatusUp) continue;
        if (a->FirstGatewayAddress == NULL) continue;
        connected = 1;
        break;
    }
    free(buffer);
    return connected;
}

int32_t flwin32_network_status(int32_t* kind,
                               int32_t* signal,
                               char* ssid,
                               int32_t ssid_size,
                               int32_t* has_wifi) {
    if (kind) *kind = 0;
    if (signal) *signal = 0;
    if (ssid != NULL && ssid_size > 0) ssid[0] = '\0';

    /* Wi-Fi first: it is the only source of a signal strength, and a laptop
     * on Wi-Fi also has adapters that would satisfy the Ethernet test. */
    HANDLE wlan = NULL;
    DWORD negotiated = 0;
    if (has_wifi) *has_wifi = 0;
    if (WlanOpenHandle(2, NULL, &negotiated, &wlan) == ERROR_SUCCESS) {
        WLAN_INTERFACE_INFO_LIST* interfaces = NULL;
        if (WlanEnumInterfaces(wlan, NULL, &interfaces) == ERROR_SUCCESS &&
            interfaces != NULL) {
            /* Whether the machine HAS Wi-Fi, which is a different question
             * from whether it is on one. A desktop with only Ethernet has no
             * WLAN interface at all, and a status bar should not show it an
             * empty signal meter for hardware it does not have. A laptop with
             * the radio switched off does have the interface, and four unlit
             * bars is exactly the right thing to show there. */
            if (has_wifi) *has_wifi = interfaces->dwNumberOfItems > 0 ? 1 : 0;
            for (DWORD i = 0; i < interfaces->dwNumberOfItems; i++) {
                WLAN_INTERFACE_INFO* info = &interfaces->InterfaceInfo[i];
                if (info->isState != wlan_interface_state_connected) continue;

                DWORD bytes = 0;
                WLAN_CONNECTION_ATTRIBUTES* attributes = NULL;
                if (WlanQueryInterface(wlan, &info->InterfaceGuid,
                                       wlan_intf_opcode_current_connection, NULL,
                                       &bytes, (PVOID*)&attributes,
                                       NULL) == ERROR_SUCCESS &&
                    attributes != NULL) {
                    if (kind) *kind = 2;
                    if (signal) {
                        *signal =
                            (int32_t)attributes->wlanAssociationAttributes.wlanSignalQuality;
                    }
                    if (ssid != NULL && ssid_size > 0) {
                        DOT11_SSID* name =
                            &attributes->wlanAssociationAttributes.dot11Ssid;
                        /* The SSID is raw bytes with a length, not a C string,
                         * and it is not required to be valid UTF-8 -- copy the
                         * declared length and terminate it ourselves. */
                        int32_t n = (int32_t)name->uSSIDLength;
                        if (n > ssid_size - 1) n = ssid_size - 1;
                        memcpy(ssid, name->ucSSID, (size_t)n);
                        ssid[n] = '\0';
                    }
                    WlanFreeMemory(attributes);
                    WlanFreeMemory(interfaces);
                    WlanCloseHandle(wlan, NULL);
                    return 1;
                }
            }
            WlanFreeMemory(interfaces);
        }
        WlanCloseHandle(wlan, NULL);
    }

    if (ethernet_connected()) {
        if (kind) *kind = 1;
        if (signal) *signal = 100;
        return 1;
    }
    return 1;  /* answered: nothing is connected */
}

/* ----------------------------------------------------------------- volume */

int32_t flwin32_volume_status(int32_t* percent, int32_t* muted) {
    /* The apartment may already be initialized by the embedder; either answer
     * is fine, and RPC_E_CHANGED_MODE is not an error for us. */
    CoInitializeEx(NULL, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);

    IMMDeviceEnumerator* enumerator = NULL;
    IMMDevice* device = NULL;
    IAudioEndpointVolume* volume = NULL;
    int32_t ok = 0;

    if (SUCCEEDED(CoCreateInstance(&kCLSID_MMDeviceEnumerator, NULL,
                                   CLSCTX_INPROC_SERVER, &kIID_IMMDeviceEnumerator,
                                   (void**)&enumerator)) &&
        SUCCEEDED(enumerator->lpVtbl->GetDefaultAudioEndpoint(
            enumerator, eRender, eConsole, &device)) &&
        SUCCEEDED(device->lpVtbl->Activate(device, &kIID_IAudioEndpointVolume,
                                           CLSCTX_INPROC_SERVER, NULL,
                                           (void**)&volume))) {
        float scalar = 0.0f;
        BOOL is_muted = FALSE;
        if (SUCCEEDED(volume->lpVtbl->GetMasterVolumeLevelScalar(volume, &scalar)) &&
            SUCCEEDED(volume->lpVtbl->GetMute(volume, &is_muted))) {
            /* The SCALAR, not the decibel level: it is the one that matches
             * the position of the user's own volume slider. GetMasterVolumeLevel
             * returns dB, which is linear in nothing anyone can see. */
            if (percent) *percent = (int32_t)(scalar * 100.0f + 0.5f);
            if (muted) *muted = is_muted ? 1 : 0;
            ok = 1;
        }
    }

    if (volume != NULL) volume->lpVtbl->Release(volume);
    if (device != NULL) device->lpVtbl->Release(device);
    if (enumerator != NULL) enumerator->lpVtbl->Release(enumerator);
    return ok;
}

/* -- the control centre's half: setting what the status bar reads --------- */

/* Open the default render endpoint's volume interface. The three-step
 * enumerator/device/activate dance is identical for reading and writing, so
 * it is written once and both paths borrow it. Caller releases everything it
 * is handed; on failure nothing is left to release. */
static int volume_open(IMMDeviceEnumerator** enumerator,
                       IMMDevice** device,
                       IAudioEndpointVolume** volume) {
    *enumerator = NULL;
    *device = NULL;
    *volume = NULL;
    CoInitializeEx(NULL, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    if (FAILED(CoCreateInstance(&kCLSID_MMDeviceEnumerator, NULL,
                                CLSCTX_INPROC_SERVER, &kIID_IMMDeviceEnumerator,
                                (void**)enumerator))) {
        return 0;
    }
    if (FAILED((*enumerator)->lpVtbl->GetDefaultAudioEndpoint(
            *enumerator, eRender, eConsole, device))) {
        (*enumerator)->lpVtbl->Release(*enumerator);
        *enumerator = NULL;
        return 0;
    }
    if (FAILED((*device)->lpVtbl->Activate(*device, &kIID_IAudioEndpointVolume,
                                           CLSCTX_INPROC_SERVER, NULL,
                                           (void**)volume))) {
        (*device)->lpVtbl->Release(*device);
        (*enumerator)->lpVtbl->Release(*enumerator);
        *device = NULL;
        *enumerator = NULL;
        return 0;
    }
    return 1;
}

static void volume_close(IMMDeviceEnumerator* enumerator,
                         IMMDevice* device,
                         IAudioEndpointVolume* volume) {
    if (volume != NULL) volume->lpVtbl->Release(volume);
    if (device != NULL) device->lpVtbl->Release(device);
    if (enumerator != NULL) enumerator->lpVtbl->Release(enumerator);
}

int32_t flwin32_volume_set(int32_t percent) {
    IMMDeviceEnumerator* enumerator;
    IMMDevice* device;
    IAudioEndpointVolume* volume;
    if (percent < 0) percent = 0;
    if (percent > 100) percent = 100;
    if (!volume_open(&enumerator, &device, &volume)) return 0;
    /* Scalar, matching the reader: the dB setter is linear in nothing the
     * user can see, so a slider driven through it moves wrong. */
    HRESULT hr = volume->lpVtbl->SetMasterVolumeLevelScalar(
        volume, (float)percent / 100.0f, NULL);
    volume_close(enumerator, device, volume);
    return SUCCEEDED(hr) ? 1 : 0;
}

int32_t flwin32_volume_set_muted(int32_t muted) {
    IMMDeviceEnumerator* enumerator;
    IMMDevice* device;
    IAudioEndpointVolume* volume;
    if (!volume_open(&enumerator, &device, &volume)) return 0;
    HRESULT hr = volume->lpVtbl->SetMute(volume, muted ? TRUE : FALSE, NULL);
    volume_close(enumerator, device, volume);
    return SUCCEEDED(hr) ? 1 : 0;
}

/* The Wi-Fi RADIO, not the adapter.
 *
 * "Disable the network" has two spellings on Windows and only one of them is
 * ours to use. Disabling the ADAPTER (what Device Manager and
 * Disable-NetAdapter do) needs administrator rights, and a shell that raises
 * a UAC prompt to turn Wi-Fi off is not a shell anyone wants. The radio is
 * the softer switch behind the same idea -- it is what Airplane Mode flips --
 * and the interactive user owns it.
 *
 * Symmetric on purpose: whatever turns it off has to be able to turn it back
 * on, or the control centre is a trap. */
int32_t flwin32_wifi_set_radio(int32_t on) {
    HANDLE wlan = NULL;
    DWORD negotiated = 0;
    int32_t ok = 0;
    if (WlanOpenHandle(2, NULL, &negotiated, &wlan) != ERROR_SUCCESS) return 0;

    WLAN_INTERFACE_INFO_LIST* interfaces = NULL;
    if (WlanEnumInterfaces(wlan, NULL, &interfaces) == ERROR_SUCCESS &&
        interfaces != NULL) {
        for (DWORD i = 0; i < interfaces->dwNumberOfItems; i++) {
            WLAN_PHY_RADIO_STATE state;
            ZeroMemory(&state, sizeof(state));
            state.dwPhyIndex = 0;
            state.dot11SoftwareRadioState =
                on ? dot11_radio_state_on : dot11_radio_state_off;
            /* The HARDWARE radio state is read-only -- a physical switch --
             * so only the software one is set here, which is what every
             * on-screen Wi-Fi toggle sets. */
            if (WlanSetInterface(wlan, &interfaces->InterfaceInfo[i].InterfaceGuid,
                                 wlan_intf_opcode_radio_state,
                                 (DWORD)sizeof(state), &state,
                                 NULL) == ERROR_SUCCESS) {
                ok = 1;
            }
        }
        WlanFreeMemory(interfaces);
    }
    WlanCloseHandle(wlan, NULL);
    return ok;
}

/* Windows' own light/dark setting, which is a registry value plus a
 * broadcast. Two values, not one: `AppsUseLightTheme` is what applications
 * read and `SystemUsesLightTheme` is what the shell furniture reads, and
 * setting only the first leaves a light taskbar over dark apps. The
 * WM_SETTINGCHANGE with "ImmersiveColorSet" is what makes running apps
 * notice -- without it nothing changes until the next login. */
static const wchar_t* const kPersonalizeKey =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";

int32_t flwin32_dark_mode(void) {
    DWORD value = 1;
    DWORD size = sizeof(value);
    if (RegGetValueW(HKEY_CURRENT_USER, kPersonalizeKey, L"AppsUseLightTheme",
                     RRF_RT_REG_DWORD, NULL, &value, &size) != ERROR_SUCCESS) {
        return 0;
    }
    return value == 0 ? 1 : 0;
}

int32_t flwin32_set_dark_mode(int32_t dark) {
    HKEY key = NULL;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, kPersonalizeKey, 0, NULL, 0,
                        KEY_SET_VALUE, NULL, &key, NULL) != ERROR_SUCCESS) {
        return 0;
    }
    DWORD light = dark ? 0 : 1;
    LSTATUS a = RegSetValueExW(key, L"AppsUseLightTheme", 0, REG_DWORD,
                               (const BYTE*)&light, sizeof(light));
    LSTATUS b = RegSetValueExW(key, L"SystemUsesLightTheme", 0, REG_DWORD,
                               (const BYTE*)&light, sizeof(light));
    RegCloseKey(key);
    if (a != ERROR_SUCCESS || b != ERROR_SUCCESS) return 0;

    /* SendMessageTimeout, not Send: a broadcast that waits is a broadcast
     * held up by the first hung window on the desktop. */
    DWORD_PTR result = 0;
    SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, 0,
                        (LPARAM)L"ImmersiveColorSet",
                        SMTO_ABORTIFHUNG, 200, &result);
    return 1;
}
