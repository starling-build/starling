// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Word's Navigation pane: the document's outline — Title and Heading 1–3
// paragraphs, nested by level — with the heading the caret is under
// highlighted. Clicking one moves the caret there; the editable scrolls it
// into view on its own.

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

final class NavigationPane: StatelessWidget {
    static let width = 240.0

    let session: OfficeSession
    let onClose: () -> Void

    init(session: OfficeSession, onClose: @escaping () -> Void) {
        self.session = session
        self.onClose = onClose
        super.init()
    }

    /// (paragraph index, outline level 0–3, text) for every heading.
    static func outline(_ doc: RichDocument) -> [(index: Int, level: Int, text: String)] {
        var out: [(Int, Int, String)] = []
        for (i, p) in doc.paragraphs.enumerated() {
            let level: Int
            if p.style.named == "Title" { level = 0 }
            else if let h = p.style.heading, h <= 3 { level = h }
            else { continue }
            let text = p.text.trimmingCharacters(in: .whitespacesAndNewlines)
            out.append((i, level, text.isEmpty ? "(empty heading)" : text))
        }
        return out
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let c = session.controller
        let items = Self.outline(c.document)
        let caret = c.caret.paragraph
        // The heading the caret is under: the last one at or before it.
        let current = items.lastIndex { $0.index <= caret }

        let header = Padding(padding: EdgeInsets(left: 12, top: 8, right: 4, bottom: 4), child: Row(
            crossAxisAlignment: .center, children: [
                Expanded(child: Text("Navigation", style: fluent.typography.bodyStrong)),
                Chrome.icon(FluentSystemIcons.close, "Close", fluent, action: onClose),
            ]))

        let body: Widget
        if items.isEmpty {
            body = Padding(padding: EdgeInsets(left: 12, top: 8, right: 12, bottom: 8), child: Text(
                "Create an interactive outline of your document.\n\nApply a heading style from the Home tab to the text you want to appear here.",
                style: fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary)))
        } else {
            // Keyed by what the rows show: a lazy list's children do not
            // rebuild on an ancestor rebuild, so the highlight would lag.
            body = ListView(key: ValueKey("\(items.count)-\(current ?? -1)"), itemCount: items.count) { [session] _, i in
                let item = items[i]
                return Padding(padding: EdgeInsets(left: 8 + Double(item.level) * 14, top: 0, right: 8, bottom: 0),
                               child: FlyoutListTile(
                                   onPressed: {
                                       session.controller.moveTo(RichPosition(paragraph: item.index, offset: 0), reveal: .top)
                                       session.onStatus?("Heading \(i + 1) of \(items.count)")
                                   },
                                   text: Text(item.text, style: i == current ? fluent.typography.bodyStrong : fluent.typography.body,
                                              softWrap: false),
                                   margin: EdgeInsets(left: 0, top: 0, right: 0, bottom: 1),
                                   selected: i == current))
            }
        }

        return SizedBox(width: Self.width, height: nil, child: DecoratedBox(
            decoration: BoxDecoration(
                color: fluent.resources.layerFillColorDefault,
                border: Border(right: BorderSide(color: fluent.resources.dividerStrokeColorDefault, width: 1))),
            child: Column(crossAxisAlignment: .stretch, children: [header, Expanded(child: body)])))
    }
}
