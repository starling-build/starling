// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Toast banners — the transient card Windows pops bottom-right when a toast
// arrives.
//
// The native banner is drawn by explorer's family: ShellExperienceHost stays
// alive when explorer dies, but goes MUTE — measured 2026-08-21 in the VM,
// `Show()` succeeds, the store fills, nothing pops. So with explorer gone
// this surface is the only visible sign a notification happened. It runs as
// its own parked overlay process (`--banners`), the launcher's bargain, with
// two differences: it is PASSIVE (showing must not steal focus or the next
// Escape from whatever the user is typing in), and nothing the user does
// boots it — it shows itself when the store grows.
//
// It hears about a toast rather than looking for one: the controller
// subscribes to UserNotificationListener's NotificationChanged (wired through
// the raw ABI in flwin32_notifications.c) and reads the store when the event
// says something moved. It used to poll that store every two seconds, which
// was both a banner up to two seconds late AND ~0.25% of a core spent, for the
// life of the session, in a process whose entire job is to wait — the largest
// idle cost left in the shell once the timer floors were gone. The process
// still has to exist before the first toast does (see
// flwin32_shell_ensure_banners): a subscriber that is not running hears
// nothing either.

#if os(Windows)
import Flutter
import FlutterSwiftBridge
import FlutterWin32
import CupertinoIcons
import Foundation

let kBannerWidth = 360.0
let kBannerHeight = 102.0
let kBannerGap = 12.0

/// Watches the store and owns the banner's lifecycle. Lives OUTSIDE the
/// widget tree: a parked overlay's tree does not mount until first shown,
/// and the whole point of this surface is deciding when that is.
final class BannerController {
    static let shared = BannerController()

    private(set) var current: Win32Toast?
    private(set) var iconTexture: Int?
    /// The tree's ear, hooked in initState. nil until the first show mounts
    /// the tree — the controller's state is read fresh at build either way.
    var onChange: (() -> Void)?

    private var seen: Set<UInt32> = []
    private var seeded = false
    /// Bumped on every show and dismiss, so a stale 6-second timer from a
    /// banner that was already replaced cannot hide its successor.
    private var generation = 0
    private var iconApp: String?

    /// Called from main.swift before runStarlingApp.
    func start() {
        // The event, if the OS will give it to us. It fires for removals as
        // well as arrivals, which costs nothing: `apply` compares against what
        // it has already seen.
        let subscribed = Win32Notifications.onChanged { [weak self] in
            self?.readStore()
        }
        // One read either way: it seeds `seen` with the login backlog, which
        // is the notification centre's business rather than a banner storm.
        readStore()
        // Windows refuses that registration to a process without package
        // identity — measured on the box: ERROR_NOT_FOUND — so in practice
        // the loop below is the mechanism, and the only question is how often
        // it asks. Asking is not cheap and cannot be made cheap: every ask is
        // a cross-process RPC to the notification service, ~6 ms of CPU
        // whether it fetches five toasts or just their ids (an ids-only
        // variant was written and measured at exactly the same cost; see
        // flwin32_notifications.c).
        //
        // So it asks at the rate somebody can actually be surprised at. A
        // banner is an alert: it is worth two seconds of latency while a
        // person is at the machine, and worth nothing at all while nobody
        // has touched it for a minute — the toast is still in the centre
        // when they come back, which is where they would look anyway. The
        // presence check itself is microseconds (GetLastInputInfo).
        //
        // If the event ever IS granted — a packaged Starling would get it —
        // the same loop stays as a slow backstop, because the listener is
        // somebody else's code and a banner that never appears is worse than
        // a wakeup every half minute.
        scheduleNextPoll(subscribed: subscribed)
    }

    /// The poll queue exists because a store read BLOCKS for ~40 ms (it is an
    /// RPC to the notification service, polled to completion), and because of
    /// what it replaced: `Task.detached { while true { try? await
    /// Task.sleep(…) } }`. That loop cost **~46 context switches a second** in
    /// a process that was otherwise asleep — measured against the parked Run
    /// dialog next to it, which wakes zero times — so Swift concurrency's
    /// sleep is not a free way to wait on this platform. A libdispatch timer
    /// is: the kernel holds the deadline and nothing runs until it fires.
    private let pollQueue = DispatchQueue(label: "starling.banner.poll")

    /// One-shot, rescheduled after each read, so the interval can follow
    /// presence without a timer to reschedule.
    private func scheduleNextPoll(subscribed: Bool) {
        let away = Win32SystemInfo.idleMillis() > 60_000
        let seconds = subscribed ? 30 : (away ? 15 : 2)
        pollQueue.asyncAfter(deadline: .now() + .seconds(seconds)) { [weak self] in
            guard let self else { return }
            let items = Win32Notifications.read()
            DispatchQueue.main.async { self.apply(items) }
            self.scheduleNextPoll(subscribed: subscribed)
        }
    }

    /// Read the store off the UI thread and apply what came back on it.
    private func readStore() {
        pollQueue.async { [weak self] in
            let items = Win32Notifications.read()
            DispatchQueue.main.async { self?.apply(items) }
        }
    }

    private func apply(_ items: [Win32Toast]) {
        // The first read seeds silently: the login backlog is the centre's
        // business, not a banner storm.
        if !seeded {
            seeded = true
            seen.formUnion(items.map(\.id))
            return
        }
        let fresh = items.filter { !seen.contains($0.id) }
        guard !fresh.isEmpty else { return }
        seen.formUnion(fresh.map(\.id))
        guard shouldShow else { return }
        // Newest first is read()'s order; several at once show the newest.
        show(fresh[0])
    }

    /// Banners pop only where the native ones cannot: explorer absent, or
    /// STARLING_BANNERS=1 forcing it for a test (0 kills them outright).
    /// An open notification centre suppresses them, native behavior.
    private var shouldShow: Bool {
        let env = ProcessInfo.processInfo.environment["STARLING_BANNERS"]
        if env == "0" { return false }
        if Win32Shell.surfaceVisible("Starling Notifications") { return false }
        if env == "1" { return true }
        return !Win32Shell.explorerPresent
    }

    private func show(_ toast: Win32Toast) {
        current = toast
        generation += 1
        let g = generation
        if iconApp != toast.app {
            iconTexture = nil
            iconApp = toast.app
            fetchIcon(toast)
        }
        onChange?()
        Win32WindowedHost.host?.setVisible(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
            guard let self, self.generation == g else { return }
            self.dismiss()
        }
    }

    private func fetchIcon(_ toast: Win32Toast) {
        let id = toast.id
        let app = toast.app
        Task.detached { [weak self] in
            guard let bitmap = Win32Notifications.appIcon(toastId: id, size: 32) else { return }
            await MainActor.run {
                guard let self, self.iconApp == app else { bitmap.discard(); return }
                if let tex = Win32WindowedHost.host?.registerPixels(bitmap) {
                    self.iconTexture = tex
                    self.onChange?()
                }
            }
        }
    }

    func dismiss() {
        generation += 1
        Win32WindowedHost.host?.setVisible(false)
    }

    /// A click on the card body — what the native banner does is activate
    /// the app; ours opens the centre, where the toast now lives.
    func openCentre() {
        dismiss()
        Win32Shell.toggleOverlay(channel: "notifications")
    }
}

final class StarlingBanner: StatefulWidget {
    override func createState() -> State<StatefulWidget> { StarlingBannerState() }
}

final class StarlingBannerState: State<StatefulWidget> {
    private var closeHovered = false

    override func initState() {
        super.initState()
        BannerController.shared.onChange = { [weak self] in
            self?.setState {}
        }
        // The parked-black bargain (the launcher's didToggle): the host shows
        // the window; the tree marks itself dirty so the frame that show
        // produces is fresh rather than the parked one.
        Win32WindowedHost.host?.onToggle { [weak self] in
            guard let self else { return }
            if Win32WindowedHost.host?.isVisible == true {
                self.setState {}
            }
        }
    }

    private var closeRect: (x: Double, y: Double, w: Double, h: Double) {
        (kBannerWidth - 40, 8, 28, 28)
    }

    private func inClose(_ x: Double, _ y: Double) -> Bool {
        let r = closeRect
        return x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h
    }

    override func build(_ context: any BuildContext) -> Widget {
        let p = WinPalette.of(dark: Win32Control.isDarkMode)
        let toast = BannerController.shared.current
        return Directionality(
            textDirection: .ltr,
            child: Listener(
                onPointerDown: { [weak self] event in
                    guard let self else { return }
                    if self.inClose(event.position.dx, event.position.dy) {
                        BannerController.shared.dismiss()
                    } else {
                        BannerController.shared.openCentre()
                    }
                },
                onPointerHover: { [weak self] event in
                    guard let self else { return }
                    let over = self.inClose(event.position.dx, event.position.dy)
                    if over != self.closeHovered {
                        self.setState { self.closeHovered = over }
                    }
                },
                behavior: .opaque,
                // The SizedBox gives the Stack its extent: with only
                // Positioned children a Stack sizes to nothing, and a
                // zero-sized tree paints a black window with no error.
                child: SizedBox(width: kBannerWidth, height: kBannerHeight) {
                    ClipRRect(borderRadius: BorderRadius.circular(8)) {
                        ColoredBox(color: p.stroke) {
                            Padding(padding: EdgeInsets(left: 1, top: 1, right: 1, bottom: 1)) {
                                ClipRRect(borderRadius: BorderRadius.circular(7)) {
                                    ColoredBox(color: p.panel) {
                                        Stack(alignment: Alignment.topLeft) {
                                            // The native anatomy: logo + app
                                            // name up top, dismiss at the
                                            // corner, then title and body.
                                            Positioned(left: 16, top: 13, width: kBannerWidth - 72, height: 18) {
                                                Row(crossAxisAlignment: .center, spacing: 8) {
                                                    if let tex = BannerController.shared.iconTexture {
                                                        SizedBox(width: 16, height: 16) {
                                                            TextureWidget(textureId: tex)
                                                        }
                                                    }
                                                    Text(toast?.app ?? "",
                                                         style: TextStyle(color: p.subInk, fontSize: 12),
                                                         overflow: .ellipsis, maxLines: 1)
                                                }
                                            }
                                            Positioned(left: closeRect.x, top: closeRect.y,
                                                       width: closeRect.w, height: closeRect.h) {
                                                ClipRRect(borderRadius: BorderRadius.circular(4)) {
                                                    ColoredBox(color: closeHovered ? p.rowHover : Color(0x00000000)) {
                                                        Center {
                                                            MacosIcon(icon: FluentIcons.close,
                                                                      color: p.subInk, size: 12)
                                                        }
                                                    }
                                                }
                                            }
                                            Positioned(left: 16, top: 40, width: kBannerWidth - 32, height: 18) {
                                                Text(toast?.title ?? "",
                                                     style: TextStyle(color: p.ink, fontSize: 13,
                                                                      fontWeight: .w600),
                                                     overflow: .ellipsis, maxLines: 1)
                                            }
                                            Positioned(left: 16, top: 62, width: kBannerWidth - 32, height: 32) {
                                                Text(toast?.body ?? "",
                                                     style: TextStyle(color: p.subInk, fontSize: 12),
                                                     overflow: .ellipsis, maxLines: 2)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            )
        )
    }
}

#endif
