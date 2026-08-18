// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/*
 * flwin32_status.c -- what a status bar is supposed to show.
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
 */

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
                               int32_t ssid_size) {
    if (kind) *kind = 0;
    if (signal) *signal = 0;
    if (ssid != NULL && ssid_size > 0) ssid[0] = '\0';

    /* Wi-Fi first: it is the only source of a signal strength, and a laptop
     * on Wi-Fi also has adapters that would satisfy the Ethernet test. */
    HANDLE wlan = NULL;
    DWORD negotiated = 0;
    if (WlanOpenHandle(2, NULL, &negotiated, &wlan) == ERROR_SUCCESS) {
        WLAN_INTERFACE_INFO_LIST* interfaces = NULL;
        if (WlanEnumInterfaces(wlan, NULL, &interfaces) == ERROR_SUCCESS &&
            interfaces != NULL) {
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
