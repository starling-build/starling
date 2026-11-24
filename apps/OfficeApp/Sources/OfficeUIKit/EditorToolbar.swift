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
    public init(id: String, title: String, symbol: String, isOn: Bool, isEnabled: Bool, action: @escaping () -> Void) {
        self.id = id; self.title = title; self.symbol = symbol
        self.isOn = isOn; self.isEnabled = isEnabled; self.action = action
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
        let snapshot = buttons.map { ($0.id, $0.isOn, $0.isEnabled) }
        if snapshot.elementsEqual(shown, by: { $0 == $1 }) { relayout(); return }
        shown = snapshot
        var items: [UIBarButtonItem] = []
        for (i, b) in buttons.enumerated() {
            if i == 2 || i == 5 { items.append(UIBarButtonItem(systemItem: .fixedSpace)); items[items.count - 1].width = 12 }
            let item = UIBarButtonItem(image: UIImage(systemName: b.symbol), primaryAction: UIAction(title: b.title) { _ in b.action() })
            item.isEnabled = b.isEnabled
            item.isSelected = b.isOn
            item.accessibilityLabel = b.title
            items.append(item)
        }
        items.append(UIBarButtonItem(systemItem: .flexibleSpace))
        items.append(UIBarButtonItem(image: UIImage(systemName: "keyboard.chevron.compact.down"), primaryAction: UIAction(title: "Hide Keyboard") { _ in
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }))
        bar.setItems(buttons.isEmpty ? [] : items, animated: false)
        relayout()
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

    private func relayout() {
        if Self.debug {
            fputs("[toolbar] relayout super=\(superview != nil) window=\(superview?.window != nil) buttons=\(buttons.count) kb=\(String(describing: keyboardFrame))\n", stderr)
        }
        guard let view = superview else { return }
        // A docked soft keyboard is tall; a hardware keyboard's floating
        // assistant bar is a strip, and gets no toolbar of ours.
        var keyboardTop: CGFloat?
        if let end = keyboardFrame, let window = view.window {
            // The system gives the keyboard's frame in the SCREEN's space, which is the window's
            // only when the window fills the screen: a Slide Over or Split View window is offset.
            let local = view.convert(end, from: window.screen.coordinateSpace)
            if local.height > 150, local.minY < view.bounds.height { keyboardTop = local.minY }
        }
        let holdsKeys = view.window?.isKeyWindow ?? true
        isHidden = keyboardTop == nil || buttons.isEmpty || !holdsKeys
        guard let top = keyboardTop else { return }
        frame = CGRect(x: 0, y: top - Self.height, width: view.bounds.width, height: Self.height)
        view.bringSubviewToFront(self)
    }
}
#endif
