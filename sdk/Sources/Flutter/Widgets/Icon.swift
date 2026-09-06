// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// `Icon`: one glyph from an icon font, in a square box.
//
// A port of Flutter's `Icon` (widgets/icon.dart, minus the semantics and
// the RTL mirroring): the size and colour default to the enclosing
// `IconTheme`, which every `FluentTheme` and `MacosApp` installs, so a bare
// `Icon(FluentSystemIcons.settings)` inside either comes out at the theme's
// size in the theme's ink. The framework had no such widget until the Fluent
// gallery needed one — the example host carried a stand-in, MacosUI has
// `MacosIcon`, and the Fluent controls take a `Widget` for every icon slot
// precisely so this could be anything.
//
// The glyph's font is loaded on first draw (`StarlingFonts.ensure`), so an
// icon from one of the SDK's own sets needs no registration call from the
// app; a family the SDK does not ship is drawn with whatever the engine
// falls back to, exactly as before.

import FlutterSwiftBridge

public class Icon: StatelessWidget {
    /// The glyph. nil draws an empty box of the icon's size.
    public let icon: IconData?

    /// Logical pixels; the theme's, or 24, when nil.
    public let size: Double?

    /// The ink; the theme's, or near-black, when nil.
    public let color: Color?

    public init(
        _ icon: IconData?,
        key: (any Key)? = nil,
        size: Double? = nil,
        color: Color? = nil
    ) {
        self.icon = icon
        self.size = size
        self.color = color
        super.init(key: key)
    }

    public override func build(_ context: any BuildContext) -> Widget {
        let theme = IconTheme.of(context)
        let side = size ?? theme.size ?? 24
        guard let icon, let scalar = UnicodeScalar(icon.codePoint) else {
            return SizedBox(width: side, height: side)
        }
        let ink = color ?? theme.color ?? Color(0xDD000000)
        StarlingFonts.ensure(icon.fontFamily)
        return SizedBox(
            width: side, height: side,
            child: Center(child: Text(
                String(scalar),
                style: TextStyle(
                    color: ink,
                    fontSize: side,
                    height: 1.0,
                    fontFamily: icon.fontFamily,
                    fontFamilyFallback: icon.fontFamilyFallback))))
    }
}
