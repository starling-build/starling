// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Design → Slide Size → Custom Slide Size: PowerPoint's dialog. A preset or a width and height in inches, and
// what to do with the content already on the slides: Maximize or Ensure Fit.

import Flutter
import OfficeText
import FlutterSwiftBridge
import Foundation

final class SlideSizeDialog: StatefulWidget {
    let size: Size
    let onApply: (Size, DeckController.SlideScaling) -> Void
    let onCancel: () -> Void

    init(size: Size, onApply: @escaping (Size, DeckController.SlideScaling) -> Void, onCancel: @escaping () -> Void) {
        self.size = size
        self.onApply = onApply
        self.onCancel = onCancel
        super.init()
    }

    override func createState() -> State<StatefulWidget> { SlideSizeDialogState() }
}

final class SlideSizeDialogState: State<StatefulWidget> {
    /// The sizes PowerPoint lists, in inches.
    static let presets: [(name: String, width: Double, height: Double)] = [
        ("Standard (4:3)", 10, 7.5), ("Widescreen (16:9)", 40.0 / 3, 7.5), ("Letter Paper (8.5x11 in)", 10, 7.5),
        ("A4 Paper (210x297 mm)", 10.833, 7.5), ("Banner", 8, 1),
    ]
    static let range = 1.0 ... 56.0

    private var _w: SlideSizeDialog { widget as! SlideSizeDialog }
    private let _width = TextEditingController()
    private let _height = TextEditingController()
    private var _scaling = DeckController.SlideScaling.ensureFit

    static func inches(_ v: Double) -> String {
        let r = (v * 1000).rounded() / 1000
        return r == r.rounded() ? String(Int(r)) : String(r)
    }

    override func initState() {
        super.initState()
        _width.text = Self.inches(_w.size.width / 72)
        _height.text = Self.inches(_w.size.height / 72)
    }

    override func dispose() {
        _width.dispose()
        _height.dispose()
        super.dispose()
    }

    /// The typed size in points, or nil when either box is not a number within PowerPoint's 1 to 56 inches.
    private func _typed() -> Size? {
        guard let w = Double(String(_width.text.filter { $0 != " " })), let h = Double(String(_height.text.filter { $0 != " " })),
              Self.range.contains(w), Self.range.contains(h) else { return nil }
        return Size((w * 72).rounded(), (h * 72).rounded())   // whole points: 13.333 in is the 960 pt of Widescreen
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let caption = fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary)
        func gap(_ h: Double) -> Widget { SizedBox(width: nil, height: h, child: nil) }
        let presets = Self.presets.enumerated().map { i, p -> Widget in
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 8, bottom: 4), child: Button(
                key: ValueKey("size.preset.\(i)"),
                onPressed: { [weak self] in
                    self?._width.text = Self.inches(p.width); self?._height.text = Self.inches(p.height)
                    self?.setState {}
                }, child: Text(p.name)))
        }
        func field(_ id: String, _ label: String, _ c: TextEditingController) -> Widget {
            Row(children: [
                SizedBox(width: 70, height: nil, child: Text(label, style: caption)),
                SizedBox(key: ValueKey(id), width: 90, height: Chrome.fieldHeight, child: FluentTextBox(controller: c, onChanged: { [weak self] _ in self?.setState {} })),
                SizedBox(width: 6, height: nil, child: Text("in", style: caption)),
            ])
        }
        let ok = _typed() != nil
        let card = Column(mainAxisSize: .min, crossAxisAlignment: .start, children: [
            Text("Slide Size", style: fluent.typography.subtitle), gap(12),
            Text("Slides sized for", style: caption), gap(6),
            Wrap(children: presets), gap(10),
            field("size.width", "Width", _width), gap(6),
            field("size.height", "Height", _height),
            ok ? gap(0) : Padding(padding: EdgeInsets(left: 0, top: 6, right: 0, bottom: 0),
                                  child: Text("Width and height must be between 1 and 56 inches.", style: caption)),
            gap(14),
            Text("Scale the content on your slides", style: caption), gap(6),
            RadioButton<DeckController.SlideScaling>(key: ValueKey("size.maximize"), value: .maximize, groupValue: _scaling,
                onChanged: { [weak self] _ in self?.setState { self?._scaling = .maximize } },
                content: Text("Maximize (larger content; it may not fit)")), gap(4),
            RadioButton<DeckController.SlideScaling>(key: ValueKey("size.fit"), value: .ensureFit, groupValue: _scaling,
                onChanged: { [weak self] _ in self?.setState { self?._scaling = .ensureFit } },
                content: Text("Ensure Fit (smaller content that fits)")),
            gap(20),
            Row(mainAxisAlignment: .end, children: [
                FilledButton(key: ValueKey("size.ok"), onPressed: ok ? { [weak self] in
                    guard let self, let s = self._typed() else { return }
                    self._w.onApply(s, self._scaling)
                } : nil, child: Text("OK")),
                SizedBox(width: 8, height: nil, child: nil),
                Button(key: ValueKey("size.cancel"), onPressed: { [weak self] in self?._w.onCancel() }, child: Text("Cancel")),
            ]),
        ])
        return Stack(children: [
            Positioned(left: 0, top: 0, right: 0, bottom: 0, child: Listener(
                behavior: .opaque,
                child: ColoredBox(color: Color(0x33000000), child: SizedBox(expand: ())))),
            Positioned(left: 0, top: 0, right: 0, bottom: 0, child: Center(child: SizedBox(width: 460, height: nil, child: DecoratedBox(
                decoration: BoxDecoration(color: OfficeAppearance.surface(fluent),
                                          border: Border.all(color: fluent.resources.controlStrokeColorDefault, width: 1),
                                          borderRadius: BorderRadius.circular(8),
                                          boxShadow: [BoxShadow(color: Color(0x40000000), offset: Offset(0, 8), blurRadius: 24)]),
                child: Padding(padding: EdgeInsets(all: 24), child: KeyboardRegion(name: "dialog", modal: true, child: card)))))),
        ])
    }
}
