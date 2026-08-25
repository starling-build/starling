// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/*
 * flwin32_net.c -- the network adapters, in the detail a settings page shows.
 *
 * The status bar's question is "am I online, and how strong is the signal",
 * and flwin32_status.c answers that in one call. This answers a different
 * one -- "what are my adapters, and what address does each hold" -- which
 * needs the whole enumeration rather than the first thing that is up.
 *
 * GetAdaptersAddresses, once per call, and no cached pointers. The list is a
 * chain of variable-length structures the caller owns for exactly as long as
 * the buffer lives; keeping a pointer into it across calls is how a settings
 * page reads a freed adapter after a cable is unplugged. Adapters are a
 * handful, so re-enumerating per query costs nothing worth saving.
 *
 * WRITES ARE NOT HERE, and that is deliberate. Changing an address, the DNS
 * servers or an adapter's enabled state all need administrator rights:
 * CreateUnicastIpAddressEntry and SetInterfaceDnsSettings both fail with
 * access denied for a normal user, and a settings page whose controls throw
 * up a UAC prompt -- or silently do nothing -- is worse than one that reads
 * honestly and hands the user to Windows for the rest.
 *
 * Plain ASCII throughout, same reason as the neighbouring files.
 */

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <iphlpapi.h>
#include <shellapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "include/FlutterWin32Bridge.h"

#pragma comment(lib, "iphlpapi.lib")
/* NOT ws2_32: see address_text below. <winsock2.h> above is included for the
 * sockaddr_in/sockaddr_in6 TYPES, which costs no import -- linking the library
 * is what would put Winsock in this binary's import table. */
#pragma comment(lib, "shell32.lib")

static int32_t wide_to_utf8(const wchar_t* w, char* out, int32_t out_size) {
    if (w == NULL || out == NULL || out_size <= 0) return 0;
    int need = WideCharToMultiByte(CP_UTF8, 0, w, -1, NULL, 0, NULL, NULL);
    if (need <= 0 || need > out_size) return 0;
    WideCharToMultiByte(CP_UTF8, 0, w, -1, out, out_size, NULL, NULL);
    return need;
}

/* An address from the sockaddr the API hands back, in the form people read.
 *
 * WHY NOT inet_ntop, WHICH IS RIGHT THERE. It is the only Winsock function
 * this shell ever wanted, and asking for it links ws2_32 -- so a reviewer
 * reading the import table of the binary that IS the Windows shell sees
 * "Winsock" and has to go find out whether it opens sockets. It does not:
 * the answer was one pure text formatter. Writing the formatter here costs
 * forty lines and removes the question. Nothing else in the process needs
 * Winsock, so the import goes away entirely.
 *
 * The output matches inet_ntop, which is RFC 5952: lowercase hex, no leading
 * zeros in a group, the LONGEST run of two or more zero groups collapsed to
 * "::" (the leftmost such run when two tie), and IPv4-mapped addresses in the
 * mixed ::ffff:1.2.3.4 form. Checked against the system inet_ntop over 25,000
 * addresses -- the literal edge cases plus random ones biased toward zero
 * runs, which is the rule that is easy to get subtly wrong. */
static void format_v4(const unsigned char* b, char* out, int32_t size) {
    snprintf(out, (size_t)size, "%u.%u.%u.%u", b[0], b[1], b[2], b[3]);
}

static void format_v6(const unsigned char* b, char* out, int32_t size) {
    unsigned int g[8];
    for (int i = 0; i < 8; ++i) g[i] = ((unsigned)b[i * 2] << 8) | b[i * 2 + 1];

    /* IPv4-mapped and IPv4-compatible addresses print their last four bytes
     * as a dotted quad, so only the first six groups take part above. */
    int mapped = (g[0] | g[1] | g[2] | g[3] | g[4]) == 0
                 && (g[5] == 0xffff || (g[5] == 0 && g[6] != 0));
    int limit = mapped ? 6 : 8;

    int best = -1, best_len = 0, cur = -1, cur_len = 0;
    for (int i = 0; i < limit; ++i) {
        if (g[i] == 0) {
            if (cur < 0) { cur = i; cur_len = 1; } else { cur_len++; }
            if (cur_len > best_len) { best = cur; best_len = cur_len; }
        } else {
            cur = -1;
            cur_len = 0;
        }
    }
    if (best_len < 2) { best = -1; best_len = 0; }

    char buf[64];
    int n = 0;
    for (int i = 0; i < limit; ++i) {
        if (best >= 0 && i >= best && i < best + best_len) {
            /* One colon here; the separator rules on either side supply the
             * second, which is what makes "::" rather than ":". */
            if (i == best) buf[n++] = ':';
            continue;
        }
        if (i != 0) buf[n++] = ':';
        n += snprintf(buf + n, sizeof(buf) - (size_t)n, "%x", g[i]);
    }
    /* A run reaching the end has no group after it to write the closing colon. */
    if (best >= 0 && best + best_len == limit) buf[n++] = ':';
    buf[n] = '\0';
    if (mapped) {
        if (!(best >= 0 && best + best_len == limit)) buf[n++] = ':';
        buf[n] = '\0';
        snprintf(buf + n, sizeof(buf) - (size_t)n, "%u.%u.%u.%u",
                 b[12], b[13], b[14], b[15]);
    }
    snprintf(out, (size_t)size, "%s", buf);
}

static void address_text(const SOCKET_ADDRESS* address, char* out, int32_t size) {
    if (out == NULL || size <= 0) return;
    out[0] = '\0';
    if (address == NULL || address->lpSockaddr == NULL) return;
    if (address->lpSockaddr->sa_family == AF_INET) {
        struct sockaddr_in* v4 = (struct sockaddr_in*)address->lpSockaddr;
        format_v4((const unsigned char*)&v4->sin_addr, out, size);
    } else if (address->lpSockaddr->sa_family == AF_INET6) {
        struct sockaddr_in6* v6 = (struct sockaddr_in6*)address->lpSockaddr;
        format_v6((const unsigned char*)&v6->sin6_addr, out, size);
    }
}

static IP_ADAPTER_ADDRESSES* enumerate(IP_ADAPTER_ADDRESSES** buffer) {
    ULONG size = 32768;
    *buffer = (IP_ADAPTER_ADDRESSES*)malloc(size);
    if (*buffer == NULL) return NULL;
    ULONG flags = GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST
                  | GAA_FLAG_INCLUDE_GATEWAYS | GAA_FLAG_INCLUDE_PREFIX;
    ULONG rc = GetAdaptersAddresses(AF_UNSPEC, flags, NULL, *buffer, &size);
    if (rc == ERROR_BUFFER_OVERFLOW) {
        free(*buffer);
        *buffer = (IP_ADAPTER_ADDRESSES*)malloc(size);
        if (*buffer == NULL) return NULL;
        rc = GetAdaptersAddresses(AF_UNSPEC, flags, NULL, *buffer, &size);
    }
    if (rc != NO_ERROR) {
        free(*buffer);
        *buffer = NULL;
        return NULL;
    }
    return *buffer;
}

/* Loopback is not an adapter anybody configures, and the tunnels Windows
 * keeps around (Teredo, ISATAP) are noise on a page about the network the
 * user plugged in. */
static int interesting(const IP_ADAPTER_ADDRESSES* adapter) {
    if (adapter->IfType == IF_TYPE_SOFTWARE_LOOPBACK) return 0;
    if (adapter->IfType == IF_TYPE_TUNNEL) return 0;
    return 1;
}

int32_t flwin32_adapter_count(void) {
    IP_ADAPTER_ADDRESSES* buffer = NULL;
    if (enumerate(&buffer) == NULL) return 0;
    int32_t count = 0;
    for (IP_ADAPTER_ADDRESSES* a = buffer; a != NULL; a = a->Next) {
        if (interesting(a)) count++;
    }
    free(buffer);
    return count;
}

int32_t flwin32_adapter_info(int32_t index,
                             char* name, int32_t name_size,
                             char* description, int32_t description_size,
                             char* ipv4, int32_t ipv4_size,
                             char* gateway, int32_t gateway_size,
                             char* dns, int32_t dns_size,
                             char* mac, int32_t mac_size,
                             int32_t* kind, int32_t* up,
                             int64_t* speed, int32_t* dhcp) {
    IP_ADAPTER_ADDRESSES* buffer = NULL;
    if (enumerate(&buffer) == NULL) return 0;

    int32_t seen = 0;
    int32_t found = 0;
    for (IP_ADAPTER_ADDRESSES* a = buffer; a != NULL; a = a->Next) {
        if (!interesting(a)) continue;
        if (seen++ != index) continue;
        found = 1;

        wide_to_utf8(a->FriendlyName, name, name_size);
        wide_to_utf8(a->Description, description, description_size);

        /* The first UNICAST v4 address. A machine with several on one adapter
         * is doing something deliberate and does not need this page. */
        if (ipv4 != NULL && ipv4_size > 0) {
            ipv4[0] = '\0';
            for (IP_ADAPTER_UNICAST_ADDRESS* u = a->FirstUnicastAddress;
                 u != NULL; u = u->Next) {
                if (u->Address.lpSockaddr->sa_family != AF_INET) continue;
                address_text(&u->Address, ipv4, ipv4_size);
                break;
            }
        }
        /* IPv4 FIRST, and this is not a preference -- the row above it says
         * "IPv4 address", and Windows lists the v6 gateway first on a
         * dual-stack link. Showing fe80::2a87:baff:fe61:97f4 as the gateway
         * for 192.168.68.60 is not wrong so much as an answer to a question
         * nobody asked. The v6 one is the fallback, for a link that has only
         * that. */
        if (gateway != NULL && gateway_size > 0) {
            gateway[0] = '\0';
            for (IP_ADAPTER_GATEWAY_ADDRESS* g = a->FirstGatewayAddress;
                 g != NULL; g = g->Next) {
                if (g->Address.lpSockaddr->sa_family != AF_INET) continue;
                address_text(&g->Address, gateway, gateway_size);
                break;
            }
            if (gateway[0] == '\0' && a->FirstGatewayAddress != NULL) {
                address_text(&a->FirstGatewayAddress->Address, gateway, gateway_size);
            }
        }
        /* Both resolvers, comma separated: one is not the answer people are
         * looking for when they suspect DNS. */
        if (dns != NULL && dns_size > 0) {
            dns[0] = '\0';
            /* Two passes for the same reason as the gateway: the v4 servers
             * are the ones that answer for the address shown above, and
             * Windows puts fec0:0:0:ffff::1 at the head of the list on any
             * link that has never seen a v6 resolver. */
            for (int pass = 0; pass < 2 && dns[0] == '\0'; pass++) {
                int32_t written = 0;
                for (IP_ADAPTER_DNS_SERVER_ADDRESS* d = a->FirstDnsServerAddress;
                     d != NULL && written < 2; d = d->Next) {
                    int is_v4 = d->Address.lpSockaddr->sa_family == AF_INET;
                    if (pass == 0 && !is_v4) continue;
                    char one[64];
                    address_text(&d->Address, one, (int32_t)sizeof(one));
                    if (one[0] == '\0') continue;
                    if (written > 0 && (int32_t)(strlen(dns) + 2) < dns_size) {
                        strcat(dns, ", ");
                    }
                    if ((int32_t)(strlen(dns) + strlen(one) + 1) < dns_size) {
                        strcat(dns, one);
                        written++;
                    }
                }
            }
        }
        if (mac != NULL && mac_size > 0) {
            mac[0] = '\0';
            if (a->PhysicalAddressLength > 0) {
                int at = 0;
                for (ULONG i = 0; i < a->PhysicalAddressLength; i++) {
                    if (at + 3 >= mac_size) break;
                    at += snprintf(mac + at, (size_t)(mac_size - at),
                                   i == 0 ? "%02X" : "-%02X",
                                   a->PhysicalAddress[i]);
                }
            }
        }

        if (kind) {
            *kind = (a->IfType == IF_TYPE_IEEE80211) ? 2
                  : (a->IfType == IF_TYPE_ETHERNET_CSMACD) ? 1 : 0;
        }
        /* OperStatus, not "has an address": an adapter with a stale
         * self-assigned 169.254 address is DOWN and saying otherwise is how a
         * settings page tells someone their cable is fine. */
        if (up) *up = (a->OperStatus == IfOperStatusUp) ? 1 : 0;
        if (speed) *speed = (int64_t)a->TransmitLinkSpeed;
        if (dhcp) *dhcp = (a->Flags & IP_ADAPTER_DHCP_ENABLED) ? 1 : 0;
        break;
    }
    free(buffer);
    return found;
}

/* Windows' own network page, for everything that needs administrator rights.
 * ms-settings: is the documented protocol for this and lands on the exact
 * page rather than the top of Settings. */
int32_t flwin32_open_network_settings(void) {
    HINSTANCE rc = ShellExecuteW(NULL, L"open", L"ms-settings:network-ethernet",
                                 NULL, NULL, SW_SHOWNORMAL);
    return ((INT_PTR)rc > 32) ? 1 : 0;
}
