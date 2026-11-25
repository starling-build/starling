// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import OfficeText
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

/// The find (and replace) strip under the ribbon.
final class FindBar: StatelessWidget {
    let session: OfficeSession
    let query: TextEditingController
    let replacement: TextEditingController
    let showReplace: Bool
    let status: String
    let onNext: (Bool) -> Void          // backwards?
    let onReplace: () -> Void
    let onReplaceAll: () -> Void
    let onClose: () -> Void
    /// Opens the full Find and Replace dialog (match case, whole word, wildcards, Go To); nil hides the button.
    let onAdvanced: (() -> Void)?

    init(session: OfficeSession, query: TextEditingController, replacement: TextEditingController,
         showReplace: Bool, status: String, onNext: @escaping (Bool) -> Void,
         onReplace: @escaping () -> Void, onReplaceAll: @escaping () -> Void, onAdvanced: (() -> Void)? = nil,
         onClose: @escaping () -> Void) {
        self.onAdvanced = onAdvanced
        self.session = session
        self.query = query
        self.replacement = replacement
        self.showReplace = showReplace
        self.status = status
        self.onNext = onNext
        self.onReplace = onReplace
        self.onReplaceAll = onReplaceAll
        self.onClose = onClose
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        // Escape in a field unfocuses it and is consumed there, which left
        // the bar open with the keyboard going nowhere — a second Escape,
        // or Ctrl+H, did nothing. A field that loses focus to nothing (not
        // to the other field, nor to the document) closes the bar.
        let blurred: (Bool) -> Void = { [onClose] focused in
            if !focused, FocusManager.instance.focusedNode == nil { onClose() }
        }
        var items: [Widget] = [
            SizedBox(width: 60, height: nil, child: Text("Find", style: fluent.typography.body)),
            // The field takes the keyboard as the bar opens: ⌘F then type.
            SizedBox(width: 260 * SystemDisplay.current.chromeTextScale, height: OfficeAppearance.rowHeight(30), child: FluentTextBox(
                controller: query,
                placeholderText: session.kind == .presentation ? "Search presentation" : session.kind == .workbook ? "Search workbook" : "Search document",
                onSubmitted: { [onNext] _ in onNext(false) }, autofocus: true, onFocusChanged: blurred,
                tabGroup: "find", tabOrder: 0)),
            Chrome.gap(6),
            Chrome.icon(FluentSystemIcons.chevronUp, "Previous", fluent) { [onNext] in onNext(true) },
            Chrome.icon(FluentSystemIcons.chevronDown, "Next", fluent) { [onNext] in onNext(false) },
            Chrome.gap(12),
            Text(status, style: fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary)),
        ]
        if showReplace {
            items.append(Chrome.gap(24))
            items.append(SizedBox(width: 70, height: nil, child: Text("Replace", style: fluent.typography.body)))
            items.append(SizedBox(width: 220 * SystemDisplay.current.chromeTextScale, height: OfficeAppearance.rowHeight(30), child: FluentTextBox(
                controller: replacement, placeholderText: "Replace with",
                onSubmitted: { [onReplace] _ in onReplace() }, onFocusChanged: blurred,
                tabGroup: "find", tabOrder: 1)))
            items.append(Chrome.gap(6))
            items.append(Button(onPressed: onReplace, child: Text("Replace")))
            items.append(Chrome.gap(4))
            items.append(Button(onPressed: onReplaceAll, child: Text("Replace All")))
        }
        if let onAdvanced {
            items.append(Chrome.gap(12))
            items.append(Button(onPressed: onAdvanced, child: Text("Options...")))
        }
        items.append(Expanded(child: SizedBox(width: 0, height: 0, child: nil)))
        items.append(Chrome.icon(FluentSystemIcons.chromeClose, "Close (Esc)", fluent, action: onClose))
        return DecoratedBox(
            decoration: BoxDecoration(
                color: fluent.resources.layerFillColorDefault,
                border: Border(bottom: BorderSide(color: fluent.resources.dividerStrokeColorDefault, width: 1))),
            child: Padding(padding: EdgeInsets(left: 12, top: 6, right: 8, bottom: 6),
                           child: Row(crossAxisAlignment: .center, children: items)))
    }
}
