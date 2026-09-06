// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Toasts: the banner a notification raises when it arrives. On Windows it
// slides in at the bottom right above the taskbar, stays for the post's
// expire_timeout (five seconds when the app left it to the desktop), and
// slides away; a click opens the notification centre with the post in it,
// the X puts just the banner away. The same banner serves the macOS style
// at the top right under the menu bar — new chrome lands in both styles.
//
// Do-not-disturb and an open notification centre both keep a post from
// toasting: it still collects, which is the point of the centre.

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

enum ToastAnchor {
    case topRight, bottomRight
}

enum ToastMetrics {
    /// Windows' toast is 364 wide; three at most stack on screen.
    static let width: Double = 364
    static let margin: Double = 12
    static let gap: Double = FluentSpacing.s
    static let visible = 3
    /// The freedesktop default when an app passes -1.
    static let defaultTimeout: Duration = .seconds(5)
}

extension _DesktopShellState {

    /// A post just arrived (or the shell posted): raise its banner unless
    /// the user asked for quiet or is looking at the centre already.
    func _showToast(id: UInt32, timeoutMs: Int) {
        guard !_doNotDisturb,
              activeStatusBarPopup.map(fluentIsNotificationCentre) != true else { return }
        if !_toasts.contains(id) { _toasts.append(id) }
        let delay = _toastTimers[id] ?? FluentDelay()
        _toastTimers[id] = delay
        // 0 means "until dismissed", the spec's word; anything else expires.
        if timeoutMs != 0 {
            let duration: Duration = timeoutMs > 0 ? .milliseconds(timeoutMs) : ToastMetrics.defaultTimeout
            delay.schedule(after: duration) { [weak self] in self?._hideToast(id) }
        } else {
            delay.cancel()
        }
    }

    /// The banner goes; the post stays in the centre.
    func _hideToast(_ id: UInt32) {
        _toastTimers[id]?.cancel()
        _toastTimers[id] = nil
        guard _toasts.contains(id) else { return }
        setState { _toasts.removeAll { $0 == id } }
    }

    func fluentToasts(anchor: ToastAnchor) -> Widget? {
        let showing = _toasts.suffix(ToastMetrics.visible)
        let notes = showing.compactMap { id in _notifications.first { $0.id == id } }
        guard !notes.isEmpty else { return nil }
        let column = Column(
            mainAxisSize: .min, crossAxisAlignment: .end, spacing: ToastMetrics.gap,
            children: notes.map { note in
                FluentEntrance(child: _toastCard(note), slideFrom: Offset(40, 0))
            })
        switch anchor {
        case .bottomRight:
            return Positioned(
                right: ToastMetrics.margin,
                bottom: DesktopTheme.kDockHeight + ToastMetrics.margin,
                child: column)
        case .topRight:
            return Positioned(
                top: shellMetrics.topInset + ToastMetrics.margin,
                right: ToastMetrics.margin,
                child: column)
        }
    }

    private func _toastCard(_ note: ShellNotification) -> Widget {
        let content: Widget = Padding(
            padding: EdgeInsets(left: FluentSpacing.l, top: FluentSpacing.m,
                                right: FluentSpacing.s, bottom: FluentSpacing.l),
            child: Column(crossAxisAlignment: .stretch, spacing: 2) {
                Row(crossAxisAlignment: .center) {
                    Expanded {
                        Text(note.appName.isEmpty ? "Notification" : note.appName,
                             style: fluentType.styled({ $0.caption }, shellTheme.fgSecondary),
                             overflow: .ellipsis, maxLines: 1)
                    }
                    SizedBox(
                        width: 24, height: 24,
                        child: HoverButton(
                            builder: { [self] _, states in
                                let hot = states.isHovered || states.isPressed
                                return DecoratedBox(
                                    decoration: BoxDecoration(
                                        color: hot ? shellTheme.controlHover : Color(0x00000000),
                                        borderRadius: FluentCorners.controlRadius),
                                    child: Center(child: Icon(FluentSystemIcons.close, size: 12,
                                                              color: shellTheme.fgPrimary)))
                            },
                            onPressed: { [self] in _hideToast(note.id) }))
                }
                Text(note.summary,
                     style: fluentType.styled({ $0.bodyStrong }, shellTheme.fgPrimary, strong: true),
                     overflow: .ellipsis, maxLines: 2)
                if !note.body.isEmpty {
                    Text(note.body, style: fluentType.styled({ $0.body }, shellTheme.fgSecondary),
                         overflow: .ellipsis, maxLines: 3)
                }
            })
        // The card as a whole opens the centre on the post; the X above
        // gets its press first, being the inner listener.
        return Listener(
            onPointerDown: { [self] event in
                guard event.buttons & kPrimaryButton != 0 else { return }
                _hideToast(note.id)
                setState {
                    activeStatusBarPopup = .notifications
                    _notificationsUnseen = false
                    _calendarMonthOffset = 0
                }
            },
            behavior: .translucent,
            child: fluentFlyoutFrame(width: ToastMetrics.width, child: content))
    }
}
