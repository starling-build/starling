// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Conversions the server cannot do itself (it does not link the suite):
// the headless OfficeApp binary turns a .docx (or RTF, Markdown) into a
// page body and a page body back into a .docx. One process per call.

import Foundation

struct Converter: Sendable {
    /// Path to the OfficeApp binary; nil disables import and export.
    let officeApp: String?

    enum Failure: Error, CustomStringConvertible {
        case unavailable
        case failed(String)
        var description: String {
            switch self {
            case .unavailable: return "no OfficeApp binary configured (--office-app)"
            case .failed(let s): return s
            }
        }
    }

    private func run(_ args: [String]) throws {
        guard let officeApp else { throw Failure.unavailable }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: officeApp)
        p.arguments = args
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let text = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw Failure.failed("OfficeApp \(args.first ?? "") failed (\(p.terminationStatus)): \(text.prefix(300))")
        }
    }

    private func scratch(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("wiki-\(UUID().uuidString)-\(name)")
    }

    /// A file's bytes (named for its extension) as a page body.
    func toPage(_ data: Data, named name: String) throws -> String {
        let ext = (name as NSString).pathExtension.isEmpty ? "docx" : (name as NSString).pathExtension
        let input = scratch("in.\(ext)"), output = scratch("out.json")
        defer { try? FileManager.default.removeItem(at: input); try? FileManager.default.removeItem(at: output) }
        try data.write(to: input)
        try run(["--page-json", input.path, output.path])
        return String(decoding: try Data(contentsOf: output), as: UTF8.self)
    }

    /// A page body as a .docx.
    func toDocx(_ body: String) throws -> Data {
        let input = scratch("in.json"), output = scratch("out.docx")
        defer { try? FileManager.default.removeItem(at: input); try? FileManager.default.removeItem(at: output) }
        try Data(body.utf8).write(to: input)
        try run(["--page-docx", input.path, output.path])
        return try Data(contentsOf: output)
    }
}

/// What the server reads out of a page body for itself: the first lines
/// of text for the shell's description. The body is the suite's JSON; this
/// walks only the `paragraphs[].text` strings and nothing else.
enum BodyText {
    static func plainText(_ body: String, limit: Int = 200_000) -> String {
        guard let data = body.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let doc = root["document"] as? [String: Any],
              let paragraphs = doc["paragraphs"] as? [[String: Any]] else { return "" }
        var out = ""
        for p in paragraphs {
            if let t = p["text"] as? String, !t.isEmpty {
                if !out.isEmpty { out += "\n" }
                out += t
                if out.count > limit { break }
            }
        }
        return out
    }
}
