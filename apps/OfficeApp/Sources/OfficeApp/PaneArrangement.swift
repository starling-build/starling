// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge

/// Where a side pane (Format Shape, Animation, Styles...) sits relative to the document it works on.
///
/// - A narrow window (a Split View pane, under `narrowBelow`): the newest pane is a sheet along the bottom, full width, the
///   document above it.
/// - A wide window on a touch device: the newest pane is a slide-over, a panel floating over the document's right edge with
///   a shadow, so the page keeps its size and position and the pane can be dismissed without the page jumping.
/// - A wide window under a pointer: panes dock beside the document, as they always have.
///
/// Only the newest pane gets the sheet or the slide-over; earlier open panes stay docked and come back when it closes.
enum PaneArrangement {
    static let narrowBelow = 600.0
    static let slideOverWidth = 320.0

    enum Style: Equatable { case docked, slideOver, bottomSheet }

    static func style(narrow: Bool, touch: Bool) -> Style {
        narrow ? .bottomSheet : touch ? .slideOver : .docked
    }

    /// Whether this build is one a finger drives.
    static var isTouchDevice: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    /// `document` is the work area as laid out without the panes; `docked` are the panes that sit beside it (in order,
    /// already built); `newest` is the pane that becomes a sheet or a slide-over, if any.
    static func arrange(style: Style, fluent: FluentThemeData, document: Widget, docked: [Widget], newest: Widget?) -> Widget {
        guard let newest else { return Row(crossAxisAlignment: .stretch, children: [document] + docked) }
        switch style {
        case .docked:
            return Row(crossAxisAlignment: .stretch, children: [document] + docked + [newest])
        case .bottomSheet:
            return Column(crossAxisAlignment: .stretch, children: [
                Expanded(flex: 5, child: Row(crossAxisAlignment: .stretch, children: [document] + docked)),
                Expanded(flex: 4, child: DecoratedBox(
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: fluent.resources.controlStrokeColorDefault, width: 1))),
                    child: newest)),
            ])
        case .slideOver:
            return Stack(children: [
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: Row(crossAxisAlignment: .stretch, children: [document] + docked)),
                Positioned(top: 8, right: 8, bottom: 8, width: slideOverWidth, child: DecoratedBox(
                    decoration: BoxDecoration(border: Border.all(color: fluent.resources.controlStrokeColorDefault, width: 1),
                                              borderRadius: BorderRadius.circular(8),
                                              boxShadow: [BoxShadow(color: Color(0x40000000), offset: Offset(-2, 4), blurRadius: 16)]),
                    child: newest)),
            ])
        }
    }
}
