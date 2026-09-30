// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Pointer event button constants and utility functions.
///
/// **Dart Source:** `packages/flutter/lib/src/gestures/events.dart`

// MARK: - Button Constants

/// The bit of PointerEvent.buttons that corresponds to a cross-device
/// behavior of "primary operation".
///
/// **Dart Source:** `events.dart:43`
public let kPrimaryButton: Int = 0x01

/// The bit of PointerEvent.buttons that corresponds to a cross-device
/// behavior of "secondary operation".
///
/// **Dart Source:** `events.dart:59`
public let kSecondaryButton: Int = 0x02

/// The bit of PointerEvent.buttons that corresponds to the primary mouse button.
///
/// **Dart Source:** `events.dart:70`
public let kPrimaryMouseButton: Int = kPrimaryButton

/// The bit of PointerEvent.buttons that corresponds to the secondary mouse button.
///
/// **Dart Source:** `events.dart:81`
public let kSecondaryMouseButton: Int = kSecondaryButton

/// The bit of PointerEvent.buttons that corresponds to when a stylus contacting the screen.
///
/// **Dart Source:** `events.dart:90`
public let kStylusContact: Int = kPrimaryButton

/// The bit of PointerEvent.buttons that corresponds to the primary stylus button.
///
/// **Dart Source:** `events.dart:101`
public let kPrimaryStylusButton: Int = kSecondaryButton

/// The bit of PointerEvent.buttons that corresponds to a cross-device
/// behavior of "tertiary operation".
///
/// **Dart Source:** `events.dart:119`
public let kTertiaryButton: Int = 0x04

/// The bit of PointerEvent.buttons that corresponds to the middle mouse button.
///
/// **Dart Source:** `events.dart:131`
public let kMiddleMouseButton: Int = kTertiaryButton

/// The bit of PointerEvent.buttons that corresponds to the secondary stylus button.
///
/// **Dart Source:** `events.dart:142`
public let kSecondaryStylusButton: Int = kTertiaryButton

/// The bit of PointerEvent.buttons that corresponds to the back mouse button.
///
/// **Dart Source:** `events.dart:148`
public let kBackMouseButton: Int = 0x08

/// The bit of PointerEvent.buttons that corresponds to the forward mouse button.
///
/// **Dart Source:** `events.dart:154`
public let kForwardMouseButton: Int = 0x10

/// The bit of PointerEvent.buttons that corresponds to the pointer contacting a touch screen.
///
/// **Dart Source:** `events.dart:163`
public let kTouchContact: Int = kPrimaryButton

/// The maximum unsigned small integer on 64-bit platforms.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/_bitfield_io.dart:8`
// Spelled from Int.max so that it is also right where Int is 32 bits.
public let kMaxUnsignedSMI: Int = Int.max >> 1

// MARK: - Button Utility Functions

/// The bit of PointerEvent.buttons that corresponds to the nth mouse button.
///
/// The `number` argument can be at most 62.
///
/// **Dart Source:** `events.dart:173`
public func nthMouseButton(_ number: Int) -> Int {
    (kPrimaryMouseButton << (number - 1)) & kMaxUnsignedSMI
}

/// The bit of PointerEvent.buttons that corresponds to the nth stylus button.
///
/// The `number` argument can be at most 62.
///
/// **Dart Source:** `events.dart:182`
public func nthStylusButton(_ number: Int) -> Int {
    (kPrimaryStylusButton << (number - 1)) & kMaxUnsignedSMI
}

/// Returns the button of `buttons` with the smallest integer.
///
/// Returns zero when `buttons` is zero.
///
/// **Dart Source:** `events.dart:203`
public func smallestButton(_ buttons: Int) -> Int {
    buttons & (-buttons)
}

/// Returns whether `buttons` contains one and only one button.
///
/// Returns false when `buttons` is zero.
///
/// **Dart Source:** `events.dart:224`
public func isSingleButton(_ buttons: Int) -> Bool {
    buttons != 0 && (smallestButton(buttons) == buttons)
}
