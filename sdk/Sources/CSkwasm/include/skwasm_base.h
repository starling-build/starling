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

// UTC minus browser-local time, in seconds, at a Unix timestamp (includes DST).
HOST(timezone_offset) double starling_host_timezone_offset(double unix_seconds);

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

// Request a font family (UTF-8 in OUR memory). The page fetches deferred
// faces once, then calls starling_fonts_changed after registration.
HOST(request_font) void starling_host_request_font(const void* utf8, uint32_t length);

// The tab's title (UTF-8, in OUR memory).
HOST(set_title) void starling_host_set_title(const void* utf8, uint32_t length);

// Files, the browser's way. open_file shows the picker for the given
// extensions ("docx,rtf,md,txt", UTF-8 in OUR memory); the page answers
// through our exported starling_file_opened(name, nameLength, bytes,
// byteCount) with the bytes copied into memory from starling_alloc — ours to
// free — or with byteCount 0 if the user cancelled. download hands the
// browser a file to save: name and bytes, both in OUR memory, copied
// before the call returns.
HOST(open_file) void starling_host_open_file(const void* extensions, uint32_t length);
HOST(download)
void starling_host_download(const void* name, uint32_t nameLength, const void* bytes,
                            uint32_t byteCount);

// The network, the browser's way (docs/plans/wiki.md W0). http_request
// starts a fetch: method, URL, headers ("Name: value" lines joined by \n)
// and body are UTF-8/bytes in OUR memory, copied before the call returns;
// same-origin cookies ride along. The page answers through our exported
// starling_http_done(id, status, headers, headersLength, body, bodyLength)
// with both buffers from starling_alloc — ours to free — and status 0 for a
// network failure. Sockets: socket_open starts a WebSocket; the page reports
// through starling_socket_event(id, kind, bytes, length) with kind 0 open,
// 1 text message, 2 binary message, 3 closed, 4 error (bytes as above, or
// null). socket_send takes bytes in OUR memory (text != 0 sends a string).
HOST(http_request)
void starling_host_http_request(uint32_t id, const void* method, uint32_t methodLength,
                                const void* url, uint32_t urlLength, const void* headers,
                                uint32_t headersLength, const void* body, uint32_t bodyLength);
HOST(socket_open) void starling_host_socket_open(uint32_t id, const void* url, uint32_t urlLength);
HOST(socket_send)
void starling_host_socket_send(uint32_t id, const void* bytes, uint32_t length, uint32_t text);
HOST(socket_close) void starling_host_socket_close(uint32_t id);

// The address bar: push (or replace) the tab's URL path without a load.
// The page reports the user's back/forward through our exported
// starling_route_changed(utf8, length).
HOST(push_route) void starling_host_push_route(const void* utf8, uint32_t length, uint32_t replace);

// The on-screen keyboard (SoftKeyboard): a phone shows one only for an
// editable element, so the page keeps a hidden one and focuses it on show.
// What is typed there comes back through our exported
// starling_text(utf8, length, milliseconds) and starling_key.
HOST(soft_keyboard) void starling_host_soft_keyboard(uint32_t show);

// The system clipboard (Clipboard.provider): text and, when there is one,
// HTML written together; a read answers through our exported
// starling_clipboard_text(id, utf8, length) — length 0 for nothing or
// no permission.
HOST(clipboard_write)
void starling_host_clipboard_write(const void* utf8, uint32_t length, const void* html, uint32_t htmlLength);
HOST(clipboard_read) void starling_host_clipboard_read(uint32_t id);

// The document's text for screen readers and crawlers: one line per
// paragraph as "<level>\t<text>" (level 0 a paragraph, 1-3 a heading),
// which the page keeps as hidden HTML beside the canvas.
HOST(set_document_text) void starling_host_set_document_text(const void* utf8, uint32_t length);

// A link out of the app (hostOpenURL): the browser opens it in a new tab.
HOST(open_url) void starling_host_open_url(const void* utf8, uint32_t length);
// The tab's own address onto the clipboard (a link to what is open).
HOST(copy_location) void starling_host_copy_location(void);

#endif  // STARLING_SKWASM_BASE_H
