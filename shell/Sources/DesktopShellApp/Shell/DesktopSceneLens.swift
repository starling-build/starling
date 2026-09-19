// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/// Off-axis projection for one virtual desktop. All values are logical
/// pixels, independent of each monitor's physical resolution and scale.
struct DesktopSceneLens {
    let width: Double
    let height: Double
    let focal: Double
    /// Optical centre relative to the virtual desktop's top-left.
    let centreX: Double
    let centreY: Double

    var tanHalfFovX: Double { width / (2 * focal) }
    var shiftX: Double { 1 - 2 * centreX / width }
    var shiftY: Double { 2 * centreY / height - 1 }
}
