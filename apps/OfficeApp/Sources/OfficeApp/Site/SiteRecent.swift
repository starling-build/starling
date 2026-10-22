// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

#if !os(WASI)
/// Local navigation history, kept outside publication content and Git.
struct SiteRecent {
    struct Entry: Codable, Equatable {
        var path: String
        var title: String
        var slug: String
    }

    struct Item {
        let entry: Entry
        let available: Bool
        let pageTitle: String?
    }

    let directory: String
    init(directory: String? = nil) {
        self.directory = directory
            ?? ProcessInfo.processInfo.environment["OFFICE_RECOVERY_DIR"].flatMap { $0.isEmpty ? nil : $0 }
            ?? homeDirectory() + "/.config/starling"
    }

    private var file: URL { URL(fileURLWithPath: directory).appendingPathComponent("office-publications.json") }
    private func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    func load() -> [Entry] {
        guard let data = try? Data(contentsOf: file),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return Array(entries.prefix(20))
    }

    func items() -> [Item] {
        load().map { entry in
            guard let config = try? SiteBuilder.readConfig(entry.path) else {
                return Item(entry: entry, available: false, pageTitle: nil)
            }
            var current = entry
            current.title = config.title
            let manifest = SiteBuilder.manifest(from: config, base: "/")
            return Item(entry: current, available: true,
                        pageTitle: manifest.node(entry.slug)?.title ?? manifest.node(manifest.home)?.title)
        }
    }

    /// Called only after opening a page successfully. A missing folder stays
    /// in history, so a disconnected drive does not erase the writer's place.
    func remember(repo: String, slug: String) {
        let path = canonical(repo)
        guard let config = try? SiteBuilder.readConfig(path),
              SiteBuilder.manifest(from: config).node(slug) != nil else { return }
        var entries = load().filter { canonical($0.path) != path }
        entries.insert(Entry(path: path, title: config.title, slug: slug), at: 0)
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(Array(entries.prefix(20))).write(to: file, options: .atomic)
        } catch {
            // An unwritable history file must not prevent editing a document.
        }
    }

    func route(for repo: String) -> String {
        let path = canonical(repo)
        guard let entry = load().first(where: { canonical($0.path) == path }),
              let config = try? SiteBuilder.readConfig(path) else { return "/" }
        let manifest = SiteBuilder.manifest(from: config, base: "/")
        // A removed page falls back to the publication's current home.
        return manifest.node(entry.slug) == nil ? "/" : manifest.route(entry.slug)
    }
}
#endif
