// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

#if !os(WASI)
/// Commit attribution for this publication only. This does not sign in to a host.
enum SitePublishingIdentity {
    struct Snapshot {
        let name: String
        let email: String
        let configURL: URL
        let configBytes: Data
    }

    static func load(repo: String) throws -> Snapshot {
        try SiteHosting.requireRoot(repo)
        let result = LocalSiteStore.git(["rev-parse", "--git-path", "config"], in: repo)
        guard result.status == 0 else { throw SiteError("Could not read this publication's author settings.") }
        let path = result.output.trimmingWhitespace()
        let url = URL(fileURLWithPath: path.hasPrefix("/") ? path : repo + "/" + path).standardizedFileURL
        // Do not replace a config symlink that deliberately redirects settings.
        guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw SiteError("This publication uses linked Git settings. Update its author identity in Git.")
        }
        func value(_ key: String) -> String {
            let result = LocalSiteStore.git(["config", "--get", key], in: repo)
            return result.status == 0 ? result.output.trimmingWhitespace() : ""
        }
        return Snapshot(name: value("user.name"), email: value("user.email"), configURL: url.resolvingSymlinksInPath(),
                        configBytes: try Data(contentsOf: url))
    }

    static func save(name: String, email: String, repo: String, expected: Snapshot) throws {
        let name = name.trimmingWhitespace(), email = email.trimmingWhitespace()
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "<>"))
        guard !name.isEmpty, name.count <= 200, name.rangeOfCharacter(from: forbidden) == nil else {
            throw SiteError("Enter the name to show in this publication's history, without line breaks or angle brackets.")
        }
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }), email.count <= 254,
              email.rangeOfCharacter(from: forbidden.union(.whitespacesAndNewlines)) == nil else {
            throw SiteError("Enter a valid publishing email, such as your GitHub no-reply address.")
        }
        let current = try load(repo: repo)
        guard current.configURL == expected.configURL,
              current.name == expected.name, current.email == expected.email else {
            throw SiteError("Author settings changed elsewhere. Reopen Publishing settings before saving.")
        }
        // Respect Git's config lock, and install both fields together. Failure
        // must not leave a new name paired with the previous email.
        let lock = URL(fileURLWithPath: current.configURL.path + ".lock")
        do { try Data().write(to: lock, options: .withoutOverwriting) }
        catch { throw SiteError("Author settings are busy or not writable. Finish other Git operations, then try again.") }
        defer { try? FileManager.default.removeItem(at: lock) }
        let stage = current.configURL.deletingLastPathComponent().appendingPathComponent(".starling-author-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: stage) }
        try current.configBytes.write(to: stage, options: .withoutOverwriting)
        for (key, value) in [("user.name", name), ("user.email", email)] {
            guard LocalSiteStore.git(["config", "--file", stage.path, "--replace-all", key, value], in: repo).status == 0 else {
                throw SiteError("Could not save the publishing author. No author settings were changed.")
            }
        }
        guard try Data(contentsOf: current.configURL) == current.configBytes else {
            throw SiteError("Author settings changed elsewhere. Reopen Publishing settings before saving.")
        }
        let updated = try Data(contentsOf: stage)
        try updated.write(to: current.configURL, options: .atomic)
        // Worktree or included configuration can override the fields we just
        // wrote. Never report that the requested attribution is active if it isn't.
        let effective = try? load(repo: repo)
        guard effective?.name == name, effective?.email == email else {
            if (try? Data(contentsOf: current.configURL)) == updated {
                try current.configBytes.write(to: current.configURL, options: .atomic)
            }
            throw SiteError("Other Git settings override this publication's author. Update those settings in Git; the author change was not applied.")
        }
    }
}
#endif
