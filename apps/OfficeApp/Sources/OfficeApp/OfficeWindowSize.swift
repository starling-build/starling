// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/// The size of the app's drawing area (below the title bar), in points. STARLING_WINDOW_W / _H set it; otherwise
/// 1440x900, except under the script driver (OFFICE_SCRIPT), which opens 1440x932: the size the UI harness tests use,
/// so a point read in the harness lands on the same control on the Mac (Q1: at 1440x900 everything below the ribbon
/// sat 16-33 px off).
enum OfficeWindowSize {
    static let scripted = (width: 1440, height: 932)

    static func of(_ env: [String: String]) -> (width: Int, height: Int) {
        let scripting = !(env["OFFICE_SCRIPT"] ?? "").isEmpty
        let fallback = scripting ? scripted : (width: 1440, height: 900)
        return (metric(env["STARLING_WINDOW_W"]) ?? fallback.width, metric(env["STARLING_WINDOW_H"]) ?? fallback.height)
    }

    private static func metric(_ v: String?) -> Int? {
        guard let v, let n = Int(v), n > 0 else { return nil }
        return n
    }
}
