// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The hover wrapper every Windows-shaped control needs.
//
// Native chrome answers the pointer everywhere -- caption buttons grey,
// close goes red, rows lighten -- and a surface that sits still under the
// mouse reads as a picture of a UI rather than one. This wraps a builder
// whose only input is "is the pointer here", so the REBUILD SCOPE of a
// hover change is this widget alone: the same discipline that moved the
// context menu into its own widget, applied at control size. Wrapping rows
// in it costs one enter and one exit rebuild per row crossed, not a window
// rebuild per pointer move.

#if os(Windows)
import Flutter

final class Hover: StatefulWidget {
    let builder: (Bool) -> Widget

    init(_ builder: @escaping (Bool) -> Widget) {
        self.builder = builder
        super.init()
    }

    override func createState() -> State<StatefulWidget> { HoverState() }
}

final class HoverState: State<StatefulWidget> {
    private var hovered = false

    override func build(_ context: any BuildContext) -> Widget {
        // Read through `widget`, not a captured init value: the parent
        // rebuilds with fresh builder closures (fresh captured state), and
        // the framework keeps `widget` pointing at the newest one.
        let hover = widget as! Hover
        return MouseRegion(
            onEnter: { [weak self] _ in
                guard let self, self.mounted else { return }
                self.setState { self.hovered = true }
            },
            onExit: { [weak self] _ in
                guard let self, self.mounted else { return }
                self.setState { self.hovered = false }
            },
            child: hover.builder(hovered))
    }
}
#endif
