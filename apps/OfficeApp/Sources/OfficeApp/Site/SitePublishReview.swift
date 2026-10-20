// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

#if !os(WASI)
/// A read-only inventory of saved website pages. Comparison uses the last
/// matching upload receipt, never HEAD or a possibly failed local build.
struct SitePublishReview {
    enum Change: String {
        case included = "Included", added = "Added", updated = "Updated", unchanged = "Unchanged"
    }
    struct Page {
        let slug: String
        let title: String
        let depth: Int
        let route: String
        let previousRoute: String?
        let isHome: Bool
        let change: Change
        let references: [SiteReaderText.ReferenceIssue]
        let comparison: SiteReleaseComparison?
        let heldDraft: SiteDrafts.Draft?
    }
    struct RemovedPage {
        let title: String
        let route: String
        let comparison: SiteReleaseComparison
    }
    let title: String
    let pages: [Page]
    let removed: [RemovedPage]
    let compared: Bool
    let settingsChanged: Bool
    var referenceCount: Int { pages.reduce(0) { $0 + $1.references.count } }

    var summary: String {
        let count = "\(pages.count) website page\(pages.count == 1 ? "" : "s")"
        guard compared else { return "\(count) included. No matching upload record is available for comparison." }
        let added = pages.filter { $0.change == .added }.count
        let updated = pages.filter { $0.change == .updated }.count
        return "\(count) included: \(added) added, \(updated) updated, \(removed.count) removed since the last recorded upload."
    }

    static func load(repo: String, out: String, web: String?) throws -> Self {
        let config = try SiteBuilder.readConfig(repo)
        let sources = try SiteBuilder.validatedSources(repo: repo, config: config, web: web)
        let drafts = try SiteDrafts.loadAll(repo: repo)
        let current = SiteBuilder.manifest(from: config)
        let prior = baseline(repo: repo, out: out)
        let oldNodes = prior.map { Dictionary(uniqueKeysWithValues: $0.manifest.flattened().map { ($0.node.slug, $0.node) }) } ?? [:]
        let pages = sources.map { source -> Page in
            let node = source.node
            let old = oldNodes[node.slug]
            let previousRoute = old.flatMap { prior?.manifest.route($0.slug) }
            let route = current.route(node.slug)
            let change: Change
            let saved = SiteFiles.decodePage(source.data)
            let draft = drafts[node.slug]
            let working = draft.flatMap { SiteFiles.decodePage($0.working) } ?? saved
            // Identical uploaded bytes need no second document decode.
            let uploaded = prior?.bytes[node.slug].flatMap { data in
                data == source.data ? saved : SiteFiles.decodePage(data)
            }
            if prior == nil { change = .included }
            else if old == nil { change = .added }
            else if old?.title != node.title || prior?.bytes[node.slug] != source.data || previousRoute != route { change = .updated }
            else { change = .unchanged }
            return Page(slug: node.slug, title: node.title, depth: source.depth, route: route,
                        previousRoute: previousRoute != route ? previousRoute : nil,
                        isHome: node.slug == current.home, change: change,
                        references: working.map { SiteReaderText.referenceIssues(in: $0.document) } ?? [],
                        comparison: prior == nil ? nil : SiteReleaseComparison(
                            previous: uploaded, current: working,
                            previousTitle: old?.title, currentTitle: node.title),
                        heldDraft: draft)
        }
        let slugs = Set(pages.map(\.slug))
        let removed = prior?.manifest.flattened().filter { !slugs.contains($0.node.slug) }.map {
            RemovedPage(title: $0.node.title, route: prior!.manifest.route($0.node.slug),
                        comparison: SiteReleaseComparison(
                            previous: prior!.bytes[$0.node.slug].flatMap { SiteFiles.decodePage($0) }, current: nil,
                            previousTitle: $0.node.title, currentTitle: nil))
        } ?? []
        let settingsChanged = prior.map {
            $0.config.title != config.title || $0.config.base != config.base ||
            $0.config.url != config.url || $0.config.repository != config.repository ||
            $0.config.pages != config.pages || $0.config.resolvedHome != config.resolvedHome || $0.config.details != config.details
        } ?? false
        return Self(title: config.title, pages: pages, removed: removed, compared: prior != nil, settingsChanged: settingsChanged)
    }

    private struct Baseline {
        let config: SiteConfig
        let manifest: SiteManifest
        let bytes: [String: Data]
    }

    private static func baseline(repo: String, out: String) -> Baseline? {
        guard let receipt = try? SitePublicationState.matchingReceipt(repo: repo, out: out) else { return nil }
        func read(_ path: String) -> Data? {
            let result = LocalSiteStore.git(["show", receipt.revision + ":" + path], in: repo)
            return result.status == 0 ? Data(result.output.utf8) : nil
        }
        guard let manifestData = read(out + "/" + SiteFiles.manifest),
              let manifest = try? JSONDecoder().decode(SiteManifest.self, from: manifestData),
              let configData = read(SiteFiles.config),
              let config = try? JSONDecoder().decode(SiteConfig.self, from: configData),
              !manifest.pages.isEmpty else { return nil }
        var bytes: [String: Data] = [:]
        for (node, _) in manifest.flattened() {
            guard !node.slug.isEmpty, node.slug.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }),
                  bytes[node.slug] == nil,
                  let data = read(out + "/" + SiteFiles.pagePath(node.slug)),
                  SiteFiles.decodePage(data) != nil else { return nil }
            bytes[node.slug] = data
        }
        return Baseline(config: config, manifest: manifest, bytes: bytes)
    }
}
#endif
