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
    let exeDir = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
        .deletingLastPathComponent().path
    for candidate in [exeDir + "/data/icudtl.dat", exeDir + "/../Resources/data/icudtl.dat",
                      exeDir + "/../share/starling/icudtl.dat"]
    where FileManager.default.fileExists(atPath: candidate) {
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

// `--convert <in> <out>`: the formats without the window, for scripts and
// for checking our output against other readers (`textutil`, LibreOffice).
if let i = CommandLine.arguments.firstIndex(of: "--convert"), i + 2 < CommandLine.arguments.count {
    let src = CommandLine.arguments[i + 1]
    let dst = CommandLine.arguments[i + 2]
    initializeHeadlessText()
    do {
        let opened = try OfficeFormats.read(src)
        if dst.pathExtension.lowercased() == "pdf" {
            let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
            theme.fontFamilyResolver = OfficeFonts.substitute
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
    if args.count > 1 && !args[1].hasPrefix("-") { return args[1] }
    return nil
}()

runStarlingApp(title: "Office",
               width: windowMetric("STARLING_WINDOW_W", 1440),
               height: windowMetric("STARLING_WINDOW_H", 900)) {
    OfficeRoot(initialPath: initialPath)
}
