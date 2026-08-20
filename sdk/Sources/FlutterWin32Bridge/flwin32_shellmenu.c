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
 * So this does the same work on a thread of its own. The menu draws with our
 * own verbs at once and the shell's land underneath when they arrive -- which
 * is the one thing Explorer cannot do, because its verbs and its rectangle
 * are decided together.
 *
 * A THREAD PER MENU, and an apartment on it. Shell extensions are
 * apartment-threaded in-proc servers: they expect an STA, and an STA only
 * works if its thread PUMPS MESSAGES, because that is how COM marshals calls
 * into it. Neither Swift's cooperative pool nor a plain worker does that, so
 * the thread is ours and it runs MsgWaitForMultipleObjects rather than a bare
 * wait. (flwin32_com_ensure's MTA-off-the-UI-thread rule is the right one for
 * a one-shot call like reading an icon; it is the wrong one here, where the
 * objects have to stay alive between the query and the invoke.)
 *
 * EVERY COM OBJECT IN A SESSION BELONGS TO THAT THREAD -- the IContextMenu is
 * created there, queried there, asked to expand a submenu there, and invoked
 * there. The public functions below are therefore not the work; they are a
 * ping-pong across two events with a thread that does it. The Swift side
 * serializes its calls onto one queue, which is what makes a request slot
 * with no lock around it correct.
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

/* How many submenus one session will hold open. "Send to", "New", "Open
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

struct FlWin32ShellMenu {
    HANDLE thread;
    /* Signalled when the query is done -- once, at the start of the session.
     * Distinct from the request pair below because it is not a reply to
     * anything: the caller waits for it without having asked. */
    HANDLE ev_ready;
    HANDLE ev_request;
    HANDLE ev_done;

    /* The request slot. One caller at a time, guaranteed by the Swift side's
     * serial queue rather than by a lock here. */
    int cmd;
    int arg;
    FlWin32ShellVerb* out;
    int out_max;
    int out_count;

    /* Written by the query, read after ev_ready. */
    FlWin32ShellVerb items[FLWIN32_SHELLMENU_MAX];
    int count;
    int status;

    /* Session-thread only, from here down. */
    wchar_t path[1024];
    int background;
    int extended;
    HWND owner;
    IContextMenu* cm;
    IContextMenu2* cm2;
    IContextMenu3* cm3;
    HMENU menu;
    FlWin32SubMenu subs[MAX_SUBMENUS];
    int sub_count;
};

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
static int collect_menu(struct FlWin32ShellMenu* s, HMENU menu,
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
             * the session's own table, handed back to expand(). */
            v->id = -1;
            v->is_submenu = 1;
            if (s->sub_count < MAX_SUBMENUS) {
                s->subs[s->sub_count].menu = mi.hSubMenu;
                s->subs[s->sub_count].position = i;
                s->sub_count++;
                v->submenu = s->sub_count; /* 1-based; 0 means "none" */
            } else {
                continue; /* No token to give, so do not offer the row. */
            }
        } else {
            if (mi.wID < ID_FIRST || mi.wID > ID_LAST) continue;
            v->id = (int32_t)(mi.wID - ID_FIRST);
            canonical_verb(s->cm, (UINT)v->id, v->verb, (int)sizeof(v->verb));
        }
        count++;
    }

    while (count > 0 && out[count - 1].is_separator) count--;
    return count;
}

/* Builds the session's IContextMenu and reads its top level. */
static int build(struct FlWin32ShellMenu* s) {
    IContextMenu* cm = NULL;

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

    s->cm = cm;
    /* IContextMenu3 first: a handler that implements both wants the newer one,
     * and HandleMenuMsg2 is what fills a submenu in on Windows 11. Either may
     * be absent, and a session with neither simply cannot expand anything. */
    cm->lpVtbl->QueryInterface(cm, &IID_IContextMenu3, (void**)&s->cm3);
    cm->lpVtbl->QueryInterface(cm, &IID_IContextMenu2, (void**)&s->cm2);

    s->menu = CreatePopupMenu();
    if (s->menu == NULL) return 0;

    /* CMF_EXPLORE is what a folder VIEW asks for, and it is the difference
     * between the menu a file gets in Explorer's list and the shorter one it
     * gets on the desktop. CMF_EXTENDEDVERBS is Shift+right-click: the extra
     * verbs Windows hides ("Open in new process", "Copy as path" on older
     * builds), asked for only when the caller says the modifier was down. */
    UINT flags = CMF_NORMAL | CMF_EXPLORE;
    if (s->extended) flags |= CMF_EXTENDEDVERBS;
    HRESULT hr = s->cm->lpVtbl->QueryContextMenu(s->cm, s->menu, 0,
                                                 ID_FIRST, ID_LAST, flags);
    if (FAILED(hr)) return 0;

    s->count = collect_menu(s, s->menu, s->items, FLWIN32_SHELLMENU_MAX);
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
static int expand(struct FlWin32ShellMenu* s, int token,
                  FlWin32ShellVerb* out, int max) {
    if (token < 1 || token > s->sub_count) return 0;
    FlWin32SubMenu sub = s->subs[token - 1];
    if (sub.menu == NULL) return 0;

    if (s->cm3 != NULL) {
        LRESULT unused = 0;
        s->cm3->lpVtbl->HandleMenuMsg2(s->cm3, WM_INITMENUPOPUP,
                                       (WPARAM)sub.menu,
                                       MAKELPARAM(sub.position, FALSE), &unused);
    } else if (s->cm2 != NULL) {
        s->cm2->lpVtbl->HandleMenuMsg(s->cm2, WM_INITMENUPOPUP,
                                      (WPARAM)sub.menu,
                                      MAKELPARAM(sub.position, FALSE));
    }
    return collect_menu(s, sub.menu, out, max);
}

/* The canonical verb of a top-level row, or "". */
static const char* verb_of(struct FlWin32ShellMenu* s, int id) {
    for (int i = 0; i < s->count; i++) {
        if (!s->items[i].is_separator && s->items[i].id == id) {
            return s->items[i].verb;
        }
    }
    return "";
}

static int invoke(struct FlWin32ShellMenu* s, int id) {
    if (s->cm == NULL || id < 0) return 0;

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
    if (strcmp(verb_of(s, id), "properties") == 0) {
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

    HRESULT hr = s->cm->lpVtbl->InvokeCommand(s->cm, (CMINVOKECOMMANDINFO*)&ici);
    return SUCCEEDED(hr) ? 1 : 0;
}

static void release_session(struct FlWin32ShellMenu* s) {
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
     * belongs to somebody else, so it is unconditional here. */
    OleFlushClipboard();
    if (s->menu != NULL) { DestroyMenu(s->menu); s->menu = NULL; }
    if (s->cm3 != NULL) { s->cm3->lpVtbl->Release(s->cm3); s->cm3 = NULL; }
    if (s->cm2 != NULL) { s->cm2->lpVtbl->Release(s->cm2); s->cm2 = NULL; }
    if (s->cm != NULL) { s->cm->lpVtbl->Release(s->cm); s->cm = NULL; }
}

static DWORD WINAPI session_thread(LPVOID param) {
    struct FlWin32ShellMenu* s = (struct FlWin32ShellMenu*)param;

    /* OleInitialize, not CoInitializeEx: it is an apartment PLUS the OLE
     * libraries, and the difference is not academic here. A shell extension
     * expects to be able to use the clipboard and drag-and-drop, and both are
     * OLE -- OleSetClipboard on a thread that only ever called CoInitializeEx
     * fails with CO_E_NOTINITIALIZED, which is a Copy that silently copies
     * nothing. Explorer's own threads are OleInitialize'd. */
    HRESULT co = OleInitialize(NULL);
    if (SUCCEEDED(co)) {
        s->status = build(s) ? 1 : -1;
    } else {
        s->status = -1;
    }
    SetEvent(s->ev_ready);

    for (;;) {
        /* Waits on the request AND on the message queue. The second half is
         * not optional: this is an STA, and everything COM does for it --
         * marshaling a call in from another apartment, a handler's own hidden
         * window -- happens through messages. A thread that only waits on the
         * event deadlocks the first handler that needs either. */
        DWORD w = MsgWaitForMultipleObjects(1, &s->ev_request, FALSE,
                                            INFINITE, QS_ALLINPUT);
        if (w == WAIT_OBJECT_0) {
            int cmd = s->cmd;
            s->cmd = CMD_NONE;
            if (cmd == CMD_QUIT) {
                SetEvent(s->ev_done);
                break;
            }
            if (cmd == CMD_EXPAND) {
                s->out_count = expand(s, s->arg, s->out, s->out_max);
            } else if (cmd == CMD_INVOKE) {
                s->out_count = invoke(s, s->arg);
            }
            SetEvent(s->ev_done);
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

    release_session(s);
    if (SUCCEEDED(co)) OleUninitialize();
    return 0;
}

/* Hands `cmd` to the session thread and waits for it to be done with it. */
static void request(struct FlWin32ShellMenu* s, int cmd, int arg,
                    FlWin32ShellVerb* out, int out_max) {
    s->cmd = cmd;
    s->arg = arg;
    s->out = out;
    s->out_max = out_max;
    s->out_count = 0;
    SetEvent(s->ev_request);
    WaitForSingleObject(s->ev_done, INFINITE);
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
    s->ev_ready = CreateEventW(NULL, TRUE, FALSE, NULL);   /* manual reset */
    s->ev_request = CreateEventW(NULL, FALSE, FALSE, NULL);
    s->ev_done = CreateEventW(NULL, FALSE, FALSE, NULL);
    if (s->ev_ready == NULL || s->ev_request == NULL || s->ev_done == NULL) {
        if (s->ev_ready) CloseHandle(s->ev_ready);
        if (s->ev_request) CloseHandle(s->ev_request);
        if (s->ev_done) CloseHandle(s->ev_done);
        free(s);
        return NULL;
    }

    s->thread = CreateThread(NULL, 0, session_thread, s, 0, NULL);
    if (s->thread == NULL) {
        CloseHandle(s->ev_ready);
        CloseHandle(s->ev_request);
        CloseHandle(s->ev_done);
        free(s);
        return NULL;
    }
    return s;
}

int32_t flwin32_shellmenu_items(FlWin32ShellMenu* s, FlWin32ShellVerb* out,
                                int32_t max) {
    if (s == NULL || out == NULL || max <= 0) return -1;
    WaitForSingleObject(s->ev_ready, INFINITE);
    if (s->status != 1) return -1;
    int n = s->count < max ? s->count : max;
    memcpy(out, s->items, (size_t)n * sizeof(FlWin32ShellVerb));
    return n;
}

int32_t flwin32_shellmenu_expand(FlWin32ShellMenu* s, int32_t token,
                                 FlWin32ShellVerb* out, int32_t max) {
    if (s == NULL || out == NULL || max <= 0) return 0;
    WaitForSingleObject(s->ev_ready, INFINITE);
    if (s->status != 1) return 0;
    request(s, CMD_EXPAND, (int)token, out, (int)max);
    return (int32_t)s->out_count;
}

int32_t flwin32_shellmenu_invoke(FlWin32ShellMenu* s, int32_t id) {
    if (s == NULL) return 0;
    WaitForSingleObject(s->ev_ready, INFINITE);
    if (s->status != 1) return 0;
    request(s, CMD_INVOKE, (int)id, NULL, 0);
    return (int32_t)s->out_count;
}

void flwin32_shellmenu_close(FlWin32ShellMenu* s) {
    if (s == NULL) return;
    /* The query may still be running -- a menu dismissed before the handlers
     * answered is the ordinary case, not the rare one. ev_ready is what makes
     * that safe: the thread signals it whether the build succeeded or failed,
     * and only then does it start looking at requests, so the quit cannot
     * arrive while it is mid-QueryContextMenu. */
    WaitForSingleObject(s->ev_ready, INFINITE);
    request(s, CMD_QUIT, 0, NULL, 0);
    WaitForSingleObject(s->thread, INFINITE);
    CloseHandle(s->thread);
    CloseHandle(s->ev_ready);
    CloseHandle(s->ev_request);
    CloseHandle(s->ev_done);
    free(s);
}
