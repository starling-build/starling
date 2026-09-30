// Copyright the Starling authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_SWIFT_PDF_BRIDGE_H_
#define FLUTTER_SWIFT_PDF_BRIDGE_H_

#include "swift_bridge_export.h"

#include <swift/bridging>

#include <cstddef>
#include <cstdint>

namespace flutter::swift_bridge {

/// Writes recorded pictures to a PDF, one picture per page, through Skia's
/// PDF backend (SkPDF), so the code that paints a page on screen is the
/// code that writes it to the file — with the real fonts embedded.
///
/// `display_lists` holds `count` pointers as PictureBridge::GetDisplayListPtr
/// returns them (a null entry is a blank page); `widths`/`heights` are
/// the page sizes in PDF points (1/72 in). A picture is played back at
/// 1 unit = 1 point, so a caller painting in logical pixels scales its
/// canvas by 72/96 first. `title`/`author` may be null. Returns true when
/// the file was written. Renderer-independent: SkPDF needs neither GPU
/// path, so this works under Skia and Impeller alike.
FLUTTER_SWIFT_BRIDGE_EXPORT bool WritePdf(const char* path,
                                          const void* const* display_lists,
                                          int count,
                                          const double* widths,
                                          const double* heights,
                                          const char* title,
                                          const char* author);

}  // namespace flutter::swift_bridge

#endif  // FLUTTER_SWIFT_PDF_BRIDGE_H_
