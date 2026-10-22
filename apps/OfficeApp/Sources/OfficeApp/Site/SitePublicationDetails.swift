// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Author-supplied publication information, separate from document formatting
/// and Git identity. An edition label does not create an archived edition.
struct SitePublicationDetails: Codable, Equatable {
    var version: Int = 1
    var byline: String? = nil
    var summary: String? = nil
    var edition: String? = nil
    var language: String? = nil
    var rights: String? = nil

    var hasContent: Bool { [byline, summary, edition, language, rights].contains { $0?.isEmpty == false } }

    func validated() throws -> Self {
        guard version == 1 else { throw SiteError("These publication details need a newer version of Starling.") }
        func field(_ value: String?, name: String, limit: Int) throws -> String? {
            guard let text = value?.trimmingWhitespace(), !text.isEmpty else { return nil }
            guard text.count <= limit, !text.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
                throw SiteError("\(name) must be a single line of at most \(limit) characters.")
            }
            return text
        }
        var result = self
        result.byline = try field(byline, name: "Byline", limit: 200)
        result.summary = try field(summary, name: "Description", limit: 300)
        result.edition = try field(edition, name: "Edition label", limit: 120)
        result.rights = try field(rights, name: "Rights statement", limit: 500)
        result.language = try field(language, name: "Language", limit: 35)
        if let language = result.language {
            let parts = language.split(separator: "-", omittingEmptySubsequences: false)
            guard let first = parts.first, (2...8).contains(first.count),
                  first.allSatisfy({ $0.isASCII && $0.isLetter }),
                  parts.dropFirst().allSatisfy({ (1...8).contains($0.count) && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) } }) else {
                throw SiteError("Use a language code such as en, en-GB, fr or zh-Hant.")
            }
        }
        return result
    }
}

#if !os(WASI)
enum SitePublicationDetailsStore {
    struct Snapshot {
        let bytes: Data
        let config: SiteConfig
    }

    static func load(repo: String) throws -> Snapshot {
        let data = try Data(contentsOf: URL(fileURLWithPath: repo + "/" + SiteFiles.config))
        var config = try JSONDecoder().decode(SiteConfig.self, from: data)
        config.details = try config.details?.validated()
        return Snapshot(bytes: data, config: config)
    }

    /// Patch only our known fields; preserve unrelated configuration and reject
    /// intervening edits rather than overwriting a stale settings form.
    static func save(_ details: SitePublicationDetails, repo: String, expected: Snapshot) throws {
        let details = try details.validated()
        let path = URL(fileURLWithPath: repo + "/" + SiteFiles.config)
        guard try Data(contentsOf: path) == expected.bytes else {
            throw SiteError("The publication changed while these details were open. Reopen Publication details before saving.")
        }
        guard var object = try JSONSerialization.jsonObject(with: expected.bytes) as? [String: Any] else {
            throw SiteError("The publication settings could not be read.")
        }
        var saved = object["details"] as? [String: Any] ?? [:]
        saved["version"] = details.version
        saved["byline"] = details.byline
        saved["summary"] = details.summary
        saved["edition"] = details.edition
        saved["language"] = details.language
        saved["rights"] = details.rights
        object["details"] = saved
        object["home"] = expected.config.resolvedHome
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: path, options: .atomic)
    }
}
#endif
