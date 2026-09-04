// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import NotificationService
import Foundation

/// Manages the freedesktop notification daemon: an sd-bus service on a
/// background thread that claims org.freedesktop.Notifications on the
/// session's own bus (the portal pattern — same pinned address, same euid
/// drop, and the launchers mask the stock daemon's activation the same way).
///
/// The service thread speaks the protocol; the shell draws. Both callbacks
/// hop to the main queue before touching shell state — the C strings are
/// copied first, because they die when the callback returns. The reassemble
/// crash taught this lesson at the cost of a day: nothing mutates the
/// element tree from a non-UI thread, ever.
final class NotificationIntegration {

    private var service: OpaquePointer?  // NotificationService*

    init() {
        service = notification_service_create()
    }

    deinit {
        stop()
        if let s = service {
            notification_service_destroy(s)
        }
    }

    func start(busAddress: String? = nil, targetUid: UInt32 = 0) {
        guard let s = service else { return }

        notification_service_set_callbacks(s, { _, id, app, summary, body,
                                               urgency, timeoutMs, replaces in
            let appName = app.map { String(cString: $0) } ?? ""
            let sum = summary.map { String(cString: $0) } ?? ""
            let bod = body.map { String(cString: $0) } ?? ""
            let u = Int(urgency), t = Int(timeoutMs), r = replaces != 0
            let call: () -> Void = {
                _shellState?._notificationPosted(
                    id: id, appName: appName, summary: sum, body: bod,
                    urgency: u, timeoutMs: t, replaces: r)
            }
            onPlatformThread(call)
        }, { _, id in
            let call: () -> Void = {
                _shellState?._notificationCloseRequested(id)
            }
            onPlatformThread(call)
        }, nil)

        let r: Int32
        if let addr = busAddress {
            r = notification_service_start(s, addr, targetUid)
        } else {
            r = notification_service_start(s, nil, targetUid)
        }
        if r < 0 {
            FileHandle.standardError.write(
                Data("[NotificationIntegration] Failed to start: \(r)\n".utf8))
        }
    }

    func stop() {
        guard let s = service else { return }
        notification_service_stop(s)
    }

    /// Emit NotificationClosed(id, reason) back to the bus. Thread-safe.
    /// Reasons: 1 expired, 2 dismissed by the user, 3 CloseNotification.
    func emitClosed(id: UInt32, reason: UInt32) {
        guard let s = service else { return }
        notification_service_emit_closed(s, id, reason)
    }
}
