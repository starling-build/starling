// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Flutter

#if !os(WASI)
/// Creates a complete local publication without touching an existing folder,
/// changing the user's Git identity, committing, or contacting a remote.
enum SiteCreation {
    static func create(title: String, parent: String, source: String? = nil) throws -> String {
        let title = title.trimmingWhitespace()
        guard !title.isEmpty else { throw SiteError("Enter a publication title.") }
        let fm = FileManager.default
        let parentURL = URL(fileURLWithPath: parent).standardizedFileURL.resolvingSymlinksInPath()
        var directory: ObjCBool = false
        guard fm.fileExists(atPath: parentURL.path, isDirectory: &directory), directory.boolValue else {
            throw SiteError("Choose an existing folder for your publication.")
        }
        let target = parentURL.appendingPathComponent(SiteFiles.slug(for: title))
        guard (try? fm.attributesOfItem(atPath: target.path)) == nil else {
            throw SiteError("A folder or file named \(target.lastPathComponent) already exists. Choose a different title or location.")
        }
        guard LocalSiteStore.git(["rev-parse", "--show-toplevel"], in: parentURL.path).status != 0 else {
            throw SiteError("Choose a location outside an existing Git repository. Each publication has its own history.")
        }
        let page: SitePage
        if let source {
            guard source.pathExtension.lowercased() == "docx" else { throw SiteError("Choose a Word (.docx) document.") }
            do {
                let opened = try DocxFormat.read(Data(contentsOf: URL(fileURLWithPath: source)))
                page = SitePage(document: opened.document, pageSetup: opened.pageSetup)
            } catch {
                throw SiteError("Could not open \(source.lastPathComponent). Choose a readable, unencrypted Word (.docx) document.")
            }
        } else {
            var blank = RichDocument()
            blank.styles = OfficeStyles.sheet
            page = SitePage(document: blank, pageSetup: .letter)
        }
        let stage = parentURL.appendingPathComponent(".starling-create-" + UUID().uuidString)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: stage) }
        try fm.createDirectory(at: stage.appendingPathComponent("pages"), withIntermediateDirectories: false)
        var document = page.document
        document.assignParagraphIDs()
        try RichDocumentEnvelope.encode(document, pageSetup: page.pageSetup)
            .write(to: stage.appendingPathComponent(SiteFiles.pagePath("welcome")))
        try SiteBuilder.writeConfig(SiteConfig(title: title, pages: [SiteNode(slug: "welcome", title: title)]), to: stage.path)
        try publishingGuide.write(to: stage.appendingPathComponent("PUBLISHING.md"), atomically: true, encoding: .utf8)
        let initialized = LocalSiteStore.git(["init", "--initial-branch=main"], in: stage.path)
        guard initialized.status == 0 else { throw SiteError("Could not create local history. Install Git and try again. \(initialized.output.trimmingWhitespace())") }
        // moveItem refuses an existing destination, including one created
        // while the scaffold was being prepared.
        try fm.moveItem(at: stage, to: target)
        return target.path
    }

    static let publishingGuide = """
    # Publish your documents

    This publication is local. Nothing has been uploaded.

    Open site.json from Writer's Home → Open publication. Choose Edit document
    to write, or Add a Word document to add more material. Review the page and reading
    views before publishing. Update from Word previews later revisions;
    Apply saves locally and preserves the page address.

    ## First-time hosting setup

    GitHub Pages is the initial supported host. Publishing settings can save your
    author name and email for this publication; signing in to GitHub still uses Git credentials. You can keep writing locally without it.

    1. Create an empty GitHub repository for this publication. A public
       repository exposes source documents as well as the built website.
       Only publish content you intend to make public.
    2. In Writer, choose Publish. First-time setup opens automatically. Enter the
       repository address; leave Website address blank for a GitHub Pages address,
       or enter your own HTTPS address. Choose Save and connect. Existing remotes
       are never replaced. The URL path automatically sets the build base.
    3. Enter your author name and publishing email, then Save author. This affects
       only this publication's change history. GitHub's no-reply email can keep
       your personal address private. Use the sign-in help link if this computer
       is not authenticated with GitHub. Check saved setup, then Continue to publish.
       Local checks do not verify authentication or remote changes.
    4. Choose Publish, optionally describe the changes, then Publish. The first publish sets the upstream branch automatically. The
       build needs the bundled web reader. If pushing fails, your local
       commit is retained so you can resolve the error and retry.
    5. Open website settings on GitHub from Publishing settings. Choose Deploy
       from a branch and the branch and /docs folder shown in the app.
       Wait for deployment, then choose Check live website in the preview.
       Once the uploaded version is confirmed, open the website to review it
       and copy the link for readers.

    ## Later updates

    Edit or import, review, then Publish again. Publish includes site.json,
    pages/ and docs/ only; unrelated files are not included. Source documents
    in pages/ go to the repository. docs/ includes the web reader and generated
    Word and PDF downloads. The first configured page is the home page.

    Creating the remote repository, signing in and enabling Pages are still external
    setup steps. The live check confirms the public version marker, not every page
    or asset. Do not put access tokens in site.json or document content.
    """
}
#endif
