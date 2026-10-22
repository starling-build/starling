// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Flutter

#if !os(WASI)
final class SiteReleasePlanPanel: StatefulWidget {
    let store: LocalSiteStore
    let onBack: () -> Void
    let onPreview: (String, UInt32?) -> Void
    init(store: LocalSiteStore, onBack: @escaping () -> Void, onPreview: @escaping (String, UInt32?) -> Void) {
        self.store = store; self.onBack = onBack; self.onPreview = onPreview; super.init()
    }
    override func createState() -> State<StatefulWidget> { _SiteReleasePlanState() }
}

private final class _SiteReleasePlanState: State<StatefulWidget> {
    private var panel: SiteReleasePlanPanel { widget as! SiteReleasePlanPanel }
    private var review: SitePublishReview?
    private var plan: SiteReleasePlan.Snapshot?
    private var busy = false
    private var notice: String?
    private var editing: SiteReleasePlan.Entry?
    private let date = TextEditingController()

    override func initState() { super.initState(); refresh() }
    override func dispose() { date.dispose(); super.dispose() }

    private func refresh() {
        guard !busy else { return }
        let store = panel.store
        setState { busy = true; notice = nil; editing = nil; review = nil; plan = nil }
        let worker = Thread { [weak self] in
            let result = Result { (try SitePublishReview.load(repo: store.repo, out: store.out, web: store.webStage),
                                   try SiteReleasePlan.load(repo: store.repo)) }
            DispatchQueue.main.async {
                guard let self, self.mounted else { return }
                self.setState {
                    self.busy = false
                    switch result {
                    case .success(let (review, plan)): self.review = review; self.plan = plan
                    case .failure(let error): self.notice = "\(error)"
                    }
                }
            }
        }
        worker.name = "Starling release plan"
        worker.stackSize = 8 * 1024 * 1024
        worker.start()
    }

    private func save(_ entry: SiteReleasePlan.Entry, value: String?) {
        guard !busy, let plan else { return }
        let repo = panel.store.repo
        setState { busy = true; notice = nil }
        let worker = Thread { [weak self] in
            let result = Result { try SiteReleasePlan.save(repo: repo, slug: entry.slug, date: value, expected: plan) }
            DispatchQueue.main.async {
                guard let self, self.mounted else { return }
                self.setState {
                    self.busy = false
                    switch result {
                    case .success(let updated):
                        self.plan = updated; self.editing = nil
                        self.notice = value == nil ? "Planned date cleared. Publication choices are unchanged."
                            : "Planned date saved on this device. Nothing was scheduled or published."
                    case .failure(let error): self.notice = "\(error)"
                    }
                }
            }
        }
        worker.name = "Starling save release date"
        worker.stackSize = 8 * 1024 * 1024
        worker.start()
    }

    override func build(_ context: any BuildContext) -> Widget {
        var rows: [Widget] = [
            Text("Release plan", style: WikiAppearance.text(30, bold: true)), Chrome.vgap(10),
            Text("Keep track of the next release for each chapter. Planned dates are reminders, not scheduled uploads.", style: WikiAppearance.text()),
            Chrome.vgap(12), Text("Publishing sends every included page, even if its planned date is in the future. Return to review to check what you will share.", style: WikiAppearance.text(15, bold: true)),
            Chrome.vgap(16), Wrap(spacing: 12, runSpacing: 8, children: [
                Button(onPressed: busy ? nil : panel.onBack, child: Text(editing == nil ? "Back to publication review" : "Back without saving date")),
                Button(onPressed: busy ? nil : { [weak self] in self?.refresh() }, child: Text(editing == nil ? "Refresh plan" : "Refresh and discard date edit")),
            ]),
        ]
        if busy { rows += [Chrome.vgap(16), Text("Reading or saving your local plan…", style: WikiAppearance.text())] }
        if let notice { rows += [Chrome.vgap(16), Text(notice, style: WikiAppearance.text(16, bold: true))] }
        if let editing {
            rows += [Chrome.vgap(24), Text(editing.title, style: WikiAppearance.text(23, bold: true)),
                     Chrome.vgap(12), Text("Planned release date · YYYY-MM-DD", style: WikiAppearance.text(17, bold: true)),
                     Chrome.vgap(8), SizedBox(height: 46, child: FluentTextBox(controller: date, placeholderText: "YYYY-MM-DD",
                         enabled: !busy, style: WikiAppearance.text(17), tabGroup: "release-plan", tabOrder: 0)),
                     Chrome.vgap(8), Text("A calendar day in your plan, with no automatic release time. Leave empty to clear it.", style: WikiAppearance.text(14, color: WikiAppearance.muted)),
                     Chrome.vgap(16), Wrap(spacing: 12, runSpacing: 8, children: [
                        FilledButton(onPressed: busy ? nil : { [weak self] in
                            guard let self else { return }
                            let value = self.date.text.trimmingWhitespace()
                            self.save(editing, value: value.isEmpty ? nil : value)
                        }, child: Text("Save planned date")),
                        Button(onPressed: busy ? nil : { [weak self] in self?.setState { self?.editing = nil; self?.notice = nil } }, child: Text("Cancel date edit")),
                     ])]
        } else if let review, let plan {
            rows += [Chrome.vgap(24), Text(review.title, style: WikiAppearance.text(23, bold: true)),
                     Chrome.vgap(8), Text("Destination: Your website" + (review.website.map { " · " + $0 } ?? " · address not configured"), style: WikiAppearance.text(16)),
                     Chrome.vgap(6), Text("Audience: Public website. This app does not restrict chapters to subscribers or paid tiers.", style: WikiAppearance.text(14)),
                     Chrome.vgap(6), Text("Live deployment is not checked here. Use Check live website in the preview after uploading.", style: WikiAppearance.text(14, color: WikiAppearance.muted)),
                     Chrome.vgap(6), Text("Dates stay on this device and remain until you change or clear them, including after an upload. Back up the whole publication folder, including its local history.", style: WikiAppearance.text(14, color: WikiAppearance.muted)),
                     Chrome.vgap(20)]
            for entry in SiteReleasePlan.entries(review: review, plan: plan) {
                let uploaded = entry.uploadedRevision.map { "Included in upload snapshot " + String($0.prefix(12)) }
                    ?? (review.compared ? "Absent from the last recorded upload" : "No matching upload snapshot available")
                var actions: [Widget] = []
                if entry.canPlan {
                    actions.append(Button(onPressed: busy ? nil : { [weak self] in
                        guard let self else { return }
                        self.date.text = entry.date ?? ""
                        self.setState { self.editing = entry; self.notice = nil }
                    }, child: Text(entry.date == nil ? "Plan a date" : "Change planned date")))
                }
                if entry.date != nil {
                    actions.append(Button(onPressed: busy ? nil : { [weak self] in self?.save(entry, value: nil) }, child: Text("Clear date")))
                }
                if entry.canPreview {
                    actions.append(Button(onPressed: busy ? nil : { [weak self] in self?.panel.onPreview(entry.slug, nil) }, child: Text("Preview saved chapter")))
                }
                rows += [DecoratedBox(decoration: BoxDecoration(color: WikiAppearance.white, border: Border.all(color: WikiAppearance.line),
                            borderRadius: BorderRadius.circular(8)), child: Padding(padding: EdgeInsets(all: 16), child:
                            Column(crossAxisAlignment: .stretch, children: [
                                Text(entry.title, style: WikiAppearance.text(19, bold: true)), Chrome.vgap(8),
                                Text(entry.date.map { "Planned: " + $0 } ?? "No planned date", style: WikiAppearance.text(16, bold: true)), Chrome.vgap(6),
                                Text(entry.nextPublication, style: WikiAppearance.text(15)), Chrome.vgap(6),
                                Text(uploaded, style: WikiAppearance.text(14, color: WikiAppearance.muted)), Chrome.vgap(12),
                                Wrap(spacing: 12, runSpacing: 8, children: actions),
                            ]))), Chrome.vgap(12)]
            }
        }
        return ColoredBox(color: WikiAppearance.paper, child: Padding(padding: EdgeInsets(all: 28), child:
            SingleChildScrollView(child: Column(crossAxisAlignment: .stretch, children: rows))))
    }
}
#endif
