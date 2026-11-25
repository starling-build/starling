// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-CE-3c: Formulas → Create from Selection. Each label in the top row, left column, bottom row or right
// column names the cells beside it, as Excel does. One undo step.

import Flutter
import FlutterSwiftBridge
import Foundation

struct NameEdges: Equatable {
    var top = false, left = false, bottom = false, right = false
    var any: Bool { top || left || bottom || right }
}

extension WorkbookController {
    /// Excel's guess: the top row when it holds text, else the left column when it does.
    var defaultNameEdges: NameEdges {
        var e = NameEdges()
        let r = selection, ws = sheet
        func text(_ a: CellAddress) -> Bool { if case .text? = ws.cells[a]?.value { return true } else { return false } }
        if r.rows > 1, (r.left ... r.right).contains(where: { text(CellAddress(row: r.top, col: $0)) }) { e.top = true }
        else if r.cols > 1, (r.top ... r.bottom).contains(where: { text(CellAddress(row: $0, col: r.left)) }) { e.left = true }
        return e
    }

    /// A label turned into a legal name: spaces and punctuation become `_`, a leading digit gets one in front.
    static func nameFromLabel(_ label: String) -> String? {
        var out = ""
        for ch in label.trimmingWhitespace() {
            if ch.isLetter || ch.isNumber || ch == "_" || ch == "." || ch == "\\" { out.append(ch) } else { out.append("_") }
        }
        guard !out.isEmpty, out.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        if let f = out.first, !(f.isLetter || f == "_" || f == "\\") { out = "_" + out }
        return checkName(out) == nil ? out : (checkName("_" + out) == nil ? "_" + out : nil)
    }

    private func _absRef(_ a: CellAddress, _ b: CellAddress) -> String {
        func abs(_ a: CellAddress) -> String { "$" + CellAddress.columnName(a.col) + "$" + String(a.row + 1) }
        let sn = book.sheets[activeSheet].name
        let q = sn.contains(where: { !($0.isLetter || $0.isNumber || $0 == "_") }) ? "'" + sn.replacingAll("'", with: "''") + "'" : sn
        return q + "!" + (a == b ? abs(a) : abs(a) + ":" + abs(b))
    }

    /// Makes the names. Returns how many were made and how many were skipped (the name was already taken, or
    /// the label could not be a name).
    @discardableResult
    func createNames(from edges: NameEdges) -> (made: Int, skipped: Int) {
        let r = selection, ws = sheet
        var plan: [(String, String)] = []
        var skipped = 0
        func label(_ a: CellAddress) -> String? { ws.cells[a].flatMap { c in c.input.isEmpty ? nil : c.input } }
        func add(_ a: CellAddress, _ from: CellAddress, _ to: CellAddress) {
            guard from.row <= to.row, from.col <= to.col else { return }
            guard let l = label(a), let n = Self.nameFromLabel(l) else { if label(a) != nil { skipped += 1 }; return }
            plan.append((n, _absRef(from, to)))
        }
        if edges.top, r.rows > (edges.bottom ? 2 : 1) {
            let lo = r.top + 1, hi = edges.bottom ? r.bottom - 1 : r.bottom
            for col in (edges.left ? r.left + 1 : r.left) ... (edges.right ? r.right - 1 : r.right) {
                add(CellAddress(row: r.top, col: col), CellAddress(row: lo, col: col), CellAddress(row: hi, col: col))
            }
        }
        if edges.bottom, r.rows > (edges.top ? 2 : 1) {
            let lo = edges.top ? r.top + 1 : r.top, hi = r.bottom - 1
            for col in (edges.left ? r.left + 1 : r.left) ... (edges.right ? r.right - 1 : r.right) {
                add(CellAddress(row: r.bottom, col: col), CellAddress(row: lo, col: col), CellAddress(row: hi, col: col))
            }
        }
        if edges.left, r.cols > (edges.right ? 2 : 1) {
            let lo = r.left + 1, hi = edges.right ? r.right - 1 : r.right
            for row in (edges.top ? r.top + 1 : r.top) ... (edges.bottom ? r.bottom - 1 : r.bottom) {
                add(CellAddress(row: row, col: r.left), CellAddress(row: row, col: lo), CellAddress(row: row, col: hi))
            }
        }
        if edges.right, r.cols > (edges.left ? 2 : 1) {
            let lo = edges.left ? r.left + 1 : r.left, hi = r.right - 1
            for row in (edges.top ? r.top + 1 : r.top) ... (edges.bottom ? r.bottom - 1 : r.bottom) {
                add(CellAddress(row: row, col: r.right), CellAddress(row: row, col: lo), CellAddress(row: row, col: hi))
            }
        }
        var fresh: [(String, String)] = []
        for (n, ref) in plan {
            if book.names[n.uppercased()] != nil || fresh.contains(where: { $0.0.uppercased() == n.uppercased() }) { skipped += 1 } else { fresh.append((n, ref)) }
        }
        if fresh.isEmpty { return (0, skipped) }
        structural {
            for (n, ref) in fresh { book.names[n.uppercased()] = ref; book.nameSpellings[n.uppercased()] = n }
        }
        return (fresh.count, skipped)
    }
}

final class CreateNamesDialog: StatefulWidget {
    let controller: WorkbookController
    let onClose: () -> Void
    init(controller: WorkbookController, onClose: @escaping () -> Void) {
        self.controller = controller
        self.onClose = onClose
        super.init()
    }
    override func createState() -> State<StatefulWidget> { CreateNamesDialogState() }
}

final class CreateNamesDialogState: State<StatefulWidget> {
    private var _w: CreateNamesDialog { widget as! CreateNamesDialog }
    private(set) var edges = NameEdges()
    private(set) var message = ""
    private var _seeded = false

    func set(_ edit: (inout NameEdges) -> Void) { edit(&edges); message = ""; setState {} }

    func apply() {
        guard edges.any else { message = "Pick where the labels are."; setState {}; return }
        let c = _w.controller
        let out = c.createNames(from: edges)
        if out.made == 0 { message = "No names were made: the labels are not usable or the names already exist."; setState {}; return }
        c.onCommand?(.status("Made \(out.made) name\(out.made == 1 ? "" : "s")" + (out.skipped > 0 ? "; skipped \(out.skipped)." : ".")))
        _w.onClose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        if !_seeded { _seeded = true; edges = _w.controller.defaultNameEdges }
        let fluent = FluentTheme.of(context)
        let gap: (Double) -> Widget = { SizedBox(width: nil, height: $0, child: nil) }
        let rows: [Widget] = [
            Text("Create names from values in the:", style: fluent.typography.body), gap(6),
            Checkbox(key: ValueKey("names-top"), checked: edges.top, onChanged: { [weak self] v in self?.set { $0.top = v ?? false } }, content: Text("Top row")),
            Checkbox(key: ValueKey("names-left"), checked: edges.left, onChanged: { [weak self] v in self?.set { $0.left = v ?? false } }, content: Text("Left column")),
            Checkbox(key: ValueKey("names-bottom"), checked: edges.bottom, onChanged: { [weak self] v in self?.set { $0.bottom = v ?? false } }, content: Text("Bottom row")),
            Checkbox(key: ValueKey("names-right"), checked: edges.right, onChanged: { [weak self] v in self?.set { $0.right = v ?? false } }, content: Text("Right column")),
            gap(6), Text(message, style: fluent.typography.caption?.copyWith(color: Color(0xFFC42B1C))),
        ]
        return DialogShell(title: "Create Names from Selection", page: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: rows),
                           okLabel: "OK", cancelLabel: "Cancel", width: 340,
                           onOK: { [weak self] in self?.apply() }, onCancel: _w.onClose)
    }
}
