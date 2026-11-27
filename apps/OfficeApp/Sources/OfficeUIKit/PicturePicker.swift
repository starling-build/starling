// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Insert > Picture on iPad: the system's own sources instead of an in-app list over the sandbox.
// A sheet offers the Photo Library (PHPicker: no permission prompt, reads only what the user picks) and
// Files (the document picker: iCloud Drive, On My iPad, other apps' folders). Either way the picture
// is copied into a temporary file the editors read as an ordinary path; HEIC and other formats the
// image codec does not decode are re-encoded as JPEG on the way (orientation baked in).

#if os(iOS)
import UIKit
import PhotosUI
import UniformTypeIdentifiers

/// One pick in flight: it is the delegate of whichever picker the user chose, and keeps itself alive until done.
final class PicturePick: NSObject, PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
    private let dir: URL
    private var finish: ((String?) -> Void)?
    private var keep: PicturePick?

    init(finish: @escaping (String?) -> Void) {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        self.finish = finish
        super.init()
        keep = self
    }

    private func end(_ path: String?) {
        let f = finish
        finish = nil
        keep = nil
        DispatchQueue.main.async { f?(path) }
    }

    /// `url` (a file we may read now) copied to the temp directory under `name`, converted if the codec can't read it.
    private func take(_ url: URL, name: String) -> String? {
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let ext = (name as NSString).pathExtension.lowercased()
            if ["png", "jpg", "jpeg", "gif", "bmp", "webp"].contains(ext) {
                let to = dir.appendingPathComponent(name)
                try FileManager.default.copyItem(at: url, to: to)
                return to.path
            }
            guard let image = UIImage(contentsOfFile: url.path), let jpeg = image.jpegData(compressionQuality: 0.92) else { return nil }
            let to = dir.appendingPathComponent(((name as NSString).deletingPathExtension) + ".jpg")
            try jpeg.write(to: to)
            return to.path
        } catch {
            return nil
        }
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let item = results.first?.itemProvider else { end(nil); return }
        item.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, _ in
            // The file is the system's, and gone when this block returns: copy it here.
            guard let self, let url else { self?.end(nil); return }
            self.end(self.take(url, name: url.lastPathComponent))
        }
    }

    /// A picture dragged in from another app: the same copy-and-convert as a pick.
    func receive(_ provider: NSItemProvider) {
        provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, _ in
            guard let self, let url else { self?.end(nil); return }
            self.end(self.take(url, name: url.lastPathComponent))
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { end(nil); return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        end(take(url, name: url.lastPathComponent))
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { end(nil) }
    func cancel() { end(nil) }

    func presentPhotos(over presenter: UIViewController) {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    func presentFiles(over presenter: UIViewController) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image], asCopy: true)
        picker.delegate = self
        presenter.present(picker, animated: true)
    }
}

/// A picture dropped on the editor (from Photos, Files, Safari, any app that drags an image, in Split View or
/// Slide Over beside this one): copied to a temporary file and handed to `onPicture`.
final class PictureDropDelegate: NSObject, UIDropInteractionDelegate {
    private let onPicture: (String) -> Void
    init(onPicture: @escaping (String) -> Void) { self.onPicture = onPicture }

    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        session.hasItemsConforming(toTypeIdentifiers: [UTType.image.identifier])
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        UIDropProposal(operation: .copy)
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        guard let item = session.items.first(where: { $0.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) else { return }
        PicturePick(finish: { [onPicture] path in if let path { onPicture(path) } }).receive(item.itemProvider)
    }
}

enum PicturePicker {
    /// Asks the user where the picture comes from, then calls `done` with the path of a temporary copy (nil if
    /// cancelled or it could not be read). `anchor` is the view the sheet points at on iPad.
    static func choose(over presenter: UIViewController, anchor: CGRect, done: @escaping (String?) -> Void) {
        let pick = PicturePick(finish: done)
        let sheet = UIAlertController(title: "Insert Picture", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Photo Library", style: .default) { _ in pick.presentPhotos(over: presenter) })
        sheet.addAction(UIAlertAction(title: "Files", style: .default) { _ in pick.presentFiles(over: presenter) })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in pick.cancel() })
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = presenter.view
            pop.sourceRect = anchor
        }
        presenter.present(sheet, animated: true)
    }
}
#endif
