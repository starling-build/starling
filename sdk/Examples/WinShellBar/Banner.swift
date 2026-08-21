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
// There is no arrival event wired yet: the listener's store is polled every
// two seconds off the UI thread, which is also why the process must exist
// before the first toast does (see flwin32_shell_ensure_banners). Wiring
// UserNotificationListener's NotificationChanged through the raw ABI would
// make it instant; a two-second-late banner is the honest MVP.

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
        Task.detached { [weak self] in
            while true {
                guard let self else { return }
                let items = Win32Notifications.read()
                await MainActor.run { self.apply(items) }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
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
