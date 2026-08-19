// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// What to send when the terminal draws the wrong thing.
//
// A rendering bug is the one class of bug a person cannot usefully describe.
// "It shows weird red FSSPS;" is a real report, and it is not the reporter's
// fault: from where they sit, the letters are simply wrong, and every fact
// that would place the fault — which painter drew it, which faces were
// loaded, what the emulator thought was on screen, what the grid measured —
// lives inside the process and is invisible from a photograph.
//
// So the terminal writes those facts down itself, on a chord, at the moment
// the wrong thing is on screen. Two files land at the top of the home
// directory:
//
//   starling-terminal-report-<stamp>.txt   these facts, and the screen AS THE
//                                          EMULATOR HOLDS IT
//   starling-terminal-report-<stamp>.png   the same frame AS THE PAINTER DREW
//                                          IT, straight from an offscreen
//                                          recording, nothing composited over
//
// The pair is the point. Comparing them answers the first question in one
// glance, and it is the question that decides everything after it:
//
//   text right, png right   → the fault is below us: compositor, driver,
//                             display. Nothing in this process is wrong.
//   text right, png wrong   → ours, in the painter or the atlas. Ask the
//                             reporter for STARLING_TERM_ATLAS=0, which
//                             swaps the whole glyph path for the baseline.
//   text wrong              → ours, in the emulator or the pty — the painter
//                             is drawing exactly what it was handed.
//
// PRIVACY. The screen block is whatever was on screen. Scrollback is NOT
// included — a report is about a frame, and the rest of the session is
// nobody's business — and the file says so at the top, above the block, so a
// person can read what they are about to attach.

import Foundation

#if !os(iOS)

/// One report: the facts, the screen, and the file names they went to.
enum TerminalReport {

    /// Everything a report states, gathered at the moment of the chord.
    ///
    /// Passed in rather than read from the view, so this file formats and
    /// never guesses: every number here is the one the painter used for that
    /// frame.
    struct Scene {
        let grid: [[TermCell]]
        let cols: Int
        let rows: Int
        let cursorRow: Int
        let cursorCol: Int
        let viewOffset: Int
        let scrollback: Int
        let exited: Bool

        let theme: TerminalTheme
        let family: String
        /// What the widget asked for, and what glyphs were actually shaped at.
        /// They differ only on a fitted grid — and when they differ silently,
        /// glyphs land in slots of the other size, which is exactly the bug
        /// this report exists to make visible.
        let requestedSize: Double
        let shapedSize: Double
        let fallback: [String]

        let cellW: Double
        let cellH: Double
        let scale: Double
        let viewWidth: Double
        let viewHeight: Double

        let painter: String
        let atlas: String
        /// Whether the recorded .png is what drew the screen. False on the
        /// Text path, where the painter that records is not the one that
        /// painted — still worth having, as the difference between them
        /// localises the bug, but the report has to say which it is.
        let paintedIsScreen: Bool
    }

    // MARK: - Writing

    /// Write both files. Returns the text file's path, or nil if the home
    /// directory would not take it.
    ///
    /// `image` is handed the .png path and answers whether it managed to write
    /// one — the painter owns that, since only it can record the frame.
    static func write(_ scene: Scene, image: (String) -> Bool) -> String? {
        let stem = realUserHomeDirectory() + "/starling-terminal-report-" + stamp()
        let png = stem + ".png"
        let drew = image(png)
        let body = text(scene, png: drew ? png : nil)
        guard (try? body.write(toFile: stem + ".txt", atomically: true,
                               encoding: .utf8)) != nil
        else { return nil }
        return stem + ".txt"
    }

    /// `20260819-094122`. Seconds, because a person chasing one bug presses
    /// the chord more than once and the reports must not overwrite each other.
    private static func stamp(_ now: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: now)
    }

    // MARK: - The text

    static func text(_ s: Scene, png: String?) -> String {
        var out = """
        starling terminal — rendering report
        \(ISO8601DateFormatter().string(from: Date()))

        Send this file and the .png beside it.

        The .png is NOT a screenshot: it is what the painter drew, recorded
        offscreen with nothing composited over it. If it looks right and the
        screen did not, the fault is below this process — compositor, driver
        or display. If it looks wrong, the fault is here, and the "screen"
        block at the bottom says which half: it is what the emulator held, so
        text that reads correctly there and wrongly in the png is a painting
        bug, and text that is already wrong there never reached the painter.
        \(s.paintedIsScreen ? "" : """

        NOTE: this run is NOT using the default painter, so the .png is what \
        the atlas painter would draw for this grid rather than what was on \
        screen. Comparing the two is still worth doing — a difference is the \
        bug's address — but do not read the png as a photograph here.
        """)

        Worth trying before you send: run the terminal with
        STARLING_TERM_ATLAS=0, which swaps the whole glyph path for the older
        one kept as a baseline. If that fixes it, say so — it halves the
        search.

        PRIVACY: the screen block below is the text that was on screen when
        this was written. Scrollback is not included. Read it before you
        attach it.


        """
        out += section("where")
        out += row("platform", platformLine())
        out += row("binary", binaryLine())
        out += row("host", hostLine())
        if let png = png {
            out += row("painted", png)
        } else {
            out += row("painted", "— the frame could not be recorded, which is "
                                + "itself worth reporting")
        }

        out += section("how it was drawn")
        out += row("painter", s.painter)
        out += row("atlas", s.atlas)
        out += row("view", String(format: "%.1f × %.1f logical, device pixel ratio %.2f",
                                  s.viewWidth, s.viewHeight, s.scale))
        out += row("grid", String(format: "%d × %d cells of %.3f × %.3f",
                                  s.cols, s.rows, s.cellW, s.cellH))
        // Requested vs shaped, always both: equal is the normal case and
        // unequal is a bug with a known shape, so a reader must be able to
        // tell which they are looking at without knowing the feature exists.
        out += row("font", String(format: "%@ — %.2fpt asked, %.2fpt shaped",
                                  s.family, s.requestedSize, s.shapedSize))
        out += row("fallback", s.fallback.isEmpty ? "(none)"
                                                  : s.fallback.joined(separator: ", "))
        out += row("faces", facesLine())
        out += row("cursor", s.exited ? "(process exited)"
                                      : "row \(s.cursorRow), col \(s.cursorCol)")
        out += row("scrolled", s.viewOffset == 0
                     ? "no — this is the live screen"
                     : "\(s.viewOffset) line(s) back, of \(s.scrollback)")
        out += row("theme", String(format: "bg #%08X  fg #%08X  cursor #%08X  sel #%08X",
                                   s.theme.background, s.theme.defaultForeground,
                                   s.theme.cursorOverlay, s.theme.selection))
        out += row("env", envLine())

        out += glyphInventory(s)
        out += screen(s)
        return out
    }

    // MARK: - Sections

    private static func section(_ title: String) -> String {
        "\n── \(title) " + String(repeating: "─", count: max(3, 68 - title.count))
            + "\n"
    }

    private static func row(_ label: String, _ value: String) -> String {
        label.padding(toLength: max(label.count, 10), withPad: " ", startingAt: 0)
            + "  " + value + "\n"
    }

    /// Every non-ASCII codepoint on screen, with how many cells hold it.
    ///
    /// A glyph bug is about specific codepoints, and the report has to survive
    /// being pasted into an issue tracker that may mangle them — so they are
    /// named as U+XXXX as well as shown. This is also the fastest way to see
    /// that the wrong FACE is being asked for a character: ✗ (U+2717) and ❌
    /// (U+274C) look alike in a sentence and come from different fonts.
    private static func glyphInventory(_ s: Scene) -> String {
        var counts: [UInt32: Int] = [:]
        for line in s.grid {
            for cell in line where cell.scalar > 0x7F {
                counts[cell.scalar, default: 0] += 1
            }
        }
        guard !counts.isEmpty else {
            return section("non-ascii on screen") + "(none — every cell is ASCII)\n"
        }
        var out = section("non-ascii on screen")
        for (scalar, n) in counts.sorted(by: { $0.key < $1.key }).prefix(64) {
            let ch = UnicodeScalar(scalar).map(String.init) ?? "?"
            out += String(format: "U+%04X  %@  ×%d\n", scalar, ch, n)
        }
        if counts.count > 64 { out += "… and \(counts.count - 64) more\n" }
        return out
    }

    /// The visible screen, one line per row, with the colours and attributes
    /// each row carries.
    ///
    /// The annotations matter as much as the text: a report that says "weird
    /// red" is answered by whether the emulator already had that cell red. A
    /// row drawn in a colour it does not claim here is the painter inventing
    /// it; a row that claims it is the program's own output.
    private static func screen(_ s: Scene) -> String {
        var out = section("screen — what the emulator held")
        let width = String(s.grid.count).count
        // A terminal is mostly empty, and forty blank numbered lines at the
        // bottom of a report are forty lines nobody reads. The count still
        // gets said: "the rest was blank" is a fact about the frame, and a
        // report that simply stopped would leave a reader wondering.
        var lastInk = s.grid.count - 1
        while lastInk >= 0,
              s.grid[lastInk].prefix(s.cols).allSatisfy({
                  $0.scalar == 32 || $0.scalar == 0 }) {
            lastInk -= 1
        }
        for (i, line) in s.grid.prefix(lastInk + 1).enumerated() {
            var text = ""
            var fgs: Set<UInt32> = []
            var bgs: Set<UInt32> = []
            var attrs: CellAttrs = []
            for cell in line.prefix(s.cols) {
                if cell.attrs.contains(.wideCont) { continue }
                text.append(cell.scalar == 0 ? " " : cell.char)
                // 0 is "the theme's colour", which the header already states —
                // only a colour the CELL carries is worth a line here.
                if cell.fg != 0 { fgs.insert(cell.fg) }
                if cell.bg != 0 { bgs.insert(cell.bg) }
                attrs.formUnion(cell.attrs)
            }
            while text.hasSuffix(" ") { text.removeLast() }
            var note = ""
            if !fgs.isEmpty { note += "  [fg " + hexes(fgs) + "]" }
            if !bgs.isEmpty { note += "  [bg " + hexes(bgs) + "]" }
            let flags = attrFlags(attrs)
            if !flags.isEmpty { note += "  [" + flags + "]" }
            let n = String(repeating: " ",
                           count: max(0, width - String(i + 1).count))
                + String(i + 1)
            out += "\(n) │ \(text)\(note)\n"
        }
        let blank = s.grid.count - (lastInk + 1)
        if blank > 0 {
            out += "\(String(repeating: " ", count: width)) │ "
                + "(\(blank) blank row\(blank == 1 ? "" : "s") to the bottom "
                + "of the screen)\n"
        }
        return out
    }

    private static func hexes(_ colours: Set<UInt32>) -> String {
        colours.sorted().map { String(format: "#%08X", $0) }.joined(separator: " ")
    }

    private static func attrFlags(_ a: CellAttrs) -> String {
        var flags = ""
        if a.contains(.bold) { flags += "bold " }
        if a.contains(.dim) { flags += "dim " }
        if a.contains(.italic) { flags += "italic " }
        if a.contains(.underline) { flags += "underline " }
        if a.contains(.reverse) { flags += "reverse " }
        if a.contains(.wideLead) { flags += "wide " }
        return flags.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - The machine

    private static func platformLine() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        #if os(macOS)
        let name = "macOS"
        #elseif os(Linux)
        let name = "Linux"
        #elseif os(Windows)
        let name = "Windows"
        #else
        let name = "unknown platform"
        #endif
        #if arch(arm64)
        let cpu = "arm64"
        #elseif arch(x86_64)
        let cpu = "x86_64"
        #else
        let cpu = "unknown cpu"
        #endif
        return "\(name) \(os) · \(cpu)"
    }

    /// Which build this is. A version string when the packager left one, and
    /// the executable's own path and date regardless — on Linux nothing stamps
    /// the binary, and "which build were you running" is otherwise unanswerable.
    private static func binaryLine() -> String {
        var parts: [String] = []
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            parts.append("version \(v)")
        }
        let path = CommandLine.arguments.first ?? "(unknown)"
        parts.append(path)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let built = attrs[.modificationDate] as? Date {
            parts.append("built \(ISO8601DateFormatter().string(from: built))")
        }
        return parts.joined(separator: " · ")
    }

    /// Which embedder is drawing. Derived rather than recorded: the shell sets
    /// the socket, and otherwise the platform decides which windowed host was
    /// linked, one per platform.
    private static func hostLine() -> String {
        let env = ProcessInfo.processInfo.environment
        if let sock = env["FLUTTER_DMABUF_SOCKET"], !sock.isEmpty {
            return "Starling shell (DMA-BUF child)"
        }
        #if os(macOS)
        return "Cocoa window"
        #elseif os(Windows)
        return "Win32 window"
        #elseif os(Linux)
        return "GTK window"
        #else
        return "unknown host"
        #endif
    }

    /// The faces the terminal actually registered, and where they came from —
    /// the bundled ones are found by searching for a resource bundle, and a
    /// build that ships without one draws with the system's fonts and none of
    /// ours, which looks like a rendering bug and is a packaging one.
    private static func facesLine() -> String {
        let loaded = TerminalFontLoader.loadedFaces
        guard !loaded.isEmpty else {
            return "NONE registered — the resource bundle was not found, so "
                 + "nothing bundled is loaded (a packaging fault, not a "
                 + "drawing one)"
        }
        return loaded.joined(separator: ", ")
    }

    /// The knobs that change how this draws, and only the ones actually set:
    /// a report listing twenty unset variables buries the one that was.
    private static func envLine() -> String {
        let watched = ["STARLING_TERM_ATLAS", "STARLING_TERM_ATLAS_DEBUG",
                       "STARLING_TERM_DUMP", "STARLING_TERM_READER",
                       "STARLING_TERM_PACE_NS", "STARLING_CELL_W",
                       "STARLING_FONT_DIR", "FLUTTER_DMABUF_SOCKET"]
        let env = ProcessInfo.processInfo.environment
        let set = watched.compactMap { key -> String? in
            guard let v = env[key] else { return nil }
            return "\(key)=\(v.isEmpty ? "(empty)" : v)"
        }
        return set.isEmpty ? "(none of the drawing knobs are set — defaults)"
                           : set.joined(separator: " ")
    }
}

#endif
