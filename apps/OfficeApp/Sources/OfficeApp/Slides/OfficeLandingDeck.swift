// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation

/// The website is an ordinary, editable Slides deck. Generate wide and portrait
/// PPTX files with --landing-deck; the browser reads them through Pptx.read.
enum OfficeLandingDeck {
    static func make(portrait: Bool = false) -> DeckController {
        let deck = DeckController()
        let w = portrait ? 450.0 : 1280.0
        deck.setSlideSize(Size(w, 720))
        let blue = Color(0xFF2449DF), ink = Color(0xFF132442)
        let white = Color(0xFFFFFFFF), muted = Color(0xFF536782)
        let margin = portrait ? 32.0 : 72.0
        func shape(_ rect: Rect, _ fill: Color, radius: Bool = false, rotation: Double = 0) {
            let s = deck.addShape(radius ? .roundRect : .rect)
            s.frame = rect; s.fill = fill; s.fillScheme = nil; s.outline = nil; s.rotation = rotation
        }
        func text(_ value: String, _ x: Double, _ y: Double, _ width: Double,
                  _ size: Double, _ color: Color = Color(0xFF132442), bold: Bool = false) {
            let s = deck.addTextBox(at: Rect.fromLTWH(x, y, width, 720 - y))
            s.insets = .zero
            s.textTheme = RichTextTheme(fontFamily: "Calibri", fontSize: size, textColor: color)
            s.textTheme?.fontFamilyResolver = OfficeFonts.substitute
            let paragraphs = value.split(separator: "\n", omittingEmptySubsequences: false).map { line -> RichParagraph in
                var p = RichParagraph(text: String(line), style: RichParagraphStyle(spaceAfter: 0, lineSpacing: 1.0))
                if bold { p.applyStyle(0 ..< p.length) { $0.bold = true } }
                return p
            }
            s.text?.load(RichDocument(paragraphs: paragraphs))
        }
        func slide(_ color: Color, first: Bool = false) {
            if !first { _ = deck.addSlide(.blank) }
            deck.currentSlide.shapes.removeAll()
            deck.currentSlide.background = SlideFill(color: color)
            deck.currentSlide.transition = SlideTransition(kind: .fade, duration: 0.25)
        }
        func eyebrow(_ value: String, _ color: Color = Color(0xFF2449DF)) {
            text(value, margin, 40, w - margin * 2, portrait ? 13 : 16, color, bold: true)
        }
        slide(blue, first: true)
        eyebrow("STARLING OFFICE  /  OPEN SOURCE", white)
        text("Big ideas.\nStart here.", margin, portrait ? 112 : 130,
             portrait ? 400 : 730, portrait ? 72 : 112, white, bold: true)
        text("Writer. Slides. Sheets.\nAn open source office suite.", margin, portrait ? 318 : 418,
             portrait ? 380 : 640, portrait ? 23 : 30, white)
        let apps: [(String, String, String, Color)] = [
            ("W", "Writer", "Documents", blue),
            ("S", "Slides", "Presentations", Color(0xFFE45B35)),
            ("#", "Sheets", "Spreadsheets", Color(0xFF13794D)),
        ]
        for (i, app) in apps.enumerated() {
            let x = portrait ? 32 + Double(i) * 132 : 870
            let y = portrait ? 480.0 : 164 + Double(i) * 137
            let width = portrait ? 122.0 : 338.0
            shape(Rect.fromLTWH(x, y, width, portrait ? 156 : 114), white, radius: true)
            shape(Rect.fromLTWH(x + 14, y + 14, portrait ? 42 : 66, portrait ? 42 : 86), app.3, radius: true)
            text(app.0, x + (portrait ? 23 : 29), y + (portrait ? 16 : 28), 56,
                 portrait ? 29 : 45, white, bold: true)
            text(app.1, x + (portrait ? 14 : 99), y + (portrait ? 73 : 23), portrait ? 100 : 220,
                 portrait ? 24 : 33, ink, bold: true)
            text(app.2, x + (portrait ? 14 : 99), y + (portrait ? 115 : 68), portrait ? 100 : 220,
                 portrait ? 13 : 19, muted)
        }
        text("THREE APPS. ONE OPEN SOURCE SUITE.", margin, portrait ? 666 : 624,
             w - margin * 2, portrait ? 13 : 18, white, bold: true)

        slide(Color(0xFFF7F9FF))
        eyebrow("01  /  MEET WRITER")
        text("Write something\ngreat.", margin, portrait ? 94 : 126,
             portrait ? 400 : 620, portrait ? 49 : 76, ink, bold: true)
        text("A familiar ribbon. A clean page.\nRoom for your next big idea.", margin, portrait ? 570 : 342,
             portrait ? 390 : 485, portrait ? 20 : 27, muted)
        // An editable document illustration, like the other app panels.
        let dx = portrait ? 32.0 : 660.0, dy = portrait ? 284.0 : 180.0
        let documentScale = (portrait ? 386.0 : 548.0) / 548
        shape(Rect.fromLTWH(dx, dy, 548 * documentScale, 350 * documentScale), white, radius: true)
        text("PROJECT NOTES", dx + 35 * documentScale, dy + 27 * documentScale,
             478 * documentScale, 15 * documentScale, blue, bold: true)
        text("Your next big idea.", dx + 35 * documentScale, dy + 65 * documentScale,
             478 * documentScale, 36 * documentScale, ink, bold: true)
        shape(Rect.fromLTWH(dx + 35 * documentScale, dy + 125 * documentScale,
                           478 * documentScale, 3 * documentScale), blue)
        text("Start with a thought.\nGive it room to grow.", dx + 35 * documentScale,
             dy + 153 * documentScale, 478 * documentScale, 25 * documentScale, muted)
        for (i, width) in [430.0, 478.0, 330.0].enumerated() {
            shape(Rect.fromLTWH(dx + 35 * documentScale,
                               dy + (250 + Double(i) * 24) * documentScale,
                               width * documentScale, 8 * documentScale), Color(0xFFE3E9FA), radius: true)
        }
        text("DOCX  ·  RTF  ·  MARKDOWN  ·  TEXT", margin, portrait ? 654 : 625,
             w - margin * 2, portrait ? 13 : 18, blue, bold: true)
        if !portrait { text("Fonts, styles, tables, pictures.\nThe tools to make it yours.", margin, 466, 490, 25, muted) }

        slide(Color(0xFFFFF3ED))
        let coral = Color(0xFFC74724)
        eyebrow("02  /  MEET SLIDES", coral)
        text("Make your\npoint.", margin, portrait ? 94 : 126,
             portrait ? 400 : 620, portrait ? 66 : 88, ink, bold: true)
        text("Build a deck. Tell your story.\nPresent it with confidence.", margin, portrait ? 570 : 342,
             portrait ? 390 : 485, portrait ? 21 : 27, muted)
        // An editable presentation graphic, drawn by Slides itself.
        let sx = portrait ? 32.0 : 660.0, sy = portrait ? 284.0 : 180.0
        let scale = (portrait ? 386.0 : 548.0) / 548
        shape(Rect.fromLTWH(sx, sy, 548 * scale, 350 * scale), white, radius: true)
        text("A clear idea.", sx + 35 * scale, sy + 27 * scale, 475 * scale, 42 * scale, ink, bold: true)
        text("MAKE EVERY SLIDE COUNT", sx + 35 * scale, sy + 91 * scale, 475 * scale, 15 * scale, coral, bold: true)
        for (i, height) in [70.0, 113.0, 164.0].enumerated() {
            let x = sx + (42 + Double(i) * 92) * scale
            shape(Rect.fromLTWH(x, sy + (294 - height) * scale,  62 * scale, height * scale),
                  [Color(0xFFFFCBB8), Color(0xFFF2906D), coral][i], radius: true)
        }
        for (i, value) in ["Clear message", "Strong visuals", "Your next big idea"].enumerated() {
            text(value, sx + 344 * scale, sy + (170 + Double(i) * 43) * scale,
                 185 * scale, 18 * scale, muted, bold: i == 0)
        }
        if !portrait { text("Themes, charts, and animations.\nSpeaker notes for your moment.", margin, 466, 490, 25, muted) }
        text("PPTX  ·  THEMES  ·  CHARTS  ·  ANIMATIONS", margin, 654, w - margin * 2,
             portrait ? 12 : 18, coral, bold: true)

        slide(Color(0xFFEDF9F2))
        let green = Color(0xFF13794D)
        eyebrow("03  /  MEET SHEETS", green)
        text("Let the numbers\ntell the story.", margin, portrait ? 94 : 126,
             portrait ? 400 : 610, portrait ? 48 : 72, ink, bold: true)
        text("Organize your data.\nTurn formulas into answers.", margin, portrait ? 570 : 342,
             portrait ? 390 : 485, portrait ? 22 : 27, muted)
        // A small workbook example made from ordinary editable slide shapes.
        let gx = portrait ? 32.0 : 654.0, gy = portrait ? 286.0 : 176.0
        let unit = (portrait ? 386.0 : 554.0) / 554
        shape(Rect.fromLTWH(gx, gy, 554 * unit, 350 * unit), white, radius: true)
        shape(Rect.fromLTWH(gx + 16 * unit, gy + 16 * unit, 522 * unit, 46 * unit), Color(0xFFE3F3E9), radius: true)
        text("fx    =SUM(C2:C4)", gx + 32 * unit, gy + 24 * unit, 490 * unit, 22 * unit, green)
        let cells = [["Project", "Budget", "Actual"], ["Design", "2,400", "2,100"],
                     ["Build", "6,800", "6,500"], ["Launch", "1,800", "1,400"],
                     ["Total", "11,000", "10,000"]]
        for (row, values) in cells.enumerated() {
            let y = gy + (82 + Double(row) * 49) * unit
            shape(Rect.fromLTWH(gx + 16 * unit, y, 522 * unit, 48 * unit),
                  row == 4 ? green : row == 0 ? Color(0xFFE3F3E9) : Color(0xFFF6FAF7))
            for (col, value) in values.enumerated() {
                text(value, gx + (32 + Double(col) * 174) * unit, y + 8 * unit, 166 * unit,
                     22 * unit, row == 4 ? white : ink, bold: row == 0 || row == 4)
            }
        }
        if !portrait { text("Formulas, tables, and filters.\nKeep the whole picture in view.", margin, 466, 490, 25, muted) }
        text("XLSX  ·  CSV  ·  FORMULAS  ·  FILTERS", margin, 654, w - margin * 2,
             portrait ? 13 : 18, green, bold: true)

        slide(Color(0xFFEDF2FF))
        eyebrow("04  /  SIX PLATFORMS. ONE AMBITION.")
        text("Your office.\nEverywhere.", margin, portrait ? 91 : 148,
             portrait ? 400 : 570, portrait ? 59 : 86, ink, bold: true)
        if !portrait { text("At a desk. On the move.\nIn a browser.", margin, 391, 500, 30, muted) }
        let names = ["macOS", "Windows", "Linux", "iOS", "Android", "Web"]
        for (i, name) in names.enumerated() {
            let x = (portrait ? 32.0 : 657.0) + Double(i % 2) * (portrait ? 198 : 272)
            let y = (portrait ? 313.0 : 151.0) + Double(i / 2) * (portrait ? 99 : 143)
            let width = portrait ? 188.0 : 249.0
            let live = name == "Web"
            shape(Rect.fromLTWH(x, y, width, portrait ? 87 : 122), live ? blue : white, radius: true)
            text(name, x + 18, y + 12, width - 26, portrait ? 25 : 33, live ? white : ink, bold: true)
            text(live ? "In your browser" : "Planned", x + 18, y + (portrait ? 50 : 71), width - 26,
                 portrait ? 15 : 19, live ? white : muted)
        }
        text("Documents. Presentations. Spreadsheets.\nAcross your devices. Built in the open.", margin,
             portrait ? 642 : 626, w - margin * 2, portrait ? 16 : 21, muted)

        slide(Color(0xFF101D37))
        eyebrow("05  /  OPEN SOURCE. FROM THE START.", Color(0xFFA8B9FF))
        text(portrait ? "Open code.\nShared\nambition." : "Open code.\nShared ambition.", margin,
             portrait ? 112 : 140, portrait ? 400 : 1040, portrait ? 67 : 98, white, bold: true)
        text("Read the code. Follow the progress.\nHelp shape what comes next.", margin, portrait ? 408 : 410,
             w - margin * 2, portrait ? 23 : 31, Color(0xFFCCD6EE))
        text("github.com/starling-build/starling", margin, portrait ? 494 : 510,
             w - margin * 2, portrait ? 18 : 28, white, bold: true)
        text("Built on the Starling SDK.\nApache 2.0 licensed.", margin, portrait ? 538 : 570,
             w - margin * 2, portrait ? 20 : 24, Color(0xFFA8B9FF))
        text("WRITER  ·  SLIDES  ·  SHEETS", margin, 661, w - margin * 2, portrait ? 13 : 16,
             Color(0xFFA8B9FF), bold: true)
        deck.select(0)
        return deck
    }
}
