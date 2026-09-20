// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/// A centered lens for one display. All values are logical pixels,
/// independent of that monitor's position and physical resolution.
struct DesktopSceneLens {
    let width: Double
    let height: Double
    let focal: Double
    var centreX: Double { width / 2 }
    var centreY: Double { height / 2 }

    var tanHalfFovX: Double { width / (2 * focal) }
    var shiftX: Double { 1 - 2 * centreX / width }
    var shiftY: Double { 2 * centreY / height - 1 }
}
