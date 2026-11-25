// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-ST-1: Word's Styles pane — every style in the document, the caret's
// one highlighted. A click applies it; the pencil opens Modify; the bin
// deletes a style you made (Normal and the headings stay).

import Flutter
import OfficeText
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

private final class SPKeyed: StatelessWidget {
    let child: Widget
    init(_ id: String, _ child: Widget) { self.child = child; super.init(key: ValueKey(id)) }
    override func build(_ context: any BuildContext) -> Widget { child }
}

final class StylesPane: StatelessWidget {
    static let width = 272.0

    let session: OfficeSession
    let onModify: (String) -> Void
    let onClose: () -> Void

    init(session: OfficeSession, onModify: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        self.session = session; self.onModify = onModify; self.onClose = onClose
        super.init()
    }

    /// Normal and the headings cannot be deleted.
    static func deletable(_ id: String) -> Bool { id != RichNamedStyle.normalId && !id.hasPrefix("Heading") }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let c = session.controller
        let styles = c.document.styles.styles
        let current = c.currentNamedStyleId
        let header = Padding(padding: EdgeInsets(left: 18, top: 16, right: 8, bottom: 14), child: Row(
            crossAxisAlignment: .center, children: [
                Expanded(child: Text("Styles", style: fluent.typography.bodyStrong)),
                Chrome.icon(FluentSystemIcons.close, "Close", fluent, action: onClose),
            ]))
        let body = ListView(key: ValueKey("\(styles.map(\.id).joined(separator: ","))-\(current)"), itemCount: styles.count) { [session, onModify] _, i in
            let entry = styles[i]
            var row: [Widget] = [
                Expanded(child: SPKeyed("sp-style-\(entry.id)", FlyoutListTile(
                    onPressed: { session.controller.setNamedStyle(entry.id) },
                    text: Text(entry.name, style: entry.id == current ? fluent.typography.bodyStrong : fluent.typography.body,
                               softWrap: false),
                    margin: EdgeInsets(left: 0, top: 0, right: 0, bottom: 1),
                    selected: entry.id == current))),
                SPKeyed("sp-modify-\(entry.id)", Chrome.icon(FluentSystemIcons.edit, "Modify \(entry.name)", fluent, action: { onModify(entry.id) })),
            ]
            if Self.deletable(entry.id) {
                row.append(SPKeyed("sp-delete-\(entry.id)", Chrome.icon(FluentSystemIcons.delete, "Delete \(entry.name)", fluent, action: {
                    session.controller.deleteStyle(entry.id)
                })))
            }
            return Padding(padding: EdgeInsets(left: 8, top: 0, right: 8, bottom: 0),
                           child: Row(crossAxisAlignment: .center, children: row))
        }
        return SizedBox(width: Self.width, height: nil, child: DecoratedBox(
            decoration: BoxDecoration(
                color: OfficeAppearance.surface(fluent),
                border: Border(left: BorderSide(color: OfficeAppearance.border(fluent), width: 1))),
            child: Column(crossAxisAlignment: .stretch, children: [header, Expanded(child: body)])))
    }
}
