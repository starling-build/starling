// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// View > Show > Grid Settings: PowerPoint's Grid and Guides dialog. Snap to grid and to other objects, the grid's
// spacing, whether the grid, the drawing guides and the smart guides show. The snap settings, the spacing and the
// guides are the deck's (saved in viewProps.xml, one undo step); showing the grid and smart guides is the session's.

import Flutter
import OfficeText
import FlutterSwiftBridge
import Foundation

final class GridGuidesDialog: StatefulWidget {
    let grid: SlideGridSettings
    let showGrid: Bool
    let smartGuides: Bool
    let slideSize: Size
    let onApply: (SlideGridSettings, _ showGrid: Bool, _ smartGuides: Bool) -> Void
    let onCancel: () -> Void

    init(grid: SlideGridSettings, showGrid: Bool, smartGuides: Bool, slideSize: Size,
         onApply: @escaping (SlideGridSettings, Bool, Bool) -> Void, onCancel: @escaping () -> Void) {
        self.grid = grid; self.showGrid = showGrid; self.smartGuides = smartGuides; self.slideSize = slideSize
        self.onApply = onApply; self.onCancel = onCancel
        super.init()
    }

    override func createState() -> State<StatefulWidget> { GridGuidesDialogState() }
}

final class GridGuidesDialogState: State<StatefulWidget> {
    private var _w: GridGuidesDialog { widget as! GridGuidesDialog }
    private var _g = SlideGridSettings()
    private var _showGrid = false
    private var _smart = true
    private let _spacing = TextEditingController()

    override func initState() {
        super.initState()
        _g = _w.grid
        _showGrid = _w.showGrid
        _smart = _w.smartGuides
        _spacing.text = Self.inches(_g.spacing)
    }

    override func dispose() {
        _spacing.dispose()
        super.dispose()
    }

    /// Points shown as inches, PowerPoint's way: "0.08\"".
    static func inches(_ pt: Double) -> String {
        let v = (pt / 72 * 100).rounded() / 100
        var s = "\(v)"
        if s.hasSuffix(".0") { s.removeLast(2) }
        return s + "\""
    }

    /// A typed spacing in inches ("0.5", "0.5\"", "1/12") as points, or nil when it is outside 0.01 to 2 inches.
    static func parse(_ text: String) -> Double? {
        let t = String(text.filter { $0 != " " && $0 != "\"" && $0 != "i" && $0 != "n" })
        var inch: Double? = nil
        let parts = t.split(separator: "/", omittingEmptySubsequences: false)
        if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b != 0 { inch = a / b }
        else if parts.count == 1 { inch = Double(t) }
        guard let inch else { return nil }
        let pt = inch * 72
        return SlideGridSettings.spacingRange.contains(pt) ? pt : nil
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let caption = fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary)
        func gap(_ h: Double) -> Widget { SizedBox(width: nil, height: h, child: nil) }
        func check(_ id: String, _ label: String, _ on: Bool, _ set: @escaping (Bool) -> Void) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 6), child: Checkbox(
                key: ValueKey(id), checked: on, onChanged: { [weak self] v in self?.setState { set(v ?? false) } },
                content: Text(label)))
        }
        let typed = Self.parse(_spacing.text)
        let preset = SlideGridSettings.spacingPresets.firstIndex { abs($0.1 - (typed ?? -1)) < 0.01 } ?? -1
        let items = [ComboBoxItem<Int>(value: -1, child: Text("Custom"))]
            + SlideGridSettings.spacingPresets.enumerated().map { ComboBoxItem<Int>(value: $0.offset, child: Text($0.element.0)) }
        let page = Column(mainAxisSize: .min, crossAxisAlignment: .start, children: [
            Text("Snap to", style: caption), gap(6),
            check("griddlg.snapGrid", "Snap objects to grid", _g.snapToGrid) { [weak self] v in self?._g.snapToGrid = v },
            check("griddlg.snapObjects", "Snap objects to other objects", _g.snapToObjects) { [weak self] v in self?._g.snapToObjects = v },
            gap(6),
            Text("Grid settings", style: caption), gap(6),
            Row(children: [
                SizedBox(width: 70, height: nil, child: Text("Spacing:")),
                SizedBox(width: 110, height: nil, child: ComboBox<Int>(
                    key: ValueKey("griddlg.preset"), value: preset, items: items,
                    onChanged: { [weak self] i in
                        guard let self, let i, SlideGridSettings.spacingPresets.indices.contains(i) else { return }
                        self.setState { self._spacing.text = Self.inches(SlideGridSettings.spacingPresets[i].1) }
                    })),
                SizedBox(width: 8, height: nil, child: nil),
                SizedBox(width: 80, height: 30, child: PKeyed("griddlg.spacing", FluentTextBox(
                    controller: _spacing, onChanged: { [weak self] _ in self?.setState {} }))),
            ]),
            typed != nil ? gap(6) : Padding(padding: EdgeInsets(left: 0, top: 6, right: 0, bottom: 0),
                                            child: Text("Enter a spacing from 0.01\" to 2\".", style: caption)),
            check("griddlg.showGrid", "Display grid on screen", _showGrid) { [weak self] v in self?._showGrid = v },
            gap(6),
            Text("Guide settings", style: caption), gap(6),
            check("griddlg.showGuides", "Display drawing guides on screen", _g.showGuides) { [weak self] v in
                guard let self else { return }
                self._g.showGuides = v
                if v { self._g.addCentreGuidesIfNone(self._w.slideSize) }
            },
            check("griddlg.smart", "Display smart guides when shapes are aligned", _smart) { [weak self] v in self?._smart = v },
        ])
        return DialogShell(title: "Grid and Guides", page: page, okEnabled: typed != nil, width: 380,
                           onOK: { [weak self] in
                               guard let self, let pt = Self.parse(self._spacing.text) else { return }
                               var g = self._g
                               // Keep the deck's spacing exactly when the shown value was not changed.
                               if Self.inches(pt) != Self.inches(self._w.grid.spacing) { g.spacing = pt } else { g.spacing = self._w.grid.spacing }
                               self._w.onApply(g, self._showGrid, self._smart)
                           },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}

extension SlideGridSettings {
    /// Showing the guides with none set gives one of each through the slide's centre, as PowerPoint does.
    mutating func addCentreGuidesIfNone(_ slide: Size) {
        guard guides.isEmpty else { return }
        guides = [DrawingGuide(vertical: false, at: slide.height / 2), DrawingGuide(vertical: true, at: slide.width / 2)]
    }
}
