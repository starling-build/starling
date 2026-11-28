// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The Selection Pane (S-AR-1b): every shape of the current slide, front first,
// with an eye to show or hide it and buttons to move it in the stack. A row
// selects its shape (Shift or Ctrl adds), which is the only way to reach a
// hidden one. A double-click on a name (or F2 on a selected row's name) renames
// the shape, as PowerPoint's pane does; Show All and Hide All act on the slide.

import Flutter
import OfficeText
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

final class SelectionPane: StatefulWidget {
    let deck: DeckController
    let onClose: () -> Void
    let modifiers: () -> KeyModifiers

    init(deck: DeckController, modifiers: @escaping () -> KeyModifiers = { [] }, onClose: @escaping () -> Void) {
        self.deck = deck
        self.modifiers = modifiers
        self.onClose = onClose
        super.init()
    }

    override func createState() -> State<StatefulWidget> { SelectionPaneState() }
}

final class SelectionPaneState: State<StatefulWidget> {
    private var _w: SelectionPane { widget as! SelectionPane }
    private var deck: DeckController { _w.deck }
    private var modifiers: () -> KeyModifiers { _w.modifiers }
    private var onClose: () -> Void { _w.onClose }
    /// The shape whose name is being typed, and the text box's text.
    private var _renaming: SlideShape? = nil
    private let _renameText = TextEditingController()
    /// Double-click on a name, detected by hand: registering onDoubleTap kills taps on the DRM embedder (CLAUDE.md).
    private var _lastDown: (shape: SlideShape, at: Date)? = nil

    /// Starts typing a new name for `shape`, its whole old name selected so typing replaces it.
    func startRename(_ shape: SlideShape) {
        let name = shape.name
        _renameText.value = TextEditingValue(text: name, selection: TextSelection(baseOffset: 0, extentOffset: name.count))
        setState { _renaming = shape }
    }

    private func _finishRename(_ shape: SlideShape, _ name: String) {
        guard _renaming === shape else { return }
        _renaming = nil
        deck.renameShape(shape, name)
        setState {}
    }

    override func build(_ context: any BuildContext) -> Widget {
        // The pane follows the deck itself: a hide or a reorder renumbers its rows.
        AnimatedBuilder(animation: deck, builder: { [self] ctx, _ in _panel(ctx) })
    }

    private func _panel(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let ink = fluent.resources.textFillColorPrimary
        let accent = fluent.accentColor.defaultBrushFor(fluent.brightness)
        let shapes = deck.currentSlide.shapes
        var rows: [Widget] = []
        // Front of the stack first, as PowerPoint lists it.
        for (i, shape) in shapes.enumerated().reversed() {
            let selected = deck.isSelected(shape)
            let hidden = shape.invisible
            let byGroup = shape.group?.hidden == true
            let label = shape.name.isEmpty ? "Shape \(i + 1)" : shape.name
            let color = hidden ? fluent.resources.textFillColorDisabled : ink
            rows.append(ColoredBox(
                color: selected ? accent.withOpacity(0.14) : Color(0x00000000),
                child: Row(children: [
                    Padding(key: ValueKey("selpane.eye.\(i)"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), child:
                        FlatButton(child: Text(hidden ? "○" : "●", style: fluent.typography.body?.copyWith(color: color)),
                                   tip: hidden ? "Show" : "Hide", enabled: !byGroup) { [deck] in deck.setHidden(shape, !hidden) }),
                    Expanded(child: _renaming === shape
                        ? Padding(key: ValueKey("selpane.rename.\(i)"), padding: EdgeInsets(left: 0, top: 2, right: 0, bottom: 2),
                                  child: SizedBox(width: nil, height: 28, child: FluentTextBox(
                                      controller: _renameText,
                                      onSubmitted: { [weak self] name in self?._finishRename(shape, name) },
                                      autofocus: true,
                                      onFocusChanged: { [weak self] f in
                                          if !f, let self { self._finishRename(shape, self._renameText.text) } })))
                        : KeyboardRow(label: label, activate: { [deck] in deck.selectShapes([shape]) }, child: Listener(
                        key: ValueKey("selpane.row.\(i)"),
                        onPointerDown: { [weak self, deck, modifiers] _ in
                            let now = Date()
                            if let self, let last = self._lastDown, last.shape === shape, now.timeIntervalSince(last.at) < 0.4 {
                                self._lastDown = nil
                                deck.selectShapes([shape])
                                self.startRename(shape)
                                return
                            }
                            self?._lastDown = (shape, now)
                            let m = modifiers()
                            if deck.selectMultiple || m.contains(.shift) || m.contains(.control) || m.contains(.meta) { deck.toggleSelected(shape) }
                            else { deck.selectShapes([shape]) }
                        },
                        behavior: .opaque,
                        child: Padding(padding: EdgeInsets(left: 4, top: 8, right: 4, bottom: 8),
                                       child: Text(label, style: fluent.typography.body?.copyWith(color: color),
                                                   overflow: .ellipsis, maxLines: 1))))),
                    Padding(key: ValueKey("selpane.front.\(i)"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), child:
                        Chrome.icon(FluentSystemIcons.chevronUp, "Bring forward", fluent, enabled: i < shapes.count - 1) { [deck] in
                            deck.moveInStack(shape, by: 1) }),
                    Padding(key: ValueKey("selpane.back.\(i)"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), child:
                        Chrome.icon(FluentSystemIcons.chevronDown, "Send backward", fluent, enabled: i > 0) { [deck] in
                            deck.moveInStack(shape, by: -1) }),
                ])))
        }
        if rows.isEmpty {
            rows.append(Padding(padding: EdgeInsets(left: 8, top: 8, right: 8, bottom: 8), child: Text(
                "This slide has no shapes.", style: fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary))))
        }
        let header = Row(children: [
            Expanded(child: Text("Selection Pane", style: fluent.typography.bodyStrong)),
            Padding(key: ValueKey("selpane.close"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0),
                    child: IconButton(icon: Icon(FluentSystemIcons.close, size: 14, color: ink), onPressed: onClose)),
        ])
        // PowerPoint's pane opens with Show All and Hide All over the list.
        let allHidden = !shapes.isEmpty && shapes.allSatisfy(\.invisible)
        let noneHidden = shapes.allSatisfy { !$0.invisible }
        let bulk = Row(children: [
            Padding(key: ValueKey("selpane.showAll"), padding: EdgeInsets(left: 0, top: 0, right: 4, bottom: 0),
                    child: Button(onPressed: noneHidden ? nil : { [deck] in deck.setAllHidden(false) }, child: Text("Show All"))),
            Padding(key: ValueKey("selpane.hideAll"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0),
                    child: Button(onPressed: allHidden || shapes.isEmpty ? nil : { [deck] in deck.setAllHidden(true) }, child: Text("Hide All"))),
        ])
        return SizedBox(width: 300, height: nil, child: DecoratedBox(
            decoration: BoxDecoration(color: OfficeAppearance.surface(fluent),
                                      border: Border(left: BorderSide(color: fluent.resources.controlStrokeColorDefault, width: 1))),
            child: Padding(padding: EdgeInsets(left: 12, top: 12, right: 12, bottom: 12), child: Column(
                crossAxisAlignment: .stretch, children: [
                    header,
                    SizedBox(width: nil, height: 8, child: nil),
                    bulk,
                    SizedBox(width: nil, height: 8, child: nil),
                    Expanded(child: SingleChildScrollView(child: Column(crossAxisAlignment: .stretch, children: rows))),
                ]))))
    }
}
