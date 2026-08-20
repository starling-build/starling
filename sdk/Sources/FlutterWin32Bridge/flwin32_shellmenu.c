// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/*
 * flwin32_shellmenu.c -- the shell's own context-menu verbs, assembled off
 * the thread that draws.
 *
 * WHY THIS EXISTS, in numbers measured on this machine. Right-click to
 * menu-on-screen, median of five with the popup's owner verified:
 *
 *     Windows Explorer     370ms   (and 1134ms for the first one after a
 *                                   window opens, as handler DLLs load cold)
 *     Starling Files        98ms
 *
 * The cost is not the WinUI renderer -- the legacy USER32 menu behind "Show
 * more options" is SLOWER over the same file (246ms against 202ms) -- and it
 * is not the number of shell extensions either: the desktop background has 4
 * registered handlers against a file's 29, and the 29-handler menu comes up
 * faster. What both renderers share, and what neither can start drawing
 * without, is the assembly: resolving the shell item, reading the type's
 * associations, and then CoCreateInstance + IShellExtInit::Initialize +
 * IContextMenu::QueryContextMenu on every registered handler in turn. It is
 * SYNCHRONOUS. One slow handler holds the whole menu, and OneDrive's
 * FileSyncShell64.dll and Defender's shellext.dll are both in that list.
 *
 * So this does the same work on threads of its own. The menu draws with our
 * own verbs at once and the shell's land underneath when they arrive -- which
 * is the one thing Explorer cannot do, because its verbs and its rectangle
 * are decided together.
 *
 * AND IT ASKS TWICE, cheaply first.
 *
 * QueryContextMenu is 84-99% of the assembly, and the cost is per HANDLER --
 * Defender 40ms on a folder, shell32's Library Location 19ms, Sharing 7ms.
 * Handlers are registered PER CLASS, so the association keys are a lever on
 * the price: SHCreateDefaultContextMenu takes them as a parameter, and asking
 * only about the item's own ProgID and extension asks almost no handlers.
 * Measured: 2ms for a .rdp, 9ms for an .exe, 45ms for a folder, against
 * 48-59ms for the full set.
 *
 * The fast tier is still the SHELL's menu -- its labels, localized, and its
 * built-in verbs (Cut, Copy, Delete, Create shortcut, Properties) -- and a
 * real IContextMenu bound to the item, so it can be invoked through. And it
 * is a STRICT SUBSET of the full menu, checked row by row, which is what
 * makes drawing it early safe: the second tier only ever ADDS.
 *
 * A background menu has one tier. Its verbs come from the folder's view
 * object rather than from association keys, so there is nothing to restrict.
 *
 * A THREAD PER TIER, and an apartment on each -- but the two
 * QueryContextMenu calls NEVER overlap, and that ordering is a measured
 * finding, not caution. Run genuinely concurrently, the full query LOSES
 * ROWS: on a folder, "Open in Terminal" and "Open in Terminal Preview"
 * dropped out of the warm full menu in half the runs (21 rows against 23,
 * bimodal over ten runs, never once with the queries serialized). Both tiers
 * ask the Directory class, so both instantiate Windows Terminal's packaged
 * handler at the same moment, and whichever query loses that race simply
 * goes without the handler's verbs -- the same handler that is too slow to
 * make the first menu of a cold process (see --menu-probe on why cold menus
 * are SHORTER). A fast tier whose rows the full tier then forgets is the
 * exact appear-then-vanish churn this design exists to prevent, so the full
 * tier's QueryContextMenu waits for the fast tier to finish building
 * (ev_built, signalled success or failure -- a background menu's is
 * signalled at open, so there is no special case here).
 *
 * What the second thread still buys over one thread running both in
 * sequence: the full tier's BIND (26-50ms cold, the handler DLLs loading)
 * overlaps the fast build instead of queuing behind it, and the fast tier
 * answers expand/invoke the moment it is built -- on one thread, a click on
 * a fast row sat unread until the full query finished, which on a cold
 * folder was a Copy that ran a quarter-second after it was clicked.
 *
 * Why the threads are ours: shell extensions are apartment-threaded in-proc
 * servers. They expect an STA, and an STA only works if its thread PUMPS
 * MESSAGES, because that is how COM marshals calls into it. Neither Swift's
 * cooperative pool nor a plain worker does that, so each tier's thread runs
 * MsgWaitForMultipleObjects rather than a bare wait. (flwin32_com_ensure's
 * MTA-off-the-UI-thread rule is the right one for a one-shot call like
 * reading an icon; it is the wrong one here, where the objects have to stay
 * alive between the query and the invoke.)
 *
 * EVERY COM OBJECT IN A TIER BELONGS TO THAT TIER'S THREAD -- the
 * IContextMenu is created there, queried there, asked to expand a submenu
 * there, and invoked there. The public functions below are therefore not the
 * work; they are a ping-pong across two events with the thread that does it,
 * routed by the tier the caller names. The Swift side serializes its calls
 * onto one queue, which is what makes a request slot with no lock around it
 * correct -- per tier and across tiers alike.
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
#include <shlwapi.h>
#include <stdlib.h>
#include <string.h>

#include "include/FlutterWin32Bridge.h"

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "uuid.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "oleaut32.lib")

/* The id range handed to QueryContextMenu. It starts at 1 rather than 0 so
 * that a zero wID -- what a popup row carries, since a submenu has no command
 * of its own -- cannot be mistaken for a real verb. */
#define ID_FIRST 1
#define ID_LAST  0x7000

/* How many submenus one tier will hold open. "Send to", "New", "Open
 * with", "Give access to" and whatever the installed handlers add: eight
 * would do and 64 costs a kilobyte. */
#define MAX_SUBMENUS 64

enum { CMD_NONE = 0, CMD_EXPAND, CMD_INVOKE, CMD_QUIT };

/* A submenu we handed the caller a token for, and the two things needed to
 * fill it in later: the HMENU itself, and its POSITION in its parent, which is
 * what WM_INITMENUPOPUP is addressed by. */
typedef struct {
    HMENU menu;
    int position;
} FlWin32SubMenu;

struct FlWin32ShellMenu;

/* One tier: a thread, the apartment on it, and every COM object the two of
 * them own. The two tiers share nothing but the session's inputs, which is
 * what lets their queries run at the same time. */
typedef struct {
    struct FlWin32ShellMenu* session;
    int tier;
    HANDLE thread;

    /* Signalled when this tier's build is done -- once, success or failure,
     * before the thread starts listening for requests. Not a reply to
     * anything: the caller waits for it without having asked. */
    HANDLE ev_built;
    HANDLE ev_request;
    HANDLE ev_done;

    /* The request slot. One caller at a time, guaranteed by the Swift side's
     * serial queue rather than by a lock here. */
    int cmd;
    int arg;
    FlWin32ShellVerb* out;
    int out_max;
    int out_count;

    /* Written by the build, read after ev_built. */
    FlWin32ShellVerb items[FLWIN32_SHELLMENU_MAX];
    int count;
    int status;

    /* Tier-thread only, from here down. */
    IContextMenu* cm;
    IContextMenu2* cm2;
    IContextMenu3* cm3;
    HMENU menu;
    FlWin32SubMenu subs[MAX_SUBMENUS];
    int sub_count;
    double t_verbs;
} FlWin32MenuTier;

struct FlWin32ShellMenu {
    FlWin32MenuTier tiers[2];

    /* Read-only after open(), shared by both tier threads. */
    wchar_t path[1024];
    int background;
    int extended;
    HWND owner;

    /* Where the time went, in milliseconds. t_bind/t_query/t_walk are the
     * full tier's, t_fast is the cheap tier's whole build; each is written
     * by the thread that did the work and read after that tier's ev_built.
     * They exist because "QueryContextMenu is the slow part" was a guess for
     * as long as nobody split it up. */
    double t_bind;
    double t_query;
    double t_walk;
    double t_fast;
};

static double now_ms(void) {
    LARGE_INTEGER f, c;
    QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&c);
    return (double)c.QuadPart * 1000.0 / (double)f.QuadPart;
}

static wchar_t* utf8_to_wide_local(const char* utf8) {
    if (utf8 == NULL) return NULL;
    int n = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, NULL, 0);
    if (n <= 0) return NULL;
    wchar_t* out = (wchar_t*)calloc((size_t)n, sizeof(wchar_t));
    if (out == NULL) return NULL;
    MultiByteToWideChar(CP_UTF8, 0, utf8, -1, out, n);
    return out;
}

static void wide_to_utf8(const wchar_t* w, char* out, int out_size) {
    if (out == NULL || out_size <= 0) return;
    out[0] = 0;
    if (w == NULL) return;
    WideCharToMultiByte(CP_UTF8, 0, w, -1, out, out_size, NULL, NULL);
    out[out_size - 1] = 0;
}

/* A menu label as a person reads it.
 *
 * Two things have to come off. The AMPERSAND is a keyboard-accelerator mark
 * ("Cu&t"), and a doubled one is a literal ampersand ("Play in AIMP && enqueue").
 * The TAB and everything after it is the right-aligned accelerator text
 * ("Copy\tCtrl+C"), which belongs to a menu we are not drawing -- our rows
 * have no second column to put it in, and left as-is it renders as a stray
 * gap followed by a key name in the middle of the label. */
static void clean_label(const wchar_t* in, wchar_t* out, size_t max) {
    size_t o = 0;
    for (size_t i = 0; in[i] != 0 && o + 1 < max; i++) {
        if (in[i] == L'\t') break;
        if (in[i] == L'&') {
            if (in[i + 1] == L'&') { out[o++] = L'&'; i++; }
            continue;
        }
        out[o++] = in[i];
    }
    while (o > 0 && (out[o - 1] == L' ' || out[o - 1] == L'\t')) o--;
    out[o] = 0;
}

/* The canonical verb -- "open", "cut", "copy", "delete", "properties" -- or
 * an empty string.
 *
 * Worth asking for even though nothing here dispatches on it: it is how the
 * CALLER knows that the shell's "Open" is the same thing as the Open it has
 * already drawn itself, and a menu that offers Open twice is worse than one
 * that offers it once. Plenty of handlers return E_NOTIMPL -- a third-party
 * verb usually has no canonical name at all -- and that is not an error.
 *
 * The buffer parameter is typed char* for the ANSI form; GCS_VERBW writes
 * wide characters into it, which is why the cast is here and the buffer is
 * declared wide. */
static void canonical_verb(IContextMenu* cm, UINT offset, char* out, int out_size) {
    wchar_t wide[96];
    wide[0] = 0;
    HRESULT hr = cm->lpVtbl->GetCommandString(cm, (UINT_PTR)offset, GCS_VERBW,
                                              NULL, (CHAR*)wide, 96);
    if (SUCCEEDED(hr)) {
        wide[95] = 0;
        wide_to_utf8(wide, out, out_size);
    } else {
        out[0] = 0;
    }
}

/* Reads one HMENU into the caller's array.
 *
 * OWNER-DRAW ROWS ARE DROPPED. A handler that sets MFT_OWNERDRAW does not put
 * text in the item at all -- dwTypeData is a pointer of its own choosing, and
 * the string only exists inside the WM_DRAWITEM it expects to be sent. We are
 * not drawing this menu with USER32, so that message is never coming, and
 * there is nothing to show but a blank row. Skipping is honest; a blank row
 * that does something when clicked is not.
 *
 * Separators are collapsed as they are read: leading ones are dropped, runs of
 * them become one, and a trailing one is trimmed at the end. Explorer's menu
 * has a separator per handler group and several of those groups are empty
 * once the owner-draw rows are gone -- without this the menu comes out as a
 * column of rules. */
static int collect_menu(FlWin32MenuTier* t, HMENU menu,
                        FlWin32ShellVerb* out, int max) {
    int total = GetMenuItemCount(menu);
    if (total <= 0) return 0;
    UINT def = GetMenuDefaultItem(menu, FALSE, GMDI_USEDISABLED);
    int count = 0;

    for (int i = 0; i < total && count < max; i++) {
        wchar_t text[512];
        text[0] = 0;
        MENUITEMINFOW mi;
        ZeroMemory(&mi, sizeof(mi));
        mi.cbSize = sizeof(mi);
        mi.fMask = MIIM_FTYPE | MIIM_STATE | MIIM_ID | MIIM_SUBMENU | MIIM_STRING;
        mi.dwTypeData = text;
        mi.cch = 511;
        if (!GetMenuItemInfoW(menu, (UINT)i, TRUE, &mi)) continue;

        FlWin32ShellVerb* v = &out[count];
        memset(v, 0, sizeof(*v));

        if (mi.fType & MFT_SEPARATOR) {
            if (count == 0 || out[count - 1].is_separator) continue;
            v->id = -1;
            v->is_separator = 1;
            count++;
            continue;
        }
        if (mi.fType & MFT_OWNERDRAW) continue;

        wchar_t label[512];
        clean_label(text, label, 512);
        if (label[0] == 0) continue;
        wide_to_utf8(label, v->label, (int)sizeof(v->label));

        v->is_enabled = (mi.fState & (MFS_DISABLED | MFS_GRAYED)) ? 0 : 1;
        v->is_default = (def != (UINT)-1 && mi.wID == def) ? 1 : 0;

        if (mi.hSubMenu != NULL) {
            /* A popup carries no command of its own, so there is nothing to
             * invoke and nothing to name it by: the token is an index into
             * the tier's own table, handed back to expand(). */
            v->id = -1;
            v->is_submenu = 1;
            if (t->sub_count < MAX_SUBMENUS) {
                t->subs[t->sub_count].menu = mi.hSubMenu;
                t->subs[t->sub_count].position = i;
                t->sub_count++;
                v->submenu = t->sub_count; /* 1-based; 0 means "none" */
            } else {
                continue; /* No token to give, so do not offer the row. */
            }
        } else {
            if (mi.wID < ID_FIRST || mi.wID > ID_LAST) continue;
            v->id = (int32_t)(mi.wID - ID_FIRST);
            double verb_start = now_ms();
            canonical_verb(t->cm, (UINT)v->id, v->verb, (int)sizeof(v->verb));
            t->t_verbs += now_ms() - verb_start;
        }
        count++;
    }

    while (count > 0 && out[count - 1].is_separator) count--;
    return count;
}

/* The item's own classes, which is where an application's verbs live and
 * where the expensive handlers do NOT: Defender, OneDrive, Sharing and
 * WorkFolders are all registered against `*` and AllFilesystemObjects.
 * Returns how many keys were opened. */
static int cheap_keys(struct FlWin32ShellMenu* s, HKEY* keys, int max) {
    int count = 0;
    DWORD attrs = GetFileAttributesW(s->path);
    int is_directory = (attrs != INVALID_FILE_ATTRIBUTES)
                    && (attrs & FILE_ATTRIBUTE_DIRECTORY);
    wchar_t names[4][80];
    int n = 0;
    if (is_directory) {
        wcscpy_s(names[n++], 80, L"Directory");
        wcscpy_s(names[n++], 80, L"Folder");
    } else {
        const wchar_t* dot = wcsrchr(s->path, L'.');
        if (dot != NULL && wcslen(dot) < 60) {
            wchar_t progid[80];
            DWORD size = sizeof(progid);
            if (RegGetValueW(HKEY_CLASSES_ROOT, dot, NULL, RRF_RT_REG_SZ, NULL,
                             progid, &size) == ERROR_SUCCESS && progid[0] != 0) {
                wcscpy_s(names[n++], 80, progid);
            }
            wcscpy_s(names[n++], 80, dot);
        }
    }
    for (int i = 0; i < n && count < max; i++) {
        HKEY key;
        if (RegOpenKeyExW(HKEY_CLASSES_ROOT, names[i], 0, KEY_READ, &key)
                == ERROR_SUCCESS) {
            keys[count++] = key;
        }
    }
    return count;
}

/* Tier 0: the same shell, asked about fewer classes.
 *
 * SHCreateDefaultContextMenu is the documented way to hand the association
 * keys in rather than let the shell derive them. Everything else is the
 * shell's: the labels, the built-in verbs, the invocation. Returns 0 when
 * there is no cheap tier to build -- a background menu has none, and its
 * thread is never started. */
static int build_fast(FlWin32MenuTier* t) {
    struct FlWin32ShellMenu* s = t->session;

    LPITEMIDLIST pidl = NULL;
    if (FAILED(SHParseDisplayName(s->path, NULL, &pidl, 0, NULL))) return 0;
    IShellFolder* parent = NULL;
    LPCITEMIDLIST child = NULL;
    HRESULT hr = SHBindToParent(pidl, &IID_IShellFolder, (void**)&parent, &child);
    if (FAILED(hr) || parent == NULL) {
        CoTaskMemFree(pidl);
        return 0;
    }

    HKEY keys[4];
    int key_count = cheap_keys(s, keys, 4);
    int ok = 0;
    if (key_count > 0) {
        DEFCONTEXTMENU dcm;
        ZeroMemory(&dcm, sizeof(dcm));
        dcm.hwnd = s->owner;
        dcm.psf = parent;
        dcm.cidl = 1;
        dcm.apidl = &child;
        dcm.cKeys = (UINT)key_count;
        dcm.aKeys = keys;

        IContextMenu* cm = NULL;
        double t0 = now_ms();
        if (SUCCEEDED(SHCreateDefaultContextMenu(&dcm, &IID_IContextMenu,
                                                 (void**)&cm)) && cm != NULL) {
            t->cm = cm;
            cm->lpVtbl->QueryInterface(cm, &IID_IContextMenu3, (void**)&t->cm3);
            cm->lpVtbl->QueryInterface(cm, &IID_IContextMenu2, (void**)&t->cm2);
            t->menu = CreatePopupMenu();
            if (t->menu != NULL) {
                UINT flags = CMF_NORMAL | CMF_EXPLORE;
                if (s->extended) flags |= CMF_EXTENDEDVERBS;
                if (SUCCEEDED(cm->lpVtbl->QueryContextMenu(cm, t->menu, 0,
                                                           ID_FIRST, ID_LAST,
                                                           flags))) {
                    t->count = collect_menu(t, t->menu, t->items,
                                            FLWIN32_SHELLMENU_MAX);
                    ok = 1;
                }
            }
        }
        s->t_fast = now_ms() - t0;
    }

    for (int i = 0; i < key_count; i++) RegCloseKey(keys[i]);
    parent->lpVtbl->Release(parent);
    CoTaskMemFree(pidl);
    return ok;
}

/* Tier 1: everything, as Explorer would build it. */
static int build(FlWin32MenuTier* t) {
    struct FlWin32ShellMenu* s = t->session;
    IContextMenu* cm = NULL;
    double t0 = now_ms();

    if (s->background) {
        /* The FOLDER's menu rather than an item's -- what a right-click on
         * empty space gets, and the only place "New" and "Paste" live. It
         * comes from the folder's view object, not from a shell item, which
         * is why this is a separate path and not a different flag. */
        LPITEMIDLIST pidl = NULL;
        if (FAILED(SHParseDisplayName(s->path, NULL, &pidl, 0, NULL))) return 0;
        IShellFolder* folder = NULL;
        HRESULT hr = SHBindToObject(NULL, pidl, NULL, &IID_IShellFolder,
                                    (void**)&folder);
        CoTaskMemFree(pidl);
        if (FAILED(hr) || folder == NULL) return 0;
        hr = folder->lpVtbl->CreateViewObject(folder, s->owner, &IID_IContextMenu,
                                              (void**)&cm);
        folder->lpVtbl->Release(folder);
        if (FAILED(hr) || cm == NULL) return 0;
    } else {
        /* THROUGH THE PARENT FOLDER, not through the item.
         *
         * IShellItem::BindToHandler(BHID_SFUIObject) also returns an
         * IContextMenu and its verbs look identical -- but the menu it hands
         * back does not know which folder the item is IN, and some verbs need
         * that. Measured: "Copy as path" worked, and "Properties" answered
         * with a message box reading "The properties for this item are not
         * available", from a shell that could not resolve the item it was
         * being asked about.
         *
         * SHBindToParent + GetUIObjectOf is what Explorer's own view does:
         * the folder is the object, the item is a child pidl within it, and
         * the owner window is given at CREATION rather than only at invoke.
         * Properties opens the real sheet after this change and nothing else
         * in the menu moved. */
        LPITEMIDLIST pidl = NULL;
        if (FAILED(SHParseDisplayName(s->path, NULL, &pidl, 0, NULL))) return 0;
        IShellFolder* parent = NULL;
        LPCITEMIDLIST child = NULL;
        HRESULT hr = SHBindToParent(pidl, &IID_IShellFolder, (void**)&parent,
                                    &child);
        if (FAILED(hr) || parent == NULL) {
            CoTaskMemFree(pidl);
            return 0;
        }
        hr = parent->lpVtbl->GetUIObjectOf(parent, s->owner, 1, &child,
                                           &IID_IContextMenu, NULL, (void**)&cm);
        parent->lpVtbl->Release(parent);
        CoTaskMemFree(pidl);
        if (FAILED(hr) || cm == NULL) return 0;
    }

    t->cm = cm;
    /* IContextMenu3 first: a handler that implements both wants the newer one,
     * and HandleMenuMsg2 is what fills a submenu in on Windows 11. Either may
     * be absent, and a tier with neither simply cannot expand anything. */
    cm->lpVtbl->QueryInterface(cm, &IID_IContextMenu3, (void**)&t->cm3);
    cm->lpVtbl->QueryInterface(cm, &IID_IContextMenu2, (void**)&t->cm2);

    s->t_bind = now_ms() - t0;

    t->menu = CreatePopupMenu();
    if (t->menu == NULL) return 0;

    /* CMF_EXPLORE is what a folder VIEW asks for, and it is the difference
     * between the menu a file gets in Explorer's list and the shorter one it
     * gets on the desktop. CMF_EXTENDEDVERBS is Shift+right-click: the extra
     * verbs Windows hides ("Open in new process", "Copy as path" on older
     * builds), asked for only when the caller says the modifier was down. */
    UINT flags = CMF_NORMAL | CMF_EXPLORE;
    if (s->extended) flags |= CMF_EXTENDEDVERBS;

    /* NOT UNTIL THE FAST TIER IS DONE. Two QueryContextMenu calls in flight
     * instantiate the same handlers at the same moment, and a handler that
     * loses that race contributes nothing to the query that lost it --
     * measured, Windows Terminal's rows fell out of the warm full menu in
     * half the runs (see the file comment). The event is signalled whether
     * the fast build succeeded, failed, or never existed, so this cannot
     * deadlock; what it costs is the fast build's duration (2-9ms for a
     * file, ~50ms for a folder), and the bind above already ran during it. */
    WaitForSingleObject(s->tiers[0].ev_built, INFINITE);

    double t1 = now_ms();
    HRESULT hr = t->cm->lpVtbl->QueryContextMenu(t->cm, t->menu, 0,
                                                 ID_FIRST, ID_LAST, flags);
    if (FAILED(hr)) return 0;
    double t2 = now_ms();
    s->t_query = t2 - t1;

    t->count = collect_menu(t, t->menu, t->items, FLWIN32_SHELLMENU_MAX);
    s->t_walk = now_ms() - t2;
    return 1;
}

/* Fills in one submenu and reads it.
 *
 * A submenu arrives EMPTY. "Send to" has no items in it until the handler is
 * told to populate it, and the way it is told is the message the menu system
 * would have sent when the user hovered the row: WM_INITMENUPOPUP, addressed
 * by the submenu's handle and its position in the parent. We are not running
 * a USER32 menu, so nobody sends it -- this does, by hand, on the thread that
 * owns the handler. */
static int expand(FlWin32MenuTier* t, int token,
                  FlWin32ShellVerb* out, int max) {
    if (token < 1 || token > t->sub_count) return 0;
    FlWin32SubMenu sub = t->subs[token - 1];
    if (sub.menu == NULL) return 0;

    if (t->cm3 != NULL) {
        LRESULT unused = 0;
        t->cm3->lpVtbl->HandleMenuMsg2(t->cm3, WM_INITMENUPOPUP,
                                       (WPARAM)sub.menu,
                                       MAKELPARAM(sub.position, FALSE),
                                       &unused);
    } else if (t->cm2 != NULL) {
        t->cm2->lpVtbl->HandleMenuMsg(t->cm2, WM_INITMENUPOPUP,
                                      (WPARAM)sub.menu,
                                      MAKELPARAM(sub.position, FALSE));
    }
    return collect_menu(t, sub.menu, out, max);
}

/* The canonical verb of a top-level row, or "". */
static const char* verb_of(FlWin32MenuTier* t, int id) {
    for (int i = 0; i < t->count; i++) {
        if (!t->items[i].is_separator && t->items[i].id == id) {
            return t->items[i].verb;
        }
    }
    return "";
}

/* Invoked on the tier the row CAME FROM. The two menus number their verbs
 * independently -- both start at zero -- so an id is meaningless without the
 * tier that issued it, and crossing them would run whatever verb happens to
 * sit at that offset in the other menu. */
static int invoke(FlWin32MenuTier* t, int id) {
    struct FlWin32ShellMenu* s = t->session;
    if (t->cm == NULL || id < 0) return 0;

    /* PROPERTIES IS ASKED FOR, NOT INVOKED -- and this is the one place where
     * hosting somebody else's menu shows its seam.
     *
     * InvokeCommand on the properties verb answers with a message box reading
     * "The properties for this item are not available", for a file and for a
     * folder alike, with the owner window set and the menu bound through the
     * parent folder. It is not our id mapping: every other verb on the same
     * menu runs, and it is the properties handler itself that puts up the
     * box. What that handler wants is a SITE -- the IShellBrowser/IShellView
     * of the folder view it expects to be living in -- and we have no view,
     * because the listing is ours and not the shell's.
     *
     * SHObjectProperties is the shell's own front door to the same sheet and
     * needs no view. So the verb the user asked for is the verb they get; it
     * simply does not travel through IContextMenu to get there.
     *
     * Verbs that want the site for something OTHER than a property sheet --
     * "Restore previous versions" is one -- have no such front door and
     * remain the boundary of what a menu without a view can run. */
    if (strcmp(verb_of(t, id), "properties") == 0) {
        return SHObjectProperties(s->owner, SHOP_FILEPATH, s->path, NULL) ? 1 : 0;
    }

    CMINVOKECOMMANDINFOEX ici;
    ZeroMemory(&ici, sizeof(ici));
    ici.cbSize = sizeof(ici);
    /* CMIC_MASK_UNICODE is what makes lpVerbW and lpDirectoryW be read at
     * all; without it a handler takes the ANSI members and the wide ones are
     * ignored. Both verbs are the same id -- MAKEINTRESOURCE of the OFFSET,
     * not of the menu's wID, which is the off-by-ID_FIRST that turns "Copy"
     * into whatever verb sits one place along. */
    ici.fMask = CMIC_MASK_UNICODE;
    ici.hwnd = s->owner;
    ici.lpVerb = MAKEINTRESOURCEA(id);
    ici.lpVerbW = MAKEINTRESOURCEW(id);
    ici.nShow = SW_SHOWNORMAL;

    HRESULT hr = t->cm->lpVtbl->InvokeCommand(t->cm,
                                              (CMINVOKECOMMANDINFO*)&ici);
    return SUCCEEDED(hr) ? 1 : 0;
}

static void release_tier(FlWin32MenuTier* t) {
    /* WHATEVER WE PUT ON THE CLIPBOARD HAS TO OUTLIVE US.
     *
     * Cut and Copy do not copy anything: the handler calls OleSetClipboard
     * with a data object of its OWN, and the clipboard then holds a reference
     * to an object living in this process, on this thread. Releasing the menu
     * and ending the apartment a moment later leaves the clipboard pointing
     * at nothing -- which is exactly what it looked like from outside, an
     * empty clipboard after a Copy that had visibly run.
     *
     * OleFlushClipboard renders the formats out of the object and into the
     * clipboard itself, so the data survives the session. It is what Explorer
     * does before it exits, for the same reason. A no-op when the clipboard
     * belongs to somebody else -- including the other tier's thread -- so it
     * is unconditional here. */
    OleFlushClipboard();
    if (t->menu != NULL) { DestroyMenu(t->menu); t->menu = NULL; }
    if (t->cm3 != NULL) { t->cm3->lpVtbl->Release(t->cm3); t->cm3 = NULL; }
    if (t->cm2 != NULL) { t->cm2->lpVtbl->Release(t->cm2); t->cm2 = NULL; }
    if (t->cm != NULL) { t->cm->lpVtbl->Release(t->cm); t->cm = NULL; }
}

static DWORD WINAPI tier_thread(LPVOID param) {
    FlWin32MenuTier* t = (FlWin32MenuTier*)param;

    /* OleInitialize, not CoInitializeEx: it is an apartment PLUS the OLE
     * libraries, and the difference is not academic here. A shell extension
     * expects to be able to use the clipboard and drag-and-drop, and both are
     * OLE -- OleSetClipboard on a thread that only ever called CoInitializeEx
     * fails with CO_E_NOTINITIALIZED, which is a Copy that silently copies
     * nothing. Explorer's own threads are OleInitialize'd. */
    HRESULT co = OleInitialize(NULL);
    if (SUCCEEDED(co)) {
        int ok = t->tier == 0 ? build_fast(t) : build(t);
        t->status = ok ? 1 : -1;
    } else {
        t->status = -1;
    }
    SetEvent(t->ev_built);

    for (;;) {
        /* Waits on the request AND on the message queue. The second half is
         * not optional: this is an STA, and everything COM does for it --
         * marshaling a call in from another apartment, a handler's own hidden
         * window -- happens through messages. A thread that only waits on the
         * event deadlocks the first handler that needs either. */
        DWORD w = MsgWaitForMultipleObjects(1, &t->ev_request, FALSE,
                                            INFINITE, QS_ALLINPUT);
        if (w == WAIT_OBJECT_0) {
            int cmd = t->cmd;
            t->cmd = CMD_NONE;
            if (cmd == CMD_QUIT) {
                SetEvent(t->ev_done);
                break;
            }
            if (cmd == CMD_EXPAND) {
                t->out_count = expand(t, t->arg, t->out, t->out_max);
            } else if (cmd == CMD_INVOKE) {
                t->out_count = invoke(t, t->arg);
            }
            SetEvent(t->ev_done);
        } else if (w == WAIT_OBJECT_0 + 1) {
            MSG msg;
            while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) {
                TranslateMessage(&msg);
                DispatchMessageW(&msg);
            }
        } else {
            break;
        }
    }

    release_tier(t);
    if (SUCCEEDED(co)) OleUninitialize();
    return 0;
}

/* Hands `cmd` to the tier's thread and waits for it to be done with it. */
static void request(FlWin32MenuTier* t, int cmd, int arg,
                    FlWin32ShellVerb* out, int out_max) {
    t->cmd = cmd;
    t->arg = arg;
    t->out = out;
    t->out_max = out_max;
    t->out_count = 0;
    SetEvent(t->ev_request);
    WaitForSingleObject(t->ev_done, INFINITE);
}

/* Waits for a tier to finish building and, if its thread exists, asks it to
 * quit and joins it. Safe while the query is still running -- a menu
 * dismissed before the handlers answered is the ordinary case, not the rare
 * one -- because the thread signals ev_built whether the build succeeded or
 * failed, and only then starts looking at requests, so the quit cannot
 * arrive while it is mid-QueryContextMenu. */
static void stop_tier(FlWin32MenuTier* t) {
    if (t->thread == NULL) return;
    WaitForSingleObject(t->ev_built, INFINITE);
    request(t, CMD_QUIT, 0, NULL, 0);
    WaitForSingleObject(t->thread, INFINITE);
    CloseHandle(t->thread);
    t->thread = NULL;
}

static void close_tier_events(FlWin32MenuTier* t) {
    if (t->ev_built != NULL) CloseHandle(t->ev_built);
    if (t->ev_request != NULL) CloseHandle(t->ev_request);
    if (t->ev_done != NULL) CloseHandle(t->ev_done);
}

FlWin32ShellMenu* flwin32_shellmenu_open(const char* path,
                                         int32_t background,
                                         int32_t extended,
                                         uint64_t owner) {
    if (path == NULL || path[0] == 0) return NULL;
    struct FlWin32ShellMenu* s = (struct FlWin32ShellMenu*)calloc(1, sizeof(*s));
    if (s == NULL) return NULL;

    wchar_t* wide = utf8_to_wide_local(path);
    if (wide == NULL) { free(s); return NULL; }
    wcsncpy_s(s->path, 1024, wide, _TRUNCATE);
    free(wide);

    s->background = background ? 1 : 0;
    s->extended = extended ? 1 : 0;
    s->owner = (HWND)(ULONG_PTR)owner;

    int events_ok = 1;
    for (int i = 0; i < 2; i++) {
        FlWin32MenuTier* t = &s->tiers[i];
        t->session = s;
        t->tier = i;
        t->status = -1;
        t->ev_built = CreateEventW(NULL, TRUE, FALSE, NULL);   /* manual reset */
        t->ev_request = CreateEventW(NULL, FALSE, FALSE, NULL);
        t->ev_done = CreateEventW(NULL, FALSE, FALSE, NULL);
        if (t->ev_built == NULL || t->ev_request == NULL || t->ev_done == NULL) {
            events_ok = 0;
        }
    }
    if (!events_ok) {
        close_tier_events(&s->tiers[0]);
        close_tier_events(&s->tiers[1]);
        free(s);
        return NULL;
    }

    /* The full tier first: it is the long pole, and every instruction between
     * here and its CreateThread is time the concurrency was supposed to buy. */
    s->tiers[1].thread = CreateThread(NULL, 0, tier_thread, &s->tiers[1], 0, NULL);
    if (s->tiers[1].thread == NULL) {
        close_tier_events(&s->tiers[0]);
        close_tier_events(&s->tiers[1]);
        free(s);
        return NULL;
    }

    /* The cheap tier is a nicety, not a requirement: a background menu has
     * none to build (its verbs come from the view object, which takes no key
     * set), and if its thread cannot be created the session still works --
     * the caller just waits for the full answer, which is where every row
     * ends up anyway. Either way the event is signalled here so nobody blocks
     * on a thread that does not exist. */
    if (!s->background) {
        s->tiers[0].thread = CreateThread(NULL, 0, tier_thread, &s->tiers[0],
                                          0, NULL);
    }
    if (s->tiers[0].thread == NULL) {
        SetEvent(s->tiers[0].ev_built);
    }
    return s;
}

int32_t flwin32_shellmenu_items(FlWin32ShellMenu* s, int32_t tier,
                                FlWin32ShellVerb* out, int32_t max) {
    if (s == NULL || out == NULL || max <= 0 || tier < 0 || tier > 1) return -1;
    FlWin32MenuTier* t = &s->tiers[tier];
    /* Each tier has its own thread and its own event, so asking for the cheap
     * one does not wait for the expensive one -- which is the entire point of
     * there being two. */
    WaitForSingleObject(t->ev_built, INFINITE);
    if (t->status != 1) return -1;
    int n = t->count < max ? t->count : max;
    memcpy(out, t->items, (size_t)n * sizeof(FlWin32ShellVerb));
    return n;
}

int32_t flwin32_shellmenu_expand(FlWin32ShellMenu* s, int32_t tier,
                                 int32_t token, FlWin32ShellVerb* out,
                                 int32_t max) {
    if (s == NULL || out == NULL || max <= 0 || tier < 0 || tier > 1) return 0;
    FlWin32MenuTier* t = &s->tiers[tier];
    WaitForSingleObject(t->ev_built, INFINITE);
    if (t->status != 1) return 0;
    request(t, CMD_EXPAND, (int)token, out, (int)max);
    return (int32_t)t->out_count;
}

int32_t flwin32_shellmenu_invoke(FlWin32ShellMenu* s, int32_t tier, int32_t id) {
    if (s == NULL || tier < 0 || tier > 1) return 0;
    FlWin32MenuTier* t = &s->tiers[tier];
    WaitForSingleObject(t->ev_built, INFINITE);
    if (t->status != 1) return 0;
    request(t, CMD_INVOKE, (int)id, NULL, 0);
    return (int32_t)t->out_count;
}

void flwin32_shellmenu_timings(FlWin32ShellMenu* s, double* bind, double* query,
                               double* walk, double* verbs) {
    if (s == NULL) return;
    WaitForSingleObject(s->tiers[1].ev_built, INFINITE);
    if (bind != NULL) *bind = s->t_bind;
    if (query != NULL) *query = s->t_query;
    if (walk != NULL) *walk = s->t_walk;
    if (verbs != NULL) *verbs = s->tiers[1].t_verbs;
}

void flwin32_shellmenu_close(FlWin32ShellMenu* s) {
    if (s == NULL) return;
    stop_tier(&s->tiers[0]);
    stop_tier(&s->tiers[1]);
    close_tier_events(&s->tiers[0]);
    close_tier_events(&s->tiers[1]);
    free(s);
}
