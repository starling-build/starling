// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "Paragraph+Frame": the state of one `_layoutParagraphBody` call (its locals), as a class, so its steps can be methods in separate files.
// A pure move, scripted (test/tools/split-paragraph.py): the bodies are as they were; the function's locals are the fields of `_ParaFrame`.

import Flutter
import FlutterSwiftBridge
import Foundation

final class _ParaFrame {
    unowned let rl: RichLayout
    let i: Int
    let document: RichDocument
    var p: RichParagraph
    var _style_: (RichParagraphStyle)?
    var style: RichParagraphStyle { get { _style_.unsafelyUnwrapped } set { _style_ = newValue } _modify { yield &_style_! } }
    var wordList: (left: Double, first: Double, format: ListLevelFormat?)?
    var _sides_: ((left: Double, right: Double))?
    var sides: (left: Double, right: Double) { get { _sides_.unsafelyUnwrapped } set { _sides_ = newValue } _modify { yield &_sides_! } }
    var listLeft: Double?
    var _ownLeft_: (Double)?
    var ownLeft: Double { get { _ownLeft_.unsafelyUnwrapped } set { _ownLeft_ = newValue } _modify { yield &_ownLeft_! } }
    var _left_: (Double)?
    var left: Double { get { _left_.unsafelyUnwrapped } set { _left_ = newValue } _modify { yield &_left_! } }
    var _right_: (Double)?
    var right: Double { get { _right_.unsafelyUnwrapped } set { _right_ = newValue } _modify { yield &_right_! } }
    var _width_: (Double)?
    var width: Double { get { _width_.unsafelyUnwrapped } set { _width_ = newValue } _modify { yield &_width_! } }
    var _gridCut_: (Double)?
    var gridCut: Double { get { _gridCut_.unsafelyUnwrapped } set { _gridCut_ = newValue } _modify { yield &_gridCut_! } }
    var frameLeft: Double?
    var _notBesideInText_: (Bool)?
    var notBesideInText: Bool { get { _notBesideInText_.unsafelyUnwrapped } set { _notBesideInText_ = newValue } _modify { yield &_notBesideInText_! } }
    var _textWidth_: (Double)?
    var textWidth: Double { get { _textWidth_.unsafelyUnwrapped } set { _textWidth_ = newValue } _modify { yield &_textWidth_! } }
    var _lead_: (Double)?
    var lead: Double { get { _lead_.unsafelyUnwrapped } set { _lead_ = newValue } _modify { yield &_lead_! } }
    var _tabs_: ([Int : Double])?
    var tabs: [Int : Double] { get { _tabs_.unsafelyUnwrapped } set { _tabs_ = newValue } _modify { yield &_tabs_! } }
    var _hangs_: ([Int : Double])?
    var hangs: [Int : Double] { get { _hangs_.unsafelyUnwrapped } set { _hangs_ = newValue } _modify { yield &_hangs_! } }
    var _runsPast_: (Set<Int>)?
    var runsPast: Set<Int> { get { _runsPast_.unsafelyUnwrapped } set { _runsPast_ = newValue } _modify { yield &_runsPast_! } }
    var _clampedStops_: (Set<Double>)?
    var clampedStops: Set<Double> { get { _clampedStops_.unsafelyUnwrapped } set { _clampedStops_ = newValue } _modify { yield &_clampedStops_! } }
    var _beyond_: ([Int : Double])?
    var beyond: [Int : Double] { get { _beyond_.unsafelyUnwrapped } set { _beyond_ = newValue } _modify { yield &_beyond_! } }
    var _pictureTabs_: (Bool)?
    var pictureTabs: Bool { get { _pictureTabs_.unsafelyUnwrapped } set { _pictureTabs_ = newValue } _modify { yield &_pictureTabs_! } }
    var _atMargin_: (Set<Int>)?
    var atMargin: Set<Int> { get { _atMargin_.unsafelyUnwrapped } set { _atMargin_ = newValue } _modify { yield &_atMargin_! } }
    var _leftTabs_: (Set<Int>)?
    var leftTabs: Set<Int> { get { _leftTabs_.unsafelyUnwrapped } set { _leftTabs_ = newValue } _modify { yield &_leftTabs_! } }
    var _lonePastTabs_: (Set<Int>)?
    var lonePastTabs: Set<Int> { get { _lonePastTabs_.unsafelyUnwrapped } set { _lonePastTabs_ = newValue } _modify { yield &_lonePastTabs_! } }
    var _beforeTabs_: (Set<Int>)?
    var beforeTabs: Set<Int> { get { _beforeTabs_.unsafelyUnwrapped } set { _beforeTabs_ = newValue } _modify { yield &_beforeTabs_! } }
    var _tabWindows_: ([LineIndent])?
    var tabWindows: [LineIndent] { get { _tabWindows_.unsafelyUnwrapped } set { _tabWindows_ = newValue } _modify { yield &_tabWindows_! } }
    var _forcedWraps_: (Set<Int>)?
    var forcedWraps: Set<Int> { get { _forcedWraps_.unsafelyUnwrapped } set { _forcedWraps_ = newValue } _modify { yield &_forcedWraps_! } }
    var _afterTabWraps_: (Set<Int>)?
    var afterTabWraps: Set<Int> { get { _afterTabWraps_.unsafelyUnwrapped } set { _afterTabWraps_ = newValue } _modify { yield &_afterTabWraps_! } }
    var _leadTab_: (Bool)?
    var leadTab: Bool { get { _leadTab_.unsafelyUnwrapped } set { _leadTab_ = newValue } _modify { yield &_leadTab_! } }
    var _underHeld_: (Set<Int>)?
    var underHeld: Set<Int> { get { _underHeld_.unsafelyUnwrapped } set { _underHeld_ = newValue } _modify { yield &_underHeld_! } }
    var _tabRuns_: (Set<Int>)?
    var tabRuns: Set<Int> { get { _tabRuns_.unsafelyUnwrapped } set { _tabRuns_ = newValue } _modify { yield &_tabRuns_! } }
    var _tabsHeld_: (Set<Int>)?
    var tabsHeld: Set<Int> { get { _tabsHeld_.unsafelyUnwrapped } set { _tabsHeld_ = newValue } _modify { yield &_tabsHeld_! } }
    var _tieSlack_: (Double)?
    var tieSlack: Double { get { _tieSlack_.unsafelyUnwrapped } set { _tieSlack_ = newValue } _modify { yield &_tieSlack_! } }
    var _tieShort_: ((first: Bool, rest: Bool))?
    var tieShort: (first: Bool, rest: Bool) { get { _tieShort_.unsafelyUnwrapped } set { _tieShort_ = newValue } _modify { yield &_tieShort_! } }
    var _besideLineIndents_: ([LineIndent])?
    var besideLineIndents: [LineIndent] { get { _besideLineIndents_.unsafelyUnwrapped } set { _besideLineIndents_ = newValue } _modify { yield &_besideLineIndents_! } }
    var _equationLinesGrowAfterLayout_: (Bool)?
    var equationLinesGrowAfterLayout: Bool { get { _equationLinesGrowAfterLayout_.unsafelyUnwrapped } set { _equationLinesGrowAfterLayout_ = newValue } _modify { yield &_equationLinesGrowAfterLayout_! } }
    var _besideIndent_: (Double)?
    var besideIndent: Double { get { _besideIndent_.unsafelyUnwrapped } set { _besideIndent_ = newValue } _modify { yield &_besideIndent_! } }
    var _besideRight_: (Bool)?
    var besideRight: Bool { get { _besideRight_.unsafelyUnwrapped } set { _besideRight_ = newValue } _modify { yield &_besideRight_! } }
    var besideLeftRoom: Double?
    var besideBand: (top: Double, bottom: Double)?
    var colWrapBoxes: [RichLayout.ColWrapBox]?
    var _span_: (TextSpan)?
    var span: TextSpan { get { _span_.unsafelyUnwrapped } set { _span_ = newValue } _modify { yield &_span_! } }
    var _inline_: ([(image: ImageAttachment?, dimensions: PlaceholderDimensions)])?
    var inline: [(image: ImageAttachment?, dimensions: PlaceholderDimensions)] { get { _inline_.unsafelyUnwrapped } set { _inline_ = newValue } _modify { yield &_inline_! } }
    var _inserts_: ([Int])?
    var inserts: [Int] { get { _inserts_.unsafelyUnwrapped } set { _inserts_ = newValue } _modify { yield &_inserts_! } }
    var _align_: (TextAlign)?
    var align: TextAlign { get { _align_.unsafelyUnwrapped } set { _align_ = newValue } _modify { yield &_align_! } }
    var _thaiDistributed_: (Bool)?
    var thaiDistributed: Bool { get { _thaiDistributed_.unsafelyUnwrapped } set { _thaiDistributed_ = newValue } _modify { yield &_thaiDistributed_! } }
    var _picturesInLine_: (Bool)?
    var picturesInLine: Bool { get { _picturesInLine_.unsafelyUnwrapped } set { _picturesInLine_ = newValue } _modify { yield &_picturesInLine_! } }
    var _spacedOver_: (Bool)?
    var spacedOver: Bool { get { _spacedOver_.unsafelyUnwrapped } set { _spacedOver_ = newValue } _modify { yield &_spacedOver_! } }
    var _thaiNear_: (Bool)?
    var thaiNear: Bool { get { _thaiNear_.unsafelyUnwrapped } set { _thaiNear_ = newValue } _modify { yield &_thaiNear_! } }
    var _numberLift_: (Double)?
    var numberLift: Double { get { _numberLift_.unsafelyUnwrapped } set { _numberLift_ = newValue } _modify { yield &_numberLift_! } }
    var _painter_: (TextPainter)?
    var painter: TextPainter { get { _painter_.unsafelyUnwrapped } set { _painter_ = newValue } _modify { yield &_painter_! } }
    var _fit_: ([Int : Double])?
    var fit: [Int : Double] { get { _fit_.unsafelyUnwrapped } set { _fit_ = newValue } _modify { yield &_fit_! } }
    var _held_: (Set<Int>)?
    var held: Set<Int> { get { _held_.unsafelyUnwrapped } set { _held_ = newValue } _modify { yield &_held_! } }
    var _bareBreak_: (Bool)?
    var bareBreak: Bool { get { _bareBreak_.unsafelyUnwrapped } set { _bareBreak_ = newValue } _modify { yield &_bareBreak_! } }
    var _bTop_: (Double)?
    var bTop: Double { get { _bTop_.unsafelyUnwrapped } set { _bTop_ = newValue } _modify { yield &_bTop_! } }
    var _bBottom_: (Double)?
    var bBottom: Double { get { _bBottom_.unsafelyUnwrapped } set { _bBottom_ = newValue } _modify { yield &_bBottom_! } }
    var _spacing_: ((before: Double, after: Double))?
    var spacing: (before: Double, after: Double) { get { _spacing_.unsafelyUnwrapped } set { _spacing_ = newValue } _modify { yield &_spacing_! } }
    var _frameGap_: (Double)?
    var frameGap: Double { get { _frameGap_.unsafelyUnwrapped } set { _frameGap_ = newValue } _modify { yield &_frameGap_! } }
    var _cellBreakLead_: (Bool)?
    var cellBreakLead: Bool { get { _cellBreakLead_.unsafelyUnwrapped } set { _cellBreakLead_ = newValue } _modify { yield &_cellBreakLead_! } }
    var _topRaise_: (Double)?
    var topRaise: Double { get { _topRaise_.unsafelyUnwrapped } set { _topRaise_ = newValue } _modify { yield &_topRaise_! } }
    var _before_: (Double)?
    var before: Double { get { _before_.unsafelyUnwrapped } set { _before_ = newValue } _modify { yield &_before_! } }
    var _after_: (Double)?
    var after: Double { get { _after_.unsafelyUnwrapped } set { _after_ = newValue } _modify { yield &_after_! } }
    var _segoeLift_: (Double)?
    var segoeLift: Double { get { _segoeLift_.unsafelyUnwrapped } set { _segoeLift_ = newValue } _modify { yield &_segoeLift_! } }
    var _chainFaceLine_: (Bool)?
    var chainFaceLine: Bool { get { _chainFaceLine_.unsafelyUnwrapped } set { _chainFaceLine_ = newValue } _modify { yield &_chainFaceLine_! } }
    var _scriptsOnly_: (Bool)?
    var scriptsOnly: Bool { get { _scriptsOnly_.unsafelyUnwrapped } set { _scriptsOnly_ = newValue } _modify { yield &_scriptsOnly_! } }
    var _mixedSizes_: (Bool)?
    var mixedSizes: Bool { get { _mixedSizes_.unsafelyUnwrapped } set { _mixedSizes_ = newValue } _modify { yield &_mixedSizes_! } }
    var _latinFirstLine_: (Bool)?
    var latinFirstLine: Bool { get { _latinFirstLine_.unsafelyUnwrapped } set { _latinFirstLine_ = newValue } _modify { yield &_latinFirstLine_! } }
    var _w2Done_: (Bool)?
    var w2Done: Bool { get { _w2Done_.unsafelyUnwrapped } set { _w2Done_ = newValue } _modify { yield &_w2Done_! } }
    var _w2Trim_: (Double)?
    var w2Trim: Double { get { _w2Trim_.unsafelyUnwrapped } set { _w2Trim_ = newValue } _modify { yield &_w2Trim_! } }
    var keepClear: (top: Double, bottom: Double)?
    var _wholePitchEquation_: (Bool)?
    var wholePitchEquation: Bool { get { _wholePitchEquation_.unsafelyUnwrapped } set { _wholePitchEquation_ = newValue } _modify { yield &_wholePitchEquation_! } }
    var _lowTop_: (Bool)?
    var lowTop: Bool { get { _lowTop_.unsafelyUnwrapped } set { _lowTop_ = newValue } _modify { yield &_lowTop_! } }
    var lowNamed: Double?
    var _push_: (Double)?
    var push: Double { get { _push_.unsafelyUnwrapped } set { _push_ = newValue } _modify { yield &_push_! } }
    var _firstLine_: (() -> (top: Double, line: Double)?)?
    var firstLine: () -> (top: Double, line: Double)? { get { _firstLine_.unsafelyUnwrapped } set { _firstLine_ = newValue } _modify { yield &_firstLine_! } }
    var _lineEndsAbove_: ((Double) -> Bool)?
    var lineEndsAbove: (Double) -> Bool { get { _lineEndsAbove_.unsafelyUnwrapped } set { _lineEndsAbove_ = newValue } _modify { yield &_lineEndsAbove_! } }
    var _pushUnder_: ((Double) -> Double)?
    var pushUnder: (Double) -> Double { get { _pushUnder_.unsafelyUnwrapped } set { _pushUnder_ = newValue } _modify { yield &_pushUnder_! } }
    var _headerStepped_: (Bool)?
    var headerStepped: Bool { get { _headerStepped_.unsafelyUnwrapped } set { _headerStepped_ = newValue } _modify { yield &_headerStepped_! } }
    var _bodyHeight_: (Double)?
    var bodyHeight: Double { get { _bodyHeight_.unsafelyUnwrapped } set { _bodyHeight_ = newValue } _modify { yield &_bodyHeight_! } }
    var _spacesOnly_: (Bool)?
    var spacesOnly: Bool { get { _spacesOnly_.unsafelyUnwrapped } set { _spacesOnly_ = newValue } _modify { yield &_spacesOnly_! } }
    var _combined_: (Bool)?
    var combined: Bool { get { _combined_.unsafelyUnwrapped } set { _combined_ = newValue } _modify { yield &_combined_! } }
    var _inLine_: (Bool)?
    var inLine: Bool { get { _inLine_.unsafelyUnwrapped } set { _inLine_ = newValue } _modify { yield &_inLine_! } }
    var _total_: (Double)?
    var total: Double { get { _total_.unsafelyUnwrapped } set { _total_ = newValue } _modify { yield &_total_! } }
    var _onlyFloats_: (Bool)?
    var onlyFloats: Bool { get { _onlyFloats_.unsafelyUnwrapped } set { _onlyFloats_ = newValue } _modify { yield &_onlyFloats_! } }

    init(_ rl: RichLayout, _ i: Int, _ p: RichParagraph, _ document: RichDocument) {
        self.rl = rl; self.i = i; self.p = p; self.document = document
    }

    func go() {
        c0()
        c1()
        c2()
        c3()
        c4()
        c5()
        c6()
        c7()
    }
}

extension _ParaFrame {
// FWD-BEGIN
    typealias _HeaderFooter = RichLayout._HeaderFooter
    typealias _CellGeo = RichLayout._CellGeo
    typealias _OffsetMap = RichLayout._OffsetMap
    typealias _PairedLines = RichLayout._PairedLines
    func _asciiRunInMissingBengaliFace(_ a0: CharStyle, _ a1: RichNamedStyle?, _ a2: RichDocument, _ a3: Substring, _ a4: String) -> Bool { rl._asciiRunInMissingBengaliFace(a0, a1, a2, a3, a4) }
    func _atPageTopNegativeOffset(_ a0: Int, _ a1: ImageAttachment) -> Bool { rl._atPageTopNegativeOffset(a0, a1) }
    var _bandCap: [Int : Double] { get { rl._bandCap } set { rl._bandCap = newValue } }
    func _besideBand(_ a0: Int, _ a1: RichDocument) -> (top: Double, bottom: Double)? { rl._besideBand(a0, a1) }
    var _besideBoxes: [Int : [(top: Double, bottom: Double, left: Double, right: Double)]] { get { rl._besideBoxes } set { rl._besideBoxes = newValue } }
    func _besideIndent(_ a0: Int, _ a1: RichParagraph, _ a2: RichDocument, table a3: String? = nil) -> (indent: Double, right: Bool)? { rl._besideIndent(a0, a1, a2, table: a3) }
    var _besideIndentOnTop: Set<Int> { get { rl._besideIndentOnTop } set { rl._besideIndentOnTop = newValue } }
    var _besideLabelShift: [Int : Double] { get { rl._besideLabelShift } set { rl._besideLabelShift = newValue } }
    var _besideLead: [Double] { get { rl._besideLead } set { rl._besideLead = newValue } }
    var _besideLeftAt: [Int : (Double, Double) -> Double] { get { rl._besideLeftAt } set { rl._besideLeftAt = newValue } }
    var _besideListEarlier: Set<Int> { get { rl._besideListEarlier } set { rl._besideListEarlier = newValue } }
    var _besideMoreBands: [Int : [(top: Double, bottom: Double)]] { get { rl._besideMoreBands } set { rl._besideMoreBands = newValue } }
    func _besideOwn(_ a0: Int, _ a1: RichParagraph, _ a2: RichDocument) -> (indent: Double, band: (top: Double, bottom: Double), right: Bool, leftRoom: Double?)? { rl._besideOwn(a0, a1, a2) }
    var _besidePending: Set<Int> { get { rl._besidePending } set { rl._besidePending = newValue } }
    var _besideRightAt: [Int : (Double, Double) -> Double] { get { rl._besideRightAt } set { rl._besideRightAt = newValue } }
    var _besideRightSide: [Bool] { get { rl._besideRightSide } set { rl._besideRightSide = newValue } }
    var _besideSeq: [Int : [RichLayout.ColWrapBox]] { get { rl._besideSeq } set { rl._besideSeq = newValue } }
    var _besideStartAt: [Int : (Double, Double) -> Double] { get { rl._besideStartAt } set { rl._besideStartAt = newValue } }
    var _besideStartLeft: [Int : (indent: Double, band: (top: Double, bottom: Double))] { get { rl._besideStartLeft } set { rl._besideStartLeft = newValue } }
    var _besideTightTop: [Int : Double] { get { rl._besideTightTop } set { rl._besideTightTop = newValue } }
    func _bodyBoxHeight(_ a0: ImageAttachment, _ a1: RichDocument) -> Double { rl._bodyBoxHeight(a0, a1) }
    func _bordersJoin(_ a0: Int, _ a1: Int, _ a2: RichDocument) -> Bool { rl._bordersJoin(a0, a1, a2) }
    var _boxFirstLineShift: [Double] { get { rl._boxFirstLineShift } set { rl._boxFirstLineShift = newValue } }
    func _cellInsets(_ a0: String, _ a1: RichDocument) -> (top: Double, left: Double, bottom: Double, right: Double) { rl._cellInsets(a0, a1) }
    var _cells: [RichLayout._CellGeo?] { get { rl._cells } set { rl._cells = newValue } }
    var _clearBand: [Int : (top: Double, bottom: Double)] { get { rl._clearBand } set { rl._clearBand = newValue } }
    var _colWrap: [Int : [RichLayout.ColWrapBox]] { get { rl._colWrap } set { rl._colWrap = newValue } }
    var _columnWidths: [String : [Double]] { get { rl._columnWidths } set { rl._columnWidths = newValue } }
    var _columns: Int { get { rl._columns } }
    func _eastDashLeadStyle(_ a0: CharStyle, named a1: RichNamedStyle?) -> CharStyle? { rl._eastDashLeadStyle(a0, named: a1) }
    func _edgeShift(_ a0: String, _ a1: RichDocument) -> Double { rl._edgeShift(a0, a1) }
    func _emptyBreakFragment(_ a0: Int, _ a1: RichDocument) -> Bool { rl._emptyBreakFragment(a0, a1) }
    func _ensureDecoded(_ a0: ImageAttachment)  { rl._ensureDecoded(a0) }
    func _equationsAfterFirstLine(_ a0: TextSpan, _ a1: [PlaceholderDimensions], align a2: TextAlign, rtl a3: Bool, width a4: Double, indents a5: [LineIndent]) -> Bool { rl._equationsAfterFirstLine(a0, a1, align: a2, rtl: a3, width: a4, indents: a5) }
    func _equationsWithinStrut(_ a0: TextSpan, _ a1: [PlaceholderDimensions], whole a2: [Double], near a3: Bool, wide a4: Bool, multiple a5: Double) -> Bool { rl._equationsWithinStrut(a0, a1, whole: a2, near: a3, wide: a4, multiple: a5) }
    func _firstLineGridHalf(_ a0: Int, _ a1: RichDocument) -> Double { rl._firstLineGridHalf(a0, a1) }
    func _firstLineHoldsMangalMark(_ a0: RichParagraph, painter a1: TextPainter, lead a2: Int, named a3: RichNamedStyle?, document a4: RichDocument) -> Bool { rl._firstLineHoldsMangalMark(a0, painter: a1, lead: a2, named: a3, document: a4) }
    var _firstLineLift: [Double] { get { rl._firstLineLift } set { rl._firstLineLift = newValue } }
    func _firstTextRun(_ a0: RichParagraph) -> Run? { rl._firstTextRun(a0) }
    func _fitEastAsianLines(_ a0: RichParagraph, at a1: Int, _ a2: RichDocument, textWidth a3: Double, first a4: TextPainter, leadWidth a5: Double, tabs a6: [Int: Double] = [:], leftTabs a7: Set<Int> = [], runsPast a8: Set<Int> = [], beyond a9: [Int: Double] = [:], tieShort a10: (first: Bool, rest: Bool) = (false, false), lineIndents a11: [LineIndent] = []) -> [Int: Double] { rl._fitEastAsianLines(a0, at: a1, a2, textWidth: a3, first: a4, leadWidth: a5, tabs: a6, leftTabs: a7, runsPast: a8, beyond: a9, tieShort: a10, lineIndents: a11) }
    var _fixedTextFrame: (left: Double, right: Double)? { get { rl._fixedTextFrame } set { rl._fixedTextFrame = newValue } }
    var _floatImages: [ImageAttachment?] { get { rl._floatImages } set { rl._floatImages = newValue } }
    var _floatPush: [Double] { get { rl._floatPush } set { rl._floatPush = newValue } }
    var _floatTight: [Bool] { get { rl._floatTight } set { rl._floatTight = newValue } }
    var _floats: [ImageFloat?] { get { rl._floats } set { rl._floats = newValue } }
    func _flowWidth(_ a0: Int) -> Double { rl._flowWidth(a0) }
    func _grid(_ a0: Int?, _ a1: RichDocument) -> (pitch: Double?, chars: Double?) { rl._grid(a0, a1) }
    func _gridCellBase(_ a0: Int?, _ a1: RichDocument) -> Double? { rl._gridCellBase(a0, a1) }
    func _hangMarker(_ a0: Int, _ a1: RichParagraph, _ a2: RichDocument, label a3: String) -> TextPainter { rl._hangMarker(a0, a1, a2, label: a3) }
    func _hasVisibleText(_ a0: RichParagraph) -> Bool { rl._hasVisibleText(a0) }
    var _headPushUse: [Int : Double] { get { rl._headPushUse } set { rl._headPushUse = newValue } }
    var _heights: [Double] { get { rl._heights } set { rl._heights = newValue } }
    var _heldTallerLatin: Set<Int> { get { rl._heldTallerLatin } set { rl._heldTallerLatin = newValue } }
    func _holdsEastAsianAndLatinRuns(_ a0: RichParagraph, document a1: RichDocument) -> Bool { rl._holdsEastAsianAndLatinRuns(a0, document: a1) }
    var _imageDrop: [Double] { get { rl._imageDrop } set { rl._imageDrop = newValue } }
    var _imageShift: [Double] { get { rl._imageShift } set { rl._imageShift = newValue } }
    var _imageSize: [Size?] { get { rl._imageSize } set { rl._imageSize = newValue } }
    func _indicFirstLineAscent(_ a0: RichParagraph, painter a1: TextPainter, lead a2: Int, named a3: RichNamedStyle?, document a4: RichDocument, target a5: Double, style a6: RichParagraphStyle, pitch a7: Double?, lift a8: inout Double) -> Double? { rl._indicFirstLineAscent(a0, painter: a1, lead: a2, named: a3, document: a4, target: a5, style: a6, pitch: a7, lift: &a8) }
    var _inkShift: [Double] { get { rl._inkShift } set { rl._inkShift = newValue } }
    var _inline: [[ImageAttachment]] { get { rl._inline } set { rl._inline = newValue } }
    var _inlineBoxes: [[Int]] { get { rl._inlineBoxes } set { rl._inlineBoxes = newValue } }
    func _inlinePictureOnly(_ a0: Int, _ a1: RichDocument) -> Bool { rl._inlinePictureOnly(a0, a1) }
    var _inserts: [[Int]] { get { rl._inserts } set { rl._inserts = newValue } }
    func _koreanSymbolFirstLineRaise(_ a0: RichParagraph, painter a1: TextPainter, lead a2: Int, named a3: RichNamedStyle?, document a4: RichDocument) -> Double? { rl._koreanSymbolFirstLineRaise(a0, painter: a1, lead: a2, named: a3, document: a4) }
    func _koreanSymbolLineFlags(_ a0: RichParagraph, painter a1: TextPainter, lead a2: Int, named a3: RichNamedStyle?, document a4: RichDocument) -> [Bool] { rl._koreanSymbolLineFlags(a0, painter: a1, lead: a2, named: a3, document: a4) }
    func _labelFaceGrowth(_ a0: RichParagraph, named a1: RichNamedStyle?, document a2: RichDocument, style a3: RichParagraphStyle) -> (target: Double, growth: Double)? { rl._labelFaceGrowth(a0, named: a1, document: a2, style: a3) }
    func _layoutParagraphOnce(_ a0: Int, _ a1: RichParagraph, _ a2: RichDocument)  { rl._layoutParagraphOnce(a0, a1, a2) }
    func _lead(_ a0: Int) -> Int { rl._lead(a0) }
    var _leadWidth: [Double] { get { rl._leadWidth } set { rl._leadWidth = newValue } }
    var _leaders: [[(offset: Int, fill: String)]] { get { rl._leaders } set { rl._leaders = newValue } }
    func _leadingBreakCut(_ a0: Int, _ a1: RichParagraph, _ a2: TextPainter, _ a3: RichDocument, bodyHeight a4: inout Double)  { rl._leadingBreakCut(a0, a1, a2, a3, bodyHeight: &a4) }
    func _levelNumberFonts(_ a0: RichParagraph, _ a1: RichDocument) -> (latin: String?, eastAsian: String?) { rl._levelNumberFonts(a0, a1) }
    func _levelNumberSize(_ a0: RichParagraph, _ a1: RichDocument) -> Double? { rl._levelNumberSize(a0, a1) }
    var _lineCentre: [String : Double] { get { rl._lineCentre } set { rl._lineCentre = newValue } }
    var _lineDrop: [Int : (from: Int, dy: Double)] { get { rl._lineDrop } set { rl._lineDrop = newValue } }
    var _lineLift: [[Double]] { get { rl._lineLift } set { rl._lineLift = newValue } }
    var _lineOverhang: [[Double]] { get { rl._lineOverhang } set { rl._lineOverhang = newValue } }
    func _hangsLineEndMarks(_ a0: RichParagraph) -> Bool { rl._hangsLineEndMarks(a0) }
    func _lineStarts(_ a0: TextPainter, _ a1: _OffsetMap, count a2: Int) -> [Int] { rl._lineStarts(a0, a1, count: a2) }
    func _listIndents(_ a0: RichParagraph, _ a1: RichDocument) -> (left: Double, hanging: Double)? { rl._listIndents(a0, a1) }
    func _map(_ a0: Int) -> _OffsetMap { rl._map(a0) }
    func _markLineHeight(_ a0: Int, _ a1: RichDocument, single a2: Bool = false, using a3: CharStyle? = nil, descentOnly a4: Bool = false, paragraph a5: RichParagraph? = nil) -> Double { rl._markLineHeight(a0, a1, single: a2, using: a3, descentOnly: a4, paragraph: a5) }
    func _markSize(_ a0: RichParagraph, _ a1: RichDocument) -> Double? { rl._markSize(a0, a1) }
    func _markUnderNestedTable(_ a0: Int, _ a1: RichDocument) -> Bool { rl._markUnderNestedTable(a0, a1) }
    func _marker(_ a0: Int, _ a1: RichParagraph, _ a2: RichDocument, label a3: String, strut a4: StrutStyle?) -> TextPainter { rl._marker(a0, a1, a2, label: a3, strut: a4) }
    func _markerChar(_ a0: RichParagraph, _ a1: RichDocument) -> CharStyle { rl._markerChar(a0, a1) }
    func _maxContent(_ a0: Int, _ a1: RichParagraph, _ a2: RichDocument) -> Double { rl._maxContent(a0, a1, a2) }
    var _mirrored: Set<Int> { get { rl._mirrored } set { rl._mirrored = newValue } }
    var _mixedFace: [Int : (depth: Double, size: Double)] { get { rl._mixedFace } set { rl._mixedFace = newValue } }
    func _mixedFaceLinesSpan(_ a0: TextSpan, _ a1: RichParagraph, _ a2: TextPainter) -> TextSpan? { rl._mixedFaceLinesSpan(a0, a1, a2) }
    func _mixedFaceSpan(_ a0: TextSpan, _ a1: RichParagraph) -> (span: TextSpan, depth: Double, size: Double)? { rl._mixedFaceSpan(a0, a1) }
    func _named(_ a0: RichParagraph, _ a1: RichDocument) -> RichNamedStyle? { rl._named(a0, a1) }
    func _normalChar(_ a0: RichDocument) -> CharStyle? { rl._normalChar(a0) }
    var _numberLiftShift: [Double] { get { rl._numberLiftShift } set { rl._numberLiftShift = newValue } }
    func _offGrid(_ a0: Int, _ a1: RichDocument) -> Bool { rl._offGrid(a0, a1) }
    var _overhang: [Double] { get { rl._overhang } set { rl._overhang = newValue } }
    var _pageBreak: [Bool] { get { rl._pageBreak } set { rl._pageBreak = newValue } }
    var _pageFill: [String : Double] { get { rl._pageFill } set { rl._pageFill = newValue } }
    var _painters: [TextPainter?] { get { rl._painters } set { rl._painters = newValue } }
    var _pastLeft: [Int : Double] { get { rl._pastLeft } set { rl._pastLeft = newValue } }
    var _pastNeed: [Int : Double] { get { rl._pastNeed } set { rl._pastNeed = newValue } }
    var _pastWiden: Double? { get { rl._pastWiden } set { rl._pastWiden = newValue } }
    func _pictureRoom(_ a0: ImageAttachment) -> (top: Double, bottom: Double, left: Double, right: Double) { rl._pictureRoom(a0) }
    func _pictureTextLineAdjust(_ a0: Int, _ a1: RichParagraph, multiple a2: Double, single a3: Double, bodyHeight a4: inout Double)  { rl._pictureTextLineAdjust(a0, a1, multiple: a2, single: a3, bodyHeight: &a4) }
    func _picturesTakeLines(_ a0: RichParagraph, textWidth a1: Double) -> Bool { rl._picturesTakeLines(a0, textWidth: a1) }
    func _px(_ a0: Double) -> Double { rl._px(a0) }
    var _rubyApply: Set<Int> { get { rl._rubyApply } set { rl._rubyApply = newValue } }
    var _rubyWiden: [Int : [Int : Double]] { get { rl._rubyWiden } set { rl._rubyWiden = newValue } }
    func _sectionEndnotesHeight(before a0: Int, _ a1: RichDocument) -> Double { rl._sectionEndnotesHeight(before: a0, a1) }
    func _setup(ofParagraph a0: Int) -> PageSetup { rl._setup(ofParagraph: a0) }
    func _sideIndents(_ a0: RichParagraph, at a1: Int? = nil, _ a2: RichDocument) -> (left: Double, right: Double) { rl._sideIndents(a0, at: a1, a2) }
    var _spaceBefore: [Double] { get { rl._spaceBefore } set { rl._spaceBefore = newValue } }
    func _spacesToHold(_ a0: RichParagraph, lineStarts a1: Set<Int>) -> Set<Int> { rl._spacesToHold(a0, lineStarts: a1) }
    func _spacing(_ a0: Int, _ a1: RichDocument) -> (before: Double, after: Double) { rl._spacing(a0, a1) }
    func _span(for a0: RichParagraph, at a1: Int?, _ a2: RichDocument, textWidth a3: Double, lead a4: Double = 0, adjust a5: [Int: Double] = [:], held a6: Set<Int> = [], spread a7: [Int: Double] = [:], fitProbe a8: Bool = false, autoSpaces a9: ((Int, Double) -> Void)? = nil) -> (TextSpan, [(image: ImageAttachment?, dimensions: PlaceholderDimensions)], [Int]) { rl._span(for: a0, at: a1, a2, textWidth: a3, lead: a4, adjust: a5, held: a6, spread: a7, fitProbe: a8, autoSpaces: a9) }
    func _stripBesideLeftTable(_ a0: String, _ a1: Int, _ a2: RichDocument) -> Bool { rl._stripBesideLeftTable(a0, a1, a2) }
    var _stripUse: [Int : (indent: Double, band: (top: Double, bottom: Double), right: Bool)] { get { rl._stripUse } set { rl._stripUse = newValue } }
    func _strut(_ a0: TextSpan, tallest a1: Bool = false, near a2: Bool = false, wide a3: Bool = false, joiners a4: Bool = true) -> StrutStyle? { rl._strut(a0, tallest: a1, near: a2, wide: a3, joiners: a4) }
    func _tableLeft(_ a0: String, _ a1: RichDocument) -> Double { rl._tableLeft(a0, a1) }
    var _tableMerged: [String : [Int]] { get { rl._tableMerged } set { rl._tableMerged = newValue } }
    var _tableOwnLeft: [String : (style: String, width: Double)] { get { rl._tableOwnLeft } set { rl._tableOwnLeft = newValue } }
    var _tableRows: [String : Int] { get { rl._tableRows } set { rl._tableRows = newValue } }
    func _tallestTextLine(_ a0: Int, _ a1: RichDocument) -> Double? { rl._tallestTextLine(a0, a1) }
    func _tamilMarkedLinesExtra(_ a0: Int, _ a1: RichParagraph, _ a2: RichDocument, _ a3: TextPainter) -> Double { rl._tamilMarkedLinesExtra(a0, a1, a2, a3) }
    func _textBox(_ a0: ImageAttachment, _ a1: RichDocument) -> _HeaderFooter? { rl._textBox(a0, a1) }
    var _textLeft: [Double] { get { rl._textLeft } set { rl._textLeft = newValue } }
    var _textWidth: [Double] { get { rl._textWidth } set { rl._textWidth = newValue } }
    var _topsValid: Bool { get { rl._topsValid } set { rl._topsValid = newValue } }
    var _unseenShift: [Int : Double] { get { rl._unseenShift } set { rl._unseenShift = newValue } }
    func _vanishes(_ a0: RichParagraph, _ a1: RichDocument) -> Bool { rl._vanishes(a0, a1) }
    func _verticalBody(_ a0: Int) -> Bool { rl._verticalBody(a0) }
    func _wordList(_ a0: RichParagraph, _ a1: RichDocument) -> (left: Double, first: Double, format: ListLevelFormat?)? { rl._wordList(a0, a1) }
    var _wwSpaceStarts: [Int : Set<Int>] { get { rl._wwSpaceStarts } set { rl._wwSpaceStarts = newValue } }
    var count: Int { get { rl.count } }
    func firstLineIndent(_ a0: RichParagraph, at a1: Int? = nil, _ a2: RichDocument) -> Double { rl.firstLineIndent(a0, at: a1, a2) }
    var floatsFrames: Bool { get { rl.floatsFrames } set { rl.floatsFrames = newValue } }
    var fontScale: Double { get { rl.fontScale } set { rl.fontScale = newValue } }
    var frameMargins: (left: Double, right: Double) { get { rl.frameMargins } set { rl.frameMargins = newValue } }
    var headerTopOnPage: Double? { get { rl.headerTopOnPage } set { rl.headerTopOnPage = newValue } }
    var leftHandPage: Bool { get { rl.leftHandPage } set { rl.leftHandPage = newValue } }
    func listLabel(_ a0: Int, _ a1: RichDocument) -> String? { rl.listLabel(a0, a1) }
    var scale: Double { get { rl.scale } set { rl.scale = newValue } }
    var theme: RichTextTheme { get { rl.theme } }
// FWD-END
}
