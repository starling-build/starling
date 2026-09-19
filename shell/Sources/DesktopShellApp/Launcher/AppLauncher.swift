// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge

// MARK: - LauncherApp

/// One entry in the app launcher grid.
struct LauncherApp {
    let appId: String
    let title: String
    let iconType: IconType
    let bgColor: Color
    /// Icon read from the app's own install on this host (the path comes from
    /// the app registry, resolved at install time) —
    /// third-party marks are never shipped. Nil for first-party apps, and for
    /// third-party ones that are installed without a resolvable raster icon;
    /// both fall back to `iconType`'s painted glyph.
    let textureId: Int64?

    init(appId: String, title: String, iconType: IconType, bgColor: Color,
         textureId: Int64? = nil) {
        self.appId = appId
        self.title = title
        self.iconType = iconType
        self.bgColor = bgColor
        self.textureId = textureId
    }
}

// MARK: - AppLauncher

/// Full-screen macOS-style app launcher (Launchpad): a blurred, dimmed
/// backdrop over the desktop with a centered grid of large app icons + labels.
/// Tap an app to launch it (and close the launcher); tap empty space to
/// dismiss. Opened from the dock's grid ("launcher") icon.
class AppLauncher: StatelessWidget {

    let apps: [LauncherApp]
    let query: String
    let city: Bool
    /// Blink phase of the search caret, driven by the shell (see
    /// `_restartLauncherCaret`) — the widget is stateless, so the phase has to
    /// come from above.
    let caretResetToken: Int
    let onLaunch: (String) -> Void
    let onDismiss: () -> Void

    init(
        apps: [LauncherApp],
        query: String = "",
        city: Bool = false,
        caretResetToken: Int = 0,
        onLaunch: @escaping (String) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.apps = apps
        self.query = query
        self.city = city
        self.caretResetToken = caretResetToken
        self.onLaunch = onLaunch
        self.onDismiss = onDismiss
    }

    private static let kIconSize: Double = 104
    private static let kTileWidth: Double = 150
    private static let kTileHeight: Double = 152

    /// One app tile: large rounded icon (bg colour + glyph) with a label under
    /// it. The whole tile is tappable and launches the app.
    private func tile(_ app: LauncherApp) -> Widget {
        if city { return cityTile(app) }
        let radius = AppLauncher.kIconSize * 0.225
        let glyph = AppLauncher.kIconSize * 0.52

        // The app's own icon, read from its install on this host (the path
        // comes from the app registry)
        // — third-party marks are never shipped. Without one, the painted
        // glyph for `iconType` stands in.
        let iconGlyph: Widget
        if let texId = app.textureId {
            iconGlyph = SizedBox(
                width: glyph * 1.6, height: glyph * 1.6,
                child: TextureWidget(textureId: Int(texId), filterQuality: .medium))
        } else {
            iconGlyph = SizedBox(
                width: glyph, height: glyph,
                child: CustomPaint(
                    painter: IconPainter(app.iconType, color: Color(0xFFFFFFFF))))
        }

        let iconTile: Widget = DecoratedBox(
            decoration: BoxDecoration(
                borderRadius: BorderRadius.all(Radius(circular: radius)),
                boxShadow: [
                    BoxShadow(
                        color: Color(0x59000000),
                        offset: Offset(0, 8),
                        blurRadius: 18
                    ),
                ]
            ),
            child: ClipRRect(
                borderRadius: BorderRadius.all(Radius(circular: radius)),
                child: DecoratedBox(
                    decoration: BoxDecoration(gradient: ShellPalette.tileGradient(app.bgColor)),
                    child: Center(child: iconGlyph)
                )
            )
        )

        return GestureDetector(
            onTap: { [self] in onLaunch(app.appId) },
            child: SizedBox(
                width: AppLauncher.kTileWidth,
                height: AppLauncher.kTileHeight,
                child: Column(
                    mainAxisAlignment: .center,
                    mainAxisSize: .min,
                    children: [
                        SizedBox(
                            width: AppLauncher.kIconSize,
                            height: AppLauncher.kIconSize,
                            child: iconTile
                        ),
                        SizedBox(height: 12),
                        Text(
                            app.title,
                            style: TextStyle(
                                color: Color(0xFFFFFFFF),
                                fontSize: 13
                            ),
                            textAlign: .center,
                            overflow: .ellipsis,
                            maxLines: 1
                        ),
                    ]
                )
            )
        )
    }

    /// Centered search pill showing the live query (typed via the shell's key
    /// handler — see routeKey), with a blinking caret.
    ///
    /// The caret shows from the moment the Launchpad opens, including on an
    /// empty query. That is not cosmetic. This field is always focused while
    /// the Launchpad is open — the key router hands it every keystroke — but it
    /// is not a text input and has no hit target, so clicking it does nothing
    /// and nothing ever *said* it was focused. It previously drew a caret only
    /// once you had typed, so at the one moment a user looks for focus (just
    /// opened, pill empty, click it) the pill was indistinguishable from a
    /// label. It read as an input that ignores the keyboard, which is what was
    /// reported against 0.2.1. The caret is the whole affordance; keep it
    /// visible whenever the launcher is open.
    private func searchBar() -> Widget {
        let empty = query.isEmpty
        // Blink by fading the glyph, never by swapping it out. The pill is
        // centered and hugs its content, so anything that changes the caret's
        // advance width — dropping it, or substituting a space, which is not
        // the same width as "|" — shifts the label a few pixels twice a second.
        // Same glyph, same metrics, alpha 0: the layout cannot move.
        // Blinks itself — see `ShellCaret`. Driving this from shell state
        // rebuilt the entire desktop twice a second for one glyph.
        let caret: Widget = ShellCaret(color: city ? Color(0xFF574028) : Color(0xFFFFFFFF), fontSize: 16,
                                       resetToken: caretResetToken)
        let label = Text(
            empty ? "Search" : query,
            style: TextStyle(
                color: city ? Color(0xFF625747) : (empty ? Color(0x80FFFFFF) : Color(0xFFFFFFFF)),
                fontSize: 16
            ),
            maxLines: 1
        )
        return DecoratedBox(
            decoration: BoxDecoration(
                color: city ? Color(0xFFF8F2E4) : Color(0x24FFFFFF),
                border: city ? Border.all(color: Color(0xFFA68A5F), width: 1) : nil,
                borderRadius: BorderRadius.all(Radius(circular: city ? 8 : 20))
            ),
            child: Padding(
                padding: EdgeInsets(left: 20, top: 10, right: 20, bottom: 10),
                // Caret leads the placeholder (an empty field with the cursor
                // at the start) and trails real text, as a text field does.
                child: Row(
                    mainAxisAlignment: .center,
                    mainAxisSize: .min,
                    children: empty ? [caret, city ? Flexible(child: label) : label]
                        : [city ? Flexible(child: label) : label, caret]
                )
            )
        )
    }

    override func build(_ context: any BuildContext) -> Widget {
        if city { return cityPanel() }
        let appArea: Widget = apps.isEmpty
            ? Text(
                "No apps match \u{201C}\(query)\u{201D}",
                style: TextStyle(color: Color(0x99FFFFFF), fontSize: 16)
              )
            : Wrap(
                alignment: .center,
                spacing: 40,
                runAlignment: .center,
                runSpacing: 32,
                children: apps.map { tile($0) }
              )

        // Search pill pinned near the top; the app grid below scrolls when it
        // doesn't fit (many installed apps or a short display), so the grid can
        // never overflow the screen the way a fixed centered Column does.
        let grid: Widget = Column(
            mainAxisSize: .max,
            children: [
                SizedBox(height: 72),
                searchBar(),
                SizedBox(height: 36),
                Expanded(
                    child: SingleChildScrollView(
                        padding: EdgeInsets(left: 48, top: 0, right: 48, bottom: 56),
                        child: Center(
                            child: ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: 880),
                                child: appArea
                            )
                        )
                    )
                ),
            ]
        )

        return Stack(
            fit: .expand,
            children: [
                // Blurred, dimmed backdrop over the desktop — also the
                // tap-to-dismiss catcher (taps that miss a tile land here).
                Listener(
                    onPointerDown: { [self] _ in onDismiss() },
                    behavior: .opaque,
                    child: ClipRect(
                        child: BackdropFilter(
                            filter: ImageFilterFactory.blur(sigmaX: 36, sigmaY: 36),
                            child: ColoredBox(
                                color: Color(0x8C0B0B12),
                                child: SizedBox(expand: ())
                            )
                        )
                    )
                ),
                // App grid on top; each tile claims its own tap.
                grid,
            ]
        )
    }

    /// The city's app directory: architectural trim, not a blurred screen.
    private func cityPanel() -> Widget {
        return Stack(fit: .expand, children: [
                GestureDetector(onTap: onDismiss, behavior: .opaque,
                    child: ColoredBox(color: Color(0x66312C24), child: SizedBox(expand: ()))),
                Padding(padding: EdgeInsets(left: 24, top: 24, right: 24, bottom: 24), child: Center(child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 1000, maxHeight: 780),
                    child: SizedBox(expand: (),
                    child: DecoratedBox(decoration: BoxDecoration(
                        color: Color(0xFFE8DFC9),
                        border: Border.all(color: Color(0xFF806342), width: 2),
                        borderRadius: BorderRadius.all(Radius(circular: 12)),
                        boxShadow: [BoxShadow(color: Color(0x55000000), offset: Offset(0, 12), blurRadius: 32)]),
                        child: Padding(padding: EdgeInsets(left: 24, top: 24, right: 24, bottom: 24), child: Column(children: [
                            Row(children: [
                                SizedBox(width: 48, height: 48,
                                    child: CustomPaint(painter: CityLauncherPainter(hovered: false, pressed: false))),
                                SizedBox(width: 16),
                                Expanded(child: Text("Applications", style: TextStyle(
                                    color: Color(0xFF40392F), fontSize: 24, fontWeight: .w600))),
                                HoverButton(builder: { _, states in
                                    DecoratedBox(decoration: BoxDecoration(
                                        color: states.isHovered ? Color(0xFFAF604D) : Color(0xFFF8F2E4),
                                        border: Border.all(color: Color(0xFFA68A5F), width: 1),
                                        borderRadius: BorderRadius.all(Radius(circular: 6))),
                                        child: SizedBox(width: 40, height: 40,
                                            child: Center(child: Text("×", style: TextStyle(
                                                color: states.isHovered ? Color(0xFFF8F2E4) : Color(0xFF574028), fontSize: 24)))))
                                }, onPressed: onDismiss),
                            ]),
                            SizedBox(height: 20),
                            SizedBox(width: 520, child: searchBar()),
                            SizedBox(height: 20),
                            Expanded(child: SingleChildScrollView(
                                padding: EdgeInsets(left: 8, top: 8, right: 8, bottom: 8),
                                child: Center(child: apps.isEmpty
                                    ? Text("No matching apps", style: TextStyle(color: Color(0xFF625747), fontSize: 16))
                                    : Wrap(alignment: .center, spacing: 20, runSpacing: 16,
                                        children: apps.map { tile($0) })))),
                            SizedBox(height: 12),
                            Text("Type to search · Enter to open · Esc to clear / close",
                                style: TextStyle(color: Color(0xFF726C61), fontSize: 12)),
                        ])))))))
            ])
    }

    private func cityTile(_ app: LauncherApp) -> Widget {
        let enamel = Color(alpha: 1, red: app.bgColor.r * 0.62 + 0.20,
            green: app.bgColor.g * 0.62 + 0.18, blue: app.bgColor.b * 0.62 + 0.14)
        return SizedBox(width: 150, height: 136, child: HoverButton(builder: { _, states in
            DecoratedBox(decoration: BoxDecoration(
                color: states.isHovered ? Color(0xFFF8F2E4) : Color(0x00FFFFFF),
                borderRadius: BorderRadius.all(Radius(circular: 8))),
                child: Column(mainAxisAlignment: .center, children: [
                    DecoratedBox(decoration: BoxDecoration(
                        color: states.isPressed ? Color(0xFF806342) : enamel,
                        border: Border.all(color: Color(0xFF806342), width: 1),
                        borderRadius: BorderRadius.all(Radius(circular: 8)),
                        boxShadow: [BoxShadow(color: Color(0x25000000), offset: Offset(0, 3), blurRadius: 4)]),
                        child: SizedBox(width: 80, height: 80, child: Center(child:
                            app.textureId.map { tex in
                                SizedBox(width: 62, height: 62,
                                    child: TextureWidget(textureId: Int(tex), filterQuality: .medium)) as Widget
                            } ?? SizedBox(width: 42, height: 42, child: CustomPaint(
                                painter: IconPainter(app.iconType, color: Color(0xFFF8F2E4))))))),
                    SizedBox(height: 10),
                    Text(app.title, style: TextStyle(color: Color(0xFF40392F), fontSize: 13),
                        textAlign: .center, overflow: .ellipsis, maxLines: 1),
                ]))
        }, onPressed: { [self] in onLaunch(app.appId) }))
    }
}
