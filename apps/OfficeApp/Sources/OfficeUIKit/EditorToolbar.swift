// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The compact formatting bar over the on-screen keyboard: undo, redo, bold,
// italic, underline, lists, and a button that puts the keyboard away. It is a
// plain UIToolbar laid over the editor's view and parked on the keyboard's top
// edge; it shows only while a soft keyboard is docked (with a hardware
// keyboard the system's own small bar is all there is, and the editor's ribbon
// is the toolbar). The buttons call back into the editor through closures, so
// nothing here knows what a document is. A tap on a bar button never takes
// first responder, so the keyboard and the editor's caret stay where they are.

#if os(iOS)
import UIKit

/// One button, as the app publishes it: a snapshot of its state and what it does.
public struct OfficeToolbarButton {
    public var id: String
    public var title: String
    public var symbol: String
    public var isOn: Bool
    public var isEnabled: Bool
    public var action: () -> Void
    /// Choices under this button: it opens a menu of them instead of acting (Wrap, Fill, Sort...). `action` is unused then.
    public var children: [OfficeToolbarButton]
    public init(id: String, title: String, symbol: String, isOn: Bool, isEnabled: Bool, children: [OfficeToolbarButton] = [],
                action: @escaping () -> Void) {
        self.id = id; self.title = title; self.symbol = symbol
        self.isOn = isOn; self.isEnabled = isEnabled; self.children = children; self.action = action
    }
}

final class EditorToolbar: UIView {
    private let host: UIViewController
    private let bar = UIToolbar()
    private var buttons: [OfficeToolbarButton] = []
    private var shown: [(String, Bool, Bool)] = []
    /// The keyboard's frame in screen coordinates, as the system last said;
    /// nil with no keyboard up. Converted to the editor's view only when the
    /// bar lays out: the first notification can arrive while the editor is
    /// still being presented, before its view is in a window.
    private var keyboardFrame: CGRect?

    static let height: CGFloat = 44

    init(host: UIViewController) {
        self.host = host
        super.init(frame: .zero)
        bar.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(bar)
        isHidden = true
        autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardChanged(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardChanged(_:)),
            name: UIResponder.keyboardWillHideNotification, object: nil)
        // After the animation the editor's view has its final size and is in
        // its window: the frame from the first notification, which can come
        // mid-presentation, is only usable then.
        for name in [UIResponder.keyboardDidShowNotification, UIResponder.keyboardDidChangeFrameNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)), name: name, object: nil)
        }
        // Two windows share one keyboard: only the one holding the keys shows its bar.
        for name in [UIWindow.didBecomeKeyNotification, UIWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(keyWindowChanged), name: name, object: nil)
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }

    /// Put the bar into the editor's view, above everything the engine draws.
    func attach() {
        guard superview == nil, let view = host.viewIfLoaded else { return }
        view.addSubview(self)
        relayout()
    }

    /// New buttons, or nil when the editor in front has none. State changes
    /// arrive at every caret move, so an unchanged snapshot does nothing.
    func update(_ new: [OfficeToolbarButton]?) {
        buttons = new ?? []
        let snapshot = buttons.map { ($0.id + $0.children.map { $0.id + ($0.isOn ? "+" : "-") + ($0.isEnabled ? "+" : "-") }.joined(), $0.isOn, $0.isEnabled) }
        if snapshot.elementsEqual(shown, by: { $0 == $1 }) && builtWidth == availableWidth { relayout(); return }
        shown = snapshot
        rebuild()
        relayout()
    }

    /// The width the buttons have: the editor's, or `OFFICE_TOOLBAR_FORCE_WIDTH` (a test's stand-in for a narrow window).
    private var availableWidth: CGFloat { Self.forcedWidth ?? superview?.bounds.width ?? 0 }
    private var builtWidth: CGFloat = -1

    /// A button's width in the toolbar, and a gap's.
    private static let slot: CGFloat = 44, gap: CGFloat = 12

    /// How many of `buttons` fit in `width` as they are: every one that is not a context button, then as many context
    /// buttons as there is room for beside a "More" button that holds the rest. (Hide Keyboard always has its slot.)
    static func fitting(ids: [String], width: CGFloat) -> Int {
        func needed(_ count: Int, more: Bool) -> CGFloat {
            var w = CGFloat(count) * slot + slot  // + Hide Keyboard
            if count > 2 { w += gap }
            if count > 5 { w += gap }
            if ids.prefix(count).contains(where: { $0.hasPrefix("ctx-") }) { w += gap }
            return w + (more ? slot : 0)
        }
        if width <= 0 || needed(ids.count, more: false) <= width { return ids.count }
        let fixed = ids.firstIndex { $0.hasPrefix("ctx-") } ?? ids.count
        var keep = ids.count - 1
        while keep > fixed, needed(keep, more: true) > width { keep -= 1 }
        return keep
    }

    /// A button as a menu entry: an action, or a submenu when it has choices.
    private static func action(_ b: OfficeToolbarButton) -> UIMenuElement {
        if !b.children.isEmpty {
            return UIMenu(title: b.title, image: b.symbol.isEmpty ? nil : UIImage(systemName: b.symbol), children: b.children.map(action))
        }
        return UIAction(title: b.title, image: b.symbol.isEmpty ? nil : UIImage(systemName: b.symbol),
                        attributes: b.isEnabled ? [] : .disabled, state: b.isOn ? .on : .off) { _ in b.action() }
    }

    private func rebuild() {
        builtWidth = availableWidth
        let keep = Self.fitting(ids: buttons.map(\.id), width: builtWidth)
        func item(_ b: OfficeToolbarButton) -> UIBarButtonItem {
            // No symbol: the button is its title, a key that types that text. A button with choices opens a menu of them.
            let item: UIBarButtonItem
            if !b.children.isEmpty {
                let menu = UIMenu(title: b.title, children: b.children.map(Self.action))
                item = b.symbol.isEmpty ? UIBarButtonItem(title: b.title, menu: menu)
                                        : UIBarButtonItem(image: UIImage(systemName: b.symbol), menu: menu)
            } else {
                item = b.symbol.isEmpty
                    ? UIBarButtonItem(title: b.title, primaryAction: UIAction(title: b.title) { _ in b.action() })
                    : UIBarButtonItem(image: UIImage(systemName: b.symbol), primaryAction: UIAction(title: b.title) { _ in b.action() })
            }
            item.isEnabled = b.isEnabled
            item.isSelected = b.isOn
            item.accessibilityLabel = b.title
            return item
        }
        var items: [UIBarButtonItem] = []
        for (i, b) in buttons.prefix(keep).enumerated() {
            // A gap before the formatting group, the lists, and the buttons for what the selection is in.
            if i == 2 || i == 5 || (b.id.hasPrefix("ctx-") && !(i > 0 && buttons[i - 1].id.hasPrefix("ctx-"))) { items.append(UIBarButtonItem(systemItem: .fixedSpace)); items[items.count - 1].width = Self.gap }
            items.append(item(b))
        }
        // The buttons that did not fit, in a menu: a window narrower than the bar (Split View, a small iPad) loses none.
        if keep < buttons.count {
            let rest = buttons[keep...].map(Self.action)
            let more = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), menu: UIMenu(children: rest))
            more.accessibilityLabel = "More"
            items.append(more)
        }
        items.append(UIBarButtonItem(systemItem: .flexibleSpace))
        items.append(UIBarButtonItem(image: UIImage(systemName: "keyboard.chevron.compact.down"), primaryAction: UIAction(title: "Hide Keyboard") { _ in
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }))
        bar.setItems(buttons.isEmpty ? [] : items, animated: false)
        if Self.debug { fputs("[toolbar] width \(builtWidth): \(keep) of \(buttons.count) buttons shown\(keep < buttons.count ? ", \(buttons.count - keep) in More" : "")\n", stderr) }
    }

    @objc private func keyWindowChanged() { relayout() }

    @objc private func keyboardChanged(_ note: Notification) {
        if note.name == UIResponder.keyboardWillHideNotification {
            keyboardFrame = nil
        } else if let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            keyboardFrame = end
        }
        relayout()
    }

    private static let debug = ProcessInfo.processInfo.environment["OFFICE_TOOLBAR_DEBUG"] != nil
    /// OFFICE_TOOLBAR_FORCE_WIDTH=W: the bar is always shown, W points wide, near the bottom of the editor. A hardware
    /// keyboard hides the bar, so this is how a test sees it, and at the width of a narrow window.
    private static let forcedWidth: CGFloat? = ProcessInfo.processInfo.environment["OFFICE_TOOLBAR_FORCE_WIDTH"]
        .flatMap { Double($0) }.map { CGFloat($0) }

    private func relayout() {
        if Self.debug {
            fputs("[toolbar] relayout super=\(superview != nil) window=\(superview?.window != nil) buttons=\(buttons.count) kb=\(String(describing: keyboardFrame))\n", stderr)
        }
        guard let view = superview else { return }
        if builtWidth != availableWidth, !buttons.isEmpty { rebuild() }
        if let w = Self.forcedWidth {
            isHidden = buttons.isEmpty
            frame = CGRect(x: 0, y: view.bounds.height - Self.height - 60, width: w, height: Self.height)
            view.bringSubviewToFront(self)
            return
        }
        // A docked soft keyboard is tall; a hardware keyboard's floating
        // assistant bar is a strip, and gets no toolbar of ours.
        var keyboardTop: CGFloat?
        if let end = keyboardFrame, let window = view.window {
            // The system gives the keyboard's frame in the SCREEN's space, which is the window's
            // only when the window fills the screen: a Slide Over or Split View window is offset.
            let local = view.convert(end, from: window.screen.coordinateSpace)
            // Only a DOCKED keyboard (its bottom edge is the screen's) gets the bar: a floating or undocked one hovers
            // mid-screen, and the bar full width above it would sit over the page with nothing under it.
            let docked = end.maxY >= window.screen.bounds.height - 0.5
            if docked, local.height > 150, local.minY < view.bounds.height { keyboardTop = local.minY }
        }
        let holdsKeys = view.window?.isKeyWindow ?? true
        isHidden = keyboardTop == nil || buttons.isEmpty || !holdsKeys
        guard let top = keyboardTop else { return }
        frame = CGRect(x: 0, y: top - Self.height, width: view.bounds.width, height: Self.height)
        view.bringSubviewToFront(self)
    }
}
#endif
