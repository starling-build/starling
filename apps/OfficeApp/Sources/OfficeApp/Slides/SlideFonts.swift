// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A slide's faces as PowerPoint stands in for them: the shared
/// stand-ins (`OfficeFonts.substitute`), except for a name they do not
/// know. The shared rule sets that in the Cambria clone (Word on a Mac's
/// way); PowerPoint, printing a face its machine lacks, used Calibri —
/// tdf168835's "Marianne", bug65228's "Graphik" and tdf119187's
/// "BentonSans" are Calibri in its prints. (Sweep 106: ten decks
/// nearer, n862510_4's "Segoe UI Light" — a weight we have no face for
/// either way — and tdf98603's Hebrew FrankRuehl a little further.)
enum SlideFonts {
    static func resolve(_ family: String) -> String {
        let face = OfficeFonts.substitute(family)
        guard face == OfficeFonts.cambria else { return face }
        let n = family.trimmingWhitespace().lowercased()
        guard !n.hasPrefix("cambria"), n != "caladea" else { return face }
        return OfficeFonts.calibri
    }
}
