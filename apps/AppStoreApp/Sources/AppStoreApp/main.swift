// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter

// MARK: - Themed root

/// Re-themes the store when the parent shell pushes an appearance change
/// over the DMA-BUF socket (same pattern as SettingsApp / CalculatorApp).
class ThemedStoreRoot: StatefulWidget {
    override func createState() -> State<StatefulWidget> {
        return _ThemedStoreRootState()
    }
}

class _ThemedStoreRootState: State<StatefulWidget> {
    private var _dark = true

    override func initState() {
        super.initState()
        #if os(Linux)
        if let dark = GpuDmaBufRenderer.lastPushedThemeIsDark {
            _dark = dark
        }
        GpuDmaBufRenderer.onThemeChanged = { [weak self] dark in
            guard let self, self._dark != dark else { return }
            self.setState { self._dark = dark }
        }
        #endif
    }

    override func build(_ context: any BuildContext) -> Widget {
        return MacosApp(
                // The ACTIVE STYLE's colours: `StarlingPalette` answers
                // with the macOS values this app shipped with, or WinUI's own
                // tokens when the desktop is in the Windows style. MacosApp
                // either way -- FluentApp's scaffold traps on mount as a
                // DMA-BUF child -- so the widget family stays put and only
                // the palette moves.
            theme: StarlingPalette.current(dark: _dark).macosTheme(),
            home: AppStoreApp()
        )
    }
}

runApp(ThemedStoreRoot())
