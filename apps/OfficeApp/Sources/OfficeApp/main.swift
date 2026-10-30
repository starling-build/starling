// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Office — entry point. Picks the windowed host for this platform (or runs
// as a Starling shell child when FLUTTER_DMABUF_SOCKET is set) and mounts
// the Fluent-rooted app.
//
//   swift run OfficeApp [file]                 open a document
//   OfficeApp --convert in.rtf out.docx        convert between formats, no window
//   OFFICE_DEMO_PAGES=200 swift run OfficeApp  the Phase 0 perf document

import Flutter
import FlutterSwiftBridge
import Foundation

#if os(Windows)
import FlutterWin32
#elseif os(macOS)
import FlutterCocoa
#elseif os(iOS)
import FlutterUIKit
#elseif STARLING_GTK
import FlutterGTK
#elseif os(WASI)
import FlutterWeb
#endif

#if os(Windows)
Win32WindowedHost.install()
#elseif os(macOS)
CocoaWindowedHost.install()
#elseif os(iOS)
UIKitWindowedHost.install()
#elseif STARLING_GTK
GTKWindowedHost.install()
#elseif os(WASI)
WebWindowedHost.install()
#endif

private func windowMetric(_ key: String, _ fallback: Int) -> Int {
    guard let v = ProcessInfo.processInfo.environment[key], let n = Int(v), n > 0
    else { return fallback }
    return n
}

// The command-line modes — a benchmark and a converter — need a process
// with arguments and files, which a tab is not.
#if !os(WASI)
/// No host boots for the command-line modes, so nobody hands the bridge its
/// ICU data; without it a paragraph's lines break between characters. Same
/// file the hosts use.
func initializeHeadlessText() {
    // The bridge's ICU starts empty, and without its data every paragraph
    // wraps between characters instead of words (sdk/CLAUDE.md) — which
    // reads as a layout bug in whatever is measured. A bare `swift build`
    // binary has no data/ beside it: STARLING_ICU names the file, or the
    // loaded FlutterMacOS.framework's own copy serves.
    let exeDir = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
        .deletingLastPathComponent().path
    var candidates = [exeDir + "/data/icudtl.dat", exeDir + "/../Resources/data/icudtl.dat",
                      exeDir + "/../share/starling/icudtl.dat"]
    if let env = ProcessInfo.processInfo.environment["STARLING_ICU"], !env.isEmpty { candidates.insert(env, at: 0) }
    #if os(macOS)
    for framework in Bundle.allFrameworks where framework.bundlePath.hasSuffix("FlutterMacOS.framework") {
        candidates.append(framework.bundlePath + "/Resources/icudtl.dat")
    }
    #endif
    for candidate in candidates where FileManager.default.fileExists(atPath: candidate) {
        _ = flutter.swift_bridge.InitializeICU(candidate)
        break
    }
    OfficeFonts.register()
}

// `--bench [pages]`: the perf gate without a window. Lays out the generated
// document, then types into a paragraph in the middle, re-laying out and
// painting the page around it after each keystroke, and prints the initial
// layout time and the per-keystroke layout and paint costs. The gate in
// docs/plans/office.md: ~100 µs layout and ~150 µs paint per keystroke on
// 200 pages.
if let i = CommandLine.arguments.firstIndex(of: "--bench") {
    initializeHeadlessText()
    let pages = i + 1 < CommandLine.arguments.count ? Int(CommandLine.arguments[i + 1]) ?? 200 : 200
    let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
    let setup = PageSetup.letter
    let controller = RichDocumentController()
    controller.load(DemoDocument.make(pages: pages))
    let layout = RichLayout(theme: theme, paragraphCount: controller.document.paragraphs.count)
    layout.scale = 1.0
    layout.pageSetup = setup
    layout.width = setup.columnWidth * theme.pixelsPerPoint
    func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
    let t0 = now()
    _ = controller.drainChanges()
    layout.ensureLaidOut(controller.document)
    let initialMs = Double(now() - t0) / 1e6
    let n = controller.document.paragraphs.count
    let target = n / 2
    controller.moveTo(RichPosition(paragraph: target, offset: 5), extend: false)
    var layoutUs: [Int] = [], paintUs: [Int] = []
    for k in 0 ..< 60 {
        controller.insertText(k % 7 == 6 ? " " : "x")
        let t1 = now()
        layout.apply(controller.drainChanges(), paragraphCount: controller.document.paragraphs.count)
        layout.ensureLaidOut(controller.document)
        let t2 = now()
        // Paint the page the caret is on, as the window would.
        let page = layout.page(atCanvasY: layout.canvasCaretRect(controller.caret, controller.document).top)
        let rect = layout.pageRect(page)
        let recorder = NativePictureRecorder()
        let canvas = NativeCanvas(recorder: recorder, cullRect: rect)
        canvas.translate(0, -rect.top)
        layout.paint(canvas, visible: rect, document: controller.document, selection: controller.selection,
                     caret: nil, pageBackground: nil)
        _ = recorder.endRecording()
        let t3 = now()
        layoutUs.append(Int((t2 - t1) / 1000))
        paintUs.append(Int((t3 - t2) / 1000))
    }
    func stats(_ v: [Int]) -> String {
        let s = v.sorted()
        return "median \(s[s.count / 2]) µs, p90 \(s[s.count * 9 / 10]) µs, max \(s[s.count - 1]) µs"
    }
    // The incremental passes must land exactly where a fresh layout does.
    let fresh = RichLayout(theme: theme, paragraphCount: controller.document.paragraphs.count)
    fresh.scale = 1.0
    fresh.pageSetup = setup
    fresh.width = layout.width
    fresh.ensureLaidOut(controller.document)
    let same = fresh.pieces == layout.pieces && fresh.pageCount == layout.pageCount
    print("bench: \(pages) pages, \(n) paragraphs, \(layout.pageCount) laid-out pages; incremental pagination \(same ? "matches" : "DIFFERS FROM") a fresh layout")
    if !same { exit(2) }
    print("initial layout: \(String(format: "%.0f", initialMs)) ms")
    print("per keystroke layout: \(stats(layoutUs))")
    print("per keystroke paint:  \(stats(paintUs))")
    exit(0)
}

// `--layout <in>`: the document's line breaks and pages, as text, for
// comparing one layout with another (native against the browser's
// `starling.debug('layout')`, a file against its own round trip).
// `--layout welcome` is the document a fresh window shows.
if let i = CommandLine.arguments.firstIndex(of: "--layout"), i + 1 < CommandLine.arguments.count {
    initializeHeadlessText()
    do {
        let src = CommandLine.arguments[i + 1]
        if src == "welcome" {
            print(OfficeLayoutDump.text(WelcomeDocument.make(), pageSetup: .letter), terminator: "")
            exit(0)
        }
        let opened = try OfficeFormats.read(src)
        print(OfficeLayoutDump.text(opened.document, pageSetup: opened.pageSetup ?? .letter), terminator: "")
        exit(0)
    } catch {
        FileHandle.standardError.write("layout failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

// `--sheet-layout <file.xlsx|csv>`: the active sheet as the grid lays it out
// (SheetLayoutDump) — the native half of test/sheets-layout.sh, which diffs
// it against `starling.debug('sheet')` in the browser.
if let i = CommandLine.arguments.firstIndex(of: "--sheet-layout"), i + 1 < CommandLine.arguments.count {
    initializeHeadlessText()
    do {
        let src = CommandLine.arguments[i + 1]
        let data = try Data(contentsOf: URL(fileURLWithPath: src))
        let c = WorkbookController()
        if src.pathExtension.lowercased() == "xlsx" {
            c.load(try Xlsx.read(data))
        } else {
            c.load(Csv.read(String(decoding: data, as: UTF8.self), name: src.lastPathComponent.deletingPathExtension))
        }
        print(SheetLayoutDump.text(c), terminator: "")
        exit(0)
    } catch {
        FileHandle.standardError.write("sheet layout failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

// `--deck <file.pptx>`: what the Slides reader made of a deck, one line per
// shape — kind, frame in points, fill, and the start of its text. The
// round-trip gate compares these before and after a save.
if let i = CommandLine.arguments.firstIndex(of: "--deck"), i + 1 < CommandLine.arguments.count {
    initializeHeadlessText()
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        let (state, theme, _) = try Pptx.read(data)
        print(SlidesDump.text(state, theme: theme), terminator: "")
        exit(0)
    } catch {
        FileHandle.standardError.write("deck failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

// `--deck-pdf <in.pptx> <out.pdf>`: what File → Export → PDF would write,
// without a window — this app's own drawing of every slide, for comparing
// against PowerPoint's (test/pptx-app-render.sh).
if let i = CommandLine.arguments.firstIndex(of: "--deck-pdf"), i + 2 < CommandLine.arguments.count {
    initializeHeadlessText()
    do {
        let src = CommandLine.arguments[i + 1], dst = CommandLine.arguments[i + 2]
        let data = try Data(contentsOf: URL(fileURLWithPath: src))
        let (state, theme, package) = try Pptx.read(data)
        let deck = DeckController()
        deck.load(state, theme: theme, package: package)
        let cache = SlideTextCache()
        var done: Bool? = nil
        Task { @MainActor in
            done = await SlidesPdf.write(deck, cache: cache, to: dst, title: src.lastPathComponent)
        }
        let deadline = Date().addingTimeInterval(120)
        while done == nil && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        guard done == true else {
            FileHandle.standardError.write("deck pdf failed: \(done == nil ? "timed out" : "could not write")\n".data(using: .utf8)!)
            exit(1)
        }
        print("\(src) -> \(dst): \(deck.slides.filter { !$0.hidden }.count) pages")
        exit(0)
    } catch {
        FileHandle.standardError.write("deck pdf failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

// `--deck-roundtrip <in.pptx> <out.pptx>`: read, write, read again; the two
// dumps must match. Exit 3 when they differ (the diff goes to stderr).
if let i = CommandLine.arguments.firstIndex(of: "--deck-roundtrip"), i + 2 < CommandLine.arguments.count {
    initializeHeadlessText()
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        let (state, theme, package) = try Pptx.read(data)
        let out = try PptxWriter.write(state, theme: theme, package: package)
        try out.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 2]))
        let (again, theme2, _) = try Pptx.read(out)
        let a = SlidesDump.text(state, theme: theme), b = SlidesDump.text(again, theme: theme2)
        if a == b {
            print("round trip: \(state.slides.count) slides identical (\(data.count) -> \(out.count) bytes)")
            exit(0)
        }
        let la = a.split(separator: "\n"), lb = b.split(separator: "\n")
        // Same words, numbers within a tenth of a point: a frame inside a
        // flattened group lands between EMU steps and rounds on the way out.
        func same(_ x: Substring, _ y: Substring) -> Bool {
            if x == y { return true }
            func split(_ s: Substring) -> ([String], [Double]) {
                var words: [String] = [], nums: [Double] = [], cur = ""
                for ch in s {
                    if ch.isNumber || ch == "." || ch == "-" { cur.append(ch) } else {
                        if let v = Double(cur) { nums.append(v); words.append("#") } else if !cur.isEmpty { words.append(cur) }
                        cur = ""; words.append(String(ch))
                    }
                }
                if let v = Double(cur) { nums.append(v); words.append("#") } else if !cur.isEmpty { words.append(cur) }
                return (words, nums)
            }
            let (wx, nx) = split(x), (wy, ny) = split(y)
            return wx == wy && nx.count == ny.count && zip(nx, ny).allSatisfy { abs($0 - $1) <= 0.11 }
        }
        if la.count == lb.count && zip(la, lb).allSatisfy({ same($0, $1) }) {
            print("round trip: \(state.slides.count) slides match (within 0.1 pt) (\(data.count) -> \(out.count) bytes)")
            exit(0)
        }
        var shown = 0
        for (x, y) in zip(la, lb) where !same(x, y) && shown < 20 {
            FileHandle.standardError.write("- \(x)\n+ \(y)\n".data(using: .utf8)!)
            shown += 1
        }
        if la.count != lb.count { FileHandle.standardError.write("line counts \(la.count) vs \(lb.count)\n".data(using: .utf8)!) }
        exit(3)
    } catch {
        FileHandle.standardError.write("round trip failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

// `--deck-showcase <out.pptx>`: the sample plus everything else this app
// writes — one chart of each kind (labels, axis titles, stacking), header and
// footer with fields on every slide, a fade transition — for opening in
// PowerPoint itself.
if let i = CommandLine.arguments.firstIndex(of: "--deck-showcase"), i + 1 < CommandLine.arguments.count {
    initializeHeadlessText()
    let deck = SlidesSample.make()
    for type in ChartType.allCases {
        let slide = deck.addSlide(.titleOnly)
        if let title = slide.shapes.first(where: { $0.role == .title })?.text { title.insertText("\(type.name) chart") }
        let shape = deck.addChart(type)
        shape.frame = Rect.fromLTWH(shape.frame.left, shape.frame.top + 40, shape.frame.width, shape.frame.height)
        var c = shape.chart!
        c.dataLabels = type == .column || type == .pie
        if type == .bar { c.stacked = true }
        if type == .line { c.valueAxisTitle = "Sales"; c.categoryAxisTitle = "Quarter" }
        deck.setChart(shape, c)
    }
    var hf = DeckController.HeaderFooter()
    hf.date = true
    hf.slideNumber = true
    hf.footer = "Starling Slides showcase"
    hf.skipTitleSlides = true
    deck.applyHeaderFooter(hf, toAll: true)
    deck.select(1)
    deck.setTransition(.fade)
    do {
        try Pptx.write(deck).write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        print("wrote \(deck.slides.count) slides to \(CommandLine.arguments[i + 1])")
        exit(0)
    } catch {
        FileHandle.standardError.write("showcase failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

// `--deck-sample <out.pptx>`: a new deck built through the controller — every
// layout, typed text, drawn shapes, notes — written with our own templates.
// What the new-deck path of the writer is checked with.
if let i = CommandLine.arguments.firstIndex(of: "--deck-sample"), i + 1 < CommandLine.arguments.count {
    initializeHeadlessText()
    let deck = SlidesSample.make()
    do {
        try Pptx.write(deck).write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        print("wrote \(deck.slides.count) slides to \(CommandLine.arguments[i + 1])")
        exit(0)
    } catch {
        FileHandle.standardError.write("sample failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

// `--xlsx-check file.xlsx…`: recalculate every formula and compare with
// the values Excel cached in the file (SheetsCheck.swift).
if let i = CommandLine.arguments.firstIndex(of: "--xlsx-check"), i + 1 < CommandLine.arguments.count {
    exit(SheetsCheck.run(Array(CommandLine.arguments[(i + 1)...])))
}

// `--sheet-pdf <in.xlsx> <out.pdf>`: what printing the entire workbook to
// PDF would write, without a window — every visible sheet through the
// grid's own painter, for comparing against Excel's
// (test/xlsx-app-render.sh). `SHEET_PDF_MAX_PAGES` caps the job (200).
if let i = CommandLine.arguments.firstIndex(of: "--sheet-pdf"), i + 2 < CommandLine.arguments.count {
    initializeHeadlessText()
    do {
        let src = CommandLine.arguments[i + 1], dst = CommandLine.arguments[i + 2]
        let data = try Data(contentsOf: URL(fileURLWithPath: src))
        let c = WorkbookController()
        c.load(try Xlsx.read(data))
        let grid = SheetGridState(headless: c)
        let cap = Int(ProcessInfo.processInfo.environment["SHEET_PDF_MAX_PAGES"] ?? "") ?? 200
        var done: Bool? = nil
        Task { @MainActor in
            done = await grid.writePdf(to: dst, title: src.lastPathComponent.deletingPathExtension, filePath: src,
                                       wholeBook: true, maxPages: cap)
        }
        let deadline = Date().addingTimeInterval(120)
        while done == nil && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        guard done == true else {
            FileHandle.standardError.write("sheet pdf failed: \(done == nil ? "timed out" : "nothing to print, or could not write")\n".data(using: .utf8)!)
            exit(1)
        }
        print("\(src) -> \(dst)")
        exit(0)
    } catch {
        FileHandle.standardError.write("sheet pdf failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

// `--xlsx-roundtrip <in> <out>`: read a workbook and write it back, for
// checking our .xlsx against Excel's importers (qlmanage) and its parts.
if let i = CommandLine.arguments.firstIndex(of: "--xlsx-roundtrip"), i + 2 < CommandLine.arguments.count {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        let c = WorkbookController()
        c.load(try Xlsx.read(data))
        let out = try Xlsx.write(c.book)
        try out.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 2]))
        let cells = c.book.sheets.reduce(0) { $0 + $1.cells.count }
        print("round trip: \(c.book.sheets.count) sheets, \(cells) cells (\(data.count) -> \(out.count) bytes)")
        exit(0)
    } catch {
        FileHandle.standardError.write("round trip failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

// Build the website's editable Slides source (wide or portrait).
if let i = CommandLine.arguments.firstIndex(of: "--landing-deck"), i + 1 < CommandLine.arguments.count {
    initializeHeadlessText()
    let args = CommandLine.arguments
    do {
        let deck = OfficeLandingDeck.make(portrait: args.contains("--portrait"))
        try Pptx.write(deck).write(to: URL(fileURLWithPath: args[i + 1]))
        print("Wrote \(deck.slides.count) landing slides")
        exit(0)
    } catch { print("Landing deck export failed: \(error)"); exit(1) }
}

// `--convert <in> <out>`: the formats without the window, for scripts and
// for checking our output against other readers (`textutil`, LibreOffice).
// `--read-bench file…`: what opening each file costs, step by step
// (ReadBench.swift); `--read-bench-make <pages> <out.docx>` writes the
// generated document for it to open.
if let i = CommandLine.arguments.firstIndex(of: "--read-bench-make"), i + 2 < CommandLine.arguments.count {
    exit(ReadBench.make(pages: Int(CommandLine.arguments[i + 1]) ?? 200, to: CommandLine.arguments[i + 2]))
}
if let i = CommandLine.arguments.firstIndex(of: "--read-bench"), i + 1 < CommandLine.arguments.count {
    exit(ReadBench.run(Array(CommandLine.arguments[(i + 1)...])))
}

// `--trace-rules <in>`: the document laid out as `--convert in out.pdf` lays
// it out, without the PDF; with OFFICE_RULE_TRACE=<file> set, the rules it
// reaches (`RuleTrace.hit`) are appended there. Several times faster than
// a conversion, for finding which documents a change can move.
if let i = CommandLine.arguments.firstIndex(of: "--trace-rules"), i + 1 < CommandLine.arguments.count {
    let src = CommandLine.arguments[i + 1]
    initializeHeadlessText()
    RuleTrace.document = src.lastPathComponent.deletingPathExtension
    do {
        let opened = try OfficeFormats.read(src)
        let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
        theme.fontFamilyResolver = OfficeFonts.drawn
        theme.faceResolver = OfficeFonts.face
        theme.complexFaceResolver = OfficeFonts.complexFace
        theme.averageCharWidth = OfficeFonts.averageCharWidth
        theme.symbolGlyphs = { face, text in face.map { Metafile.symbols(text, face: $0) } ?? text }
        theme.symbolAdvance = Metafile.symbolAdvance
        theme.wordRules = true
        theme.disablesLigatures = true
        _ = PdfExport.write(opened.document, pageSetup: opened.pageSetup ?? .letter, theme: theme,
                            to: "", title: src.lastPathComponent, layoutOnly: true)
        exit(0)
    } catch {
        FileHandle.standardError.write("trace failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

if let i = CommandLine.arguments.firstIndex(of: "--convert"), i + 2 < CommandLine.arguments.count {
    let src = CommandLine.arguments[i + 1]
    let dst = CommandLine.arguments[i + 2]
    initializeHeadlessText()
    RuleTrace.document = src.lastPathComponent.deletingPathExtension
    do {
        let opened = try src == "welcome"
            ? OpenedDocument(document: WelcomeDocument.make(), pageSetup: .letter)
            : OfficeFormats.read(src)
        if dst.pathExtension.lowercased() == "pdf" {
            let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
            theme.fontFamilyResolver = OfficeFonts.drawn
            theme.faceResolver = OfficeFonts.face
            theme.complexFaceResolver = OfficeFonts.complexFace
            theme.averageCharWidth = OfficeFonts.averageCharWidth
            theme.symbolGlyphs = { face, text in face.map { Metafile.symbols(text, face: $0) } ?? text }
            theme.symbolAdvance = Metafile.symbolAdvance
            theme.wordRules = true
            theme.disablesLigatures = true
            guard PdfExport.write(opened.document, pageSetup: opened.pageSetup ?? .letter, theme: theme,
                                  to: dst, title: src.lastPathComponent) else {
                FileHandle.standardError.write("convert failed: could not write PDF\n".data(using: .utf8)!)
                exit(1)
            }
        } else {
            try OfficeFormats.write(opened.document, to: dst, pageSetup: opened.pageSetup ?? .letter)
        }
        print("\(src) -> \(dst): \(opened.document.paragraphs.count) paragraphs, \(opened.document.wordCount) words")
        exit(0)
    } catch {
        FileHandle.standardError.write("convert failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}
#endif

let initialPath: String? = {
    let args = CommandLine.arguments
    if args.count > 1 && !args[1].hasPrefix("-") { return args[1].portablePath }
    return nil
}()

// `--slides` starts on a blank deck; a .pptx path starts in Slides too.
let initialKind: DocumentKind = CommandLine.arguments.contains("--slides") ? .presentation
    : CommandLine.arguments.contains("--sheets") ? .workbook
    : initialPath.map { DocumentKind.kind(forPath: $0) } ?? .document

#if os(macOS)
ScriptedInput.startIfRequested()
#endif

runStarlingApp(title: initialKind.appName,
               width: windowMetric("STARLING_WINDOW_W", 1440),
               height: windowMetric("STARLING_WINDOW_H", 900)) {
    #if os(WASI)
    if WebPlatform.defaultRouteName.hasPrefix("/office-landing") {
        FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeLandingView(), title: "Starling Office")
    } else {
        OfficeRoot(initialPath: initialPath, kind: initialKind)
    }
    #else
    OfficeRoot(initialPath: initialPath, kind: initialKind)
    #endif
}
