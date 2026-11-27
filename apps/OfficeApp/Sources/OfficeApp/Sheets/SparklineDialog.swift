// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Insert → Sparklines: the dialog that makes them (data range, location range), and the one that
// changes the group under the active cell (type, points shown, colours, empty cells, axis).

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

final class SparklineDialog: StatefulWidget {
    let controller: WorkbookController
    /// A kind makes new sparklines; nil changes the group at the active cell.
    let create: SparklineGroup.Kind?
    let onClose: () -> Void
    init(controller: WorkbookController, create: SparklineGroup.Kind?, onClose: @escaping () -> Void) {
        self.controller = controller
        self.create = create
        self.onClose = onClose
        super.init()
    }
    override func createState() -> State<StatefulWidget> { SparklineDialogState() }
}

final class SparklineDialogState: State<StatefulWidget> {
    private var _w: SparklineDialog { widget as! SparklineDialog }
    let data = TextEditingController()
    let location = TextEditingController()
    private var _seeded = false
    private var _problem: String?
    private var _open: String?
    private var _more: String?
    private var _recent = RecentColors()

    private func _create(_ kind: SparklineGroup.Kind) {
        if let p = _w.controller.addSparklines(kind: kind, data: data.text, location: location.text) {
            setState { self._problem = p.message }
        } else { _w.onClose() }
    }

    private func _change(_ f: (inout SparklineGroup) -> Void) {
        _w.controller.updateSparklineGroup(at: _w.controller.active, f)
        setState {}
    }

    private func _pick(_ name: String, _ choice: ColorChoice) {
        if let rgb = choice.resolved(theme: ColorMath.officeTheme) { _recent.use(rgb); _change { $0.setColor(name, rgb: rgb) } }
        setState { self._open = nil; self._more = nil }
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let gap: (Double) -> Widget = { SizedBox(width: nil, height: $0, child: nil) }
        if let kind = _w.create {
            if !_seeded {
                _seeded = true
                data.text = _w.controller.selection.a1
            }
            func line(_ label: String, _ id: String, _ c: TextEditingController, _ hint: String) -> Widget {
                Row(children: [
                    SizedBox(width: 130, height: nil, child: Text(label)),
                    SizedBox(width: 240, height: Chrome.touchFieldHeight, child: FluentTextBox(key: ValueKey(id), controller: c, placeholderText: hint)),
                ])
            }
            var rows: [Widget] = [Text("Choose the data you want"), gap(6), line("Data Range:", "spark-data", data, "A1:D3"), gap(10),
                                  Text("Choose where the sparklines will be placed"), gap(6), line("Location Range:", "spark-loc", location, "F1:F3")]
            if let p = _problem { rows.append(gap(8)); rows.append(Text(p, style: fluent.typography.caption)) }
            let title = kind == .line ? "Create Sparklines (Line)" : kind == .column ? "Create Sparklines (Column)" : "Create Sparklines (Win/Loss)"
            return DialogShell(title: title, page: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: rows),
                               okLabel: "OK", cancelLabel: "Cancel", width: 460,
                               onOK: { [weak self] in self?._create(kind) }, onCancel: _w.onClose)
        }
        guard let (gi, _) = _w.controller.sparklineAt(_w.controller.active) else {
            return DialogShell(title: "Sparklines", page: Text("Select a cell that has a sparkline."), okLabel: "Close", cancelLabel: "Close", width: 380,
                               onOK: _w.onClose, onCancel: _w.onClose)
        }
        let g = _w.controller.sparklineGroups()[gi]
        func toggle(_ label: String, _ key: String) -> Widget {
            Chrome.textToggle(label, g.flag(key), fluent, style: fluent.typography.caption) { [weak self] in self?._change { $0.set(key, !$0.flag(key)) } }
        }
        func pick(_ label: String, _ on: Bool, _ f: @escaping (inout SparklineGroup) -> Void) -> Widget {
            Chrome.textToggle(label, on, fluent, style: fluent.typography.caption) { [weak self] in self?._change(f) }
        }
        let look = _w.controller.sparklineLook(_w.controller.active)
        func colorRow(_ title: String, _ name: String) -> Widget {
            var parts: [Widget] = [Row(children: [
                SizedBox(width: 150, height: nil, child: Text(title)),
                SizedBox(width: 60, height: nil, child: Chrome.swatch(Color(Int64(0xFF00_0000) | Int64(look?.colors[name] ?? 0)), fluent)),
                Chrome.textToggle("Colour", _open == name, fluent) { [weak self] in self?.setState { self?._open = self?._open == name ? nil : name } },
            ])]
            if _open == name {
                parts.append(ColorPicker(recent: _recent.list, automaticLabel: nil, noneLabel: nil,
                                         onChoose: { [weak self] c in self?._pick(name, c) },
                                         onMore: { [weak self] in self?.setState { self?._more = name } }))
            }
            return Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: parts)
        }
        var rows: [Widget] = [
            Text("Type"),
            Row(children: [pick("Line", g.kind == .line) { $0.kind = .line }, pick("Column", g.kind == .column) { $0.kind = .column },
                           pick("Win/Loss", g.kind == .winLoss) { $0.kind = .winLoss }]),
            gap(8), Text("Show"),
            Row(children: [toggle("High Point", "high"), toggle("Low Point", "low"), toggle("Negative Points", "negative")]),
            Row(children: [toggle("First Point", "first"), toggle("Last Point", "last"), toggle("Markers", "markers")]),
            gap(8), Text("Empty cells"),
            Row(children: [pick("Gaps", g.emptyAs == "gap") { $0.emptyAs = "gap" }, pick("Zero", g.emptyAs == "zero") { $0.emptyAs = "zero" },
                           pick("Connect", g.emptyAs == "span") { $0.emptyAs = "span" }]),
            gap(8), Text("Axis"),
            Row(children: [toggle("Show Axis", "displayXAxis"),
                           pick("Same height for all", g.minType == "group") {
                               let on = $0.minType != "group"
                               $0.attrs["minAxisType"] = on ? "group" : nil; $0.attrs["maxAxisType"] = on ? "group" : nil
                           }]),
            gap(8), Text("Colours"),
            colorRow("Sparkline", "colorSeries"), colorRow("Negative points", "colorNegative"), colorRow("Markers", "colorMarkers"),
            colorRow("High point", "colorHigh"), colorRow("Low point", "colorLow"), colorRow("First point", "colorFirst"), colorRow("Last point", "colorLast"),
            gap(8),
            Row(children: [Chrome.textToggle("Clear Selected Sparklines", false, fluent) { [weak self] in
                guard let self else { return }
                self._w.controller.clearSparklines(in: self._w.controller.selection)
                self._w.onClose()
            }]),
        ]
        let dialog = DialogShell(title: "Sparkline Tools", page: SizedBox(width: nil, height: 420, child: SingleChildScrollView(child: Column(
                               mainAxisSize: .min, crossAxisAlignment: .stretch, children: rows))),
                           okLabel: "Close", cancelLabel: "Close", width: 480, onOK: _w.onClose, onCancel: _w.onClose)
        guard let name = _more else { return dialog }
        return Stack(children: [
            dialog,
            Positioned(left: 0, top: 0, right: 0, bottom: 0, child: CustomColorDialog(
                initial: look?.colors[name] ?? 0,
                onOK: { [weak self] rgb in self?._pick(name, .rgb(rgb)) },
                onCancel: { [weak self] in self?.setState { self?._more = nil } })),
        ])
    }
}
