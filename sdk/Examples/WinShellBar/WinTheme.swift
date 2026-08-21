// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Windows 11's flyout palette, shared by every surface that impersonates
// one of Windows' own — Quick Settings in the dock, the notification centre.
// Sampled off the native panels on this machine (light) and their dark
// twins. Not the desktop's colours on purpose: these surfaces replace
// Explorer's, and the accent pair is the one place light and dark disagree
// in kind — dark mode's accent is a LIGHT blue with BLACK glyphs on it.

#if os(Windows)

import Flutter
import FlutterSwiftBridge

struct WinPalette {
    let panel: Color
    let stroke: Color
    let button: Color
    let buttonStroke: Color
    /// The button's fill under the pointer — native darkens toward the
    /// panel in light mode and lightens in dark.
    let buttonHover: Color
    /// The subtle wash a hovered row or day cell gets.
    let rowHover: Color
    let accent: Color
    let onAccent: Color
    let ink: Color
    let subInk: Color
    let disabledInk: Color
    let trackRest: Color
    let divider: Color

    static func of(dark: Bool) -> WinPalette {
        dark
            ? WinPalette(panel: Color(0xF52C2C2C), stroke: Color(0xFF1D1D1D),
                         button: Color(0xFF383838), buttonStroke: Color(0xFF454545),
                         buttonHover: Color(0xFF3D3D3D), rowHover: Color(0xFF383838),
                         accent: Color(0xFF4CC2FF), onAccent: Color(0xFF000000),
                         ink: Color(0xFFFFFFFF), subInk: Color(0xFFCFCFCF),
                         disabledInk: Color(0xFF6E6E6E),
                         trackRest: Color(0xFF9D9D9D), divider: Color(0xFF3D3D3D))
            : WinPalette(panel: Color(0xF5F2F2F2), stroke: Color(0xFFD8D8D8),
                         button: Color(0xFFFBFBFB), buttonStroke: Color(0xFFE5E5E5),
                         buttonHover: Color(0xFFF5F5F5), rowHover: Color(0xFFE9E9E9),
                         accent: Color(0xFF0067C0), onAccent: Color(0xFFFFFFFF),
                         ink: Color(0xFF1B1B1B), subInk: Color(0xFF5D5D5D),
                         disabledInk: Color(0xFF9D9D9D),
                         trackRest: Color(0xFF868686), divider: Color(0xFFE5E5E5))
    }
}

#endif
