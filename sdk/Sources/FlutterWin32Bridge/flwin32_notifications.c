// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/*
 * flwin32_notifications.c -- the toasts Windows is holding, read the way the
 * native notification centre reads them.
 *
 * UserNotificationListener is a WinRT API, and this file consumes it through
 * the raw C ABI rather than C++/WinRT: the bridge is a C target, cppwinrt
 * under clang is not a bet this package needs, and the C-mode blocks in the
 * SDK's own generated headers (windows.ui.notifications*.h) carry everything
 * required -- vtable structs and calling macros both.
 *
 * TWO THINGS KEEP THIS SIMPLE.
 *
 * First, no parameterized IIDs. The widely-feared part of raw WinRT is the
 * generated GUIDs for IAsyncOperation<T> and IVectorView<T>; none is needed
 * here, because every such object arrives ALREADY TYPED from a method that
 * returns it -- only IAsyncInfo (a stable, well-known IID) is ever QI'd for,
 * to poll an operation to completion. Polling, not a Completed handler: a
 * handler is a hand-written COM object, and everything here already runs on
 * a background thread that has nothing better to do than sleep 10ms.
 *
 * Second, no capability dance. GetAccessStatus answers synchronously, and a
 * full-trust desktop process asking RequestAccessAsync is auto-granted on
 * current builds -- the per-app "notification access" list in Settings is
 * for packaged apps. If the OS says Denied anyway, every entry point here
 * returns the failure honestly and the UI shows its empty state.
 *
 * THREADING. Callers must treat this whole file as blocking: init spins up
 * WinRT on the calling thread (MTA), reads poll an async to completion.
 * The Swift side keeps it all in Task.detached, per the shell's "nothing
 * slow on the UI thread" rule.
 */

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <windows.h>
#include <roapi.h>
#include <winstring.h>
#include <inspectable.h>
#include <asyncinfo.h>
#include <stdio.h>

#include <windows.ui.notifications.h>
#include <windows.ui.notifications.management.h>
#include <windows.applicationmodel.h>

#include "include/FlutterWin32Bridge.h"

/* Short names for the ABI mouthful, or nothing below fits on a line. */
typedef __x_ABI_CWindows_CUI_CNotifications_CManagement_CIUserNotificationListenerStatics ListenerStatics;
typedef __x_ABI_CWindows_CUI_CNotifications_CManagement_CIUserNotificationListener Listener;
typedef __x_ABI_CWindows_CUI_CNotifications_CIUserNotification UserNotification;
typedef __x_ABI_CWindows_CUI_CNotifications_CINotification Notification;
typedef __x_ABI_CWindows_CUI_CNotifications_CINotificationVisual NotificationVisual;
typedef __x_ABI_CWindows_CUI_CNotifications_CINotificationBinding NotificationBinding;
typedef __x_ABI_CWindows_CUI_CNotifications_CIAdaptiveNotificationText AdaptiveText;
typedef __x_ABI_CWindows_CApplicationModel_CIAppInfo AppInfo;
typedef __x_ABI_CWindows_CApplicationModel_CIAppDisplayInfo AppDisplayInfo;
typedef __FIAsyncOperation_1___FIVectorView_1_Windows__CUI__CNotifications__CUserNotification NotifsAsync;
typedef __FIVectorView_1_Windows__CUI__CNotifications__CUserNotification NotifsView;
typedef __FIVectorView_1_Windows__CUI__CNotifications__CAdaptiveNotificationText TextsView;
typedef __FIAsyncOperation_1_Windows__CUI__CNotifications__CManagement__CUserNotificationListenerAccessStatus AccessAsync;

/* The headers declare these IIDs extern and define them only for C++
 * consumers, so the C side carries its own copies -- values read out of the
 * same headers (MIDL_INTERFACE lines, SDK 10.0.22621). */
static const IID kIID_ListenerStatics =
    {0xff6123cf, 0x4386, 0x4aa3, {0xb7, 0x3d, 0xb8, 0x04, 0xe5, 0xb6, 0x3b, 0x23}};
static const IID kIID_IAsyncInfo =
    {0x00000036, 0x0000, 0x0000, {0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}};

static Listener* g_listener; /* held for the process; agile, MTA */

/* Poll an operation to completion through IAsyncInfo. Returns the final
 * AsyncStatus, or Error if the QI itself failed. */
static AsyncStatus wait_async(IUnknown* op, DWORD timeout_ms) {
    IAsyncInfo* info = NULL;
    if (FAILED(op->lpVtbl->QueryInterface(op, &kIID_IAsyncInfo, (void**)&info))) {
        return Error;
    }
    AsyncStatus status = Started;
    DWORD waited = 0;
    for (;;) {
        if (FAILED(info->lpVtbl->get_Status(info, &status))) status = Error;
        if (status != Started) break;
        if (waited >= timeout_ms) break;
        Sleep(10);
        waited += 10;
    }
    info->lpVtbl->Release(info);
    return status;
}

/* UTF-16 HSTRING -> caller's UTF-8 buffer, always terminated. */
static void hstring_to_utf8(HSTRING s, char* out, int32_t out_size) {
    if (out == NULL || out_size <= 0) return;
    out[0] = '\0';
    UINT32 len = 0;
    const wchar_t* raw = WindowsGetStringRawBuffer(s, &len);
    if (raw == NULL || len == 0) return;
    int n = WideCharToMultiByte(CP_UTF8, 0, raw, (int)len, out, out_size - 1,
                                NULL, NULL);
    out[n > 0 ? n : 0] = '\0';
}

int32_t flwin32_notifications_init(void) {
    if (g_listener != NULL) return 1;
    /* MULTITHREADED: this runs on a worker, and S_FALSE / mode-mismatch both
     * mean WinRT is already up on this thread, which is fine. */
    HRESULT hr = RoInitialize(RO_INIT_MULTITHREADED);
    if (FAILED(hr) && hr != RPC_E_CHANGED_MODE) return 0;

    HSTRING_HEADER header;
    HSTRING cls = NULL;
    static const wchar_t kClass[] =
        L"Windows.UI.Notifications.Management.UserNotificationListener";
    if (FAILED(WindowsCreateStringReference(kClass, (UINT32)(wcslen(kClass)),
                                            &header, &cls))) {
        return 0;
    }
    ListenerStatics* statics = NULL;
    if (FAILED(RoGetActivationFactory(cls, &kIID_ListenerStatics,
                                      (void**)&statics))) {
        return 0;
    }
    HRESULT got = statics->lpVtbl->get_Current(statics, &g_listener);
    statics->lpVtbl->Release(statics);
    return SUCCEEDED(got) && g_listener != NULL ? 1 : 0;
}

/* 2 allowed, 1 denied, 0 unspecified/unknown, -1 not initialised. The
 * request is made when the answer is not yet Allowed -- it is what flips a
 * fresh machine to Allowed, and it no-ops once answered. */
int32_t flwin32_notifications_access(void) {
    if (g_listener == NULL && !flwin32_notifications_init()) return -1;
    enum __x_ABI_CWindows_CUI_CNotifications_CManagement_CUserNotificationListenerAccessStatus status =
        UserNotificationListenerAccessStatus_Unspecified;
    if (FAILED(g_listener->lpVtbl->GetAccessStatus(g_listener, &status))) {
        return -1;
    }
    if (status != UserNotificationListenerAccessStatus_Allowed) {
        AccessAsync* op = NULL;
        if (SUCCEEDED(g_listener->lpVtbl->RequestAccessAsync(g_listener, &op))) {
            if (wait_async((IUnknown*)op, 3000) == Completed) {
                op->lpVtbl->GetResults(op, &status);
            }
            op->lpVtbl->Release(op);
        }
    }
    switch (status) {
        case UserNotificationListenerAccessStatus_Allowed: return 2;
        case UserNotificationListenerAccessStatus_Denied: return 1;
        default: return 0;
    }
}

/* One toast's worth of strings, delivered through the callback so the list
 * can be any length without an allocation contract across the boundary.
 * `time_unix` is seconds since 1970. Title is the first ToastGeneric text
 * element, body the remaining ones joined with newlines. */
int32_t flwin32_notifications_read(
    void (*emit)(void* user, uint32_t id, const char* app, const char* title,
                 const char* body, int64_t time_unix),
    void* user) {
    if (emit == NULL) return -1;
    if (g_listener == NULL && !flwin32_notifications_init()) return -1;

    NotifsAsync* op = NULL;
    if (FAILED(g_listener->lpVtbl->GetNotificationsAsync(
            g_listener, NotificationKinds_Toast, &op))) {
        return -1;
    }
    if (wait_async((IUnknown*)op, 3000) != Completed) {
        op->lpVtbl->Release(op);
        return -1;
    }
    NotifsView* view = NULL;
    HRESULT hr = op->lpVtbl->GetResults(op, &view);
    op->lpVtbl->Release(op);
    if (FAILED(hr) || view == NULL) return -1;

    unsigned int count = 0;
    view->lpVtbl->get_Size(view, &count);

    HSTRING_HEADER bind_header;
    HSTRING bind_name = NULL;
    static const wchar_t kToastGeneric[] = L"ToastGeneric";
    WindowsCreateStringReference(kToastGeneric,
                                 (UINT32)(wcslen(kToastGeneric)),
                                 &bind_header, &bind_name);

    int32_t emitted = 0;
    for (unsigned int i = 0; i < count; i++) {
        UserNotification* un = NULL;
        if (FAILED(view->lpVtbl->GetAt(view, i, &un)) || un == NULL) continue;

        unsigned int id = 0;
        un->lpVtbl->get_Id(un, &id);
        struct __x_ABI_CWindows_CFoundation_CDateTime created = {0};
        un->lpVtbl->get_CreationTime(un, &created);
        /* WinRT DateTime is 100ns ticks since 1601; unix is seconds since
         * 1970. The offset is the usual 11644473600 seconds. */
        int64_t time_unix = created.UniversalTime / 10000000LL - 11644473600LL;

        char app[128] = "";
        AppInfo* ai = NULL;
        if (SUCCEEDED(un->lpVtbl->get_AppInfo(un, &ai)) && ai != NULL) {
            AppDisplayInfo* di = NULL;
            if (SUCCEEDED(ai->lpVtbl->get_DisplayInfo(ai, &di)) && di != NULL) {
                HSTRING name = NULL;
                if (SUCCEEDED(di->lpVtbl->get_DisplayName(di, &name))) {
                    hstring_to_utf8(name, app, sizeof(app));
                    WindowsDeleteString(name);
                }
                di->lpVtbl->Release(di);
            }
            ai->lpVtbl->Release(ai);
        }

        char title[256] = "";
        char body[512] = "";
        Notification* n = NULL;
        if (SUCCEEDED(un->lpVtbl->get_Notification(un, &n)) && n != NULL) {
            NotificationVisual* visual = NULL;
            if (SUCCEEDED(n->lpVtbl->get_Visual(n, &visual)) && visual != NULL) {
                NotificationBinding* binding = NULL;
                if (SUCCEEDED(visual->lpVtbl->GetBinding(visual, bind_name,
                                                         &binding))
                    && binding != NULL) {
                    TextsView* texts = NULL;
                    if (SUCCEEDED(binding->lpVtbl->GetTextElements(binding,
                                                                   &texts))
                        && texts != NULL) {
                        unsigned int tcount = 0;
                        texts->lpVtbl->get_Size(texts, &tcount);
                        for (unsigned int t = 0; t < tcount; t++) {
                            AdaptiveText* at = NULL;
                            if (FAILED(texts->lpVtbl->GetAt(texts, t, &at))
                                || at == NULL) continue;
                            HSTRING text = NULL;
                            if (SUCCEEDED(at->lpVtbl->get_Text(at, &text))) {
                                char utf8[256];
                                hstring_to_utf8(text, utf8, sizeof(utf8));
                                if (t == 0) {
                                    lstrcpynA(title, utf8, sizeof(title));
                                } else {
                                    size_t have = strlen(body);
                                    if (have > 0 && have + 1 < sizeof(body)) {
                                        body[have++] = '\n';
                                        body[have] = '\0';
                                    }
                                    lstrcpynA(body + have, utf8,
                                              (int)(sizeof(body) - have));
                                }
                                WindowsDeleteString(text);
                            }
                            at->lpVtbl->Release(at);
                        }
                        texts->lpVtbl->Release(texts);
                    }
                    binding->lpVtbl->Release(binding);
                }
                visual->lpVtbl->Release(visual);
            }
            n->lpVtbl->Release(n);
        }

        emit(user, id, app, title, body, time_unix);
        emitted++;
        un->lpVtbl->Release(un);
    }
    view->lpVtbl->Release(view);
    return emitted;
}

int32_t flwin32_notification_remove(uint32_t id) {
    if (g_listener == NULL && !flwin32_notifications_init()) return 0;
    return SUCCEEDED(g_listener->lpVtbl->RemoveNotification(g_listener, id))
        ? 1 : 0;
}

int32_t flwin32_notifications_clear(void) {
    if (g_listener == NULL && !flwin32_notifications_init()) return 0;
    return SUCCEEDED(g_listener->lpVtbl->ClearNotifications(g_listener)) ? 1 : 0;
}
