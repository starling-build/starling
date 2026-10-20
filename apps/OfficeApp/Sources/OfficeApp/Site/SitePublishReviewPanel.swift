// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Flutter

#if !os(WASI)
final class SitePublishReviewPanel: StatefulWidget {
    let store: LocalSiteStore
    let onBack: () -> Void
    let onContinue: () -> Void
    let onPreview: (String) -> Void
    init(store: LocalSiteStore, onBack: @escaping () -> Void, onContinue: @escaping () -> Void,
         onPreview: @escaping (String) -> Void) {
        self.store = store; self.onBack = onBack; self.onContinue = onContinue; self.onPreview = onPreview
        super.init()
    }
    override func createState() -> State<StatefulWidget> { _SitePublishReviewState() }
}

private final class _SitePublishReviewState: State<StatefulWidget> {
    private var panel: SitePublishReviewPanel { widget as! SitePublishReviewPanel }
    private var review: SitePublishReview?
    private var busy = false
    private var error: String?

    override func initState() { super.initState(); refresh() }

    private func refresh() {
        guard !busy else { return }
        let store = panel.store
        setState { busy = true; error = nil; review = nil }
        // Document decoding needs the same stack allowance as import/publish.
        let worker = Thread { [weak self] in
            let result = Result { try SitePublishReview.load(repo: store.repo, out: store.out, web: store.webStage) }
            DispatchQueue.main.async {
                guard let self, self.mounted else { return }
                self.setState {
                    self.busy = false
                    switch result {
                    case .success(let review): self.review = review
                    case .failure(let error): self.error = "\(error)"
                    }
                }
            }
        }
        worker.name = "Starling publication review"
        worker.stackSize = 8 * 1024 * 1024
        worker.start()
    }

    override func build(_ context: any BuildContext) -> Widget {
        var rows: [Widget] = [
            Text("Review your publication", style: WikiAppearance.text(30, bold: true)), Chrome.vgap(10),
            Text("Publishing shares every page listed here, not just the page you have open.", style: WikiAppearance.text()),
            Chrome.vgap(16), Wrap(spacing: 12, runSpacing: 8, children: [
                Button(onPressed: panel.onBack, child: Text("Back to preview")),
                Button(onPressed: busy ? nil : { [weak self] in self?.refresh() }, child: Text("Refresh review")),
                FilledButton(onPressed: busy || review == nil ? nil : panel.onContinue, child: Text("Continue to publish")),
            ]),
        ]
        if busy { rows += [Chrome.vgap(24), Text("Reading saved pages…", style: WikiAppearance.text())] }
        if let error { rows += [Chrome.vgap(24), Text("Could not review the publication", style: WikiAppearance.text(20, bold: true)),
                                Chrome.vgap(8), Text(error, style: WikiAppearance.text())] }
        if let review {
            rows += [Chrome.vgap(24), Text(review.title, style: WikiAppearance.text(23, bold: true)),
                     Chrome.vgap(8), Text(review.summary, style: WikiAppearance.text())]
            if review.compared {
                rows += [Chrome.vgap(6), Text("Compared with the last upload recorded on this device. This does not confirm what is live on the website.", style: WikiAppearance.text(14, color: WikiAppearance.muted))]
            }
            if review.settingsChanged {
                rows += [Chrome.vgap(10), Text("The publication title, address or navigation has also changed.", style: WikiAppearance.text(15, bold: true))]
            }
            rows += [Chrome.vgap(12), Text("Each included page has a web reading view and Word and PDF downloads. If your hosting repository is public, its source files and history are public too, including other files already committed there.", style: WikiAppearance.text(14, color: WikiAppearance.muted)),
                     Chrome.vgap(8), Text("This is a review of saved website pages. Refresh after changes made outside the app; publishing rebuilds the latest saved files.", style: WikiAppearance.text(14, color: WikiAppearance.muted)),
                     Chrome.vgap(20)]
            for page in review.pages {
                var detail: [Widget] = [
                    Text(page.title + (page.isHome ? " · Home" : ""), style: WikiAppearance.text(18, bold: true)),
                    Chrome.vgap(6), Text(page.change.rawValue + " · " + page.route, style: WikiAppearance.text(14, color: WikiAppearance.muted)),
                ]
                if let route = page.previousRoute {
                    detail += [Chrome.vgap(6), Text("Previously: " + route + " — existing links may need updating.", style: WikiAppearance.text(14))]
                }
                detail += [Chrome.vgap(8), Button(onPressed: { [weak self] in self?.panel.onPreview(page.slug) }, child: Text("Preview page"))]
                rows += [DecoratedBox(decoration: BoxDecoration(color: WikiAppearance.white, border: Border.all(color: WikiAppearance.line),
                            borderRadius: BorderRadius.circular(8)),
                            child: Padding(padding: EdgeInsets(all: 16), child: Column(crossAxisAlignment: .stretch, children: detail))), Chrome.vgap(10)]
            }
            if !review.removed.isEmpty {
                rows += [Chrome.vgap(14), Text("Removed from the next website version", style: WikiAppearance.text(22, bold: true)),
                         Chrome.vgap(8), Text("These pages and their downloads will leave the current website after deployment. Previous downloads, caches and repository history are not erased.", style: WikiAppearance.text(14, color: WikiAppearance.muted))]
                for page in review.removed {
                    rows += [Chrome.vgap(12), Text(page.title, style: WikiAppearance.text(17, bold: true)),
                             Chrome.vgap(4), Text(page.route, style: WikiAppearance.text(14))]
                }
            }
            rows += [Chrome.vgap(24), FilledButton(onPressed: panel.onContinue, child: Text("Continue to publish"))]
        }
        return ColoredBox(color: WikiAppearance.paper, child: Padding(padding: EdgeInsets(all: 28), child:
            SingleChildScrollView(child: Column(crossAxisAlignment: .stretch, children: rows))))
    }
}
#endif
