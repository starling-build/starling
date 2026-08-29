// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter

// MARK: - Themed root

/// Root that re-themes the app when the parent shell pushes an appearance
/// change over the DMA-BUF socket (DMABUF_CONTROL_SET_THEME), and keeps
/// the Appearance page's Dark Mode switch in sync.
class ThemedSettingsRoot: StatefulWidget {
    override func createState() -> State<StatefulWidget> {
        return _ThemedSettingsRootState()
    }
}

class _ThemedSettingsRootState: State<StatefulWidget> {
    private var _dark = true

    override func initState() {
        super.initState()
        #if os(Linux)
        // Seed from the appearance the shell pushed at connect, before this
        // tree existed (SettingsBloc seeds its Dark Mode switch the same way).
        if let dark = GpuDmaBufRenderer.lastPushedThemeIsDark {
            _dark = dark
        }
        GpuDmaBufRenderer.onThemeChanged = { [weak self] dark in
            guard let self, self._dark != dark else { return }
            self.setState { self._dark = dark }
            settingsBlocShared?.add(.themeApplied(dark))
        }
        // Layout switches from the desktop context menu flip the Settings
        // toggle live.
        GpuDmaBufRenderer.onLayoutChanged = { tiling in
            settingsBlocShared?.add(.layoutApplied(tiling))
        }
        // Wallpaper pushes keep the picker's selection ring live.
        // A style switch repaints this app as well as the shell's chrome:
        // the palette is a function of the pushed style, so the tree has to
        // be rebuilt for it, not merely told about it.
        GpuDmaBufRenderer.onStyleChanged = { [weak self] style in
            settingsBlocShared?.add(.styleApplied(style))
            self?.setState {}
        }
        GpuDmaBufRenderer.onWallpaperChanged = { preset in
            settingsBlocShared?.add(.wallpaperApplied(preset))
        }
        // Screensaver timeout pushes keep the segmented control live.
        GpuDmaBufRenderer.onScreensaverChanged = { seconds in
            settingsBlocShared?.add(.screensaverApplied(seconds))
        }
        // The connected displays and which one is primary. Pushed at connect
        // and again on any change, so the Displays pane follows a monitor
        // being plugged in without the user reopening it.
        GpuDmaBufRenderer.onDisplaysChanged = { displays in
            settingsBlocShared?.add(.displaysApplied(displays))
        }
        // Remote desktop: the shell reports the listener's real state, so the
        // Sharing switch follows a failed start and a session-wide
        // STARLING_RDP as well as its own click.
        GpuDmaBufRenderer.onRdpChanged = { enabled in
            settingsBlocShared?.add(.rdpApplied(enabled))
        }
        #endif
    }

    override func build(_ context: any BuildContext) -> Widget {
        // MacosApp whichever style is active -- FluentApp's scaffold traps
        // on mount as a DMA-BUF child -- but carrying the ACTIVE STYLE's
        // colours, so the Macos* controls inside come up in WinUI's palette
        // when the desktop is in the Windows style.
        return MacosApp(
            theme: StarlingPalette.current(dark: _dark).macosTheme(),
            home: SettingsApp()
        )
    }
}

runApp(ThemedSettingsRoot())
