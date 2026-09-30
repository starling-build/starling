// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The browser's half of ExampleHost: `runExampleApp` over WebHost.

#if os(WASI)
import CupertinoIcons
import Flutter
import FlutterSwiftBridge
import FlutterWeb

/// There is nothing to link: the page fetches the fonts, and there is no
/// ICU data file because the browser does the segmenting.
public func ensureEngineData() {}

/// Mounts the app on the page's canvas and returns. Unlike every other
/// host this does not run until the window closes — a tab has no loop of
/// ours to run; the page calls back in for each frame and event.
///
/// `title`, `width` and `height` describe a window, and the page already
/// has one: the canvas is whatever size the page made it.
public func runExampleApp(
    title: String, width: Int = 480, height: Int = 720, root: () -> Widget
) {
    print("[\(title)] Starting (web host)")
    WebHost.shared.mountWidget(root)
}
#endif
