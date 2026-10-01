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
        #endif
    }

    override func build(_ context: any BuildContext) -> Widget {
        let onSwitch: (DocumentKind, String?) -> Void = { [weak self] kind, path in
            guard let self else { return }
            self.setState {
                self._kind = kind
                self._path = path
                self._generation += 1
            }
        }
        let home: Widget = _kind == .document
            ? OfficeShell(initialPath: _path, startBlank: _generation > 0 && _path == nil, onSwitch: onSwitch)
            : SlidesShell(initialPath: _path, onSwitch: onSwitch)
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
