// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation

// Check for --picker mode (launched by portal FileChooser service)
let isPickerMode = CommandLine.arguments.contains("--picker")

// MARK: - Themed root

/// Rebuilds MacosApp with the pushed appearance (shell sends
/// DMABUF_CONTROL_SET_THEME at connect and on every switch) and flips the
/// FinderColors palette. MacosApp (not FluentApp): FluentApp's scaffold
/// traps on mount as a DMA-BUF child (RenderObjectElements insert cast);
/// MacosApp is proven as a child for Files/Settings.
class ThemedFilesRoot: StatefulWidget {
    let picker: Bool

    init(picker: Bool) {
        self.picker = picker
        super.init()
    }

    override func createState() -> State<StatefulWidget> {
        return _ThemedFilesRootState()
    }
}

class _ThemedFilesRootState: State<StatefulWidget> {
    private var _dark = true
    private var _root: ThemedFilesRoot { widget as! ThemedFilesRoot }

    override func initState() {
        super.initState()
        #if os(Linux)
        // The shell pushed the desktop appearance when we connected, before
        // this tree existed. Seed from it so the first frame is already right.
        if let dark = GpuDmaBufRenderer.lastPushedThemeIsDark {
            _dark = dark
            FinderColors.dark = dark
        }
        // A style switch repaints this app too: the palette is a function of
        // the pushed style, so the tree is rebuilt for it. The lazy file
        // list needs the same refresh poke as an appearance change -- its
        // sliver children do not rebuild on an ancestor rebuild.
        GpuDmaBufRenderer.onStyleChanged = { [weak self] _ in
            self?.setState {}
            filesBlocShared?.add(.refresh)
        }
        GpuDmaBufRenderer.onThemeChanged = { [weak self] dark in
            guard let self, self._dark != dark else { return }
            FinderColors.dark = dark
            self.setState { self._dark = dark }
            // The lazy file list's sliver children don't rebuild on an
            // ancestor rebuild — a refresh emission makes the rows re-read
            // the palette.
            filesBlocShared?.add(.refresh)
        }
        #endif
    }

    override func build(_ context: any BuildContext) -> Widget {
        // MacosApp in both styles (FluentApp's scaffold traps on mount as a
        // DMA-BUF child), carrying the active style's colours.
        return MacosApp(
            theme: StarlingPalette.current(dark: _dark).macosTheme(),
            home: _root.picker ? FileExplorerPickerApp() : FileExplorerApp()
        )
    }
}

runApp(ThemedFilesRoot(picker: isPickerMode))
