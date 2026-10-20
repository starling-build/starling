// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

#if !os(WASI)
/// Links to the version the author already checked live. A page with unsent
/// edits must not appear shareable as though those edits were on the website.
enum SitePublishedLink {
    static func prepare(repo: String, out: String, verified: SiteLivePublication.Snapshot,
                        slug: String, paragraph: UInt32? = nil) throws -> URL {
        guard !slug.isEmpty, slug.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
            throw SiteError("Choose a page in this publication.")
        }
        guard try SiteDrafts.load(repo: repo, slug: slug) == nil else {
            throw SiteError("You are previewing a separate local draft. Include it in the next publication and check the website before sharing this revision. Open website to read the previously uploaded version.")
        }
        guard (try? SiteLivePublication.snapshot(repo: repo, out: out)) == verified else {
            throw SiteError("The publication or website details changed. Check the live website again before sharing.")
        }
        func sent(_ path: String) throws -> Data {
            let result = LocalSiteStore.git(["show", verified.receipt.revision + ":" + path], in: repo)
            guard result.status == 0 else { throw SiteError("This page was not found in the verified publication. Publish and check the website before sharing it.") }
            return Data(result.output.utf8)
        }
        let manifest: SiteManifest
        do { manifest = try JSONDecoder().decode(SiteManifest.self, from: sent(out + "/" + SiteFiles.manifest)) }
        catch { throw SiteError("The uploaded page list is unavailable. Publish and check the website before sharing a page.") }
        guard let published = manifest.node(slug) else {
            throw SiteError("This page was not in the verified publication. Publish and check the website before sharing it.")
        }
        let config = try SiteBuilder.readConfig(repo)
        guard let current = SiteBuilder.manifest(from: config).node(slug) else {
            throw SiteError("This page is no longer in the local publication.")
        }
        let root = URL(fileURLWithPath: repo).standardizedFileURL.resolvingSymlinksInPath()
        let source = root.appendingPathComponent(SiteFiles.pagePath(slug)).resolvingSymlinksInPath()
        guard source.path.hasPrefix(root.path + "/"), let local = try? Data(contentsOf: source) else {
            throw SiteError("The saved page is unavailable. Reopen the publication before sharing it.")
        }
        let uploaded = try sent(out + "/" + SiteFiles.pagePath(slug))
        guard local == uploaded, current.title == published.title, config.title == manifest.title, config.details == manifest.details else {
            throw SiteError("This page has saved changes. Publish them and check the live website before copying its link.")
        }
        if let paragraph {
            guard paragraph != 0, let page = SiteFiles.decodePage(uploaded),
                  page.document.paragraphs.filter({ $0.id == paragraph }).count == 1 else {
                throw SiteError("This link does not identify a single passage in the published page. Share the page link, or update and publish the document first.")
            }
        }
        // A slug alias exists for home too; never attach passage links to a
        // root alias which may later point to a different document.
        let pageURL = verified.website.appendingPathComponent(slug, isDirectory: true)
        guard var parts = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) else {
            throw SiteError("The page address is unavailable.")
        }
        if let paragraph { parts.fragment = "p=\(paragraph)" }
        guard let url = parts.url else { throw SiteError("The page address is unavailable.") }
        return url
    }
}
#endif
