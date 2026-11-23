// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The edit menu over a text selection or a caret on the iPad: the system's
// UIEditMenuInteraction, laid on the editor's view. The editor says where the
// selection is and which actions apply (Cut, Copy, Paste, Select All...); this
// shows them as the system menu, with Look Up and Share added when text is
// selected. Translate is the system's own and has no public entry point, so it
// is not offered here.

#if os(iOS)
import UIKit

/// One entry of the menu, as the editor publishes it.
public struct OfficeEditMenuItem {
    public var title: String
    public var symbol: String
    public var isEnabled: Bool
    public var action: () -> Void
    public init(title: String, symbol: String, isEnabled: Bool, action: @escaping () -> Void) {
        self.title = title; self.symbol = symbol; self.isEnabled = isEnabled; self.action = action
    }
}

final class EditMenuPresenter: NSObject, UIEditMenuInteractionDelegate {
    private let host: UIViewController
    private var interaction: UIEditMenuInteraction?
    private var items: [OfficeEditMenuItem] = []
    private var target = CGRect.zero
    private var selectedText: String?

    init(host: UIViewController) { self.host = host }

    /// Puts the interaction on the editor's view; once the editor is on screen.
    func attach() {
        guard interaction == nil else { return }
        let i = UIEditMenuInteraction(delegate: self)
        host.view.addInteraction(i)
        interaction = i
    }

    /// Shows the menu above `rect` (the editor view's coordinates), or takes it
    /// away when `rect` is nil.
    func show(_ rect: CGRect?, items: [OfficeEditMenuItem], text: String?) {
        guard let interaction else { return }
        guard let rect, !items.isEmpty else { interaction.dismissMenu(); return }
        self.items = items
        self.target = rect
        self.selectedText = text
        let config = UIEditMenuConfiguration(identifier: nil, sourcePoint: CGPoint(x: rect.midX, y: rect.minY))
        config.preferredArrowDirection = .automatic
        interaction.presentEditMenu(with: config)
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                             menuFor configuration: UIEditMenuConfiguration,
                             suggestedActions: [UIMenuElement]) -> UIMenu? {
        if ProcessInfo.processInfo.environment["OFFICE_TOOLBAR_DEBUG"] != nil {
            FileHandle.standardError.write(Data("[editmenu] suggested: \(suggestedActions.map { $0.title })\n".utf8))
        }
        var children: [UIMenuElement] = items.map { item in
            UIAction(title: item.title, image: UIImage(systemName: item.symbol),
                     attributes: item.isEnabled ? [] : .disabled) { _ in item.action() }
        }
        if let text = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            if UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: text) {
                children.append(UIAction(title: "Look Up", image: UIImage(systemName: "character.book.closed")) { [weak self] _ in
                    self?.host.present(UIReferenceLibraryViewController(term: text), animated: true)
                })
            }
            children.append(UIAction(title: "Share…", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                guard let self else { return }
                let sheet = UIActivityViewController(activityItems: [text], applicationActivities: nil)
                sheet.popoverPresentationController?.sourceView = self.host.view
                sheet.popoverPresentationController?.sourceRect = self.target
                self.host.present(sheet, animated: true)
            })
        }
        return UIMenu(children: children)
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                             targetRectFor configuration: UIEditMenuConfiguration) -> CGRect {
        target
    }
}
#endif
