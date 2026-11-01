// Copyright the Starling authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_SWIFT_FONT_COLLECTION_BRIDGE_H_
#define FLUTTER_SWIFT_FONT_COLLECTION_BRIDGE_H_

#include "swift_bridge_export.h"

#include <swift/bridging>

#include <cstddef>
#include <cstdint>

namespace flutter::swift_bridge {

/// Loads a font from memory and makes it available for rendering text.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart:3756-3761`
/// **Original:** `_loadFontFromList` @Native function
///
/// This is a free function that loads font data into the Swift bridge's
/// font collection. Unlike the Dart version which uses UIDartState to get
/// the FontCollection, the Swift version maintains its own DynamicFontManager.
///
/// @param data Pointer to the font file data
/// @param length Number of bytes in the font data
/// @param family_name Optional font family name (null-terminated string, or
/// nullptr)
/// @return True if the font was loaded successfully
///
/// DIFFERENCE FROM DART: The Dart version accesses FontCollection via
/// UIDartState::Current()->platform_configuration()->client()->GetFontCollection().
/// REASON: No Dart VM in Swift. The Swift bridge maintains its own font
/// manager that is used by the ParagraphBuilderBridge.
///
/// DIFFERENCE FROM DART: Synchronous instead of async.
/// REASON: The actual font loading (creating SkTypeface) is synchronous.
/// The Dart version was async because of the callback/futurize pattern,
/// but the underlying operation doesn't require async behavior.
FLUTTER_SWIFT_BRIDGE_EXPORT bool LoadFontFromList(
    const uint8_t* data,
    size_t length,
    const char* family_name);

/// Loads a font from a file on disk and makes it available for rendering
/// text — same registration as LoadFontFromList, different memory story.
///
/// The file is mmap'd (SkData::MakeFromFileName), so its bytes stay
/// file-backed: shared between every process that loads the font, evictable
/// under memory pressure, and never counted against the app's anonymous
/// RSS. LoadFontFromList must copy because its buffer dies with the call;
/// a font that exists as a file should come through here instead — the
/// terminal's CJK + emoji fallbacks are ~30 MB of font data, which this
/// turns from per-app heap into shared page cache.
///
/// @param path Null-terminated filesystem path to a .ttf/.ttc/.otf
/// @param family_name Optional font family name (null-terminated string, or
/// nullptr to use the font's own name)
/// @return True if the font was loaded successfully
FLUTTER_SWIFT_BRIDGE_EXPORT bool LoadFontFromFile(const char* path,
                                                  const char* family_name);

/// LoadFontFromFile for one face of a font COLLECTION (.ttc / .otc): the
/// face at `face_index`, counted from 0, instead of always the first.
///
/// Noto Sans/Serif CJK ship as collections — one file holds SC, TC, JP and KR
/// — and LoadFontFromFile reads only face 0. The file is mmap'd as there, so
/// loading all four faces of a 30 MB collection maps it four times over the
/// same page cache and costs no more memory than once.
///
/// @param face_index which face of the file; 0 is LoadFontFromFile's face
/// @return True if the font was loaded; false for an unreadable file or an
/// index past the file's last face (no face is registered then)
///
/// Probe: `StarlingTextFontFaceIndexSupported` (extern "C"; an engine without
/// it has no such call and the caller must not link-bind to it).
FLUTTER_SWIFT_BRIDGE_EXPORT bool LoadFontFromFileFace(const char* path,
                                                      const char* family_name,
                                                      int face_index);

/// Takes the system's fonts out of text layout: after this, the families the
/// app registered (LoadFontFromList / LoadFontFromFile / LoadFontFromFileFace)
/// are the only fonts the engine's font collection can resolve, and a glyph
/// none of them has is drawn as missing — never found in a font the machine
/// happens to have. Without it a character the app's fonts lack is looked up
/// through the platform (fontconfig, CoreText, DirectWrite), so the same
/// document lays out differently on a machine with more fonts installed.
///
/// What it does: the default font manager of the engine's collection and of
/// the bridge's own is replaced by an empty one, and the collection's
/// per-character fallback is turned off. Fonts loaded before or after the
/// call are kept (they live in the dynamic font manager). Typefaces are still
/// decoded by the platform manager, so loading keeps working. Idempotent;
/// the engine's collection is picked up when it exists, now or at its first
/// font registered later.
///
/// Not undone — a process chooses once. Unused by default: an app that never
/// calls it lays out as it always did.
///
/// Probe: `StarlingTextBundledFontsOnlySupported`.
FLUTTER_SWIFT_BRIDGE_EXPORT void DisableSystemFontFallback();

/// True once DisableSystemFontFallback has been called.
FLUTTER_SWIFT_BRIDGE_EXPORT bool SystemFontFallbackDisabled();

/// Clears the font family cache.
///
/// This should be called after loading fonts to ensure the paragraph
/// builder picks up the new fonts.
FLUTTER_SWIFT_BRIDGE_EXPORT void ClearFontFamilyCache();

/// Load ICU's common data (icudtl.dat) into THIS library's ICU.
///
/// On macOS the Swift bridge is a dylib of its own beside
/// FlutterMacOS.framework, and it carries its own copies of Skia, skparagraph,
/// fml and ICU. The framework initialises ICU from the project's icu_data_path
/// when its shell starts — into the framework's copy. The bridge's copy, the
/// one every paragraph a Swift app lays out actually goes through, never saw
/// the data, so its break iterators failed to open and skparagraph fell back
/// to breaking lines between characters: every wrapped paragraph on the Cocoa
/// host broke mid-word, and Impeller aborted outright (which is why Swift
/// mode forces Skia there). A host that links the bridge as a separate library
/// calls this with the same path it hands the engine, before building any
/// paragraph. Idempotent; a no-op where the bridge lives inside the engine
/// library (Linux, Windows), because that ICU is the shell's and already has
/// its data — the once-flag it shares with fml::icu makes the second call
/// harmless. Returns false when the file cannot be read.
FLUTTER_SWIFT_BRIDGE_EXPORT bool InitializeICU(const char* icu_data_path);

}  // namespace flutter::swift_bridge

#endif  // FLUTTER_SWIFT_FONT_COLLECTION_BRIDGE_H_
