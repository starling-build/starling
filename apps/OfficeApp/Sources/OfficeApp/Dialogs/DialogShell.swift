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
//
// On an iPad the soft keyboard must not cover OK: the card sits above the
// keyboard (the view's bottom inset), its page scrolls when the card is taller
// than what is left, and the title and the buttons stay put. Buttons are 44 pt
// tall on a touch device (Apple's minimum target), and the card is never wider
// than the view.

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
    /// An optional third button between OK and Cancel (Yes / No / Cancel).
    var middle: (label: String, action: () -> Void)?
    /// The middle button shows but greyed (Paste Special's Paste Link for a choice it cannot link), so the row never moves.
    var middleEnabled = true
    /// The tab showing when the dialog opens (Borders > More Borders… opens Format Cells on Border).
    var startTab = 0

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

/// The view this context is drawn in: its render tree's root, else the only view there is.
private func _hostView(_ context: any BuildContext) -> FlutterView? {
    var node: RenderObject? = context.findRenderObject()
    while let n = node {
        if let root = n as? RenderView { return root.flutterView }
        node = n.parent
    }
    return PlatformDispatcher.instance.views.first
}

final class DialogShellState: State<StatefulWidget> {
    private var _w: DialogShell { widget as! DialogShell }
    /// The tab showing.
    private(set) var selectedTab = 0
    private var _keys: Int?

    override func initState() {
        super.initState()
        selectedTab = max(0, min(_w.startTab, _w.tabs.count - 1))
        ScreenReader.announce("\(_w.title) dialog", priority: .assertive)
        // Ahead of the focused field, so Enter and Esc work wherever focus is.
        _keys = FocusManager.instance.addKeyInterceptor { [weak self] key in
            if KeyboardTraversal.shared.handle(key) { return true }
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

    /// EditorToolbar.height, which this module cannot see.
    private static let softKeyboardBar = 44.0

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let tabs = _w.tabs
        let index = min(selectedTab, max(0, tabs.count - 1))
        // The room there is: the view less the soft keyboard (nothing is known before the first frame).
        var keyboard = 0.0, viewWidth = Double.infinity
        if let view = _hostView(context), view.devicePixelRatio > 0 {
            keyboard = view.viewInsets.bottom / view.devicePixelRatio
            #if os(iOS)
            // The bar of buttons over the soft keyboard (EditorToolbar, 44 pt) is a UIKit view the keyboard's inset
            // does not count: without this it covers the sheet's OK and Cancel.
            if keyboard > 150 { keyboard += Self.softKeyboardBar }   // (EditorToolbar shows only for a docked keyboard: over 150 pt)
            #endif
            viewWidth = view.physicalSize.width / view.devicePixelRatio
        }
        #if os(iOS)
        let touch = true
        #else
        let touch = false
        #endif
        func button(_ b: Widget) -> Widget { touch ? SizedBox(width: nil, height: 44, child: b) : b }
        var children: [Widget] = [Semantics(label: _w.title, header: true, container: true, excludeSemantics: true, child: Text(_w.title, style: fluent.typography.subtitle)), SizedBox(width: nil, height: 12, child: nil)]
        if tabs.count > 1 {
            children.append(Row(children: tabs.enumerated().map { i, tab in
                Padding(padding: EdgeInsets(left: 0, top: 0, right: 8, bottom: 4), child: FlatButton(
                    child: Padding(padding: EdgeInsets(left: 8, top: 0, right: 8, bottom: 0),
                                   child: Text(tab.title, style: i == index ? fluent.typography.bodyStrong : fluent.typography.body)),
                    checked: i == index, width: nil, height: 28, action: { [weak self] in self?.select(i) }))
            }))
            children.append(SizedBox(width: nil, height: 12, child: nil))
        }
        // The page scrolls inside what is left, so the buttons below it are never pushed off by the keyboard.
        if !tabs.isEmpty { children.append(Flexible(fit: .loose, child: SingleChildScrollView(child: tabs[index].page))) }
        children.append(SizedBox(width: nil, height: 20, child: nil))
        children.append(Row(mainAxisAlignment: .end, children: [
            button(FilledButton(onPressed: _w.okEnabled ? { [weak self] in self?._w.onOK() } : nil, child: Text(_w.okLabel))),
            SizedBox(width: 8, height: nil, child: nil),
        ] + (_w.middle.map { m in [button(Button(key: ValueKey("dialog-middle"), onPressed: _w.middleEnabled ? m.action : nil, child: Text(m.label))),
                                   SizedBox(width: 8, height: nil, child: nil) as Widget] } ?? []) + [
            button(Button(onPressed: { [weak self] in self?._w.onCancel() }, child: Text(_w.cancelLabel))),
        ]))
        let card = Column(mainAxisSize: .min, crossAxisAlignment: .start, children: children)
        // On a touch device the dialog is a sheet: it rises from the bottom edge, flush with the soft keyboard (or the
        // screen), with rounded top corners and no margin below; elsewhere it is a card in the middle of the window.
        let radius = touch ? BorderRadius.vertical(top: Radius(circular: 14), bottom: Radius.zero) : BorderRadius.circular(8)
        let panel = SizedBox(width: min(_w.width, viewWidth - 32), height: nil, child: DecoratedBox(
            decoration: BoxDecoration(color: OfficeAppearance.surface(fluent),
                                      border: Border.all(color: fluent.resources.controlStrokeColorDefault, width: 1),
                                      borderRadius: radius,
                                      boxShadow: [BoxShadow(color: Color(0x40000000), offset: Offset(0, touch ? -4 : 8), blurRadius: 24)]),
            child: Padding(padding: EdgeInsets(all: 24), child: KeyboardRegion(name: "dialog", modal: true, child: card))))
        // A modal sheet: the dimmed window behind it takes no clicks.
        return Stack(children: [
            Positioned(left: 0, top: 0, right: 0, bottom: 0, child: Listener(
                behavior: .opaque,
                child: ColoredBox(color: Color(0x33000000), child: SizedBox(expand: ())))),
            Positioned(left: 0, top: 0, right: 0, bottom: 0, child: Padding(
                padding: touch ? EdgeInsets(left: 16, top: 24, right: 16, bottom: keyboard)
                               : EdgeInsets(left: 16, top: 24, right: 16, bottom: 24 + keyboard),
                child: touch ? Align(alignment: Alignment.bottomCenter, child: panel) : Center(child: panel))),
        ])
    }
}
