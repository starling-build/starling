// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
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
    let onApply: () -> Void
    let onClose: () -> Void

    init(session: OfficeSession, header: TextEditingController, footer: TextEditingController,
         onApply: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.session = session
        self.header = header
        self.footer = footer
        self.onApply = onApply
        self.onClose = onClose
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let hint = fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary)
        let items: [Widget] = [
            SizedBox(width: 60, height: nil, child: Text("Header", style: fluent.typography.body)),
            SizedBox(width: 300, height: 30, child: FluentTextBox(
                controller: header, placeholderText: "Header text", onSubmitted: { [onApply] _ in onApply() })),
            Chrome.gap(16),
            SizedBox(width: 60, height: nil, child: Text("Footer", style: fluent.typography.body)),
            SizedBox(width: 300, height: 30, child: FluentTextBox(
                controller: footer, placeholderText: "Footer text", onSubmitted: { [onApply] _ in onApply() })),
            Chrome.gap(8),
            Button(onPressed: { [footer] in footer.text += RichDocument.pageField }, child: Text("Page")),
            Chrome.gap(4),
            Button(onPressed: { [footer] in footer.text += RichDocument.pageCountField }, child: Text("Pages")),
            Chrome.gap(12),
            Text("\(RichDocument.pageField) and \(RichDocument.pageCountField) fill in per page", style: hint),
            Expanded(child: SizedBox(width: 0, height: 0, child: nil)),
            FilledButton(onPressed: onApply, child: Text("Done")),
            Chrome.gap(4),
            Chrome.icon(FluentSystemIcons.chromeClose, "Close (Esc)", fluent, action: onClose),
        ]
        return DecoratedBox(
            decoration: BoxDecoration(
                color: fluent.resources.layerFillColorDefault,
                border: Border(bottom: BorderSide(color: fluent.resources.dividerStrokeColorDefault, width: 1))),
            child: Padding(padding: EdgeInsets(left: 12, top: 6, right: 8, bottom: 6),
                           child: Row(crossAxisAlignment: .center, children: items)))
    }
}
