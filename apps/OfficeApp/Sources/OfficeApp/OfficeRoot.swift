// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation

/// The Fluent-rooted app. Office is Fluent on every host by design (the
/// plan's "Fluent style, Office layout"); the shell's pushed theme, when we
/// run as a Starling child, only flips light/dark.
final class OfficeRoot: StatefulWidget {
    let initialPath: String?
    let initialKind: DocumentKind

    init(initialPath: String?, kind: DocumentKind = .document) {
        self.initialPath = initialPath
        self.initialKind = kind
        super.init()
    }

    override func createState() -> State<StatefulWidget> {
        return _OfficeRootState()
    }
}

private final class _OfficeRootState: State<StatefulWidget> {
    private var _dark = false
    /// Writer or Slides, and the file to start on. Switching kind builds a
    /// fresh shell (the generation keys it), so nothing of one kind's state
    /// leaks into the other.
    private var _kind = DocumentKind.document
    private var _path: String? = nil
    private var _generation = 0
    /// A site's folder (docs/plans/site.md): the window is its reader
    /// until "Close site" brings Writer back.
    private var _site: String? = nil
    private var _editSiteOnOpen = false
    private var _returnToHome = false

    override func initState() {
        super.initState()
        let root = widget as! OfficeRoot
        _kind = root.initialKind
        _path = root.initialPath
        #if os(Linux)
        if let dark = GpuDmaBufRenderer.lastPushedThemeIsDark { _dark = dark }
        GpuDmaBufRenderer.onThemeChanged = { [weak self] dark in
            guard let self, self._dark != dark else { return }
            self.setState { self._dark = dark }
        }
        #elseif os(macOS)
        // The system's appearance, and its changes. OFFICE_DARK=1 or 0
        // overrides it (for checking a look without flipping the system).
        if let forced = ProcessInfo.processInfo.environment["OFFICE_DARK"], !forced.isEmpty {
            _dark = forced == "1"
        } else {
            _dark = Self._systemDark()
            _appearanceObserver = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
            ) { [weak self] _ in
                guard let self, self.mounted else { return }
                let dark = Self._systemDark()
                if dark != self._dark { self.setState { self._dark = dark } }
            }
        }
        #endif
    }

    #if os(macOS)
    private var _appearanceObserver: NSObjectProtocol?

    private static func _systemDark() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    override func dispose() {
        if let o = _appearanceObserver { DistributedNotificationCenter.default().removeObserver(o) }
        super.dispose()
    }
    #endif

    override func build(_ context: any BuildContext) -> Widget {
        let onSwitch: (DocumentKind, String?) -> Void = { [weak self] kind, path in
            guard let self else { return }
            self.setState {
                self._kind = kind
                self._returnToHome = false
                self._path = path
                self._generation += 1
            }
        }
        let home: Widget
        #if !os(WASI)
        if let site = _site {
            let reader = SiteShell(store: LocalSiteStore(repo: site), route: SiteRecent().route(for: site), startEditing: _editSiteOnOpen, onLeave: { [weak self] in
                guard let self else { return }
                self.setState { self._site = nil; self._path = nil; self._returnToHome = true; self._generation += 1 }
            })
            return _Keyed(key: ValueKey(_generation), child: FluentApp(
                theme: WikiAppearance.theme, themeMode: .light,
                home: ButtonTheme(data: WikiAppearance.buttons, child: reader), title: "Starling Site"))
        }
        #endif
        let onOpenSite: (String, Bool) -> Void = { [weak self] dir, startEditing in
            guard let self else { return }
            self.setState { self._site = dir; self._editSiteOnOpen = startEditing; self._generation += 1 }
        }
        switch _kind {
        case .document: home = OfficeShell(initialPath: _path, startBlank: _generation > 0 && _path == nil, startHome: _returnToHome, onSwitch: onSwitch, onOpenSite: onOpenSite)
        case .presentation: home = SlidesShell(initialPath: _path, startBlank: _generation > 0 && _path == nil, onSwitch: onSwitch)
        case .workbook: home = SheetsShell(initialPath: _path, onSwitch: onSwitch)
        }
        // The key is on the app, not on `home`: FluentApp reads `home`
        // once, into its first route, so a new home under the same app is
        // never shown.
        return _Keyed(key: ValueKey(_generation), child: FluentApp(
            theme: OfficeAppearance.theme(.light),
            darkTheme: OfficeAppearance.theme(.dark),
            themeMode: _dark ? .dark : .light,
            home: home,
            title: _kind.appName
        ))
    }
}

/// A child under a key: a new key remounts the whole subtree.
private final class _Keyed: StatelessWidget {
    let child: Widget
    init(key: any Key, child: Widget) {
        self.child = child
        super.init(key: key)
    }
    override func build(_ context: any BuildContext) -> Widget { child }
}
