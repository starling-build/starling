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
        let white = OfficeAppearance.white
        let name = session.title + (session.dirty ? " •" : "")
        let titleStyle = fluent.typography.bodyStrong?.copyWith(color: white)
        let captionStyle = fluent.typography.caption?.copyWith(color: white)
        func command(_ icon: IconData, _ tip: String, enabled: Bool = true,
                     action: @escaping () -> Void) -> Widget {
            FlatButton(child: Icon(icon, size: 17, color: white.withOpacity(enabled ? 1 : 0.4)),
                       tip: tip, enabled: enabled, width: 32, height: 32,
                       onAccent: true, action: action)
        }
        return ColoredBox(color: OfficeAppearance.titleBar,
            child: Padding(padding: EdgeInsets(left: 16, top: 10, right: 16, bottom: 10), child: Row(
                crossAxisAlignment: .center, children: [
                    DecoratedBox(decoration: BoxDecoration(color: white,
                        borderRadius: BorderRadius.all(Radius(circular: 6))),
                        child: SizedBox(width: 30, height: 32, child: Center(child: Text(session.kind == .document ? "W" : "S",
                            style: Flutter.TextStyle(color: OfficeAppearance.brand, fontSize: 20, fontWeight: .w600))))),
                    Chrome.gap(10),
                    Text(session.kind.appName, style: titleStyle),
                    Chrome.gap(24),
                    command(FluentSystemIcons.save, "Save (⌘S)") { [session] in session.onSave?() },
                    command(FluentSystemIcons.undo, "Undo (⌘Z)", enabled: s.canUndo) { [session] in
                        if let undo = session.onUndo { undo() } else { c.undo() }
                    },
                    command(FluentSystemIcons.redo, "Redo (⇧⌘Z)", enabled: s.canRedo) { [session] in
                        if let redo = session.onRedo { redo() } else { c.redo() }
                    },
                    Expanded(child: Padding(padding: EdgeInsets(left: 16, top: 0, right: 16, bottom: 0),
                        child: Center(child: Text(name, style: titleStyle, softWrap: false, overflow: .ellipsis)))),
                    FlatButton(child: Padding(padding: EdgeInsets(left: 9, top: 0, right: 9, bottom: 0),
                        child: Text(session.autoSave ? "AutoSave on" : "AutoSave off", style: captionStyle)),
                        tip: "Toggle automatic recovery copies", checked: session.autoSave,
                        width: nil, height: 30, onAccent: true,
                        action: { [session] in session.onToggleAutoSave?() }),
                    Chrome.gap(16),
                    SizedBox(width: 230, height: 32, child: FluentTextBox(
                        controller: searchController,
                        placeholderText: session.kind == .document ? "Find in document (⌘F)" : session.kind == .workbook ? "Find in workbook (⌘F)" : "Find in presentation (⌘F)",
                        onSubmitted: { [onSearch] q in onSearch(q) })),
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
        let caption = fluent.typography.caption?.copyWith(color: OfficeAppearance.ink(fluent))
        let dim = caption?.copyWith(color: OfficeAppearance.secondary(fluent))
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
                color: OfficeAppearance.surface(fluent),
                border: Border(top: BorderSide(color: OfficeAppearance.border(fluent), width: 1))),
            child: Padding(padding: EdgeInsets(left: 18, top: 5, right: 12, bottom: 5), child: Row(
                crossAxisAlignment: .center,
                children: left + [Expanded(child: SizedBox(width: 0, height: 0, child: nil))] + right)))
    }
}
