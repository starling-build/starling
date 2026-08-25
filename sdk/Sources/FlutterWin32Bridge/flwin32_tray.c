// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/*
 * flwin32_tray.c -- hosting the notification area.
 *
 * Hiding explorer's taskbar takes the tray with it, and with it every app
 * that lives in the tray rather than in a window: Discord, Slack, Teams,
 * OneDrive, the VPN client. This is the protocol behind Shell_NotifyIcon, and
 * none of it is documented.
 *
 * WHAT SHELL_NOTIFYICON ACTUALLY DOES: it looks up a window of class
 * "Shell_TrayWnd" and sends it WM_COPYDATA carrying the NOTIFYICONDATA the
 * caller passed. So a shell hosts the tray by BEING that window. Nothing
 * registers, nothing is granted: the class name is the whole contract.
 *
 * HOW EXISTING ICONS ARE FOUND: they are not. There is no enumeration. A new
 * taskbar broadcasts the registered message "TaskbarCreated" and every app is
 * required to re-add its icons in response -- that is the documented
 * obligation on the app side, and the only way in.
 *
 * WHAT THE PROBE ESTABLISHED (Windows 11 25H2, build 26200, and it is all
 * still reachable with --tray-probe):
 *
 *  - Our window IS the one Shell_NotifyIcon finds, with explorer running and
 *    its taskbar merely hidden. The lookup walks top-level windows in z-order
 *    and ours is created later in the same topmost band, so it comes first.
 *  - The payload is the 32-BIT NOTIFYICONDATAW -- handles as DWORDs -- even
 *    from 64-bit callers, behind an 8-byte header of magic 0x34753423 and the
 *    NIM_* message. cbSize arrives as 956, which is that struct exactly.
 *  - Another process's hIcon IS usable here: CopyIcon succeeds and gives a
 *    32x32 icon. Icons are session-wide USER handles, so the shell can draw
 *    them without asking anyone.
 *  - APPBAR MESSAGES COME DOWN THE SAME PIPE (dwData 0). SHAppBarMessage
 *    looks up Shell_TrayWnd exactly like Shell_NotifyIcon does, so taking the
 *    class takes the appbar protocol with it -- including the reservation our
 *    OWN dock makes for its strip. Anything not ours is forwarded to
 *    explorer's window, which still answers.
 */

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>

#include "include/FlutterWin32Bridge.h"

/* SHLockShared/SHUnlockShared, for reading appbar results back to callers.
 * Package.swift links shlwapi too -- belt and braces, same as dwmapi. */
#pragma comment(lib, "shlwapi")

/* The payload of the tray WM_COPYDATA is NOT the NOTIFYICONDATAW this process
 * compiles against. It is the 32-BIT layout -- handles as DWORDs, no padding
 * around them -- sent by 64-bit callers too, because the wire format froze
 * before the 64-bit port and shell32 marshals into it. Read it with the
 * native struct and every field past uID is shifted: the giveaway was an
 * hIcon of 0x0065007600690072, which is "rive", four characters into
 * "OneDrive"'s tooltip. The full 32-bit struct measures 956 bytes, which is
 * exactly the cbSize that arrives.
 *
 * #pragma pack(1) rather than 4: every field here is naturally aligned inside
 * a 4-byte world, so packing changes nothing except that it cannot be
 * silently widened by a future compiler default. */
#pragma pack(push, 1)
typedef struct {
  DWORD cbSize;
  DWORD hWnd;             /* a HWND truncated to 32 bits */
  DWORD uID;
  DWORD uFlags;
  DWORD uCallbackMessage;
  DWORD hIcon;            /* likewise an HICON */
  WCHAR szTip[128];
  DWORD dwState;
  DWORD dwStateMask;
  WCHAR szInfo[256];
  DWORD uVersion;
  WCHAR szInfoTitle[64];
  DWORD dwInfoFlags;
  GUID guidItem;
  DWORD hBalloonIcon;
} FlTrayIconData;         /* 956 bytes */
#pragma pack(pop)

/* Fails the BUILD rather than the desktop if the layout ever drifts: a struct
 * that is silently 8 bytes longer reads tooltips as icon handles, which is a
 * blank tray and no error anywhere. */
typedef char fl_tray_layout_check[(sizeof(FlTrayIconData) == 956) ? 1 : -1];

/* V1 stopped at a 64-character tip; everything after szTip arrived later, and
 * an app built against the old headers sends the short struct. cbSize is the
 * only honest guide to what is actually there. */
#define kNidV1Size (offsetof(FlTrayIconData, szTip) + 64 * sizeof(WCHAR))

static HWND g_tray;
static HWND g_notify;

static void describe(HWND hwnd, const char* label) {
  DWORD pid = 0;
  wchar_t cls[64] = {0};
  wchar_t exe[MAX_PATH] = {0};
  GetWindowThreadProcessId(hwnd, &pid);
  GetClassNameW(hwnd, cls, 64);
  HANDLE proc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (proc != NULL) {
    DWORD n = MAX_PATH;
    QueryFullProcessImageNameW(proc, 0, exe, &n);
    CloseHandle(proc);
  }
  const wchar_t* base = wcsrchr(exe, L'\\');
  base = (base != NULL) ? base + 1 : exe;
  LONG_PTR ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
  printf("[tray] %s hwnd=0x%p pid=%lu (%ls) class=%ls visible=%d topmost=%d%s\n",
         label, (void*)hwnd, (unsigned long)pid, base, cls,
         IsWindowVisible(hwnd) ? 1 : 0,
         (ex & WS_EX_TOPMOST) ? 1 : 0,
         (hwnd == g_tray) ? "  <== OURS" : "");
  fflush(stdout);
}

static BOOL CALLBACK list_trays(HWND hwnd, LPARAM param) {
  wchar_t cls[64] = {0};
  GetClassNameW(hwnd, cls, 64);
  if (wcscmp(cls, L"Shell_TrayWnd") == 0) {
    describe(hwnd, "  candidate");
    (*(int*)param)++;
  }
  return TRUE;
}

static const char* nim_name(DWORD m) {
  switch (m) {
    case NIM_ADD: return "NIM_ADD";
    case NIM_MODIFY: return "NIM_MODIFY";
    case NIM_DELETE: return "NIM_DELETE";
    case NIM_SETFOCUS: return "NIM_SETFOCUS";
    case NIM_SETVERSION: return "NIM_SETVERSION";
    default: return "NIM_?";
  }
}

static void hexdump(const char* label, void* data, DWORD len, DWORD max) {
  unsigned char* p = (unsigned char*)data;
  DWORD n = len < max ? len : max;
  for (DWORD i = 0; i < n; i += 16) {
    printf("[tray]   %s +%03lu:", label, (unsigned long)i);
    for (DWORD j = i; j < i + 16 && j < n; j++) printf(" %02X", p[j]);
    printf("\n");
  }
  fflush(stdout);
}

/* Is the handle the wire gave us a real icon in this process? The whole plan
 * rests on the answer: an HICON is a session-wide USER handle, so another
 * process's icon can be drawn here -- but only if that is actually what the
 * field holds. */
static void check_icon(DWORD raw) {
  if (raw == 0) { printf("[tray]   icon: none\n"); return; }
  HICON icon = (HICON)(ULONG_PTR)raw;
  HICON copy = CopyIcon(icon);
  if (copy == NULL) {
    printf("[tray]   icon: 0x%08lX NOT usable here (CopyIcon: %lu)\n",
           (unsigned long)raw, GetLastError());
    return;
  }
  ICONINFO info;
  BITMAP bm;
  ZeroMemory(&info, sizeof(info));
  int w = 0, h = 0;
  if (GetIconInfo(copy, &info)) {
    if (info.hbmColor != NULL && GetObject(info.hbmColor, sizeof(bm), &bm)) {
      w = bm.bmWidth; h = bm.bmHeight;
    } else if (info.hbmMask != NULL && GetObject(info.hbmMask, sizeof(bm), &bm)) {
      w = bm.bmWidth; h = bm.bmHeight / 2;
    }
    if (info.hbmColor) DeleteObject(info.hbmColor);
    if (info.hbmMask) DeleteObject(info.hbmMask);
  }
  printf("[tray]   icon: 0x%08lX usable, %dx%d\n", (unsigned long)raw, w, h);
  DestroyIcon(copy);
  fflush(stdout);
}

static void dump_tray_copydata(COPYDATASTRUCT* cds) {
  if (cds->cbData < 8 + kNidV1Size) {
    printf("[tray] tray payload too small: cb=%lu\n", (unsigned long)cds->cbData);
    return;
  }
  DWORD* head = (DWORD*)cds->lpData;
  FlTrayIconData* n = (FlTrayIconData*)((char*)cds->lpData + 8);
  wchar_t tip[129];
  size_t tipmax = (n->cbSize > kNidV1Size) ? 128 : 64;
  memcpy(tip, n->szTip, tipmax * sizeof(wchar_t));
  tip[tipmax] = 0;
  for (wchar_t* c = tip; *c; c++) if (*c == L'\r' || *c == L'\n') *c = L' ';
  printf("[tray] %-14s cb=%lu magic=0x%08lX cbSize=%lu hwnd=0x%08lX id=%lu "
         "flags=0x%lX cbmsg=0x%lX icon=0x%08lX ver=%lu tip=\"%ls\"\n",
         nim_name(head[1]), (unsigned long)cds->cbData,
         (unsigned long)head[0], (unsigned long)n->cbSize,
         (unsigned long)n->hWnd, (unsigned long)n->uID,
         (unsigned long)n->uFlags, (unsigned long)n->uCallbackMessage,
         (unsigned long)n->hIcon,
         (n->cbSize > kNidV1Size) ? (unsigned long)n->uVersion : 0UL, tip);
  if (head[1] == NIM_ADD || head[1] == NIM_MODIFY) check_icon(n->hIcon);
  /* Once, so the exact wire layout is on the record rather than inferred. */
  static int dumped = 0;
  if (!dumped) {
    dumped = 1;
    printf("[tray]   raw payload, cb=%lu (header 8 + %lu struct + %ld trailing):\n",
           (unsigned long)cds->cbData, (unsigned long)n->cbSize,
           (long)cds->cbData - 8 - (long)n->cbSize);
    hexdump("head", cds->lpData, cds->cbData, 64);
    printf("[tray]   tail (last 32 bytes):\n");
    hexdump("tail", (char*)cds->lpData + cds->cbData - 32, 32, 32);
  }
  fflush(stdout);
}

static void dump_unknown(COPYDATASTRUCT* cds) {
  printf("[tray] OTHER dwData=%llu cb=%lu\n",
         (unsigned long long)cds->dwData, (unsigned long)cds->cbData);
  /* 64, not 32: the appbar payload is 64 bytes and the fields that matter for
   * serving it -- dwMessage, hSharedMemory, the caller's pid -- are the ones
   * past 40 that the shorter dump never showed. */
  hexdump("ab", cds->lpData, cds->cbData, 64);
  fflush(stdout);
}

/* ── the icon table ─────────────────────────────────────────────────────────
 *
 * IDENTITY IS NOT ALWAYS (hwnd, uID). An icon that set NIF_GUID is addressed
 * by its GUID for the rest of its life, and its later NIM_MODIFY/NIM_DELETE
 * arrive with uID 0 and no window -- the probe caught exactly that: a delete
 * with flags=0x20 and nothing else filled in. Key on the GUID when there is
 * one, or the pair when there is not, and a shell that gets this wrong grows
 * a tray full of icons that will not go away. */

typedef struct {
  uint64_t key;      /* ours, stable, handed to the shell as an identity */
  int has_guid;
  GUID guid;
  HWND owner;
  UINT id;
  UINT callback;
  UINT version;
  int version_declared; /* whether NIM_SETVERSION said so, or we inferred it */
  int promoted;      /* whether Windows' own setting puts it on the bar */
  HICON icon;        /* OUR copy: the app may destroy its own at any time */
  uint32_t generation; /* bumped whenever the icon itself changes, so a cache
                        * keyed on it re-rasterizes and one keyed on the key
                        * alone does not go stale */
  wchar_t tip[129];
  int hidden;
} FlTrayEntry;

#define kMaxTrayIcons 128

/* ── which icons Windows itself would show ───────────────────────────────────
 *
 * Windows 11 does not put every notification icon on the bar. Each one is
 * PROMOTED or not, the user decides per icon, and the rest live behind the
 * chevron. The setting is per user in
 *
 *     HKCU\Control Panel\NotifyIconSettings\<hash>
 *
 * with IsPromoted (absent means no -- a new icon is hidden by default, which
 * is why an app you just installed does not appear on the taskbar), and an
 * identity to match on: IconGuid for the icons registered with a GUID, or
 * UID plus ExecutablePath for the rest.
 *
 * ExecutablePath is not a path. It is a KNOWNFOLDERID in braces followed by
 * the rest -- {1AC14E77-...}\SecurityHealthSystray.exe is System32 -- so it
 * has to be expanded before it can be compared to anything. Reading it raw
 * matches nothing and silently hides every icon.
 *
 * Ignoring all this and showing everything is what we did first, and it is
 * wrong in the direction that shows: this machine promotes exactly ONE icon
 * of seven, so our strip had three where explorer's had one. */

typedef struct {
  int has_guid;
  GUID guid;
  int has_uid;
  DWORD uid;
  wchar_t exe[MAX_PATH];
  int promoted;
} FlTraySetting;

#define kMaxTraySettings 64
static FlTraySetting g_settings[kMaxTraySettings];
static int g_setting_count;
static DWORD g_settings_read_at;
static uint64_t g_revision = 1;

static CRITICAL_SECTION g_lock;
static int g_lock_ready;
static FlTrayEntry g_icons[kMaxTrayIcons];
static int g_count;
static uint64_t g_next_key = 1;
static int g_probing;
/* STARLING_TRAY_DEBUG=1 prints what happens to a click. The foreground rules
 * are where tray forwarding goes wrong, and they fail silently -- an app whose
 * SetForegroundWindow was refused draws a menu that dismisses itself in the
 * same frame, which looks exactly like a click that never arrived. */
static int g_debug = -1;
static void (*g_changed)(void* user);
static void* g_changed_user;

/* "{GUID}\rest" -> "C:\real\folder\rest". Anything without the brace form
 * is already a path and is copied through. */
static void expand_known_folder(const wchar_t* in, wchar_t* out, size_t n) {
  out[0] = 0;
  if (in == NULL || in[0] != L'{') {
    if (in != NULL) wcsncpy(out, in, n - 1);
    out[n - 1] = 0;
    return;
  }
  const wchar_t* close = wcschr(in, L'}');
  if (close == NULL) return;
  wchar_t id[64] = {0};
  size_t len = (size_t)(close - in) + 1;
  if (len >= 64) return;
  wcsncpy(id, in, len);
  GUID folder;
  if (FAILED(IIDFromString(id, &folder))) return;
  PWSTR base = NULL;
  if (FAILED(SHGetKnownFolderPath(&folder, 0, NULL, &base)) || base == NULL) return;
  const wchar_t* rest = close + 1;
  if (*rest == L'\\') rest++;
  _snwprintf(out, n - 1, L"%ls\\%ls", base, rest);
  out[n - 1] = 0;
  CoTaskMemFree(base);
}

/* Re-reads HKCU\Control Panel\NotifyIconSettings. Throttled: the user
 * changes this in Settings, which sends us nothing, so it has to be polled --
 * but seven subkeys once every couple of seconds is the whole cost, and the
 * shell asks for it on the tick it already has. */
static int read_settings(void) {
  DWORD now = GetTickCount();
  /* A quarter second, not two: the throttle is here so a per-frame snapshot
   * does not re-enumerate the key, and it was two seconds when a poll asked
   * every second anyway. Now the ASK is a registry-change event, and a
   * throttle longer than the gap between two edits would swallow the second
   * one with nothing left to re-arm it. */
  if (g_setting_count > 0 && (now - g_settings_read_at) < 250) return 0;
  g_settings_read_at = now;

  HKEY root;
  if (RegOpenKeyExW(HKEY_CURRENT_USER,
                    L"Control Panel\\NotifyIconSettings", 0,
                    KEY_READ, &root) != ERROR_SUCCESS) {
    return 0;
  }
  FlTraySetting fresh[kMaxTraySettings];
  int count = 0;
  for (DWORD i = 0; count < kMaxTraySettings; i++) {
    wchar_t name[128];
    DWORD name_len = 128;
    if (RegEnumKeyExW(root, i, name, &name_len, NULL, NULL, NULL, NULL)
        != ERROR_SUCCESS) {
      break;
    }
    HKEY item;
    if (RegOpenKeyExW(root, name, 0, KEY_READ, &item) != ERROR_SUCCESS) continue;
    FlTraySetting* out = &fresh[count];
    ZeroMemory(out, sizeof(*out));

    wchar_t buf[MAX_PATH * 2];
    DWORD size = sizeof(buf);
    DWORD type = 0;
    if (RegQueryValueExW(item, L"IconGuid", NULL, &type, (LPBYTE)buf, &size)
            == ERROR_SUCCESS && type == REG_SZ) {
      buf[(size / sizeof(wchar_t)) < 1 ? 0 : (size / sizeof(wchar_t)) - 1] = 0;
      if (SUCCEEDED(IIDFromString(buf, &out->guid))) out->has_guid = 1;
    }
    DWORD dw = 0;
    size = sizeof(dw);
    if (RegQueryValueExW(item, L"UID", NULL, &type, (LPBYTE)&dw, &size)
            == ERROR_SUCCESS && type == REG_DWORD) {
      out->has_uid = 1;
      out->uid = dw;
    }
    size = sizeof(buf);
    if (RegQueryValueExW(item, L"ExecutablePath", NULL, &type, (LPBYTE)buf, &size)
            == ERROR_SUCCESS && type == REG_SZ) {
      buf[(size / sizeof(wchar_t)) < 1 ? 0 : (size / sizeof(wchar_t)) - 1] = 0;
      expand_known_folder(buf, out->exe, MAX_PATH);
    }
    dw = 0;
    size = sizeof(dw);
    /* Absent means not promoted. A new icon is hidden until the user says
     * otherwise -- that is Windows 11's default, not an omission. */
    if (RegQueryValueExW(item, L"IsPromoted", NULL, &type, (LPBYTE)&dw, &size)
            == ERROR_SUCCESS && type == REG_DWORD) {
      out->promoted = (dw != 0);
    }
    RegCloseKey(item);
    if (out->has_guid || out->has_uid) count++;
  }
  RegCloseKey(root);

  int changed = (count != g_setting_count) ||
                (memcmp(fresh, g_settings, sizeof(FlTraySetting) * (size_t)count) != 0);
  memcpy(g_settings, fresh, sizeof(FlTraySetting) * (size_t)count);
  g_setting_count = count;
  return changed;
}

/* The owning process's image, which is half of the identity for an icon that
 * did not register a GUID. */
static void owner_exe(HWND owner, wchar_t* out, size_t n) {
  out[0] = 0;
  DWORD pid = 0;
  GetWindowThreadProcessId(owner, &pid);
  if (pid == 0) return;
  HANDLE proc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (proc == NULL) return;
  DWORD len = (DWORD)n;
  QueryFullProcessImageNameW(proc, 0, out, &len);
  CloseHandle(proc);
}

static int is_promoted(const FlTrayEntry* e) {
  wchar_t exe[MAX_PATH];
  owner_exe(e->owner, exe, MAX_PATH);
  for (int i = 0; i < g_setting_count; i++) {
    const FlTraySetting* s = &g_settings[i];
    if (e->has_guid && s->has_guid) {
      if (IsEqualGUID(&e->guid, &s->guid)) return s->promoted;
      continue;
    }
    if (!e->has_guid && s->has_uid && s->uid == e->id && exe[0] != 0 &&
        _wcsicmp(exe, s->exe) == 0) {
      return s->promoted;
    }
  }
  /* No entry at all: Windows hides an icon it has not been told about. */
  return 0;
}

static void lock_init(void) {
  if (!g_lock_ready) {
    InitializeCriticalSection(&g_lock);
    g_lock_ready = 1;
  }
}

static int same_icon(const FlTrayEntry* e, const FlTrayIconData* n, int has_guid) {
  if (has_guid && e->has_guid) return IsEqualGUID(&e->guid, &n->guidItem);
  if (has_guid != e->has_guid) return 0;
  return e->owner == (HWND)(ULONG_PTR)n->hWnd && e->id == n->uID;
}

static void entry_clear_icon(FlTrayEntry* e) {
  if (e->icon != NULL) {
    DestroyIcon(e->icon);
    e->icon = NULL;
  }
}

/* Applies one message. Sets *changed when the visible set moved, and returns
 * what to REPLY -- which is not a formality:
 *
 * The near-universal way an app answers TaskbarCreated is
 *
 *     if (!Shell_NotifyIcon(NIM_MODIFY, &nid)) Shell_NotifyIcon(NIM_ADD, &nid);
 *
 * and a modify carries only the fields that changed. A shell that says TRUE
 * to a modify for an icon it has never seen gets a record with no callback
 * message and no version -- an icon it can draw and can never click, because
 * the app is now satisfied and will never send the full record. That is
 * exactly what Windows Security and the monitor applet did here: they sat in
 * the strip, correct and dead, while OneDrive worked.
 *
 * A fresh taskbar has no such icon and the modify legitimately fails, so the
 * honest answer is FALSE and the app re-adds itself properly. The entry is
 * still created from what the modify carried, so the icon appears either way
 * -- an app that ignores the failure keeps its picture, and one that handles
 * it upgrades to a record we can actually use. */
static BOOL apply_change(DWORD message, const FlTrayIconData* n, int* changed) {
  int has_guid = (n->uFlags & NIF_GUID) != 0;
  int index = -1;
  for (int i = 0; i < g_count; i++) {
    if (same_icon(&g_icons[i], n, has_guid)) { index = i; break; }
  }

  if (message == NIM_DELETE) {
    if (index < 0) return FALSE;
    entry_clear_icon(&g_icons[index]);
    for (int i = index; i < g_count - 1; i++) g_icons[i] = g_icons[i + 1];
    g_count--;
    *changed = 1;
    return TRUE;
  }

  if (message == NIM_SETVERSION) {
    if (index < 0) return FALSE;
    /* uVersion shares its slot with uTimeout; on this message it is the
     * version. It decides the SHAPE OF EVERY CLICK we send this icon later. */
    g_icons[index].version = n->uVersion;
    g_icons[index].version_declared = 1;
    return TRUE;
  }

  if (message != NIM_ADD && message != NIM_MODIFY) return FALSE;

  /* See the note above: a modify we could not match is answered with FALSE so
   * the app re-adds itself, but the icon is still put on the strip. */
  BOOL accepted = (message == NIM_ADD) || (index >= 0);

  if (index < 0) {
    if (g_count >= kMaxTrayIcons) return FALSE;
    index = g_count++;
    ZeroMemory(&g_icons[index], sizeof(FlTrayEntry));
    g_icons[index].key = g_next_key++;
    g_icons[index].owner = (HWND)(ULONG_PTR)n->hWnd;
    g_icons[index].id = n->uID;
    g_icons[index].has_guid = has_guid;
    if (has_guid) g_icons[index].guid = n->guidItem;
  }

  FlTrayEntry* e = &g_icons[index];
  /* uFlags says which fields the caller actually filled in. Reading one it
   * did not is how a tooltip becomes garbage and an icon becomes a crash. */
  if (n->uFlags & NIF_MESSAGE) e->callback = n->uCallbackMessage;
  if (n->uFlags & NIF_ICON) {
    entry_clear_icon(e);
    if (n->hIcon != 0) e->icon = CopyIcon((HICON)(ULONG_PTR)n->hIcon);
    e->generation++;
  }
  if (n->uFlags & NIF_TIP) {
    size_t max = (n->cbSize > kNidV1Size) ? 128 : 64;
    memcpy(e->tip, n->szTip, max * sizeof(wchar_t));
    e->tip[max] = 0;
    /* A multi-line tip is normal ("OneDrive - Personal\nNot signed in") and a
     * dock strip has one line. */
    for (wchar_t* c = e->tip; *c; c++) if (*c == L'\r' || *c == L'\n') *c = L' ';
  }
  /* WHICH VERSION, when the app never says.
   *
   * An app is supposed to answer TaskbarCreated with NIM_ADD and then
   * NIM_SETVERSION. Some answer with a bare NIM_MODIFY -- both of this
   * machine's Microsoft-written icons do -- and then the shell is holding an
   * icon whose click convention it was never told. Guessing legacy is not
   * neutral: a version 4 app reads our wParam as its icon id, gets a
   * mismatch, and silently ignores every click. That is exactly how Windows
   * Security and the monitor applet sat there doing nothing while OneDrive,
   * which did send NIM_SETVERSION, worked.
   *
   * NIF_SHOWTIP is the tell. It is documented as having meaning only when
   * uVersion is NOTIFYICON_VERSION_4 -- it asks for the standard tooltip that
   * version 4 otherwise suppresses -- so an app that sets it is an app that
   * asked for version 4 at some point, whether or not we were listening. An
   * explicit NIM_SETVERSION still wins. */
  if (!e->version_declared && (n->uFlags & NIF_SHOWTIP)) {
    e->version = 4;
  }
  if (n->uFlags & NIF_STATE) {
    if (n->dwStateMask & NIS_HIDDEN) {
      e->hidden = (n->dwState & NIS_HIDDEN) ? 1 : 0;
    }
  }
  /* Settled when the icon arrives, and again whenever the setting changes
   * (see flwin32_tray_revision) -- not per snapshot, which would be an
   * OpenProcess per icon per frame. */
  read_settings();
  e->promoted = is_promoted(e);
  *changed = 1;
  return accepted;
}

/* Explorer's own Shell_TrayWnd -- the one that was answering before we took
 * the name, and the one anything we do not implement has to be handed on to. */
static HWND g_explorer_tray;

static BOOL CALLBACK find_explorer(HWND hwnd, LPARAM param) {
  wchar_t cls[64] = {0};
  GetClassNameW(hwnd, cls, 64);
  if (wcscmp(cls, L"Shell_TrayWnd") == 0 && hwnd != g_tray) {
    *(HWND*)param = hwnd;
    return FALSE;
  }
  return TRUE;
}

static HWND explorer_tray(void) {
  if (g_explorer_tray == NULL || !IsWindow(g_explorer_tray)) {
    g_explorer_tray = NULL;
    EnumWindows(find_explorer, (LPARAM)&g_explorer_tray);
  }
  return g_explorer_tray;
}

/* ── the appbar service ──────────────────────────────────────────────────────
 *
 * SHAppBarMessage marshals its APPBARDATA into a WM_COPYDATA (dwData 0) to
 * whatever window the Shell_TrayWnd class resolves to. While explorer runs
 * that is explorer's problem and we forward; with explorer gone -- or with
 * STARLING_TRAY_OWN=1 forcing it for a test -- nothing else will answer, and
 * "nothing answers" means no dock reservation, no work area, and maximized
 * windows underneath the dock.
 *
 * The wire, pinned by a live 64-byte probe dump (Windows 11 25H2): the packed
 * 32-bit APPBARDATA -- DWORD handles, 8-byte lParam, 40 bytes ending at the
 * cbSize it declares -- then three 8-byte fields: the ABM_* message, the
 * shared-section handle for struct results, and the pid that handle is valid
 * in. That pid was OUR OWN in every observed message: shell32 duplicates the
 * section handle into the tray's process before sending, so the answer path
 * is usually a bare MapViewOfFile. The sender reads the section back and
 * frees the handle (SHFreeShared) after our SendMessage returns, which is
 * why the wire handle must be left open here.
 */
#pragma pack(push, 1)
typedef struct {
  DWORD cbSize;
  DWORD hWnd;             /* a HWND truncated to 32 bits, like the tray wire */
  DWORD uCallbackMessage;
  DWORD uEdge;
  RECT rc;
  UINT64 lParam;
} FlAppBarData32;         /* 40 bytes -- the cbSize the wire declares */

typedef struct {
  FlAppBarData32 abd;
  UINT64 dwMessage;
  UINT64 hSharedMemory;
  UINT64 dwSourceProcessId;
} FlAppBarEnvelope;       /* 64 bytes -- the observed cbData, exactly */
#pragma pack(pop)

typedef char fl_appbar_layout_check[(sizeof(FlAppBarEnvelope) == 64) ? 1 : -1];

/* Everything below is touched only on the tray window's thread -- WM_COPYDATA
 * lands there and nowhere else -- so unlike the icon table it needs no lock.
 * (flwin32_tray_stop resets it, and DestroyWindow already ties stop to this
 * same thread.) */
typedef struct {
  HWND hwnd;
  UINT callback;
  UINT edge;              /* granted edge, or (UINT)-1 before any SETPOS */
  RECT rect;              /* granted rect */
  int has_rect;
  int is_explorer;        /* a claim we grant but do not honour -- see below */
} FlAppBarEntry;

#define kMaxAppBars 16
static FlAppBarEntry g_bars[kMaxAppBars];
static int g_bar_count;
static UINT g_ab_state = ABS_ALWAYSONTOP;  /* what explorer reports by default */
static HWND g_autohide[4];                 /* one slot per ABE_* edge */
static RECT g_wa_saved;
static int g_wa_saved_valid;
static int g_wa_dirty;
static int g_wa_applying;
static DWORD g_stomp_since;   /* start of the current burst of repairs */
static int g_stomp_count;
static int g_stomp_gave_up;
static int g_own = -1;

/* WHO OWNS THE WORK AREA -- which is "who is the SHELL", not "does an
 * explorer process exist".
 *
 * The first spelling of this asked whether explorer's Shell_TrayWnd was gone,
 * and it was wrong in the one configuration that matters. With the
 * packaged-app explorer service running, explorer IS alive, so every appbar
 * message was forwarded to it -- and explorer, which is not the shell there,
 * never recorded the dock. The strip was drawn and nothing was reserved, so
 * maximized windows ran underneath the dock. Reproducible by restarting the
 * shell while explorer is alive, which is also what a crash respawn and every
 * deploy do.
 *
 * Why the forward loses OUR registration in particular, while a third-party
 * appbar forwards through it perfectly well: shell32 hands a SAME-PROCESS
 * caller a direct heap pointer instead of a shared section (see
 * appbar_return), and the dock is in this process. Forwarded to explorer that
 * pointer addresses nothing, SHLockShared fails there, and the call is
 * dropped -- with TRUE returned to the dock, so it looks like it worked.
 * Measured on the box: with explorer alive the dock reserves nothing, while a
 * test appbar registered from ANOTHER process moves the work area exactly as
 * it should. That asymmetry is the whole bug, and it is invisible from the
 * dock's side.
 *
 * PROGMAN IS NOT THE TELL, however much it looks like one. The obvious rule
 * is "explorer has a desktop window, so explorer is the shell" -- and the
 * service explorer HAS a Progman; we hide it rather than prevent it, and
 * FindWindow finds hidden windows. A comment two files over says it stays
 * NULL, and a probe agreed, but the probe asked through PowerShell where a
 * $null string argument marshals as "" -- so it searched for a window TITLED
 * "" and of course found nothing. That is the same trap this tree has
 * recorded twice already, and it cost a whole build-and-verify round here.
 *
 * The honest tell is our own intent: this process hid explorer's taskbar,
 * so this process put a bar on that edge and took the minimize target -- it
 * IS the shell chrome, whatever else is running. A dock started
 * --keep-taskbar never claims it, and neither does any process that is not
 * the dock. */
static int appbar_serving(void) {
  if (g_own < 0) {
    const char* v = getenv("STARLING_TRAY_OWN");
    g_own = (v != NULL && v[0] != '\0' && v[0] != '0') ? 1 : 0;
  }
  if (g_own) return 1;
  if (flwin32_explorer_taskbar_hidden_by_us()) return 1;
  /* Re-checked per message rather than latched: explorer can exit at any
   * moment, and the first appbar call after it does is the one that must not
   * be forwarded into the void. */
  return explorer_tray() == NULL;
}

static const char* abm_name(UINT m) {
  switch (m) {
    case ABM_NEW: return "ABM_NEW";
    case ABM_REMOVE: return "ABM_REMOVE";
    case ABM_QUERYPOS: return "ABM_QUERYPOS";
    case ABM_SETPOS: return "ABM_SETPOS";
    case ABM_GETSTATE: return "ABM_GETSTATE";
    case ABM_GETTASKBARPOS: return "ABM_GETTASKBARPOS";
    case ABM_ACTIVATE: return "ABM_ACTIVATE";
    case ABM_GETAUTOHIDEBAR: return "ABM_GETAUTOHIDEBAR";
    case ABM_SETAUTOHIDEBAR: return "ABM_SETAUTOHIDEBAR";
    case ABM_WINDOWPOSCHANGED: return "ABM_WINDOWPOSCHANGED";
    case ABM_SETSTATE: return "ABM_SETSTATE";
    default: return "ABM_?";
  }
}

/* Write the (possibly modified) APPBARDATA back through the caller's shared
 * section -- QUERYPOS/SETPOS/GETTASKBARPOS results travel this way, not in
 * the SendMessage return. */
static void appbar_return(UINT64 hshared, UINT64 pid, const FlAppBarData32* abd) {
  if (hshared == 0) return;
  /* This is an SHAllocShared block, not a bare file mapping: a same-process
   * caller's "handle" arrives as a direct heap pointer (the dock's own
   * registration does), and a cross-process caller's as an object only
   * SHLockShared resolves -- MapViewOfFile on either is ERROR_INVALID_HANDLE.
   * The shlwapi pair is what explorer's own tray uses, so use it too; the
   * pid rides the wire precisely to be SHLockShared's second argument. */
  void* block = SHLockShared((HANDLE)(ULONG_PTR)hshared, (DWORD)pid);
  if (block == NULL) {
    if (g_probing || g_debug > 0) {
      printf("[tray] appbar return: SHLockShared(0x%llX, %llu) failed: %lu\n",
             (unsigned long long)hshared, (unsigned long long)pid,
             GetLastError());
      fflush(stdout);
    }
    return;
  }
  if (g_probing || g_debug > 0) {
    printf("[tray] appbar return block before write:\n");
    hexdump("abret", block, 64, 64);
  }
  memcpy(block, abd, sizeof(*abd));
  SHUnlockShared(block);
  /* Freeing is the sender's job (SHFreeShared), after it reads the result
   * our SendMessage return unblocks it to collect. */
}

/* EXPLORER'S TASKBAR DOES NOT GET TO RESERVE ANYTHING WHILE WE ARE THE SHELL.
 *
 * Its window is hidden -- that is the whole arrangement -- but hidden is not
 * the same as absent, and it registers an appbar like any other client. With
 * this service answering, that claim came straight out of the desktop: a
 * borrowed explorer, alive for barely two seconds during a packaged-app
 * launch, left the work area at 1824 instead of 2048 and it stayed there,
 * because the bar's window died with the process and nothing in the protocol
 * announces that.
 *
 * So the claim is granted -- the reply says where the bar may sit, which
 * explorer is entitled to know -- and then left out of the work area. That is
 * the same thing ABS_AUTOHIDE was being used to achieve, expressed once, here,
 * rather than depending on a state change landing before the window does. */
static int bar_is_explorer(HWND hwnd) {
  DWORD pid = 0;
  HANDLE proc;
  wchar_t path[MAX_PATH];
  DWORD len = MAX_PATH;
  const wchar_t* leaf;
  int is_it = 0;
  GetWindowThreadProcessId(hwnd, &pid);
  if (pid == 0 || pid == GetCurrentProcessId()) return 0;
  proc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (proc == NULL) return 0;
  if (QueryFullProcessImageNameW(proc, 0, path, &len)) {
    leaf = wcsrchr(path, L'\\');
    leaf = (leaf != NULL) ? leaf + 1 : path;
    is_it = (_wcsicmp(leaf, L"explorer.exe") == 0);
  }
  CloseHandle(proc);
  return is_it;
}

static FlAppBarEntry* bar_find(HWND hwnd) {
  for (int i = 0; i < g_bar_count; i++) {
    if (g_bars[i].hwnd == hwnd) return &g_bars[i];
  }
  return NULL;
}

/* An appbar whose process crashed never sends ABM_REMOVE; the dead window is
 * the only notice we get, same as the icon table. */
static void bars_gc(void) {
  for (int i = g_bar_count - 1; i >= 0; i--) {
    if (!IsWindow(g_bars[i].hwnd)) {
      for (int j = i; j < g_bar_count - 1; j++) g_bars[j] = g_bars[j + 1];
      g_bar_count--;
    }
  }
}

static void bars_notify(HWND except, UINT code) {
  for (int i = 0; i < g_bar_count; i++) {
    if (g_bars[i].hwnd == except || g_bars[i].callback == 0) continue;
    PostMessageW(g_bars[i].hwnd, g_bars[i].callback, (WPARAM)code, 0);
  }
}

/* The work area is the reservation made real: explorer derives it from its
 * taskbar plus every registered appbar, and maximized windows size to it. With
 * explorer out of the picture that duty is ours, or the dock is a strip that
 * maximized windows sit underneath. */
static int workarea_wanted(RECT* out) {
  POINT origin = {0, 0};
  MONITORINFO mi;
  ZeroMemory(&mi, sizeof(mi));
  mi.cbSize = sizeof(mi);
  if (!GetMonitorInfoW(MonitorFromPoint(origin, MONITOR_DEFAULTTOPRIMARY), &mi)) return 0;
  RECT wa = mi.rcMonitor;
  for (int i = 0; i < g_bar_count; i++) {
    if (!g_bars[i].has_rect || g_bars[i].is_explorer) continue;
    RECT overlap;
    if (!IntersectRect(&overlap, &g_bars[i].rect, &mi.rcMonitor)) continue;
    const RECT* r = &g_bars[i].rect;
    switch (g_bars[i].edge) {
      case ABE_LEFT:   if (r->right > wa.left) wa.left = r->right; break;
      case ABE_TOP:    if (r->bottom > wa.top) wa.top = r->bottom; break;
      case ABE_RIGHT:  if (r->left < wa.right) wa.right = r->left; break;
      case ABE_BOTTOM: if (r->top < wa.bottom) wa.bottom = r->top; break;
    }
  }
  *out = wa;
  return 1;
}

/* Tell everyone the work area moved -- everyone EXCEPT explorer.
 *
 * SPI_SETWORKAREA's own SPIF_SENDCHANGE is the obvious way to do this and it
 * is the entire bug. Measured on the box, explorer alive, our shell not even
 * running:
 *
 *     set 2048, flags 0                -> 2048 for fifteen seconds
 *     set 2048, flags SPIF_SENDCHANGE  -> 2160 by the next read
 *     set 2048, SPIF_SENDCHANGE, explorer killed first -> 2048, holds
 *
 * So explorer treats the broadcast as its cue to recompute, and what it
 * computes is "nothing is reserved" -- its own taskbar is autohidden and its
 * appbar list has never heard of our dock. Every earlier attempt at this
 * ended in a SPIF_SENDCHANGE, which is why re-registering, re-asserting on
 * TaskbarCreated, and a self-healing watcher all failed identically: each one
 * summoned the very stomp it was trying to repair.
 *
 * Posting it ourselves, one window at a time, is the whole fix. Apps read the
 * new work area the same way they always did (SPI_GETWORKAREA is current the
 * instant it is set, notification or not); explorer simply never learns there
 * was anything to react to. */
static BOOL CALLBACK notify_workarea(HWND hwnd, LPARAM shell_pid) {
  DWORD pid = 0;
  GetWindowThreadProcessId(hwnd, &pid);
  if (shell_pid != 0 && pid == (DWORD)shell_pid) return TRUE;
  /* Post, not send: a broadcast that blocks on one stuck window would block
   * the appbar call that started it, and this is a notification -- nothing
   * here reads a reply. */
  PostMessageW(hwnd, WM_SETTINGCHANGE, SPI_SETWORKAREA, 0);
  return TRUE;
}

static void workarea_announce(void) {
  DWORD pid = 0;
  /* Progman first: explorer has one whenever it is running, including the
   * service explorer whose taskbar we hid, and it is the window we are least
   * likely to have taken over ourselves. */
  HWND desktop = FindWindowW(L"Progman", NULL);
  if (desktop != NULL) {
    GetWindowThreadProcessId(desktop, &pid);
  } else {
    HWND tray = explorer_tray();
    if (tray != NULL) GetWindowThreadProcessId(tray, &pid);
  }
  EnumWindows(notify_workarea, (LPARAM)pid);
}

/* 1 if the work area was actually changed, 0 if it already agreed or could
 * not be read -- the caller counts changes, not calls. */
static int workarea_recompute(void) {
  RECT wa;
  if (!workarea_wanted(&wa)) return 0;
  /* The announcement below reaches this window too -- it is a top-level
   * window like any other -- so the stomp watcher runs again on the back of
   * our own change. The equality test one line down ends it either way, since
   * by then the work area IS what we asked for, and posting rather than
   * sending means it is not even re-entrant today. The flag costs nothing and
   * does not rely on that staying true. */
  if (g_wa_applying) return 0;
  RECT cur;
  int have_cur = SystemParametersInfoW(SPI_GETWORKAREA, 0, &cur, 0) ? 1 : 0;
  if (have_cur && EqualRect(&cur, &wa)) return 0;
  if (!g_wa_saved_valid && have_cur) {
    /* What was there before our first change, so exiting can put it back. */
    g_wa_saved = cur;
    g_wa_saved_valid = 1;
  }
  g_wa_applying = 1;
  BOOL ok = SystemParametersInfoW(SPI_SETWORKAREA, 0, &wa, 0);
  if (ok) workarea_announce();
  g_wa_applying = 0;
  if (g_probing || g_debug > 0) {
    printf("[tray] workarea (%ld,%ld,%ld,%ld) -> set=%d err=%lu\n",
           (long)wa.left, (long)wa.top, (long)wa.right, (long)wa.bottom,
           ok ? 1 : 0, ok ? 0 : GetLastError());
    fflush(stdout);
  }
  g_wa_dirty = 1;
  return ok ? 1 : 0;
}

/* Recompute the reservation from scratch -- for when something OUTSIDE the
 * appbar protocol changed the answer.
 *
 * A borrowed explorer is exactly that. While it is alive its taskbar registers
 * a bar with this service like any other client, and our work area shrinks to
 * make room for it; when it is killed the bar goes with the window, but nothing
 * sends an appbar message to say so, and the reservation stays wrong. Left
 * alone it read 1824 instead of 2048 on the box -- a dock-height of desktop
 * missing under the dock -- and stayed there.
 *
 * Dead windows are dropped first, which is what makes this correct rather than
 * merely a retry: the bar is gone because its window is gone. */
/* Put our tray window back on top.
 *
 * SHAppBarMessage resolves Shell_TrayWnd by asking FindWindow, and FindWindow
 * answers with the topmost window of that class. A borrowed explorer creates
 * its own and lands above ours, so from that moment the dock's own appbar
 * calls go to EXPLORER rather than to this service -- the registration ends up
 * in explorer's list, our list has no dock in it, and the work area we then
 * compute is the honest answer to the wrong question: nothing is reserved.
 *
 * This is why the reservation came back for one app and not the next. It was
 * never about timing. */
void flwin32_tray_raise(void) {
  if (g_tray == NULL) return;
  SetWindowPos(g_tray, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE);
}

/* How many bars this service is holding -- the oracle for "did the dock's
 * registration land here or somewhere else", which is not otherwise visible
 * from outside the process. */
int32_t flwin32_tray_bar_count(void) { return (int32_t)g_bar_count; }

void flwin32_tray_reapply_workarea(void) {
  if (g_tray == NULL || !appbar_serving()) return;
  bars_gc();
  workarea_recompute();
}

/* Snap a proposed rect to its edge on the monitor it falls on, keeping the
 * proposed thickness, then stack it past every bar already granted the same
 * edge -- which is what explorer grants a second bottom bar. QUERYPOS and
 * SETPOS share this; the difference is only whether the result is recorded. */
static void appbar_clip(HWND self, UINT edge, RECT* rc) {
  MONITORINFO mi;
  ZeroMemory(&mi, sizeof(mi));
  mi.cbSize = sizeof(mi);
  if (!GetMonitorInfoW(MonitorFromRect(rc, MONITOR_DEFAULTTOPRIMARY), &mi)) return;
  RECT mon = mi.rcMonitor;
  int vertical = (edge == ABE_LEFT || edge == ABE_RIGHT);
  LONG thick = vertical ? rc->right - rc->left : rc->bottom - rc->top;
  if (vertical) {
    if (rc->top < mon.top) rc->top = mon.top;
    if (rc->bottom > mon.bottom) rc->bottom = mon.bottom;
  } else {
    if (rc->left < mon.left) rc->left = mon.left;
    if (rc->right > mon.right) rc->right = mon.right;
  }
  LONG base = (edge == ABE_LEFT) ? mon.left
            : (edge == ABE_TOP) ? mon.top
            : (edge == ABE_RIGHT) ? mon.right
            : mon.bottom;
  for (int i = 0; i < g_bar_count; i++) {
    FlAppBarEntry* o = &g_bars[i];
    if (o->hwnd == self || !o->has_rect || o->edge != edge) continue;
    switch (edge) {
      case ABE_LEFT:   if (o->rect.right > base) base = o->rect.right; break;
      case ABE_TOP:    if (o->rect.bottom > base) base = o->rect.bottom; break;
      case ABE_RIGHT:  if (o->rect.left < base) base = o->rect.left; break;
      default:         if (o->rect.top < base) base = o->rect.top; break;
    }
  }
  switch (edge) {
    case ABE_LEFT:   rc->left = base;          rc->right = base + thick; break;
    case ABE_TOP:    rc->top = base;           rc->bottom = base + thick; break;
    case ABE_RIGHT:  rc->right = base;         rc->left = base - thick; break;
    default:         rc->bottom = base;        rc->top = base - thick; break;
  }
}

static LRESULT appbar_serve(FlAppBarEnvelope* env) {
  FlAppBarData32 abd = env->abd;
  HWND hwnd = (HWND)(ULONG_PTR)abd.hWnd;
  UINT msg = (UINT)env->dwMessage;
  LRESULT result = TRUE;
  bars_gc();
  switch (msg) {
    case ABM_NEW: {
      /* FALSE for a second registration of the same window -- documented, and
       * the honest answer, same bargain as the unmatched NIM_MODIFY. */
      if (bar_find(hwnd) != NULL || g_bar_count >= kMaxAppBars) {
        result = FALSE;
        break;
      }
      FlAppBarEntry* e = &g_bars[g_bar_count++];
      ZeroMemory(e, sizeof(*e));
      e->hwnd = hwnd;
      e->callback = abd.uCallbackMessage;
      e->edge = (UINT)-1;
      e->is_explorer = bar_is_explorer(hwnd);
      break;
    }
    case ABM_REMOVE: {
      FlAppBarEntry* e = bar_find(hwnd);
      if (e != NULL) {
        int i = (int)(e - g_bars);
        for (int j = i; j < g_bar_count - 1; j++) g_bars[j] = g_bars[j + 1];
        g_bar_count--;
        bars_notify(hwnd, ABN_POSCHANGED);
        workarea_recompute();
      }
      break;  /* TRUE either way, per the docs */
    }
    case ABM_QUERYPOS:
    case ABM_SETPOS: {
      appbar_clip(hwnd, abd.uEdge, &abd.rc);
      if (msg == ABM_SETPOS) {
        FlAppBarEntry* e = bar_find(hwnd);
        if (e == NULL && g_bar_count < kMaxAppBars) {
          /* A bar that skipped ABM_NEW -- seen in the wild; register it
           * rather than granting a rect we then refuse to remember. */
          e = &g_bars[g_bar_count++];
          ZeroMemory(e, sizeof(*e));
          e->hwnd = hwnd;
          e->is_explorer = bar_is_explorer(hwnd);
        }
        if (e != NULL) {
          int moved = !e->has_rect || e->edge != abd.uEdge ||
                      !EqualRect(&e->rect, &abd.rc);
          if (abd.uCallbackMessage != 0) e->callback = abd.uCallbackMessage;
          e->edge = abd.uEdge;
          e->rect = abd.rc;
          e->has_rect = 1;
          if (moved) {
            bars_notify(hwnd, ABN_POSCHANGED);
            workarea_recompute();
          }
        }
      }
      break;
    }
    case ABM_GETSTATE:
      result = g_ab_state;
      break;
    case ABM_SETSTATE:
      g_ab_state = (UINT)abd.lParam;
      break;
    case ABM_GETTASKBARPOS: {
      /* Apps position flyouts by this. The dock hosts the tray in its own
       * process, so "the taskbar" is the registered bar whose window is ours
       * -- no side channel, no dock touchpoint. */
      result = FALSE;
      for (int i = 0; i < g_bar_count; i++) {
        DWORD pid = 0;
        GetWindowThreadProcessId(g_bars[i].hwnd, &pid);
        if (pid == GetCurrentProcessId() && g_bars[i].has_rect) {
          abd.uEdge = g_bars[i].edge;
          abd.rc = g_bars[i].rect;
          result = TRUE;
          break;
        }
      }
      break;
    }
    case ABM_GETAUTOHIDEBAR: {
      HWND ah = g_autohide[abd.uEdge & 3];
      result = (ah != NULL && IsWindow(ah)) ? (LRESULT)(DWORD)(ULONG_PTR)ah : 0;
      break;
    }
    case ABM_SETAUTOHIDEBAR: {
      UINT edge = abd.uEdge & 3;
      if (abd.lParam != 0) {
        HWND held = g_autohide[edge];
        if (held != NULL && IsWindow(held) && held != hwnd) result = FALSE;
        else g_autohide[edge] = hwnd;
      } else if (g_autohide[edge] == hwnd) {
        g_autohide[edge] = NULL;
      }
      break;
    }
    case ABM_ACTIVATE:
    case ABM_WINDOWPOSCHANGED:
      /* Explorer uses these to shuffle autohide bars; acknowledging is the
       * whole contract until we grow autohide of our own. */
      break;
    default:
      result = FALSE;
      break;
  }
  if (g_probing || g_debug > 0) {
    printf("[tray] appbar %-14s hwnd=0x%08lX edge=%lu rc=(%ld,%ld,%ld,%ld) "
           "-> %lld (bars=%d shm=0x%llX/%llu)\n",
           abm_name(msg), (unsigned long)env->abd.hWnd,
           (unsigned long)abd.uEdge, (long)abd.rc.left, (long)abd.rc.top,
           (long)abd.rc.right, (long)abd.rc.bottom, (long long)result,
           g_bar_count, (unsigned long long)env->hSharedMemory,
           (unsigned long long)env->dwSourceProcessId);
    fflush(stdout);
  }
  appbar_return(env->hSharedMemory, env->dwSourceProcessId, &abd);
  return result;
}

/* One id, resolved from a name, so the sender and the receiver cannot drift
 * apart -- they only have to agree on the string. */
static UINT workarea_recheck_message(void) {
  static UINT msg = 0;
  if (msg == 0) msg = RegisterWindowMessageW(L"StarlingWorkAreaRecheck");
  return msg;
}

static LRESULT CALLBACK tray_wnd_proc(HWND hwnd, UINT message, WPARAM wparam,
                                      LPARAM lparam) {
  /* SOMEBODY ELSE PUT THE WORK AREA BACK.
   *
   * While we are the shell the reservation is ours to hold, and with the
   * packaged-app explorer service running there is a second process with an
   * opinion about it -- explorer's, which is "nothing is reserved", because
   * its own taskbar is autohidden and its appbar list has never heard of the
   * dock. It recomputes on its own schedule (a display change, a theme
   * change, a packaged app activating), and whatever it recomputes lands on
   * top of ours.
   *
   * Whoever changes it announces the change, so there is nothing to poll:
   * put it back and stop. Re-registering the appbar is what earlier attempts
   * tried and it was never the missing piece -- the registration was fine,
   * the work area was simply somebody else's answer. Note this fires far less
   * now than it used to: we no longer summon explorer's recompute ourselves
   * (see workarea_announce), so what is left is explorer changing it for its
   * own reasons -- a resolution change, a monitor arriving. */
  /* "Something outside the appbar protocol moved the work area -- look again."
   *
   * Broadcast rather than called, because the process that disturbed it is not
   * necessarily this one. A borrowed explorer is started by whichever process
   * is launching an app; the reservation belongs to the process that owns the
   * dock. Those are the same process in the shell and different ones in a test
   * harness, and a repair that only works in the first case is a repair that
   * looks fine right up until it matters. */
  if (message != 0 && message == workarea_recheck_message()) {
    flwin32_tray_reapply_workarea();
    return 0;
  }
  if (message == WM_SETTINGCHANGE && wparam == SPI_SETWORKAREA) {
    if (g_bar_count > 0 && appbar_serving()) {
      /* Bounded, because the other end of this could be something that
       * re-asserts on every change too, and two shells taking turns at the
       * work area forever is a busy loop with a flickering desktop on top of
       * it. Eight repairs in two seconds is far more than any real sequence
       * of monitor and appbar changes produces, so past that we stop, say so
       * once, and wait for the next appbar message to settle it. */
      DWORD now = GetTickCount();
      if (now - g_stomp_since > 2000) {
        g_stomp_since = now;
        g_stomp_count = 0;
        g_stomp_gave_up = 0;
      }
      if (g_stomp_count < 8) {
        if (workarea_recompute()) g_stomp_count++;
      } else if (!g_stomp_gave_up) {
        g_stomp_gave_up = 1;
        printf("[tray] work area contested -- something else keeps setting "
               "it; standing down until the next appbar message\n");
        fflush(stdout);
      }
    }
    return 0;
  }
  if (message == WM_COPYDATA) {
    COPYDATASTRUCT* cds = (COPYDATASTRUCT*)lparam;
    if (cds != NULL && cds->dwData == 1 && cds->cbData >= 8 + kNidV1Size) {
      DWORD* head = (DWORD*)cds->lpData;
      FlTrayIconData* n = (FlTrayIconData*)((char*)cds->lpData + 8);
      if (g_probing) dump_tray_copydata(cds);
      lock_init();
      EnterCriticalSection(&g_lock);
      int changed = 0;
      BOOL accepted = apply_change(head[1], n, &changed);
      if (changed) g_revision++;
      LeaveCriticalSection(&g_lock);
      if (changed && g_changed != NULL) g_changed(g_changed_user);
      if (g_probing && !accepted) {
        printf("[tray]   replied FALSE -- the app should re-add\n");
        fflush(stdout);
      }
      return accepted;
    }
    /* The appbar protocol arrives on the same window, dwData 0. Serve it when
     * we are the shell (explorer's tray gone, or STARLING_TRAY_OWN forcing);
     * forward it while explorer still answers -- swallowing it and returning
     * TRUE would report success while reserving nothing, which is a dock with
     * windows underneath it and no error to show for it. The size gate is the
     * 64-byte envelope the probe pinned; a WOW64 caller might send a shorter
     * one, which has not been observed and falls through to the forward. */
    if (cds != NULL && cds->dwData == 0 &&
        cds->cbData >= sizeof(FlAppBarEnvelope) && appbar_serving()) {
      if (g_probing) dump_unknown(cds);
      FlAppBarEnvelope env;
      memcpy(&env, cds->lpData, sizeof(env));
      LRESULT served = appbar_serve(&env);
      /* ABM_SETSTATE is the one message we serve AND pass on. It is how
       * explorer's own taskbar is told to reserve nothing while the
       * packaged-app service keeps an explorer alive (flwin32_explorer.c sets
       * ABS_AUTOHIDE on it), and answering it here without telling explorer
       * would leave that taskbar claiming a strip we then have to fight over.
       * Unlike the position messages it carries its whole payload inline, so
       * forwarding it cannot lose anything to the shared-block problem that
       * made serving necessary in the first place. */
      if ((UINT)env.dwMessage == ABM_SETSTATE) {
        HWND real = explorer_tray();
        if (real != NULL) SendMessageW(real, WM_COPYDATA, wparam, lparam);
      }
      return served;
    }
    /* EVERYTHING ELSE GOES ON TO EXPLORER. */
    if (cds != NULL) {
      if (g_probing) dump_unknown(cds);
      HWND real = explorer_tray();
      if (real != NULL) return SendMessageW(real, WM_COPYDATA, wparam, lparam);
    }
    return TRUE;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

static HWND make_window(const wchar_t* cls, HWND parent) {
  WNDCLASSEXW wc;
  ZeroMemory(&wc, sizeof(wc));
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = tray_wnd_proc;
  wc.hInstance = GetModuleHandleW(NULL);
  wc.lpszClassName = cls;
  if (RegisterClassExW(&wc) == 0 &&
      GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
    return NULL;
  }
  /* Real geometry rather than 0x0: clients ask the tray window for its rect
   * to decide where to put a balloon or a menu. */
  return CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_TOPMOST, cls, L"",
                         parent ? (WS_CHILD | WS_VISIBLE) : WS_POPUP,
                         0, 0, 300, 40, parent, NULL,
                         GetModuleHandleW(NULL), NULL);
}

static UINT taskbar_created_message(void) {
  static UINT id = 0;
  if (id == 0) id = RegisterWindowMessageW(L"TaskbarCreated");
  return id;
}

static int g_atexit_installed = 0;

static void tray_restore_at_exit(void) {
  /* Same bargain as the taskbar: a machine left with our dead window owning
   * the tray has no notification area at all until something broadcasts, and
   * nothing does. This covers the tidy exit; nothing covers being killed. */
  flwin32_tray_stop();
}

int32_t flwin32_tray_start(void (*changed)(void* user), void* user) {
  if (g_debug < 0) {
    const char* v = getenv("STARLING_TRAY_DEBUG");
    g_debug = (v != NULL && v[0] != '\0' && v[0] != '0') ? 1 : 0;
  }
  if (g_tray != NULL) {
    g_changed = changed;
    g_changed_user = user;
    return 1;
  }
  lock_init();
  g_changed = changed;
  g_changed_user = user;
  g_tray = make_window(L"Shell_TrayWnd", NULL);
  if (g_tray == NULL) return 0;
  /* Explorer's own tray is found and remembered BEFORE ours goes to the top
   * of the z-order, because after that the search would find us. */
  explorer_tray();
  g_notify = make_window(L"TrayNotifyWnd", g_tray);
  SetWindowPos(g_tray, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE);
  /* There is no way to ASK for the icons that already exist. The protocol's
   * only answer is this broadcast, which every app is required to respond to
   * by re-adding its own. */
  SendNotifyMessageW(HWND_BROADCAST, taskbar_created_message(), 0, 0);
  if (!g_atexit_installed) {
    atexit(tray_restore_at_exit);
    g_atexit_installed = 1;
  }
  return 1;
}

void flwin32_tray_stop(void) {
  if (g_tray == NULL) return;
  if (g_notify != NULL) { DestroyWindow(g_notify); g_notify = NULL; }
  DestroyWindow(g_tray);
  g_tray = NULL;
  lock_init();
  EnterCriticalSection(&g_lock);
  for (int i = 0; i < g_count; i++) entry_clear_icon(&g_icons[i]);
  g_count = 0;
  LeaveCriticalSection(&g_lock);
  g_changed = NULL;
  /* The appbar side of the same hand-back: forget every registration, and put
   * the work area back the way we found it -- a shell that exits leaving the
   * screen 56 pixels short has visibly broken every maximized window until
   * something else recomputes it. */
  g_bar_count = 0;
  ZeroMemory(g_autohide, sizeof(g_autohide));
  if (g_wa_dirty && g_wa_saved_valid) {
    if (SystemParametersInfoW(SPI_SETWORKAREA, 0, &g_wa_saved, 0)) {
      workarea_announce();
    }
    g_wa_dirty = 0;
  }
  /* Hand the tray back: apps re-add to whatever answers now, which is
   * explorer. Without this the machine is left with a tray missing everything
   * that had re-registered with us. */
  SendNotifyMessageW(HWND_BROADCAST, taskbar_created_message(), 0, 0);
}

/* ── the snapshot the shell reads ───────────────────────────────────────── */

struct FlWin32TrayList {
  int32_t count;
  FlTrayEntry items[kMaxTrayIcons];
};

FlWin32TrayList* flwin32_tray_list(void) {
  FlWin32TrayList* list = (FlWin32TrayList*)calloc(1, sizeof(FlWin32TrayList));
  if (list == NULL) return NULL;
  lock_init();
  EnterCriticalSection(&g_lock);
  /* An app that exits without deleting its icon is the norm, not the
   * exception -- a crash, a kill, an installer replacing a service. Nobody
   * tells the shell, so the owner window is the liveness test. */
  for (int i = g_count - 1; i >= 0; i--) {
    if (g_icons[i].owner != NULL && !IsWindow(g_icons[i].owner)) {
      entry_clear_icon(&g_icons[i]);
      for (int j = i; j < g_count - 1; j++) g_icons[j] = g_icons[j + 1];
      g_count--;
    }
  }
  for (int i = 0; i < g_count; i++) {
    if (g_icons[i].hidden) continue;
    FlTrayEntry* out = &list->items[list->count++];
    *out = g_icons[i];
    /* The snapshot owns its own copies: the table's may be replaced by a
     * NIM_MODIFY while the shell is still rasterizing this one. */
    out->icon = (g_icons[i].icon != NULL) ? CopyIcon(g_icons[i].icon) : NULL;
  }
  LeaveCriticalSection(&g_lock);
  return list;
}

uint64_t flwin32_tray_revision(void) {
  lock_init();
  EnterCriticalSection(&g_lock);
  /* The user promotes and demotes icons in Windows' own Settings, which tells
   * us nothing at all -- so the setting is polled here, on the tick the shell
   * already has, and the revision moves only when something really changed.
   * The read itself is throttled inside read_settings. */
  if (read_settings()) {
    for (int i = 0; i < g_count; i++) {
      g_icons[i].promoted = is_promoted(&g_icons[i]);
    }
    g_revision++;
  }
  uint64_t r = g_revision;
  LeaveCriticalSection(&g_lock);
  return r;
}

void flwin32_tray_reannounce(void) {
  /* The only way to repopulate a notification area. Whoever owns the class
   * now gets every icon back. */
  SendNotifyMessageW(HWND_BROADCAST, taskbar_created_message(), 0, 0);
}

void flwin32_tray_list_free(FlWin32TrayList* list) {
  if (list == NULL) return;
  for (int i = 0; i < list->count; i++) {
    if (list->items[i].icon != NULL) DestroyIcon(list->items[i].icon);
  }
  free(list);
}

int32_t flwin32_tray_list_count(FlWin32TrayList* list) {
  return (list == NULL) ? 0 : list->count;
}

uint64_t flwin32_tray_list_key(FlWin32TrayList* list, int32_t index) {
  if (list == NULL || index < 0 || index >= list->count) return 0;
  return list->items[index].key;
}

uint64_t flwin32_tray_list_icon(FlWin32TrayList* list, int32_t index) {
  if (list == NULL || index < 0 || index >= list->count) return 0;
  return (uint64_t)(ULONG_PTR)list->items[index].icon;
}

int32_t flwin32_tray_list_promoted(FlWin32TrayList* list, int32_t index) {
  if (list == NULL || index < 0 || index >= list->count) return 0;
  return list->items[index].promoted;
}

uint32_t flwin32_tray_list_generation(FlWin32TrayList* list, int32_t index) {
  if (list == NULL || index < 0 || index >= list->count) return 0;
  return list->items[index].generation;
}

uint64_t flwin32_tray_list_take_icon(FlWin32TrayList* list, int32_t index) {
  if (list == NULL || index < 0 || index >= list->count) return 0;
  HICON icon = list->items[index].icon;
  /* Ownership moves to the caller, so freeing the list must not destroy it.
   * The alternative -- a second CopyIcon -- would have the shell holding two
   * handles to the same picture for no reason. */
  list->items[index].icon = NULL;
  return (uint64_t)(ULONG_PTR)icon;
}

int32_t flwin32_tray_list_tip(FlWin32TrayList* list, int32_t index, char* out,
                              int32_t out_size) {
  if (list == NULL || index < 0 || index >= list->count || out == NULL) return 0;
  return WideCharToMultiByte(CP_UTF8, 0, list->items[index].tip, -1, out,
                             out_size, NULL, NULL) > 0;
}

/* ── clicks ─────────────────────────────────────────────────────────────────
 *
 * The shell does not act on a tray icon; it tells the owner the mouse was
 * over it and the owner does whatever it likes. Which message, and with what
 * in the words, depends on the version the icon asked for with
 * NIM_SETVERSION -- and that is the whole reason we track it.
 */
static void send_click(const FlTrayEntry* e, UINT mouse, int32_t x, int32_t y) {
  if (e->callback == 0 || e->owner == NULL || !IsWindow(e->owner)) return;
  if (e->version >= 4) {
    /* Version 4: the position rides in the wParam, and the message shares the
     * lParam with the icon's id. */
    PostMessageW(e->owner, e->callback, MAKEWPARAM(x, y),
                 MAKELPARAM(mouse, e->id));
  } else {
    PostMessageW(e->owner, e->callback, (WPARAM)e->id, (LPARAM)mouse);
  }
}

void flwin32_tray_click(uint64_t key, int32_t button) {
  /* WHERE, without doing the arithmetic. The app decides where to put its
   * menu and most of them call GetCursorPos to find out; the ones that use
   * the position the shell sends want the same answer, because the pointer is
   * on the icon -- that is what a click IS. Deriving the icon's own screen
   * rectangle instead would mean reproducing the dock's placement, its edge,
   * its overhang and the monitor's scale, to arrive back at the point Windows
   * already knows. */
  POINT cursor;
  if (!GetCursorPos(&cursor)) { cursor.x = 0; cursor.y = 0; }
  int32_t x = cursor.x, y = cursor.y;
  lock_init();
  EnterCriticalSection(&g_lock);
  FlTrayEntry entry;
  int found = 0;
  for (int i = 0; i < g_count; i++) {
    if (g_icons[i].key == key) { entry = g_icons[i]; found = 1; break; }
  }
  LeaveCriticalSection(&g_lock);
  if (!found) return;

  /* Windows' own tray does this before the click, and an app that has not
   * been foreground since it started will not otherwise raise its menu.
   * A tray menu is a popup owned by the app, and a popup whose owner is not
   * allowed the foreground either does not appear or appears and will not
   * dismiss. The shell is the one with foreground rights here, so it has to
   * pass them on -- this is why explorer does it too. */
  DWORD pid = 0;
  GetWindowThreadProcessId(entry.owner, &pid);
  BOOL allowed = (pid != 0) ? AllowSetForegroundWindow(pid) : FALSE;
  DWORD allow_err = allowed ? 0 : GetLastError();
  BOOL fg = SetForegroundWindow(entry.owner);
  if (g_debug) {
    printf("[tray] click key=%llu \"%ls\" button=%d ver=%u owner=0x%p visible=%d "
           "msgonly=%d allow=%d(%lu) setfg=%d at %d,%d\n",
           (unsigned long long)key, entry.tip, button, entry.version, (void*)entry.owner,
           IsWindowVisible(entry.owner) ? 1 : 0,
           (GetAncestor(entry.owner, GA_PARENT) == HWND_MESSAGE) ? 1 : 0,
           allowed ? 1 : 0, (unsigned long)allow_err, fg ? 1 : 0, x, y);
    fflush(stdout);
  }

  if (button == 1) {
    send_click(&entry, WM_RBUTTONDOWN, x, y);
    send_click(&entry, WM_RBUTTONUP, x, y);
    /* Version 4 apps wait for this rather than for the button-up. */
    if (entry.version >= 4) send_click(&entry, WM_CONTEXTMENU, x, y);
  } else if (button == 2) {
    send_click(&entry, WM_MBUTTONDOWN, x, y);
    send_click(&entry, WM_MBUTTONUP, x, y);
  } else {
    send_click(&entry, WM_LBUTTONDOWN, x, y);
    send_click(&entry, WM_LBUTTONUP, x, y);
    if (entry.version >= 4) send_click(&entry, NIN_SELECT, x, y);
  }
}

void flwin32_tray_probe(int32_t seconds) {
  printf("[tray] probe starting\n");
  fflush(stdout);
  g_probing = 1;

  int before = 0;
  printf("[tray] Shell_TrayWnd windows BEFORE ours:\n");
  EnumWindows(list_trays, (LPARAM)&before);
  HWND found = FindWindowW(L"Shell_TrayWnd", NULL);
  describe(found, "FindWindow picks:");

  if (!flwin32_tray_start(NULL, NULL)) {
    printf("[tray] could not take the class\n");
    return;
  }

  int after = 0;
  printf("[tray] Shell_TrayWnd windows AFTER ours:\n");
  EnumWindows(list_trays, (LPARAM)&after);
  found = FindWindowW(L"Shell_TrayWnd", NULL);
  describe(found, "FindWindow picks:");
  printf("[tray] ours is %s\n",
         (found == g_tray) ? "THE ONE SHELL_NOTIFYICON WILL FIND"
                           : "NOT the one -- explorer still owns the tray");
  printf("[tray] explorer's own tray window: 0x%p\n", (void*)explorer_tray());

  APPBARDATA abd;
  ZeroMemory(&abd, sizeof(abd));
  abd.cbSize = sizeof(abd);
  abd.hWnd = g_tray;
  abd.uEdge = ABE_TOP;
  UINT_PTR ok = SHAppBarMessage(ABM_NEW, &abd);
  printf("[tray] SHAppBarMessage(ABM_NEW) -> %llu\n", (unsigned long long)ok);
  if (ok) SHAppBarMessage(ABM_REMOVE, &abd);
  fflush(stdout);

  DWORD until = GetTickCount() + (DWORD)seconds * 1000;
  MSG msg;
  for (;;) {
    DWORD now = GetTickCount();
    if (now >= until) break;
    if (MsgWaitForMultipleObjects(0, NULL, FALSE, until - now, QS_ALLINPUT) == WAIT_TIMEOUT) break;
    while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) {
      TranslateMessage(&msg);
      DispatchMessageW(&msg);
    }
  }

  FlWin32TrayList* list = flwin32_tray_list();
  printf("[tray] table after %ds: %d icon(s)\n", seconds,
         flwin32_tray_list_count(list));
  for (int i = 0; i < flwin32_tray_list_count(list); i++) {
    char tip[512] = {0};
    flwin32_tray_list_tip(list, i, tip, sizeof(tip));
    printf("[tray]   key=%llu icon=0x%llX ver=%u \"%s\"\n",
           (unsigned long long)flwin32_tray_list_key(list, i),
           (unsigned long long)flwin32_tray_list_icon(list, i),
           list->items[i].version, tip);
  }
  flwin32_tray_list_free(list);

  printf("[tray] probe done; giving the tray back to explorer\n");
  fflush(stdout);
  g_probing = 0;
  flwin32_tray_stop();
}
