// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/*
 * flwin32_apps.c -- the installed applications, and how to start one.
 *
 * On Linux the Starling shell reads the app registry: catalog.d/*.app plus the
 * .desktop entries app-install records. Windows has no such registry, and what
 * stands in for it is TWO catalogs, not one:
 *
 *   - the START MENU, a directory tree of .lnk shortcuts in a machine-wide
 *     location and a per-user one. It carries what a launcher wants: the
 *     target, its arguments, and the folder to group the entry under.
 *   - the APPSFOLDER, a virtual shell folder keyed by AppUserModelID. A
 *     packaged app -- MSIX, Store, UWP -- has NO shortcut anywhere and lives
 *     only here, so a shell that reads the Start Menu alone cannot see
 *     Settings, the Store, Photos, Notepad, Terminal or Calculator, and
 *     cannot start them either. Measured on the test machine: 79 shortcuts
 *     against 127 AppsFolder entries, 34 of them packaged.
 *
 * Explorer's own Start reads both and so do we -- the Start Menu first,
 * because it says more, and the AppsFolder for everything the walk did not
 * already produce.
 *
 * Plain ASCII throughout, same reason as the neighbouring files.
 *
 * The one thing worth knowing: a .lnk is a structured binary file, not a
 * symlink, and the only supported way to read one is the IShellLink COM
 * interface. Parsing the format by hand is a known-bad idea -- the target can
 * be stored as an item-ID list rather than a path, and resolving that needs
 * the shell anyway.
 */

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <windows.h>
#include <shlobj.h>    /* IShellLinkW, SHGetKnownFolderPath */
#include <shobjidl.h>
#include <objbase.h>
#include <shellapi.h>  /* ShellExecuteW */
#include <stdio.h>     /* _snwprintf_s */
#include <stdlib.h>
#include <string.h>

#include "include/FlutterWin32Bridge.h"

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")

/* UTF-16 -> UTF-8 into the caller's buffer, with the shared convention:
 * bytes written including the terminator, or -1 when the buffer is short. */
static int32_t wide_copy_out(const wchar_t* w, char* out, int32_t out_size) {
    if (w == NULL) return 0;
    int need = WideCharToMultiByte(CP_UTF8, 0, w, -1, NULL, 0, NULL, NULL);
    if (need <= 0) return 0;
    if (out == NULL || out_size < need) return -1;
    WideCharToMultiByte(CP_UTF8, 0, w, -1, out, out_size, NULL, NULL);
    return need;
}

static wchar_t* utf8_to_wide(const char* utf8) {
    if (utf8 == NULL) return NULL;
    int n = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, NULL, 0);
    if (n <= 0) return NULL;
    wchar_t* out = (wchar_t*)calloc((size_t)n, sizeof(wchar_t));
    if (out == NULL) return NULL;
    MultiByteToWideChar(CP_UTF8, 0, utf8, -1, out, n);
    return out;
}

/* COM on this thread, once PER THREAD.
 *
 * The flag is thread-local and that is the whole point. It used to be a plain
 * static, which was correct exactly as long as every caller was the UI thread.
 * The moment icon rasterization moved to a background thread, the flag was
 * already set by the UI thread, CoInitializeEx was skipped, and every call
 * needing the shell failed on a thread with no apartment -- CoCreateInstance
 * for IShellLink returns an error, so the shortcut's own icon could not be
 * read and roughly half the Start Menu quietly fell back to a generic glyph.
 * No crash, no message: just the wrong picture.
 *
 * An apartment is a property of a THREAD, so the bookkeeping has to be too. */
static DWORD g_ui_thread = 0;

void flwin32_com_mark_ui_thread(void) { g_ui_thread = GetCurrentThreadId(); }

void flwin32_com_ensure(void) {
    static __declspec(thread) int done = 0;
    if (done) return;
    done = 1;
    /* STA on the UI thread, MTA everywhere else, and the distinction is not
     * academic.
     *
     * A single-threaded apartment only works if its thread pumps messages:
     * that is how COM marshals calls into it. The UI thread does, because it
     * IS a message loop. A worker from Swift's cooperative pool does not, and
     * never will. Initialized STA there, everything that needs the shell to
     * marshal anything fails -- measured, 15 of 79 Start Menu icons came back
     * empty and drew a generic glyph, silently and only for the entries whose
     * icon has to be resolved rather than read straight out of an exe.
     *
     * MTA on those threads lets COM host apartment-model objects itself. */
    if (GetCurrentThreadId() == g_ui_thread) {
        CoInitializeEx(NULL, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    } else {
        CoInitializeEx(NULL, COINIT_MULTITHREADED | COINIT_DISABLE_OLE1DDE);
    }
}

static void ensure_com(void) { flwin32_com_ensure(); }

int32_t flwin32_shortcut_target(const char* shortcut_path,
                                char* out,
                                int32_t out_size) {
    if (shortcut_path == NULL) return 0;
    ensure_com();

    wchar_t* wpath = utf8_to_wide(shortcut_path);
    if (wpath == NULL) return 0;

    IShellLinkW* link = NULL;
    int32_t result = 0;
    if (SUCCEEDED(CoCreateInstance(&CLSID_ShellLink, NULL, CLSCTX_INPROC_SERVER,
                                   &IID_IShellLinkW, (void**)&link))) {
        IPersistFile* file = NULL;
        if (SUCCEEDED(link->lpVtbl->QueryInterface(link, &IID_IPersistFile,
                                                   (void**)&file))) {
            if (SUCCEEDED(file->lpVtbl->Load(file, wpath, STGM_READ))) {
                wchar_t target[MAX_PATH];
                target[0] = L'\0';
                /* No SLGP_UNCPRIORITY / no resolve: Resolve() would go looking
                 * for a moved target, which puts a network timeout in the
                 * middle of building a dock. The stored path is what Explorer
                 * shows. */
                if (SUCCEEDED(link->lpVtbl->GetPath(link, target, MAX_PATH, NULL,
                                                    SLGP_RAWPATH))) {
                    /* SLGP_RAWPATH means literally raw: a great many Windows
                     * shortcuts store "%windir%\\system32\\charmap.exe"
                     * rather than a resolved path, and every one of those
                     * fails to open, fails to yield an icon, and fails to
                     * match a running window's executable -- silently, and
                     * only for the built-in tools, which is what makes it
                     * look like a font or a rendering problem rather than a
                     * path one. */
                    wchar_t expanded[MAX_PATH];
                    DWORD n = ExpandEnvironmentStringsW(target, expanded, MAX_PATH);
                    result = wide_copy_out(
                        (n > 0 && n <= MAX_PATH) ? expanded : target,
                        out, out_size);
                }
            }
            file->lpVtbl->Release(file);
        }
        link->lpVtbl->Release(link);
    }
    free(wpath);
    return result;
}

/* Target, arguments and working directory in ONE link load.
 *
 * Not three calls: the catalog walk already loads every .lnk once, and the
 * load is the expensive half. And not just the target, because launching the
 * target without the shortcut's arguments silently starts the wrong thing --
 * a great many Start Menu entries are one exe plus a switch (control panel
 * applets, the PowerShell profiles, anything with an -ExecutionPolicy). */
int32_t flwin32_shortcut_info(const char* shortcut_path,
                              char* target, int32_t target_size,
                              char* arguments, int32_t arguments_size,
                              char* workdir, int32_t workdir_size) {
    if (shortcut_path == NULL) return 0;
    ensure_com();

    wchar_t* wpath = utf8_to_wide(shortcut_path);
    if (wpath == NULL) return 0;

    if (target != NULL && target_size > 0) target[0] = '\0';
    if (arguments != NULL && arguments_size > 0) arguments[0] = '\0';
    if (workdir != NULL && workdir_size > 0) workdir[0] = '\0';

    IShellLinkW* link = NULL;
    int32_t result = 0;
    if (SUCCEEDED(CoCreateInstance(&CLSID_ShellLink, NULL, CLSCTX_INPROC_SERVER,
                                   &IID_IShellLinkW, (void**)&link))) {
        IPersistFile* file = NULL;
        if (SUCCEEDED(link->lpVtbl->QueryInterface(link, &IID_IPersistFile,
                                                   (void**)&file))) {
            if (SUCCEEDED(file->lpVtbl->Load(file, wpath, STGM_READ))) {
                wchar_t buf[MAX_PATH];
                wchar_t expanded[MAX_PATH];
                DWORD n;

                buf[0] = L'\0';
                /* SLGP_RAWPATH and then expand by hand -- see the comment in
                 * flwin32_shortcut_target for why both halves are needed. */
                if (SUCCEEDED(link->lpVtbl->GetPath(link, buf, MAX_PATH, NULL,
                                                    SLGP_RAWPATH))) {
                    n = ExpandEnvironmentStringsW(buf, expanded, MAX_PATH);
                    result = wide_copy_out((n > 0 && n <= MAX_PATH) ? expanded : buf,
                                           target, target_size);
                }

                /* GetPath ANSWERS SUCCESSFULLY WITH NOTHING for a shortcut
                 * whose target is a folder or a shell namespace item, and the
                 * Recent folder -- which is where Start's Recommended list
                 * comes from -- is full of exactly those. Every one of its
                 * eight shortcuts on this machine came back S_OK with an empty
                 * string, which reads as "the reader is broken" rather than
                 * "ask a different way".
                 *
                 * The different way is the link's ID LIST: a PIDL names any
                 * shell item, and SHGetPathFromIDListW turns the ones that
                 * have a file-system path into that path. The ones that do not
                 * -- ms-gamingoverlay:// and the Control Panel pages -- come
                 * back empty here too, which is the correct answer for them. */
                if (buf[0] == L'\0') {
                    LPITEMIDLIST pidl = NULL;
                    if (SUCCEEDED(link->lpVtbl->GetIDList(link, &pidl))
                        && pidl != NULL) {
                        if (SHGetPathFromIDListW(pidl, buf) && buf[0] != L'\0') {
                            result = wide_copy_out(buf, target, target_size);
                        }
                        CoTaskMemFree(pidl);
                    }
                }

                buf[0] = L'\0';
                if (SUCCEEDED(link->lpVtbl->GetArguments(link, buf, MAX_PATH))
                    && buf[0] != L'\0') {
                    n = ExpandEnvironmentStringsW(buf, expanded, MAX_PATH);
                    wide_copy_out((n > 0 && n <= MAX_PATH) ? expanded : buf,
                                  arguments, arguments_size);
                }

                buf[0] = L'\0';
                if (SUCCEEDED(link->lpVtbl->GetWorkingDirectory(link, buf, MAX_PATH))
                    && buf[0] != L'\0') {
                    n = ExpandEnvironmentStringsW(buf, expanded, MAX_PATH);
                    wide_copy_out((n > 0 && n <= MAX_PATH) ? expanded : buf,
                                  workdir, workdir_size);
                }
            }
            file->lpVtbl->Release(file);
        }
        link->lpVtbl->Release(link);
    }
    free(wpath);
    return result;
}

int32_t flwin32_shortcut_icon(const char* shortcut_path,
                              char* out,
                              int32_t out_size,
                              int32_t* index) {
    if (shortcut_path == NULL) return 0;
    ensure_com();
    if (index != NULL) *index = 0;

    wchar_t* wpath = utf8_to_wide(shortcut_path);
    if (wpath == NULL) return 0;

    IShellLinkW* link = NULL;
    int32_t result = 0;
    if (SUCCEEDED(CoCreateInstance(&CLSID_ShellLink, NULL, CLSCTX_INPROC_SERVER,
                                   &IID_IShellLinkW, (void**)&link))) {
        IPersistFile* file = NULL;
        if (SUCCEEDED(link->lpVtbl->QueryInterface(link, &IID_IPersistFile,
                                                   (void**)&file))) {
            if (SUCCEEDED(file->lpVtbl->Load(file, wpath, STGM_READ))) {
                wchar_t icon[MAX_PATH];
                int icon_index = 0;
                icon[0] = L'\0';
                if (SUCCEEDED(link->lpVtbl->GetIconLocation(link, icon, MAX_PATH,
                                                            &icon_index)) &&
                    icon[0] != L'\0') {
                    /* Same expansion as the target: these are stored raw too,
                     * and "%SystemRoot%\\system32\\imageres.dll" opens as
                     * nothing at all. */
                    wchar_t expanded[MAX_PATH];
                    DWORD n = ExpandEnvironmentStringsW(icon, expanded, MAX_PATH);
                    result = wide_copy_out(
                        (n > 0 && n <= MAX_PATH) ? expanded : icon, out, out_size);
                    if (index != NULL) *index = (int32_t)icon_index;
                }
            }
            file->lpVtbl->Release(file);
        }
        link->lpVtbl->Release(link);
    }
    free(wpath);
    return result;
}

int32_t flwin32_known_folder(int32_t which, char* out, int32_t out_size) {
    /* 0 = the machine-wide Start Menu programs, 1 = this user's. Two folders,
     * not one: an app installed for all users lands in the first and one
     * installed for the current user in the second, and a dock that reads
     * only ProgramData silently misses everything installed per-user --
     * which on a modern Windows is most things. 2/3 are the Startup pair,
     * same split, for the session slot's startup runner. */
    const KNOWNFOLDERID* id;
    switch (which) {
        case 1: id = &FOLDERID_Programs; break;
        case 2: id = &FOLDERID_Startup; break;
        case 3: id = &FOLDERID_CommonStartup; break;
        default: id = &FOLDERID_CommonPrograms; break;
    }
    PWSTR path = NULL;
    if (FAILED(SHGetKnownFolderPath(id, 0, NULL, &path))) return 0;
    int32_t n = wide_copy_out(path, out, out_size);
    CoTaskMemFree(path);
    return n;
}

/* Hand our foreground rights to whatever is about to be started.
 *
 * Windows refuses SetForegroundWindow to a process that does not already own
 * the foreground. A shell that has just been clicked DOES own it, and the way
 * it lets a launched app come up in front is to pass that right on -- exactly
 * what the tray click does before raising an app's menu, and what explorer
 * does here.
 *
 * ASFW_ANY rather than a pid, and that is the whole point. Granting the pid
 * we start covers only the case that already worked: a program that creates
 * its own window. It does nothing for the ones that hand off -- Windows
 * Terminal reuses an existing WindowsTerminal.exe, a packaged app is created
 * by an activation broker -- because the process that ends up owning the
 * window is not the process we started, and cannot be known before it exists.
 * Measured on the test box: mspaint came up on top, Windows Terminal opened
 * BEHIND everything including the dock, which is issue #28 exactly.
 *
 * The grant lapses on the next foreground change, so this is a permission for
 * the launch in flight and not a standing one. */
static void allow_launched_app_to_foreground(void) {
    AllowSetForegroundWindow(ASFW_ANY);
}

int32_t flwin32_launch(const char* path, const char* arguments,
                       const char* directory) {
    if (path == NULL) return 0;
    ensure_com();
    wchar_t* wpath = utf8_to_wide(path);
    wchar_t* wargs = utf8_to_wide(arguments);
    wchar_t* wdir = utf8_to_wide(directory);
    if (wpath == NULL) {
        free(wargs);
        free(wdir);
        return 0;
    }
    /* ShellExecuteW, not CreateProcess: what arrives here can be a URL or a
     * document as well as a program, and only the shell knows how to start
     * those. SW_SHOWNORMAL so a launched app does not inherit the shell's own
     * window state.
     *
     * Callers should hand this the shortcut's TARGET rather than the .lnk
     * wherever they have one. Measured on this machine, opening a .lnk costs
     * 484ms the first time in a process and 73ms after; opening the exe it
     * points at costs 8ms, cold or warm. The difference is the shell's link
     * resolution machinery, and it is charged to whatever thread asks.
     *
     * The return is a legacy HINSTANCE-shaped error code: anything <= 32 is a
     * failure. */
    allow_launched_app_to_foreground();
    flwin32_trace("launch: ShellExecuteW begin");
    HINSTANCE rc = ShellExecuteW(NULL, L"open", wpath, wargs, wdir, SW_SHOWNORMAL);
    flwin32_trace("launch: ShellExecuteW end");
    free(wpath);
    free(wargs);
    free(wdir);
    return ((INT_PTR)rc > 32) ? 1 : 0;
}

/* ---------------------------------------------------------------------------
 * The AppsFolder: the half of the catalog that has no files in it.
 *
 * `shell:AppsFolder` is a virtual folder whose children are applications
 * rather than files. Each child's PARENT-RELATIVE PARSING NAME is its
 * AppUserModelID, and that id comes in four shapes on a real machine:
 *
 *   Microsoft.WindowsCalculator_8wekyb3d8bbwe!App   packaged -- the '!' is
 *                                                   the package/app split
 *   Microsoft.AutoGenerated.{GUID}                  a Start Menu .lnk the
 *                                                   shell gave an id to
 *   C:\...\python.exe                               a program, addressed by
 *                                                   its own path
 *   https://gitforwindows.org/faq                   a shortcut to a URL
 *
 * Only the first kind is invisible to the .lnk walk; the rest are the same
 * entries seen from the other side, and the caller drops them.
 *
 * Snapshot-object shape, like flwin32_ns_list: one call resolves everything
 * into plain C strings and releases every COM object before returning, so
 * the caller never holds an apartment-bound pointer across a thread hop.
 * -------------------------------------------------------------------------*/

/* Defined locally rather than pulled from uuid.lib: BHID_EnumItems is
 * __declspec(selectany) in the C++ headers and simply absent from a C build,
 * and the GUID is documented and frozen. flwin32_namespace.c carries its own
 * copy for the same reason -- one per translation unit, no link-order
 * coupling between two files that otherwise share nothing. */
static const GUID kAppsEnumItemsBHID =
    {0x94f60519, 0x2850, 0x4924,
     {0xaa, 0x5a, 0xd1, 0x5e, 0x84, 0x86, 0x80, 0x39}};

typedef struct {
    char* app_id;   /* the AppUserModelID (UTF-8) */
    char* name;     /* what the user sees (UTF-8) */
} AppsEntry;

struct FlWin32AppsList {
    AppsEntry* entries;
    int32_t count;
};

static char* apps_utf8_dup(const wchar_t* w) {
    if (w == NULL) return _strdup("");
    int need = WideCharToMultiByte(CP_UTF8, 0, w, -1, NULL, 0, NULL, NULL);
    if (need <= 0) return _strdup("");
    char* out = (char*)malloc((size_t)need);
    if (out == NULL) return NULL;
    WideCharToMultiByte(CP_UTF8, 0, w, -1, out, need, NULL, NULL);
    return out;
}

static char* apps_display_name(IShellItem* item, SIGDN which) {
    LPWSTR w = NULL;
    if (FAILED(item->lpVtbl->GetDisplayName(item, which, &w))) {
        return _strdup("");
    }
    char* out = apps_utf8_dup(w);
    CoTaskMemFree(w);
    return out;
}

typedef struct {
    AppsEntry* entries;
    int32_t count;
    int32_t capacity;
} AppsBuild;

/* One child of the AppsFolder into the build. 0 only on allocation failure. */
static int apps_collect(AppsBuild* b, IShellItem* child) {
    if (b->count == b->capacity) {
        int32_t grown_cap = b->capacity * 2;
        AppsEntry* grown = (AppsEntry*)realloc(
            b->entries, (size_t)grown_cap * sizeof(AppsEntry));
        if (grown == NULL) return 0;
        b->entries = grown;
        b->capacity = grown_cap;
    }
    AppsEntry* e = &b->entries[b->count];
    memset(e, 0, sizeof(*e));
    /* PARENTRELATIVEPARSING, not DESKTOPABSOLUTEPARSING: the absolute
     * form of an AppsFolder child is the folder's own CLSID with the id
     * hung off it, and what launches an app is the id alone. */
    e->app_id = apps_display_name(child, SIGDN_PARENTRELATIVEPARSING);
    e->name = apps_display_name(child, SIGDN_NORMALDISPLAY);
    if (e->app_id == NULL || e->name == NULL) {
        free(e->app_id);
        free(e->name);
        return 0;
    }
    b->count++;
    return 1;
}

FlWin32AppsList* flwin32_apps_folder_list(void) {
    ensure_com();

    AppsBuild build;
    memset(&build, 0, sizeof(build));
    build.capacity = 128;
    build.entries = (AppsEntry*)calloc((size_t)build.capacity,
                                       sizeof(AppsEntry));
    if (build.entries == NULL) return NULL;
    int enumerated = 0;

    IShellItem* root = NULL;
    if (SUCCEEDED(SHCreateItemFromParsingName(L"shell:AppsFolder", NULL,
                                              &IID_IShellItem,
                                              (void**)&root))) {
        IEnumShellItems* iter = NULL;
        if (SUCCEEDED(root->lpVtbl->BindToHandler(root, NULL,
                                                  &kAppsEnumItemsBHID,
                                                  &IID_IEnumShellItems,
                                                  (void**)&iter))) {
            enumerated = 1;
            IShellItem* child = NULL;
            while (iter->lpVtbl->Next(iter, 1, &child, NULL) == S_OK) {
                int ok = apps_collect(&build, child);
                child->lpVtbl->Release(child);
                if (!ok) break;
            }
            iter->lpVtbl->Release(iter);
        }
        root->lpVtbl->Release(root);
    }

    if (!enumerated) {
        /* The classic walk, exactly as flwin32_ns_list keeps one: the modern
         * enumerator is refused outright by some shell folders, and a
         * catalog that silently comes back empty is worse than a slow one. */
        LPITEMIDLIST pidl = NULL;
        IShellFolder* folder = NULL;
        IEnumIDList* ids = NULL;
        if (SUCCEEDED(SHParseDisplayName(L"shell:AppsFolder", NULL, &pidl, 0,
                                         NULL))
            && SUCCEEDED(SHBindToObject(NULL, pidl, NULL, &IID_IShellFolder,
                                        (void**)&folder))
            && SUCCEEDED(folder->lpVtbl->EnumObjects(
                   folder, NULL, SHCONTF_FOLDERS | SHCONTF_NONFOLDERS, &ids))
            && ids != NULL) {
            enumerated = 1;
            LPITEMIDLIST child_pidl = NULL;
            while (ids->lpVtbl->Next(ids, 1, &child_pidl, NULL) == S_OK) {
                IShellItem* child = NULL;
                int ok = 1;
                if (SUCCEEDED(SHCreateItemWithParent(NULL, folder, child_pidl,
                                                     &IID_IShellItem,
                                                     (void**)&child))) {
                    ok = apps_collect(&build, child);
                    child->lpVtbl->Release(child);
                }
                CoTaskMemFree(child_pidl);
                if (!ok) break;
            }
            ids->lpVtbl->Release(ids);
        }
        if (folder != NULL) folder->lpVtbl->Release(folder);
        if (pidl != NULL) CoTaskMemFree(pidl);
    }

    FlWin32AppsList* list = NULL;
    if (enumerated) {
        list = (FlWin32AppsList*)calloc(1, sizeof(FlWin32AppsList));
        if (list != NULL) {
            list->entries = build.entries;
            list->count = build.count;
            build.entries = NULL;
        }
    }
    if (build.entries != NULL) {
        for (int32_t i = 0; i < build.count; i++) {
            free(build.entries[i].app_id);
            free(build.entries[i].name);
        }
        free(build.entries);
    }
    return list;
}

void flwin32_apps_folder_free(FlWin32AppsList* list) {
    if (list == NULL) return;
    for (int32_t i = 0; i < list->count; i++) {
        free(list->entries[i].app_id);
        free(list->entries[i].name);
    }
    free(list->entries);
    free(list);
}

int32_t flwin32_apps_folder_count(FlWin32AppsList* list) {
    return list == NULL ? 0 : list->count;
}

/* field: 0 = the AppUserModelID, 1 = the display name. */
int32_t flwin32_apps_folder_field(FlWin32AppsList* list, int32_t index,
                                  int32_t field, char* out, int32_t out_size) {
    if (list == NULL || index < 0 || index >= list->count || out == NULL
        || out_size <= 0) {
        return 0;
    }
    const char* s = field == 0 ? list->entries[index].app_id
                               : list->entries[index].name;
    if (s == NULL) s = "";
    int len = (int)strlen(s);
    if (len + 1 > out_size) len = out_size - 1;
    memcpy(out, s, (size_t)len);
    out[len] = 0;
    return len + 1;
}

/* Starting an app by its AppUserModelID -- two routes, because neither one
 * covers the whole folder.
 *
 * The ACTIVATION MANAGER is the documented way to start a packaged app: it
 * hands the id to the same broker the Start menu uses and answers with a
 * pid. It only knows packaged ids, and it refuses to run at all from an
 * ELEVATED process (a shell started with highest privileges gets
 * E_ACCESSDENIED here, and nothing starts).
 *
 * The SHELL PATH -- "shell:AppsFolder\<id>" through ShellExecuteW -- invokes
 * the item's default verb the way a double-click in Explorer would, and
 * works for every shape of id including the autogenerated ones. It is the
 * fallback rather than the first choice because it costs the shell's whole
 * parse-and-invoke machinery.
 *
 * Note this is NOT the protocol path (`ms-settings:` and friends), which is
 * a separate fault under our shell and does not need fixing to launch these.
 *
 * Answers WHICH route ran -- 1 the activation manager, 2 the shell path, 0
 * neither -- because "it launched" and "it launched the way we intended" are
 * different facts, and the second one is what a probe needs to see.
 */
static const CLSID kAppActivationManagerCLSID =
    {0x45ba127d, 0x10a8, 0x46ea,
     {0x8a, 0xb7, 0x56, 0xea, 0x90, 0x78, 0x94, 0x3c}};
static const IID kAppActivationManagerIID =
    {0x2e941141, 0x7f97, 0x4756,
     {0xba, 0x1d, 0x9d, 0xec, 0xde, 0x89, 0x4a, 0x3d}};

/* A known-folder-relative AppsFolder id, resolved to a real path.
 *
 * Windows 11 files most of the old Administrative Tools as
 * "{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\dfrgui.exe" -- a KNOWNFOLDERID
 * with a file name hung off it, not a path. It matters twice over: an id
 * like that resolves to nothing on disk (no icon, no window match), and it
 * cannot be recognized as the same app the Start Menu shortcut points at, so
 * the launcher lists BOTH -- once under the shortcut's file name ("dfrgui")
 * and once under the shell's display name ("Defragment and Optimize
 * Drives").
 *
 * Answers 0 for anything that is not that shape, which is most ids. */
int32_t flwin32_expand_known_folder_id(const char* app_id, char* out,
                                       int32_t out_size) {
    if (app_id == NULL || app_id[0] != '{' || out == NULL || out_size <= 0) {
        return 0;
    }
    const char* close = strchr(app_id, '}');
    if (close == NULL || close[1] != '\\' || close[2] == 0) return 0;

    size_t guid_len = (size_t)(close - app_id) + 1;
    if (guid_len >= 64) return 0;
    char guid_ascii[64];
    memcpy(guid_ascii, app_id, guid_len);
    guid_ascii[guid_len] = 0;

    wchar_t guid_wide[64];
    if (MultiByteToWideChar(CP_UTF8, 0, guid_ascii, -1, guid_wide, 64) <= 0) {
        return 0;
    }
    GUID folder;
    if (FAILED(CLSIDFromString(guid_wide, &folder))) return 0;

    PWSTR base = NULL;
    if (FAILED(SHGetKnownFolderPath(&folder, 0, NULL, &base)) || base == NULL) {
        return 0;
    }
    wchar_t* rest = utf8_to_wide(close + 2);
    int32_t written = 0;
    if (rest != NULL) {
        size_t need = wcslen(base) + wcslen(rest) + 2;
        wchar_t* full = (wchar_t*)calloc(need, sizeof(wchar_t));
        if (full != NULL) {
            _snwprintf_s(full, need, _TRUNCATE, L"%s\\%s", base, rest);
            written = wide_copy_out(full, out, out_size);
            free(full);
        }
        free(rest);
    }
    CoTaskMemFree(base);
    return written;
}

int32_t flwin32_launch_app_id_ex(const char* app_id, char* diag,
                                 int32_t diag_size) {
    char notes[256];
    notes[0] = 0;
    if (diag != NULL && diag_size > 0) diag[0] = 0;
    if (app_id == NULL || app_id[0] == 0) return 0;
    ensure_com();
    wchar_t* wid = utf8_to_wide(app_id);
    if (wid == NULL) return 0;

    /* Same reason as the shell launch below: for a packaged app the window is
     * made by the activation broker, which is never the process we asked. */
    allow_launched_app_to_foreground();

    int32_t started = 0;
    if (strchr(app_id, '!') != NULL) {
        IApplicationActivationManager* aam = NULL;
        HRESULT create = CoCreateInstance(&kAppActivationManagerCLSID, NULL,
                                          CLSCTX_LOCAL_SERVER,
                                          &kAppActivationManagerIID,
                                          (void**)&aam);
        if (SUCCEEDED(create)) {
            DWORD pid = 0;
            DWORD t_borrow = 0, t_ready = 0, t_act = 0;
            int ready_tries = 0;
            int borrowed = 0;
            HRESULT hr;

            /* MAKE SURE THE SHELL SERVICES ARE THERE BEFORE ASKING, rather
             * than asking and recovering from the refusal.
             *
             * The recovering version is the obvious shape and it is far worse,
             * because a refused activation does not fail fast: measured on the
             * box at 45141 ms, twice, to the millisecond -- a DCOM activation
             * timeout waiting for a server that is never going to appear, not
             * work being done. Checking first costs a FindWindow.
             *
             * A packaged app of the full-trust generation does not need any of
             * this and would launch without it. It pays the borrow anyway, and
             * that is the deliberate trade: about a second and a half, against
             * a branch that would have to know which generation an app belongs
             * to before launching it, and be wrong 45 seconds at a time when
             * it guessed low. */
            if (!flwin32_shell_services_ready()) {
                DWORD tb = GetTickCount();
                borrowed = flwin32_shell_borrow_explorer();
                t_borrow = GetTickCount() - tb;
                if (borrowed) {
                    int tries;
                    DWORD tr = GetTickCount();
                    for (tries = 0; tries < 80; tries++) {
                        Sleep(50);
                        /* Its taskbar and desktop must not surface during the
                         * couple of seconds it is up. */
                        flwin32_shell_suppress_explorer_chrome();
                        if (flwin32_shell_services_ready()) break;
                    }
                    ready_tries = tries;
                    t_ready = GetTickCount() - tr;
                }
            }

            {
                DWORD ta = GetTickCount();
                int tries;
                /* Explorer's desktop window appearing is necessary, not
                 * sufficient -- the rest of its shell side lands a moment
                 * later -- so give it a few goes rather than one. */
                hr = E_FAIL;
                for (tries = 0; tries < 4 && FAILED(hr); tries++) {
                    if (tries > 0) Sleep(250);
                    hr = aam->lpVtbl->ActivateApplication(aam, wid, NULL,
                                                          AO_NONE, &pid);
                }
                t_act = GetTickCount() - ta;
            }
            /* The pid rides along so the hand-back can wait for the app's
             * window instead of guessing with a timer; a failed activation
             * has no window coming and keeps the fixed grace. */
            if (borrowed) {
                flwin32_shell_return_explorer_after(
                    SUCCEEDED(hr) ? (uint32_t)pid : 0);
            }
            aam->lpVtbl->Release(aam);
            _snprintf_s(notes, sizeof(notes), _TRUNCATE,
                        "activate=0x%08lX pid=%lu%s "
                        "[borrow=%lums ready=%lums/%d activate=%lums bars-here=%d]",
                        (unsigned long)hr, (unsigned long)pid,
                        borrowed ? " (borrowed an explorer)" : "",
                        (unsigned long)t_borrow, (unsigned long)t_ready,
                        ready_tries, (unsigned long)t_act,
                        /* THIS process's appbar count, which is zero in a
                         * one-shot launcher and only interesting in the dock.
                         * Named to say so: reading it as the dock's number
                         * cost a whole measuring round. */
                        (int)flwin32_tray_bar_count());
            if (SUCCEEDED(hr)) {
                flwin32_trace("launch: activation manager started the app");
                started = 1;
            } else {
                flwin32_trace("launch: activation manager refused; "
                              "falling back to the shell path");
            }
        } else {
            _snprintf_s(notes, sizeof(notes), _TRUNCATE,
                        "cocreate=0x%08lX", (unsigned long)create);
        }
    }

    if (!started) {
        /* MAX_PATH is not the limit here -- an AUMID is a package family
         * name plus an app id and runs long -- so the buffer is sized from
         * the string. */
        size_t chars = wcslen(wid) + 32;
        wchar_t* path = (wchar_t*)calloc(chars, sizeof(wchar_t));
        if (path != NULL) {
            _snwprintf_s(path, chars, _TRUNCATE, L"shell:AppsFolder\\%s", wid);
            SetLastError(0);
            HINSTANCE rc = ShellExecuteW(NULL, L"open", path, NULL, NULL,
                                         SW_SHOWNORMAL);
            DWORD err = GetLastError();
            started = ((INT_PTR)rc > 32) ? 2 : 0;
            char tail[128];
            _snprintf_s(tail, sizeof(tail), _TRUNCATE,
                        " shellexec=%d lasterr=%lu", (int)(INT_PTR)rc,
                        (unsigned long)err);
            strncat_s(notes, sizeof(notes), tail, _TRUNCATE);
            free(path);
        }
    }
    if (diag != NULL && diag_size > 0) {
        strncpy_s(diag, (size_t)diag_size, notes, _TRUNCATE);
    }
    free(wid);
    return started;
}

int32_t flwin32_launch_app_id(const char* app_id) {
    return flwin32_launch_app_id_ex(app_id, NULL, 0);
}
