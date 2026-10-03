// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Insert → Header & Footer (S7): PowerPoint's Slide tab of that dialog —
// date and time (updating, or fixed text), slide number, footer text, and
// "Don't show on title slide" — applied to this slide or to all of them.

import Flutter
import FlutterSwiftBridge
import Foundation

final class HeaderFooterDialog: StatefulWidget {
    let initial: DeckController.HeaderFooter
    let onApply: (DeckController.HeaderFooter, _ toAll: Bool) -> Void
    let onCancel: () -> Void

    init(initial: DeckController.HeaderFooter,
         onApply: @escaping (DeckController.HeaderFooter, Bool) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial
        self.onApply = onApply
        self.onCancel = onCancel
        super.init()
    }

    override func createState() -> State<StatefulWidget> { HeaderFooterDialogState() }
}

final class HeaderFooterDialogState: State<StatefulWidget> {
    private var _w: HeaderFooterDialog { widget as! HeaderFooterDialog }
    private var _hf = DeckController.HeaderFooter()
    private var _fixed = false
    private var _footerOn = false
    private let _date = TextEditingController()
    private let _footer = TextEditingController()

    override func initState() {
        super.initState()
        _hf = _w.initial
        _fixed = _hf.fixedDate != nil
        _footerOn = _hf.footer != nil
        _date.text = _hf.fixedDate ?? SlidesDates.format(Date(), "M/d/yyyy")
        _footer.text = _hf.footer ?? ""
    }

    override func dispose() {
        _date.dispose()
        _footer.dispose()
        super.dispose()
    }

    private func _result() -> DeckController.HeaderFooter {
        var hf = _hf
        hf.fixedDate = _fixed ? _date.text : nil
        hf.footer = _footerOn ? _footer.text : nil
        return hf
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let caption = fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary)
        func check(_ label: String, _ on: Bool, _ set: @escaping (Bool) -> Void) -> Widget {
            Checkbox(checked: on, onChanged: { [weak self] v in self?.setState { set(v ?? false) } }, content: Text(label))
        }
        func gap(_ h: Double) -> Widget { SizedBox(width: nil, height: h, child: nil) }
        let dateOptions = Padding(padding: EdgeInsets(left: 28, top: 6, right: 0, bottom: 0), child: Column(
            crossAxisAlignment: .start, children: [
                RadioButton<Bool>(value: false, groupValue: _fixed,
                                  onChanged: _hf.date ? { [weak self] _ in self?.setState { self?._fixed = false } } : nil,
                                  content: Text("Update automatically")),
                gap(6),
                Row(children: [
                    RadioButton<Bool>(value: true, groupValue: _fixed,
                                      onChanged: _hf.date ? { [weak self] _ in self?.setState { self?._fixed = true } } : nil,
                                      content: Text("Fixed")),
                    SizedBox(width: 10, height: nil, child: nil),
                    SizedBox(width: 180, height: 30, child: FluentTextBox(controller: _date, enabled: _hf.date && _fixed)),
                ]),
            ]))
        let card = Column(mainAxisSize: .min, crossAxisAlignment: .start, children: [
            Text("Header and Footer", style: fluent.typography.subtitle),
            gap(4),
            Text("Include on slide", style: caption),
            gap(12),
            check("Date and time", _hf.date) { [weak self] v in self?._hf.date = v },
            dateOptions,
            gap(12),
            check("Slide number", _hf.slideNumber) { [weak self] v in self?._hf.slideNumber = v },
            gap(12),
            check("Footer", _footerOn) { [weak self] v in self?._footerOn = v },
            Padding(padding: EdgeInsets(left: 28, top: 6, right: 0, bottom: 0),
                    child: SizedBox(width: 330, height: 30, child: FluentTextBox(controller: _footer, enabled: _footerOn))),
            gap(16),
            check("Don't show on title slide", _hf.skipTitleSlides) { [weak self] v in self?._hf.skipTitleSlides = v },
            gap(20),
            Row(mainAxisAlignment: .end, children: [
                Button(onPressed: { [weak self] in
                    guard let self else { return }
                    self._w.onApply(self._result(), false)
                }, child: Text("Apply")),
                SizedBox(width: 8, height: nil, child: nil),
                FilledButton(onPressed: { [weak self] in
                    guard let self else { return }
                    self._w.onApply(self._result(), true)
                }, child: Text("Apply to All")),
                SizedBox(width: 8, height: nil, child: nil),
                Button(onPressed: { [weak self] in self?._w.onCancel() }, child: Text("Cancel")),
            ]),
        ])
        // A modal sheet: the dimmed window behind it takes no clicks.
        return Stack(children: [
            Positioned(left: 0, top: 0, right: 0, bottom: 0, child: Listener(
                behavior: .opaque,
                child: ColoredBox(color: Color(0x33000000), child: SizedBox(expand: ())))),
            Positioned(left: 0, top: 0, right: 0, bottom: 0, child: Center(child: SizedBox(width: 440, height: nil, child: DecoratedBox(
                decoration: BoxDecoration(color: OfficeAppearance.surface(fluent),
                                          border: Border.all(color: fluent.resources.controlStrokeColorDefault, width: 1),
                                          borderRadius: BorderRadius.circular(8),
                                          boxShadow: [BoxShadow(color: Color(0x40000000), offset: Offset(0, 8), blurRadius: 24)]),
                child: Padding(padding: EdgeInsets(all: 24), child: card))))),
        ])
    }
}
