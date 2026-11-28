/// Not in Flutter: which kind of pointer was used last, so chrome that opens
/// from a dense toolbar can size its rows for a finger when the last input
/// was one (a menu row under a mouse is 28 pt; under a finger Apple asks 44).
///
/// Only a press or a hover counts: a finger presses, a mouse or pen also
/// hovers, and the two together tell which one the person is using now.

import FlutterSwiftBridge

public enum LastPointerKind {
    /// The kind of the last press or hover; nil before the first.
    nonisolated(unsafe) public private(set) static var kind: PointerDeviceKind?

    /// Whether menu rows, tiles and the like should be touch-sized: always
    /// on iOS, never elsewhere unless a caller turns it on (tests do).
    nonisolated(unsafe) public static var touchSizedRows: Bool = {
        #if os(iOS)
        true
        #else
        false
        #endif
    }()

    /// A row's minimum height when the last input was touch (and touch-sized rows are on), else nil.
    public static var touchRowHeight: Double? { touchSizedRows && kind == .touch ? 44 : nil }

    public static func note(_ event: PointerEvent) {
        if event is PointerDownEvent || event is PointerHoverEvent { kind = event.kind }
    }

    /// For tests: forget the last kind.
    public static func reset() { kind = nil }
}
