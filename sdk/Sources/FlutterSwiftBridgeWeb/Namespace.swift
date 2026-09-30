// The web's stand-in for the engine's C++ bridge.
//
// Everywhere else, `FlutterSwiftBridgeCxx` is a clang module: the engine's
// `flutter::swift_bridge` classes, imported through C++ interop. Here it is
// this Swift module, under the same name and spelling, so that
// FlutterSwiftBridge — the dart:ui layer, 29k lines — compiles unchanged.
// Each class keeps the C++ one's method names and argument types and does
// the work through skwasm (CSkwasm) instead.
import CSkwasm

public enum flutter {
    public enum swift_bridge {}
}

/// `std::string`, as far as the bridge's callers use it: built from a Swift
/// string, handed straight back to us.
public enum std {
    public struct string {
        public let value: String
        public init(_ value: String) { self.value = value }
        public init() { self.value = "" }
    }
}

extension String {
    public init(_ s: std.string) { self = s.value }
}
