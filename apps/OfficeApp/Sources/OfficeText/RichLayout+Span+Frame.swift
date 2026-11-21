// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "Span+Frame": the state of one `_spanStyled` call (once its locals), as a class, so its steps can be methods in separate files.
// A pure move: the bodies are as they were; the locals are these fields.

import Flutter
import FlutterSwiftBridge
import Foundation

final class _StyledFrame {
    unowned let rl: RichLayout
    var ctx: _SpanCtx
    let rawText: Substring
    let base: Int
    let next: Character?
    let symbolsShown: Bool
    var run: CharStyle
    let p: RichParagraph
    let index: Int?
    let document: RichDocument
    let textWidth: Double
    let lead: Double
    let adjust: [Int: Double]
    let held: Set<Int>
    let fitProbe: Bool
    let autoSpaces: ((Int, Double) -> Void)?
    let capped: (Substring, CharStyle, TextStyle) -> [TextSpan]
    let eaFaceOffset: (Character, Character?, Int, Int) -> Int
    let breaksAtQuotes: Bool
    let fullQuotes: Bool
    let hanJoins: Set<Int>
    let heldSpaces: Set<Int>
    let kinsokuOff: Bool
    let koreanSpaces: Set<Int>
    let koreanTokenJoins: Set<Int>
    let lineSize: (size: Double, blank: Bool)?
    let mixedRubyRaise: Double
    let named: RichNamedStyle?
    let openerBeforeLatin: Bool
    let pausesOpenLines: Bool
    let percentStarts: Bool
    let pitch: Double?
    let plainNoLineRules: Bool
    let raised: [Bool]
    let thaiJoins: Set<Int>
    let thaiParagraph: Bool
    let traditionalLists: Bool
    let vertical: Bool
    let wholeRaised: Bool
    let wideIndicWords: [Range<Int>]
    let windowsCounted: Set<Int>
    let mixedLatinFaces: Bool
    let trailingSpaces: Int
    // (locals)
    var hyphenFace: String? = nil
    var bidiLanguage: String = ""
    var wasRightToLeft: Bool = false
    var moved: String? = nil
    var stackHung: String? = nil
    var hung: String? = nil
    var spaceBeforeDanda: Bool = false
    var text0: Substring!
    var text: Substring!
    var latinFace: RichResolvedFace? = nil
    var highFace: RichResolvedFace? = nil
    var hint: String? = nil
    var eaFaceIsLatin: Bool = false
    var eaNamedNone: Bool = false
    var eaUnnamedLetters: Bool = false
    var hinted: Bool = false
    var hAnsiFace: RichResolvedFace? = nil
    var latinDash: Bool = false
    var eastDash: Bool = false
    var em: Double = 0
    var wScale: Double = 0
    var closes: Bool = false
    var lineRulesOff: Bool = false
    var classed: Bool = false
    var narrowLatinInRTL: Bool = false
    var styles: [Int: TextStyle] = [:]
    var ownGridSay: Bool = false
    var runOffGrid: Bool = false
    var cellFix: Double = 0
    var grid: Double? = nil
    var latinCell: Double? = nil
    var latinGrid: Double? = nil
    var ideographGrid: Double? = nil
    var spacing: Double = 0
    var doubles: Bool = false
    var subsetFace: RichResolvedFace? = nil
    var uncovered: (String, Set<UInt32>)? = nil
    var chain: [(family: String, covers: Set<UInt32>?)]? = nil
    var chainAt: Int? = nil
    var cambriaWidth: Double = 0
    var latinShapes: Bool = false
    var tcFit: Bool = false
    var fitGroup: (points: Double, id: String)? = nil
    var fitPitch: Double? = nil
    var fitBusy: Bool = false
    var plainPiece: Bool = false
    var latinNoScale: Bool = false
    var latinFaceNamed: Bool = false
    var fitNone: Bool = false
    var fitLastSingle: Bool = false
    var fitLastEnd: Int = 0
    var kokilaLatin: Bool = false
    var malgunLatin: Bool = false
    var aumsLatin: Bool = false
    var yuOfMissingHangul: Bool = false
    var aumsYuInIndic: Bool = false
    var aumsSpaces: Bool = false
    var mangalLatinSpace: Bool = false
    var utsaahLatin: Bool = false
    var namedFace: String? = nil
    var namedKalimati: Bool = false
    var indic: (face: String, scale: Double)? = nil
    var complexFaceOfRun: RichResolvedFace? = nil
    var joinedFace: RichResolvedFace? = nil
    var complexSpaceFace: RichResolvedFace? = nil
    var notoStyle: TextStyle? = nil
    var segoeStyle: TextStyle? = nil
    var devanagariStyles: [String: TextStyle?] = [:]
    var spans: [TextSpan] = []
    var start: Substring.Index = "".startIndex
    var current: Int? = nil
    var offset: Int = 0
    var i: Substring.Index = "".startIndex
    var compatJoinerAfter: TextStyle? = nil
    var shownCaps: Bool = false
    var ch: Character!
    var after: Substring.Index = "".startIndex
    var following: Character? = nil
    var ea: Bool = false
    var kind: Int = 0
    var insideWide: Bool = false
    var myanmarJoin: Bool = false
    var narrowFamily: String? = nil
    var narrowQuotes: Bool = false
    var quote: Bool = false
    var blank: Double = 0
    var blankShown: Double = 0
    var led: Bool = false
    var extra: Double = 0
    var nbspHAnsi: Bool = false
    var malgunDigit: Bool = false
    var jisLatin1: Bool = false

    init(_ rl: RichLayout, _ ctx: _SpanCtx, _ rawText: Substring, _ run: CharStyle, base: Int, next: Character?, symbolsShown: Bool) {
        self.rl = rl; self.ctx = ctx; self.rawText = rawText; self.run = run; self.base = base; self.next = next; self.symbolsShown = symbolsShown
        self.p = ctx.p
        self.index = ctx.index
        self.document = ctx.document
        self.textWidth = ctx.textWidth
        self.lead = ctx.lead
        self.adjust = ctx.adjust
        self.held = ctx.held
        self.fitProbe = ctx.fitProbe
        self.autoSpaces = ctx.autoSpaces
        self.capped = ctx.capped
        self.eaFaceOffset = ctx.eaFaceOffset
        self.breaksAtQuotes = ctx.breaksAtQuotes
        self.fullQuotes = ctx.fullQuotes
        self.hanJoins = ctx.hanJoins
        self.heldSpaces = ctx.heldSpaces
        self.kinsokuOff = ctx.kinsokuOff
        self.koreanSpaces = ctx.koreanSpaces
        self.koreanTokenJoins = ctx.koreanTokenJoins
        self.lineSize = ctx.lineSize
        self.mixedRubyRaise = ctx.mixedRubyRaise
        self.named = ctx.named
        self.openerBeforeLatin = ctx.openerBeforeLatin
        self.pausesOpenLines = ctx.pausesOpenLines
        self.percentStarts = ctx.percentStarts
        self.pitch = ctx.pitch
        self.plainNoLineRules = ctx.plainNoLineRules
        self.raised = ctx.raised
        self.thaiJoins = ctx.thaiJoins
        self.thaiParagraph = ctx.thaiParagraph
        self.traditionalLists = ctx.traditionalLists
        self.vertical = ctx.vertical
        self.wholeRaised = ctx.wholeRaised
        self.wideIndicWords = ctx.wideIndicWords
        self.windowsCounted = ctx.windowsCounted
        self.mixedLatinFaces = ctx.mixedLatinFaces
        self.trailingSpaces = ctx.trailingSpaces
    }
    var theme: RichTextTheme { rl.theme }
    func eastAsianFaceIsLatin(atOffset o: Int) -> Bool { ctx.eastAsianFaceIsLatin(o) }
    func runHinted(atOffset o: Int) -> Bool { ctx.runHinted(o) }
    var paragraphLatinOwner: String? { ctx.paragraphLatinOwnerFn() }
    // forwarders to RichLayout
    func _spanStyled(_ ctx: inout _SpanCtx, _ rawText: Substring, _ run: CharStyle, at base: Int = 0, next: Character? = nil, symbolsShown: Bool = false) -> [TextSpan] { rl._spanStyled(&ctx, rawText, run, at: base, next: next, symbolsShown: symbolsShown) }
    func _normalChar(_ document: RichDocument) -> CharStyle? { rl._normalChar(document) }
    func _glyphWidth(_ style: TextStyle, _ ch: Character) -> Double { rl._glyphWidth(style, ch) }
    func _px(_ points: Double) -> Double { rl._px(points) }
    func _indicSpaceStyle(base: TextStyle, spaceEm: Double, unit: Double, glyph: String = " ") -> TextStyle { rl._indicSpaceStyle(base: base, spaceEm: spaceEm, unit: unit, glyph: glyph) }
    func _lineJoiner(_ run: CharStyle, _ named: RichNamedStyle?, _ own: TextStyle, _ paragraph: RichParagraphStyle, _ pitch: Double?, _ scale: Double, ascent ems: Double, descent emsDown: Double, spacing: Bool = true, belowOnly: Bool = false, evenExtra: Bool = false) -> TextStyle? { rl._lineJoiner(run, named, own, paragraph, pitch, scale, ascent: ems, descent: emsDown, spacing: spacing, belowOnly: belowOnly, evenExtra: evenExtra) }
    func _clusterFitted(_ w: Substring, base: TextStyle, authored: Double, table: [String: Double], flatScale: Double, conjunctRatio: Double? = 0.85, block: UInt32 = 0x900, lowVowelsZero: Bool = false, spaceMarks: Bool = false) -> (style: TextStyle, flat: TextStyle)? { rl._clusterFitted(w, base: base, authored: authored, table: table, flatScale: flatScale, conjunctRatio: conjunctRatio, block: block, lowVowelsZero: lowVowelsZero, spaceMarks: spaceMarks) }
    func _wordWidth(_ style: TextStyle, _ word: String) -> Double { rl._wordWidth(style, word) }
    func _verticalBody(_ i: Int) -> Bool { rl._verticalBody(i) }
    func _spaceWidth(_ style: TextStyle) -> Double { rl._spaceWidth(style) }
    func _asciiRunInMissingBengaliFace(_ run: CharStyle, _ named: RichNamedStyle?, _ document: RichDocument, _ text: Substring, _ paragraphText: String) -> Bool { rl._asciiRunInMissingBengaliFace(run, named, document, text, paragraphText) }
    func _shonarSpaced(_ w: Substring, base: TextStyle, authored: Double) -> TextStyle? { rl._shonarSpaced(w, base: base, authored: authored) }
    func _isSolaimanLipi(_ run: CharStyle, _ named: RichNamedStyle?, _ document: RichDocument) -> Bool { rl._isSolaimanLipi(run, named, document) }
    func _grid(_ i: Int?, _ document: RichDocument) -> (pitch: Double?, chars: Double?) { rl._grid(i, document) }
    func _yuLatinOfMissingHangulFace(_ run: CharStyle, _ named: RichNamedStyle?, _ document: RichDocument) -> Bool { rl._yuLatinOfMissingHangulFace(run, named, document) }
    func _shonarLatinRunFace(_ run: CharStyle, _ named: RichNamedStyle?, _ document: RichDocument, _ paragraphText: String) -> String? { rl._shonarLatinRunFace(run, named, document, paragraphText) }
    func _pairAdvance(_ style: TextStyle, _ ch: Character, _ next: Character) -> Double { rl._pairAdvance(style, ch, next) }
    var _narrowQuoteMemo: [String: Bool] { get { rl._narrowQuoteMemo } set { rl._narrowQuoteMemo = newValue } }
    func _namedMetricFace(_ run: CharStyle, _ named: RichNamedStyle?, _ document: RichDocument, _ text: Substring) -> String? { rl._namedMetricFace(run, named, document, text) }
    func _kokilaLatinStyle(_ seg: Substring, base: TextStyle, px: Double) -> TextStyle { rl._kokilaLatinStyle(seg, base: base, px: px) }
    var _hyphenShown: [Int: Set<Int>] { get { rl._hyphenShown } set { rl._hyphenShown = newValue } }
    var _hyphenPoints: [Int: Set<Int>] { get { rl._hyphenPoints } set { rl._hyphenPoints = newValue } }
    func _gridCellBase(_ i: Int?, _ document: RichDocument) -> Double? { rl._gridCellBase(i, document) }
    var _yuEndKern: [Int: [Int: Double]] { get { rl._yuEndKern } set { rl._yuEndKern = newValue } }
    var _topLiftBig: Double? { get { rl._topLiftBig } set { rl._topLiftBig = newValue } }
    var _trailCut: [Int: Int] { get { rl._trailCut } set { rl._trailCut = newValue } }
    func _tamilVijaya(_ cs: String?, _ named: RichNamedStyle?, _ document: RichDocument) -> Bool { rl._tamilVijaya(cs, named, document) }
    func _segoeJoiner(_ run: CharStyle, _ named: RichNamedStyle?, _ own: TextStyle, _ paragraph: RichParagraphStyle, _ pitch: Double?, _ scale: Double) -> TextStyle? { rl._segoeJoiner(run, named, own, paragraph, pitch, scale) }
    func _rubyShiftApplies(_ p: RichParagraph, named: RichNamedStyle?, ruby: CharStyle, pitch: Double?) -> Bool { rl._rubyShiftApplies(p, named: named, ruby: ruby, pitch: pitch) }
    func _notoJoiner(_ noto: CharStyle, _ notoStyle: TextStyle, _ run: CharStyle, _ named: RichNamedStyle?, _ own: TextStyle, _ paragraph: RichParagraphStyle, _ pitch: Double?, _ scale: Double) -> TextStyle? { rl._notoJoiner(noto, notoStyle, run, named, own, paragraph, pitch, scale) }
    func _malgunAlternate(_ family: String?, _ document: RichDocument) -> Bool { rl._malgunAlternate(family, document) }
    func _listIndents(_ p: RichParagraph, _ document: RichDocument) -> (left: Double, hanging: Double)? { rl._listIndents(p, document) }
    func _jisLatin1Symbol(_ ch: Character, theme: RichTextTheme, run: CharStyle, named: RichNamedStyle?, document: RichDocument, hint: String?) -> Bool { rl._jisLatin1Symbol(ch, theme: theme, run: run, named: named, document: document, hint: hint) }
    var _hanChunks: [Int: Set<Int>] { get { rl._hanChunks } set { rl._hanChunks = newValue } }
    func _glyphCount(_ style: TextStyle, _ ch: Character) -> Int { rl._glyphCount(style, ch) }
    func _closesUpMarks(_ run: CharStyle, _ named: RichNamedStyle?, _ document: RichDocument) -> Bool { rl._closesUpMarks(run, named, document) }
    func gridPitchIsNil(_ pitch: Double?) -> Bool { rl.gridPitchIsNil(pitch) }
    var scale: Double { get { rl.scale } set { rl.scale = newValue } }
    var fontScale: Double { get { rl.fontScale } set { rl.fontScale = newValue } }

}
