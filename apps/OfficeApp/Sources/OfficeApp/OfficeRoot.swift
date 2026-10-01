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

    init(initialPath: String?) {
        self.initialPath = initialPath
        super.init()
    }

    override func createState() -> State<StatefulWidget> {
        return _OfficeRootState()
    }
}

private final class _OfficeRootState: State<StatefulWidget> {
    private var _dark = false

    override func initState() {
        super.initState()
        #if os(Linux)
        if let dark = GpuDmaBufRenderer.lastPushedThemeIsDark { _dark = dark }
        GpuDmaBufRenderer.onThemeChanged = { [weak self] dark in
            guard let self, self._dark != dark else { return }
            self.setState { self._dark = dark }
        }
        #endif
    }

    override func build(_ context: any BuildContext) -> Widget {
        let root = widget as! OfficeRoot
        return FluentApp(
            theme: OfficeAppearance.theme(.light),
            darkTheme: OfficeAppearance.theme(.dark),
            themeMode: _dark ? .dark : .light,
            home: OfficeShell(initialPath: root.initialPath),
            title: "Writer"
        )
    }
}
