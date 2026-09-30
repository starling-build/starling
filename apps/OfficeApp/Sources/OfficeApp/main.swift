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
#endif

#if os(Windows)
Win32WindowedHost.install()
#elseif os(macOS)
CocoaWindowedHost.install()
#elseif os(iOS)
UIKitWindowedHost.install()
#elseif STARLING_GTK
GTKWindowedHost.install()
#endif

private func windowMetric(_ key: String, _ fallback: Int) -> Int {
    guard let v = ProcessInfo.processInfo.environment[key], let n = Int(v), n > 0
    else { return fallback }
    return n
}

// `--convert <in> <out>`: the formats without the window, for scripts and
// for checking our output against other readers (`textutil`, LibreOffice).
if let i = CommandLine.arguments.firstIndex(of: "--convert"), i + 2 < CommandLine.arguments.count {
    let src = CommandLine.arguments[i + 1]
    let dst = CommandLine.arguments[i + 2]
    // No host boots here, so nobody hands the bridge its ICU data; without
    // it a PDF's lines break between characters. Same file the hosts use.
    let exeDir = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
        .deletingLastPathComponent().path
    for candidate in [exeDir + "/data/icudtl.dat", exeDir + "/../Resources/data/icudtl.dat",
                      exeDir + "/../share/starling/icudtl.dat"]
    where FileManager.default.fileExists(atPath: candidate) {
        _ = flutter.swift_bridge.InitializeICU(candidate)
        break
    }
    do {
        let opened = try OfficeFormats.read(src)
        if (dst as NSString).pathExtension.lowercased() == "pdf" {
            // The bridge's own font manager serves the PDF, so the document
            // faces have to be registered exactly as the window does it.
            OfficeFonts.register()
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
            guard PdfExport.write(opened.document, pageSetup: opened.pageSetup ?? .letter, theme: theme,
                                  to: dst, title: (src as NSString).lastPathComponent) else {
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
