// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation
import Observation
import StarlingNet
import StarlingTime

// MARK: - SettingsApp

class SettingsApp: StatefulWidget {
    override func createState() -> State<StatefulWidget> {
        return _SettingsAppState()
    }
}

/// Theme-driven text ramp: white levels on dark, black levels on light.
/// Sidebar tile colors and status colors stay fixed; `accent` tracks the
/// desktop shell's per-theme system blue so selection pills and links
/// highlight with the same blue as the rest of the desktop.
/// Settings' colours, in the roles the pane builders ask for.
///
/// The VALUES come from `StarlingPalette`, which answers for whichever
/// desktop style is active -- the macOS numbers this app shipped with, or
/// WinUI's own tokens when the desktop is in the Windows style. The field
/// names are unchanged so the ~55 `pal.textSecondary`-style readers below
/// never had to learn that styles exist.
///
/// Settings paints its surfaces OPAQUE either way. The translucent
/// liquid-glass haze read as blur over busy backdrops, so the canvas is
/// solid and the shell's frost simply stays hidden behind it.
private struct Palette {
    let textStrong: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let textPlaceholder: Color
    let accent: Color
    let fieldFill: Color
    let fieldBorder: Color
    let glassCanvas: Color
    let glassSidebar: Color
    /// A settings card and its edge, and the rule between rows on one.
    let cardFill: Color
    let cardStroke: Color
    let hairline: Color
    /// The face the active style sets its text in, or nil for the default.
    let fontFamily: String?
    let fontFamilyStrong: String?

    init(dark: Bool) {
        let p = StarlingPalette.current(dark: dark)
        textStrong = p.textPrimary
        textPrimary = p.textPrimary
        textSecondary = p.textSecondary
        textTertiary = p.textTertiary
        textPlaceholder = p.textDisabled
        accent = p.accent
        fieldFill = p.fieldFill
        fieldBorder = p.fieldBorder
        // Opaque: see the note above. The shared palette's macOS canvas
        // carries the alpha the shell's window frost wants; Settings drops
        // it and paints the same colour solid.
        glassCanvas = Color(alpha: 1.0, red: p.canvas.r,
                            green: p.canvas.g, blue: p.canvas.b)
        glassSidebar = Color(alpha: 1.0, red: p.sidebar.r,
                             green: p.sidebar.g, blue: p.sidebar.b)
        cardFill = p.surface
        cardStroke = p.hairline
        hairline = p.hairline
        fontFamily = p.fontFamily
        fontFamilyStrong = p.fontFamilyStrong
    }
}

class _SettingsAppState: State<StatefulWidget>, @unchecked Sendable {

    let bloc = SettingsBloc()

    /// Refreshed from the Fluent theme at every build; read by the section
    /// builders (they don't take a BuildContext).
    private var pal = Palette(dark: true)

    override func initState() {
        super.initState()
        settingsBlocShared = bloc
        bloc.add(.loadInitialData)
    }

    override func build(_ context: any BuildContext) -> Widget {
        return withObservationTracking {
            _buildContent(context)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.setState {}
            }
        }
    }

    // MARK: - Content

    /// The panes, in the order the sidebar lists them. The index is what the
    /// bloc stores as `selectedIndex` and what the search box resolves a
    /// name to.
    private static let _panes: [(title: String, icon: IconData)] = [
        ("General",      FluentSystemIcons.system),
        ("Network",      FluentSystemIcons.wifiFull),
        ("Displays",     FluentSystemIcons.desktop),
        ("Sound",        FluentSystemIcons.volume),
        ("Date & Time",  FluentSystemIcons.clock),
        ("Default Apps", FluentSystemIcons.appDefault),
        ("Appearance",   FluentSystemIcons.personalize),
        ("Power",        FluentSystemIcons.battery),
        ("Sharing",      FluentSystemIcons.share),
        ("About",        FluentSystemIcons.info),
    ]

    /// Windows Settings' shape: a NavigationView with the search box at the
    /// top of the pane and the categories under it; the selected category's
    /// page on the right under a 28pt title, its settings on cards.
    private func _buildContent(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        pal = Palette(dark: theme.brightness == .dark)
        let s = bloc.state
        let selected = s.selectedIndex
        var items: [NavigationPaneItem] = []
        for (i, pane) in Self._panes.enumerated() {
            items.append(PaneItem(
                icon: Icon(pane.icon, size: 16),
                title: Text(pane.title),
                // Only the selected page is built: the others would be
                // widget trees computed every frame for nothing. A
                // placeholder rather than nil — the pane counts only items
                // WITH a body, and a nil one would fall out of its index.
                body: i == selected ? _page(context, index: i) : SizedBox(shrink: ())))
        }
        return NavigationView(
            pane: NavigationPane(
                selected: selected,
                onChanged: { [self] (i: Int) in bloc.add(.selectTab(i)) },
                items: items,
                header: _searchBox(),
                displayMode: .open))
    }

    /// One page: Windows' title over the content, which scrolls.
    private func _page(_ context: any BuildContext, index: Int) -> Widget {
        return ScaffoldPage(
            header: PageHeader(title: Text(_tabTitle(index))),
            content: _buildPage(context, index: index),
            padding: EdgeInsets(all: 0))
    }

    /// "Find a setting": the pane names, filtered as you type; picking one
    /// opens it.
    private func _searchBox() -> Widget {
        var items: [AutoSuggestBoxItem] = []
        for (i, pane) in Self._panes.enumerated() {
            items.append(AutoSuggestBoxItem(
                value: pane.title,
                onTap: { [self] in bloc.add(.selectTab(i)) }))
        }
        return Padding(
            padding: EdgeInsets(left: 12, top: 8, right: 12, bottom: 12),
            child: AutoSuggestBox(
                items: items,
                onSelected: { [self] item in
                    if let i = Self._panes.firstIndex(where: { $0.title == item.value }) {
                        bloc.add(.selectTab(i))
                    }
                },
                placeholderText: "Find a setting",
                leadingIcon: Icon(FluentSystemIcons.search, size: 14),
                clearOnSelect: true))
    }

    /// The content's inset under the page title. Windows sets the title and
    /// the first card on the same left edge.
    private static let _pagePadding = EdgeInsets(left: 24, top: 4, right: 24, bottom: 24)

    private func _tabTitle(_ index: Int) -> String {
        switch index {
        case 0: return "General"
        case 1: return "Network"
        case 2: return "Displays"
        case 3: return "Sound"
        case 4: return "Date & Time"
        case 5: return "Default Apps"
        case 6: return "Appearance"
        case 7: return "Power"
        case 8: return "Sharing"
        case 9: return "About"
        default: return "Settings"
        }
    }

    private func _buildPage(_ context: any BuildContext, index: Int) -> Widget {
        switch index {
        case 0: return _buildGeneralPage()
        case 1: return _buildNetworkPage(context)
        case 2: return _buildDisplayPage()
        case 3: return _buildSoundPage()
        case 4: return _buildDateTimePage()
        case 5: return _buildDefaultAppsPage()
        case 6: return _buildAppearancePage()
        case 7: return _buildPowerPage()
        case 8: return _buildSharingPage()
        case 9: return _buildAboutPage()
        default: return SizedBox(shrink: ())
        }
    }

    // MARK: - General Page (System Info)

    private func _buildGeneralPage() -> Widget {
        let s = bloc.state
        return Padding(
            padding: Self._pagePadding,
            child: Column(
                crossAxisAlignment: .start,
                children: [
                    // System section
                    _sectionHeader("System Information"),
                    SizedBox(height: 12),
                    _card([
                        _settingsRow("Starling OS", "Version \(SystemInfo.starlingVersion())"),
                        _divider(),
                        _settingsRow("OS", s.osVersion),
                        _divider(),
                        _settingsRow("Kernel", s.kernelVersion),
                        _divider(),
                        _settingsRow("Mesa", s.mesaVersion),
                    ]),
                ]
            )
        )
    }

    // MARK: - Network Page

    private func _buildNetworkPage(_ context: any BuildContext) -> Widget {
        let s = bloc.state
        var children: [Widget] = []

        // Wired first: on a desktop it is usually the connection that matters,
        // and it needs no interaction to be useful.
        if !s.wiredLinks.isEmpty {
            children.append(_sectionHeader("Wired"))
            children.append(SizedBox(height: 12))
            var rows: [Widget] = []
            for (i, link) in s.wiredLinks.enumerated() {
                let dev = link.device
                let isUp = link.connected
                if i > 0 { rows.append(_divider()) }
                rows.append(
                    _settingsRowWithTrailingIcon(
                        FluentSystemIcons.ethernet,
                        link.device,
                        link.summary,
                        // Without a cable there is nothing a button could do
                        // but fail, so don't offer one.
                        link.carrier ? Button(
                            onPressed: { [self] in
                                bloc.add(.setWiredConnected(device: dev,
                                                            connected: !isUp))
                            },
                            child: Text(isUp ? "Disconnect" : "Connect")
                        ) : nil
                    )
                )
                if link.connected {
                    rows.append(_detailRow("IP Address", link.ipAddress))
                    rows.append(_detailRow("Gateway", link.gateway))
                    rows.append(_detailRow("DNS", link.dns.joined(separator: ", ")))
                    rows.append(_detailRow("MAC", link.mac))
                }
            }
            children.append(_card(rows))
            children.append(SizedBox(height: 20))
        }

        // Wi-Fi toggle
        children.append(_sectionHeader("Wi-Fi"))
        children.append(SizedBox(height: 12))
        children.append(
            _card([
                _settingsRowWithTrailing(
                    "Wi-Fi",
                    // "Connected to X" / "On" / "Off" — radio-on is not
                    // "Connected"; that is what connectionInfo answers.
                    s.wifiEnabled
                        ? (s.connectionInfo.map { "Connected to \($0.ssid)" } ?? "On")
                        : "Off",
                    _toggle(s.wifiEnabled, { [self] (val: Bool) in
                            bloc.add(.toggleWifi(val))
                        })
                ),
            ])
        )

        guard s.wifiEnabled else {
            // Scrolls like the main path: with the wired details above it,
            // this branch is no longer guaranteed to be short.
            return Padding(
                padding: Self._pagePadding,
                child: SingleChildScrollView(
                    child: Column(crossAxisAlignment: .start, children: children)
                )
            )
        }

        // Active connection
        if let info = s.connectionInfo {
            children.append(SizedBox(height: 20))
            children.append(_sectionHeader("Current Network"))
            children.append(SizedBox(height: 12))
            children.append(
                _card([
                    // No emoji in labels — Noto Sans has no glyph for ✅ (or
                    // the block-element bars), and the fallback renders a
                    // tofu box. Icons come from the SDK's icon font.
                    _settingsRowWithTrailingIcon(
                        FluentSystemIcons.check,
                        info.ssid,
                        "\(info.security.isEmpty ? "Open" : info.security)  \u{2022}  Signal: \(info.signal)%",
                        Button(
                            onPressed: { [self] in
                                bloc.add(.disconnect(connectionName: info.ssid))
                            },
                            child: Text("Disconnect")
                        )
                    ),
                    _divider(),
                    _detailRow("IP Address", info.ipAddress),
                    _detailRow("Gateway", info.gateway),
                    _detailRow("DNS", info.dns.joined(separator: ", ")),
                    _detailRow("Interface", info.device.isEmpty
                        ? "" : "\(info.device)  \u{2022}  \(info.mac)"),
                ])
            )
        }

        // Status
        if let status = s.networkStatus {
            children.append(SizedBox(height: 8))
            children.append(
                Text(status, style: TextStyle(color: Color(0xFFFF8800), fontSize: 12, fontFamily: pal.fontFamily))
            )
        }

        // Available networks
        children.append(SizedBox(height: 20))
        children.append(
            Row(children: [
                _sectionHeader("Available Networks"),
                Expanded(child: SizedBox(shrink: ())),
                GestureDetector(
                    onTap: { [self] in bloc.add(.scanNetworks) },
                    child: Row(mainAxisSize: .min, children: [
                        Icon(FluentSystemIcons.refresh, size: 12, color: pal.accent),
                        SizedBox(width: 4),
                        Text("Scan", style: TextStyle(color: pal.accent, fontSize: 12, fontFamily: pal.fontFamily)),
                    ])
                ),
            ])
        )
        children.append(SizedBox(height: 12))

        if s.wifiNetworks.isEmpty {
            children.append(
                Text(
                    "No networks found. Tap Scan to search.",
                    style: TextStyle(color: pal.textTertiary, fontSize: 12, fontFamily: pal.fontFamily)
                )
            )
        } else {
            var rows: [Widget] = []
            for (i, network) in s.wifiNetworks.enumerated() {
                let ssid = network.ssid
                let isOpen = network.isOpen
                let isSaved = s.savedConnections.contains(ssid)
                if i > 0 { rows.append(_divider()) }
                rows.append(
                    _wifiListRow(
                        network,
                        network.inUse ? nil : GestureDetector(
                            onTap: { [self] in
                                if isOpen || isSaved {
                                    // Open, or saved with a stored password —
                                    // no dialog to answer.
                                    bloc.add(.connectToNetwork(ssid: ssid, password: nil))
                                } else {
                                    _showConnectDialog(context, ssid: ssid)
                                }
                            },
                            child: Text("Connect", style: TextStyle(color: pal.accent, fontSize: 14, fontFamily: pal.fontFamily))
                        )
                    )
                )
            }
            children.append(_card(rows))
        }

        // Saved networks
        if !s.savedConnections.isEmpty {
            children.append(SizedBox(height: 20))
            children.append(_sectionHeader("Saved Networks"))
            children.append(SizedBox(height: 12))
            var rows: [Widget] = []
            for (i, name) in s.savedConnections.enumerated() {
                let connName = name
                if i > 0 { rows.append(_divider()) }
                rows.append(
                    _settingsRowWithTrailing(
                        name, "",
                        GestureDetector(
                            onTap: { [self] in bloc.add(.forgetNetwork(connectionName: connName)) },
                            child: Text("Forget", style: TextStyle(color: Color(0xFFFF6666), fontSize: 14, fontFamily: pal.fontFamily))
                        )
                    )
                )
            }
            children.append(_card(rows))
        }

        return Padding(
            padding: Self._pagePadding,
            child: SingleChildScrollView(
                child: Column(crossAxisAlignment: .start, children: children)
            )
        )
    }

    /// Four ascending bars lit by signal strength — drawn rects, not the
    /// ▂▄▆█ block glyphs: Noto Sans ships no block elements, so the text
    /// spelling renders as tofu (same fix as the shell popup's bars).
    private func _signalBars(_ signal: Int) -> Widget {
        var bars: [Widget] = []
        let heights: [Double] = [4, 6, 8, 10]
        let thresholds = [1, 30, 55, 80]
        for i in 0..<4 {
            if i > 0 { bars.append(SizedBox(width: 2)) }
            bars.append(DecoratedBox(
                decoration: BoxDecoration(
                    color: signal >= thresholds[i] ? pal.textSecondary : pal.fieldFill,
                    borderRadius: BorderRadius.all(Radius(circular: 1))
                ),
                child: SizedBox(width: 3, height: heights[i])
            ))
        }
        return Row(mainAxisSize: .min, crossAxisAlignment: .end, children: bars)
    }

    /// An available-network row: signal bars + SSID + security subtitle.
    private func _wifiListRow(_ network: WifiNetwork, _ trailing: Widget?) -> Widget {
        return Padding(
            padding: EdgeInsets(horizontal: 16, vertical: 8),
            child: Row(children: [
                _signalBars(network.signal),
                SizedBox(width: 10),
                Expanded(
                    child: Column(crossAxisAlignment: .start, children: [
                        Text(network.ssid, style: TextStyle(color: pal.textPrimary, fontSize: 14, fontFamily: pal.fontFamily)),
                        SizedBox(height: 2),
                        Text(network.securityLabel + (network.inUse ? "  \u{2022}  Connected" : ""),
                             style: TextStyle(color: pal.textSecondary, fontSize: 12, fontFamily: pal.fontFamily)),
                    ])
                ),
                trailing ?? SizedBox(shrink: ()),
            ])
        )
    }

    private func _showConnectDialog(_ context: any BuildContext, ssid: String) {
        showDialog(context: context, barrierDismissible: true, builder: { [self] ctx in
            return _WifiPasswordDialog(ssid: ssid, onConnect: { (password: String) in
                self.bloc.add(.connectToNetwork(ssid: ssid, password: password))
            })
        })
    }

    // MARK: - Display Page

    private func _buildDisplayPage() -> Widget {
        let s = bloc.state
        let maxDpi = SystemInfo.maxDPI()
        let divisions = Int((maxDpi - 1.0) * 4)  // 0.25 steps
        var children: [Widget] = []
        #if os(Linux)
        // Only worth a section with something to choose between. On one
        // screen there is no arrangement and no pick to make, and macOS
        // hides the Arrangement tab for exactly that reason.
        if s.displays.count > 1 {
            children.append(_sectionHeader("Arrangement"))
            children.append(SizedBox(height: 12))
            children.append(_displayArrangement(s.displays))
            children.append(SizedBox(height: 12))
            var rows: [Widget] = []
            for (i, display) in s.displays.enumerated() {
                if i > 0 { rows.append(_divider()) }
                let id = display.id
                rows.append(GestureDetector(
                    onTap: { [self] in bloc.add(.selectPrimaryDisplay(id)) },
                    child: _settingsRowWithTrailingIcon(
                        FluentSystemIcons.desktop,
                        display.name,
                        "\(display.physicalWidth)×\(display.physicalHeight)"
                            + "  ·  \(String(format: "%.2g", display.scale))× scale"
                            + (display.isPrimary
                                ? "  ·  primary" : ""),
                        display.isPrimary
                            ? _checkmark()
                            : SizedBox(width: 16, height: 16)
                    )
                ))
            }
            children.append(_card(rows))
            children.append(SizedBox(height: 8))
            children.append(Text(
                "The primary display carries the dock, and new windows open "
                + "there. The menu bar stays on every screen.",
                style: TextStyle(color: pal.textTertiary, fontSize: 12, fontFamily: pal.fontFamily)
            ))
            children.append(SizedBox(height: 20))
        }
        #endif
        children.append(contentsOf: [
            _sectionHeader("Resolution & Scaling"),
            SizedBox(height: 12),
            _card([
                _settingsRow("Scale (DPI)", "\(String(format: "%.2f", s.dpiValue))x"),
                SizedBox(height: 8),
                Padding(
                    padding: EdgeInsets(horizontal: 16),
                    child: Row(children: [
                        Text("1x", style: TextStyle(color: pal.textSecondary, fontSize: 12, fontFamily: pal.fontFamily)),
                        SizedBox(
                            width: 300,
                            child: Slider(
                                value: min(s.dpiValue, maxDpi),
                                onChanged: { [self] (val: Double) in
                                    bloc.add(.previewDpi(val))
                                },
                                onChangeEnd: { [self] (val: Double) in
                                    bloc.add(.changeDpi(val))
                                },
                                min: 1.0, max: maxDpi,
                                divisions: max(divisions, 1)
                            )
                        ),
                        Text("\(String(format: "%.0f", maxDpi))x", style: TextStyle(color: pal.textSecondary, fontSize: 12, fontFamily: pal.fontFamily)),
                    ])
                ),
                SizedBox(height: 4),
                Padding(
                    padding: EdgeInsets(horizontal: 16, vertical: 4),
                    child: Text(
                        _dpiDescription(s.dpiValue),
                        style: TextStyle(color: pal.textTertiary, fontSize: 12, fontFamily: pal.fontFamily)
                    )
                ),
            ]),
        ])
        return Padding(
            padding: Self._pagePadding,
            child: SingleChildScrollView(
                child: Column(crossAxisAlignment: .start, children: children)
            )
        )
    }

    #if os(Linux)
    /// The screens drawn to scale beside each other, macOS Arrangement style:
    /// the primary wears the menu-bar stripe, and tapping a screen makes it the
    /// primary. The shell lays real outputs out left to right in enumeration
    /// order, so this row matches what is on the desk.
    private func _displayArrangement(
        _ displays: [GpuDmaBufRenderer.DisplayInfo]
    ) -> Widget {
        // Scale the whole row to fit the pane, keeping the screens' relative
        // sizes — the point of the picture is that the big one looks big.
        let totalLogical = displays.reduce(0.0) { $0 + Double($1.logicalWidth) }
        let tallest = displays.reduce(1.0) { max($0, Double($1.logicalHeight)) }
        let scale = min(340.0 / max(totalLogical, 1), 96.0 / tallest)
        var tiles: [Widget] = []
        for display in displays {
            let id = display.id
            let w = max(Double(display.logicalWidth) * scale, 40)
            let h = max(Double(display.logicalHeight) * scale, 28)
            tiles.append(GestureDetector(
                onTap: { [self] in bloc.add(.selectPrimaryDisplay(id)) },
                child: Padding(
                    padding: EdgeInsets(right: 10),
                    child: Column(crossAxisAlignment: .center, children: [
                        SizedBox(
                            width: w, height: h,
                            child: DecoratedBox(
                                decoration: BoxDecoration(
                                    color: Color(rgbo: 255, 255, 255, 0.06),
                                    border: Border.all(
                                        color: display.isPrimary
                                            ? pal.accent
                                            : Color(rgbo: 255, 255, 255, 0.22),
                                        width: display.isPrimary ? 2 : 1),
                                    borderRadius: BorderRadius.all(Radius(circular: 4))),
                                // The menu-bar stripe is macOS's cue for which
                                // screen is primary, and the thing you drag
                                // there. Ours is a badge, not a handle — every
                                // screen really does have a menu bar.
                                child: Column(children: [
                                    SizedBox(
                                        height: 5,
                                        child: DecoratedBox(
                                            decoration: BoxDecoration(
                                                color: display.isPrimary
                                                    ? pal.accent
                                                    : Color(rgbo: 255, 255, 255, 0.12)))),
                                    Expanded(child: SizedBox(shrink: ())),
                                ]))),
                        SizedBox(height: 6),
                        Text(display.name, style: TextStyle(
                            color: display.isPrimary ? pal.textPrimary : pal.textSecondary,
                            fontSize: 12, fontFamily: pal.fontFamily)),
                    ]))))
        }
        return Row(crossAxisAlignment: .end, children: tiles)
    }
    #endif

    private func _dpiDescription(_ dpi: Double) -> String {
        let screenW = Int(Double(ProcessInfo.processInfo.environment["FLUTTER_SCREEN_WIDTH"] ?? "") ?? 3840)
        let screenH = Int(Double(ProcessInfo.processInfo.environment["FLUTTER_SCREEN_HEIGHT"] ?? "") ?? 2160)
        let logW = Int(Double(screenW) / dpi)
        let logH = Int(Double(screenH) / dpi)
        let pct = Int(dpi * 100)
        if dpi <= 1.0 { return "1:1 pixel mapping — \(logW)x\(logH)" }
        return "\(pct)% scaling — \(logW)x\(logH) logical"
    }

    // MARK: - Appearance Page

    private func _buildAppearancePage() -> Widget {
        let s = bloc.state
        return Padding(
            padding: Self._pagePadding,
            child: SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: .start,
                    children: [
                        _sectionHeader("Appearance"),
                        SizedBox(height: 12),
                        _card([
                            _settingsRowWithTrailing(
                                "Desktop Style",
                                "The shape of the desktop's own chrome",
                                _choice(Self._styleChoices,
                                        selected: min(s.style, Self._styleChoices.count - 1),
                                        onChanged: { [self] (i: Int) in
                                            bloc.add(.selectStyle(i))
                                        })
                            ),
                            _divider(),
                            _settingsRowWithTrailing(
                                "Dark Mode", "Use dark theme for the interface",
                                _toggle(s.darkMode, { [self] (val: Bool) in bloc.add(.toggleDarkMode(val)) })
                            ),
                            _divider(),
                            _settingsRowWithTrailing(
                                "Tiling Windows", "Automatically tile windows instead of free-floating",
                                _toggle(s.tilingWM, { [self] (val: Bool) in bloc.add(.toggleTilingWM(val)) })
                            ),
                            _divider(),
                            // Windows' two accessibility switches, where
                            // Windows keeps them (Personalization > Colors
                            // and Accessibility > Visual effects): the
                            // shell honours both, and so does every app.
                            _settingsRowWithTrailing(
                                "Transparency effects", "Windows and surfaces appear translucent",
                                _toggle(s.transparency, { [self] (val: Bool) in
                                    bloc.add(.setPref(.transparency, val ? 1 : 0)) })
                            ),
                            _divider(),
                            _settingsRowWithTrailing(
                                "Animation effects", "Windows and menus move as they open and close",
                                _toggle(s.animations, { [self] (val: Bool) in
                                    bloc.add(.setPref(.animations, val ? 1 : 0)) })
                            ),
                        ]),
                        SizedBox(height: 20),
                        _sectionHeader("Start"),
                        SizedBox(height: 12),
                        _card([
                            _settingsRowWithTrailing(
                                "Show recently added apps and recent files",
                                "The Recent section under Pinned",
                                _toggle(s.startRecent, { [self] (val: Bool) in
                                    bloc.add(.setPref(.startRecent, val ? 1 : 0)) })
                            ),
                            _divider(),
                            _settingsRowWithTrailing(
                                "Layout", "How All apps is arranged",
                                _choice(["Category", "Grid", "List"], selected: s.startView,
                                        onChanged: { [self] (i: Int) in bloc.add(.setPref(.startView, i)) })
                            ),
                            _divider(),
                            _settingsRowWithTrailing(
                                "Size", "How much of the screen Start takes",
                                _choice(["Automatic", "Small", "Large"], selected: s.startSize,
                                        onChanged: { [self] (i: Int) in bloc.add(.setPref(.startSize, i)) })
                            ),
                        ]),
                        SizedBox(height: 20),
                        _sectionHeader("Wallpaper"),
                        SizedBox(height: 12),
                        _card([
                            Padding(
                                padding: EdgeInsets(horizontal: 16, vertical: 12),
                                child: Row(children: _wallpaperSwatches(selected: s.wallpaper))
                            ),
                        ]),
                        SizedBox(height: 20),
                        _sectionHeader("Screensaver"),
                        SizedBox(height: 12),
                        _card([
                            _settingsRowWithTrailing(
                                "Start After", "Idle time before the screensaver appears",
                                _choice(Self._screensaverChoices.map { $0.label },
                                        selected: Self._screensaverChoices.firstIndex {
                                            $0.seconds == s.screensaverIdle
                                        } ?? -1,
                                        onChanged: { [self] (i: Int) in
                                            bloc.add(.selectScreensaverIdle(
                                                Self._screensaverChoices[i].seconds))
                                        })
                            ),
                            Padding(
                                padding: EdgeInsets(horizontal: 16, vertical: 4),
                                child: Text(
                                    _screensaverDescription(s.screensaverIdle),
                                    style: TextStyle(color: pal.textTertiary, fontSize: 12, fontFamily: pal.fontFamily)
                                )
                            ),
                        ]),
                        // No Notifications or Auto-Update toggles, no
                        // Brightness or Volume sliders, and no accent picker.
                        // All five sat here once, flipping local state and
                        // nothing else — a control that looks settable and
                        // isn't is worse than its absence. Each comes back
                        // with the backend that makes it real (a notification
                        // daemon, an updater, a backlight writer, an audio
                        // layer, the accent plumbing).
                    ]
                )
            )
        )
    }

    /// The desktop styles, in the shell's own order — this mirrors
    /// `ShellStyles.all`; the shell owns the list and the index is what goes
    /// over the wire. A style from a newer shell than this build knows about
    /// simply selects the last segment rather than crashing the picker.
    private static let _styleChoices: [String] = ["macOS", "Windows"]

    /// The idle timeouts the picker offers. The shell accepts any value —
    /// these are just the ones worth a segment, and an idle timeout it holds
    /// that isn't here (set by hand in the config file, or by a newer build)
    /// shows no selection rather than being silently rounded to one of these.
    private static let _screensaverChoices: [(label: String, seconds: Int)] = [
        ("Never", 0),
        ("1 min", 60),
        ("5 min", 300),
        ("10 min", 600),
        ("30 min", 1800),
        ("1 hr", 3600),
    ]

    private func _screensaverDescription(_ seconds: Int) -> String {
        if seconds <= 0 {
            return "The screensaver never starts on its own. Ctrl+Shift+S still shows it."
        }
        if !Self._screensaverChoices.contains(where: { $0.seconds == seconds }) {
            return "Custom: \(seconds) seconds."
        }
        return "Wakes on any key, click, or mouse movement. "
            + "Video playback holds it off."
    }

    /// One swatch per shell wallpaper preset. The raw values and colors
    /// mirror WallpaperPreset in the shell — the shell owns the enum; this
    /// is its presentation here, and an unknown value from a newer shell
    /// simply shows no selection ring.
    private func _wallpaperSwatches(selected: Int) -> [Widget] {
        let presets: [(raw: Int, name: String, color: Color)] = [
            (0, "Photo", Color(0xFF3A6EA8)),
            (1, "Slate", Color(0xFF2C3444)),
            (2, "Dusk",  Color(0xFF342C4E)),
            (3, "Ocean", Color(0xFF173540)),
            (4, "Ember", Color(0xFF3C302B)),
        ]
        var out: [Widget] = []
        for p in presets {
            out.append(GestureDetector(
                onTap: { [self] in bloc.add(.selectWallpaper(p.raw)) },
                child: Padding(
                    padding: EdgeInsets(right: 14),
                    child: Column(mainAxisSize: .min, children: [
                        DecoratedBox(
                            decoration: BoxDecoration(
                                color: p.color,
                                border: selected == p.raw
                                    ? Border.all(color: pal.accent, width: 2)
                                    : Border.all(color: Color(0x33808080), width: 1),
                                borderRadius: BorderRadius.circular(6)
                            ),
                            child: SizedBox(width: 64, height: 40)
                        ),
                        SizedBox(height: 4),
                        Text(p.name, style: TextStyle(
                            color: selected == p.raw ? pal.textPrimary : pal.textSecondary,
                            fontSize: 12, fontFamily: pal.fontFamily)),
                    ])
                )
            ))
        }
        return out
    }

    // MARK: - Date & Time Page

    private func _buildDateTimePage() -> Widget {
        let s = bloc.state
        let t = s.time
        var children: [Widget] = []
        if !t.available {
            children.append(_sectionHeader("Date & Time"))
            children.append(SizedBox(height: 12))
            children.append(_card([
                _settingsRow("Clock service", "Not running"),
            ]))
            children.append(SizedBox(height: 8))
            children.append(Text(
                "systemd-timedated is not answering — there is nothing to configure.",
                style: TextStyle(color: pal.textTertiary, fontSize: 12, fontFamily: pal.fontFamily)
            ))
        } else {
            children.append(_sectionHeader("Date & Time"))
            children.append(SizedBox(height: 12))
            var clockRows: [Widget] = [
                _settingsRow("Current Time", t.localTime),
            ]
            if t.canNTP {
                clockRows.append(_divider())
                clockRows.append(_settingsRowWithTrailing(
                    "Set time automatically", "Sync the clock over the network (NTP)",
                    _toggle(t.ntpEnabled, { [self] (val: Bool) in bloc.add(.toggleNTP(val)) })
                ))
                clockRows.append(_divider())
                clockRows.append(_settingsRow(
                    "Synchronized", t.ntpSynchronized ? "Yes" : "No"))
            }
            children.append(_card(clockRows))
            children.append(SizedBox(height: 20))
            children.append(_sectionHeader("Time Zone"))
            children.append(SizedBox(height: 12))
            children.append(_card(_timezoneRows(s)))
        }
        if let error = s.timeError {
            children.append(SizedBox(height: 8))
            // polkit's refusal, verbatim: a session that is not seat-active
            // is not allowed to set the clock, and pretending the toggle
            // worked would be worse than showing why it didn't.
            children.append(Text(
                error,
                style: TextStyle(color: Color(0xFFE0655A), fontSize: 12, fontFamily: pal.fontFamily)
            ))
        }
        return Padding(
            padding: Self._pagePadding,
            child: SingleChildScrollView(
                child: Column(crossAxisAlignment: .start, children: children)
            )
        )
    }

    /// The timezone group: the current zone as a tappable row; open, it
    /// becomes a two-step picker (region, then city) fed from
    /// `timedatectl list-timezones` — the picker never invents a zone the
    /// system would refuse.
    private func _timezoneRows(_ s: SettingsState) -> [Widget] {
        var rows: [Widget] = [
            GestureDetector(
                onTap: { [self] in
                    bloc.add(.setTzPicker(open: !s.tzPickerOpen, region: nil))
                },
                child: _settingsRowWithTrailing(
                    "Time Zone", s.time.timezone,
                    Icon(s.tzPickerOpen
                                  ? FluentSystemIcons.chevronUp
                                  : FluentSystemIcons.chevronDown, size: 12, color: pal.textSecondary)
                )
            ),
        ]
        guard s.tzPickerOpen else { return rows }
        if s.timezones.isEmpty {
            rows.append(_divider())
            rows.append(_settingsRow("Loading zones…", ""))
            return rows
        }
        if let region = s.tzPickerRegion {
            rows.append(_divider())
            rows.append(GestureDetector(
                onTap: { [self] in bloc.add(.setTzPicker(open: true, region: nil)) },
                child: _settingsRow("‹ All Regions", region)
            ))
            for zone in TimeControl.zones(s.timezones, inRegion: region) {
                let city = zone.contains("/")
                    ? String(zone.split(separator: "/", maxSplits: 1)[1])
                        .replacingOccurrences(of: "_", with: " ")
                    : zone
                rows.append(_divider())
                rows.append(GestureDetector(
                    onTap: { [self] in bloc.add(.selectTimezone(zone)) },
                    child: _settingsRowWithTrailing(
                        city, "",
                        zone == s.time.timezone
                            ? _checkmark()
                            : SizedBox(width: 16, height: 16)
                    )
                ))
            }
        } else {
            for region in TimeControl.regions(of: s.timezones) {
                rows.append(_divider())
                rows.append(GestureDetector(
                    onTap: { [self] in
                        bloc.add(.setTzPicker(open: true, region: region))
                    },
                    child: _settingsRowWithTrailing(
                        region, "",
                        Icon(FluentSystemIcons.chevronRight, size: 12, color: pal.textSecondary)
                    )
                ))
            }
        }
        return rows
    }

    // MARK: - Default Apps Page

    private func _buildDefaultAppsPage() -> Widget {
        let s = bloc.state
        var children: [Widget] = [
            _sectionHeader("Web Browser"),
            SizedBox(height: 12),
        ]
        if s.browserCandidates.isEmpty {
            children.append(_card([
                _settingsRow("Browser", "None installed"),
            ]))
            children.append(SizedBox(height: 8))
            children.append(Text(
                "No installed app declares itself a browser. Install one from "
                + "the App Store and it appears here.",
                style: TextStyle(color: pal.textTertiary, fontSize: 12, fontFamily: pal.fontFamily)
            ))
        } else {
            var rows: [Widget] = []
            for (i, candidate) in s.browserCandidates.enumerated() {
                if i > 0 { rows.append(_divider()) }
                rows.append(GestureDetector(
                    onTap: { [self] in bloc.add(.selectBrowser(candidate.id)) },
                    child: _settingsRowWithTrailing(
                        candidate.name,
                        candidate.id == s.defaultBrowser
                            ? "Opens web links" : "Tap to make default",
                        candidate.id == s.defaultBrowser
                            ? _checkmark()
                            : SizedBox(width: 16, height: 16)
                    )
                ))
            }
            children.append(_card(rows))
            children.append(SizedBox(height: 8))
            children.append(Text(
                "http and https links from every app open here. Deep-link "
                + "schemes (slack://, zoommtg://, …) always route to their "
                + "own app — each app's registry record declares its schemes.",
                style: TextStyle(color: pal.textTertiary, fontSize: 12, fontFamily: pal.fontFamily)
            ))
        }
        return Padding(
            padding: Self._pagePadding,
            child: SingleChildScrollView(
                child: Column(crossAxisAlignment: .start, children: children)
            )
        )
    }

    // MARK: - Sound Page

    private func _buildSoundPage() -> Widget {
        let a = bloc.state.audio
        var children: [Widget] = []
        if !a.available {
            children.append(_sectionHeader("Sound"))
            children.append(SizedBox(height: 12))
            children.append(_card([
                _settingsRow("Sound system", "Not running"),
            ]))
            children.append(SizedBox(height: 8))
            children.append(Text(
                "PipeWire is not answering — there is nothing to control.",
                style: TextStyle(color: pal.textTertiary, fontSize: 12, fontFamily: pal.fontFamily)
            ))
        } else {
            children.append(_sectionHeader("Output Volume"))
            children.append(SizedBox(height: 12))
            children.append(_card([
                Padding(
                    padding: EdgeInsets(horizontal: 16, vertical: 10),
                    child: Row(children: [
                        Icon(FluentSystemIcons.volumeLow, size: 14, color: pal.textSecondary),
                        SizedBox(width: 10),
                        Expanded(
                            child: Slider(
                                value: min(a.volume, 1.0) * 100,
                                onChanged: { [self] (val: Double) in
                                    bloc.add(.changeVolume(val / 100))
                                },
                                min: 0, max: 100
                            )
                        ),
                        SizedBox(width: 10),
                        Icon(FluentSystemIcons.volume, size: 14, color: pal.textSecondary),
                        SizedBox(width: 12),
                        Text("\(Int((min(a.volume, 1.0) * 100).rounded()))%",
                             style: TextStyle(color: pal.textSecondary, fontSize: 12, fontFamily: pal.fontFamily)),
                    ])
                ),
                _divider(),
                _settingsRowWithTrailing(
                    "Mute", "Silence the current output",
                    _toggle(a.muted, { [self] (val: Bool) in bloc.add(.toggleMute(val)) })
                ),
            ]))
            children.append(SizedBox(height: 20))
            children.append(_sectionHeader("Output Device"))
            children.append(SizedBox(height: 12))
            if a.sinks.isEmpty {
                children.append(_card([
                    _settingsRow("Output", "No devices"),
                ]))
                children.append(SizedBox(height: 8))
                children.append(Text(
                    "PipeWire reports no output hardware. The volume above still "
                    + "applies to whatever sink is routing.",
                    style: TextStyle(color: pal.textTertiary, fontSize: 12, fontFamily: pal.fontFamily)
                ))
            } else {
                var rows: [Widget] = []
                for (i, sink) in a.sinks.enumerated() {
                    if i > 0 { rows.append(_divider()) }
                    rows.append(GestureDetector(
                        onTap: { [self] in bloc.add(.selectSink(sink.id)) },
                        child: _settingsRowWithTrailing(
                            sink.name,
                            sink.isDefault ? "Current output" : "Tap to switch",
                            sink.isDefault
                                ? _checkmark()
                                : SizedBox(width: 16, height: 16)
                        )
                    ))
                }
                children.append(_card(rows))
            }
        }
        return Padding(
            padding: Self._pagePadding,
            child: SingleChildScrollView(
                child: Column(crossAxisAlignment: .start, children: children)
            )
        )
    }

    // MARK: - Power Page

    /// "2 h 05 min" under an hour shortens to "45 min" — the same spelling
    /// as the shell's battery popup.
    private func _formatMinutes(_ minutes: Int) -> String {
        if minutes >= 60 {
            return "\(minutes / 60) h \(String(format: "%02d", minutes % 60)) min"
        }
        return "\(minutes) min"
    }

    // MARK: - Sharing Page (remote desktop)

    /// Remote desktop over RDP. The switch reflects the shell's report of the
    /// listener, not the click: turning it on can fail (no certificate, port
    /// in use) and the switch springs back rather than lying about it.
    private func _buildSharingPage() -> Widget {
        let s = bloc.state
        #if os(Linux)
        let enabled = s.rdpEnabled
        #else
        let enabled = false
        #endif
        _ = s

        let rows: [Widget] = [
            _settingsRowWithTrailing(
                "Remote Desktop",
                "Let another computer see and control this desktop over RDP",
                _toggle(enabled, { [self] (val: Bool) in bloc.add(.toggleRdp(val)) })
            ),
        ]

        return Padding(
            padding: Self._pagePadding,
            child: SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: .start,
                    children: [
                        _sectionHeader("Sharing"),
                        SizedBox(height: 12),
                        _card(rows),
                        SizedBox(height: 12),
                        // Said plainly, and on screen rather than only in the
                        // docs: the connection is encrypted but not
                        // authenticated, so the port IS the credential.
                        Padding(
                            padding: EdgeInsets(horizontal: 4),
                            child: Text(
                                "Anyone who can reach this machine on the network "
                                + "can connect — there is no password. The "
                                + "connection is encrypted, but access is not "
                                + "restricted. Leave this off on untrusted networks.",
                                style: TextStyle(color: pal.textSecondary,
                                                 fontSize: 12, fontFamily: pal.fontFamily)
                            )
                        ),
                    ]
                )
            )
        )
    }

    private func _buildPowerPage() -> Widget {
        let b = bloc.state.battery
        var children: [Widget] = [
            _sectionHeader("Battery"),
            SizedBox(height: 12),
        ]
        if b.present {
            let barColor: Color = b.state == .discharging && b.percent <= 20
                ? Color(0xFFFF3B30)
                : (b.state == .charging ? Color(0xFF34C759) : pal.accent)
            var rows: [Widget] = [
                _settingsRow("Charge", "\(b.percent)%"),
                Padding(
                    padding: EdgeInsets(left: 16, top: 2, right: 16, bottom: 12),
                    child: SizedBox(
                        height: 8,
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                                color: Color(0x33808080),
                                borderRadius: BorderRadius.circular(4)
                            ),
                            child: Align(
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                    widthFactor: Double(b.percent) / 100.0,
                                    child: DecoratedBox(
                                        decoration: BoxDecoration(
                                            color: barColor,
                                            borderRadius: BorderRadius.circular(4)
                                        ),
                                        child: SizedBox(expand: ())
                                    )
                                )
                            )
                        )
                    )
                ),
                _divider(),
                _settingsRow("Status", b.state.label),
                _divider(),
                _settingsRow("Power Source", b.acOnline ? "AC Power" : "Battery"),
            ]
            // Estimate rows only when the kernel offered a rate — a missing
            // estimate reads as a missing row, never a made-up time.
            if b.state == .charging, let m = b.minutesToFull {
                rows.append(_divider())
                rows.append(_settingsRow("Time to Full", _formatMinutes(m)))
            } else if b.state == .discharging, let m = b.minutesToEmpty {
                rows.append(_divider())
                rows.append(_settingsRow("Time Remaining", _formatMinutes(m)))
            }
            children.append(_card(rows))
        } else {
            children.append(_card([
                _settingsRow("Battery", "None detected"),
            ]))
            children.append(SizedBox(height: 8))
            children.append(Text(
                "This machine reports no system battery — power settings apply to laptops.",
                style: TextStyle(color: pal.textTertiary, fontSize: 12, fontFamily: pal.fontFamily)
            ))
        }
        // Brightness exists only where a backlight does — same gate as the
        // battery icon. External monitors are DDC, a different world.
        let bl = bloc.state.backlight
        if bl.present {
            children.append(SizedBox(height: 20))
            children.append(_sectionHeader("Display Brightness"))
            children.append(SizedBox(height: 12))
            children.append(_card([
                Padding(
                    padding: EdgeInsets(horizontal: 16, vertical: 10),
                    child: Row(children: [
                        Icon(FluentSystemIcons.brightness, size: 14, color: pal.textSecondary),
                        SizedBox(width: 10),
                        Expanded(
                            child: Slider(
                                value: Double(bl.percent),
                                onChanged: { [self] (val: Double) in
                                    bloc.add(.changeBrightness(Int(val.rounded())))
                                },
                                min: 1, max: 100
                            )
                        ),
                        SizedBox(width: 10),
                        Icon(FluentSystemIcons.sun, size: 14, color: pal.textSecondary),
                        SizedBox(width: 12),
                        Text("\(bl.percent)%",
                             style: TextStyle(color: pal.textSecondary, fontSize: 12, fontFamily: pal.fontFamily)),
                    ])
                ),
            ]))
        }
        if let error = bloc.state.powerError {
            children.append(SizedBox(height: 8))
            children.append(Text(
                error,
                style: TextStyle(color: Color(0xFFE0655A), fontSize: 12, fontFamily: pal.fontFamily)
            ))
        }
        return Padding(
            padding: Self._pagePadding,
            child: SingleChildScrollView(
                child: Column(crossAxisAlignment: .start, children: children)
            )
        )
    }

    // MARK: - About Page

    private func _buildAboutPage() -> Widget {
        #if os(macOS)
        let platformName = "macOS (Darwin)"
        #elseif os(Linux)
        let platformName = "Linux"
        #endif

        return Padding(
            padding: Self._pagePadding,
            child: SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: .start,
                    children: [
                        // macOS-style centered logo area
                        SizedBox(height: 20),
                        Center(
                            child: Column(
                                children: [
                                    Text(
                                        "\u{2B50}",
                                        style: TextStyle(fontSize: 48)
                                    ),
                                    SizedBox(height: 12),
                                    Text(
                                        "Starling OS",
                                        style: TextStyle(
                                            color: pal.textStrong,
                                            fontSize: 20,
                                            fontWeight: .w600
                                        )
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                        "Version \(SystemInfo.starlingVersion())",
                                        style: TextStyle(color: pal.textSecondary, fontSize: 14, fontFamily: pal.fontFamily)
                                    ),
                                ]
                            )
                        ),
                        SizedBox(height: 24),
                        _card([
                            _settingsRow("Framework", "Starling SDK (Fluent)"),
                            _divider(),
                            _settingsRow("Platform", platformName),
                        ]),
                    ]
                )
            )
        )
    }

    // MARK: - Windows Settings' shapes

    /// A section header: Body Strong, sitting a little above its cards.
    private func _sectionHeader(_ title: String) -> Widget {
        return Text(
            title,
            style: TextStyle(
                color: pal.textPrimary,
                fontSize: 14,
                fontWeight: .w600,
                fontFamily: pal.fontFamilyStrong ?? pal.fontFamily
            )
        )
    }

    /// A settings card: rows on a raised surface with a hairline edge and
    /// 4pt corners, rules between the rows — the shape of a SettingsExpander's
    /// open list in Windows Settings.
    private func _card(_ children: [Widget]) -> Widget {
        let radius = BorderRadius.all(Radius(circular: 4))
        return DecoratedBox(
            decoration: BoxDecoration(
                color: pal.cardFill,
                border: Border.all(color: pal.cardStroke, width: 1),
                borderRadius: radius
            ),
            child: ClipRRect(
                borderRadius: radius,
                child: Column(
                    crossAxisAlignment: .stretch,
                    children: children
                )
            )
        )
    }

    /// A row with a label and a value.
    private func _settingsRow(_ label: String, _ value: String) -> Widget {
        return Padding(
            padding: EdgeInsets(horizontal: 16, vertical: 14),
            child: Row(children: [
                Text(label, style: TextStyle(color: pal.textPrimary, fontSize: 14, fontFamily: pal.fontFamily)),
                Expanded(child: SizedBox(shrink: ())),
                Text(value, style: TextStyle(color: pal.textSecondary, fontSize: 14, fontFamily: pal.fontFamily)),
            ])
        )
    }

    /// A row with a label, a description under it, and a control at the
    /// right — Windows' SettingsCard.
    private func _settingsRowWithTrailing(_ label: String, _ subtitle: String, _ trailing: Widget?) -> Widget {
        return Padding(
            padding: EdgeInsets(horizontal: 16, vertical: 12),
            child: Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: .start,
                        children: subtitle.isEmpty
                            ? [Text(label, style: TextStyle(color: pal.textPrimary, fontSize: 14, fontFamily: pal.fontFamily))]
                            : [
                                Text(label, style: TextStyle(color: pal.textPrimary, fontSize: 14, fontFamily: pal.fontFamily)),
                                SizedBox(height: 2),
                                Text(subtitle, style: TextStyle(color: pal.textSecondary, fontSize: 12, fontFamily: pal.fontFamily)),
                              ]
                    )
                ),
                SizedBox(width: 16),
                trailing ?? SizedBox(shrink: ()),
            ])
        )
    }

    /// The same row led by an icon.
    private func _settingsRowWithTrailingIcon(
        _ icon: IconData, _ label: String, _ subtitle: String, _ trailing: Widget?
    ) -> Widget {
        return Padding(
            padding: EdgeInsets(horizontal: 16, vertical: 12),
            child: Row(children: [
                Icon(icon, size: 16, color: pal.textPrimary),
                SizedBox(width: 16),
                Expanded(
                    child: Column(crossAxisAlignment: .start, children: [
                        Text(label, style: TextStyle(color: pal.textPrimary, fontSize: 14, fontFamily: pal.fontFamily)),
                        SizedBox(height: 2),
                        Text(subtitle, style: TextStyle(color: pal.textSecondary, fontSize: 12, fontFamily: pal.fontFamily)),
                    ])
                ),
                SizedBox(width: 16),
                trailing ?? SizedBox(shrink: ()),
            ])
        )
    }

    /// A detail key-value row (used in network info).
    private func _detailRow(_ label: String, _ value: String) -> Widget {
        return Padding(
            padding: EdgeInsets(left: 48, top: 3, right: 16, bottom: 3),
            child: Row(children: [
                SizedBox(
                    width: 96,
                    child: Text(label, style: TextStyle(color: pal.textTertiary, fontSize: 12, fontFamily: pal.fontFamily))
                ),
                Expanded(
                    child: Text(value, style: TextStyle(color: pal.textSecondary, fontSize: 12, fontFamily: pal.fontFamily))
                ),
            ])
        )
    }

    /// The rule between two rows on a card: full width, 1pt.
    private func _divider() -> Widget {
        return SizedBox(
            height: 1,
            child: DecoratedBox(decoration: BoxDecoration(color: pal.hairline))
        )
    }

    /// A ToggleSwitch with Windows' "On"/"Off" beside it.
    private func _toggle(_ on: Bool, _ onChanged: @escaping (Bool) -> Void) -> Widget {
        return ToggleSwitch(
            checked: on,
            onChanged: onChanged,
            content: Text(on ? "On" : "Off",
                          style: TextStyle(color: pal.textPrimary, fontSize: 14, fontFamily: pal.fontFamily)),
            leadingContent: true)
    }

    /// A ComboBox over a list of labels, by index; -1 selects nothing.
    private func _choice(_ labels: [String], selected: Int, onChanged: @escaping (Int) -> Void) -> Widget {
        var items: [ComboBoxItem<Int>] = []
        for (i, label) in labels.enumerated() {
            items.append(ComboBoxItem(value: i, child: Text(label)))
        }
        return ComboBox<Int>(
            value: selected >= 0 && selected < labels.count ? selected : nil,
            items: items,
            onChanged: { (v: Int?) in if let v { onChanged(v) } })
    }

    /// The accent check that marks the chosen row.
    private func _checkmark() -> Widget {
        return Icon(FluentSystemIcons.check, size: 16, color: pal.accent)
    }
}

// MARK: - Wi-Fi Password Dialog

class _WifiPasswordDialog: StatefulWidget {
    let ssid: String
    let onConnect: (String) -> Void

    init(ssid: String, onConnect: @escaping (String) -> Void) {
        self.ssid = ssid
        self.onConnect = onConnect
        super.init()
    }

    override func createState() -> State<StatefulWidget> {
        return _WifiPasswordDialogState()
    }
}

class _WifiPasswordDialogState: State<StatefulWidget> {
    private let password = TextEditingController()

    override func dispose() {
        password.dispose()
        super.dispose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let dialog = widget as! _WifiPasswordDialog
        return ContentDialog(
            title: Text("Connect to \(dialog.ssid)"),
            content: Column(mainAxisSize: .min, crossAxisAlignment: .start, children: [
                Text("Enter the Wi-Fi password to join this network."),
                SizedBox(height: 12),
                FluentTextBox(
                    controller: password,
                    placeholderText: "Password",
                    onSubmitted: { [self] _ in _connect(context) },
                    obscureText: true,
                    autofocus: true
                ),
            ]),
            actions: [
                Button(onPressed: { Navigator.pop(context) }, child: Text("Cancel")),
                FilledButton(onPressed: { [self] in _connect(context) }, child: Text("Connect")),
            ]
        )
    }

    private func _connect(_ context: any BuildContext) {
        let dialog = widget as! _WifiPasswordDialog
        Navigator.pop(context)
        dialog.onConnect(password.text)
    }
}
