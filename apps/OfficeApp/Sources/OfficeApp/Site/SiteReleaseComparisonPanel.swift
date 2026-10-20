// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import Foundation

#if !os(WASI)
/// Displays the immutable snapshot captured by publication review, with bounded
/// widget counts even for a whole imported manuscript.
final class SiteReleaseComparisonPanel: StatefulWidget {
    let comparison: SiteReleaseComparison
    let onBack: () -> Void
    let onPreview: ((UInt32?) -> Void)?
    init(comparison: SiteReleaseComparison, onBack: @escaping () -> Void,
         onPreview: ((UInt32?) -> Void)?) {
        self.comparison = comparison
        self.onBack = onBack
        self.onPreview = onPreview
        super.init()
    }
    override func createState() -> State<StatefulWidget> { _SiteReleaseComparisonState() }
}

private final class _SiteReleaseComparisonState: State<StatefulWidget> {
    private var panel: SiteReleaseComparisonPanel { widget as! SiteReleaseComparisonPanel }
    private var batch = 0
    private let batchSize = 10
    private let scroll = ScrollController()
    override func dispose() { scroll.dispose(); super.dispose() }

    private func move(_ delta: Int) {
        let last = max(0, (panel.comparison.passages.count - 1) / batchSize)
        let next = min(last, max(0, batch + delta))
        guard next != batch else { return }
        setState { batch = next }
        if scroll.hasClients { scroll.jumpTo(0) }
    }

    override func build(_ context: any BuildContext) -> Widget {
        let comparison = panel.comparison
        var actions: [Widget] = [Button(onPressed: panel.onBack, child: Text("Back to review"))]
        if let preview = panel.onPreview {
            actions.append(Button(onPressed: { preview(nil) }, child: Text("Preview saved draft")))
        }
        var rows: [Widget] = [
            Text("Compare saved changes", style: WikiAppearance.text(30, bold: true)), Chrome.vgap(10),
            Text(comparison.currentTitle ?? comparison.previousTitle ?? "Document", style: WikiAppearance.text(23, bold: true)),
            Chrome.vgap(12), Wrap(spacing: 12, runSpacing: 8, children: actions), Chrome.vgap(16),
            Text("Last uploaded version → Saved draft", style: WikiAppearance.text(18, bold: true)), Chrome.vgap(8),
            Text("This comparison uses the saved files captured when you opened or refreshed review. Saving does not publish your edits. The upload record does not confirm what is live on the website.",
                 style: WikiAppearance.text(14, color: WikiAppearance.muted)), Chrome.vgap(12),
            Text(comparison.summary, style: WikiAppearance.text()),
        ]
        if comparison.previousTitle == nil {
            rows += notice("This page was not included in the last recorded upload.")
        } else if comparison.currentTitle == nil {
            rows += notice("This page will be removed from the next website version. Its last uploaded text is shown below.")
        } else if comparison.previousTitle != comparison.currentTitle {
            rows += notice("Page renamed: \(comparison.previousTitle!) → \(comparison.currentTitle!)")
        }
        if comparison.orderChanged {
            rows += notice("The order of existing paragraphs changed. Preview the saved draft to check their new order.")
        }
        if comparison.pageSetupChanged { rows += notice("Page layout settings changed. Check the page preview before publishing.") }
        if comparison.documentDetailsChanged { rows += notice("Document-level content or settings changed. Check the full document preview as well as the passages below.") }
        rows += notice("Paragraph details can include formatting, links, bookmarks or embedded content. This view shows paragraph text, not a visual layout diff. Unmatched passages appear as additions and removals.")
        if comparison.passages.isEmpty {
            rows += [Chrome.vgap(20), Text("No paragraph changes found.", style: WikiAppearance.text(20, bold: true)),
                     Chrome.vgap(8), Text("Page titles, addresses, publication settings or saved document data may still differ. Check the publication review and document preview.", style: WikiAppearance.text())]
        } else {
            let start = batch * batchSize
            let end = min(start + batchSize, comparison.passages.count)
            rows += [Chrome.vgap(20), Text("Changes \(start + 1)–\(end) of \(comparison.passages.count)", style: WikiAppearance.text(18, bold: true))]
            for passage in comparison.passages[start..<end] {
                var fields: [Widget] = [Text(passage.kind.rawValue, style: WikiAppearance.text(18, bold: true))]
                if let before = passage.before {
                    fields += textBlock("Last upload · paragraph \(passage.oldNumber!)", before)
                }
                if let after = passage.after {
                    fields += textBlock("Saved draft · paragraph \(passage.newNumber!)", after)
                }
                if passage.kind == .details {
                    fields += notice("The text is unchanged; other paragraph details differ. Inspect this passage in the document preview.")
                }
                if let id = passage.paragraphID, let preview = panel.onPreview {
                    fields += [Chrome.vgap(10), Button(onPressed: { preview(id) }, child: Text("Show in saved draft"))]
                }
                rows += [Chrome.vgap(12), DecoratedBox(
                    decoration: BoxDecoration(color: WikiAppearance.white, border: Border.all(color: WikiAppearance.line),
                                              borderRadius: BorderRadius.circular(8)),
                    child: Padding(padding: EdgeInsets(all: 16), child: Column(crossAxisAlignment: .stretch, children: fields)))]
            }
            rows += [Chrome.vgap(18), Wrap(spacing: 12, runSpacing: 8, children: [
                Button(onPressed: batch == 0 ? nil : { [weak self] in self?.move(-1) }, child: Text("Previous changes")),
                Button(onPressed: end == comparison.passages.count ? nil : { [weak self] in self?.move(1) }, child: Text("Next changes")),
            ])]
        }
        return ColoredBox(color: WikiAppearance.paper, child: Padding(padding: EdgeInsets(all: 28), child:
            SingleChildScrollView(controller: scroll, child: Column(crossAxisAlignment: .stretch, children: rows))))
    }

    private func notice(_ text: String) -> [Widget] {
        [Chrome.vgap(10), Text(text, style: WikiAppearance.text(14, color: WikiAppearance.muted))]
    }

    private func textBlock(_ label: String, _ value: String) -> [Widget] {
        [Chrome.vgap(12), Text(label, style: WikiAppearance.text(14, bold: true)), Chrome.vgap(6),
         Text(value.isEmpty ? "(Empty paragraph)" : value, style: WikiAppearance.text(16))]
    }
}
#endif
