// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Backstage — what Word shows for File: a full-window page with the accent
// rail on the left (Home, New, Open, Info, Save, Save As, Export, Print,
// Close) and the chosen page on the right.

import Flutter
import OfficeText
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

enum BackstagePage: Int, CaseIterable {
    case home, new, open, info, save, saveAs, export, print, options, close
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
        case .options: return "Options"
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
        case .options: return FluentSystemIcons.settings
        case .close: return FluentSystemIcons.chromeClose
        case .insertPicture: return FluentSystemIcons.image
        }
    }
}

final class Backstage: StatelessWidget {
    let session: OfficeSession
    let page: BackstagePage
    let recent: [String]
    /// What the window's status bar is saying. The backstage covers that
    /// bar, so a save that failed from here said nothing at all.
    let notice: String?
    let onPage: (BackstagePage) -> Void
    let onClose: () -> Void
    let onOpenPath: (String) -> Void
    let onSavePath: (String) -> Void
    let onPicturePath: (String) -> Void

    init(session: OfficeSession, page: BackstagePage, recent: [String], notice: String? = nil,
         onPage: @escaping (BackstagePage) -> Void, onClose: @escaping () -> Void,
         onOpenPath: @escaping (String) -> Void, onSavePath: @escaping (String) -> Void,
         onPicturePath: @escaping (String) -> Void) {
        self.session = session
        self.page = page
        self.recent = recent
        self.notice = notice
        self.onPage = onPage
        self.onClose = onClose
        self.onOpenPath = onOpenPath
        self.onSavePath = onSavePath
        self.onPicturePath = onPicturePath
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        return ColoredBox(color: OfficeAppearance.surface(fluent), child: Row(
            crossAxisAlignment: .stretch, children: [
                _rail(fluent),
                Expanded(child: Padding(padding: EdgeInsets(left: 40, top: 32, right: 40, bottom: 32),
                                        child: _content(fluent))),
            ]))
    }

    // MARK: Rail

    private func _rail(_ fluent: FluentThemeData) -> Widget {
        let accent = OfficeAppearance.titleBar
        let ink = OfficeAppearance.white
        var items: [Widget] = [
            Padding(padding: EdgeInsets(left: 8, top: 8, right: 8, bottom: 16), child: Row(children: [
                FlatButton(child: Icon(FluentSystemIcons.back, size: 20, color: ink),
                           tip: "Back to document", width: 36, height: 36, onAccent: true,
                           action: { [session, onClose] in session.unsavedPrompt = nil; onClose() }),
                Chrome.gap(10),
                Text(session.kind.appName, style: fluent.typography.bodyStrong?.copyWith(color: ink)),
            ])),
        ]
        for p in BackstagePage.allCases where p != .insertPicture {
            let selected = p == page
            items.append(GestureDetector(onTap: { [self] in self._go(p) }, child: DecoratedBox(
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
        if let pending = session.unsavedPrompt { return _unsaved(pending, fluent) }
        switch page {
        case .home: return _home(fluent)
        case .new: return _new(fluent)
        case .open: return _panel(.open, fluent)
        case .save, .saveAs: return _panel(.save, fluent)
        case .info: return _info(fluent)
        case .export: return _export(fluent)
        case .print: return _simple("Print", hostPrintPDF != nil
                                    ? "Prints the document as laid out on screen, through the system print dialog."
                                    : "This host has no print dialog; Export makes a PDF to print elsewhere.",
                                    fluent, action: hostPrintPDF != nil
                                    ? ("Print…", { [session] in session.onPrint?() })
                                    : ("Export PDF", { [session] in session.onExport?("pdf") }))
        case .options: return _options(fluent)
        case .insertPicture: return _picturePanel(fluent)
        case .close: return _simple("Close", "Close the document and start a blank one.", fluent, action: ("Close document", { [session] in session.replacing { session.onNew?() } }))
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
                onPressed: { [session, onOpenPath] in session.replacing { onOpenPath(path) } },
                icon: Icon(FluentSystemIcons.document, size: 16, color: fluent.resources.textFillColorPrimary),
                text: Text(path.lastPathComponent),
                trailing: Text(path.deletingLastPathComponent.displayPath,
                               style: fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary))))
        }
        return Column(crossAxisAlignment: .start, children: [
            _heading("Good \(Self._daypart())", fluent),
            Row(children: [
                _template("Blank document", FluentSystemIcons.documentAdd, fluent) { [session] in session.replacing { session.onNewKind?(.document) } },
                Chrome.gap(16),
                _template("Blank presentation", FluentSystemIcons.desktop, fluent) { [session] in session.replacing { session.onNewKind?(.presentation) } },
                Chrome.gap(16),
                _template("Blank workbook", FluentSystemIcons.table, fluent) { [session] in session.replacing { session.onNewKind?(.workbook) } },
                Chrome.gap(16),
                _template("Open", FluentSystemIcons.folderOpen, fluent) { [self] in self._go(.open) },
            ]),
            Chrome.vgap(28),
            Column(crossAxisAlignment: .start, children: recentRows),
        ])
    }

    private func _new(_ fluent: FluentThemeData) -> Widget {
        Column(crossAxisAlignment: .start, children: [
            _heading("New", fluent),
            Row(children: [
                _template("Blank document", FluentSystemIcons.documentAdd, fluent) { [session] in session.replacing { session.onNewKind?(.document) } },
                Chrome.gap(16),
                _template("Blank presentation", FluentSystemIcons.desktop, fluent) { [session] in session.replacing { session.onNewKind?(.presentation) } },
                Chrome.gap(16),
                _template("Blank workbook", FluentSystemIcons.table, fluent) { [session] in session.replacing { session.onNewKind?(.workbook) } },
            ] + (session.kind != .document ? [] : [
                Chrome.gap(16),
                _template("Letter", FluentSystemIcons.document, fluent) { [session] in session.replacing {
                    session.onNew?()
                    let c = session.controller
                    c.insertText("[Your name]\n[Street address]\n[City, State ZIP]\n\n\(Self._today())\n\nDear [Recipient],\n\n[Body]\n\nSincerely,\n\n[Your name]")
                    c.moveTo(.start, extend: false)
                } },
                Chrome.gap(16),
                _template("Report", FluentSystemIcons.document, fluent) { [session] in session.replacing {
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
                } },
            ])),
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

    /// Where a rail item or tile goes. In a tab the Open and Save pages
    /// would list directories the page cannot see: they hand over to the
    /// browser's picker and download instead, and Backstage closes.
    private func _go(_ p: BackstagePage) {
        #if os(WASI)
        switch p {
        case .open: onClose(); session.onOpen?(); return
        case .save: onClose(); session.onSave?(); return
        case .saveAs: onClose(); session.onSaveAs?(); return
        default: break
        }
        #endif
        session.unsavedPrompt = nil
        onPage(p)
    }

    private func _panel(_ mode: FilePanelMode, _ fluent: FluentThemeData) -> Widget {
        let dir = session.path.map { $0.deletingLastPathComponent }
            ?? homeDirectory() + "/Documents"
        let start = FileManager.default.fileExists(atPath: dir) ? dir : homeDirectory()
        let suggested = session.path.map { $0.lastPathComponent }
            ?? (session.kind == .presentation ? "Presentation1.pptx" : session.kind == .workbook ? "Book1.xlsx" : "Document1.docx")
        var rows: [Widget] = [_heading(mode == .open ? "Open" : "Save As", fluent)]
        if let notice {
            rows.append(Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 12),
                                child: Text(notice, style: fluent.typography.body)))
        }
        return Column(crossAxisAlignment: .stretch, children: rows + [
            Expanded(child: FluentFilePanel(
                mode: mode, initialDirectory: start, suggestedName: suggested,
                extensions: mode == .open ? OfficeFormats.readable + ["pptx", "xlsx", "csv", "tsv"]
                    : session.kind == .presentation ? ["pptx"] : session.kind == .workbook ? ["xlsx", "csv", "tsv"] : OfficeFormats.writable,
                onDone: { [session, onClose, onOpenPath, onSavePath] path in
                    guard let path else { onClose(); return }
                    if mode == .open { session.replacing { onOpenPath(path) } } else { onSavePath(path) }
                })),
        ])
    }

    private func _picturePanel(_ fluent: FluentThemeData) -> Widget {
        let start = [homeDirectory() + "/Pictures", homeDirectory() + "/Desktop", homeDirectory()]
            .first { FileManager.default.fileExists(atPath: $0) } ?? homeDirectory()
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
            ("Location", session.path?.displayPath ?? "Not saved yet"),
            ("Pages", "\(session.pageInfo.count)"),
            ("Words", "\(s.words)"),
            ("Characters", "\(s.characters)"),
            ("Paragraphs", "\(s.paragraphs)"),
            ("Paper", session.pageSetup.isLandscape ? "Landscape" : "Portrait"),
        ]
        let secondary = fluent.typography.body?.copyWith(color: fluent.resources.textFillColorSecondary)
        return Column(crossAxisAlignment: .start, children: [_heading("Info", fluent)] + rows.map { k, v in
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8), child: Row(children: [
                SizedBox(width: 120, height: nil, child: Text(k, style: secondary)),
                Text(v, style: fluent.typography.body),
            ]))
        } + [
            Chrome.vgap(24),
            _heading("About \(session.kind.appName)", fluent),
            Text("Built with Fluent UI System Icons and the fluent_ui controls (MIT), the Selawik, Liberation, Carlito, Poppins, Work Sans and Libre Franklin fonts (SIL OFL), the Caladea font (Apache 2.0), the TeX Gyre fonts (GUST Font License), zlib, and the Flutter engine (BSD).",
                 style: secondary),
            Chrome.vgap(4),
            Text("The full notices ship with the app as THIRD_PARTY_NOTICES.md.", style: secondary),
        ])
    }

    /// The user's settings: which faces draw a document's fonts.
    private func _options(_ fluent: FluentThemeData) -> Widget {
        let secondary = fluent.typography.body?.copyWith(color: fluent.resources.textFillColorSecondary)
        let installed = OfficeFonts.fontSource == .local
        func choice(_ title: String, _ detail: String, _ on: Bool, _ local: Bool) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 12), child: Column(crossAxisAlignment: .start, children: [
                Checkbox(checked: on, onChanged: { [self] _ in
                    OfficeSettings.useInstalledFonts = local
                    _go(.options)
                }, content: Text(title, style: fluent.typography.body)),
                Padding(padding: EdgeInsets(left: 28, top: 2, right: 0, bottom: 0), child: Text(detail, style: secondary)),
            ]))
        }
        var rows: [Widget] = [
            _heading("Options", fluent),
            Text("Fonts", style: fluent.typography.subtitle),
            Chrome.vgap(8),
        ]
        #if os(WASI)
        rows.append(Text("Documents are drawn with Starling's matching fonts.", style: secondary))
        #else
        rows.append(choice("Use fonts installed on this computer",
                           "A document's fonts are drawn with this computer's own, where it has them, and with Starling's matching fonts where it does not.",
                           installed, true))
        rows.append(choice("Use Starling's matching fonts",
                           "Always draw with the fonts Starling ships, so a document lays out the same on every computer.",
                           !installed, false))
        rows.append(Text(OfficeFonts.fontSourcePinned
                         ? "OFFICE_FONT_SOURCE is set for this session, and decides over this setting."
                         : "Applies to documents opened from now on.", style: secondary))
        #endif
        return Column(crossAxisAlignment: .start, children: rows)
    }

    private func _export(_ fluent: FluentThemeData) -> Widget {
        Column(crossAxisAlignment: .start, children: [
            _heading("Export", fluent),
            Text("Choose a format. The file lands beside the document, or in Documents.",
                 style: fluent.typography.body?.copyWith(color: fluent.resources.textFillColorSecondary)),
            Chrome.vgap(16),
            session.kind == .workbook ? Row(children: [
                _template("PDF (.pdf)", FluentSystemIcons.documentPdf, fluent) { [session] in session.onExport?("pdf") },
                Chrome.gap(16),
                _template("CSV (.csv)", FluentSystemIcons.table, fluent) { [session] in session.onExport?("csv") },
            ]) : session.kind == .presentation ? Row(children: [
                _template("PDF (.pdf)", FluentSystemIcons.documentPdf, fluent) { [session] in session.onExport?("pdf") },
                Chrome.gap(16),
                _template("PowerPoint (.pptx)", FluentSystemIcons.desktop, fluent) { [session] in session.onExport?("pptx") },
            ]) : Row(children: [
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

    /// The question before a document with unsaved changes is replaced:
    /// save it first, let the changes go, or stay.
    private func _unsaved(_ pending: @escaping () -> Void, _ fluent: FluentThemeData) -> Widget {
        let named = session.path != nil
        return Column(crossAxisAlignment: .start, children: [
            _heading("Save changes to \(session.title)?", fluent),
            Text(named ? "It has changes that have not been saved."
                       : "It has not been saved yet. Save it first, or its contents are lost.",
                 style: fluent.typography.body),
            Chrome.vgap(16),
            Row(children: [
                FilledButton(onPressed: { [session, onPage] in
                    session.unsavedPrompt = nil
                    guard named else { onPage(.saveAs); return }
                    session.onSave?()
                    // A save that failed has said so; the document stays.
                    if !session.dirty { pending() }
                }, child: Text(named ? "Save" : "Save As…")),
                Chrome.gap(8),
                Button(onPressed: { [session] in
                    session.unsavedPrompt = nil
                    session.discardRecoveryCopy()
                    pending()
                }, child: Text("Don't Save")),
                Chrome.gap(8),
                Button(onPressed: { [session, onPage, page] in
                    session.unsavedPrompt = nil
                    onPage(page)
                }, child: Text("Cancel")),
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

    static func todayLongDate() -> String { _today() }

    private static func _today() -> String {
        #if os(WASI)
        // DateFormatter is the legacy Foundation layer (and ICU). The
        // calendar's numbers are enough for the greeting's date.
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let months = ["January", "February", "March", "April", "May", "June", "July",
                      "August", "September", "October", "November", "December"]
        return "\(months[(parts.month ?? 1) - 1]) \(parts.day ?? 1), \(parts.year ?? 0)"
        #else
        let f = DateFormatter()
        f.dateStyle = .long
        return f.string(from: Date())
        #endif
    }
}
