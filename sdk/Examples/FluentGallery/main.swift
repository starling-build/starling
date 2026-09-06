// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The Fluent Gallery: the design system on one screen, in the shape of
// Microsoft's WinUI 3 Gallery — a navigation pane of categories, a page per
// control with live examples and their options, and the design-guidance
// pages that draw the tokens themselves. Runs on the GTK host in an
// ordinary window and knows nothing about a desktop, which is the point: if
// it looks like Windows 11 here, the tokens and controls are right, and any
// surface built from them elsewhere inherits that.
//
//   swift run -c release FluentGallery
//
// Files: GalleryApp (the pane and the catalog), GalleryWidgets (page,
// example card, tile), DesignPages (tokens drawn), ControlPages (one page
// per control).

#if os(Linux)
import ExampleHost
import Flutter
import FlutterSwiftBridge
import FluentSystemIcons

runExampleApp(title: "Fluent Gallery", width: 1400, height: 900) {
    GalleryApp()
}
#endif
