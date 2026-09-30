// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The Phase 0 window: a formatting bar, the page, a status bar. The Office
// ribbon, Backstage and ruler replace this in Phase 1; what stays is the
// shape — a toolbar that reads a summary of the controller and rebuilds
// only when that summary changes, so typing never rebuilds chrome.

import Flutter
import FlutterSwiftBridge
import Foundation

final class OfficeShell: StatefulWidget {
    let initialPath: String?

    init(initialPath: String?) {
        self.initialPath = initialPath
        super.init()
    }

    override func createState() -> State<StatefulWidget> {
        return OfficeShellState()
    }
}

/// What the chrome shows about the selection. Compared before setState so
/// keystrokes that change nothing visible in the toolbar cost no rebuild.
private struct ToolbarSummary: Equatable {
    var bold = false
    var italic = false
    var underline = false
    var strikethrough = false
    var heading: Int? = nil
    var list: ListKind? = nil
    var alignment: ParagraphAlignment = .left
    var canUndo = false
    var canRedo = false
    var words = 0
    var paragraph = 0
    var paragraphs = 0
}

final class OfficeShellState: State<StatefulWidget> {
    let controller = RichDocumentController()
    let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
    private var _pageSetup = PageSetup.letter
    private var _pageInfo = (1, 1)
    private var _summary = ToolbarSummary()
    private var _zoom = 1.0

    override func initState() {
        super.initState()
        OfficeFonts.register()
        let env = ProcessInfo.processInfo.environment
        if let pages = env["OFFICE_DEMO_PAGES"].flatMap(Int.init), pages > 0 {
            controller.load(DemoDocument.make(pages: pages))
        } else if let path = (widget as! OfficeShell).initialPath,
                  let text = try? String(contentsOfFile: path, encoding: .utf8) {
            controller.load(RichDocument(plainText: text))
        }
        _summary = _summarize()
        controller.addListener { [weak self] in
            guard let self else { return }
            let s = self._summarize()
            if s != self._summary {
                self.setState { self._summary = s }
            }
        }
    }

    private func _summarize() -> ToolbarSummary {
        var s = ToolbarSummary()
        s.bold = controller.selectionAll { $0.bold }
        s.italic = controller.selectionAll { $0.italic }
        s.underline = controller.selectionAll { $0.underline }
        s.strikethrough = controller.selectionAll { $0.strikethrough }
        let ps = controller.currentParagraphStyle
        s.heading = ps.heading
        s.list = ps.list
        s.alignment = ps.alignment
        s.canUndo = controller.canUndo
        s.canRedo = controller.canRedo
        s.words = controller.document.wordCount
        s.paragraph = controller.caret.paragraph + 1
        s.paragraphs = controller.document.paragraphs.count
        return s
    }

    // MARK: - Build

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        return ColoredBox(
            color: fluent.scaffoldBackgroundColor,
            child: Column(
                crossAxisAlignment: .stretch,
                children: [
                    _toolbar(fluent),
                    Expanded(child: _pageArea(fluent)),
                    _statusBar(fluent),
                ]
            )
        )
    }

    private func _toolbar(_ fluent: FluentThemeData) -> Widget {
        let s = _summary
        let c = controller
        let items: [Widget] = [
            _button("Undo", enabled: s.canUndo) { c.undo() },
            _gap(),
            _button("Redo", enabled: s.canRedo) { c.redo() },
            _gap(16),
            _toggle("B", s.bold, Flutter.TextStyle(fontWeight: .bold)) { c.toggleBold() },
            _gap(),
            _toggle("I", s.italic, Flutter.TextStyle(fontStyle: .italic)) { c.toggleItalic() },
            _gap(),
            _toggle("U", s.underline, Flutter.TextStyle(decoration: .underline)) { c.toggleUnderline() },
            _gap(),
            _toggle("S", s.strikethrough, Flutter.TextStyle(decoration: .lineThrough)) { c.toggleStrikethrough() },
            _gap(16),
            _toggle("H1", s.heading == 1, nil) { c.setHeading(s.heading == 1 ? nil : 1) },
            _gap(),
            _toggle("H2", s.heading == 2, nil) { c.setHeading(s.heading == 2 ? nil : 2) },
            _gap(),
            _toggle("H3", s.heading == 3, nil) { c.setHeading(s.heading == 3 ? nil : 3) },
            _gap(16),
            _toggle("\u{2022}", s.list == .bullet, nil) { c.toggleList(.bullet) },
            _gap(),
            _toggle("1.", s.list == .numbered, nil) { c.toggleList(.numbered) },
            _gap(16),
            _toggle("L", s.alignment == .left, nil) { c.setAlignment(.left) },
            _gap(),
            _toggle("C", s.alignment == .center, nil) { c.setAlignment(.center) },
            _gap(),
            _toggle("R", s.alignment == .right, nil) { c.setAlignment(.right) },
            _gap(),
            _toggle("J", s.alignment == .justify, nil) { c.setAlignment(.justify) },
            _gap(16),
            _button("-", enabled: _zoom > 0.5) { [weak self] in self?._setZoom(-0.1) },
            _gap(),
            Text("\(Int((_zoom * 100).rounded()))%", style: fluent.typography.body),
            _gap(),
            _button("+", enabled: _zoom < 3) { [weak self] in self?._setZoom(0.1) },
        ]
        return Padding(
            padding: EdgeInsets(left: 12, top: 8, right: 12, bottom: 8),
            child: Row(crossAxisAlignment: .center, children: items)
        )
    }

    private func _setZoom(_ delta: Double) {
        setState { _zoom = max(0.5, min(3.0, (_zoom + delta).rounded(toPlaces: 1))) }
    }

    private func _gap(_ w: Double = 4) -> Widget { SizedBox(width: w) }

    private func _button(_ label: String, enabled: Bool, _ action: @escaping () -> Void) -> Widget {
        Button(onPressed: enabled ? action : nil, child: Text(label))
    }

    private func _toggle(_ label: String, _ on: Bool, _ style: Flutter.TextStyle?, _ action: @escaping () -> Void) -> Widget {
        ToggleButton(checked: on, onChanged: { _ in action() },
                     child: Text(label, style: style))
    }

    private func _pageArea(_ fluent: FluentThemeData) -> Widget {
        let dark = fluent.brightness == .dark
        let backdrop = dark ? Color(0xFF202020) : Color(0xFFE6E6E6)
        let page = dark ? Color(0xFF2B2B2B) : Color(0xFFFFFFFF)
        let editorTheme = theme
        editorTheme.textColor = dark ? Color(0xFFF0F0F0) : Color(0xFF1B1B1B)
        editorTheme.caretColor = editorTheme.textColor
        return RichEditable(
            controller: controller, theme: editorTheme,
            padding: EdgeInsets(left: 24, top: 24, right: 24, bottom: 24),
            backgroundColor: backdrop, zoom: _zoom,
            pageSetup: _pageSetup, pageColor: page,
            onPageInfo: { [weak self] page, count in
                guard let self, self._pageInfo != (page, count) else { return }
                self.setState { self._pageInfo = (page, count) }
            }
        )
    }

    private func _statusBar(_ fluent: FluentThemeData) -> Widget {
        let s = _summary
        return Padding(
            padding: EdgeInsets(left: 12, top: 4, right: 12, bottom: 4),
            child: Row(children: [
                Text("Page \(_pageInfo.0) of \(_pageInfo.1)", style: fluent.typography.caption),
                _gap(24),
                Text("Paragraph \(s.paragraph) of \(s.paragraphs)", style: fluent.typography.caption),
                _gap(24),
                Text("\(s.words) words", style: fluent.typography.caption),            ])
        )
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let f = pow(10.0, Double(places))
        return (self * f).rounded() / f
    }
}
