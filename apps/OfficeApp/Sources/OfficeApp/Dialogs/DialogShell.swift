// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The shell every Office dialog sits in (U-shared): a dimmed, click-blocking
// window behind a card with a title, an optional tab strip, the page of the
// selected tab, and OK / Cancel. Enter is OK and Esc is Cancel, as in Office.
// Focus order is the order of the controls in the page (tab strip, page,
// then the buttons).
//
// A dialog is `DialogShell(title:, tabs:, onOK:, onCancel:)`; with one tab
// there is no strip. The caller keeps the dialog's values and builds the
// pages from them; the shell only owns which tab is showing.

import Flutter
import FlutterSwiftBridge

struct DialogTab {
    let title: String
    let page: Widget
}

final class DialogShell: StatefulWidget {
    let title: String
    let tabs: [DialogTab]
    let okLabel: String
    let cancelLabel: String
    /// False greys OK out and makes Enter do nothing (a value that cannot apply yet).
    let okEnabled: Bool
    let width: Double
    let onOK: () -> Void
    let onCancel: () -> Void

    init(title: String, tabs: [DialogTab], okLabel: String = "OK", cancelLabel: String = "Cancel",
         okEnabled: Bool = true, width: Double = 440,
         onOK: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.title = title
        self.tabs = tabs
        self.okLabel = okLabel
        self.cancelLabel = cancelLabel
        self.okEnabled = okEnabled
        self.width = width
        self.onOK = onOK
        self.onCancel = onCancel
        super.init()
    }

    /// A one-page dialog.
    convenience init(title: String, page: Widget, okLabel: String = "OK", cancelLabel: String = "Cancel",
                     okEnabled: Bool = true, width: Double = 440,
                     onOK: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.init(title: title, tabs: [DialogTab(title: "", page: page)], okLabel: okLabel, cancelLabel: cancelLabel,
                  okEnabled: okEnabled, width: width, onOK: onOK, onCancel: onCancel)
    }

    override func createState() -> State<StatefulWidget> { DialogShellState() }
}

final class DialogShellState: State<StatefulWidget> {
    private var _w: DialogShell { widget as! DialogShell }
    /// The tab showing.
    private(set) var selectedTab = 0
    private var _keys: Int?

    override func initState() {
        super.initState()
        // Ahead of the focused field, so Enter and Esc work wherever focus is.
        _keys = FocusManager.instance.addKeyInterceptor { [weak self] key in
            guard let self, key.type == .down else { return false }
            switch key.logical {
            case 0x1_0000_000D, 0xFF0D, 0xFF8D:
                guard self._w.okEnabled else { return true }
                self._w.onOK()
                return true
            case 0x1_0000_001B, 0xFF1B:
                self._w.onCancel()
                return true
            default:
                return false
            }
        }
    }

    override func dispose() {
        if let k = _keys { FocusManager.instance.removeKeyInterceptor(k) }
        _keys = nil
        super.dispose()
    }

    func select(_ index: Int) { setState { self.selectedTab = index } }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let tabs = _w.tabs
        let index = min(selectedTab, max(0, tabs.count - 1))
        var children: [Widget] = [Text(_w.title, style: fluent.typography.subtitle), SizedBox(width: nil, height: 12, child: nil)]
        if tabs.count > 1 {
            children.append(Row(children: tabs.enumerated().map { i, tab in
                GestureDetector(onTap: { [weak self] in self?.select(i) }, behavior: .opaque, child: Padding(
                    padding: EdgeInsets(left: 0, top: 4, right: 18, bottom: 6),
                    child: Text(tab.title, style: i == index ? fluent.typography.bodyStrong : fluent.typography.body)))
            }))
            children.append(SizedBox(width: nil, height: 12, child: nil))
        }
        if !tabs.isEmpty { children.append(tabs[index].page) }
        children.append(SizedBox(width: nil, height: 20, child: nil))
        children.append(Row(mainAxisAlignment: .end, children: [
            FilledButton(onPressed: _w.okEnabled ? { [weak self] in self?._w.onOK() } : nil, child: Text(_w.okLabel)),
            SizedBox(width: 8, height: nil, child: nil),
            Button(onPressed: { [weak self] in self?._w.onCancel() }, child: Text(_w.cancelLabel)),
        ]))
        let card = Column(mainAxisSize: .min, crossAxisAlignment: .start, children: children)
        // A modal sheet: the dimmed window behind it takes no clicks.
        return Stack(children: [
            Positioned(left: 0, top: 0, right: 0, bottom: 0, child: Listener(
                behavior: .opaque,
                child: ColoredBox(color: Color(0x33000000), child: SizedBox(expand: ())))),
            Positioned(left: 0, top: 0, right: 0, bottom: 0, child: Center(child: SizedBox(width: _w.width, height: nil, child: DecoratedBox(
                decoration: BoxDecoration(color: OfficeAppearance.surface(fluent),
                                          border: Border.all(color: fluent.resources.controlStrokeColorDefault, width: 1),
                                          borderRadius: BorderRadius.circular(8),
                                          boxShadow: [BoxShadow(color: Color(0x40000000), offset: Offset(0, 8), blurRadius: 24)]),
                child: Padding(padding: EdgeInsets(all: 24), child: card))))),
        ])
    }
}
