// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation
#if os(Linux)
import Glibc
#endif

// MARK: - FileExplorerPickerApp

/// The xdg portal file chooser — launched by the shell's FileChooser portal
/// service (`FileExplorerApp --picker` with PORTAL_* env). A thin shell
/// around the framework's FluentFilePanel (the same dialog apps embed
/// in-process), keeping only the portal contract: on confirm, print
/// selected file:// URIs to stdout (one per line) and exit 0; on cancel,
/// exit 1.
class FileExplorerPickerApp: StatelessWidget {

    private static func _options() -> FluentFilePanelOptions {
        let env = ProcessInfo.processInfo.environment
        var opts = FluentFilePanelOptions()
        if env["PORTAL_SAVE"] == "1" {
            opts.mode = .save
        } else if env["PORTAL_DIRECTORY"] == "1" {
            opts.mode = .directory
        } else {
            opts.mode = .open
        }
        opts.allowsMultiple = env["PORTAL_MULTIPLE"] == "1"
        opts.title = env["PORTAL_TITLE"] ?? "Open"
        if let accept = env["PORTAL_ACCEPT_LABEL"], !accept.isEmpty {
            opts.confirmLabel = accept
        }
        if let folder = env["PORTAL_FOLDER"], !folder.isEmpty {
            opts.initialDirectory = folder
        }
        if let name = env["PORTAL_SUGGESTED_NAME"], !name.isEmpty {
            opts.suggestedName = name
        }
        return opts
    }

    override func build(_ context: any BuildContext) -> Widget {
        return FluentFilePanel(options: Self._options()) { paths in
            guard !paths.isEmpty else { _exit(1) }
            // fflush is essential: print() buffers into the C stdio FILE*,
            // and _exit(0) skips stdio flushing — without this the URIs
            // never reach the portal's pipe.
            for path in paths {
                print("file://\(path)")
            }
            fflush(nil)
            _exit(0)
        }
    }
}
