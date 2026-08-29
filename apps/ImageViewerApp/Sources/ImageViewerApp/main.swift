// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter

// MARK: - Themed root

/// Re-themes the viewer when the parent shell pushes an appearance change
/// over the DMA-BUF socket (same pattern as the other child apps).
class ThemedViewerRoot: StatefulWidget {
    override func createState() -> State<StatefulWidget> {
        return _ThemedViewerRootState()
    }
}

class _ThemedViewerRootState: State<StatefulWidget> {
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
            // The ACTIVE STYLE's colours -- see StarlingPalette. MacosApp
            // either way, because FluentApp's scaffold traps on mount as a
            // DMA-BUF child; only the palette moves.
            theme: StarlingPalette.current(dark: _dark).macosTheme(),
            home: ImageViewerApp(),
            title: "Image Viewer"
        )
    }
}

runApp(ThemedViewerRoot())
