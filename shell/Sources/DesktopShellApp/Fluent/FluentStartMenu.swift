// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Start: a panel above the taskbar, not a screen.
//
// That is the substantive difference from Launchpad, which takes the whole
// display and dims everything behind it. Start opens over the desktop and
// leaves it visible, so opening it is a smaller act — you can see what you
// were doing while you look for the next thing.
//
// The panel is anchored to the BOTTOM CENTRE, above the bar, and its width is
// fixed rather than proportional: Windows' Start is the same size on a laptop
// panel and a 4K monitor, and a grid that reflows with the display makes the
// same app land somewhere different every time.
//
// Typing is routed here by the shell's key handler exactly as it is for
// Launchpad — `_launcherQuery` is filtered upstream, so an empty query is the
// pinned grid and a non-empty one is the results, in the same cells.

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

// MARK: - Geometry

// Sized against the real thing rather than guessed: on the reference machine
// (test/win/capture-reference.sh) Windows' Start measures 830 x 862pt on a
// 1920x1080 logical desktop — a big panel that owns most of the screen's
// height, not the small card this started as. Held to a fraction of the
// display so it stays proportionate on a laptop panel, where a fixed 830
// would not fit at all.
private enum StartPanel {
    static let width: Double = 640
    static let minHeight: Double = 320
    static let maxHeight: Double = 640
    /// Windows' proportions: roughly 43% of the width and 80% of the height.
    static let widthFraction: Double = 0.43
    static let heightFraction: Double = 0.80
    static let pad: Double = 20
    static let radius: Double = 8
    /// Gap between the panel and the taskbar.
    static let gap: Double = 12
    static let columns: Int = 6
    static let cellHeight: Double = 88
    static let iconSize: Double = 32
    static let searchHeight: Double = 34
    static let footerHeight: Double = 48
    /// Everything above the grid: top padding, the search box, and the
    /// section header with its gaps.
    static let headerBlock: Double = pad + searchHeight + 18 + 24 + 8
    /// Below the grid: its bottom padding and the footer strip.
    static let footerBlock: Double = 12 + footerHeight

    /// The panel sizes to its grid rather than standing at a fixed height:
    /// Windows fills the space below Pinned with a Recommended section, and
    /// without one a fixed panel is two thirds empty.
    static func height(rows: Int, available: Double) -> Double {
        let wanted = headerBlock + Double(rows) * cellHeight + footerBlock
        return max(minHeight, min(min(wanted, maxHeight), available))
    }
}

// MARK: - FluentStartMenu

class FluentStartMenu: StatelessWidget {
    let apps: [LauncherApp]
    /// How many apps are installed, before the query filters them. The panel
    /// is SIZED from this rather than from `apps.count`, so it does not resize
    /// under the pointer on every keystroke as results narrow.
    let installedCount: Int
    let query: String
    let caretOn: Bool
    let userName: String
    let screenWidth: Double
    let screenHeight: Double

    let onLaunch: (String) -> Void
    let onPower: () -> Void
    let onDismiss: () -> Void

    init(apps: [LauncherApp], installedCount: Int, query: String,
         caretOn: Bool, userName: String,
         screenWidth: Double, screenHeight: Double,
         onLaunch: @escaping (String) -> Void,
         onPower: @escaping () -> Void,
         onDismiss: @escaping () -> Void) {
        self.apps = apps
        self.installedCount = installedCount
        self.query = query
        self.caretOn = caretOn
        self.userName = userName
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.onLaunch = onLaunch
        self.onPower = onPower
        self.onDismiss = onDismiss
    }

    override func build(_ context: any BuildContext) -> Widget {
        let barH = DesktopTheme.kDockHeight
        // Windows' proportions where the screen is big enough for them, and
        // the fixed size where it is not.
        let width = min(max(StartPanel.width,
                            screenWidth * StartPanel.widthFraction),
                        screenWidth - 32)
        let available = screenHeight - barH - StartPanel.gap * 2
        let rows = (max(installedCount, 1) + StartPanel.columns - 1)
            / StartPanel.columns
        let height = min(available,
                         max(StartPanel.height(rows: rows, available: available),
                             screenHeight * StartPanel.heightFraction))

        return Stack(
            fit: .expand,
            children: [
                // Tap-to-dismiss over the whole desktop. No blur and no scrim:
                // Start is a panel, and dimming the desktop behind it would
                // make it read as a mode.
                Listener(
                    onPointerDown: { [self] _ in onDismiss() },
                    behavior: .opaque,
                    child: SizedBox(expand: ())
                ),
                Positioned(
                    left: (screenWidth - width) / 2,
                    bottom: barH + StartPanel.gap,
                    width: width,
                    height: height,
                    child: _panel()
                ),
            ]
        )
    }

    // MARK: The panel

    private func _panel() -> Widget {
        // Claims its own pointers so a click inside does not fall through to
        // the dismiss layer behind it.
        Listener(
            onPointerDown: { _ in },
            behavior: .opaque,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: shellTheme.panelFill,
                    border: Border.all(color: shellTheme.panelStroke, width: 1),
                    borderRadius: BorderRadius.circular(StartPanel.radius),
                    boxShadow: [
                        BoxShadow(color: shellTheme.popupShadow,
                                  offset: Offset(0, 8), blurRadius: 24),
                    ]
                ),
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(StartPanel.radius),
                    // Acrylic under the panel's tint, which is why that tint
                    // is translucent — Start is a frosted pane over the
                    // desktop, not a grey card sitting on it.
                    child: BackdropFilter(
                        filter: ShellPalette.chromeFilter(blurSigma: 20),
                        child: Column(
                        crossAxisAlignment: .stretch,
                        children: [
                            Padding(
                                padding: EdgeInsets(
                                    left: StartPanel.pad, top: StartPanel.pad,
                                    right: StartPanel.pad, bottom: 0),
                                child: Column(
                                    mainAxisSize: .min,
                                    crossAxisAlignment: .stretch,
                                    children: [
                                        _searchBox(),
                                        SizedBox(height: 18),
                                        _sectionHeader(),
                                        SizedBox(height: 8),
                                    ]
                                )
                            ),
                            Expanded(child: _grid()),
                            _footer(),
                        ]
                        )
                    )
                )
            )
        )
    }

    /// The query, live. Not a text field: the shell's key router owns the
    /// keyboard while Start is open and feeds `query` from above, so the caret
    /// is the only thing that says the typing is going somewhere. It blinks by
    /// fading rather than by being removed — swapping the glyph out changes
    /// the advance width and shifts the text twice a second.
    private func _searchBox() -> Widget {
        let empty = query.isEmpty
        return SizedBox(
            height: StartPanel.searchHeight,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: shellTheme.controlFill,
                    border: Border.all(color: shellTheme.controlStroke, width: 1),
                    borderRadius: BorderRadius.circular(4)
                ),
                child: Padding(
                    padding: EdgeInsets(left: 10, top: 0, right: 10, bottom: 0),
                    child: Row(crossAxisAlignment: .center) {
                        MacosIcon(icon: FluentSystemIcons.search,
                                  color: shellTheme.fgSecondary, size: 14)
                        SizedBox(width: 8)
                        Text(empty ? "Search for apps" : query,
                             style: TextStyle(
                                color: empty ? shellTheme.fgTertiary
                                             : shellTheme.fgPrimary,
                                fontSize: 13, fontFamily: shellTheme.fontFamily),
                             overflow: .ellipsis,
                             maxLines: 1)
                        Text("|", style: TextStyle(
                            color: caretOn ? shellTheme.fgPrimary
                                           : Color(0x00000000),
                            fontSize: 13, fontFamily: shellTheme.fontFamily), maxLines: 1)
                    }
                )
            )
        )
    }

    private func _sectionHeader() -> Widget {
        Row(mainAxisAlignment: .spaceBetween, crossAxisAlignment: .center) {
            Text(query.isEmpty ? "Pinned" : "Results",
                 style: TextStyle(color: shellTheme.fgPrimary,
                                  fontSize: 13, fontWeight: .w600, fontFamily: shellTheme.fontFamilyStrong))
            Text("\(apps.count) apps",
                 style: TextStyle(color: shellTheme.fgSecondary, fontSize: 12, fontFamily: shellTheme.fontFamily))
        }
    }

    private func _grid() -> Widget {
        if apps.isEmpty {
            return Center(child: Text(
                "No apps match \u{201C}\(query)\u{201D}",
                style: TextStyle(color: shellTheme.fgSecondary, fontSize: 13, fontFamily: shellTheme.fontFamily)))
        }
        // Rows of `columns`, padded out to a full row so the last row's tiles
        // stay left-aligned under the ones above instead of centring.
        var rows: [Widget] = []
        var i = 0
        while i < apps.count {
            let slice = apps[i..<min(i + StartPanel.columns, apps.count)]
            rows.append(Row(crossAxisAlignment: .start) {
                for app in slice { Expanded(child: _tile(app)) }
                for _ in slice.count..<StartPanel.columns {
                    Expanded(child: SizedBox(height: StartPanel.cellHeight))
                }
            })
            i += StartPanel.columns
        }
        return SingleChildScrollView(
            padding: EdgeInsets(left: StartPanel.pad, top: 0,
                                right: StartPanel.pad, bottom: 12),
            child: Column(crossAxisAlignment: .stretch, children: rows)
        )
    }

    private func _tile(_ app: LauncherApp) -> Widget {
        let glyph: Widget
        if let texId = app.textureId {
            glyph = TextureWidget(textureId: Int(texId), filterQuality: .medium)
        } else {
            glyph = DecoratedBox(
                decoration: BoxDecoration(
                    gradient: ShellPalette.tileGradient(app.bgColor)),
                child: Center(
                    child: SizedBox(
                        width: StartPanel.iconSize * 0.55,
                        height: StartPanel.iconSize * 0.55,
                        child: CustomPaint(
                            painter: IconPainter(app.iconType,
                                                 color: Color(0xFFFFFFFF)))))
            )
        }

        return HoverButton(
            builder: { context, states in
                let hot = states.isHovered || states.isPressed
                return DecoratedBox(
                    decoration: BoxDecoration(
                        color: hot ? shellTheme.barHover : Color(0x00000000),
                        borderRadius: BorderRadius.circular(4)
                    ),
                    child: SizedBox(
                        height: StartPanel.cellHeight,
                        child: Column(
                            mainAxisAlignment: .center,
                            crossAxisAlignment: .center,
                            children: [
                                SizedBox(
                                    width: StartPanel.iconSize,
                                    height: StartPanel.iconSize,
                                    child: ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: glyph)
                                ),
                                SizedBox(height: 8),
                                Padding(
                                    padding: EdgeInsets(left: 4, top: 0,
                                                        right: 4, bottom: 0),
                                    child: Text(
                                        app.title,
                                        style: TextStyle(
                                            color: shellTheme.fgPrimary,
                                            fontSize: 11, fontFamily: shellTheme.fontFamily),
                                        textAlign: .center,
                                        overflow: .ellipsis,
                                        maxLines: 2)
                                ),
                            ]
                        )
                    )
                )
            },
            onPressed: { [self] in onLaunch(app.appId) }
        )
    }

    /// The user on the left, power on the right — where Windows puts them, and
    /// the reason the taskbar does not carry a power tile.
    private func _footer() -> Widget {
        SizedBox(
            height: StartPanel.footerHeight,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    // A WASH over the panel, not a fill: Windows' footer is a
                    // shade DARKER than the body it sits under, and using the
                    // field colour here made it lighter — white-on-grey where
                    // the reference is grey-on-white.
                    //
                    // Weaker than `hoverFill`, which measured 29 levels down
                    // from the body against the reference's 16: the wash lands
                    // on the blurred backdrop rather than on the panel fill,
                    // so it bites harder here than the same alpha does on a
                    // plain surface.
                    color: shellTheme.isDark ? Color(0x0AFFFFFF)
                                             : Color(0x06000000),
                    border: Border(
                        top: BorderSide(color: shellTheme.panelStroke, width: 1))
                ),
                child: Padding(
                    padding: EdgeInsets(left: 12, top: 6, right: 12, bottom: 6),
                    child: Row(mainAxisAlignment: .spaceBetween,
                               crossAxisAlignment: .center) {
                        Row(mainAxisSize: .min, crossAxisAlignment: .center) {
                            MacosIcon(icon: FluentSystemIcons.person,
                                      color: shellTheme.fgPrimary, size: 18)
                            SizedBox(width: 8)
                            Text(userName, style: TextStyle(
                                color: shellTheme.fgPrimary, fontSize: 13, fontFamily: shellTheme.fontFamily))
                        }
                        SizedBox(
                            width: 36, height: 36,
                            child: HoverButton(
                                builder: { context, states in
                                    let hot = states.isHovered || states.isPressed
                                    return DecoratedBox(
                                        decoration: BoxDecoration(
                                            color: hot ? shellTheme.controlHover
                                                       : Color(0x00000000),
                                            borderRadius: BorderRadius.circular(4)
                                        ),
                                        child: Center(child: MacosIcon(
                                            icon: FluentSystemIcons.power,
                                            color: shellTheme.fgPrimary,
                                            size: 16))
                                    )
                                },
                                onPressed: { [self] in onPower() }
                            )
                        )
                    }
                )
            )
        )
    }
}
