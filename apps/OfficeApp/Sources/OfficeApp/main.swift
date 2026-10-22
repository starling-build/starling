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

// The wiki's stored form (docs/plans/wiki.md): a document as JSON, lossless.
//   --page-json <in.docx|rtf|md> <out.json>   read a file, write the page
//   --page-docx <in.json> <out.docx>          write a page back as a file
//   --page-roundtrip <in.docx|rtf|md>         read, encode, decode, compare;
//                                             prints OK or the first difference
// Paragraphs get ids on the way in (Word's own where the file had them).
// A site from a repository (docs/plans/site.md): the folder GitHub Pages
// serves, made from site.json, pages/*.json and the web build.
//   --site-build <repo> [--out <dir>] [--web <stage>] [--base /path/]
//   out defaults to <repo>/docs; web to STARLING_WEB_STAGE or the stage in
//   the working directory; base to site.json's, else "/".
if let i = CommandLine.arguments.firstIndex(of: "--site-build"), i + 1 < CommandLine.arguments.count {
    initializeHeadlessText()
    func option(_ name: String) -> String? {
        guard let j = CommandLine.arguments.firstIndex(of: name), j + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[j + 1]
    }
    let repo = CommandLine.arguments[i + 1]
    do {
        let summary = try SiteBuilder.build(repo: repo, out: option("--out") ?? repo + "/docs",
                                            web: option("--web") ?? SiteBuilder.defaultWebStage(), base: option("--base"))
        print("site-build: \(summary.pages) pages into \(summary.out) (base \(summary.base))")
        exit(0)
    } catch {
        FileHandle.standardError.write("site-build failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}
// Create a local publication; no network, commit, or remote configuration.
if let i = CommandLine.arguments.firstIndex(of: "--site-create"), i + 2 < CommandLine.arguments.count {
    do {
        var source: String?
        if let flag = CommandLine.arguments.firstIndex(of: "--from"), flag + 1 < CommandLine.arguments.count {
            source = CommandLine.arguments[flag + 1]
            initializeHeadlessText()
        }
        let path = try SiteCreation.create(title: CommandLine.arguments[i + 2], parent: CommandLine.arguments[i + 1], source: source)
        print("Created local publication: \(path)\nOpen site.json in Writer. Nothing has been uploaded.")
        exit(0)
    } catch {
        FileHandle.standardError.write("site-create failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}
//   --site-publish <repo> [--out <dir>] [--web <stage>] [-m <message>]
//   what the reader's Publish button runs: build into <repo>/<out> (docs),
//   git add -A, commit, push.
//   --site-import <repo> <file.docx|rtf|md> [--title T] [--under slug]
//   a document as a new page of the site (paragraph ids assigned, page
//   setup kept); prints the slug.
if let i = CommandLine.arguments.firstIndex(of: "--site-import"), i + 2 < CommandLine.arguments.count {
    initializeHeadlessText()
    func option(_ name: String) -> String? {
        guard let j = CommandLine.arguments.firstIndex(of: name), j + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[j + 1]
    }
    let file = CommandLine.arguments[i + 2]
    do {
        var opened = try OfficeFormats.read(file)
        opened.document.assignParagraphIDs()
        let title = option("--title") ?? file.lastPathComponent.deletingPathExtension
        let page = SitePage(document: opened.document, pageSetup: opened.pageSetup)
        let slug = try CommandLine.arguments.contains("--draft")
            ? SiteUnpublishedDrafts.create(repo: CommandLine.arguments[i + 1], title: title, page: page)
            : LocalSiteStore.addPage(repo: CommandLine.arguments[i + 1], title: title, page: page, under: option("--under"))
        print(slug)
        exit(0)
    } catch {
        FileHandle.standardError.write("site-import failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}
// Preview a revised source against an existing page; --apply saves locally.
// Publishing is a separate operation. The page URL/tree/title stay unchanged.
if let i = CommandLine.arguments.firstIndex(of: "--site-update"), i + 3 < CommandLine.arguments.count {
    initializeHeadlessText()
    do {
        let opened = try OfficeFormats.read(CommandLine.arguments[i + 3])
        let revision = try LocalSiteStore.prepareUpdate(repo: CommandLine.arguments[i + 1], slug: CommandLine.arguments[i + 2],
            page: SitePage(document: opened.document, pageSetup: opened.pageSetup))
        print(revision.summary)
        if CommandLine.arguments.contains("--apply") {
            try LocalSiteStore.applyUpdate(repo: CommandLine.arguments[i + 1], revision: revision)
            let held = try SiteDrafts.load(repo: CommandLine.arguments[i + 1], slug: CommandLine.arguments[i + 2]) != nil
                || SiteUnpublishedDrafts.load(repo: CommandLine.arguments[i + 1], slug: CommandLine.arguments[i + 2]) != nil
            print(held ? "Updated the separate local draft. Include it in publication review when ready; publishing excludes these draft edits."
                       : "Updated locally; page address unchanged. Publish when ready.")
        } else { print("Preview only; no files changed. Use --apply to replace the page, including local edits.") }
        exit(0)
    } catch {
        FileHandle.standardError.write("site-update failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}
// --site-draft <repo> <slug> start|include|set-aside|restore [--out docs]
// The same local draft choices as publication review; these actions do not upload.
if let i = CommandLine.arguments.firstIndex(of: "--site-draft"), i + 3 < CommandLine.arguments.count {
    do {
        let repo = CommandLine.arguments[i + 1], slug = CommandLine.arguments[i + 2]
        let out = CommandLine.arguments.firstIndex(of: "--out").flatMap { $0 + 1 < CommandLine.arguments.count ? CommandLine.arguments[$0 + 1] : nil } ?? "docs"
        switch CommandLine.arguments[i + 3] {
        case "start":
            try SiteDrafts.start(repo: repo, out: out, slug: slug)
            print("Separate local draft started. Publishing keeps the previously uploaded document.")
        case "include":
            if let draft = try SiteUnpublishedDrafts.load(repo: repo, slug: slug) {
                try SiteUnpublishedDrafts.include(repo: repo, expected: draft)
            } else {
                guard let draft = try SiteDrafts.load(repo: repo, slug: slug) else { throw SiteError("This page has no separate draft.") }
                try SiteDrafts.include(repo: repo, expected: draft)
            }
            print("Saved draft included in the next publication. Nothing has been uploaded.")
        case "set-aside", "restore":
            guard let draft = try SiteUnpublishedDrafts.load(repo: repo, slug: slug) else {
                throw SiteError("Choose an unpublished chapter. Revisions of uploaded pages cannot be set aside here.")
            }
            if CommandLine.arguments[i + 3] == "set-aside" {
                try SiteUnpublishedDrafts.setAside(repo: repo, expected: draft)
                print("Chapter set aside locally. Its title and document are retained for restoration; nothing has been uploaded.")
            } else {
                try SiteUnpublishedDrafts.restore(repo: repo, expected: draft)
                print("Chapter restored as an unpublished draft. Include it explicitly when ready for readers.")
            }
        default: throw SiteError("Choose start, include, set-aside or restore.")
        }
        exit(0)
    } catch {
        FileHandle.standardError.write("site-draft failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}
//   --site-move <repo> <slug> up|down   one place among its siblings
if let i = CommandLine.arguments.firstIndex(of: "--site-move"), i + 3 < CommandLine.arguments.count {
    do {
        let moved = try LocalSiteStore.movePage(repo: CommandLine.arguments[i + 1], slug: CommandLine.arguments[i + 2],
                                                by: CommandLine.arguments[i + 3] == "up" ? -1 : 1)
        print(moved ? "moved" : "already at the end")
        exit(0)
    } catch {
        FileHandle.standardError.write("site-move failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}
// Inspect local publishing evidence without accessing the network.
if let i = CommandLine.arguments.firstIndex(of: "--site-status"), i + 1 < CommandLine.arguments.count {
    let out = CommandLine.arguments.firstIndex(of: "--out").flatMap { $0 + 1 < CommandLine.arguments.count ? CommandLine.arguments[$0 + 1] : nil } ?? "docs"
    let status = SitePublicationState.status(repo: CommandLine.arguments[i + 1], out: out)
    print("\(status.rawValue): \(status.message)")
    exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--site-publish"), i + 1 < CommandLine.arguments.count {
    initializeHeadlessText()
    func option(_ name: String) -> String? {
        guard let j = CommandLine.arguments.firstIndex(of: name), j + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[j + 1]
    }
    let r = LocalSiteStore.publishNow(repo: CommandLine.arguments[i + 1], out: option("--out") ?? "docs",
                                      web: option("--web") ?? SiteBuilder.defaultWebStage(), message: option("-m") ?? "")
    if let failure = r.failure {
        FileHandle.standardError.write("site-publish failed: \(failure)\n".data(using: .utf8)!)
        exit(1)
    }
    print("site-publish: \(r.summary)")
    exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--page-json"), i + 2 < CommandLine.arguments.count {
    initializeHeadlessText()
    do {
        var opened = try OfficeFormats.read(CommandLine.arguments[i + 1])
        opened.document.assignParagraphIDs()
        try RichDocumentEnvelope.encode(opened.document, pageSetup: opened.pageSetup).write(to: URL(fileURLWithPath: CommandLine.arguments[i + 2]))
        exit(0)
    } catch {
        FileHandle.standardError.write("page-json failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}
if let i = CommandLine.arguments.firstIndex(of: "--page-docx"), i + 2 < CommandLine.arguments.count {
    initializeHeadlessText()
    do {
        let envelope = try RichDocumentEnvelope.decodeEnvelope(try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[i + 1])))
        if let setup = envelope.pageSetup { try OfficeFormats.write(envelope.document, to: CommandLine.arguments[i + 2], pageSetup: setup) }
        else { try OfficeFormats.write(envelope.document, to: CommandLine.arguments[i + 2]) }
        exit(0)
    } catch {
        FileHandle.standardError.write("page-docx failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}
if let i = CommandLine.arguments.firstIndex(of: "--page-roundtrip"), i + 1 < CommandLine.arguments.count {
    initializeHeadlessText()
    do {
        var doc = try OfficeFormats.read(CommandLine.arguments[i + 1]).document
        doc.assignParagraphIDs()
        let data = try RichDocumentEnvelope.encode(doc)
        let back = try RichDocumentEnvelope.decode(data)
        if back == doc {
            print("OK \(doc.paragraphs.count) paragraphs \(data.count) bytes")
            exit(0)
        }
        // Name the first thing that differs, so the fix is a grep away.
        if back.paragraphs.count != doc.paragraphs.count {
            print("DIFF paragraph count \(doc.paragraphs.count) -> \(back.paragraphs.count)")
        } else if let k = zip(doc.paragraphs, back.paragraphs).enumerated().first(where: { $0.element.0 != $0.element.1 })?.offset {
            let (a, b) = (doc.paragraphs[k], back.paragraphs[k])
            var what = "paragraph \(k)"
            if a.text != b.text { what += " text" }
            if a.runs != b.runs { what += " runs" }
            if a.style != b.style { what += " style" }
            if a.image != b.image { what += " image" }
            if a.cell != b.cell { what += " cell" }
            if a.inlineImages != b.inlineImages { what += " inlineImages" }
            print("DIFF \(what)")
        } else {
            var what = "document"
            if doc.styles != back.styles { what += " styles" }
            if doc.tableColumns != back.tableColumns { what += " tableColumns" }
            if doc.tableStyles != back.tableStyles { what += " tableStyles" }
            if doc.listFormats != back.listFormats { what += " listFormats" }
            if doc.keptParts != back.keptParts { what += " keptParts" }
            if doc.keptTables != back.keptTables { what += " keptTables" }
            if doc.keptHeaderFooters != back.keptHeaderFooters { what += " keptHeaderFooters" }
            print("DIFF \(what)")
        }
        exit(2)
    } catch {
        FileHandle.standardError.write("page-roundtrip failed: \(error)\n".data(using: .utf8)!)
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

if let i = CommandLine.arguments.firstIndex(of: "--convert"), i + 2 < CommandLine.arguments.count {
    let src = CommandLine.arguments[i + 1]
    let dst = CommandLine.arguments[i + 2]
    initializeHeadlessText()
    do {
        let opened = try OfficeFormats.read(src)
        if dst.pathExtension.lowercased() == "pdf" {
            let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
            theme.fontFamilyResolver = OfficeFonts.substitute
            theme.faceResolver = OfficeFonts.face
            theme.averageCharWidth = OfficeFonts.averageCharWidth
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

// `--wiki <url>` opens the wiki at that server natively (docs/plans/wiki.md);
// in a tab the server's shell page sets the route, `/s/<space>/p/<id>/…`.
let wikiBase: String? = {
    guard let i = CommandLine.arguments.firstIndex(of: "--wiki"), i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}()

// `--site <dir>` opens a cloned site repository to read, edit and publish
// (docs/plans/site.md); `--site <url>` reads a published one. In a tab the
// built site's shell page passes `--site <base>`.
let siteArg: String? = {
    guard let i = CommandLine.arguments.firstIndex(of: "--site"), i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}()

runStarlingApp(title: siteArg != nil ? "Site" : wikiBase != nil ? "Wiki" : initialKind.appName,
               width: windowMetric("STARLING_WINDOW_W", 1440),
               height: windowMetric("STARLING_WINDOW_H", 900)) {
    #if os(WASI)
    if WebPlatform.defaultRouteName.hasPrefix("/office-landing") {
        FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeLandingView(), title: "Starling Office")
    } else if let siteArg {
        SiteRoot(store: StaticSiteStore(base: siteArg), route: WebPlatform.defaultRouteName)
    } else if WebPlatform.defaultRouteName.hasPrefix("/s/") || WebPlatform.defaultRouteName.hasPrefix("/login") || CommandLine.arguments.contains("--wiki") {
        WikiRoot(base: "", route: WebPlatform.defaultRouteName)
    } else {
        OfficeRoot(initialPath: initialPath, kind: initialKind)
    }
    #else
    if let siteArg {
        if siteArg.hasPrefix("http://") || siteArg.hasPrefix("https://") {
            SiteRoot(store: StaticSiteStore(base: siteArg), route: "/")
        } else {
            SiteRoot(store: LocalSiteStore(repo: siteArg), route: "/")
        }
    } else if let wikiBase {
        // The URL may name a page: the server part is the base, the rest the route.
        WikiRoot(base: wikiBase.findRange(of: "/s/").map { String(wikiBase[..<$0.lowerBound]) } ?? wikiBase,
                 route: wikiBase.findRange(of: "/s/").map { String(wikiBase[$0.lowerBound...]) } ?? "/")
    } else {
        OfficeRoot(initialPath: initialPath, kind: initialKind)
    }
    #endif
}
