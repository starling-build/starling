// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation
import StarlingRegistry

// MARK: - Palette

/// macOS-App-Store-style palette for both appearances.
private struct StorePalette {
    let background: Color
    let sidebar: Color
    let sidebarSelected: Color
    let card: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let buttonIdle: Color
    let buttonIdleText: Color
    let separator: Color
    let progressTrack: Color
    let installedGreen: Color
    let failedRed: Color
    /// Remove button: tinted rather than filled, so a destructive action is
    /// clearly not the primary one next to Open.
    let destructiveBg: Color
    let destructiveText: Color

    init(dark: Bool) {
        if StarlingPalette.isCity {
            let p = StarlingPalette.city
            background = p.canvas
            sidebar = p.sidebar
            sidebarSelected = p.hover
            card = p.surface
            textPrimary = p.textPrimary
            textSecondary = p.textSecondary
            accent = p.accent
            buttonIdle = p.hover
            buttonIdleText = p.accent
            separator = p.hairline
            progressTrack = p.sidebar
            installedGreen = p.accent
            failedRed = Color(0xFFAF604D)
            destructiveBg = Color(0x20AF604D)
            destructiveText = Color(0xFFAF604D)
            return
        }
        if dark {
            background = Color(0xC221252C)
            sidebar = Color(0x7A1D2129)
            sidebarSelected = Color(0x33FFFFFF)
            card = Color(0xFF323234)
            textPrimary = Color(0xFFFFFFFF)
            textSecondary = Color(0x99FFFFFF)
            accent = Color(0xFF0A84FF)
            buttonIdle = Color(0x28FFFFFF)
            buttonIdleText = Color(0xFF0A84FF)
            separator = Color(0x22FFFFFF)
            progressTrack = Color(0x33FFFFFF)
            installedGreen = Color(0xFF32D74B)
            failedRed = Color(0xFFFF6961)
            destructiveBg = Color(0x33FF453A)
            destructiveText = Color(0xFFFF6961)
        } else {
            background = Color(0xCCF4F4F6)
            sidebar = Color(0xA6ECECEF)
            sidebarSelected = Color(0x1A000000)
            card = Color(0xFFFFFFFF)
            textPrimary = Color(0xFF1D1D1F)
            textSecondary = Color(0x99000000)
            accent = Color(0xFF007AFF)
            buttonIdle = Color(0x14000000)
            buttonIdleText = Color(0xFF007AFF)
            separator = Color(0x1A000000)
            progressTrack = Color(0x1F000000)
            installedGreen = Color(0xFF28A745)
            failedRed = Color(0xFFD70015)
            destructiveBg = Color(0x1FD70015)
            destructiveText = Color(0xFFD70015)
        }
    }
}

// MARK: - App tile icons

/// Hand-drawn glyphs for the catalog tiles (no bundled image assets).
/// What a catalog tile draws.
///
/// Deliberately by *category*, not by brand. Starling ships no third-party
/// artwork: those logos are their owners' trademarks and their software
/// licences do not grant the marks (Mozilla and Google both reserve them
/// explicitly). Naming an app you can install is nominative use and fine;
/// redrawing its logo is not. So a browser gets a globe, not a coloured disc.
private enum StoreIconKind {
    case browser, videoCall, graphics, terminal, editor, generic
}

/// From the catalog's `Glyph`, which is the same field the shell's dock and
/// launcher draw from — so an app's shape is declared once, in its record,
/// rather than in a per-app switch here and another one there.
private func iconKind(_ glyph: String) -> StoreIconKind {
    switch glyph {
    case "chrome":    return .browser
    case "vscode":    return .editor
    case "videoCall": return .videoCall
    case "graphics":  return .graphics
    case "terminal":  return .terminal
    default:          return .generic
    }
}

private class StoreIconPainter: CustomPainter {
    let glyph: String

    init(_ glyph: String) {
        self.glyph = glyph
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        let w = size.width, h = size.height
        let c = Offset(w / 2, h / 2)
        let paint = Paint()
        paint.style = .fill
        paint.color = Color(0xFFFFFFFF)

        switch iconKind(glyph) {
        case .browser:
            // Globe: ring, equator, two meridians drawn as narrowing ellipses.
            paint.style = .stroke
            paint.strokeWidth = max(1.5, w * 0.055)
            canvas.drawCircle(c, w * 0.36, paint)
            canvas.drawLine(Offset(c.dx - w * 0.36, c.dy),
                            Offset(c.dx + w * 0.36, c.dy), paint)
            for fraction in [0.40, 0.80] {
                canvas.drawOval(
                    Rect.fromCenter(center: c, width: w * 0.72 * fraction, height: w * 0.72),
                    paint)
            }
        case .editor:
            // Angle brackets around a slash — a generic "code" mark, not
            // anyone's ribbon.
            paint.style = .stroke
            paint.strokeWidth = max(1.5, w * 0.075)
            paint.strokeCap = .round
            let inset = w * 0.26
            canvas.drawLine(Offset(c.dx - inset, c.dy - h * 0.18),
                            Offset(w * 0.18, c.dy), paint)
            canvas.drawLine(Offset(w * 0.18, c.dy),
                            Offset(c.dx - inset, c.dy + h * 0.18), paint)
            canvas.drawLine(Offset(c.dx + inset, c.dy - h * 0.18),
                            Offset(w * 0.82, c.dy), paint)
            canvas.drawLine(Offset(w * 0.82, c.dy),
                            Offset(c.dx + inset, c.dy + h * 0.18), paint)
            canvas.drawLine(Offset(c.dx + w * 0.07, c.dy - h * 0.20),
                            Offset(c.dx - w * 0.07, c.dy + h * 0.20), paint)
        case .videoCall:
            // Plain video-camera pictogram: body plus lens cone.
            canvas.drawRRect(
                RRect(fromRectAndRadius:
                        Rect.fromLTWH(w * 0.20, h * 0.36, w * 0.34, h * 0.28),
                      Radius(circular: 5)),
                paint)
            let lens = Rect.fromLTWH(w * 0.56, h * 0.30, w * 0.40, h * 0.40)
            canvas.drawArc(lens, 150 * .pi / 180, 60 * .pi / 180, true, paint)
        case .graphics:
            // Artist's palette: disc, thumb hole, paint dots.
            paint.color = Color(0xFFF2F2F2)
            canvas.drawCircle(c, w * 0.38, paint)
            paint.color = tileColor(glyph)       // carves the hole
            canvas.drawCircle(Offset(c.dx + w * 0.20, c.dy + h * 0.16), w * 0.13, paint)
            let dots: [(Color, Double, Double)] = [
                (Color(0xFFE53935), -0.16, -0.18),
                (Color(0xFF43A047), 0.10, -0.20),
                (Color(0xFF1E88E5), -0.20, 0.10),
            ]
            for (color, dx, dy) in dots {
                paint.color = color
                canvas.drawCircle(Offset(c.dx + w * dx, c.dy + h * dy), w * 0.07, paint)
            }
        case .terminal:
            // Activity bars.
            let heights: [Double] = [0.30, 0.52, 0.40, 0.62]
            let barW = w * 0.12
            let gap = w * 0.06
            let totalW = Double(heights.count) * barW + Double(heights.count - 1) * gap
            var x = (w - totalW) / 2
            let colors: [Color] = [
                Color(0xFF32D74B), Color(0xFFFFD60A), Color(0xFF32D74B), Color(0xFFFF9F0A),
            ]
            for (i, hh) in heights.enumerated() {
                paint.color = colors[i]
                let barH = h * hh
                canvas.drawRRect(
                    RRect(fromRectAndRadius:
                            Rect.fromLTWH(x, h * 0.76 - barH, barW, barH),
                          Radius(circular: 2)),
                    paint)
                x += barW + gap
            }
        case .generic:
            canvas.drawCircle(c, w * 0.3, paint)
        }
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        guard let old = oldDelegate as? StoreIconPainter else { return true }
        return old.glyph != glyph
    }
}

/// Tile backgrounds follow the same rule: a neutral ramp by category, not the
/// vendor's brand colour.
private func tileColor(_ glyph: String) -> Color {
    switch iconKind(glyph) {
    case .browser:   return Color(0xFF3E4C5E)
    case .editor:    return Color(0xFF2B303B)
    case .videoCall: return Color(0xFF3A4A55)
    case .graphics:  return Color(0xFF4A3B32)
    case .terminal:  return Color(0xFF1C1C1E)
    case .generic:   return Color(0xFF444444)
    }
}

// MARK: - AppStoreApp

class AppStoreApp: StatefulWidget {
    override func createState() -> State<StatefulWidget> {
        return _AppStoreAppState()
    }
}

class _AppStoreAppState: State<StatefulWidget>, @unchecked Sendable {

    private var pal = StorePalette(dark: true)
    // Transient lifecycle only (installing / failed). The steady installed vs
    // notInstalled state is derived from disk on each read, so an install or
    // removal done outside this window — the CLI, the dock, another view — is
    // reflected live without reopening the store.
    private var states: [String: InstallState] = [:]

    /// Apps the shell reports as live. Removing one would pull the package
    /// out from under a running program, so Remove is disabled for them.
    ///
    /// Maintained by the shell and pushed over the broker socket — the store
    /// does not work this out for itself, or it would drift from what the
    /// dock shows.
    private var running: Set<String> = []

    // Flathub page. Collections load once on first visit; a search replaces
    // them while the query is non-empty. Results are Flathub's own records
    // turned into AppRecords, so every row below is the same row widget.
    private let flathubSearch = TextEditingController()
    private var flathubQuery = ""
    private var flathubSearchGeneration = 0
    private var flathubResults: [FlathubApp]? = nil
    private var flathubSearching = false
    private var flathubPopular: [FlathubApp]? = nil
    private var flathubTrending: [FlathubApp]? = nil
    private var flathubError: String? = nil
    private var flathubLoadedCollections = false
    // The page the sidebar has selected: "Discover", "Installed", or one of
    // Flathub's category ids below. Every page is filled from Flathub.
    private var selectedPage = "Discover"
    /// Flathub's main categories, in sidebar order. Left: the id its
    /// collection endpoint takes; right: the label.
    static let flathubCategories: [(id: String, label: String)] = [
        ("AudioVideo", "Audio & Video"), ("Development", "Development"),
        ("Education", "Education"), ("Game", "Games"), ("Graphics", "Graphics"),
        ("Network", "Internet"), ("Office", "Office"), ("Science", "Science"),
        ("System", "System"), ("Utility", "Utilities"),
    ]
    // A category's listing loads the first time its page is opened.
    private var flathubCategoryApps: [String: [FlathubApp]] = [:]
    private var flathubCategoryError: [String: String] = [:]
    private var flathubCategoryRequested: Set<String> = []

    override func initState() {
        super.initState()
        FlathubClient.shared.onIconsChanged = { [weak self] in
            guard let self else { return }
            self.setState {}
        }
        ShellLink.shared.onRunningChanged = { [weak self] live in
            guard let self, live != self.running else { return }
            self.setState { self.running = live }
        }
        ShellLink.shared.connect()
    }

    override func dispose() {
        FlathubClient.shared.onIconsChanged = nil
        ShellLink.shared.onRunningChanged = nil
        ShellLink.shared.disconnect()
        super.dispose()
    }

    private func _installedOnDisk(_ entry: AppRecord) -> Bool {
        switch entry.backend {
        case .host(let bins):     return HostStore.shared.isInstalled(bins: bins)
        case .deb(_, let marker): return DebStore.shared.isInstalled(entry.id, marker: marker)
        case .flatpak(let appId): return HostStore.shared.isFlatpakInstalled(appId)
        }
    }

    private func _state(_ entry: AppRecord) -> InstallState {
        let onDisk = _installedOnDisk(entry)
        if let s = states[entry.id] {
            switch s {
            case .installing:
                return s                          // in-flight — keep as shown
            case .failed(_, let removal):
                // A failure is only worth showing while the thing it failed
                // to do still hasn't happened. Once it has — from the CLI,
                // another store window, apt directly — the error is a lie, so
                // fall through to the truth on disk.
                //
                // A failed removal is stale once the app is gone; a failed
                // install is stale once it is present. Both are "the on-disk
                // state no longer matches what the failure was about".
                if removal == onDisk { return s }
            default:
                break
            }
        }
        return onDisk ? .installed : .notInstalled
    }

    private func _install(_ entry: AppRecord) {
        if case .installing = _state(entry) { return }
        setState {
            states[entry.id] = .installing(progress: nil, status: "Contacting store…")
        }
        let onUpdate: @Sendable (InstallState) -> Void = { [weak self] state in
            guard let self else { return }
            self.setState { self.states[entry.id] = state }
        }
        switch entry.backend {
        case .host:
            HostStore.shared.install(entry.installRecipe ?? entry.id,
                                     onUpdate: onUpdate)
        case .deb(let url, let marker):
            DebStore.shared.install(entry.id, url: url, marker: marker,
                                    onUpdate: onUpdate)
        case .flatpak(let appId):
            HostStore.shared.installFlatpak(appId) { state in
                onUpdate(state)
                if case .installed = state {
                    // The launcher and dock learn of it by watching Flatpak's
                    // exports; the store's own list is refreshed here.
                    DispatchQueue.main.async { AppRegistry.shared.reload() }
                }
            }
        }
    }

    private func _uninstall(_ entry: AppRecord) {
        if case .installing = _state(entry) { return }
        // Never remove a running app: apt would delete the binaries and data
        // files out from under live processes, leaving something that is
        // half-uninstalled and still on screen. The button is already disabled
        // in that case; this catches a click that raced the shell's push.
        // `app-install` checks again at the point of action, which is the
        // guarantee — this is just the UI half of it.
        if running.contains(entry.id) { return }
        setState {
            states[entry.id] = .installing(progress: nil, status: "Removing…")
        }
        let onUpdate: @Sendable (InstallState) -> Void = { [weak self] state in
            guard let self else { return }
            self.setState { self.states[entry.id] = state }
        }
        switch entry.backend {
        case .host:
            HostStore.shared.remove(entry.installRecipe ?? entry.id,
                                    onUpdate: onUpdate)
        case .deb:
            DebStore.shared.remove(entry.id, onUpdate: onUpdate)
        case .flatpak(let appId):
            HostStore.shared.removeFlatpak(appId) { state in
                onUpdate(state)
                if case .notInstalled = state {
                    DispatchQueue.main.async { AppRegistry.shared.reload() }
                }
            }
        }
    }

    /// Open an installed app through the same launcher the dock uses.
    private func _open(_ entry: AppRecord) {
        if case .flatpak(let appId) = entry.backend {
            HostStore.shared.launchFlatpak(appId)
            return
        }
        HostStore.shared.launch(entry.exec)
    }

    // MARK: Build

    override func build(_ context: any BuildContext) -> Widget {
        let theme = MacosTheme.of(context)
        pal = StorePalette(dark: theme.brightness == .dark)

        // The store is Flathub, and nothing else: third-party apps come from
        // there, sandboxed, with a graphics stack the runtime keeps current.
        // Discover, Installed and the category shelves are all Flathub. The
        // catalog's remaining host entries (Chrome, VS Code, IntelliJ,
        // Ubuntu's App Center) are launcher and dock entries, installed from
        // the command line with `app-install <id>` — not store items.
        let page: Widget
        switch selectedPage {
        case "Discover": page = _buildDiscover()
        case "Installed": page = _buildInstalled()
        default: page = _buildCategoryPage(selectedPage)
        }
        return ColoredBox(
            color: pal.background,
            child: Row(crossAxisAlignment: .stretch, children: [
                _buildSidebar(),
                Expanded(child: page),
            ])
        )
    }

    /// Categories with at least one app, in catalog order — the first app of
    /// each category decides where its section sits, so the shelf order is a
    /// curation the catalog owns rather than an alphabetical accident.

    /// Filtered list page for a sidebar category (Browsers, Work, …).

    // MARK: Sidebar

    private func _sidebarItem(_ id: String, _ label: String) -> Widget {
        let selected = id == selectedPage
        return GestureDetector(
            onTap: { [self] in
                if selectedPage != id {
                    setState { selectedPage = id }
                }
            },
            behavior: .opaque,
            child: Padding(
                padding: EdgeInsets(left: 10, top: 2, right: 10, bottom: 2),
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: selected ? pal.sidebarSelected : Color(0x00000000),
                        borderRadius: BorderRadius.circular(6)
                    ),
                    child: Padding(
                        padding: EdgeInsets(left: 10, top: 6, right: 10, bottom: 6),
                        child: Row(children: [
                            Text(label, style: TextStyle(
                                color: pal.textPrimary, fontSize: 13,
                                fontWeight: selected ? .w600 : .w400)),
                        ])
                    )
                )
            )
        )
    }

    private func _buildSidebar() -> Widget {
        return SizedBox(
            width: 185,
            child: ColoredBox(
                color: pal.sidebar,
                child: Column(crossAxisAlignment: .stretch, children: [
                    SizedBox(height: 14),
                    Padding(
                        padding: EdgeInsets(left: 20, top: 0, right: 20, bottom: 10),
                        child: Row(children: [
                            Text("App Store", style: TextStyle(
                                color: pal.textPrimary, fontSize: 17, fontWeight: .w700)),
                        ])
                    ),
                    _sidebarItem("Discover", "Discover"),
                    _sidebarItem("Installed", "Installed"),
                    SizedBox(height: 10),
                ] + Self.flathubCategories.map { _sidebarItem($0.id, $0.label) } + [
                    Expanded(child: SizedBox(expand: ())),
                ])
            )
        )
    }

    // MARK: Flathub data

    private func _loadFlathubCollections() {
        guard !flathubLoadedCollections else { return }
        flathubLoadedCollections = true
        FlathubClient.shared.collection("popular") { [weak self] apps, error in
            guard let self else { return }
            self.setState {
                self.flathubPopular = apps
                if let error, self.flathubPopular == nil { self.flathubError = error }
            }
        }
        FlathubClient.shared.collection("trending") { [weak self] apps, _ in
            guard let self else { return }
            self.setState { self.flathubTrending = apps }
        }
    }

    private func _loadCategory(_ id: String) {
        guard !flathubCategoryRequested.contains(id) else { return }
        flathubCategoryRequested.insert(id)
        FlathubClient.shared.collection("category/\(id)?page=1&per_page=40") { [weak self] apps, error in
            guard let self else { return }
            self.setState {
                if let apps { self.flathubCategoryApps[id] = apps }
                if let error { self.flathubCategoryError[id] = error }
            }
        }
    }

    private func _flathubQueryChanged(_ q: String) {
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        flathubQuery = trimmed
        flathubSearchGeneration += 1
        let gen = flathubSearchGeneration
        if trimmed.count < 2 {
            setState { flathubResults = nil; flathubSearching = false }
            return
        }
        // Debounced: a keystroke starts a search only once typing pauses.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, gen == self.flathubSearchGeneration else { return }
            self._runFlathubSearch(trimmed, generation: gen)
        }
    }

    private func _runFlathubSearch(_ q: String, generation: Int) {
        setState { flathubSearching = true; flathubError = nil }
        FlathubClient.shared.search(q) { [weak self] apps, error in
            guard let self, generation == self.flathubSearchGeneration else { return }
            self.setState {
                self.flathubSearching = false
                self.flathubResults = apps ?? []
                self.flathubError = error
            }
        }
    }

    // MARK: Pages

    /// A Flathub app as a store row: its record, with the icon fetch kicked
    /// off the first time the row is built.
    private func _flathubRow(_ app: FlathubApp) -> Widget {
        FlathubClient.shared.loadIcon(appId: app.appId, url: app.iconURL, localPath: nil)
        return _appRow(app.record())
    }

    private func _card(_ rows: [Widget]) -> Widget {
        DecoratedBox(
            decoration: BoxDecoration(
                color: pal.card,
                borderRadius: BorderRadius.circular(12)
            ),
            child: Padding(
                padding: EdgeInsets(left: 16, top: 4, right: 16, bottom: 4),
                child: Column(children: rows)
            )
        )
    }

    private func _flathubList(_ apps: [FlathubApp]) -> Widget {
        var rows: [Widget] = []
        for app in apps {
            if !rows.isEmpty { rows.append(_divider()) }
            rows.append(_flathubRow(app))
        }
        return _card(rows)
    }

    private func _sectionTitle(_ title: String) -> Widget {
        Row(children: [
            Text(title, style: TextStyle(
                color: pal.textPrimary, fontSize: 17, fontWeight: .w600)),
        ])
    }

    private func _note(_ text: String, color: Color? = nil) -> Widget {
        Padding(
            padding: EdgeInsets(left: 0, top: 16, right: 0, bottom: 0),
            child: Row(children: [
                Text(text, style: TextStyle(color: color ?? pal.textSecondary, fontSize: 14)),
            ])
        )
    }

    private func _pageHeader(_ title: String, _ subtitle: String) -> [Widget] {
        [
            Row(children: [
                Text(title, style: TextStyle(
                    color: pal.textPrimary, fontSize: 24, fontWeight: .w700)),
            ]),
            SizedBox(height: 4),
            Row(children: [
                Text(subtitle, style: TextStyle(color: pal.textSecondary, fontSize: 12)),
            ]),
        ]
    }

    private func _page(_ children: [Widget]) -> Widget {
        SingleChildScrollView(
            padding: EdgeInsets(left: 24, top: 20, right: 24, bottom: 24),
            child: Column(crossAxisAlignment: .start, children: children)
        )
    }

    /// Search, then what Flathub says is popular and trending.
    private func _buildDiscover() -> Widget {
        _loadFlathubCollections()
        var children = _pageHeader(
            "Discover",
            "Apps from Flathub, sandboxed, with a graphics driver the store keeps current.")
        children.append(SizedBox(height: 14))
        children.append(SizedBox(width: 420, child: MacosSearchField(
            controller: flathubSearch,
            placeholder: "Search Flathub",
            onChanged: { [self] q in _flathubQueryChanged(q) },
            onSubmitted: { [self] q in
                flathubSearchGeneration += 1
                _runFlathubSearch(q.trimmingCharacters(in: .whitespaces),
                                  generation: flathubSearchGeneration)
            }
        )))
        children.append(SizedBox(height: 20))
        if !flathubQuery.isEmpty {
            if flathubSearching {
                children.append(_note("Searching…"))
            } else if let error = flathubError {
                children.append(_note(error, color: pal.failedRed))
            } else if let results = flathubResults {
                if results.isEmpty {
                    children.append(_note("Nothing on Flathub matches “\(flathubQuery)”."))
                } else {
                    children.append(_sectionTitle("Results"))
                    children.append(SizedBox(height: 6))
                    children.append(_flathubList(results))
                }
            }
        } else if let error = flathubError, flathubPopular == nil {
            children.append(_note(error, color: pal.failedRed))
        } else if let popular = flathubPopular {
            children.append(_sectionTitle("Popular"))
            children.append(SizedBox(height: 6))
            children.append(_flathubList(Array(popular.prefix(12))))
            if let trending = flathubTrending, !trending.isEmpty {
                children.append(SizedBox(height: 26))
                children.append(_sectionTitle("Trending"))
                children.append(SizedBox(height: 6))
                children.append(_flathubList(Array(trending.prefix(12))))
            }
        } else {
            children.append(_note("Loading Flathub…"))
        }
        return _page(children)
    }

    /// Every Flatpak on this machine, from the registry — the same records the
    /// launcher and dock read, so the store cannot disagree with them.
    private func _buildInstalled() -> Widget {
        var children = _pageHeader("Installed", "Flatpaks on this machine.")
        children.append(SizedBox(height: 16))
        let installed = AppRegistry.shared.apps.filter { $0.kind == .flatpak }
        if installed.isEmpty {
            children.append(_note("Nothing from Flathub is installed yet."))
        } else {
            var rows: [Widget] = []
            for rec in installed {
                FlathubClient.shared.loadIcon(appId: rec.exec, url: nil, localPath: rec.iconPath)
                if !rows.isEmpty { rows.append(_divider()) }
                rows.append(_appRow(rec))
            }
            children.append(_card(rows))
        }
        return _page(children)
    }

    /// One of Flathub's category shelves, fetched the first time it opens.
    private func _buildCategoryPage(_ id: String) -> Widget {
        _loadCategory(id)
        let label = Self.flathubCategories.first { $0.id == id }?.label ?? id
        var children = _pageHeader(label, "\(label) on Flathub, most popular first.")
        children.append(SizedBox(height: 16))
        if let apps = flathubCategoryApps[id] {
            if apps.isEmpty {
                children.append(_note("Flathub lists nothing in \(label) yet."))
            } else {
                children.append(_flathubList(apps))
            }
        } else if let error = flathubCategoryError[id] {
            children.append(_note(error, color: pal.failedRed))
        } else {
            children.append(_note("Loading Flathub…"))
        }
        return _page(children)
    }

    private func _divider() -> Widget {
        return SizedBox(height: 1, child: ColoredBox(
            color: pal.separator, child: SizedBox(expand: ())))
    }

    /// Big gradient banner for the headline app, macOS-style. The gradient is
    /// Starling's own accent, deliberately not the featured vendor's brand blue.

    /// One row in the "More Apps" list.
    private func _appRow(_ entry: AppRecord) -> Widget {
        return Padding(
            padding: EdgeInsets(left: 0, top: 12, right: 0, bottom: 12),
            child: Row(children: [
                _appTile(entry, size: 48, radius: 11),
                SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: .start, children: [
                    Text(entry.name, style: TextStyle(
                        color: pal.textPrimary, fontSize: 14, fontWeight: .w600)),
                    SizedBox(height: 2),
                    Text(_rowSubtitle(entry),
                         style: TextStyle(color: pal.textSecondary, fontSize: 12),
                         maxLines: 2),
                ])),
                SizedBox(width: 16),
                _actionCluster(entry, onBanner: false),
            ])
        )
    }

    /// Rounded-square app icon tile.
    /// "summary — category · publisher", skipping whatever the record lacks
    /// (an installed Flatpak discovered from disk has only a name).
    private func _rowSubtitle(_ entry: AppRecord) -> String {
        let tail = [entry.category, entry.publisher].filter { !$0.isEmpty }.joined(separator: " · ")
        switch (entry.subtitle.isEmpty, tail.isEmpty) {
        case (false, false): return "\(entry.subtitle) — \(tail)"
        case (false, true):  return entry.subtitle
        case (true, false):  return tail
        case (true, true):   return entry.kind == .flatpak ? "Flatpak" : ""
        }
    }

    private func _appTile(_ entry: AppRecord, size: Double, radius: Double) -> Widget {
        // A Flathub app carries its real icon, fetched and decoded once;
        // until it lands (or if it never does) the glyph tile stands in.
        if entry.kind == .flatpak, let icon = FlathubClient.shared.icons[entry.exec] {
            return SizedBox(width: size, height: size, child: DecoratedBox(
                decoration: BoxDecoration(
                    color: pal.card,
                    borderRadius: BorderRadius.circular(radius),
                    boxShadow: [BoxShadow(
                        color: Color(0x33000000), offset: Offset(0, 1), blurRadius: 4)]
                ),
                child: ClipRRect(
                    borderRadius: BorderRadius.all(Radius(circular: radius)),
                    child: CustomPaint(painter: FlathubIconPainter(icon))
                )
            ))
        }
        return SizedBox(width: size, height: size, child: DecoratedBox(
            decoration: BoxDecoration(
                color: tileColor(entry.glyph),
                borderRadius: BorderRadius.circular(radius),
                boxShadow: [BoxShadow(
                    color: Color(0x33000000), offset: Offset(0, 1), blurRadius: 4)]
            ),
            child: ClipRRect(
                borderRadius: BorderRadius.all(Radius(circular: radius)),
                child: CustomPaint(painter: StoreIconPainter(entry.glyph))
            )
        ))
    }

    // MARK: Install button / progress cluster

    /// The right-hand side of a row: install button, progress, installed
    /// state, or error — depending on the entry's lifecycle state.
    private func _actionCluster(_ entry: AppRecord, onBanner: Bool) -> Widget {
        let accentText = onBanner ? Color(0xFF2B6CB0) : pal.buttonIdleText
        let pillBg = onBanner ? Color(0xFFFFFFFF) : pal.buttonIdle

        switch _state(entry) {
        case .notInstalled:
            return Column(children: [
                _pillButton("Install", bg: pillBg, fg: accentText) { [self] in
                    _install(entry)
                },
                SizedBox(height: 4),
                Text(entry.sizeLabel, style: TextStyle(
                    color: onBanner ? Color(0xB3FFFFFF) : pal.textSecondary,
                    fontSize: 10)),
            ])
        case .installing(let progress, let status):
            return SizedBox(width: 120, child: Column(crossAxisAlignment: .end, children: [
                _progressBar(progress, onBanner: onBanner),
                SizedBox(height: 5),
                Text(progress.map { "\(status) \(Int($0 * 100))%" } ?? status,
                     style: TextStyle(
                        color: onBanner ? Color(0xE6FFFFFF) : pal.textSecondary,
                        fontSize: 10)),
            ]))
        case .installed:
            // Open and Remove side by side, both real buttons. Remove used to
            // be 10pt caption text under Open, which read as a label rather
            // than something you could press.
            //
            // Remove is tinted, not filled: destructive, and clearly not the
            // primary action. It fires immediately with no confirmation —
            // deliberate, because the point of this pair is a quick
            // install/run/remove loop, and `app-install --remove` is a plain
            // apt removal that reinstalling undoes.
            let removeBg = onBanner ? Color(0x40FFFFFF) : pal.destructiveBg
            let removeFg = onBanner ? Color(0xFFFFE0E0) : pal.destructiveText
            let isRunning = running.contains(entry.id)
            // Running: Remove goes flat and inert, with the reason under it.
            // Dimming rather than hiding keeps the row from reflowing every
            // time you launch or quit something.
            let remove: Widget = isRunning
                ? _pillLabel("Remove",
                             bg: onBanner ? Color(0x1AFFFFFF) : pal.progressTrack,
                             fg: onBanner ? Color(0x66FFFFFF) : pal.textSecondary)
                : _pillButton("Remove", bg: removeBg, fg: removeFg) { [self] in
                    _uninstall(entry)
                  }
            return Column(crossAxisAlignment: .end, children: [
                Row(mainAxisSize: .min, children: [
                    _pillButton("Open", bg: pillBg, fg: accentText) { [self] in
                        _open(entry)
                    },
                    SizedBox(width: 8),
                    remove,
                ]),
                SizedBox(height: 4),
                Text(isRunning ? "Quit \(entry.name) to remove it" : "Installed",
                     style: TextStyle(
                        color: onBanner ? Color(0xB3FFFFFF) : pal.textSecondary,
                        fontSize: 10)),
            ])
        case .failed(let message, let removal):
            return SizedBox(width: 150, child: Column(crossAxisAlignment: .end, children: [
                // Retry what actually failed. A failed uninstall offering to
                // install is worse than useless — it does the opposite of
                // what you were trying to do.
                _pillButton("Retry", bg: pillBg, fg: accentText) { [self] in
                    if removal { _uninstall(entry) } else { _install(entry) }
                },
                SizedBox(height: 4),
                Text(message, style: TextStyle(
                    color: onBanner ? Color(0xFFFFD0D0) : pal.failedRed,
                    fontSize: 9), maxLines: 3),
            ]))
        }
    }

    /// A pill that looks like a button but isn't one — the disabled state.
    private func _pillLabel(_ label: String, bg: Color, fg: Color) -> Widget {
        return DecoratedBox(
            decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(13)
            ),
            child: Padding(
                padding: EdgeInsets(left: 18, top: 5, right: 18, bottom: 5),
                child: Text(label, style: TextStyle(
                    color: fg, fontSize: 13, fontWeight: .w600))
            )
        )
    }

    private func _pillButton(_ label: String, bg: Color, fg: Color,
                             onTap: @escaping () -> Void) -> Widget {
        return GestureDetector(
            onTap: onTap,
            behavior: .opaque,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(13)
                ),
                child: Padding(
                    padding: EdgeInsets(left: 18, top: 5, right: 18, bottom: 5),
                    child: Text(label, style: TextStyle(
                        color: fg, fontSize: 13, fontWeight: .w600))
                )
            )
        )
    }

    private func _progressBar(_ fraction: Double?, onBanner: Bool) -> Widget {
        let track = onBanner ? Color(0x40FFFFFF) : pal.progressTrack
        let fill = onBanner ? Color(0xFFFFFFFF) : pal.accent
        let width = 120.0
        // Indeterminate: a half-filled bar (no animation ticker in this
        // child app; the status text underneath carries the liveness).
        let f = fraction ?? 0.5
        return SizedBox(width: width, height: 5, child: Stack(children: [
            DecoratedBox(
                decoration: BoxDecoration(
                    color: track, borderRadius: BorderRadius.circular(2.5)),
                child: SizedBox(width: width, height: 5)
            ),
            DecoratedBox(
                decoration: BoxDecoration(
                    color: fill, borderRadius: BorderRadius.circular(2.5)),
                child: SizedBox(width: max(5, width * f), height: 5)
            ),
        ]))
    }
}
