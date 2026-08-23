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
 * (One exception now: NotificationChanged, at the bottom of this file, IS a
 * hand-written COM object. It bought the banner surface its idle back --
 * polling the store every two seconds cost ~0.25% of a core in a process
 * whose entire job is to wait for something that might not happen for hours.
 * A handler is about sixty lines of vtable; the poll was the same cost
 * forever.)
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
#include <stdlib.h>
#include <string.h>

#include <windows.ui.notifications.h>
#include <windows.ui.notifications.management.h>
#include <windows.applicationmodel.h>
#include <windows.storage.streams.h>
#include <shcore.h>
#include <wincodec.h>

#include "include/FlutterWin32Bridge.h"

/* STARLING_TOAST_DEBUG=1: what the store costs to ask, and what the arrival
 * event said when we tried to register it. Defined with the handler below. */
static int toast_debug(void);

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
static const IID kIID_IStream =
    {0x0000000c, 0x0000, 0x0000, {0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}};
static const CLSID kCLSID_WICImagingFactory =
    {0xcacaf262, 0x9370, 0x4615, {0xa1, 0x3b, 0x9f, 0x55, 0x39, 0xda, 0x4c, 0x0a}};
static const IID kIID_IWICImagingFactory =
    {0xec5ec8a9, 0xc395, 0x4314, {0x9c, 0x77, 0x54, 0xd7, 0xa9, 0x35, 0xff, 0x70}};
/* 32bppPRGBA: premultiplied RGBA, byte-for-byte what the engine's texture
 * path wants (see flwin32_icon.c) -- WIC does the swizzle, not us. */
static const GUID kGUID_WICPixelFormat32bppPRGBA =
    {0x3cc4a650, 0xa527, 0x4d37, {0xa9, 0x16, 0x31, 0x42, 0xc7, 0xeb, 0xed, 0xba}};

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

/* WHAT ASKING COSTS, measured on the box with STARLING_TOAST_DEBUG=1:
 *
 *     full read of 5 toasts   36-60 ms wall, ~6.2 ms CPU
 *     the ids alone            24 ms wall, ~6.2 ms CPU
 *
 * The same CPU either way, which is the useful finding: the price is the
 * cross-process RPC to the notification service and the marshalling around
 * it, NOT the per-toast walk through AppInfo and the ToastGeneric binding.
 * So there is no cheap "has anything changed" to poll on -- an ids-only
 * variant was written, measured, and deleted. The only lever left is HOW
 * OFTEN the question is asked, which is why the caller varies its interval
 * with whether anyone is there to read the answer.
 */

static int64_t now_micros(void) {
    LARGE_INTEGER f, t;
    QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&t);
    return t.QuadPart * 1000000LL / f.QuadPart;
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
    int64_t read_t0 = toast_debug() ? now_micros() : 0;

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
    if (toast_debug()) {
        printf("[toast] full read of %d in %lld us\n", emitted,
               (long long)(now_micros() - read_t0));
        fflush(stdout);
    }
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

/* The notifying app's logo, as premultiplied RGBA pixels the engine's
 * texture path takes as-is. Looked up by toast id (one enumeration per
 * call -- the Swift side caches per app, so this runs once per app, not
 * once per card). malloc'd; ownership passes to the caller, and
 * flwin32_host_register_pixels' texture takes it from there.
 *
 * The stream plumbing is the one place raw WinRT threatens to sprawl and
 * does not: OpenReadAsync's operation arrives typed, and
 * CreateStreamOverRandomAccessStream (shcore) turns the WinRT stream into a
 * classic IStream that WIC decodes directly -- no IBuffer, no ReadAsync. */
int32_t flwin32_notification_app_icon(uint32_t toast_id, int32_t size,
                                      uint8_t** out_pixels,
                                      int32_t* out_w, int32_t* out_h) {
    if (out_pixels == NULL || out_w == NULL || out_h == NULL) return 0;
    *out_pixels = NULL;
    if (g_listener == NULL && !flwin32_notifications_init()) return 0;

    NotifsAsync* op = NULL;
    if (FAILED(g_listener->lpVtbl->GetNotificationsAsync(
            g_listener, NotificationKinds_Toast, &op))) {
        return 0;
    }
    if (wait_async((IUnknown*)op, 3000) != Completed) {
        op->lpVtbl->Release(op);
        return 0;
    }
    NotifsView* view = NULL;
    HRESULT hr = op->lpVtbl->GetResults(op, &view);
    op->lpVtbl->Release(op);
    if (FAILED(hr) || view == NULL) return 0;

    int32_t ok = 0;
    unsigned int count = 0;
    view->lpVtbl->get_Size(view, &count);
    for (unsigned int i = 0; i < count && !ok; i++) {
        UserNotification* un = NULL;
        if (FAILED(view->lpVtbl->GetAt(view, i, &un)) || un == NULL) continue;
        unsigned int id = 0;
        un->lpVtbl->get_Id(un, &id);
        if (id != toast_id) {
            un->lpVtbl->Release(un);
            continue;
        }

        AppInfo* ai = NULL;
        AppDisplayInfo* di = NULL;
        __x_ABI_CWindows_CStorage_CStreams_CIRandomAccessStreamReference* ref = NULL;
        if (SUCCEEDED(un->lpVtbl->get_AppInfo(un, &ai)) && ai != NULL &&
            SUCCEEDED(ai->lpVtbl->get_DisplayInfo(ai, &di)) && di != NULL) {
            struct __x_ABI_CWindows_CFoundation_CSize want;
            want.Width = (FLOAT)size;
            want.Height = (FLOAT)size;
            di->lpVtbl->GetLogo(di, want, &ref);
        }
        if (ref != NULL) {
            __FIAsyncOperation_1_Windows__CStorage__CStreams__CIRandomAccessStreamWithContentType* open_op = NULL;
            if (SUCCEEDED(ref->lpVtbl->OpenReadAsync(ref, &open_op)) &&
                wait_async((IUnknown*)open_op, 3000) == Completed) {
                __x_ABI_CWindows_CStorage_CStreams_CIRandomAccessStreamWithContentType* stream = NULL;
                if (SUCCEEDED(open_op->lpVtbl->GetResults(open_op, &stream)) &&
                    stream != NULL) {
                    IStream* istream = NULL;
                    if (SUCCEEDED(CreateStreamOverRandomAccessStream(
                            (IUnknown*)stream, &kIID_IStream,
                            (void**)&istream))) {
                        IWICImagingFactory* wic = NULL;
                        if (SUCCEEDED(CoCreateInstance(
                                &kCLSID_WICImagingFactory, NULL,
                                CLSCTX_INPROC_SERVER, &kIID_IWICImagingFactory,
                                (void**)&wic))) {
                            IWICBitmapDecoder* decoder = NULL;
                            if (SUCCEEDED(wic->lpVtbl->CreateDecoderFromStream(
                                    wic, istream, NULL,
                                    WICDecodeMetadataCacheOnDemand,
                                    &decoder))) {
                                IWICBitmapFrameDecode* frame = NULL;
                                if (SUCCEEDED(decoder->lpVtbl->GetFrame(
                                        decoder, 0, &frame))) {
                                    IWICBitmapSource* converted = NULL;
                                    if (SUCCEEDED(WICConvertBitmapSource(
                                            &kGUID_WICPixelFormat32bppPRGBA,
                                            (IWICBitmapSource*)frame,
                                            &converted))) {
                                        UINT w = 0, h = 0;
                                        converted->lpVtbl->GetSize(converted,
                                                                   &w, &h);
                                        if (w > 0 && h > 0 && w <= 512 &&
                                            h <= 512) {
                                            UINT stride = w * 4;
                                            UINT bytes = stride * h;
                                            uint8_t* pixels =
                                                (uint8_t*)malloc(bytes);
                                            if (pixels != NULL &&
                                                SUCCEEDED(converted->lpVtbl
                                                    ->CopyPixels(
                                                        converted, NULL,
                                                        stride, bytes,
                                                        pixels))) {
                                                *out_pixels = pixels;
                                                *out_w = (int32_t)w;
                                                *out_h = (int32_t)h;
                                                ok = 1;
                                            } else {
                                                free(pixels);
                                            }
                                        }
                                        converted->lpVtbl->Release(converted);
                                    }
                                    frame->lpVtbl->Release(frame);
                                }
                                decoder->lpVtbl->Release(decoder);
                            }
                            wic->lpVtbl->Release(wic);
                        }
                        istream->lpVtbl->Release(istream);
                    }
                    stream->lpVtbl->Release(stream);
                }
                if (open_op != NULL) open_op->lpVtbl->Release(open_op);
            }
            ref->lpVtbl->Release(ref);
        }
        if (di != NULL) di->lpVtbl->Release(di);
        if (ai != NULL) ai->lpVtbl->Release(ai);
        un->lpVtbl->Release(un);
    }
    view->lpVtbl->Release(view);
    return ok;
}


/* ── NotificationChanged ─────────────────────────────────────────────────────
 *
 * The arrival event. Nothing the user does brings a toast banner up, so the
 * surface that shows one has to hear about the toast -- and "hear" is the
 * word: it used to READ the whole store every two seconds instead, which is
 * what a process spends its idle life on if you let it.
 *
 * This is the hand-written COM object the top of this file was pleased not to
 * need. It is a singleton with a static vtable and a refcount that never
 * reaches zero: the listener holds it for the life of the process, and there
 * is exactly one banner surface per session.
 *
 * The Invoke lands on a WinRT threadpool thread. It does nothing but call the
 * callback, and the Swift side hops to the UI thread from there -- reading the
 * store from inside an event handler would block the pool thread on an async
 * this file polls to completion.
 */

typedef __FITypedEventHandler_2_Windows__CUI__CNotifications__CManagement__CUserNotificationListener_Windows__CUI__CNotifications__CUserNotificationChangedEventArgs
    ChangedHandler;
typedef __FITypedEventHandler_2_Windows__CUI__CNotifications__CManagement__CUserNotificationListener_Windows__CUI__CNotifications__CUserNotificationChangedEventArgsVtbl
    ChangedHandlerVtbl;
typedef __x_ABI_CWindows_CUI_CNotifications_CIUserNotificationChangedEventArgs
    ChangedArgs;

static void (*g_changed_cb)(void* user);
static void* g_changed_user;
static EventRegistrationToken g_changed_token;

/* The handler's own IID, which is where a PARAMETERIZED interface differs
 * from every other IID in this file: MIDL does not emit a literal for it,
 * because there is nothing to emit -- the value is DERIVED from the
 * instantiation. WinRT's rule is SHA-1 over the namespace GUID
 * 11f47ad5-7b73-42c0-abae-878b1e16adee followed by the UTF-8 signature
 *
 *   pinterface({9de1c534-6ae1-11e0-84e1-18a905bcc53f};
 *              rc(Windows.UI.Notifications.Management.UserNotificationListener;
 *                 {62553e41-8a06-4cef-8215-6033a5be4b03});
 *              rc(Windows.UI.Notifications.UserNotificationChangedEventArgs;
 *                 {b6bd6839-79cf-4b25-82c0-0ce1eef81f8c}))
 *
 * (no whitespace in the real string), with the RFC 4122 version-5 bits set.
 * The two inner GUIDs are the default interfaces, read from the SDK headers'
 * MIDL_INTERFACE lines. Re-derivable from those four values alone, which is
 * why they are written out here rather than just the answer.
 *
 * STARLING_TOAST_DEBUG=1 prints any IID this object is asked for and does not
 * recognise -- if the derivation above is ever wrong, that log is what says
 * so, rather than a banner that silently never appears. */
static const IID kIID_ChangedHandler =
    {0x10242902, 0xb897, 0x5507, {0x99, 0x22, 0x2c, 0x0a, 0x7d, 0x34, 0x46, 0x4d}};
static const IID kIID_IUnknown_local =
    {0x00000000, 0x0000, 0x0000, {0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}};
static const IID kIID_IAgileObject =
    {0x94ea2b94, 0xe9cc, 0x49e0, {0xc0, 0xff, 0xee, 0x64, 0xca, 0x8f, 0x5b, 0x90}};

static int toast_debug(void) {
    static int on = -1;
    if (on < 0) {
        const char* v = getenv("STARLING_TOAST_DEBUG");
        on = (v != NULL && strcmp(v, "1") == 0) ? 1 : 0;
    }
    return on;
}

static HRESULT STDMETHODCALLTYPE changed_qi(ChangedHandler* This, REFIID riid,
                                            void** ppv) {
    if (ppv == NULL) return E_POINTER;
    /* IUnknown and the handler's own IID are the two that matter;
     * IAgileObject spares the event source a proxy for a callback that is
     * safe on any thread, which this one is -- it only calls a function
     * pointer. */
    if (IsEqualIID(riid, &kIID_IUnknown_local) ||
        IsEqualIID(riid, &kIID_IAgileObject) ||
        IsEqualIID(riid, &kIID_ChangedHandler)) {
        *ppv = This;
        return S_OK;
    }
    if (toast_debug()) {
        printf("[toast] QI refused {%08lx-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x}\n",
               (unsigned long)riid->Data1, riid->Data2, riid->Data3,
               riid->Data4[0], riid->Data4[1], riid->Data4[2], riid->Data4[3],
               riid->Data4[4], riid->Data4[5], riid->Data4[6], riid->Data4[7]);
        fflush(stdout);
    }
    *ppv = NULL;
    return E_NOINTERFACE;
}

/* Static lifetime, so the counts are a formality the ABI still asks for. */
static ULONG STDMETHODCALLTYPE changed_addref(ChangedHandler* This) {
    (void)This;
    return 2;
}

static ULONG STDMETHODCALLTYPE changed_release(ChangedHandler* This) {
    (void)This;
    return 1;
}

static HRESULT STDMETHODCALLTYPE changed_invoke(ChangedHandler* This,
                                                Listener* sender,
                                                ChangedArgs* args) {
    (void)This; (void)sender; (void)args;
    if (g_changed_cb != NULL) g_changed_cb(g_changed_user);
    return S_OK;
}

static const ChangedHandlerVtbl g_changed_vtbl = {
    changed_qi, changed_addref, changed_release, changed_invoke
};

static ChangedHandler g_changed_sink = { &g_changed_vtbl };

int32_t flwin32_notifications_on_changed(void (*cb)(void* user), void* user) {
    if (g_listener == NULL && !flwin32_notifications_init()) return 0;
    if (g_changed_cb != NULL) return 1;   /* one registration per process */
    g_changed_cb = cb;
    g_changed_user = user;
    HRESULT hr = g_listener->lpVtbl->add_NotificationChanged(
        g_listener, &g_changed_sink, &g_changed_token);
    if (toast_debug()) {
        printf("[toast] add_NotificationChanged hr=0x%08lx\n",
               (unsigned long)hr);
        fflush(stdout);
    }
    if (FAILED(hr)) {
        /* Denied access, or an OS that will not raise it for this process.
         * The caller keeps its poll; saying so honestly is the whole
         * contract. */
        g_changed_cb = NULL;
        g_changed_user = NULL;
        return 0;
    }
    return 1;
}
