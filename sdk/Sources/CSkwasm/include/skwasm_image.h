// skwasm's image exports: image.cpp, data.cpp, and the readback entry point
// of surface.cpp. See skwasm.h for the rule about sk_ptr.
#ifndef STARLING_SKWASM_IMAGE_H
#define STARLING_SKWASM_IMAGE_H

#include "skwasm_base.h"

// --- data.cpp ---------------------------------------------------------------
// An SkData is how bytes get into skwasm for keeps: create, write through
// getPointer with starling_host_write, hand it over. Ref counted; whoever
// consumes it takes its own reference, so the creator still disposes.
SKWASM(skData_create) sk_ptr skData_create(uint32_t size);
SKWASM(skData_getPointer) sk_ptr skData_getPointer(sk_ptr data);
SKWASM(skData_getConstPointer) sk_ptr skData_getConstPointer(sk_ptr data);
SKWASM(skData_getSize) uint32_t skData_getSize(sk_ptr data);
SKWASM(skData_dispose) void skData_dispose(sk_ptr data);

// --- image.cpp --------------------------------------------------------------
// pixelFormat: 0 rgba8888 (premul), 1 bgra8888 (premul), 2 rgbaFloat32
// (unpremul) — the same order as dart:ui's PixelFormat. Returns 0 when Skia
// rejects the description (rowByteCount too small, data too short).
SKWASM(image_createFromPixels)
sk_ptr image_createFromPixels(sk_ptr data, int32_t width, int32_t height,
                              int32_t pixelFormat, uint32_t rowByteCount);
SKWASM(image_createFromPicture)
sk_ptr image_createFromPicture(sk_ptr picture, int32_t width, int32_t height);
SKWASM(image_ref) void image_ref(sk_ptr image);
SKWASM(image_dispose) void image_dispose(sk_ptr image);
SKWASM(image_getWidth) int32_t image_getWidth(sk_ptr image);
SKWASM(image_getHeight) int32_t image_getHeight(sk_ptr image);

// image_createFromTextureSource is deliberately absent: its first argument
// is an externref (an ImageBitmap or VideoFrame), which C cannot spell. Only
// the page can call it.

// --- surface.cpp ------------------------------------------------------------
// format: 0 rawRgba, 1 rawStraightRgba, 2 rawUnmodified, 3 rawExtendedRgba128,
// 4 png. Returns a callback id; the bytes arrive later, as an SkData, through
// the surface's callback handler — which the page owns.
SKWASM(surface_rasterizeImage)
uint32_t surface_rasterizeImage(sk_ptr surface, sk_ptr image, int32_t format);

#endif  // STARLING_SKWASM_IMAGE_H
