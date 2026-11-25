// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import OfficeText
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

/// The view a widget is drawn in: its render tree's root, else the only view there is.
func hostView(_ context: any BuildContext) -> FlutterView? {
    var node: RenderObject? = context.findRenderObject()
    while let n = node {
        if let root = n as? RenderView { return root.flutterView }
        node = n.parent
    }
    return PlatformDispatcher.instance.views.first
}

/// The soft keyboard's height in logical pixels, 0 when there is none (a hardware keyboard, the Mac).
func softKeyboardHeight(_ context: any BuildContext) -> Double {
    guard let view = hostView(context), view.devicePixelRatio > 0 else { return 0 }
    return view.viewInsets.bottom / view.devicePixelRatio
}

/// The bar above an iPad's soft keyboard (docs/plans/office-ui-gaps.md, section 6): what a touch user reaches for
/// while typing, without leaving the keyboard for the ribbon. Undo and Redo, the character toggles, lists and
/// indent; and it grows with what the selection is in: a table cell adds row and column commands, a selected
/// picture adds Fit to Width and Delete. Every button is 44 pt, Apple's minimum target; the row scrolls when the
/// window is narrower than it.
final class WriterKeyBar: StatelessWidget {
    let session: OfficeSession
    let controller: RichDocumentController
    static let height = 52.0

    init(session: OfficeSession, controller: RichDocumentController) {
        self.session = session
        self.controller = controller
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let s = session.summary
        let c = controller
        let ink = OfficeAppearance.ink(fluent)
        let accent = fluent.accentColor.defaultBrushFor(fluent.brightness)
        let dim = fluent.resources.textFillColorDisabled
        func icon(_ i: IconData, _ tip: String, on: Bool = false, enabled: Bool = true, _ action: @escaping () -> Void) -> Widget {
            FlatButton(child: Icon(i, size: 22, color: !enabled ? dim : on ? accent : ink),
                       tip: tip, checked: on, enabled: enabled, width: 44, height: 44, action: action)
        }
        func label(_ text: String, _ tip: String, _ action: @escaping () -> Void) -> Widget {
            FlatButton(child: Padding(padding: EdgeInsets(left: 6, top: 0, right: 6, bottom: 0),
                                      child: Text(text, style: fluent.typography.caption?.copyWith(color: ink), softWrap: false)),
                       tip: tip, width: nil, height: 44, action: action)
        }
        func divider() -> Widget {
            Padding(padding: EdgeInsets(left: 6, top: 0, right: 6, bottom: 0),
                    child: SizedBox(width: 1, height: 24, child: ColoredBox(color: OfficeAppearance.border(fluent))))
        }
        var items: [Widget] = [
            icon(FluentSystemIcons.undo, "Undo", enabled: s.canUndo) { [session] in
                if let undo = session.onUndo { undo() } else { c.undo() }
            },
            icon(FluentSystemIcons.redo, "Redo", enabled: s.canRedo) { [session] in
                if let redo = session.onRedo { redo() } else { c.redo() }
            },
            divider(),
            icon(FluentSystemIcons.textBold, "Bold", on: s.bold) { c.toggleBold() },
            icon(FluentSystemIcons.textItalic, "Italic", on: s.italic) { c.toggleItalic() },
            icon(FluentSystemIcons.textUnderline, "Underline", on: s.underline) { c.toggleUnderline() },
            divider(),
            icon(FluentSystemIcons.bulletList, "Bullets", on: s.list == .bullet) { c.toggleList(.bullet) },
            icon(FluentSystemIcons.numberList, "Numbering", on: s.list == .numbered) { c.toggleList(.numbered) },
            icon(FluentSystemIcons.indentDecrease, "Decrease Indent") { c.indent(-1) },
            icon(FluentSystemIcons.indentIncrease, "Increase Indent") { c.indent(1) },
        ]
        if s.inCell {
            items += [
                divider(),
                label("Row +", "Insert Row Below") { c.insertRow(below: true) },
                label("Row −", "Delete Row") { c.deleteRow() },
                label("Col +", "Insert Column Right") { c.insertColumn(after: true) },
                label("Col −", "Delete Column") { c.deleteColumn() },
            ]
        }
        if let i = s.imageIndex, i < c.document.paragraphs.count, let image = c.document.paragraphs[i].image {
            items += [
                divider(),
                label("Fit Width", "Fit Picture to Width") { [session] in
                    let w = session.pageSetup.columnWidth
                    c.setImageSize(at: i, width: w, height: w * image.height / max(1, image.width))
                },
                label("Delete Picture", "Delete Picture") { c.deleteForward() },
            ]
        }
        return SizedBox(width: nil, height: Self.height, child: DecoratedBox(
            decoration: BoxDecoration(color: OfficeAppearance.surface(fluent),
                                      border: Border(top: BorderSide(color: OfficeAppearance.border(fluent), width: 1))),
            child: SingleChildScrollView(scrollDirection: .horizontal,
                child: Padding(padding: EdgeInsets(left: 8, top: 4, right: 8, bottom: 4),
                               child: Row(crossAxisAlignment: .center, children: items)))))
    }
}
