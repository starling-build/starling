// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The rubber band: Explorer's drag-selection rectangle.
//
// Same division of labour as the context menu, for the same measured reason:
// the rectangle chases the pointer at input rate, so it gets its own model
// and its own overlay widget, and what re-runs per pointer move is THIS
// build -- one Positioned box -- never the file explorer behind it. The
// explorer only hears about it when the SET of covered rows changes, which
// is a bloc event like any other and worth a real rebuild.
//
// The geometry (which rows a rectangle covers, how far the list is scrolled)
// stays in Files.swift with the rest of the listing's arithmetic; this file
// is only the drawing.

#if os(Windows)
import Flutter
import Observation

@Observable
final class BandModel: @unchecked Sendable {
    /// The rectangle, in window coordinates, or nil when no drag is live.
    /// Written by the listing's pointer handlers, read only by the overlay.
    var rect: (x: Double, y: Double, w: Double, h: Double)?
}

final class BandOverlay: StatefulWidget {
    let model: BandModel

    init(model: BandModel) {
        self.model = model
        super.init()
    }

    override func createState() -> State<StatefulWidget> {
        BandOverlayState(model: model)
    }
}

final class BandOverlayState: State<StatefulWidget> {
    private let model: BandModel

    init(model: BandModel) {
        self.model = model
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        withObservationTracking {
            _buildContent()
        } onChange: { [weak self] in
            guard let self, self.mounted else { return }
            self.setState {}
        }
    }

    private func _buildContent() -> Widget {
        // Zero-size when idle: nothing drawn, and nothing hit-testable
        // sitting over the listing (a ColoredBox is opaque to hits even at
        // alpha 0 -- the overlay must genuinely not exist between drags).
        guard let r = model.rect else { return SizedBox(width: 0, height: 0) }
        return Stack(alignment: Alignment.topLeft) {
            Positioned(left: r.x, top: r.y) {
                SizedBox(width: r.w, height: r.h) {
                    DecoratedBox(
                        decoration: BoxDecoration(
                            color: Win11.bandFill,
                            border: Border.all(color: Win11.bandStroke,
                                               width: 1)))
                }
            }
        }
    }
}

#endif
