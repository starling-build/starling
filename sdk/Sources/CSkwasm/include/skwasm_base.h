// What every skwasm_*.h header shares: the import macros, the pointer type,
// skwasm's stack, and the page's own functions. See skwasm.h for the rule
// that matters — an sk_ptr is an address in ANOTHER module's memory.
#ifndef STARLING_SKWASM_BASE_H
#define STARLING_SKWASM_BASE_H

#include <stdbool.h>
#include <stdint.h>

#define SKWASM(name) __attribute__((import_module("skwasm"), import_name(#name)))
#define HOST(name) __attribute__((import_module("starling"), import_name(#name)))

typedef uint32_t sk_ptr;  // an address in skwasm's memory

// --- skwasm's stack: scratch space for arguments passed by pointer ---------
SKWASM(_emscripten_stack_alloc) sk_ptr skwasm_stack_alloc(uint32_t size);
SKWASM(emscripten_stack_get_current) sk_ptr skwasm_stack_save(void);
SKWASM(_emscripten_stack_restore) void skwasm_stack_restore(sk_ptr sp);

// --- the page (web/host/starling.js) ----------------------------------------
// Copies between our memory and skwasm's. These two are the only functions
// here that take a real pointer, and it is always the Swift-side one.
HOST(write) void starling_host_write(sk_ptr dst, const void* src, uint32_t length);
HOST(read) void starling_host_read(void* dst, sk_ptr src, uint32_t length);

// The light skwasm build carries no ICU: grapheme, word and line breaks come
// from the browser (Intl.Segmenter, Intl.v8BreakIterator). The page reads the
// builder's text and sets all three, exactly as Flutter's own
// SkwasmParagraphBuilder._addSegmenterData does. Call before build().
HOST(segment) void starling_host_segment(sk_ptr paragraphBuilder);

// skwasm reports a finished render through a function in ITS OWN table taking
// an externref, which Swift cannot express. The page owns that function: it
// puts the rendered ImageBitmap on screen, then calls our exported
// starling_frame_presented. This returns its table index.
HOST(render_callback) uint32_t starling_host_render_callback(void);

// Asks for one requestAnimationFrame; the page answers by calling our
// exported starling_begin_frame.
HOST(request_frame) void starling_host_request_frame(void);

// One-shot timer: after `milliseconds` the page calls our exported
// starling_timer_fired(id). 0 ms is "as soon as the current task ends".
// This is what stands in for a run loop — there is no thread to block.
HOST(set_timeout) void starling_host_set_timeout(int32_t id, double milliseconds);

// Milliseconds since the page loaded, monotonic (performance.now()).
HOST(now) double starling_host_now(void);

// Decodes an encoded image (PNG, JPEG, GIF, WebP — whatever the browser
// reads) from `length` bytes at `bytes` in OUR memory, copied before the
// call returns. The page makes an SkImage of it in skwasm
// (image_createFromTextureSource takes a JavaScript object, which Swift
// cannot hold) and answers through our exported starling_image_decoded
// (requestId, skImage or 0, width, height). `surface` is skwasm's Surface,
// whose GL context the texture is uploaded to.
HOST(decode_image)
void starling_host_decode_image(uint32_t requestId, const void* bytes, uint32_t length,
                                sk_ptr surface);

// The tab's title (UTF-8, in OUR memory).
HOST(set_title) void starling_host_set_title(const void* utf8, uint32_t length);

#endif  // STARLING_SKWASM_BASE_H
