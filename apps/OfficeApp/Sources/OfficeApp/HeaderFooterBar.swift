// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import OfficeText
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

/// The strip Insert → Header / Footer opens: one line each, with the page
/// fields as buttons. Word edits these in place on the page; a strip is
/// the honest version until the layout has editable margin boxes.
final class HeaderFooterBar: StatelessWidget {
    let session: OfficeSession
    let header: TextEditingController
    let footer: TextEditingController
    /// The file's own header/footer holds pictures, tables or formatting the
    /// strip cannot edit; that side is shown read-only and saved untouched.
    let headerLocked: Bool
    let footerLocked: Bool
    /// Bold, italic and alignment of each line (W-HF-1); the shell keeps them and rebuilds on a change.
    let headerLook: RichDocumentController.HeaderFooterLook
    let footerLook: RichDocumentController.HeaderFooterLook
    let onLook: (_ header: Bool, _ look: RichDocumentController.HeaderFooterLook) -> Void
    let onApply: () -> Void
    let onClose: () -> Void

    init(session: OfficeSession, header: TextEditingController, footer: TextEditingController,
         headerLocked: Bool = false, footerLocked: Bool = false,
         headerLook: RichDocumentController.HeaderFooterLook = .init(), footerLook: RichDocumentController.HeaderFooterLook = .init(),
         onLook: @escaping (Bool, RichDocumentController.HeaderFooterLook) -> Void = { _, _ in },
         onApply: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.session = session
        self.header = header
        self.footer = footer
        self.headerLocked = headerLocked
        self.footerLocked = footerLocked
        self.headerLook = headerLook
        self.footerLook = footerLook
        self.onLook = onLook
        self.onApply = onApply
        self.onClose = onClose
        super.init()
    }

    private func lookButtons(_ isHeader: Bool, _ look: RichDocumentController.HeaderFooterLook, locked: Bool) -> [Widget] {
        let side = isHeader ? "header" : "footer"
        func toggle(_ label: String, _ id: String, _ on: Bool, _ change: @escaping (inout RichDocumentController.HeaderFooterLook) -> Void) -> Widget {
            let btn = { [onLook] in var l = look; change(&l); onLook(isHeader, l) }
            let child = Text(label)
            return SizedBox(width: 34, height: 30, child: locked
                ? Button(key: ValueKey<String>("\(side)-\(id)"), onPressed: nil, child: child)
                : (on ? FilledButton(key: ValueKey<String>("\(side)-\(id)"), onPressed: btn, child: child)
                      : Button(key: ValueKey<String>("\(side)-\(id)"), onPressed: btn, child: child)))
        }
        return [
            toggle("B", "bold", look.bold) { $0.bold.toggle() },
            toggle("I", "italic", look.italic) { $0.italic.toggle() },
            toggle("L", "left", look.alignment == .left) { $0.alignment = .left },
            toggle("C", "center", look.alignment == .center) { $0.alignment = .center },
            toggle("R", "right", look.alignment == .right) { $0.alignment = .right },
        ]
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let hint = fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary)
        let headerRow: [Widget] = [
            SizedBox(width: 60, height: nil, child: Text("Header", style: fluent.typography.body)),
            // (The field takes the keyboard as the bar opens, as Find's
            // does: Insert → Header and a typed line used to go into the
            // document's text — seen on screen 2026-10-13.)
            SizedBox(width: 230 * SystemDisplay.current.chromeTextScale, height: OfficeAppearance.rowHeight(30), child: FluentTextBox(
                controller: header, placeholderText: headerLocked ? "Has pictures or formatting: kept as is" : "Header text",  onSubmitted: { [onApply] _ in onApply() }, enabled: !headerLocked, autofocus: true,
                tabGroup: "header-footer", tabOrder: 0)),
            Chrome.gap(4)] + lookButtons(true, headerLook, locked: headerLocked) + [
            Expanded(child: SizedBox(width: 0, height: 0, child: nil)),
            FilledButton(key: ValueKey<String>("header-footer-done"), onPressed: onApply, child: Text("Done")),
            Chrome.gap(4),
            Chrome.icon(FluentSystemIcons.chromeClose, "Close (Esc)", fluent, action: onClose),
        ]
        let footerRow: [Widget] = [
            SizedBox(width: 60, height: nil, child: Text("Footer", style: fluent.typography.body)),
            SizedBox(width: 230 * SystemDisplay.current.chromeTextScale, height: OfficeAppearance.rowHeight(30), child: FluentTextBox(
                controller: footer, placeholderText: footerLocked ? "Has pictures or formatting: kept as is" : "Footer text",  onSubmitted: { [onApply] _ in onApply() }, enabled: !footerLocked,
                tabGroup: "header-footer", tabOrder: 1)),
            Chrome.gap(4)] + lookButtons(false, footerLook, locked: footerLocked) + [
            Chrome.gap(8),
            Button(onPressed: footerLocked ? nil : { [footer] in footer.text += RichDocument.pageField }, child: Text("Page")),
            Chrome.gap(4),
            Button(onPressed: footerLocked ? nil : { [footer] in footer.text += RichDocument.pageCountField }, child: Text("Pages")),
            Chrome.gap(12),
            Text("\(RichDocument.pageField) and \(RichDocument.pageCountField) fill in per page", style: hint),
        ]
        return DecoratedBox(
            decoration: BoxDecoration(
                color: fluent.resources.layerFillColorDefault,
                border: Border(bottom: BorderSide(color: fluent.resources.dividerStrokeColorDefault, width: 1))),
            child: Padding(padding: EdgeInsets(left: 12, top: 6, right: 8, bottom: 6),
                           child: Column(mainAxisSize: .min, crossAxisAlignment: .start, children: [
                               Row(crossAxisAlignment: .center, children: headerRow),
                               Chrome.vgap(6),
                               Row(crossAxisAlignment: .center, children: footerRow)])))
    }
}
