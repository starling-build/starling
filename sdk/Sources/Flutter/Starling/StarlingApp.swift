// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The root every first-party Starling app hangs its tree from.
//
// An app used to carry a "themed root" of its own — a StatefulWidget that
// seeded light-or-dark from what the shell pushed at connect, re-ran its
// build on a push, and wrapped its page in `MacosApp` with the palette of
// the moment. Ten apps, ten copies, each a little different, and each with
// the same note explaining why it was `MacosApp` whichever style the desktop
// was in. This is the one copy.
//
// WHAT IT INSTALLS. Both control families' themes, over one `Navigator`:
//
//     Directionality
//       AnimatedFluentTheme   ← the Fluent controls read this
//         AnimatedMacosTheme  ← the Macos* controls read this
//           Navigator(home)
//
// which is exactly the union of what `FluentApp` and `MacosApp` build. The
// controls are the Fluent set (docs/plans/fluent-first.md, Phase 6); the
// macOS style does not swap them for another widget tree, it RECOLOURS them
// through `StarlingPalette` — a macOS-blue accent, macOS greys, the system
// face instead of Selawik. That bargain is what keeps a style switch from
// being a second port of every app.
//
// WHY THE TREE DOES NOT CHANGE SHAPE on a style push. A root that built
// `FluentApp` in one style and `MacosApp` in the other would change the
// widget TYPE above `home` on every switch, and a type change remounts the
// subtree: the editor's buffer, the file list's directory, every scroll
// position — gone, for a colour change. Here the shapes are identical in
// both styles and only the theme data moves, so a switch is a rebuild the
// app's state lives through. Lazy lists whose rows cache colours still need
// their own refresh poke; `onStyleChanged` is where an app sends it.
//
// FONTS. The palette's face (Selawik in the Fluent style) is loaded here
// before the first frame that needs it; icon fonts load themselves from the
// `Icon` widget. An app registers nothing.

import FlutterSwiftBridge

// MARK: - StarlingApp

public final class StarlingApp: StatefulWidget {
    /// The app's page.
    public let home: Widget

    /// A short name for the app. Not drawn anywhere; the window's title is
    /// the shell's business.
    public let title: String

    /// Called after the tree has been rebuilt for a pushed appearance
    /// (true = dark). For state outside the tree that mirrors it — a bloc's
    /// Dark Mode switch, a colour table a lazy list reads.
    public let onThemeChanged: ((Bool) -> Void)?

    /// Called after the tree has been rebuilt for a pushed style.
    public let onStyleChanged: ((StarlingStyleId) -> Void)?

    /// Called after the tree has been rebuilt for a pushed preference
    /// (`StarlingPref`, its value). The root already honours transparency
    /// and animations itself; this is for a page that shows the switch.
    public let onPrefChanged: ((StarlingPref, Int) -> Void)?

    public init(
        key: (any Key)? = nil,
        title: String = "",
        onThemeChanged: ((Bool) -> Void)? = nil,
        onStyleChanged: ((StarlingStyleId) -> Void)? = nil,
        onPrefChanged: ((StarlingPref, Int) -> Void)? = nil,
        home: Widget
    ) {
        self.home = home
        self.title = title
        self.onThemeChanged = onThemeChanged
        self.onStyleChanged = onStyleChanged
        self.onPrefChanged = onPrefChanged
        super.init(key: key)
    }

    public override func createState() -> State<StatefulWidget> {
        _StarlingAppState()
    }
}

// MARK: - _StarlingAppState

final class _StarlingAppState: State<StatefulWidget> {
    /// Dark until the shell says otherwise — the desktop's default
    /// appearance, and what a standalone run of an app shows.
    private var _dark = true

    private var app: StarlingApp { widget as! StarlingApp }

    /// The appearance this root is drawing in. Read by tests.
    var isDark: Bool { _dark }

    override func initState() {
        super.initState()
        #if os(Linux)
        // The shell pushed the appearance and the style when we connected,
        // before this tree existed; seed from them so the first frame is
        // already right. The style needs no field of its own —
        // `StarlingStyleId.current` reads the latch.
        if let dark = GpuDmaBufRenderer.lastPushedThemeIsDark {
            _dark = dark
        }
        // Tell the app now, synchronously, what was latched: the renderer
        // replays a push to a freshly registered callback, but on the main
        // queue, i.e. AFTER the first frame — and a colour table the app
        // keeps outside the tree (Files' FinderColors) would paint that
        // frame in the wrong appearance. The replay then repeats the same
        // value, which every listener has to be able to take twice.
        app.onThemeChanged?(_dark)
        app.onStyleChanged?(StarlingStyleId.current)
        for (id, value) in GpuDmaBufRenderer.lastPushedPrefs {
            if let pref = StarlingPref(rawValue: id) { app.onPrefChanged?(pref, value) }
        }
        GpuDmaBufRenderer.onThemeChanged = { [weak self] dark in
            guard let self else { return }
            if self._dark != dark {
                self.setState { self._dark = dark }
            }
            self.app.onThemeChanged?(dark)
        }
        GpuDmaBufRenderer.onStyleChanged = { [weak self] _ in
            guard let self else { return }
            // The palette is a function of the pushed style, so the tree
            // is rebuilt for it, not merely told about it.
            self.setState {}
            self.app.onStyleChanged?(StarlingStyleId.current)
        }
        GpuDmaBufRenderer.onPrefChanged = { [weak self] id, value in
            guard let self else { return }
            // Transparency and animations sit above the tree as
            // FluentMaterialSettings; a rebuild is what applies them.
            self.setState {}
            if let pref = StarlingPref(rawValue: id) { self.app.onPrefChanged?(pref, value) }
        }
        #endif
    }

    override func build(_ context: any BuildContext) -> Widget {
        let palette = StarlingPalette.current(dark: _dark)
        StarlingFonts.ensure(palette.fontFamily)
        StarlingFonts.ensure(palette.fontFamilyStrong)
        let fluent = palette.fluentTheme()
        // The user's transparency and animation switches, as the SDK's
        // materials and entrances read them: acrylic falls to its solid
        // fallback and a FluentEntrance lands without moving when off.
        return FluentMaterialSettings(
            transparencyEffects: StarlingPrefs.isOn(.transparency),
            animationEffects: StarlingPrefs.isOn(.animations),
            child: Directionality(
                textDirection: .ltr,
                child: AnimatedFluentTheme(
                    data: fluent,
                    child: AnimatedMacosTheme(
                        data: palette.macosTheme(),
                        // One Navigator (with its own Overlay) so showDialog /
                        // Navigator.push work from either control family.
                        child: Navigator(home: app.home),
                        curve: Curves.easeInOut
                    ),
                    curve: fluent.animationCurve
                )
            )
        )
    }
}
