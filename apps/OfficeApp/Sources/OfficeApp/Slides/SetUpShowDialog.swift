// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Slide Show → Set Up Slide Show, and Custom Shows: how the show runs
// (presented by a speaker, browsed in a window, or a kiosk; loop until Esc;
// all slides, a range or a custom show; use timings) and the named lists of
// slides a custom show plays in their own order.

import Flutter
import OfficeText
import FlutterSwiftBridge
import Foundation

private func _sheet(_ fluent: FluentThemeData, width: Double, _ card: Widget) -> Widget {
    // A modal sheet: the dimmed window behind it takes no clicks.
    Stack(children: [
        Positioned(left: 0, top: 0, right: 0, bottom: 0, child: Listener(
            behavior: .opaque,
            child: ColoredBox(color: Color(0x33000000), child: SizedBox(expand: ())))),
        Positioned(left: 0, top: 0, right: 0, bottom: 0, child: Center(child: SizedBox(width: width, height: nil, child: DecoratedBox(
            decoration: BoxDecoration(color: OfficeAppearance.surface(fluent),
                                      border: Border.all(color: fluent.resources.controlStrokeColorDefault, width: 1),
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: [BoxShadow(color: Color(0x40000000), offset: Offset(0, 8), blurRadius: 24)]),
            child: Padding(padding: EdgeInsets(all: 24), child: KeyboardRegion(name: "dialog", modal: true, child: card)))))),
    ])
}

private func _gap(_ h: Double) -> Widget { SizedBox(width: nil, height: h, child: nil) }

final class SetUpShowDialog: StatefulWidget {
    let initial: ShowSettings
    let slideCount: Int
    let shows: [CustomShow]
    let onOK: (ShowSettings) -> Void
    let onCancel: () -> Void

    init(initial: ShowSettings, slideCount: Int, shows: [CustomShow],
         onOK: @escaping (ShowSettings) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial
        self.slideCount = slideCount
        self.shows = shows
        self.onOK = onOK
        self.onCancel = onCancel
        super.init()
    }

    override func createState() -> State<StatefulWidget> { SetUpShowDialogState() }
}

final class SetUpShowDialogState: State<StatefulWidget> {
    private var _w: SetUpShowDialog { widget as! SetUpShowDialog }
    private var _s = ShowSettings()
    /// 0 all, 1 from-to, 2 custom show.
    private var _rangeKind = 0
    private var _customId = -1
    private let _from = TextEditingController()
    private let _to = TextEditingController()

    override func initState() {
        super.initState()
        _s = _w.initial
        _from.text = "1"
        _to.text = "\(_w.slideCount)"
        switch _s.range {
        case .all: _rangeKind = 0
        case .slides(let a, let b): _rangeKind = 1; _from.text = "\(a)"; _to.text = "\(b)"
        case .custom(let id): _rangeKind = 2; _customId = id
        }
        if _customId < 0 { _customId = _w.shows.first?.id ?? -1 }
    }

    override func dispose() {
        _from.dispose()
        _to.dispose()
        super.dispose()
    }

    /// The settings the dialog now describes. A custom range with no show to play falls back to all slides.
    func result() -> ShowSettings {
        var s = _s
        switch _rangeKind {
        case 1:
            let n = _w.slideCount
            let a = max(1, min(n, Int(_from.text.trimmingWhitespace()) ?? 1))
            let b = max(1, min(n, Int(_to.text.trimmingWhitespace()) ?? n))
            s.range = .slides(from: min(a, b), to: max(a, b))
        case 2: s.range = _customId >= 0 ? .custom(_customId) : .all
        default: s.range = .all
        }
        if s.kind == .kiosk { s.loop = true }
        return s
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let caption = fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary)
        func kind(_ label: String, _ k: ShowSettings.Kind) -> Widget {
            RadioButton<ShowSettings.Kind>(value: k, groupValue: _s.kind,
                                           onChanged: { [weak self] _ in self?.setState { self?._s.kind = k } },
                                           content: Text(label))
        }
        func range(_ label: String, _ n: Int) -> Widget {
            RadioButton<Int>(value: n, groupValue: _rangeKind,
                             onChanged: { [weak self] _ in self?.setState { self?._rangeKind = n } }, content: Text(label))
        }
        let kiosk = _s.kind == .kiosk
        let customs: Widget = _w.shows.isEmpty
            ? Padding(padding: EdgeInsets(left: 28, top: 4, right: 0, bottom: 0), child: Text("No custom shows yet.", style: caption))
            : Padding(padding: EdgeInsets(left: 28, top: 4, right: 0, bottom: 0), child: Column(
                crossAxisAlignment: .start, children: _w.shows.map { cs in
                    RadioButton<Int>(value: cs.id, groupValue: _customId,
                                     onChanged: { [weak self] _ in self?.setState { self?._customId = cs.id; self?._rangeKind = 2 } },
                                     content: Text(cs.name))
                }))
        let card = Column(mainAxisSize: .min, crossAxisAlignment: .start, children: [
            Text("Set Up Show", style: fluent.typography.subtitle),
            _gap(14),
            Text("Show type", style: caption),
            _gap(6),
            kind("Presented by a speaker (full screen)", .presenter),
            _gap(4),
            kind("Browsed by an individual (window)", .window),
            _gap(4),
            kind("Browsed at a kiosk (full screen)", .kiosk),
            _gap(14),
            Text("Show options", style: caption),
            _gap(6),
            Checkbox(checked: _s.loop || kiosk, onChanged: kiosk ? nil : { [weak self] v in self?.setState { self?._s.loop = v ?? false } },
                     content: Text("Loop continuously until 'Esc'")),
            _gap(14),
            Text("Show slides", style: caption),
            _gap(6),
            range("All", 0),
            _gap(4),
            Row(children: [
                range("From:", 1),
                SizedBox(width: 10, height: nil, child: nil),
                SizedBox(width: 60, height: Chrome.fieldHeight, child: FluentTextBox(controller: _from, enabled: _rangeKind == 1)),
                SizedBox(width: 10, height: nil, child: nil),
                Text("To:"),
                SizedBox(width: 10, height: nil, child: nil),
                SizedBox(width: 60, height: Chrome.fieldHeight, child: FluentTextBox(controller: _to, enabled: _rangeKind == 1)),
            ]),
            _gap(4),
            range("Custom show:", 2),
            customs,
            _gap(14),
            Text("Advance slides", style: caption),
            _gap(6),
            RadioButton<Bool>(value: false, groupValue: _s.useTimings,
                              onChanged: { [weak self] _ in self?.setState { self?._s.useTimings = false } },
                              content: Text("Manually")),
            _gap(4),
            RadioButton<Bool>(value: true, groupValue: _s.useTimings,
                              onChanged: { [weak self] _ in self?.setState { self?._s.useTimings = true } },
                              content: Text("Using timings, if present")),
            _gap(20),
            Row(mainAxisAlignment: .end, children: [
                FilledButton(onPressed: { [weak self] in
                    guard let self else { return }
                    self._w.onOK(self.result())
                }, child: Text("OK")),
                SizedBox(width: 8, height: nil, child: nil),
                Button(onPressed: { [weak self] in self?._w.onCancel() }, child: Text("Cancel")),
            ]),
        ])
        return _sheet(fluent, width: 440, card)
    }
}

/// Custom Shows: the list (New, Edit, Delete, Show) and the editor of one show.
final class CustomShowsDialog: StatefulWidget {
    let shows: [CustomShow]
    /// Slide ids with their titles, in deck order.
    let slides: [(id: Int, title: String)]
    /// The shows as the dialog leaves them (Close).
    let onClose: ([CustomShow]) -> Void
    /// Play one of them: the shows are saved first.
    let onPlay: ([CustomShow], Int) -> Void

    init(shows: [CustomShow], slides: [(id: Int, title: String)],
         onClose: @escaping ([CustomShow]) -> Void, onPlay: @escaping ([CustomShow], Int) -> Void) {
        self.shows = shows
        self.slides = slides
        self.onClose = onClose
        self.onPlay = onPlay
        super.init()
    }

    override func createState() -> State<StatefulWidget> { CustomShowsDialogState() }
}

final class CustomShowsDialogState: State<StatefulWidget> {
    private var _w: CustomShowsDialog { widget as! CustomShowsDialog }
    private(set) var _shows: [CustomShow] = []
    private var _picked = -1
    /// The show being edited, with its list-position (nil: a new one).
    private(set) var _draft: CustomShow? = nil
    private var _draftIsNew = false
    private var _draftPick = -1
    private let _name = TextEditingController()

    private var _keys: Int?

    override func initState() {
        super.initState()
        _shows = _w.shows
        _picked = _shows.isEmpty ? -1 : 0
        // Esc is Cancel in Define Custom Show and Close in the list, as in PowerPoint (the list's edits are kept).
        _keys = FocusManager.instance.addKeyInterceptor { [weak self] key in
            if KeyboardTraversal.shared.handle(key) { return true }
            guard let self, key.type == .down, key.logical == 0x1_0000_001B || key.logical == 0xFF1B else { return false }
            if self._draft != nil { self.setState { self._draft = nil } } else { self._w.onClose(self._shows) }
            return true
        }
    }

    override func dispose() {
        if let k = _keys { FocusManager.instance.removeKeyInterceptor(k) }
        _name.dispose()
        super.dispose()
    }

    private func _title(_ id: Int) -> String {
        guard let n = _w.slides.firstIndex(where: { $0.id == id }) else { return "(deleted slide)" }
        let t = _w.slides[n].title
        return "\(n + 1). " + (t.isEmpty ? "Slide \(n + 1)" : t)
    }

    private func _row(_ text: String, selected: Bool, _ fluent: FluentThemeData, onTap: @escaping () -> Void) -> Widget {
        GestureDetector(onTap: onTap, child: DecoratedBox(
            decoration: BoxDecoration(color: selected ? fluent.accentColor.defaultBrushFor(fluent.brightness).withOpacity(0.25) : Color(0x00000000)),
            child: Padding(padding: EdgeInsets(left: 8, top: 4, right: 8, bottom: 4),
                           child: Row(children: [Expanded(child: Text(text))]))))
    }

    private func _list(_ rows: [Widget], height: Double = 190) -> Widget {
        SizedBox(width: nil, height: height, child: SingleChildScrollView(child: Column(crossAxisAlignment: .stretch, children: rows)))
    }

    func beginEdit(new: Bool) {
        if new {
            var id = 1
            while _shows.contains(where: { $0.id == id }) { id += 1 }
            _draft = CustomShow(id: id, name: "Custom Show \(_shows.count + 1)", slides: [])
        } else if _picked >= 0 {
            _draft = _shows[_picked]
        } else { return }
        _draftIsNew = new
        _draftPick = -1
        _name.text = _draft?.name ?? ""
        setState {}
    }

    func addToDraft(slide id: Int) { _draft?.slides.append(id); _draftPick = (_draft?.slides.count ?? 1) - 1; setState {} }

    func moveDraft(_ delta: Int) {
        guard var d = _draft, d.slides.indices.contains(_draftPick), d.slides.indices.contains(_draftPick + delta) else { return }
        d.slides.swapAt(_draftPick, _draftPick + delta)
        _draft = d
        _draftPick += delta
        setState {}
    }

    func removeFromDraft() {
        guard var d = _draft, d.slides.indices.contains(_draftPick) else { return }
        d.slides.remove(at: _draftPick)
        _draft = d
        _draftPick = min(_draftPick, d.slides.count - 1)
        setState {}
    }

    func acceptDraft() {
        guard var d = _draft else { return }
        let name = _name.text.trimmingWhitespace()
        d.name = name.isEmpty ? "Custom Show" : name
        if _draftIsNew { _shows.append(d); _picked = _shows.count - 1 }
        else if _shows.indices.contains(_picked) { _shows[_picked] = d }
        _draft = nil
        setState {}
    }

    func delete() {
        guard _shows.indices.contains(_picked) else { return }
        _shows.remove(at: _picked)
        _picked = _shows.isEmpty ? -1 : min(_picked, _shows.count - 1)
        setState {}
    }

    func copy() {
        guard _shows.indices.contains(_picked) else { return }
        var c = _shows[_picked]
        var id = 1
        while _shows.contains(where: { $0.id == id }) { id += 1 }
        c.id = id
        c.name += " (copy)"
        _shows.append(c)
        _picked = _shows.count - 1
        setState {}
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let caption = fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary)
        func btn(_ label: String, enabled: Bool = true, _ f: @escaping () -> Void) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 6),
                    child: SizedBox(width: 90, height: nil, child: Button(onPressed: enabled ? f : nil, child: Text(label))))
        }
        if let d = _draft {
            let all = _list(_w.slides.map { s in
                _row(_title(s.id), selected: false, fluent) { [weak self] in self?.addToDraft(slide: s.id) }
            })
            let chosen = _list(d.slides.enumerated().map { (i, id) in
                _row(_title(id), selected: i == _draftPick, fluent) { [weak self] in self?.setState { self?._draftPick = i } }
            })
            let card = Column(mainAxisSize: .min, crossAxisAlignment: .start, children: [
                Text("Define Custom Show", style: fluent.typography.subtitle),
                _gap(12),
                Row(children: [
                    Text("Slide show name:"),
                    SizedBox(width: 10, height: nil, child: nil),
                    SizedBox(width: 280, height: Chrome.fieldHeight, child: FluentTextBox(controller: _name)),
                ]),
                _gap(12),
                Row(crossAxisAlignment: .start, children: [
                    SizedBox(width: 250, height: nil, child: Column(crossAxisAlignment: .start, children: [
                        Text("Slides in presentation (click to add):", style: caption), _gap(4), all])),
                    SizedBox(width: 12, height: nil, child: nil),
                    SizedBox(width: 250, height: nil, child: Column(crossAxisAlignment: .start, children: [
                        Text("Slides in custom show:", style: caption), _gap(4), chosen])),
                    SizedBox(width: 12, height: nil, child: nil),
                    Column(children: [
                        btn("Move Up", enabled: _draftPick > 0) { [weak self] in self?.moveDraft(-1) },
                        btn("Move Down", enabled: _draftPick >= 0 && _draftPick < d.slides.count - 1) { [weak self] in self?.moveDraft(1) },
                        btn("Remove", enabled: _draftPick >= 0) { [weak self] in self?.removeFromDraft() },
                    ]),
                ]),
                _gap(16),
                Row(mainAxisAlignment: .end, children: [
                    FilledButton(onPressed: { [weak self] in self?.acceptDraft() }, child: Text("OK")),
                    SizedBox(width: 8, height: nil, child: nil),
                    Button(onPressed: { [weak self] in self?.setState { self?._draft = nil } }, child: Text("Cancel")),
                ]),
            ])
            return _sheet(fluent, width: 700, card)
        }
        let rows = _shows.enumerated().map { (i, cs) in
            _row(cs.name, selected: i == _picked, fluent) { [weak self] in self?.setState { self?._picked = i } }
        }
        let have = _shows.indices.contains(_picked)
        let card = Column(mainAxisSize: .min, crossAxisAlignment: .start, children: [
            Text("Custom Shows", style: fluent.typography.subtitle),
            _gap(12),
            Row(crossAxisAlignment: .start, children: [
                SizedBox(width: 280, height: nil, child: _shows.isEmpty
                    ? Text("No custom shows yet. New makes one.", style: caption) : _list(rows)),
                SizedBox(width: 12, height: nil, child: nil),
                Column(children: [
                    btn("New...") { [weak self] in self?.beginEdit(new: true) },
                    btn("Edit...", enabled: have) { [weak self] in self?.beginEdit(new: false) },
                    btn("Remove", enabled: have) { [weak self] in self?.delete() },
                    btn("Copy", enabled: have) { [weak self] in self?.copy() },
                ]),
            ]),
            _gap(16),
            Row(mainAxisAlignment: .end, children: [
                Button(onPressed: have ? { [weak self] in
                    guard let self else { return }
                    self._w.onPlay(self._shows, self._shows[self._picked].id)
                } : nil, child: Text("Show")),
                SizedBox(width: 8, height: nil, child: nil),
                FilledButton(onPressed: { [weak self] in
                    guard let self else { return }
                    self._w.onClose(self._shows)
                }, child: Text("Close")),
            ]),
        ])
        return _sheet(fluent, width: 440, card)
    }
}

/// Rename Section / Add Section: one name box.
final class SectionNameDialog: StatefulWidget {
    let title: String
    let initial: String
    let onOK: (String) -> Void
    let onCancel: () -> Void
    init(title: String, initial: String, onOK: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.title = title; self.initial = initial; self.onOK = onOK; self.onCancel = onCancel
        super.init()
    }
    override func createState() -> State<StatefulWidget> { SectionNameDialogState() }
}

final class SectionNameDialogState: State<StatefulWidget> {
    private var _w: SectionNameDialog { widget as! SectionNameDialog }
    private let _name = TextEditingController()

    override func initState() {
        super.initState()
        _name.text = _w.initial
    }

    override func dispose() {
        _name.dispose()
        super.dispose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let card = Column(mainAxisSize: .min, crossAxisAlignment: .start, children: [
            Text(_w.title, style: fluent.typography.subtitle),
            _gap(12),
            Row(children: [
                Text("Section name:"),
                SizedBox(width: 10, height: nil, child: nil),
                SizedBox(width: 240, height: Chrome.fieldHeight, child: FluentTextBox(controller: _name)),
            ]),
            _gap(16),
            Row(mainAxisAlignment: .end, children: [
                FilledButton(onPressed: { [weak self] in
                    guard let self else { return }
                    self._w.onOK(self._name.text.trimmingWhitespace())
                }, child: Text("OK")),
                SizedBox(width: 8, height: nil, child: nil),
                Button(onPressed: { [weak self] in self?._w.onCancel() }, child: Text("Cancel")),
            ]),
        ])
        return _sheet(fluent, width: 400, card)
    }
}
