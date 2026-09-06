// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation

// Check for --picker mode (launched by portal FileChooser service)
let isPickerMode = CommandLine.arguments.contains("--picker")

// MARK: - Root

runApp(StarlingApp(
    title: "Files",
    // FinderColors is a static table the lazy file list's rows read, so it
    // is flipped before the rebuild; and those rows do not rebuild on an
    // ancestor rebuild, so a refresh emission makes them re-read it — on a
    // style switch as much as on an appearance one.
    onThemeChanged: { dark in
        FinderColors.dark = dark
        filesBlocShared?.add(.refresh)
    },
    onStyleChanged: { _ in filesBlocShared?.add(.refresh) },
    home: isPickerMode ? FileExplorerPickerApp() : FileExplorerApp()))
