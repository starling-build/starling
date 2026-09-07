// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter

// MARK: - Root

#if os(Linux)
// The pushes the Settings pages mirror beyond the appearance and the style,
// which `StarlingApp` handles itself: the desktop context menu's layout
// switch flips the toggle, wallpaper pushes keep the picker's ring live,
// the screensaver timeout keeps its segmented control live, the connected
// displays follow a monitor being plugged in without the pane being
// reopened, and remote desktop reports the listener's REAL state — a
// failed start, a session-wide STARLING_RDP — not just its own click.
// Statics on the renderer, latched and replayed, so they can be set before
// the tree exists.
GpuDmaBufRenderer.onLayoutChanged = { tiling in
    settingsBlocShared?.add(.layoutApplied(tiling))
}
GpuDmaBufRenderer.onWallpaperChanged = { preset in
    settingsBlocShared?.add(.wallpaperApplied(preset))
}
GpuDmaBufRenderer.onScreensaverChanged = { seconds in
    settingsBlocShared?.add(.screensaverApplied(seconds))
}
GpuDmaBufRenderer.onDisplaysChanged = { displays in
    settingsBlocShared?.add(.displaysApplied(displays))
}
GpuDmaBufRenderer.onRdpChanged = { enabled in
    settingsBlocShared?.add(.rdpApplied(enabled))
}
#endif

runApp(StarlingApp(
    title: "Settings",
    // Keep the Appearance page's Dark Mode switch and the style picker in
    // step with what the desktop is actually showing.
    onThemeChanged: { dark in settingsBlocShared?.add(.themeApplied(dark)) },
    onStyleChanged: { style in settingsBlocShared?.add(.styleApplied(style.rawValue)) },
    onPrefChanged: { pref, value in settingsBlocShared?.add(.prefApplied(pref, value)) },
    home: SettingsApp()))
