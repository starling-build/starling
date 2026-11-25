// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-SH-1: Tab Color and Move or Copy, on the shared dialog.
import Flutter
import FlutterSwiftBridge

/// Tab Color: pick one of the swatches, or none.
final class TabColorPanel: StatefulWidget {
    let sheetName: String
    let current: UInt32?
    let onPick: (UInt32?) -> Void
    let onClose: () -> Void
    init(sheetName: String, current: UInt32?, onPick: @escaping (UInt32?) -> Void, onClose: @escaping () -> Void) {
        self.sheetName = sheetName; self.current = current; self.onPick = onPick; self.onClose = onClose
        super.init()
    }
    override func createState() -> State<StatefulWidget> { TabColorPanelState() }
}

final class TabColorPanelState: State<StatefulWidget> {
    private var _w: TabColorPanel { widget as! TabColorPanel }
    var pick: UInt32?
    private var _started = false

    override func build(_ context: any BuildContext) -> Widget {
        if !_started { _started = true; pick = _w.current }
        let fluent = FluentTheme.of(context)
        let content = Padding(padding: EdgeInsets(left: 16, top: 8, right: 16, bottom: 8), child: Column(
            mainAxisSize: .min, crossAxisAlignment: .start, children: [
                Text("Tab colour for “\(_w.sheetName)”", style: fluent.typography.bodyStrong),
                SizedBox(key: ValueKey("tabcolor-none"), width: nil, height: 28, child: FlatButton(
                    child: Padding(padding: EdgeInsets(left: 8, top: 0, right: 8, bottom: 0), child: Text("No colour")),
                    checked: pick == nil, width: nil, height: 28, alignLeft: true,
                    action: { [weak self] in self?.setState { self?.pick = nil } })),
                Wrap(spacing: 4, runSpacing: 4, children: FormatCellsDialog.swatches.map { name, rgb in
                    SizedBox(key: ValueKey("tabcolor-\(name)"), width: 28, height: 28, child: FlatButton(
                        child: DecoratedBox(decoration: BoxDecoration(color: Color(Int64(0xFF000000 | rgb))), child: SizedBox(width: 18, height: 18)),
                        tip: name, checked: pick == rgb, action: { [weak self] in self?.setState { self?.pick = rgb } }))
                }),
            ]))
        return DialogShell(title: "Tab Color", page: content, width: 360,
                           onOK: { [weak self] in guard let self else { return }; self._w.onPick(self.pick); self._w.onClose() },
                           onCancel: _w.onClose)
    }
}

/// Move or Copy: the sheet goes before the chosen sheet (or to the end), as a move or a copy.
final class MoveCopyPanel: StatefulWidget {
    let sheetName: String
    let sheets: [String]            // visible and hidden, in file order
    let canCopy: String?            // why a copy is refused, or nil
    let onDone: (_ before: Int, _ copy: Bool) -> Void
    let onClose: () -> Void
    init(sheetName: String, sheets: [String], canCopy: String?, onDone: @escaping (Int, Bool) -> Void, onClose: @escaping () -> Void) {
        self.sheetName = sheetName; self.sheets = sheets; self.canCopy = canCopy; self.onDone = onDone; self.onClose = onClose
        super.init()
    }
    override func createState() -> State<StatefulWidget> { MoveCopyPanelState() }
}

final class MoveCopyPanelState: State<StatefulWidget> {
    private var _w: MoveCopyPanel { widget as! MoveCopyPanel }
    var before: Int?
    var copy = false

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let n = _w.sheets.count
        let at = before ?? n
        func row(_ k: Int, _ label: String) -> Widget {
            SizedBox(key: ValueKey("movecopy-\(k)"), width: nil, height: 26, child: FlatButton(
                child: Padding(padding: EdgeInsets(left: 8, top: 0, right: 8, bottom: 0), child: Text(label)),
                checked: at == k, width: nil, height: 26, alignLeft: true,
                action: { [weak self] in self?.setState { self?.before = k } }))
        }
        var rows: [Widget] = _w.sheets.enumerated().map { row($0.offset, $0.element) }
        rows.append(row(n, "(move to end)"))
        var kids: [Widget] = [
            Text("Move or copy “\(_w.sheetName)”", style: fluent.typography.bodyStrong),
            Text("Before sheet:"),
            SizedBox(width: nil, height: 180, child: SingleChildScrollView(child: Column(crossAxisAlignment: .start, children: rows))),
        ]
        if let why = _w.canCopy {
            kids.append(Text("A copy is not possible yet: the sheet has \(why)."))
        } else {
            kids.append(Checkbox(key: ValueKey("movecopy-copy"), checked: copy,
                                 onChanged: { [weak self] _ in self?.setState { self?.copy.toggle() } },
                                 content: Text("Create a copy")))
        }
        let content = Padding(padding: EdgeInsets(left: 16, top: 8, right: 16, bottom: 8),
                              child: Column(mainAxisSize: .min, crossAxisAlignment: .start, children: kids))
        return DialogShell(title: "Move or Copy", page: content, width: 380,
                           onOK: { [weak self] in guard let self else { return }; self._w.onDone(self.before ?? n, self.copy); self._w.onClose() },
                           onCancel: _w.onClose)
    }
}

// MARK: Dragging a tab

/// Where a dropped tab goes: the tab under the pointer, or the end of the row if it is dropped past the last tab.
enum SheetTabDrag {
    /// `spans`: the visible tabs' (book index, left, right) in screen order; `x` the pointer's x. Returns the book index to move to.
    static func target(spans: [(index: Int, left: Double, right: Double)], x: Double) -> Int? {
        guard let first = spans.first, let last = spans.last else { return nil }
        if x < first.left { return first.index }
        if x >= last.right { return last.index }
        return spans.first { x >= $0.left && x < $0.right }?.index
    }
    /// A press that moves this far sideways (in logical pixels) is a drag, not a click.
    static let threshold = 6.0
}

/// Remembers where each tab is on screen, so a drop can find the tab under it.
final class SheetTabProbes {
    private var boxes: [Int: () -> (Double, Double)?] = [:]
    func set(_ i: Int, _ read: @escaping () -> (Double, Double)?) { boxes[i] = read }
    func spans(_ visible: [Int]) -> [(index: Int, left: Double, right: Double)] {
        visible.compactMap { i in boxes[i]?().map { (i, $0.0, $0.1) } }
    }
}

final class SheetTabProbe: StatefulWidget {
    let index: Int
    let probes: SheetTabProbes
    let child: Widget
    init(index: Int, probes: SheetTabProbes, child: Widget) { self.index = index; self.probes = probes; self.child = child; super.init() }
    override func createState() -> State<StatefulWidget> { SheetTabProbeState() }
}

final class SheetTabProbeState: State<StatefulWidget> {
    override func build(_ context: any BuildContext) -> Widget {
        let w = widget as! SheetTabProbe
        w.probes.set(w.index) { [weak self] in
            guard let rb = self?.context?.findRenderObject() as? RenderBox else { return nil }
            let o = rb.localToGlobal(Offset(0, 0))
            return (Double(o.dx), Double(o.dx + rb.size.width))
        }
        return w.child
    }
}
