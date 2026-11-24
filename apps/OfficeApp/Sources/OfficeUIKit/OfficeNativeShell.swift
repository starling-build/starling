// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The iPad's native frame around the Office editors: Files-style document
// browser at launch, the editor (the Flutter view) presented over it when a
// document is chosen, and the way back.
//
// Why native: opening, creating, renaming and moving documents, iCloud Drive,
// "Open in…", recents and thumbnails are things the platform already does well
// and an in-app file panel over the sandbox cannot do at all. The page canvas
// stays ours — layout and paint are OfficeText on the engine — so this layer is
// only the frame. It knows nothing about .docx: it moves files and tells the
// app (OfficeApp, by the closures below) which path to open.
//
// Working copies. A picked document is copied into the app's own directory and
// the editor opens THAT path. The three shells save by writing to the path they
// were given with Data.write(.atomic), which creates a temporary file beside the
// target — not permitted next to a document in another app's container, where
// only the file itself is granted. So the editors keep working on a path they
// fully own, and every save is followed by documentSaved(_:), which replaces
// the original under an NSFileCoordinator (what iCloud and file providers need
// to see the change at all).
//
// This module has no C++ interop on purpose: UIKit through the interop importer
// is the thing the SDK's ObjC glue exists to avoid. It reaches the host through
// the C functions in FlutterUIKitBridge.h only.

#if os(iOS)
import UIKit
import UniformTypeIdentifiers
import FlutterUIKitBridge

public enum OfficeNativeShell {
    /// The app's handler for "open this path now" — the working copy of the
    /// document the user chose. Called on the main thread, before the editor
    /// is shown.
    /// `viewId` is the window (the Flutter view) the document is for.
    public static var onOpenDocument: ((String, Int) -> Void)?

    /// Writes an empty document of `kind` ("document", "presentation",
    /// "workbook") to `path`; false if the app could not.
    public static var makeBlank: ((String, String) -> Bool)?

    /// The original document a working copy at `path` was made from, if it is the one being edited. Safe from any
    /// thread.
    public static func originalPath(forWorking path: String) -> String? {
        func look() -> String? {
            for shell in shells.values {
                if let s = shell.session, s.working.path == path { return s.original.path }
            }
            return nil
        }
        return Thread.isMainThread ? look() : DispatchQueue.main.sync(execute: look)
    }

    /// Opens `url` as if the user had picked it in the browser (a file handed over by another app, a drop, a test).
    /// `viewId` is the window it is handed to.
    public static func open(_ url: URL, viewId: Int = 0) {
        DispatchQueue.main.async { shells[viewId]?.open(handedOver.removeValue(forKey: url.absoluteString) ?? url) }
    }

    /// Asks for a new window, showing `url` if there is one. The window is the system's (Stage Manager, Split View):
    /// it arrives later, as a scene.
    public static func openInNewWindow(_ url: URL?) {
        if let url { handedOver[url.absoluteString] = url }
        fluikit_scene_request_new(url?.absoluteString)
    }

    /// URLs the browser handed us that another window is about to open: the URL object, not a copy of its text,
    /// is what carries the access to a file outside the app's sandbox.
    nonisolated(unsafe) fileprivate static var handedOver: [String: URL] = [:]

    /// Set by the app: the window (other than `viewId`'s) already showing the document at `path`, if any, is
    /// brought forward and true is returned. One document, one window.
    public static var focusIfOpen: ((String, Int) -> Bool)?

    /// Set by the app: a window beyond the first has connected (its view is about to be added) or disconnected (its
    /// view is about to go).
    public static var sceneConnected: ((Int) -> Void)?
    public static var sceneDisconnected: ((Int) -> Void)?

    /// The editor wants the browser back (Open, Close).
    public static func showBrowser(viewId: Int = 0) {
        DispatchQueue.main.async { shells[viewId]?.dismissEditor() }
    }

    /// The editor has just written the working copy at `path`; carry it to the
    /// document the user chose. Safe to call from any thread.
    public static func documentSaved(_ path: String, viewId: Int = 0) {
        // Straight away on the main thread (the app going to the background has no time for a hop); else via it.
        if Thread.isMainThread { shells[viewId]?.writeBack(path) } else { DispatchQueue.main.async { shells[viewId]?.writeBack(path) } }
    }

    /// Writes a copy to a temporary file with `prepare`, then asks the user
    /// where to put it. See OfficeHost.exportRequested.
    public static func export(name: String,
                              prepare: @escaping (String, @escaping (Bool) -> Void) -> Void,
                              thenOpen: Bool,
                              viewId: Int = 0,
                              done: @escaping (String?) -> Void) {
        guard let shell = shells[viewId] else { done(nil); return }
        shell.presentExport(name: name, prepare: prepare, thenOpen: thenOpen, done: done)
    }

    /// Writes a copy to a temporary file with `prepare`, then offers it to the
    /// system share sheet. See OfficeHost.shareRequested.
    public static func share(name: String,
                             prepare: @escaping (String, @escaping (Bool) -> Void) -> Void,
                             viewId: Int = 0,
                             done: @escaping (String?) -> Void) {
        guard let shell = shells[viewId] else { done(nil); return }
        shell.presentShare(name: name, prepare: prepare, done: done)
    }

    /// Insert > Picture: the Photo Library or Files, then `done` with a temporary copy's path (nil: cancelled).
    public static func pickPicture(viewId: Int = 0, done: @escaping (String?) -> Void) {
        guard let shell = shells[viewId] else { done(nil); return }
        let presenter = shell.presentedViewController ?? shell
        let b = presenter.view.bounds
        PicturePicker.choose(over: presenter, anchor: CGRect(x: b.midX, y: b.midY * 0.5, width: 1, height: 1), done: done)
    }

    /// Runs the browser's "Open in New Window" action for `url` in window `viewId`, as its menu item does (a test:
    /// the menu itself is a system popover no in-app driver can tap).
    public static func runNewWindowAction(viewId: Int, url: URL) {
        shells[viewId]?.newWindowHandler?([url])
    }

    /// How many window controllers are alive (a leak hunt).
    public static var liveBrowsers: Int { OfficeBrowserController.live }

    /// The buttons of the bar over the keyboard (nil: none). Safe to call on
    /// the main thread only.
    public static func setToolbar(_ buttons: [OfficeToolbarButton]?, viewId: Int = 0) {
        shells[viewId]?.latestToolbar = buttons
        shells[viewId]?.toolbar.update(buttons)
    }

    /// The edit menu over a selection or caret at `rect` (the editor view's
    /// coordinates); nil takes it away. Main thread only.
    public static func showEditMenu(_ rect: CGRect?, items: [OfficeEditMenuItem], text: String?, viewId: Int = 0) {
        shells[viewId]?.editMenu.show(rect, items: items, text: text)
    }

    /// The system print dialog over a PDF the editor rendered. The file is a
    /// temporary one; it goes when the dialog is done.
    public static func printPDF(_ path: String) {
        let url = URL(fileURLWithPath: path)
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = url.deletingPathExtension().lastPathComponent
        controller.printInfo = info
        controller.printingItem = url
        controller.present(animated: true) { _, _, _ in
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Whether the window showing `viewId` has a native browser.
    public static func hasShell(_ viewId: Int) -> Bool { shells[viewId] != nil }

    /// Whether a document is being edited right now.
    public static var isEditing: Bool { shells.values.contains { $0.session != nil } }

    /// Installs the browser as the app's root. Call before the host runs.
    public static func install() {
        // One browser (and editing session) per window, found by the view the window shows.
        fluikit_host_set_root_factory({ editor, viewId, _ in
            let editorController = Unmanaged<UIViewController>.fromOpaque(editor!).takeUnretainedValue()
            let browser = OfficeBrowserController(editor: editorController, viewId: Int(viewId))
            OfficeNativeShell.shells[Int(viewId)] = browser
            return Unmanaged.passRetained(browser).toOpaque()
        }, nil)
        fluikit_host_set_open_url_handler({ _, viewId, url in
            guard let url = url, let parsed = URL(string: String(cString: url)), parsed.isFileURL else { return false }
            OfficeNativeShell.open(parsed, viewId: Int(viewId))
            return true
        }, nil)
        // A window comes back from the last run showing the document it showed: a bookmark to the original (it
        // finds the file again wherever it went, and carries the access a file outside the app's sandbox needs).
        fluikit_host_set_restoration_handlers({ _, viewId in
            guard let original = OfficeNativeShell.shells[Int(viewId)]?.session?.original,
                  let data = try? original.bookmarkData() else { return nil }
            return strdup(data.base64EncodedString())
        }, { _, viewId, token in
            guard let token = token, let data = Data(base64Encoded: String(cString: token)) else { return }
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale),
                  FileManager.default.fileExists(atPath: url.path) else { return }   // a file that is gone: the window stays blank
            OfficeNativeShell.open(url, viewId: Int(viewId))
        }, nil)
        fluikit_host_set_scene_handlers({ _, viewId in
            OfficeNativeShell.sceneConnected?(Int(viewId))
        }, { _, viewId in
            OfficeNativeShell.sceneDisconnected?(Int(viewId))
            // The window's session ends with it (its working copy goes; the original was written by the last save).
            OfficeNativeShell.shells[Int(viewId)]?.windowClosed()
            OfficeNativeShell.shells[Int(viewId)] = nil
        }, nil)
    }

    /// Each window's browser, by the view it shows: 0 is the first.
    nonisolated(unsafe) fileprivate static var shells: [Int: OfficeBrowserController] = [:]
    fileprivate static var shared: OfficeBrowserController? { shells[0] }
}

/// The system's export picker for one file, and the clean-up after it.
private final class ExportPicker: NSObject, UIDocumentPickerDelegate {
    let controller: UIDocumentPickerViewController
    private let dir: URL
    private let finish: (URL?) -> Void

    init(file: URL, dir: URL, finish: @escaping (URL?) -> Void) {
        self.dir = dir
        self.finish = finish
        controller = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
        super.init()
        controller.delegate = self
        controller.shouldShowFileExtensions = true
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        try? FileManager.default.removeItem(at: dir)
        finish(urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        try? FileManager.default.removeItem(at: dir)
        finish(nil)
    }
}

/// One document being edited: where it came from and the copy being edited.
private final class EditingSession {
    let original: URL
    let working: URL
    let scoped: Bool
    /// Saves that arrive while a write-back is running are coalesced into one
    /// more write-back, so the last save always lands and none is skipped.
    var writing = false
    var pending = false
    init(original: URL, working: URL, scoped: Bool) {
        self.original = original; self.working = working; self.scoped = scoped
    }
}

final class OfficeBrowserController: UIDocumentBrowserViewController, UIDocumentBrowserViewControllerDelegate {
    private let editor: UIViewController
    fileprivate let toolbar: EditorToolbar
    fileprivate let editMenu: EditMenuPresenter
    fileprivate var session: EditingSession?
    private let queue = DispatchQueue(label: "office.writeback")
    /// The Flutter view this window shows (0 for the first window).
    let viewId: Int
    /// What the browser's "Open in New Window" does (the action's own closure, so a test runs the same code).
    fileprivate var newWindowHandler: (([URL]) -> Void)?
    /// The last buttons published, kept for an editor that mounted before the browser had the bar in its view.
    fileprivate var latestToolbar: [OfficeToolbarButton]?

    /// Live browser controllers (a leak hunt: OFFICE_WINDOW_CYCLES prints it).
    nonisolated(unsafe) static var live = 0
    deinit { Self.live -= 1 }

    init(editor: UIViewController, viewId: Int) {
        Self.live += 1
        self.viewId = viewId
        self.editor = editor
        self.toolbar = EditorToolbar(host: editor)
        self.editMenu = EditMenuPresenter(host: editor)
        let types = [
            "org.openxmlformats.wordprocessingml.document",
            "org.openxmlformats.presentationml.presentation",
            "org.openxmlformats.spreadsheetml.sheet",
        ].compactMap { UTType($0) } + [.commaSeparatedText, .tabSeparatedText, .rtf, .plainText]
        super.init(forOpening: types)
        delegate = self
        allowsDocumentCreation = true
        allowsPickingMultipleItems = false
        shouldShowFileExtensions = true
        // The browser's own context menu: the same file in a window of its own.
        // A file some window already shows is brought forward, not opened twice (one document, one window).
        let openInNewWindow: ([URL]) -> Void = { urls in
            guard let url = urls.first else { return }
            if OfficeNativeShell.focusIfOpen?(url.path, -1) == true { return }
            OfficeNativeShell.openInNewWindow(url)
        }
        newWindowHandler = openInNewWindow
        let newWindow = UIDocumentBrowserAction(identifier: "build.starling.office.new-window",
                                                localizedTitle: "Open in New Window",
                                                availability: [.menu, .navigationBar], handler: openInNewWindow)
        newWindow.supportedContentTypes = types.map(\.identifier)
        newWindow.supportsMultipleItems = false
        customActions = [newWindow]
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// OFFICE_NATIVE_OPEN=<path>: act as if the user had picked that file in
    /// the browser, once, when it first appears. The Simulator has no touch
    /// route from the command line, so this is how the pick → working copy →
    /// editor path is driven in a test.
    private var launchOpenDone = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !launchOpenDone else { return }
        launchOpenDone = true
        // The first window only: a window made later is for the file it was made for.
        if viewId == 0, let path = ProcessInfo.processInfo.environment["OFFICE_NATIVE_OPEN"], !path.isEmpty {
            open(URL(fileURLWithPath: path))
        }
    }

    // MARK: Opening

    func documentBrowser(_ controller: UIDocumentBrowserViewController,
                         didPickDocumentsAt documentURLs: [URL]) {
        if let url = documentURLs.first { open(url) }
    }

    func documentBrowser(_ controller: UIDocumentBrowserViewController,
                         didImportDocumentAt sourceURL: URL, toDestinationURL destinationURL: URL) {
        open(destinationURL)
    }

    func documentBrowser(_ controller: UIDocumentBrowserViewController,
                         failedToImportDocumentAt documentURL: URL, error: Error?) {
        alert("Could not create the document", error?.localizedDescription ?? "")
    }

    /// Takes a document the user chose (or that another app handed over) into
    /// the editor.
    func open(_ url: URL) {
        if OfficeNativeShell.focusIfOpen?(url.path, viewId) == true { return }
        endSession()
        let scoped = url.startAccessingSecurityScopedResource()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenDocuments", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let working = dir.appendingPathComponent(url.lastPathComponent)
        var failure: Error?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: readable, to: working)
            } catch { failure = error }
        }
        if let error = failure ?? coordinationError {
            if scoped { url.stopAccessingSecurityScopedResource() }
            alert("Could not open \(url.lastPathComponent)", error.localizedDescription)
            return
        }
        session = EditingSession(original: url, working: working, scoped: scoped)
        let path = working.path
        if editor.presentingViewController == nil {
            editor.modalPresentationStyle = .fullScreen
            // The document is handed over once the editor is on screen: the
            // engine only takes a frame request while its view is attached,
            // and a setState before that is a frame that is never drawn.
            present(editor, animated: true) {
                self.toolbar.attach()
                self.editMenu.attach()
                self.toolbar.update(self.latestToolbar)
                OfficeNativeShell.onOpenDocument?(path, self.viewId)
            }
        } else {
            OfficeNativeShell.onOpenDocument?(path, viewId)
        }
    }

    func dismissEditor() {
        endSession()
        if editor.presentingViewController != nil { dismiss(animated: true) }
    }

    // MARK: Creating

    func documentBrowser(_ controller: UIDocumentBrowserViewController,
                         didRequestDocumentCreationWithHandler importHandler:
                         @escaping (URL?, UIDocumentBrowserViewController.ImportMode) -> Void) {
        let sheet = UIAlertController(title: "New", message: nil, preferredStyle: .actionSheet)
        let kinds: [(String, String, String)] = [
            ("Document", "document", "docx"),
            ("Presentation", "presentation", "pptx"),
            ("Workbook", "workbook", "xlsx"),
        ]
        for (title, kind, ext) in kinds {
            sheet.addAction(UIAlertAction(title: title, style: .default) { _ in
                let dir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("NewDocuments", isDirectory: true)
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                let url = dir.appendingPathComponent("Untitled.\(ext)")
                do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) } catch {
                    importHandler(nil, .none); return
                }
                if OfficeNativeShell.makeBlank?(kind, url.path) == true {
                    importHandler(url, .move)
                } else {
                    importHandler(nil, .none)
                }
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in importHandler(nil, .none) })
        // Anchored under the browser's own Create button on iPad; with no
        // handle on that button, the centre of the view is a safe anchor.
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        sheet.popoverPresentationController?.permittedArrowDirections = []
        present(sheet, animated: true)
    }

    // MARK: Save As and Export

    private var exportPicker: ExportPicker?

    /// The file is written in the app's temporary directory first and handed to
    /// the system's picker as a copy, so the user chooses the place (iCloud
    /// Drive, On My iPad, another app's folder) and the picker does the writing.
    func presentExport(name: String,
                       prepare: @escaping (String, @escaping (Bool) -> Void) -> Void,
                       thenOpen: Bool,
                       done: @escaping (String?) -> Void) {
        guard exportPicker == nil else { done(nil); return }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Exports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = dir.appendingPathComponent(name)
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) } catch {
            alert("Could not export \(name)", error.localizedDescription)
            done(nil)
            return
        }
        prepare(file.path) { [weak self] ok in
            DispatchQueue.main.async {
                guard let self else { return }
                guard ok else {
                    try? FileManager.default.removeItem(at: dir)
                    self.alert("Could not write \(name)", "")
                    done(nil)
                    return
                }
                let picker = ExportPicker(file: file, dir: dir) { [weak self] picked in
                    self?.exportPicker = nil
                    if let picked, thenOpen { self?.open(picked) }
                    done(picked?.lastPathComponent)
                }
                self.exportPicker = picker
                let presenter = self.editor.presentedViewController ?? self.editor
                presenter.present(picker.controller, animated: true)
                if ProcessInfo.processInfo.environment["OFFICE_HOST_LOG"] != nil {
                    let w = self.editor.view.window
                    fputs("[export] view \(self.viewId) presents the picker over its own window: scene \(w?.windowScene?.session.persistentIdentifier ?? "none"), key \(w?.isKeyWindow == true)\n", stderr)
                }
            }
        }
    }

    /// The share sheet over a copy of the document, written in the app's
    /// temporary directory under the document's own name (the recipient sees
    /// `Report.docx`, not a working-copy name) and removed when the sheet
    /// closes. `done` gets the file's name if the user sent it somewhere.
    func presentShare(name: String,
                      prepare: @escaping (String, @escaping (Bool) -> Void) -> Void,
                      done: @escaping (String?) -> Void) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Shares", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = dir.appendingPathComponent(name)
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) } catch {
            alert("Could not share \(name)", error.localizedDescription)
            done(nil)
            return
        }
        prepare(file.path) { [weak self] ok in
            DispatchQueue.main.async {
                guard let self else { return }
                guard ok else {
                    try? FileManager.default.removeItem(at: dir)
                    self.alert("Could not write \(name)", "")
                    done(nil)
                    return
                }
                let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
                sheet.completionWithItemsHandler = { _, completed, _, _ in
                    try? FileManager.default.removeItem(at: dir)
                    done(completed ? name : nil)
                }
                let presenter = self.editor.presentedViewController ?? self.editor
                // An iPad shows the sheet as a popover, which needs somewhere to point: the top right of the
                // window, where the Share command sits.
                if let pop = sheet.popoverPresentationController {
                    pop.sourceView = presenter.view
                    pop.sourceRect = CGRect(x: presenter.view.bounds.maxX - 60, y: 40, width: 1, height: 1)
                    pop.permittedArrowDirections = [.up]
                }
                presenter.present(sheet, animated: true)
            }
        }
    }

    // MARK: Saving

    /// Replaces the original with the working copy, coordinated. Coalesced: if
    /// a write is running, one more runs after it with whatever is on disk by
    /// then.
    func writeBack(_ path: String) {
        // The session is taken NOW, by the caller: a window that is closing saves and ends its session in the same
        // turn, and a queued write that looked the session up afterwards found none and dropped the save.
        let current: EditingSession? = Thread.isMainThread ? session : DispatchQueue.main.sync { session }
        queue.async { [weak self] in
            guard let self else { return }
            guard let s = current, s.working.path == path else {
                fputs("[office] write-back skipped: \(path) is not the open document\n", stderr)
                return
            }
            if s.writing { s.pending = true; return }
            s.writing = true
            repeat {
                s.pending = false
                var coordinationError: NSError?
                var failure: Error?
                NSFileCoordinator().coordinate(writingItemAt: s.original, options: .forReplacing,
                                               error: &coordinationError) { target in
                    do {
                        let data = try Data(contentsOf: s.working)
                        try data.write(to: target)
                    } catch { failure = error }
                }
                fputs("[office] write-back \(s.original.lastPathComponent): \((failure ?? coordinationError).map { "failed: \($0)" } ?? "ok")\n", stderr)
                if let error = failure ?? coordinationError {
                    DispatchQueue.main.async {
                        self.alert("Could not save \(s.original.lastPathComponent)", error.localizedDescription)
                    }
                }
            } while s.pending
            s.writing = false
        }
    }

    /// The window is going: its session ends (the working copy is removed).
    func windowClosed() { endSession() }

    private func endSession() {
        guard let s = session else { return }
        // A write-back still running keeps its reference to the session, and the
        // security scope lasts until it is done with the original.
        queue.async {
            if s.scoped { s.original.stopAccessingSecurityScopedResource() }
            try? FileManager.default.removeItem(at: s.working.deletingLastPathComponent())
        }
        session = nil
    }

    private func alert(_ title: String, _ message: String) {
        let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        (presentedViewController ?? self).present(a, animated: true)
    }
}
#endif
