// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The desktop preferences the shell pushes to every app and Settings can
// ask it to change — one small integer each, over DMABUF_CONTROL_SET_PREF
// (DmaBufBridge.h), which carries the preference's id and its value.
//
// The shell owns the list and the meaning of each value; an app that meets
// an id it does not know ignores it, and one built before a preference
// existed keeps its default. `StarlingApp` honours the first two itself
// (`FluentMaterialSettings` over the tree, so acrylic falls to its solid
// and entrances stop moving when the user turns them off); the rest are
// Start's, mirrored by Settings.

/// A desktop preference, by the id that goes over the wire.
public enum StarlingPref: Int {
    /// Transparency effects — acrylic and Mica, or their solid fallbacks. 0/1.
    case transparency = 1
    /// Animation effects — window and flyout motion, or none. 0/1.
    case animations = 2
    /// Start's All apps layout: 0 category, 1 grid, 2 list.
    case startView = 3
    /// Whether Start shows recently added apps and recent files. 0/1.
    case startRecent = 4
    /// Start's size: 0 auto, 1 small, 2 large.
    case startSize = 5
}

public enum StarlingPrefs {
    /// The value the shell last pushed for `pref`, or nil if it has not.
    public static func current(_ pref: StarlingPref) -> Int? {
        #if os(Linux)
        return GpuDmaBufRenderer.lastPushedPrefs[pref.rawValue]
        #else
        return nil
        #endif
    }

    /// A 0/1 preference as a Bool, defaulting to on.
    public static func isOn(_ pref: StarlingPref) -> Bool {
        (current(pref) ?? 1) != 0
    }
}
