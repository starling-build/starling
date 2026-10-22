// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

#if !os(WASI)
/// Device-local intentions, never instructions to the builder or publisher.
/// Dates describe a calendar day, without inventing a deployment time or zone.
enum SiteReleasePlan {
    struct Snapshot: Equatable {
        let id: String?
        let dates: [String: String]
    }
    private struct Record: Codable {
        let version: Int
        let id: String
        let dates: [String: String]
    }
    struct Entry {
        let slug: String
        let title: String
        let nextPublication: String
        let uploadedRevision: String?
        let date: String?
        let canPlan: Bool
        let canPreview: Bool
    }

    private static func validSlug(_ slug: String) -> Bool {
        !slug.isEmpty && slug.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    static func validDate(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ [4, 7].contains($0.offset) || (48...57).contains($0.element) }),
              let year = Int(value.prefix(4)), year > 0,
              let month = Int(value.dropFirst(5).prefix(2)), (1...12).contains(month),
              let day = Int(value.suffix(2)) else { return false }
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        return (1...[31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]).contains(day)
    }

    static func storageURL(repo: String) throws -> URL {
        let git = try SitePublicationState.receiptURL(repo: repo).deletingLastPathComponent().resolvingSymlinksInPath()
        let file = git.appendingPathComponent("starling-release-plan.json")
        // Reject even dangling symbolic links, which fileExists does not see.
        if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path) {
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw SiteError("The release plan must be a regular file in this publication's local history folder.")
            }
        }
        guard file.resolvingSymlinksInPath().path == file.path else { throw SiteError("Invalid local release plan storage.") }
        return file
    }

    static func load(repo: String) throws -> Snapshot {
        let file = try storageURL(repo: repo)
        guard FileManager.default.fileExists(atPath: file.path) else { return Snapshot(id: nil, dates: [:]) }
        let record: Record
        do { record = try JSONDecoder().decode(Record.self, from: Data(contentsOf: file)) }
        catch { throw SiteError("The local release plan could not be read. Keep it intact and recover it before editing dates.") }
        guard record.version == 1, UUID(uuidString: record.id) != nil,
              record.dates.allSatisfy({ validSlug($0.key) && validDate($0.value) }) else {
            throw SiteError("This release plan cannot be read by this version. Keep it intact before editing dates.")
        }
        return Snapshot(id: record.id, dates: record.dates)
    }

    @discardableResult
    static func save(repo: String, slug: String, date: String?, expected: Snapshot) throws -> Snapshot {
        try SiteDrafts.mutate(repo: repo) {
            guard validSlug(slug), date == nil || validDate(date!) else {
                throw SiteError("Enter a real calendar date as YYYY-MM-DD, or clear the date.")
            }
            guard try load(repo: repo) == expected else {
                throw SiteError("The release plan changed in another window. Refresh the plan before saving your date.")
            }
            if date != nil {
                let manifest = try SiteBuilder.manifest(from: SiteBuilder.readConfig(repo))
                let drafts = try SiteUnpublishedDrafts.loadAll(repo: repo)
                guard manifest.node(slug) != nil || drafts.contains(where: { $0.slug == slug }) else {
                    throw SiteError("This chapter is no longer in the publication. Refresh the plan; its old date can still be cleared.")
                }
            }
            var dates = expected.dates
            dates[slug] = date
            let record = Record(version: 1, id: UUID().uuidString, dates: dates)
            try JSONEncoder().encode(record).write(to: storageURL(repo: repo), options: .atomic)
            return Snapshot(id: record.id, dates: dates)
        }
    }

    static func entries(review: SitePublishReview, plan: Snapshot) -> [Entry] {
        var entries = review.unpublished.map {
            Entry(slug: $0.slug, title: $0.title, nextPublication: "Not included · unpublished draft",
                  uploadedRevision: nil, date: plan.dates[$0.slug], canPlan: true, canPreview: true)
        }
        entries += review.pages.map {
            let state: String
            if $0.heldDraft != nil { state = "Included website version · next draft stays local" }
            else {
                switch $0.change {
                case .included: state = "Included · upload comparison unavailable"
                case .added: state = "Included · new since last upload"
                case .updated: state = "Included · changes since last upload"
                case .unchanged: state = "Included · unchanged since last upload"
                }
            }
            return Entry(slug: $0.slug, title: $0.title, nextPublication: state,
                         uploadedRevision: $0.change == .added ? nil : review.uploadedRevision,
                         date: plan.dates[$0.slug], canPlan: true, canPreview: true)
        }
        entries += review.setAside.map {
            Entry(slug: $0.slug, title: $0.title, nextPublication: "Not included · set aside",
                  uploadedRevision: nil, date: plan.dates[$0.slug], canPlan: true, canPreview: false)
        }
        entries += review.removed.map {
            Entry(slug: $0.slug, title: $0.title, nextPublication: "Removed from the next website version",
                  uploadedRevision: review.uploadedRevision, date: plan.dates[$0.slug], canPlan: false, canPreview: false)
        }
        let known = Set(entries.map(\.slug))
        // Preserve orphaned intentions visibly instead of silently dropping a date.
        entries += plan.dates.keys.sorted().filter { !known.contains($0) }.map {
            Entry(slug: $0, title: $0, nextPublication: "Chapter unavailable · clear its old date if no longer needed",
                  uploadedRevision: nil, date: plan.dates[$0], canPlan: false, canPreview: false)
        }
        return entries.enumerated().sorted {
            let left = $0.element.date ?? "~", right = $1.element.date ?? "~"
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element)
    }
}
#endif
