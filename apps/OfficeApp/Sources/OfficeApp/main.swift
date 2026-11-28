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
import OfficeText
import FlutterSwiftBridge
import Foundation

#if os(Windows)
import FlutterWin32
#elseif os(macOS)
import AppKit
import FlutterCocoa
#elseif os(iOS)
import FlutterUIKit
import OfficeUIKit
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
    #elseif os(iOS)
    // (The app's own Flutter.framework: with none of these the iOS bridge's
    // ICU stayed empty and no run had a line break inside it.)
    if let frameworks = Bundle.main.privateFrameworksPath { candidates.append(frameworks + "/Flutter.framework/icudtl.dat") }
    #endif
    for candidate in candidates where FileManager.default.fileExists(atPath: candidate) {
        _ = flutter.swift_bridge.InitializeICU(candidate)
        break
    }
    OfficeFonts.register()
    // (A stale engine is said at once, on stderr, not at the first indent.)
    _ = starlingEngineKnowsLineIndents()
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
//   --site-import <repo> <file.docx|rtf|md> [--title T] [--under slug] [--template]
//   a document as a new page of the site (paragraph ids assigned, page
//   setup kept); prints the slug. A text source (Markdown, RTF, plain
//   text) is dressed in the site's template when site.json names one;
//   --template dresses a .docx too, which otherwise keeps its own design.
//   --site-new <repo> <title> [--under slug]
//   a new page, from the site's template or blank (what New page runs).
if let i = CommandLine.arguments.firstIndex(of: "--site-new"), i + 2 < CommandLine.arguments.count {
    initializeHeadlessText()
    func option(_ name: String) -> String? {
        guard let j = CommandLine.arguments.firstIndex(of: name), j + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[j + 1]
    }
    do {
        let repo = CommandLine.arguments[i + 1]
        let page = try LocalSiteStore.newPage(repo: repo)
        print(try LocalSiteStore.addPage(repo: repo, title: CommandLine.arguments[i + 2], page: page, under: option("--under")))
        exit(0)
    } catch {
        FileHandle.standardError.write("site-new failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}
if let i = CommandLine.arguments.firstIndex(of: "--site-import"), i + 2 < CommandLine.arguments.count {
    initializeHeadlessText()
    func option(_ name: String) -> String? {
        guard let j = CommandLine.arguments.firstIndex(of: name), j + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[j + 1]
    }
    let file = CommandLine.arguments[i + 2]
    do {
        guard let data = FileManager.default.contents(atPath: file) else { throw OfficeFormats.FormatError.unreadable }
        var opened = try OfficeFormats.read(data, named: file)
        opened.document.assignParagraphIDs()
        let title = option("--title") ?? file.lastPathComponent.deletingPathExtension
        var page = SitePage(document: opened.document, pageSetup: opened.pageSetup)
        if CommandLine.arguments.contains("--template") || !SiteTemplate.carriesDesign(data),
           let template = try SiteTemplate.load(repo: CommandLine.arguments[i + 1]) {
            page = SiteTemplate.dress(page, in: template)
        }
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

// `--xls-parts <file.xls> <dir>`: the .xlsx parts the reader builds from a legacy workbook, written as files.
if let i = CommandLine.arguments.firstIndex(of: "--xls-parts"), i + 2 < CommandLine.arguments.count {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        let dir = CommandLine.arguments[i + 2]
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let cf = try CompoundFile([UInt8](data))
        guard let wbs = Xls.workbookStream(cf) else { exit(1) }
        for e in XlsBuild.parts(BiffReader.records(wbs)) ?? [] {
            try e.data.write(to: URL(fileURLWithPath: dir + "/" + e.name.split(separator: "/").joined(separator: "_")))
        }
        exit(0)
    } catch { exit(1) }
}

// `--ppt-parts <file.ppt> <dir>`: the .pptx parts the reader builds from a legacy deck, written as files.
if let i = CommandLine.arguments.firstIndex(of: "--ppt-parts"), i + 2 < CommandLine.arguments.count {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        let dir = CommandLine.arguments[i + 2]
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let pkg = try PptBuild.package([UInt8](data))
        for (name, d) in pkg.parts {
            try d.write(to: URL(fileURLWithPath: dir + "/" + name.split(separator: "/").joined(separator: "_")))
        }
        exit(0)
    } catch { print("ppt-parts: \(error)"); exit(1) }
}

// `--ppt-dump <file.ppt>`: one line of census facts: encrypted, slides, masters, record types by count.
if let i = CommandLine.arguments.firstIndex(of: "--ppt-dump"), i + 1 < CommandLine.arguments.count {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        let cf = try CompoundFile([UInt8](data))
        print("streams: \(cf.streamPaths.joined(separator: ","))")
        guard let user = cf.stream("Current User"), let doc = cf.stream("PowerPoint Document") else { print("no-ppt97"); exit(0) }
        let f = try PptFile(currentUser: user, document: doc)
        print("slides: \(f.slideIds.count) masters: \(f.masterIds.count) size: \(f.slideWidth)x\(f.slideHeight) persist: \(f.persist.count)")
        exit(0)
    } catch { print("ppt-dump: \(error)"); exit(0) }
}

// `--doc-info <file.doc>`: story lengths and the non-empty FIB ranges.
if let i = CommandLine.arguments.firstIndex(of: "--doc-info"), i + 1 < CommandLine.arguments.count {
    if let data = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[i + 1])), let cf = try? CompoundFile([UInt8](data)),
       let w = cf.stream("WordDocument"), let f = DocFib(w) {
        print("nFib=\(f.nFib) text=\(f.ccpText) ftn=\(f.ccpFtn) hdd=\(f.ccpHdd) atn=\(f.ccpAtn) edn=\(f.ccpEdn) txbx=\(f.ccpTxbx) hdrtxbx=\(f.ccpHdrTxbx)")
        if let tb = cf.stream(f.tableStream), let sr = f.range(40), let dg = f.range(50) {
            let art = DocArt.art(t: tb, w: w, at: dg.fc, count: dg.lcb)
            print("blips=\(art.blips.count) shapes=\(art.shapes.count) groups=\(art.shapes.values.filter { $0.flags & 1 != 0 }.count) children=\(art.shapes.values.filter { $0.flags & 2 != 0 }.count) crops=\(art.shapes.values.filter { $0.props[0x100] != nil || $0.props[0x101] != nil || $0.props[0x102] != nil || $0.props[0x103] != nil }.count) types=\(Dictionary(grouping: art.shapes.values.filter { $0.flags & 1 == 0 }, by: { $0.type }).mapValues { $0.count }.sorted { $0.key < $1.key }) hdrspa=\(f.range(41).map { DocArt.spas(tb, at: $0.fc, count: $0.lcb).count } ?? 0)")
            for sp in DocArt.spas(tb, at: sr.fc, count: sr.lcb) {
                let sh = art.shapes[sp.spid]
                print("spa cp=\(sp.cp) spid=\(sp.spid) flags=\(String(sp.flags, radix: 16)) type=\(sh?.type ?? -1) props=\((sh?.props ?? [:]).sorted { $0.key < $1.key }.map { "\(String($0.key, radix: 16)):\(String($0.value, radix: 16))" }.joined(separator: " ")) cx=\((sh?.complex ?? [:]).sorted { $0.key < $1.key }.map { "\(String($0.key, radix: 16)):\($0.value.count)" + ($0.value.count <= 40 && $0.key != 0xC0 && $0.key != 0xC5 ? "[" + $0.value.map { String($0, radix: 16) }.joined(separator: ".") + "]" : "") }.joined(separator: " "))")
            }
            print("tablesize=\(tb.count) w=\(w.count)"); if let b = f.range(56), let pl = DocProps.plex(tb, at: b.fc, count: b.lcb, size: 22) { print("txbx cps=\(pl.cps)") }
        }
        if let tb = cf.stream(f.tableStream), let c = f.range(DocFib.fcClx), c.fc >= 0, c.fc + c.lcb <= tb.count {
            let ps = DocRead.pieces(clx: Array(tb[c.fc ..< c.fc + c.lcb]))
            print("pieces=\(ps.count) comp=\(ps.filter { $0.compressed }.count) prm0=\(ps.filter { $0.prm != 0 && $0.prm & 1 == 0 }.map { $0.prm >> 1 & 0x7F }) prm1=\(ps.filter { $0.prm & 1 != 0 }.count) fComplex=\(OfficeArt.u16(w, 10) >> 2 & 1)")
        }
        print(f.fcLcb.enumerated().filter { $0.element.lcb > 0 }.map { "\($0.offset):\($0.element.fc)+\($0.element.lcb)" }.joined(separator: " "))
    }
    exit(0)
}
// `--doc-parts <file.doc> <dir>`: the .docx parts the reader builds from a binary Word document, written as files.
if let i = CommandLine.arguments.firstIndex(of: "--doc-parts"), i + 2 < CommandLine.arguments.count {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        let dir = CommandLine.arguments[i + 2]
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let cf = try CompoundFile([UInt8](data))
        guard let ps = DocRead.parts(cf) else {
            if let w = cf.stream("WordDocument"), let f = DocFib(w) { fputs("nFib=\(f.nFib) encrypted=\(f.encrypted) table=\(f.tableStream) hasTable=\(cf.stream(f.tableStream) != nil) clx=\(String(describing: f.range(DocFib.fcClx))) ccpText=\(f.ccpText)" + "\n", stderr) }
            else { fputs("no WordDocument or FIB" + "\n", stderr) }
            exit(1)
        }
        for e in ps { try e.data.write(to: URL(fileURLWithPath: dir + "/" + e.name.split(separator: "/").joined(separator: "_"))) }
        exit(0)
    } catch { exit(1) }
}

// `--xls-dump <file.xls>`: the streams, record counts and sheets of a legacy workbook.
if let i = CommandLine.arguments.firstIndex(of: "--xls-dump"), i + 1 < CommandLine.arguments.count {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        print(try Xls.dump([UInt8](data)), terminator: "")
        exit(0)
    } catch {
        FileHandle.standardError.write("xls dump failed: \(error)\n".data(using: .utf8)!)
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
        c.load(try Workbook.open(data, name: src.lastPathComponent))
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

// OFFICE_NOW_TABLE=<tsv> (document name, tab, time): a test script pins the clock DATE and TIME fields read to the
// moment the reference print was made (test/corpus/docx/clock.tsv; Slides decks: test/corpus/pptx/clock.tsv, read for --deck-pdf too, since a deck with a clock field scored differently by wall time). Unset, the real clock is used.
if getenv("OFFICE_NOW") == nil, let table = getenv("OFFICE_NOW_TABLE"),
   let i = CommandLine.arguments.firstIndex(where: { $0 == "--convert" || $0 == "--trace-rules" || $0 == "--deck-pdf" }),
   i + 1 < CommandLine.arguments.count,
   let text = try? String(contentsOfFile: String(cString: table), encoding: .utf8) {
    let stem = CommandLine.arguments[i + 1].lastPathComponent.deletingPathExtension
    for line in text.split(separator: "\n") {
        let cols = line.split(separator: "\t")
        if cols.count == 2, String(cols[0]) == stem { setenv("OFFICE_NOW", String(cols[1]), 1) }
    }
}

// How long a headless --deck-pdf / --sheet-pdf export may take, in wall-clock seconds: OFFICE_PDF_TIMEOUT, else 120.
// Sweeps raise it (pptx-app-render.sh): on a box at load 380 an 83-page deck needs more than 120 s of wall clock.
func pdfExportSeconds() -> TimeInterval {
    Double(ProcessInfo.processInfo.environment["OFFICE_PDF_TIMEOUT"] ?? "") ?? 120
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
        let deadline = Date().addingTimeInterval(pdfExportSeconds())
        while done == nil && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        guard done == true else {
            try? FileManager.default.removeItem(atPath: dst)   // a half-written PDF must not be scored as a render
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
        c.load(try Workbook.open(data, name: src.lastPathComponent))
        let grid = SheetGridState(headless: c)
        let cap = Int(ProcessInfo.processInfo.environment["SHEET_PDF_MAX_PAGES"] ?? "") ?? 200
        var done: Bool? = nil
        Task { @MainActor in
            done = await grid.writePdf(to: dst, title: src.lastPathComponent.deletingPathExtension, filePath: src,
                                       wholeBook: true, maxPages: cap)
        }
        let deadline = Date().addingTimeInterval(pdfExportSeconds())
        while done == nil && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        guard done == true else {
            try? FileManager.default.removeItem(atPath: dst)   // a half-written PDF must not be scored as a render
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

// `--xlsx-scan-stats <in.xlsx>...`: per book, how many cells the sheet reader took on its fast path and how
// many it read as a tree (the share the scanner gave up on).
if let i = CommandLine.arguments.firstIndex(of: "--xlsx-scan-stats") {
    for src in CommandLine.arguments[(i + 1)...] {
        MiniXML.scanFast = 0; MiniXML.scanTree = 0
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: src)), (try? Workbook.open(data, name: src.lastPathComponent)) != nil else {
            print("\(src.lastPathComponent) unreadable"); continue
        }
        print("\(src.lastPathComponent) fast=\(MiniXML.scanFast) tree=\(MiniXML.scanTree)")
    }
    exit(0)
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
        theme.complexFaceKeepsDigits = OfficeFonts.complexFaceKeepsDigits
        theme.averageCharWidth = OfficeFonts.averageCharWidth
        theme.winLineBox = OfficeFonts.standInWinBox
        theme.capOverWinAscent = OfficeFonts.standInCapOverWinAscent
        theme.winDescent = { name in name.flatMap { n in SheetPrintMetrics.descent(family: n).flatMap { d in SheetPrintMetrics.ascent(family: n).map { d / ($0 + d) } } } }
        theme.winAscent = { name in name.flatMap { SheetPrintMetrics.ascent(family: $0) } }
        theme.symbolGlyphs = { face, text in face.map { Metafile.symbols(text, face: $0) } ?? text }
        theme.isSymbolFace = { Metafile.isSymbolFace($0) }
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

/// The theme the headless Word commands (`--convert` to PDF, `--paint-pages`) lay out with.
func headlessWordTheme() -> RichTextTheme {
    let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
    theme.fontFamilyResolver = OfficeFonts.drawn
    theme.faceResolver = OfficeFonts.face
    theme.complexFaceResolver = OfficeFonts.complexFace
    theme.complexFaceKeepsDigits = OfficeFonts.complexFaceKeepsDigits
    theme.averageCharWidth = OfficeFonts.averageCharWidth
    theme.winLineBox = OfficeFonts.standInWinBox
    theme.capOverWinAscent = OfficeFonts.standInCapOverWinAscent
    theme.winDescent = { name in name.flatMap { n in SheetPrintMetrics.descent(family: n).flatMap { d in SheetPrintMetrics.ascent(family: n).map { d / ($0 + d) } } } }
    theme.winAscent = { name in name.flatMap { SheetPrintMetrics.ascent(family: $0) } }
    theme.symbolGlyphs = { face, text in face.map { Metafile.symbols(text, face: $0) } ?? text }
    theme.isSymbolFace = { Metafile.isSymbolFace($0) }
    theme.symbolAdvance = Metafile.symbolAdvance
    theme.wordRules = true
    theme.disablesLigatures = true
    return theme
}

// `--paint-pages <in>`: lays the document out and paints every page the way the window does (`RichLayout.paint` with
// a paper behind each page) on THIS thread, then prints the page count. A diagnostic for the stack the window paints
// on: under `ulimit -s 1024` (an iPad's main thread) a document that overflows it dies here with signal 11.
if let i = CommandLine.arguments.firstIndex(of: "--paint-pages"), i + 1 < CommandLine.arguments.count {
    initializeHeadlessText()
    do {
        let opened = try OfficeFormats.read(CommandLine.arguments[i + 1])
        let theme = headlessWordTheme()
        let setup = opened.pageSetup ?? .letter
        let layout = RichLayout(theme: theme, paragraphCount: opened.document.paragraphs.count)
        layout.pageSetup = setup
        layout.width = setup.columnWidth * theme.pixelsPerPoint
        layout.ensureLaidOut(opened.document)
        for round in 0 ..< 2 {   // (the second pass paints what the first one asked for: headers, text boxes)
            for p in 0 ..< layout.pageCount {
                let rect = layout.pageRect(p)
                let recorder = NativePictureRecorder()
                let canvas = NativeCanvas(recorder: recorder, cullRect: Rect.fromLTWH(0, 0, rect.width, rect.height))
                canvas.translate(0, -rect.top)
                layout.paint(canvas, visible: rect, document: opened.document, selection: nil, caret: nil,
                             pageBackground: { _, r in
                                 let paper = Paint()
                                 paper.color = Color(0xFFFFFFFF)
                                 paper.style = .fill
                                 canvas.drawRect(r, paper)
                             })
                _ = recorder.endRecording()
            }
            _ = round
        }
        print("painted \(layout.pageCount) pages")
        // STARLING_PAINT_BENCH=N: N more paints, one page each, walking down the document as a scroll does, each into a fresh
        // recording as the window's paint is; the mean milliseconds a paint takes (STARLING_BIGSTACK_ALWAYS=1 puts it through
        // the hop, STARLING_BIGSTACK_PERCALL=1 through a thread per paint).
        if let n = getenv("STARLING_PAINT_BENCH").flatMap({ Int(String(cString: $0)) }), n > 0 {
            var samples: [Double] = []
            for frame in 0 ..< n {
                let rect = layout.pageRect(frame % max(1, layout.pageCount))
                let t0 = DispatchTime.now().uptimeNanoseconds
                let recorder = NativePictureRecorder()
                let canvas = NativeCanvas(recorder: recorder, cullRect: Rect.fromLTWH(0, 0, rect.width, rect.height))
                canvas.translate(0, -rect.top)
                layout.paint(canvas, visible: rect, document: opened.document, selection: nil, caret: nil)
                _ = recorder.endRecording()
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
            }
            samples.sort()
            let mean = samples.reduce(0, +) / Double(n)
            print(String(format: "bench %d paints: mean %.3f ms, median %.3f ms, p95 %.3f ms", n, mean, samples[n / 2], samples[n * 95 / 100]))
        }
        exit(0)
    } catch {
        FileHandle.standardError.write("paint-pages failed: \(error)\n".data(using: .utf8)!)
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
            let theme = headlessWordTheme()
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

#if os(iOS)
// On iPad the file browser is the platform's (UIDocumentBrowserViewController),
// with the editor presented over it. A path on the command line still opens
// that file straight into the editor, as before — the way the simulator is
// driven without a touch route.
#if os(iOS)
/// What every window's scene shares of the native shell: the saved-file notice, the edit menu and the formatting
/// bar over the keyboard. `viewId` is the Flutter view the window draws in; the edit menu's rect arrives in that view's
/// coordinates and the menu lives in the window's, so it is moved by the view's place there. The bar is one for the
/// screen: the editor that published last (the one the user is working in) owns it.
func connectNativeHooks(_ scene: OfficeScene, viewId: Int) {
    let log = ProcessInfo.processInfo.environment["OFFICE_HOST_LOG"] != nil
    OfficeScene.byView[viewId] = scene
    scene.documentSaved = { OfficeNativeShell.documentSaved($0, viewId: viewId) }
    scene.editMenuRequested = { x, y, w, h, items, text in
        let o = viewId == 0 ? nil : TextInputChannel.viewOrigin?(viewId)
        let rect = CGRect(x: x + (o?.x ?? 0), y: y + (o?.y ?? 0), width: w, height: h)
        if log { fputs("[office] view \(viewId) edit menu at \(rect.origin.x),\(rect.origin.y)\n", stderr) }
        OfficeNativeShell.showEditMenu(rect,
                                       items: items.map { OfficeEditMenuItem(title: $0.title, symbol: $0.symbol,
                                                                              isEnabled: $0.isEnabled, action: $0.action) },
                                       text: text, viewId: viewId)
    }
    scene.editMenuDismissed = { OfficeNativeShell.showEditMenu(nil, items: [], text: nil, viewId: viewId) }
    scene.toolbarChanged = { buttons in
        if log { fputs("[office] view \(viewId) toolbar: \(buttons.map { "\($0.count) buttons" } ?? "withdrawn")\n", stderr) }
        func native(_ b: OfficeHost.ToolbarButton) -> OfficeToolbarButton {
            OfficeToolbarButton(id: b.id, title: b.title, symbol: b.symbol, isOn: b.isOn, isEnabled: b.isEnabled,
                                children: b.children.map(native), action: b.action)
        }
        OfficeNativeShell.setToolbar(buttons?.map(native), viewId: viewId)
    }
    // Bringing this window forward: the system's scene if it is one, else (a test host) its view in the window.
    scene.raise = {
        UIKitHost.activateScene(viewId)
        UIKitHost.raiseExtraView(viewId)
    }
    // A window with a native browser takes Open and Export over; one without (a test host's) keeps the editor's own.
    scene.openRequested = {
        guard OfficeNativeShell.hasShell(viewId) else { return false }
        OfficeNativeShell.showBrowser(viewId: viewId)
        return true
    }
    OfficeNativeShell.onPictureDrop = { path, id in OfficeScene.byView[id]?.pictureDropped?(path) }
    scene.pictureRequested = { done in
        // OFFICE_PICK_PICTURE=path: a script's stand-in for the system pickers, which no in-app driver can tap
        // (Slides reads it itself, on every platform; this one serves the other apps on iOS).
        if let stub = ProcessInfo.processInfo.environment["OFFICE_PICK_PICTURE"], !stub.isEmpty { done(stub); return }
        OfficeNativeShell.pickPicture(viewId: viewId, done: done)
    }
    scene.exportRequested = { name, prepare, thenOpen, done in
        OfficeNativeShell.export(name: name, prepare: prepare, thenOpen: thenOpen, viewId: viewId, done: done)
    }
    scene.shareRequested = { name, prepare, _, done in
        OfficeNativeShell.share(name: name, prepare: prepare, viewId: viewId, done: done)
    }
}
#endif


#if os(iOS)
Clipboard.provider = IOSClipboardProvider()
// iPadOS may end an app it has put in the background: every window writes what it has not saved yet first.
_ = NotificationCenter.default.addObserver(forName: Notification.Name("UIApplicationDidEnterBackgroundNotification"), object: nil, queue: .main) { _ in
    fputs("[office] background: saving every window's pending edits\n", stderr)
    OfficeScene.flushAll()
}
#endif
if initialPath == nil && siteArg == nil && wikiBase == nil {
    OfficeNativeShell.install()
    OfficeNativeShell.onOpenDocument = { path, viewId in OfficeScene.byView[viewId]?.requestOpen(path) }
    OfficeScene.originalOf = { OfficeNativeShell.originalPath(forWorking: $0) }
    // One document, one window: a file another window than the main one has is shown by bringing that window forward.
    OfficeNativeShell.focusIfOpen = { path, viewId in
        guard let held = OfficeScene.holding(path, besides: OfficeScene.byView[viewId]) else { return false }
        if ProcessInfo.processInfo.environment["OFFICE_HOST_LOG"] != nil { fputs("[office] open \((path as NSString).lastPathComponent): already open in another window, bringing it forward\n", stderr) }
        held.focusWindow()
        return true
    }
    OfficeNativeShell.makeBlank = { OfficeHost.writeBlank(kind: $0, to: $1) }
    connectNativeHooks(OfficeScene.main, viewId: 0)
    hostPrintPDF = { path in DispatchQueue.main.async { OfficeNativeShell.printPDF(path) } }
    // A window the system makes beyond the first (Stage Manager, Open in New Window): a scene of its own with its
    // own tree, shown in the engine view the host has given it.
    OfficeNativeShell.sceneConnected = { viewId in
        let scene = OfficeScene()
        connectNativeHooks(scene, viewId: viewId)
        runView(id: viewId) { OfficeSceneScope(scene: scene, child: OfficeRoot(initialPath: nil, kind: .document)) }
    }
    // The system dropped a window: what it had not saved is written first, and its claim on its file is released.
    OfficeNativeShell.sceneDisconnected = { viewId in
        guard let scene = OfficeScene.byView[viewId] else { return }
        scene.flushPendingSaves()
        if viewId != 0 { OfficeScene.byView[viewId] = nil } else { scene.releaseDocument() }
        fputs("[office] window \(viewId) closed\n", stderr)
    }
}
#endif

#if os(macOS)
// The window's close button and ⌘Q end the process (the Cocoa host terminates after its last window): what the
// editors have not saved is written first, as on iPad. Without it a Sheets workbook (no AutoSave) lost every edit
// since the last ⌘S, and a document lost what its 2-second AutoSave timer had not yet written. Both the window's
// close and the app's termination are watched: whichever comes first writes (a second finds nothing dirty).
for name in [NSWindow.willCloseNotification, NSApplication.willTerminateNotification] {
    // (queue: nil: run in the poster, on the main thread, now. A block queued on `.main` never ran: the app exits
    // inside terminate, before the run loop turns again.)
    _ = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { n in
        if ProcessInfo.processInfo.environment["OFFICE_HOST_LOG"] != nil { fputs("[office] \(n.name.rawValue): saving every window's pending edits\n", stderr) }
        OfficeScene.flushAll()
    }
}
#endif

#if os(iOS)
// The second-window test host (docs/plans/ipad-multi-window.md, step 4): OFFICE_SECOND_VIEW_DOC=<path> shows
// that document in view 1, in a scene of its own (STARLING_SPIKE_SECOND_VIEW=1 adds the view, STARLING_SPIKE_VIEW_W/H
// size it). Off unless asked; the real entry points are step 5.
if let second = ProcessInfo.processInfo.environment["OFFICE_SECOND_VIEW_DOC"], !second.isEmpty {
    let scene = OfficeScene()
    connectNativeHooks(scene, viewId: 1)
    scene.raise = { UIKitHost.raiseExtraView(1) }
    runView(id: 1) {
        OfficeSceneScope(scene: scene, child: OfficeRoot(initialPath: second, kind: DocumentKind.kind(forPath: second)))
    }
}
// OFFICE_OPEN_AFTER=<ms>:<path> asks for that file through the browser's entry point after a delay (a test, no screen).
if let spec = ProcessInfo.processInfo.environment["OFFICE_OPEN_AFTER"], let colon = spec.firstIndex(of: ":"),
   let ms = Int(spec[..<colon]) {
    let path = String(spec[spec.index(after: colon)...])
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) { OfficeNativeShell.open(URL(fileURLWithPath: path)) }
}
// A heap histogram for the leak hunt (OFFICE_HEAP_DUMP=<dir>): every live malloc block, grouped by the symbol its
// first word points at (a Swift or ObjC object's class) or else by size; written as "count bytes key" lines.
// The blocks are collected into a preallocated buffer first (allocating inside the enumerator would change the
// heap being walked), and read with vm_read_overwrite so a block freed meanwhile cannot crash the walk.
private nonisolated(unsafe) var heapRanges: UnsafeMutablePointer<(UInt, UInt)>? = nil
private nonisolated(unsafe) var heapRangeCount = 0
private let heapRangeCapacity = 6_000_000

func dumpHeapHistogram(to path: String) {
    heapRanges = UnsafeMutablePointer<(UInt, UInt)>.allocate(capacity: heapRangeCapacity)
    heapRangeCount = 0
    var zones: UnsafeMutablePointer<vm_address_t>?
    var zoneCount: UInt32 = 0
    _ = malloc_get_all_zones(mach_task_self_, { _, addr, _, out in out?.pointee = UnsafeMutableRawPointer(bitPattern: addr); return KERN_SUCCESS }, &zones, &zoneCount)
    guard let zones else { return }
    for i in 0..<Int(zoneCount) {
        guard let zone = UnsafeMutablePointer<malloc_zone_t>(bitPattern: zones[i]), let intro = zone.pointee.introspect,
              let enumerate = intro.pointee.enumerator else { continue }
        _ = enumerate(mach_task_self_, nil, UInt32(MALLOC_PTR_IN_USE_RANGE_TYPE), vm_address_t(bitPattern: zone),
                      { _, addr, size, out in out?.pointee = UnsafeMutableRawPointer(bitPattern: addr); return KERN_SUCCESS },
                      { _, _, _, ranges, count in
                          guard let ranges, let buffer = heapRanges else { return }
                          for j in 0..<Int(count) where heapRangeCount < heapRangeCapacity {
                              buffer[heapRangeCount] = (UInt(ranges[j].address), UInt(ranges[j].size)); heapRangeCount += 1
                          }
                      })
    }
    var groups: [String: (Int, Int)] = [:]
    for j in 0..<heapRangeCount {
        let (addr, size) = heapRanges![j]
        var key = "size:\(size)"
        if size >= 16, size <= 65536 {
            var word: UInt = 0
            var got: vm_size_t = 0
            let kr = withUnsafeMutablePointer(to: &word) { vm_read_overwrite(mach_task_self_, vm_address_t(addr), 8, vm_address_t(UInt(bitPattern: $0)), &got) }
            if kr == KERN_SUCCESS, word > 0x10000 {
                var info = Dl_info()
                if dladdr(UnsafeRawPointer(bitPattern: word), &info) != 0, let name = info.dli_sname,
                   let base = info.dli_saddr, UInt(bitPattern: base) == word { key = "obj:" + String(cString: name) }
            }
        }
        let old = groups[key] ?? (0, 0)
        groups[key] = (old.0 + 1, old.1 + Int(size))
    }
    // Who holds the controllers that outlived their windows? A backward scan: every block that has a word equal to a
    // target's address, then who holds those, four levels up. (The oldest controller is the open window's own.)
    var chains = ""
    let leaked = LeakProbe.controllers.sorted { $0.seq < $1.seq }.dropFirst().map(\.address)
    if !leaked.isEmpty {
        var buffer = [UInt](repeating: 0, count: 65536 / 8)
        func describe(_ addr: UInt, _ size: UInt) -> String {
            var word: UInt = 0; var got: vm_size_t = 0
            let kr = withUnsafeMutablePointer(to: &word) { vm_read_overwrite(mach_task_self_, vm_address_t(addr), 8, vm_address_t(UInt(bitPattern: $0)), &got) }
            if kr == KERN_SUCCESS, word > 0x10000 {
                var info = Dl_info()
                if dladdr(UnsafeRawPointer(bitPattern: word), &info) != 0, let name = info.dli_sname { return "\(String(cString: name)) (\(size) bytes)" }
            }
            return "unnamed block (\(size) bytes, first word \(String(word, radix: 16)))"
        }
        var wanted = Set(leaked)
        var names: [UInt: String] = [:]
        for a in leaked { names[a] = "controller" }
        var parents: [UInt: [(UInt, UInt)]] = [:]   // target -> (holder block, offset)
        for _ in 0..<4 {
            var found: [UInt: [(UInt, UInt)]] = [:]
            for j in 0..<heapRangeCount {
                let (addr, size) = heapRanges![j]
                guard size >= 16, size <= 65536 else { continue }
                var got: vm_size_t = 0
                let kr = buffer.withUnsafeMutableBytes { vm_read_overwrite(mach_task_self_, vm_address_t(addr), vm_size_t(size), vm_address_t(UInt(bitPattern: $0.baseAddress!)), &got) }
                guard kr == KERN_SUCCESS else { continue }
                for k in 0..<Int(size / 8) where wanted.contains(buffer[k]) && buffer[k] != addr {
                    found[buffer[k], default: []].append((addr, UInt(k * 8)))
                }
            }
            var next = Set<UInt>()
            for (target, holders) in found {
                parents[target, default: []] += holders
                for (h, _) in holders where names[h] == nil {
                    let size = (0..<heapRangeCount).lazy.map { heapRanges![$0] }.first { $0.0 == h }?.1 ?? 0
                    names[h] = describe(h, size); next.insert(h)
                }
            }
            if next.isEmpty { break }
            wanted = next
        }
        func chain(_ a: UInt, _ depth: Int) -> [String] {
            guard depth < 5, let hs = parents[a] else { return [] }
            var out: [String] = []
            for (h, off) in hs.prefix(3) {
                let line = String(repeating: "  ", count: depth) + "<- \(names[h] ?? "?") at +\(off)"
                out.append(line); out += chain(h, depth + 1)
            }
            return out
        }
        for a in leaked.prefix(2) { chains += "controller \(String(a, radix: 16)):\n" + chain(a, 1).joined(separator: "\n") + "\n" }
    }
    try? chains.write(toFile: path + ".retainers.txt", atomically: true, encoding: .utf8)
    heapRanges!.deallocate(); heapRanges = nil
    var text = ""
    for (key, value) in groups.sorted(by: { $0.value.1 > $1.value.1 }) { text += "\(value.0) \(value.1) \(key)\n" }
    try? text.write(toFile: path, atomically: true, encoding: .utf8)
}

private final class WeakBox { weak var value: OfficeScene?; init(_ v: OfficeScene) { value = v } }
// OFFICE_WINDOW_CYCLES=<n>:<path> opens a window on that file and closes it again, n times, 3 s apart (a test of
// the scene lifecycle: flush, unmount, the claim on the file; the heap is logged after each close).
if let spec = ProcessInfo.processInfo.environment["OFFICE_WINDOW_CYCLES"] {
    let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
    if let count = Int(parts[0]) {
        // "<n>:" with no path cycles windows that show only the browser (no document): tells a window leak from a document leak.
        let url: URL? = parts.count == 2 && !parts[1].isEmpty ? URL(fileURLWithPath: parts[1]) : nil
        nonisolated(unsafe) var watched: [(Int, WeakBox)] = []
        func heapMB() -> Double {
            var info = mach_task_basic_info(); var size = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
            let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &size) } }
            return kr == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : -1
        }
        func mallocMB() -> Double {
            var s = malloc_statistics_t(); malloc_zone_statistics(nil, &s); return Double(s.size_in_use) / 1_048_576
        }
        func footprintMB() -> Double {
            var info = task_vm_info_data_t(); var size = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
            let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &size) } }
            return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
        }
        func cycle(_ n: Int) {
            guard n <= count else { return }
            let before = Set(OfficeScene.byView.keys)
            OfficeNativeShell.openInNewWindow(url)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                if let id = Set(OfficeScene.byView.keys).subtracting(before).max() {
                    fputs("[cycle] \(n): window \(id) open, document \(OfficeScene.byView[id]?.documentPath ?? "none"), rss \(heapMB()) MB\n", stderr)
                    if let s = OfficeScene.byView[id] { watched.append((id, WeakBox(s))) }
                    UIKitHost.closeScene(id)
                } else { fputs("[cycle] \(n): no window appeared\n", stderr) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    if let dir = ProcessInfo.processInfo.environment["OFFICE_HEAP_DUMP"], n == 2 || n == count { dumpHeapHistogram(to: "\(dir)/heap-\(n).txt") }
                    fputs("[cycle] \(n): closed, windows \(OfficeScene.byView.keys.sorted()), rss \(heapMB()) MB, footprint \(footprintMB()) MB, malloc in use \(mallocMB()) MB, live \(LeakProbe.live.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")), browsers \(OfficeNativeShell.liveBrowsers), closed scenes still alive: \(watched.filter { $0.1.value != nil }.map { $0.0 })\n", stderr)
                    cycle(n + 1)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { cycle(1) }
    }
}
// OFFICE_NEW_WINDOW_AFTER=<ms>[:<path>] asks for a new window (showing that file) through the same call as the
// browser's "Open in New Window", after a delay (a test: no screen to drive).
// OFFICE_EXPORT_AFTER=<ms>:<viewId> asks that window to Save As (a small text file) the way its Export does, so a
// test can see the picker come up over that window and no other.
if let spec = ProcessInfo.processInfo.environment["OFFICE_EXPORT_AFTER"] {
    let parts = spec.split(separator: ":").map(String.init)
    if parts.count == 2, let ms = Int(parts[0]), let view = Int(parts[1]) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) {
            OfficeNativeShell.export(name: "export-test.txt", prepare: { path, ok in
                ok((try? "export from view \(view)".write(toFile: path, atomically: true, encoding: .utf8)) != nil)
            }, thenOpen: false, viewId: view) { name in fputs("[export] view \(view) done: \(name ?? "cancelled")\n", stderr) }
        }
    }
}
// OFFICE_BROWSER_ACTION_AFTER=<ms>:<viewId>:<path>[,...] runs window <viewId>'s browser "Open in New Window" action on
// that file, after a delay, and logs the windows before and two seconds after.
if let specs = ProcessInfo.processInfo.environment["OFFICE_BROWSER_ACTION_AFTER"] {
    for spec in specs.split(separator: ",") {
        let parts = spec.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3, let ms = Int(parts[0]), let view = Int(parts[1]) else { continue }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) {
            let before = OfficeScene.byView.keys.sorted()
            OfficeNativeShell.runNewWindowAction(viewId: view, url: URL(fileURLWithPath: parts[2]))
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                let docs = OfficeScene.byView.sorted { $0.key < $1.key }.map { "\($0.key)=\(($0.value.documentPath as NSString?)?.lastPathComponent ?? "none")" }
                fputs("[action] view \(view) Open in New Window \((parts[2] as NSString).lastPathComponent): windows \(before) -> \(OfficeScene.byView.keys.sorted()), documents \(docs)\n", stderr)
            }
        }
    }
}
// OFFICE_CLOSE_WINDOW_AFTER=<ms>:<viewId>[,...] closes that window the way the user does (the system drops the scene:
// the document is flushed and written back first), after a delay.
if let specs = ProcessInfo.processInfo.environment["OFFICE_CLOSE_WINDOW_AFTER"] {
    for spec in specs.split(separator: ",") {
        let parts = spec.split(separator: ":").map(String.init)
        guard parts.count == 2, let ms = Int(parts[0]), let view = Int(parts[1]) else { continue }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) {
            fputs("[close] view \(view)\n", stderr)
            UIKitHost.closeScene(view)
        }
    }
}
if let spec = ProcessInfo.processInfo.environment["OFFICE_NEW_WINDOW_AFTER"] {
    let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
    if let ms = Int(parts[0]) {
        let url = parts.count > 1 ? URL(fileURLWithPath: parts[1]) : nil
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) { OfficeNativeShell.openInNewWindow(url) }
    }
}
#endif

#if os(WASI)
// File > Print in a tab: the PDF goes to the page, which opens the browser's
// print dialog on it.
hostPrintPDFBytes = { data, name in WebFiles.print(data, as: name) }
// AutoSave's recovery copy: a row in the page's storage, not a file.
OfficeHost.browserRecovery = .init(
    keep: { kind, name, data in WebFiles.keepRecovery(kind: kind, name: name, data: data) },
    discard: { WebFiles.discardRecovery() },
    take: { kind in WebFiles.takeRecovery(kind: kind).map { ($0.name, $0.data) } })

// A tab hidden or closing writes the recovery copy at once, not two seconds
// later: a closed tab gets no two seconds.
hostPageHidden = { OfficeScene.flushAll() }

// Recent files: the page keeps each document opened or saved (web-parity item 3).
OfficeHost.browserRecent = .init(names: { WebFiles.recentNames },
                                 remember: { name, data, handle in WebFiles.keepRecent(name, data, handle: handle) },
                                 open: { name, done in
                                     WebFiles.openRecent(name) { done($0.map { ($0.name, $0.data, $0.handle) }) }
                                 })

// Open, Save and Save As: the browser's pickers, with file handles where it has them.
OfficeHost.browserFiles = .init(
    canPickPlace: WebFiles.canPickPlace,
    open: { extensions, done in
        WebFiles.open(extensions: extensions) { picked in
            if let picked { done((picked.name, picked.data, picked.handle)) }
        }
    },
    pickPlace: { suggested, extensions, done in WebFiles.pickPlace(suggested: suggested, extensions: extensions, done) },
    write: { handle, data, done in WebFiles.write(data, to: handle, done) },
    download: { name, data in WebFiles.download(data, as: name) })
#endif

// A link followed in a document opens in the system's browser or mail program (Linux and Windows hosts set none; the Mac
// and web hosts set their own).
#if os(Linux) || os(Windows)
if hostOpenURL == nil { hostOpenURL = { UpdateCheck.openWithSystem($0) } }
#endif

runStarlingApp(title: siteArg != nil ? "Site" : wikiBase != nil ? "Wiki" : initialKind.appName,
               width: OfficeWindowSize.of(ProcessInfo.processInfo.environment).width,
               height: OfficeWindowSize.of(ProcessInfo.processInfo.environment).height) {
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
