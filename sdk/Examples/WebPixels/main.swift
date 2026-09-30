// Milestone 0 of docs/plans/wasm.md: Swift, compiled to WebAssembly, puts
// pixels in a browser through skwasm. No framework code — this proved the
// seam the framework's web backend is built on: two modules, skwasm's C
// exports as our imports, buffers copied across, the page driving frames.
// It answers the same page (web/host/starling.js) an app does, so it also
// documents the exports a host must provide.
//
// What it draws is chosen to touch each kind of call the backend needs:
// by-value arguments (circle), by-pointer arguments (rect, rrect), a native
// object built up over several calls (path), and text, which needs a font
// the page fetched and break data the browser computed.
import CSkwasm

// MARK: - Crossing into skwasm's memory

/// Scratch space on skwasm's stack for arguments it takes by pointer. The
/// counterpart of `withStackScope` in Flutter's skwasm_impl.
struct SkStack {
    private let saved = skwasm_stack_save()

    func floats(_ values: [Float]) -> sk_ptr {
        let p = skwasm_stack_alloc(UInt32(values.count * 4))
        values.withUnsafeBytes {
            starling_host_write(p, $0.baseAddress, UInt32($0.count))
        }
        return p
    }

    func pointers(_ values: [sk_ptr]) -> sk_ptr {
        let p = skwasm_stack_alloc(UInt32(values.count * 4))
        values.withUnsafeBytes {
            starling_host_write(p, $0.baseAddress, UInt32($0.count))
        }
        return p
    }

    func restore() { skwasm_stack_restore(saved) }
}

func withSkStack<T>(_ body: (SkStack) -> T) -> T {
    let stack = SkStack()
    defer { stack.restore() }
    return body(stack)
}

/// An SkString holding `text` as UTF-8. The caller frees it.
func makeSkString(_ text: String) -> sk_ptr {
    let utf8 = Array(text.utf8)
    let s = skString_allocate(UInt32(utf8.count))
    utf8.withUnsafeBytes {
        starling_host_write(skString_getData(s), $0.baseAddress, UInt32($0.count))
    }
    return s
}

/// A std::u16string holding `text`. The caller frees it.
func makeSkString16(_ text: String) -> sk_ptr {
    let utf16 = Array(text.utf16)
    let s = skString16_allocate(UInt32(utf16.count))
    utf16.withUnsafeBytes {
        starling_host_write(skString16_getData(s), $0.baseAddress, UInt32($0.count))
    }
    return s
}

// MARK: - The smallest useful wrappers

// DlBlendMode and DlDrawStyle, by value (display_list/dl_blend_mode.h).
let blendSrcOver: Int32 = 3
let styleFill: Int32 = 0
let styleStroke: Int32 = 1

func makePaint(_ color: UInt32, style: Int32 = styleFill, strokeWidth: Float = 0) -> sk_ptr {
    // cap and join 1 = round.
    paint_create(true, blendSrcOver, color, style, strokeWidth, 1, 1, 4, false)
}

func makeParagraph(
    _ text: String, size: Float, color: UInt32, weight: Int32 = 400, width: Float
) -> sk_ptr {
    let textStyle = textStyle_create()
    textStyle_setColor(textStyle, color)
    textStyle_setFontSize(textStyle, size)
    textStyle_setFontStyle(textStyle, weight, 0)
    let family = makeSkString(fontFamily)
    withSkStack { stack in
        textStyle_addFontFamilies(textStyle, stack.pointers([family]), 1)
    }
    skString_free(family)

    let paragraphStyle = paragraphStyle_create()
    paragraphStyle_setTextStyle(paragraphStyle, textStyle)

    let builder = paragraphBuilder_create(paragraphStyle, fontCollection)
    paragraphBuilder_pushStyle(builder, textStyle)
    let text16 = makeSkString16(text)
    paragraphBuilder_addText(builder, text16)
    skString16_free(text16)
    starling_host_segment(builder)
    let paragraph = paragraphBuilder_build(builder)

    paragraphBuilder_dispose(builder)
    paragraphStyle_dispose(paragraphStyle)
    textStyle_dispose(textStyle)

    paragraph_layout(paragraph, width)
    return paragraph
}

// MARK: - State

let fontFamily = "DejaVu Sans"
let surface = surface_create()
let fontCollection = fontCollection_create()

// Logical size and device pixel ratio, set by the page.
nonisolated(unsafe) var viewWidth: Float = 0
nonisolated(unsafe) var viewHeight: Float = 0
nonisolated(unsafe) var pixelRatio: Float = 1

nonisolated(unsafe) var pointerX: Float = -1
nonisolated(unsafe) var pointerY: Float = -1
nonisolated(unsafe) var pointerDown = false

nonisolated(unsafe) var fontReady = false
nonisolated(unsafe) var frameCount = 0
// One frame in flight at a time: a second renderPictures before the first
// has been presented would only queue work the user never sees.
nonisolated(unsafe) var frameScheduled = false

func scheduleFrame() {
    if frameScheduled { return }
    frameScheduled = true
    starling_host_request_frame()
}

// MARK: - Drawing

func draw(on canvas: sk_ptr, at seconds: Float) {
    canvas_scale(canvas, pixelRatio, pixelRatio)
    canvas_drawColor(canvas, 0xFF10_1418, blendSrcOver)

    let w = viewWidth, h = viewHeight

    // By pointer: a rect is four floats in skwasm's memory.
    let card = makePaint(0xFF1C_2430)
    withSkStack { stack in
        let radius: Float = 18
        // left, top, right, bottom, then x and y radii for tl, tr, br, bl.
        let rrect = stack.floats(
            [24, 24, w - 24, h - 24] + [Float](repeating: radius, count: 8))
        canvas_drawRRect(canvas, rrect, card)
    }
    paint_dispose(card)

    // A native object built over several calls.
    let wave = path_create()
    let base = h * 0.62
    path_moveTo(wave, 24, base)
    let segments = 6
    let span = (w - 48) / Float(segments)
    for i in 0..<segments {
        let x0 = 24 + span * Float(i)
        let lift = 46 * sinApprox(seconds * 1.3 + Float(i) * 0.9)
        path_cubicTo(
            wave, x0 + span * 0.35, base - lift, x0 + span * 0.65, base + lift,
            x0 + span, base)
    }
    let stroke = makePaint(0xFF4F_C3F7, style: styleStroke, strokeWidth: 3)
    canvas_drawPath(canvas, wave, stroke)
    paint_dispose(stroke)
    path_dispose(wave)

    // By value.
    let palette: [UInt32] = [0xFFEF_5350, 0xFFFF_CA28, 0xFF66_BB6A, 0xFF42_A5F5, 0xFFAB_47BC]
    for (i, color) in palette.enumerated() {
        let t = seconds * 0.8 + Float(i) * 1.256
        let paint = makePaint(color)
        canvas_drawCircle(
            canvas, w * 0.5 + cosApprox(t) * w * 0.28,
            h * 0.80 + sinApprox(t * 2) * 22, 12, paint)
        paint_dispose(paint)
    }

    if fontReady {
        let title = makeParagraph(
            "Starling, in WebAssembly", size: 34, color: 0xFFFF_FFFF, weight: 700,
            width: w - 96)
        canvas_drawParagraph(canvas, title, 48, 52)
        let titleHeight = paragraph_getHeight(title)
        paragraph_dispose(title)

        let body = makeParagraph(
            "Swift compiled to wasm32, drawing through skwasm — two modules, "
                + "one page. Frame \(frameCount), \(Int(w))×\(Int(h)) at \(pixelRatio)x. "
                + "Text is shaped by Skia; the line breaks come from the browser.",
            size: 16, color: 0xFFB0_BEC5, width: w - 96)
        canvas_drawParagraph(canvas, body, 48, 52 + titleHeight + 10)
        paragraph_dispose(body)
    }

    if pointerX >= 0 {
        let ring = makePaint(
            pointerDown ? 0xFFFF_7043 : 0xFFFF_FFFF, style: styleStroke, strokeWidth: 2)
        canvas_drawCircle(canvas, pointerX, pointerY, pointerDown ? 26 : 18, ring)
        paint_dispose(ring)
    }
}

// libm is there, but Foundation is what re-exports it on WASI and this
// module deliberately imports nothing. Bhaskara's approximation is within
// 0.2% — more than a demo's wave needs.
func sinApprox(_ x: Float) -> Float {
    let pi: Float = 3.14159265
    var a = x.truncatingRemainder(dividingBy: 2 * pi)
    if a < 0 { a += 2 * pi }
    let sign: Float = a > pi ? -1 : 1
    if a > pi { a -= pi }
    return sign * 16 * a * (pi - a) / (5 * pi * pi - 4 * a * (pi - a))
}
func cosApprox(_ x: Float) -> Float { sinApprox(x + 3.14159265 / 2) }

// MARK: - Called by the page

@_expose(wasm, "starling_resize")
@_cdecl("starling_resize")
func starlingResize(_ width: Double, _ height: Double, _ ratio: Double) {
    viewWidth = Float(width)
    viewHeight = Float(height)
    pixelRatio = Float(ratio)
    scheduleFrame()
}

/// `event`: 0 move, 1 down, 2 up, 3 leave, 4 cancel (WebHost.PointerEvent).
@_expose(wasm, "starling_pointer")
@_cdecl("starling_pointer")
func starlingPointer(
    _ event: Int32, _ device: Int32, _ kind: Int32, _ x: Double, _ y: Double,
    _ buttons: Int32, _ milliseconds: Double
) {
    if event >= 3 {
        pointerX = -1
    } else {
        pointerX = Float(x)
        pointerY = Float(y)
        pointerDown = buttons != 0
    }
    scheduleFrame()
}

@_expose(wasm, "starling_scroll")
@_cdecl("starling_scroll")
func starlingScroll(
    _ device: Int32, _ x: Double, _ y: Double, _ deltaX: Double, _ deltaY: Double,
    _ milliseconds: Double
) {}

@_expose(wasm, "starling_timer_fired")
@_cdecl("starling_timer_fired")
func starlingTimerFired(_ id: Int32) {}

/// The page fetched a font and wrote it into an SkData in skwasm's memory.
/// Registered under the page's name if it gave one, else the demo's.
@_expose(wasm, "starling_font_loaded")
@_cdecl("starling_font_loaded")
func starlingFontLoaded(_ data: sk_ptr, _ family: UnsafePointer<UInt8>?, _ familyLength: Int32)
    -> Int32
{
    let typeface = typeface_create(data)
    skData_dispose(data)
    guard typeface != 0 else { return 0 }
    var familyName = fontFamily
    if let family, familyLength > 0 {
        familyName = String(
            decoding: UnsafeBufferPointer(start: family, count: Int(familyLength)), as: UTF8.self)
    }
    let name = makeSkString(familyName)
    fontCollection_registerTypeface(fontCollection, typeface, name)
    skString_free(name)
    if familyName == fontFamily {
        fontReady = true
        scheduleFrame()
    }
    return 1
}

@_expose(wasm, "starling_alloc")
@_cdecl("starling_alloc")
func starlingAlloc(_ byteCount: Int32) -> UnsafeMutableRawPointer? {
    UnsafeMutableRawPointer.allocate(byteCount: Int(max(byteCount, 1)), alignment: 8)
}

@_expose(wasm, "starling_free")
@_cdecl("starling_free")
func starlingFree(_ pointer: UnsafeMutableRawPointer?) {
    pointer?.deallocate()
}

@_expose(wasm, "starling_begin_frame")
@_cdecl("starling_begin_frame")
func starlingBeginFrame(_ milliseconds: Double) {
    guard viewWidth > 0, viewHeight > 0 else {
        frameScheduled = false
        return
    }
    frameCount += 1

    let recorder = pictureRecorder_create()
    let canvas = withSkStack { stack in
        pictureRecorder_beginRecording(
            recorder,
            stack.floats([0, 0, viewWidth * pixelRatio, viewHeight * pixelRatio]))
    }
    draw(on: canvas, at: Float(milliseconds / 1000))
    let picture = pictureRecorder_endRecording(recorder)
    pictureRecorder_dispose(recorder)

    _ = withSkStack { stack in
        surface_renderPictures(
            surface, stack.pointers([picture]),
            Int32(viewWidth * pixelRatio), Int32(viewHeight * pixelRatio), 1)
    }
    // renderPictures took its own reference.
    picture_dispose(picture)
}

/// The page has put the frame on screen.
@_expose(wasm, "starling_frame_presented")
@_cdecl("starling_frame_presented")
func starlingFramePresented() {
    frameScheduled = false
    scheduleFrame()  // the demo animates; an app would wait to be dirtied
}

// MARK: - Start

surface_setCallbackHandler(surface, starling_host_render_callback())
print("starling: wasm module up, Int is \(MemoryLayout<Int>.size * 8)-bit")
