// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "Span+State": the locals `_span` shares with its `styled` step (once a nested function of it).
// A pure move: the variables `styled` changes are fields here, passed inout; the constants are copied in.

import Flutter
import FlutterSwiftBridge
import Foundation

struct _SpanCtx {
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
    let eastAsianFaceIsLatin: (Int) -> Bool
    let runHinted: (Int) -> Bool
    let paragraphLatinOwnerFn: () -> String?
    var afterHeld: Bool
    var afterIdeograph: Bool
    var before: Character?
    var beforeBefore: Character?
    let breaksAtQuotes: Bool
    var complexSpaces: Set<Int>
    var dotsAttached: Bool
    let fullQuotes: Bool
    let hanJoins: Set<Int>
    let heldSpaces: Set<Int>
    var inserts: [Int]
    let kinsokuOff: Bool
    let koreanSpaces: Set<Int>
    let koreanTokenJoins: Set<Int>
    var latinAfterEastAsian: Bool
    var latinRunBracket: Bool
    let lineSize: (size: Double, blank: Bool)?
    var loose: Set<Int>
    let mixedRubyRaise: Double
    let named: RichNamedStyle?
    let openerBeforeLatin: Bool
    var ordinaryBalancedSpaces: Set<Int>
    let pausesOpenLines: Bool
    let percentStarts: Bool
    let pitch: Double?
    let plainNoLineRules: Bool
    let raised: [Bool]
    var rubyHeld: Set<Int>
    let rubyKeep: Double
    var rubyTails: [Int : Double]
    var spacesAfterNbsp: Bool
    var splittingMark: Bool
    var splittingSpaces: Bool
    var splittingVariation: Bool
    var spread: [Int : Double]
    let thaiJoins: Set<Int>
    let thaiParagraph: Bool
    let traditionalLists: Bool
    let vertical: Bool
    let wholeRaised: Bool
    let wideIndicWords: [Range<Int>]
    var widen: [Int : Double]
    var wideSpaces: Set<Int>
    var wideStarts: Set<Int>
    let windowsCounted: Set<Int>
    var windowsShare: Double?
    var wordHasLetter: Bool
    let mixedLatinFaces: Bool
    var heldKind: Int?
    var splittingDigits: Bool
    let trailingSpaces: Int
}
