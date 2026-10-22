// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Flutter

#if !os(WASI)
final class SitePublishReviewPanel: StatefulWidget {
    let store: LocalSiteStore
    let onBack: () -> Void
    let onContinue: () -> Void
    let onPreview: (String, UInt32?) -> Void
    init(store: LocalSiteStore, onBack: @escaping () -> Void, onContinue: @escaping () -> Void,
         onPreview: @escaping (String, UInt32?) -> Void) {
        self.store = store; self.onBack = onBack; self.onContinue = onContinue; self.onPreview = onPreview
        super.init()
    }
    override func createState() -> State<StatefulWidget> { _SitePublishReviewState() }
}

private final class _SitePublishReviewState: State<StatefulWidget> {
    private var panel: SitePublishReviewPanel { widget as! SitePublishReviewPanel }
    private var review: SitePublishReview?
    private var busy = false
    private var recoverableDrafts: [SiteUnpublishedDrafts.Draft] = []
    private var error: String?
    private var referenceDetails = Set<String>()
    private var comparison: (value: SiteReleaseComparison, slug: String?)?
    private var planning = false

    override func initState() { super.initState(); refresh() }

    private func refresh() {
        guard !busy else { return }
        let store = panel.store
        setState { busy = true; error = nil; review = nil; recoverableDrafts = [] }
        // Document decoding needs the same stack allowance as import/publish.
        let worker = Thread { [weak self] in
            let result = Result { try SitePublishReview.load(repo: store.repo, out: store.out, web: store.webStage) }
            let recovery: [SiteUnpublishedDrafts.Draft]
            if case .failure = result { recovery = ((try? SiteUnpublishedDrafts.loadAll(repo: store.repo)) ?? []).filter { !$0.isSetAside } }
            else { recovery = [] }
            DispatchQueue.main.async {
                guard let self, self.mounted else { return }
                self.setState {
                    self.busy = false
                    switch result {
                    case .success(let review): self.review = review
                    case .failure(let error): self.error = "\(error)"; self.recoverableDrafts = recovery
                    }
                }
            }
        }
        worker.name = "Starling publication review"
        worker.stackSize = 8 * 1024 * 1024
        worker.start()
    }

    private func changeDraft(slug: String, include: SiteDrafts.Draft? = nil, unpublished: SiteUnpublishedDrafts.Draft? = nil, availability: SiteUnpublishedDrafts.Draft? = nil) {
        guard !busy else { return }
        let store = panel.store
        setState { busy = true; error = nil }
        let worker = Thread { [weak self] in
            let result = Result {
                if let availability {
                    if availability.isSetAside { try SiteUnpublishedDrafts.restore(repo: store.repo, expected: availability) }
                    else { try SiteUnpublishedDrafts.setAside(repo: store.repo, expected: availability) }
                }
                else if let unpublished { try SiteUnpublishedDrafts.include(repo: store.repo, expected: unpublished) }
                else if let include { try SiteDrafts.include(repo: store.repo, expected: include) }
                else { try SiteDrafts.start(repo: store.repo, out: store.out, slug: slug) }
            }
            DispatchQueue.main.async {
                guard let self, self.mounted else { return }
                self.setState { self.busy = false }
                switch result {
                case .success: self.refresh()
                case .failure(let error): self.setState { self.error = "\(error)" }
                }
            }
        }
        worker.name = "Starling chapter draft"
        worker.stackSize = 8 * 1024 * 1024
        worker.start()
    }

    override func build(_ context: any BuildContext) -> Widget {
        if planning {
            return SiteReleasePlanPanel(store: panel.store, onBack: { [weak self] in
                guard let self else { return }
                self.setState { self.planning = false }
                self.refresh()
            }, onPreview: panel.onPreview)
        }
        if let comparison {
            let preview: ((UInt32?) -> Void)? = comparison.slug.map { slug in
                { [weak self] id in self?.panel.onPreview(slug, id) }
            }
            return SiteReleaseComparisonPanel(comparison: comparison.value,
                                              onBack: { [weak self] in self?.setState { self?.comparison = nil } },
                                              onPreview: preview)
        }
        var rows: [Widget] = [
            Text("Review your publication", style: WikiAppearance.text(30, bold: true)), Chrome.vgap(10),
            Text("Publishing shares the included pages below. Separate drafts stay local until you include them.", style: WikiAppearance.text()),
            Chrome.vgap(16), Wrap(spacing: 12, runSpacing: 8, children: [
                Button(onPressed: panel.onBack, child: Text("Back to preview")),
                Button(onPressed: busy ? nil : { [weak self] in self?.refresh() }, child: Text("Refresh review")),
                Button(onPressed: busy || review == nil ? nil : { [weak self] in self?.setState { self?.planning = true } }, child: Text("Release plan")),
                FilledButton(onPressed: busy || review == nil ? nil : panel.onContinue, child: Text("Continue to publish")),
            ]),
        ]
        if busy { rows += [Chrome.vgap(24), Text("Reading saved pages…", style: WikiAppearance.text())] }
        if let error { rows += [Chrome.vgap(24), Text("Publication needs attention", style: WikiAppearance.text(20, bold: true)),
                                Chrome.vgap(8), Text(error, style: WikiAppearance.text())] }
        if !recoverableDrafts.isEmpty {
            rows += [Chrome.vgap(12), Text("Your unpublished chapters are still stored locally. If inclusion was interrupted, retry it below. Other file conflicts must be resolved before publishing.", style: WikiAppearance.text(14))]
            for draft in recoverableDrafts {
                rows += [Chrome.vgap(12), Button(onPressed: busy ? nil : { [weak self] in
                    self?.changeDraft(slug: draft.slug, unpublished: draft)
                }, child: Text("Include chapter: " + draft.title))]
            }
        }
        if let review {
            rows += [Chrome.vgap(24), Text(review.title, style: WikiAppearance.text(23, bold: true)),
                     Chrome.vgap(8), Text(review.summary, style: WikiAppearance.text())]
            if review.compared {
                rows += [Chrome.vgap(6), Text("Compared with the last upload recorded on this device. This does not confirm what is live on the website.", style: WikiAppearance.text(14, color: WikiAppearance.muted))]
            }
            if review.settingsChanged {
                rows += [Chrome.vgap(10), Text("The publication details, address or navigation have also changed.", style: WikiAppearance.text(15, bold: true))]
            }
            if review.referenceCount > 0 {
                rows += [Chrome.vgap(10), Text("\(review.referenceCount) reference\(review.referenceCount == 1 ? "" : "s") to check in text view. Open the details below to see which documents need attention.", style: WikiAppearance.text(15, bold: true))]
            }
            rows += [Chrome.vgap(12), Text("Each included page has a web reading view and Word and PDF downloads. If your hosting repository is public, its source files and history are public too, including other files already committed there.", style: WikiAppearance.text(14, color: WikiAppearance.muted)),
                     Chrome.vgap(8), Text("This is a review of saved website pages. Refresh after changes made outside the app; publishing rebuilds the latest saved files.", style: WikiAppearance.text(14, color: WikiAppearance.muted)),
                     Chrome.vgap(20)]
            if !review.unpublished.isEmpty {
                rows += [Text("Not included · \(review.unpublished.count) unpublished chapter\(review.unpublished.count == 1 ? "" : "s")", style: WikiAppearance.text(21, bold: true)),
                         Chrome.vgap(8), Text("Their titles and documents stay on this device. Include a chapter when it is ready for readers. Back up the entire publication folder, including its local history.", style: WikiAppearance.text(14)), Chrome.vgap(12)]
                for draft in review.unpublished {
                    rows += [Text(draft.title, style: WikiAppearance.text(18, bold: true)), Chrome.vgap(8),
                             Wrap(spacing: 12, runSpacing: 8, children: [
                                 Button(onPressed: busy ? nil : { [weak self] in self?.panel.onPreview(draft.slug, nil) }, child: Text("Preview local draft")),
                                 Button(onPressed: busy ? nil : { [weak self] in self?.changeDraft(slug: draft.slug, unpublished: draft) }, child: Text("Include chapter in next publication")),
                                 Button(onPressed: busy ? nil : { [weak self] in self?.changeDraft(slug: draft.slug, availability: draft) }, child: Text("Set aside")),
                             ]), Chrome.vgap(20)]
                }
            }
            if !review.setAside.isEmpty {
                rows += [Text("Set aside for later · \(review.setAside.count)", style: WikiAppearance.text(21, bold: true)),
                         Chrome.vgap(8), Text("These chapters are kept on this device, outside your working contents and publication. Restore a chapter as an unpublished draft to read, edit or include it.", style: WikiAppearance.text(14)), Chrome.vgap(12)]
                for draft in review.setAside {
                    rows += [Text(draft.title, style: WikiAppearance.text(18, bold: true)), Chrome.vgap(8),
                             Button(onPressed: busy ? nil : { [weak self] in
                                 self?.changeDraft(slug: draft.slug, availability: draft)
                             }, child: Text("Restore as draft")), Chrome.vgap(20)]
                }
            }
            rows += [Text("Included pages", style: WikiAppearance.text(21, bold: true)), Chrome.vgap(12)]
            for page in review.pages {
                var detail: [Widget] = [
                    Text(page.title + (page.isHome ? " · Home" : ""), style: WikiAppearance.text(18, bold: true)),
                    Chrome.vgap(6), Text(page.change.rawValue + " · " + page.route, style: WikiAppearance.text(14, color: WikiAppearance.muted)),
                ]
                if let held = page.heldDraft {
                    detail += [Chrome.vgap(10), Text("Draft held on this device", style: WikiAppearance.text(17, bold: true)),
                               Chrome.vgap(6), Text("Publishing keeps the previously uploaded document. Preview, comparison and reference notices below show your separate draft. Titles and navigation are still included in the release.", style: WikiAppearance.text(14)),
                               Chrome.vgap(8), Button(onPressed: busy ? nil : { [weak self] in
                                   self?.changeDraft(slug: page.slug, include: held)
                               }, child: Text("Include draft in next publication"))]
                } else if page.change == .unchanged {
                    detail += [Chrome.vgap(10), Text("Start a separate draft to keep writing while readers retain this uploaded document. It is saved only on this device; back up the entire publication folder, including its local history.", style: WikiAppearance.text(14, color: WikiAppearance.muted)),
                               Chrome.vgap(8), Button(onPressed: busy ? nil : { [weak self] in self?.changeDraft(slug: page.slug) },
                                                          child: Text("Start next draft"))]
                }
                if let route = page.previousRoute {
                    detail += [Chrome.vgap(6), Text("Previously: " + route + " — existing links may need updating.", style: WikiAppearance.text(14))]
                }
                if !page.references.isEmpty {
                    let expanded = referenceDetails.contains(page.slug)
                    detail += [Chrome.vgap(10), Text("\(page.references.count) reference\(page.references.count == 1 ? "" : "s") to check", style: WikiAppearance.text(16, bold: true)),
                               Chrome.vgap(6), Button(onPressed: { [weak self] in
                                   guard let self else { return }
                                   self.setState {
                                       if expanded { self.referenceDetails.remove(page.slug) }
                                       else { self.referenceDetails.insert(page.slug) }
                                   }
                               }, child: Text(expanded ? "Hide references" : "Show references"))]
                    if expanded {
                        detail += [Chrome.vgap(8), Text("These references stay as text in text view. Review them in the document; you can still publish.", style: WikiAppearance.text(14, color: WikiAppearance.muted))]
                        for issue in page.references {
                            let target = String(issue.target.replacingOccurrences(of: "\n", with: " ").prefix(200))
                            detail += [Chrome.vgap(12), Text(issue.excerpt.isEmpty ? "Reference in an empty paragraph" : issue.excerpt, style: WikiAppearance.text(15, bold: true)),
                                       Chrome.vgap(4), Text(target, style: WikiAppearance.text(14, color: WikiAppearance.muted)),
                                       Chrome.vgap(4), Text(issue.kind.guidance, style: WikiAppearance.text(14))]
                            if let id = issue.paragraphID {
                                detail += [Chrome.vgap(6), Button(onPressed: { [weak self] in self?.panel.onPreview(page.slug, id) },
                                                                 child: Text("Show in document"))]
                            }
                        }
                    }
                }
                detail += [Chrome.vgap(8), Button(onPressed: busy ? nil : { [weak self] in self?.panel.onPreview(page.slug, nil) }, child: Text(page.heldDraft == nil ? "Preview page" : "Preview held draft"))]
                if let comparison = page.comparison, page.change != .unchanged || page.heldDraft != nil {
                    detail += [Chrome.vgap(8), Button(onPressed: { [weak self] in
                        self?.setState { self?.comparison = (comparison, page.slug) }
                    }, child: Text("Compare saved changes"))]
                }
                rows += [DecoratedBox(decoration: BoxDecoration(color: WikiAppearance.white, border: Border.all(color: WikiAppearance.line),
                            borderRadius: BorderRadius.circular(8)),
                            child: Padding(padding: EdgeInsets(all: 16), child: Column(crossAxisAlignment: .stretch, children: detail))), Chrome.vgap(10)]
            }
            if !review.removed.isEmpty {
                rows += [Chrome.vgap(14), Text("Removed from the next website version", style: WikiAppearance.text(22, bold: true)),
                         Chrome.vgap(8), Text("These pages and their downloads will leave the current website after deployment. Previous downloads, caches and repository history are not erased.", style: WikiAppearance.text(14, color: WikiAppearance.muted))]
                for page in review.removed {
                    rows += [Chrome.vgap(12), Text(page.title, style: WikiAppearance.text(17, bold: true)),
                             Chrome.vgap(4), Text(page.route, style: WikiAppearance.text(14)),
                             Chrome.vgap(8), Button(onPressed: { [weak self] in
                                 self?.setState { self?.comparison = (page.comparison, nil) }
                             }, child: Text("Review removed text"))]
                }
            }
            rows += [Chrome.vgap(24), FilledButton(onPressed: busy ? nil : panel.onContinue, child: Text("Continue to publish"))]
        }
        return ColoredBox(color: WikiAppearance.paper, child: Padding(padding: EdgeInsets(all: 28), child:
            SingleChildScrollView(child: Column(crossAxisAlignment: .stretch, children: rows))))
    }
}
#endif
