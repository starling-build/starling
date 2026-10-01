// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The title row (quick-access toolbar, document name, search) and the
// status bar (page, words, view switcher, zoom slider) — Word's top and
// bottom edges.

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

final class TitleRow: StatelessWidget {
    let session: OfficeSession
    let searchController: TextEditingController
    let onSearch: (String) -> Void

    init(session: OfficeSession, searchController: TextEditingController,
         onSearch: @escaping (String) -> Void) {
        self.session = session
        self.searchController = searchController
        self.onSearch = onSearch
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let s = session.summary
        let c = session.controller
        let name = session.title + (session.dirty ? " •" : "")
        return DecoratedBox(
            decoration: BoxDecoration(color: fluent.resources.solidBackgroundFillColorBase),
            child: Padding(padding: EdgeInsets(left: 8, top: 4, right: 12, bottom: 2), child: Row(
                crossAxisAlignment: .center, children: [
                    Chrome.textToggle("AutoSave", session.autoSave, fluent, style: fluent.typography.caption) { [session] in
                        session.onToggleAutoSave?()
                    },
                    Chrome.gap(6),
                    Chrome.icon(FluentSystemIcons.save, "Save (⌘S)", fluent) { [session] in session.onSave?() },
                    Chrome.icon(FluentSystemIcons.undo, "Undo (⌘Z)", fluent, enabled: s.canUndo) { [session] in
                        if let undo = session.onUndo { undo() } else { c.undo() }
                    },
                    Chrome.icon(FluentSystemIcons.redo, "Redo (⇧⌘Z)", fluent, enabled: s.canRedo) { [session] in
                        if let redo = session.onRedo { redo() } else { c.redo() }
                    },
                    Expanded(child: Center(child: Text(name, style: fluent.typography.bodyStrong))),
                    SizedBox(width: 260, height: 30, child: FluentTextBox(
                        controller: searchController,
                        placeholderText: "Search (⌘F)",
                        onSubmitted: { [onSearch] q in onSearch(q) })),
                    Chrome.gap(8),
                    Chrome.icon(FluentSystemIcons.share, "Share", fluent, enabled: false) {},
                    Chrome.icon(FluentSystemIcons.person, "Account", fluent, enabled: false) {},
                ])))
    }
}

final class StatusBar: StatelessWidget {
    let session: OfficeSession
    let message: String?

    init(session: OfficeSession, message: String?) {
        self.session = session
        self.message = message
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let s = session.summary
        let caption = fluent.typography.caption
        let dim = caption?.copyWith(color: fluent.resources.textFillColorSecondary)
        var left: [Widget] = [
            Text("Page \(session.pageInfo.page) of \(session.pageInfo.count)", style: caption),
            Chrome.gap(20),
            Text("\(s.words) words", style: caption),
            Chrome.gap(20),
            Text("English (United States)", style: dim),
        ]
        if let message {
            left.append(Chrome.gap(20))
            left.append(Text(message, style: dim))
        }
        let right: [Widget] = [
            Chrome.toggle(FluentSystemIcons.onePage, "Print Layout", session.viewMode == .printLayout, fluent) { [session] in session.onViewMode?(.printLayout) },
            Chrome.toggle(FluentSystemIcons.document, "Web Layout", session.viewMode == .webLayout, fluent) { [session] in session.onViewMode?(.webLayout) },
            Chrome.toggle(FluentSystemIcons.readMode, "Read Mode", session.viewMode == .readMode, fluent) { [session] in session.onViewMode?(.readMode) },
            Chrome.gap(12),
            Chrome.icon(FluentSystemIcons.zoomOut, "Zoom Out", fluent) { [session] in session.onZoom?(session.zoom - 0.1) },
            SizedBox(width: 140, height: nil, child: Slider(
                value: session.zoom * 100,
                onChanged: { [session] v in session.onZoom?((v / 100 * 10).rounded() / 10) },
                min: 50, max: 300)),
            Chrome.icon(FluentSystemIcons.zoomIn, "Zoom In", fluent) { [session] in session.onZoom?(session.zoom + 0.1) },
            SizedBox(width: 44, height: nil, child: Text("\(Int((session.zoom * 100).rounded()))%", style: caption)),
        ]
        return DecoratedBox(
            decoration: BoxDecoration(
                color: fluent.resources.solidBackgroundFillColorBase,
                border: Border(top: BorderSide(color: fluent.resources.dividerStrokeColorDefault, width: 1))),
            child: Padding(padding: EdgeInsets(left: 12, top: 2, right: 8, bottom: 2), child: Row(
                crossAxisAlignment: .center,
                children: left + [Expanded(child: SizedBox(width: 0, height: 0, child: nil))] + right)))
    }
}
