// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if !os(WASI)
import Flutter
import OfficeText
import FlutterSwiftBridge
import Foundation

/// `--read-bench file…`: what opening a file costs, without a window, one
/// tab-separated line per file — its size, then each step in milliseconds
/// (the file read, the parse, and what the window needs before it can
/// show the first screen), a count that says how much was in it, and the
/// process's peak memory after it. test/office-read-bench.sh makes large
/// files and tabulates these.
///
/// What each kind's steps are:
///   .docx/.rtf/…  parse; layout — EVERY paragraph, which is what the
///                 editor does before its first frame; paint — page one.
///   .pptx         parse; load — the deck into its controller; paint —
///                 slide one, its pictures decoded first.
///   .xlsx/.csv    parse; load — formulas parsed and the workbook
///                 calculated; paint — a 1440 by 900 view of the
///                 active sheet through the grid's own painter.
enum ReadBench {
    static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
    static func ms(_ from: UInt64, _ to: UInt64) -> String { String(format: "%.1f", Double(to - from) / 1e6) }

    static func peakMB() -> String {
        #if os(Windows)
        // (No getrusage there; the bench's memory column is a Mac and Linux figure.)
        return "-"
        #else
        var u = rusage()
        #if os(Linux)
        // (glibc's `who` is an enum where Darwin's is an Int32.)
        getrusage(RUSAGE_SELF.rawValue, &u)
        let bytes = Double(u.ru_maxrss) * 1024      // kilobytes there
        #else
        getrusage(RUSAGE_SELF, &u)
        let bytes = Double(u.ru_maxrss)
        #endif
        return String(format: "%.0f", bytes / 1_048_576)
        #endif
    }

    static func run(_ paths: [String]) -> Int32 {
        initializeHeadlessText()
        print("file\tMB\tread\tparse\tlayout|load\tpaint\ttotal\twhat\tpeakMB")
        var failed: Int32 = 0
        for path in paths {
            do { print(try one(path)) } catch {
                print("\(path.lastPathComponent)\tERROR\t\(error)")
                failed = 1
            }
        }
        return failed
    }

    static func one(_ path: String) throws -> String {
        let t0 = now()
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let t1 = now()
        let mb = String(format: "%.2f", Double(data.count) / 1_048_576)
        let name = path.lastPathComponent
        var t2 = t1, t3 = t1, t4 = t1
        var what = ""
        switch path.pathExtension.lowercased() {
        case "pptx":
            let (state, theme, package) = try Pptx.read(data)
            t2 = now()
            let deck = DeckController()
            deck.load(state, theme: theme, package: package)
            t3 = now()
            let cache = SlideTextCache()
            var done = false
            Task { @MainActor in
                if let slide = deck.slides.first {
                    var images: [ImageAttachment] = []
                    if let i = slide.background?.image { images.append(i) }
                    if let i = slide.inheritedBackground?.image { images.append(i) }
                    for s in slide.decorations + slide.shapes {
                        if let i = s.picture { images.append(i) }
                        if let i = s.fillStyle?.image { images.append(i) }
                    }
                    await cache.preload(images)
                    let size = deck.slideSize
                    let recorder = NativePictureRecorder()
                    let canvas = NativeCanvas(recorder: recorder, cullRect: Rect.fromLTWH(0, 0, size.width, size.height))
                    SlidePainter(slide: slide, theme: deck.theme, slideSize: size, revision: deck.revision, cache: cache,
                                 placeholders: false).paint(canvas, size)
                    _ = recorder.endRecording()
                }
                done = true
            }
            let deadline = Date().addingTimeInterval(120)
            while !done && Date() < deadline { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.002)) }
            t4 = now()
            what = "\(deck.slides.count) slides, \(deck.slides.reduce(0) { $0 + $1.shapes.count }) shapes"
        case "xlsx", "csv", "tsv":
            let book = path.pathExtension.lowercased() == "xlsx" ? try Xlsx.read(data)
                : Csv.read(String(decoding: data, as: UTF8.self), name: name.deletingPathExtension)
            t2 = now()
            let c = WorkbookController()
            c.load(book)
            t3 = now()
            SheetGridState(headless: c).paintFirstScreen(Size(1440, 900))
            t4 = now()
            what = "\(book.sheets.count) sheets, \(book.sheets.reduce(0) { $0 + $1.cells.count }) cells"
        default:
            let opened = try OfficeFormats.read(data, named: name)
            t2 = now()
            let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
            theme.fontFamilyResolver = OfficeFonts.drawn
            let setup = opened.pageSetup ?? .letter
            let layout = RichLayout(theme: theme, paragraphCount: opened.document.paragraphs.count)
            layout.scale = 1.0
            layout.pageSetup = setup
            layout.width = setup.columnWidth * theme.pixelsPerPoint
            layout.ensureLaidOut(opened.document)
            t3 = now()
            let rect = layout.pageRect(0)
            let recorder = NativePictureRecorder()
            let canvas = NativeCanvas(recorder: recorder, cullRect: rect)
            layout.paint(canvas, visible: rect, document: opened.document, selection: nil,
                         caret: nil, pageBackground: nil)
            _ = recorder.endRecording()
            t4 = now()
            what = "\(layout.pageCount) pages, \(opened.document.paragraphs.count) paragraphs, \(opened.document.wordCount) words"
        }
        return [name, mb, ms(t0, t1), ms(t1, t2), ms(t2, t3), ms(t3, t4), ms(t0, t4), what, peakMB()].joined(separator: "\t")
    }

    /// `--read-bench-make <pages> <out.docx|out.pptx>`: the generated
    /// performance document (or the sample deck, repeated) saved, so there
    /// is a file of any length to open.
    static func make(pages: Int, to path: String) -> Int32 {
        initializeHeadlessText()
        do {
            if path.pathExtension.lowercased() == "pptx" {
                // The sample deck (titles, bullets, a table, a chart, a
                // picture), its slides copied until there are enough.
                let deck = SlidesSample.make()
                let base = deck.slides.count
                while deck.slides.count < pages { deck.duplicateSlide(deck.slides.count % base) }
                try Pptx.write(deck).write(to: URL(fileURLWithPath: path))
                print("wrote \(deck.slides.count) slides to \(path)")
                return 0
            }
            let doc = DemoDocument.make(pages: pages)
            try OfficeFormats.write(doc, to: path, pageSetup: .letter)
            print("wrote \(doc.paragraphs.count) paragraphs to \(path)")
            return 0
        } catch {
            FileHandle.standardError.write("make failed: \(error)\n".data(using: .utf8)!)
            return 1
        }
    }
}
#endif
