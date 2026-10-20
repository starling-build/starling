// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Flutter

final class SitePublicationAbout: StatelessWidget {
    let title: String
    let details: SitePublicationDetails
    let onClose: () -> Void
    init(title: String, details: SitePublicationDetails, onClose: @escaping () -> Void) {
        self.title = title; self.details = details; self.onClose = onClose
        super.init()
    }
    override func build(_ context: any BuildContext) -> Widget {
        var rows: [Widget] = [Text("About this publication", style: WikiAppearance.text(30, bold: true)),
                              Chrome.vgap(12), Text(title, style: WikiAppearance.text(23, bold: true)),
                              Chrome.vgap(18), Button(onPressed: onClose, child: Text("Back to reading"))]
        for (label, value) in [("By", details.byline), ("Description", details.summary), ("Edition", details.edition),
                               ("Language", details.language), ("Rights", details.rights)] {
            if let value, !value.isEmpty {
                rows += [Chrome.vgap(22), Text(label, style: WikiAppearance.text(15, bold: true)), Chrome.vgap(6),
                         Text(value, style: WikiAppearance.text(18))]
            }
        }
        return ColoredBox(color: WikiAppearance.paper, child: Padding(padding: EdgeInsets(all: 28), child:
            SingleChildScrollView(child: Column(crossAxisAlignment: .stretch, children: rows))))
    }
}

#if !os(WASI)
final class SitePublicationDetailsPanel: StatefulWidget {
    let repo: String
    let onClose: () -> Void
    init(repo: String, onClose: @escaping () -> Void) {
        self.repo = repo; self.onClose = onClose; super.init()
    }
    override func createState() -> State<StatefulWidget> { _SitePublicationDetailsState() }
}

private final class _SitePublicationDetailsState: State<StatefulWidget> {
    private var panel: SitePublicationDetailsPanel { widget as! SitePublicationDetailsPanel }
    private var snapshot: SitePublicationDetailsStore.Snapshot?
    private let fields = (0..<5).map { _ in TextEditingController() }
    private var notice: String?
    private var values: SitePublicationDetails {
        SitePublicationDetails(byline: fields[0].text, summary: fields[1].text, edition: fields[2].text,
                               language: fields[3].text, rights: fields[4].text)
    }
    private var edited: Bool {
        guard let snapshot else { return false }
        return (try? values.validated()) != (snapshot.config.details ?? SitePublicationDetails())
    }

    override func initState() {
        super.initState()
        do {
            let saved = try SitePublicationDetailsStore.load(repo: panel.repo)
            snapshot = saved
            let details = saved.config.details ?? SitePublicationDetails()
            for (i, value) in [details.byline, details.summary, details.edition, details.language, details.rights].enumerated() {
                fields[i].text = value ?? ""
            }
        } catch { notice = "\(error)" }
    }

    override func dispose() { fields.forEach { $0.dispose() }; super.dispose() }

    private func save() {
        guard let snapshot else { return }
        do {
            try SitePublicationDetailsStore.save(values, repo: panel.repo, expected: snapshot)
            let saved = try SitePublicationDetailsStore.load(repo: panel.repo)
            setState { self.snapshot = saved; notice = "Details saved locally. Publish to show them on the website." }
        } catch { setState { notice = "\(error)" } }
    }

    override func build(_ context: any BuildContext) -> Widget {
        var rows: [Widget] = [
            Text("Publication details", style: WikiAppearance.text(30, bold: true)), Chrome.vgap(10),
            Text("Tell readers who made this publication and which edition they are reading. These optional details appear around your writing; document formatting stays the same.", style: WikiAppearance.text()),
            Chrome.vgap(16), Button(onPressed: panel.onClose, child: Text(edited ? "Back without saving changes" : "Back to publication")),
        ]
        if let notice { rows += [Chrome.vgap(16), Text(notice, style: WikiAppearance.text(15, bold: true))] }
        let labels = ["Byline / publisher", "Short description", "Edition label", "Language code", "Rights statement"]
        let examples = ["Jane Doe · Example Press", "A practical guide to writing and publishing", "Second edition · October 2026", "en or en-GB", "Your copyright or licensing statement"]
        for i in fields.indices {
            rows += [Chrome.vgap(20), Text(labels[i], style: WikiAppearance.text(16, bold: true)), Chrome.vgap(8),
                     SizedBox(height: 46, child:
                        FluentTextBox(controller: fields[i], placeholderText: examples[i], onChanged: { [weak self] _ in self?.setState {} },
                                      enabled: snapshot != nil, style: WikiAppearance.text(17), tabGroup: "publication-details", tabOrder: i))]
        }
        rows += [Chrome.vgap(18), Text("An edition label identifies this publication; it does not archive an older version. Leaving a field empty removes it. The byline is separate from your Git author settings.", style: WikiAppearance.text(14, color: WikiAppearance.muted)),
                 Chrome.vgap(18), FilledButton(onPressed: snapshot == nil ? nil : { [weak self] in self?.save() }, child: Text("Save details"))]
        return ColoredBox(color: WikiAppearance.paper, child: Padding(padding: EdgeInsets(all: 28), child:
            SingleChildScrollView(child: Column(crossAxisAlignment: .stretch, children: rows))))
    }
}
#endif
