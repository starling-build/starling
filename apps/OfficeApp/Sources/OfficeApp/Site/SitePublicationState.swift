// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

#if !os(WASI)
/// A successful push recorded privately in this checkout. A build or local
/// commit cannot create this evidence, and it never proves live deployment.
enum SitePublicationState {
    enum Status: String {
        case unknown, pending, sent, held
        var message: String {
            switch self {
            case .unknown: return "Saved locally. No matching publish record on this device; live status is unknown."
            case .pending: return "Saved changes need publishing."
            case .sent: return "Saved version sent to hosting."
            case .held: return "Website version sent to hosting. Separate draft revisions remain local."
            }
        }
    }

    struct Receipt: Codable, Equatable {
        let version: Int
        let revision: String
        let destination: String
        let target: String
        let out: String
    }

    static func destination(repo: String) throws -> String {
        let result = LocalSiteStore.git(["remote", "get-url", "--push", "--all", "origin"], in: repo)
        let urls = result.output.split(separator: "\n")
        guard result.status == 0, urls.count == 1 else { throw SiteError("Choose one publishing destination.") }
        return String(urls[0])
    }

    static func receiptURL(repo: String) throws -> URL {
        let root = LocalSiteStore.git(["rev-parse", "--show-toplevel"], in: repo)
        guard root.status == 0,
              URL(fileURLWithPath: root.output.trimmingWhitespace()).resolvingSymlinksInPath().path ==
                URL(fileURLWithPath: repo).standardizedFileURL.resolvingSymlinksInPath().path else {
            throw SiteError("Open the publication's own repository.")
        }
        let result = LocalSiteStore.git(["rev-parse", "--absolute-git-dir"], in: repo)
        guard result.status == 0 else { throw SiteError("Publication history is unavailable.") }
        return URL(fileURLWithPath: result.output.trimmingWhitespace()).appendingPathComponent("starling-publish.json")
    }

    static func record(repo: String, revision: String, destination: String, target: String, out: String) throws {
        let receipt = Receipt(version: 1, revision: revision, destination: destination, target: target, out: out)
        try JSONEncoder().encode(receipt).write(to: receiptURL(repo: repo), options: .atomic)
    }

    static func matchingReceipt(repo: String, out: String) throws -> Receipt {
        let receipt = try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: receiptURL(repo: repo)))
        let arguments = try SiteHosting.pushArguments(repo: repo)
        guard receipt.version == 1, receipt.out == out,
              receipt.destination == (try destination(repo: repo)),
              arguments.last == "HEAD:" + receipt.target,
              (40...64).contains(receipt.revision.count), receipt.revision.allSatisfy({ $0.isHexDigit }),
              LocalSiteStore.git(["cat-file", "-e", receipt.revision + "^{commit}"], in: repo).status == 0 else { throw SiteError("Publish this publication from this device before checking its website.") }
        return receipt
    }

    static func status(repo: String, out: String = "docs") -> Status {
        do {
            let held = try !SiteDrafts.loadAll(repo: repo).isEmpty
            let receipt = try matchingReceipt(repo: repo, out: out)
            let paths = [SiteFiles.config, SiteFiles.pagesDir, out]
            // Working files vs the sent commit includes saved, committed-but-
            // unpushed changes and deletions, regardless of the index state.
            let diff = LocalSiteStore.git(["--literal-pathspecs", "diff", "--quiet", receipt.revision, "--"] + paths, in: repo)
            guard diff.status == 0 || diff.status == 1 else { return .unknown }
            if diff.status == 1 { return .pending }
            // Include ignored files: .gitignore must not hide new pages.
            let added = LocalSiteStore.git(["--literal-pathspecs", "ls-files", "--others", "-z", "--"] + paths, in: repo)
            guard added.status == 0 else { return .unknown }
            return added.output.isEmpty ? (held ? .held : .sent) : .pending
        } catch { return .unknown }
    }
}
#endif
