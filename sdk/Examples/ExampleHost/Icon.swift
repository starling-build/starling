// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Platform-neutral: every host the examples run on needs this, so it lives
// apart from the per-platform bring-up in ExampleHost.swift / 
// ExampleHostWindows.swift.

import CupertinoIcons
import Flutter
import FlutterSwiftBridge

// MARK: - Icon

/// The example ports' stand-in for Flutter's material `Icon` widget: a fixed
/// box drawing one glyph from an icon font (CupertinoIcons here — the same
/// approach MacosUI's MacosIcon takes). Registers the font with the engine on
/// first use; widgets first build on the first engine frame, so the engine is
/// live by then.
///
/// The framework has a real `Flutter.Icon` now (Widgets/Icon.swift), which
/// reads its size and colour from `IconTheme` and registers nothing. This one
/// stays for the Material-styled examples that lean on its CupertinoIcons
/// auto-registration; a file that imports ExampleHost AND uses `Icon` gets
/// this one, so do not write `Icon(` in a file that needs the framework's.
public class Icon: StatelessWidget {
    public let icon: IconData
    public let size: Double
    public let color: Color

    public init(
        _ icon: IconData, size: Double = 24, color: Color = Color(0xDD000000),
        key: (any Key)? = nil
    ) {
        self.icon = icon
        self.size = size
        self.color = color
        super.init(key: key)
    }

    public override func build(_ context: any BuildContext) -> Widget {
        CupertinoIcons.registerFont()
        guard let scalar = UnicodeScalar(icon.codePoint) else {
            return SizedBox(width: size, height: size)
        }
        return SizedBox(
            width: size,
            height: size,
            child: Center(
                child: Text(
                    String(scalar),
                    style: TextStyle(
                        color: color,
                        fontSize: size,
                        height: 1.0,
                        fontFamily: icon.fontFamily
                    )
                )
            )
        )
    }
}
