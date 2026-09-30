// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Backstage — what Word shows for File: a full-window page with the accent
// rail on the left (Home, New, Open, Info, Save, Save As, Export, Print,
// Close) and the chosen page on the right.

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

enum BackstagePage: Int, CaseIterable {
    case home, new, open, info, save, saveAs, export, print, close
    /// Not in the rail: the picture picker Insert → Pictures opens.
    case insertPicture

    var title: String {
        switch self {
        case .home: return "Home"
        case .new: return "New"
        case .open: return "Open"
        case .info: return "Info"
        case .save: return "Save"
        case .saveAs: return "Save As"
        case .export: return "Export"
        case .print: return "Print"
        case .close: return "Close"
        case .insertPicture: return "Insert Picture"
        }
    }

    var icon: IconData {
        switch self {
        case .home: return FluentSystemIcons.home
        case .new: return FluentSystemIcons.documentAdd
        case .open: return FluentSystemIcons.folderOpen
        case .info: return FluentSystemIcons.document
        case .save: return FluentSystemIcons.save
        case .saveAs: return FluentSystemIcons.save
        case .export: return FluentSystemIcons.documentPdf
        case .print: return FluentSystemIcons.print
        case .close: return FluentSystemIcons.chromeClose
        case .insertPicture: return FluentSystemIcons.image
        }
    }
}

final class Backstage: StatelessWidget {
    let session: OfficeSession
    let page: BackstagePage
    let recent: [String]
    let onPage: (BackstagePage) -> Void
    let onClose: () -> Void
    let onOpenPath: (String) -> Void
    let onSavePath: (String) -> Void
    let onPicturePath: (String) -> Void

    init(session: OfficeSession, page: BackstagePage, recent: [String],
         onPage: @escaping (BackstagePage) -> Void, onClose: @escaping () -> Void,
         onOpenPath: @escaping (String) -> Void, onSavePath: @escaping (String) -> Void,
         onPicturePath: @escaping (String) -> Void) {
        self.session = session
        self.page = page
        self.recent = recent
        self.onPage = onPage
        self.onClose = onClose
        self.onOpenPath = onOpenPath
        self.onSavePath = onSavePath
        self.onPicturePath = onPicturePath
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        return ColoredBox(color: fluent.resources.solidBackgroundFillColorBase, child: Row(
            crossAxisAlignment: .stretch, children: [
                _rail(fluent),
                Expanded(child: Padding(padding: EdgeInsets(left: 40, top: 32, right: 40, bottom: 32),
                                        child: _content(fluent))),
            ]))
    }

    // MARK: Rail

    private func _rail(_ fluent: FluentThemeData) -> Widget {
        let accent = fluent.accentColor.defaultBrushFor(fluent.brightness)
        let ink = fluent.resources.textOnAccentFillColorPrimary
        var items: [Widget] = [
            Padding(padding: EdgeInsets(left: 8, top: 8, right: 8, bottom: 16), child: Row(children: [
                IconButton(icon: Icon(FluentSystemIcons.back, size: 20, color: ink), onPressed: onClose),
            ])),
        ]
        for p in BackstagePage.allCases where p != .insertPicture {
            let selected = p == page
            items.append(GestureDetector(onTap: { [onPage] in onPage(p) }, child: DecoratedBox(
                decoration: BoxDecoration(color: selected ? Color(0x33FFFFFF) : Color(0x00000000)),
                child: Padding(padding: EdgeInsets(left: 20, top: 9, right: 20, bottom: 9), child: Row(children: [
                    Icon(p.icon, size: 16, color: ink),
                    Chrome.gap(12),
                    Text(p.title, style: fluent.typography.body?.copyWith(color: ink)),
                ])))))
            if p == .home || p == .info || p == .print { items.append(Chrome.vgap(10)) }
        }
        return SizedBox(width: 200, height: nil, child: ColoredBox(
            color: accent, child: Column(crossAxisAlignment: .stretch, children: items)))
    }

    // MARK: Pages

    private func _content(_ fluent: FluentThemeData) -> Widget {
        switch page {
        case .home: return _home(fluent)
        case .new: return _new(fluent)
        case .open: return _panel(.open, fluent)
        case .save, .saveAs: return _panel(.save, fluent)
        case .info: return _info(fluent)
        case .export: return _export(fluent)
        case .print: return _simple("Print", "Export a PDF and print it from your system's viewer; a print dialog of Office's own is still to come.", fluent, action: ("Export PDF", { [session] in session.onExport?("pdf") }))
        case .insertPicture: return _picturePanel(fluent)
        case .close: return _simple("Close", "Close the document and start a blank one.", fluent, action: ("Close document", { [session] in session.onNew?() }))
        }
    }

    private func _heading(_ text: String, _ fluent: FluentThemeData) -> Widget {
        Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 16),
                child: Text(text, style: fluent.typography.title))
    }

    private func _home(_ fluent: FluentThemeData) -> Widget {
        var recentRows: [Widget] = [Text("Recent", style: fluent.typography.subtitle), Chrome.vgap(8)]
        if recent.isEmpty {
            recentRows.append(Text("Documents you open or save show up here.",
                                   style: fluent.typography.body?.copyWith(color: fluent.resources.textFillColorSecondary)))
        }
        for path in recent.prefix(12) {
            recentRows.append(FlyoutListTile(
                onPressed: { [onOpenPath] in onOpenPath(path) },
                icon: Icon(FluentSystemIcons.document, size: 16, color: fluent.resources.textFillColorPrimary),
                text: Text((path as NSString).lastPathComponent),
                trailing: Text((path as NSString).deletingLastPathComponent,
                               style: fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary))))
        }
        return Column(crossAxisAlignment: .start, children: [
            _heading("Good \(Self._daypart())", fluent),
            Row(children: [
                _template("Blank document", FluentSystemIcons.documentAdd, fluent) { [session] in session.onNew?() },
                Chrome.gap(16),
                _template("Open", FluentSystemIcons.folderOpen, fluent) { [onPage] in onPage(.open) },
            ]),
            Chrome.vgap(28),
            Column(crossAxisAlignment: .start, children: recentRows),
        ])
    }

    private func _new(_ fluent: FluentThemeData) -> Widget {
        Column(crossAxisAlignment: .start, children: [
            _heading("New", fluent),
            Row(children: [
                _template("Blank document", FluentSystemIcons.documentAdd, fluent) { [session] in session.onNew?() },
                Chrome.gap(16),
                _template("Letter", FluentSystemIcons.document, fluent) { [session] in
                    session.onNew?()
                    let c = session.controller
                    c.insertText("[Your name]\n[Street address]\n[City, State ZIP]\n\n\(Self._today())\n\nDear [Recipient],\n\n[Body]\n\nSincerely,\n\n[Your name]")
                    c.moveTo(.start, extend: false)
                },
                Chrome.gap(16),
                _template("Report", FluentSystemIcons.document, fluent) { [session] in
                    session.onNew?()
                    let c = session.controller
                    c.insertText("Report title")
                    c.setHeading(1)
                    c.insertParagraphBreak()
                    c.insertText("Summary")
                    c.setHeading(2)
                    c.insertParagraphBreak()
                    c.insertText("[Start writing here.]")
                    c.moveTo(.start, extend: false)
                },
            ]),
        ])
    }

    private func _template(_ name: String, _ icon: IconData, _ fluent: FluentThemeData,
                           action: @escaping () -> Void) -> Widget {
        GestureDetector(onTap: action, child: SizedBox(width: 150, height: 190, child: DecoratedBox(
            decoration: BoxDecoration(
                color: fluent.resources.cardBackgroundFillColorDefault,
                border: Border.all(color: fluent.resources.cardStrokeColorDefault, width: 1),
                borderRadius: BorderRadius.all(Radius(circular: 6))),
            child: Column(mainAxisAlignment: .center, crossAxisAlignment: .center, children: [
                Icon(icon, size: 48, color: fluent.accentColor.defaultBrushFor(fluent.brightness)),
                Chrome.vgap(16),
                Text(name, style: fluent.typography.body),
            ]))))
    }

    private func _panel(_ mode: FilePanelMode, _ fluent: FluentThemeData) -> Widget {
        let dir = session.path.map { ($0 as NSString).deletingLastPathComponent }
            ?? NSHomeDirectory() + "/Documents"
        let start = FileManager.default.fileExists(atPath: dir) ? dir : NSHomeDirectory()
        let suggested = session.path.map { ($0 as NSString).lastPathComponent } ?? "Document1.docx"
        return Column(crossAxisAlignment: .stretch, children: [
            _heading(mode == .open ? "Open" : "Save As", fluent),
            Expanded(child: FluentFilePanel(
                mode: mode, initialDirectory: start, suggestedName: suggested,
                extensions: mode == .open ? OfficeFormats.readable : OfficeFormats.writable,
                onDone: { [onClose, onOpenPath, onSavePath] path in
                    guard let path else { onClose(); return }
                    if mode == .open { onOpenPath(path) } else { onSavePath(path) }
                })),
        ])
    }

    private func _picturePanel(_ fluent: FluentThemeData) -> Widget {
        let start = [NSHomeDirectory() + "/Pictures", NSHomeDirectory() + "/Desktop", NSHomeDirectory()]
            .first { FileManager.default.fileExists(atPath: $0) } ?? NSHomeDirectory()
        return Column(crossAxisAlignment: .stretch, children: [
            _heading("Insert Picture", fluent),
            Expanded(child: FluentFilePanel(
                mode: .open, initialDirectory: start,
                extensions: ["png", "jpg", "jpeg", "gif", "webp", "bmp"],
                onDone: { [onClose, onPicturePath] path in
                    guard let path else { onClose(); return }
                    onPicturePath(path)
                })),
        ])
    }

    private func _info(_ fluent: FluentThemeData) -> Widget {
        let s = session.summary
        let rows: [(String, String)] = [
            ("Location", session.path ?? "Not saved yet"),
            ("Pages", "\(session.pageInfo.count)"),
            ("Words", "\(s.words)"),
            ("Characters", "\(s.characters)"),
            ("Paragraphs", "\(s.paragraphs)"),
            ("Paper", session.pageSetup.isLandscape ? "Landscape" : "Portrait"),
        ]
        return Column(crossAxisAlignment: .start, children: [_heading("Info", fluent)] + rows.map { k, v in
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8), child: Row(children: [
                SizedBox(width: 120, height: nil, child: Text(k, style: fluent.typography.body?.copyWith(
                    color: fluent.resources.textFillColorSecondary))),
                Text(v, style: fluent.typography.body),
            ]))
        })
    }

    private func _export(_ fluent: FluentThemeData) -> Widget {
        Column(crossAxisAlignment: .start, children: [
            _heading("Export", fluent),
            Text("Choose a format. The file lands beside the document, or in Documents.",
                 style: fluent.typography.body?.copyWith(color: fluent.resources.textFillColorSecondary)),
            Chrome.vgap(16),
            Row(children: [
                _template("PDF (.pdf)", FluentSystemIcons.documentPdf, fluent) { [session] in session.onExport?("pdf") },
                Chrome.gap(16),
                _template("Word (.docx)", FluentSystemIcons.document, fluent) { [session] in session.onExport?("docx") },
                Chrome.gap(16),
                _template("Markdown (.md)", FluentSystemIcons.document, fluent) { [session] in session.onExport?("md") },
                Chrome.gap(16),
                _template("Rich Text (.rtf)", FluentSystemIcons.document, fluent) { [session] in session.onExport?("rtf") },
                Chrome.gap(16),
                _template("Plain Text (.txt)", FluentSystemIcons.document, fluent) { [session] in session.onExport?("txt") },
            ]),
        ])
    }

    private func _simple(_ title: String, _ body: String, _ fluent: FluentThemeData,
                         action: (String, () -> Void)? = nil) -> Widget {
        var children: [Widget] = [
            _heading(title, fluent),
            Text(body, style: fluent.typography.body),
        ]
        if let action {
            children.append(Chrome.vgap(16))
            children.append(Row(children: [FilledButton(onPressed: action.1, child: Text(action.0))]))
        }
        return Column(crossAxisAlignment: .start, children: children)
    }

    private static func _daypart() -> String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "morning" : h < 18 ? "afternoon" : "evening"
    }

    private static func _today() -> String {
        let f = DateFormatter()
        f.dateStyle = .long
        return f.string(from: Date())
    }
}
