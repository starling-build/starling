// CanvasBridge and PictureBridge over skwasm's picture recorder.
import CSkwasm

/// What the canvas needs to know about the view it will end up in.
public enum WebView {
    /// Shadows are drawn in device pixels. Set by the host on every metrics
    /// change; natively the bridge reads it from the engine's registry.
    nonisolated(unsafe) public static var devicePixelRatio: Float = 1
}

@inline(__always) private func f(_ v: Double) -> Float { Float(v) }

/// "", for the life of the process.
nonisolated(unsafe) private let noError: UnsafePointer<CChar> = {
    let p = UnsafeMutablePointer<CChar>.allocate(capacity: 1)
    p.pointee = 0
    return UnsafePointer(p)
}()

extension flutter.swift_bridge {
    public final class CanvasBridge {
        /// The DisplayListBuilder. Valid until a picture is taken.
        public private(set) var skHandle: sk_ptr
        private var recorder: sk_ptr

        public init(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double) {
            let recorder = pictureRecorder_create()
            self.recorder = recorder
            skHandle = withSkStack { stack in
                pictureRecorder_beginRecording(
                    recorder, stack.rect(f(left), f(top), f(right), f(bottom)))
            }
        }

        deinit {
            if recorder != 0 {
                // Never turned into a picture: finish the recording so the
                // builder is released, and drop the result.
                picture_dispose(pictureRecorder_endRecording(recorder))
                pictureRecorder_dispose(recorder)
            }
        }

        /// Ends the recording. The canvas is dead afterwards, as it is
        /// natively once PictureBridge has taken its display list.
        func takePicture() -> sk_ptr {
            guard recorder != 0 else { return 0 }
            let picture = pictureRecorder_endRecording(recorder)
            pictureRecorder_dispose(recorder)
            recorder = 0
            skHandle = 0
            return picture
        }

        // MARK: Save and restore

        public func Save() { if skHandle != 0 { canvas_save(skHandle) } }

        public func SaveLayer(
            _ hasBounds: Bool, _ left: Double, _ top: Double, _ right: Double,
            _ bottom: Double, _ paintData: UnsafeRawPointer?, _ shader: UnsafeRawPointer?,
            _ colorFilter: UnsafeRawPointer?, _ imageFilter: UnsafeRawPointer?
        ) {
            guard skHandle != 0 else { return }
            withWebPaint(paintData, shader, colorFilter, imageFilter) { paint in
                withSkStack { stack in
                    let bounds =
                        hasBounds ? stack.rect(f(left), f(top), f(right), f(bottom)) : 0
                    canvas_saveLayer(skHandle, bounds, paint, 0)
                }
            }
        }

        public func Restore() { if skHandle != 0 { canvas_restore(skHandle) } }

        public func RestoreToCount(_ count: Int32) {
            if skHandle != 0, count < GetSaveCount() { canvas_restoreToCount(skHandle, count) }
        }

        public func GetSaveCount() -> Int32 {
            skHandle != 0 ? canvas_getSaveCount(skHandle) : 0
        }

        // MARK: Transform

        public func Translate(_ dx: Double, _ dy: Double) {
            if skHandle != 0 { canvas_translate(skHandle, f(dx), f(dy)) }
        }

        public func Scale(_ sx: Double, _ sy: Double) {
            if skHandle != 0 { canvas_scale(skHandle, f(sx), f(sy)) }
        }

        public func Rotate(_ radians: Double) {
            if skHandle != 0 { canvas_rotate(skHandle, f(radians * 180 / .pi)) }
        }

        public func Skew(_ sx: Double, _ sy: Double) {
            if skHandle != 0 { canvas_skew(skHandle, f(sx), f(sy)) }
        }

        /// Sixteen doubles, column-major — which is also DlMatrix's layout,
        /// so they go across in order.
        public func Transform(_ matrix4: UnsafePointer<Double>?) {
            guard skHandle != 0, let matrix4 else { return }
            withSkStack { stack in
                canvas_transform(skHandle, stack.array((0..<16).map { f(matrix4[$0]) }))
            }
        }

        public func GetTransform(_ out: UnsafeMutablePointer<Double>?) {
            guard skHandle != 0, let out else { return }
            withSkStack { stack in
                let p = stack.alloc(64)
                canvas_getTransform(skHandle, p)
                let m: [Float] = skRead(p, count: 16)
                for i in 0..<16 { out[i] = Double(m[i]) }
            }
        }

        // MARK: Clip

        public func ClipRect(
            _ left: Double, _ top: Double, _ right: Double, _ bottom: Double,
            _ clipOp: Int32, _ antiAlias: Bool
        ) {
            guard skHandle != 0 else { return }
            withSkStack { stack in
                canvas_clipRect(
                    skHandle, stack.rect(f(left), f(top), f(right), f(bottom)), clipOp,
                    antiAlias)
            }
        }

        public func ClipRRect(_ rrect: UnsafePointer<Float>?, _ antiAlias: Bool) {
            guard skHandle != 0, let rrect else { return }
            withSkStack { stack in
                canvas_clipRRect(skHandle, stack.copy(rrect, count: 12), antiAlias)
            }
        }

        // WEB-TODO: skwasm has no superellipse. A rounded rectangle with the
        // same radii is drawn instead; the corners are slightly less full.
        public func ClipRSuperellipse(
            _ left: Double, _ top: Double, _ right: Double, _ bottom: Double,
            _ tlX: Double, _ tlY: Double, _ trX: Double, _ trY: Double,
            _ brX: Double, _ brY: Double, _ blX: Double, _ blY: Double,
            _ antiAlias: Bool
        ) {
            guard skHandle != 0 else { return }
            withSkStack { stack in
                canvas_clipRRect(
                    skHandle,
                    stack.floats([
                        f(left), f(top), f(right), f(bottom), f(tlX), f(tlY), f(trX),
                        f(trY), f(brX), f(brY), f(blX), f(blY),
                    ]), antiAlias)
            }
        }

        public func ClipPath(_ path: PathBridge?, _ antiAlias: Bool) {
            guard skHandle != 0, let path else { return }
            canvas_clipPath(skHandle, path.skHandle, antiAlias)
        }

        public func GetLocalClipBounds(_ out: UnsafeMutablePointer<Double>?) {
            guard skHandle != 0, let out else { return }
            withSkStack { stack in
                let p = stack.alloc(16)
                canvas_getLocalClipBounds(skHandle, p)
                let r: [Float] = skRead(p, count: 4)
                for i in 0..<4 { out[i] = Double(r[i]) }
            }
        }

        public func GetDestinationClipBounds(_ out: UnsafeMutablePointer<Double>?) {
            guard skHandle != 0, let out else { return }
            withSkStack { stack in
                let p = stack.alloc(16)
                canvas_getDeviceClipBounds(skHandle, p)
                let r: [Int32] = skRead(p, count: 4)
                for i in 0..<4 { out[i] = Double(r[i]) }
            }
        }

        // MARK: Draw

        public func DrawColor(_ color: Int32, _ blendMode: Int32) {
            if skHandle != 0 {
                canvas_drawColor(skHandle, UInt32(bitPattern: color), blendMode)
            }
        }

        public func DrawLine(
            _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double,
            _ paintData: UnsafeRawPointer?, _ shader: UnsafeRawPointer?,
            _ colorFilter: UnsafeRawPointer?, _ imageFilter: UnsafeRawPointer?
        ) {
            guard skHandle != 0 else { return }
            withWebPaint(paintData, shader, colorFilter, imageFilter) {
                canvas_drawLine(skHandle, f(x1), f(y1), f(x2), f(y2), $0)
            }
        }

        public func DrawPaint(
            _ paintData: UnsafeRawPointer?, _ shader: UnsafeRawPointer?,
            _ colorFilter: UnsafeRawPointer?, _ imageFilter: UnsafeRawPointer?
        ) {
            guard skHandle != 0 else { return }
            withWebPaint(paintData, shader, colorFilter, imageFilter) {
                canvas_drawPaint(skHandle, $0)
            }
        }

        public func DrawRect(
            _ left: Double, _ top: Double, _ right: Double, _ bottom: Double,
            _ paintData: UnsafeRawPointer?, _ shader: UnsafeRawPointer?,
            _ colorFilter: UnsafeRawPointer?, _ imageFilter: UnsafeRawPointer?
        ) {
            guard skHandle != 0 else { return }
            withWebPaint(paintData, shader, colorFilter, imageFilter) { paint in
                withSkStack { stack in
                    canvas_drawRect(
                        skHandle, stack.rect(f(left), f(top), f(right), f(bottom)), paint)
                }
            }
        }

        public func DrawRRect(
            _ rrect: UnsafePointer<Float>?, _ paintData: UnsafeRawPointer?,
            _ shader: UnsafeRawPointer?, _ colorFilter: UnsafeRawPointer?,
            _ imageFilter: UnsafeRawPointer?
        ) {
            guard skHandle != 0, let rrect else { return }
            withWebPaint(paintData, shader, colorFilter, imageFilter) { paint in
                withSkStack { stack in
                    canvas_drawRRect(skHandle, stack.copy(rrect, count: 12), paint)
                }
            }
        }

        public func DrawDRRect(
            _ outer: UnsafePointer<Float>?, _ inner: UnsafePointer<Float>?,
            _ paintData: UnsafeRawPointer?, _ shader: UnsafeRawPointer?,
            _ colorFilter: UnsafeRawPointer?, _ imageFilter: UnsafeRawPointer?
        ) {
            guard skHandle != 0, let outer, let inner else { return }
            withWebPaint(paintData, shader, colorFilter, imageFilter) { paint in
                withSkStack { stack in
                    canvas_drawDRRect(
                        skHandle, stack.copy(outer, count: 12),
                        stack.copy(inner, count: 12), paint)
                }
            }
        }

        // WEB-TODO: drawn as a rounded rectangle; see ClipRSuperellipse.
        public func DrawRSuperellipse(
            _ left: Double, _ top: Double, _ right: Double, _ bottom: Double,
            _ tlX: Double, _ tlY: Double, _ trX: Double, _ trY: Double,
            _ brX: Double, _ brY: Double, _ blX: Double, _ blY: Double,
            _ paintData: UnsafeRawPointer?, _ shader: UnsafeRawPointer?,
            _ colorFilter: UnsafeRawPointer?, _ imageFilter: UnsafeRawPointer?
        ) {
            guard skHandle != 0 else { return }
            withWebPaint(paintData, shader, colorFilter, imageFilter) { paint in
                withSkStack { stack in
                    canvas_drawRRect(
                        skHandle,
                        stack.floats([
                            f(left), f(top), f(right), f(bottom), f(tlX), f(tlY), f(trX),
                            f(trY), f(brX), f(brY), f(blX), f(blY),
                        ]), paint)
                }
            }
        }

        public func DrawOval(
            _ left: Double, _ top: Double, _ right: Double, _ bottom: Double,
            _ paintData: UnsafeRawPointer?, _ shader: UnsafeRawPointer?,
            _ colorFilter: UnsafeRawPointer?, _ imageFilter: UnsafeRawPointer?
        ) {
            guard skHandle != 0 else { return }
            withWebPaint(paintData, shader, colorFilter, imageFilter) { paint in
                withSkStack { stack in
                    canvas_drawOval(
                        skHandle, stack.rect(f(left), f(top), f(right), f(bottom)), paint)
                }
            }
        }

        public func DrawCircle(
            _ x: Double, _ y: Double, _ radius: Double,
            _ paintData: UnsafeRawPointer?, _ shader: UnsafeRawPointer?,
            _ colorFilter: UnsafeRawPointer?, _ imageFilter: UnsafeRawPointer?
        ) {
            guard skHandle != 0 else { return }
            withWebPaint(paintData, shader, colorFilter, imageFilter) {
                canvas_drawCircle(skHandle, f(x), f(y), f(radius), $0)
            }
        }

        /// Angles arrive in radians; skwasm, like DisplayList, wants degrees.
        public func DrawArc(
            _ left: Double, _ top: Double, _ right: Double, _ bottom: Double,
            _ startAngle: Double, _ sweepAngle: Double, _ useCenter: Bool,
            _ paintData: UnsafeRawPointer?, _ shader: UnsafeRawPointer?,
            _ colorFilter: UnsafeRawPointer?, _ imageFilter: UnsafeRawPointer?
        ) {
            guard skHandle != 0 else { return }
            withWebPaint(paintData, shader, colorFilter, imageFilter) { paint in
                withSkStack { stack in
                    canvas_drawArc(
                        skHandle, stack.rect(f(left), f(top), f(right), f(bottom)),
                        f(startAngle * 180 / .pi), f(sweepAngle * 180 / .pi), useCenter,
                        paint)
                }
            }
        }

        public func DrawPath(
            _ path: PathBridge?, _ paintData: UnsafeRawPointer?,
            _ shader: UnsafeRawPointer?, _ colorFilter: UnsafeRawPointer?,
            _ imageFilter: UnsafeRawPointer?
        ) {
            guard skHandle != 0, let path else { return }
            withWebPaint(paintData, shader, colorFilter, imageFilter) {
                canvas_drawPath(skHandle, path.skHandle, $0)
            }
        }

        // The image draws return an error string natively, empty on success,
        // and the caller reads it without checking for nil.

        public func DrawImage(
            _ image: ImageBridge?, _ x: Double, _ y: Double,
            _ paintData: UnsafeRawPointer?, _ shader: UnsafeRawPointer?,
            _ colorFilter: UnsafeRawPointer?, _ imageFilter: UnsafeRawPointer?,
            _ filterQuality: Int32
        ) -> UnsafePointer<CChar> {
            guard skHandle != 0, let image, image.skHandle != 0 else { return noError }
            withWebPaint(paintData, shader, colorFilter, imageFilter) {
                canvas_drawImage(skHandle, image.skHandle, f(x), f(y), $0, filterQuality)
            }
            return noError
        }

        public func DrawImageRect(
            _ image: ImageBridge?, _ srcLeft: Double, _ srcTop: Double,
            _ srcRight: Double, _ srcBottom: Double, _ dstLeft: Double, _ dstTop: Double,
            _ dstRight: Double, _ dstBottom: Double, _ paintData: UnsafeRawPointer?,
            _ shader: UnsafeRawPointer?, _ colorFilter: UnsafeRawPointer?,
            _ imageFilter: UnsafeRawPointer?, _ filterQuality: Int32
        ) -> UnsafePointer<CChar> {
            guard skHandle != 0, let image, image.skHandle != 0 else { return noError }
            withWebPaint(paintData, shader, colorFilter, imageFilter) { paint in
                withSkStack { stack in
                    canvas_drawImageRect(
                        skHandle, image.skHandle,
                        stack.rect(f(srcLeft), f(srcTop), f(srcRight), f(srcBottom)),
                        stack.rect(f(dstLeft), f(dstTop), f(dstRight), f(dstBottom)),
                        paint, filterQuality)
                }
            }
            return noError
        }

        public func DrawImageNine(
            _ image: ImageBridge?, _ centerLeft: Double, _ centerTop: Double,
            _ centerRight: Double, _ centerBottom: Double, _ dstLeft: Double,
            _ dstTop: Double, _ dstRight: Double, _ dstBottom: Double,
            _ paintData: UnsafeRawPointer?, _ shader: UnsafeRawPointer?,
            _ colorFilter: UnsafeRawPointer?, _ imageFilter: UnsafeRawPointer?,
            _ filterQuality: Int32
        ) -> UnsafePointer<CChar> {
            guard skHandle != 0, let image, image.skHandle != 0 else { return noError }
            withWebPaint(paintData, shader, colorFilter, imageFilter) { paint in
                withSkStack { stack in
                    // The centre is an integer rect: floor the near edges,
                    // ceil the far ones, as the Dart side does.
                    let center: [Int32] = [
                        Int32(centerLeft.rounded(.down)), Int32(centerTop.rounded(.down)),
                        Int32(centerRight.rounded(.up)), Int32(centerBottom.rounded(.up)),
                    ]
                    canvas_drawImageNine(
                        skHandle, image.skHandle, stack.array(center),
                        stack.rect(f(dstLeft), f(dstTop), f(dstRight), f(dstBottom)),
                        paint, filterQuality)
                }
            }
            return noError
        }

        public func DrawDisplayList(_ displayList: UnsafeRawPointer?) {
            let picture = FlutterSwiftBridgeCxx.skHandle(from: displayList)
            if skHandle != 0, picture != 0 { canvas_drawPicture(skHandle, picture) }
        }

        public func DrawPoints(
            _ pointMode: Int32, _ points: UnsafePointer<Float>?, _ pointCount: Int32,
            _ paintData: UnsafeRawPointer?, _ shader: UnsafeRawPointer?,
            _ colorFilter: UnsafeRawPointer?, _ imageFilter: UnsafeRawPointer?
        ) {
            guard skHandle != 0, let points, pointCount > 0 else { return }
            withWebPaint(paintData, shader, colorFilter, imageFilter) { paint in
                withSkStack { stack in
                    canvas_drawPoints(
                        skHandle, pointMode, stack.copy(points, count: Int(pointCount) * 2),
                        pointCount, paint)
                }
            }
        }

        public func DrawVertices(
            _ vertices: VerticesBridge?, _ blendMode: Int32,
            _ paintData: UnsafeRawPointer?, _ shader: UnsafeRawPointer?,
            _ colorFilter: UnsafeRawPointer?, _ imageFilter: UnsafeRawPointer?
        ) {
            guard skHandle != 0, let vertices, vertices.skHandle != 0 else { return }
            withWebPaint(paintData, shader, colorFilter, imageFilter) {
                canvas_drawVertices(skHandle, vertices.skHandle, blendMode, $0)
            }
        }

        public func DrawAtlas(
            _ atlas: ImageBridge?, _ transforms: UnsafePointer<Float>?,
            _ rects: UnsafePointer<Float>?, _ rectCount: Int32,
            _ colors: UnsafePointer<Int32>?, _ colorCount: Int32, _ blendMode: Int32,
            _ cullRect: UnsafePointer<Float>?, _ paintData: UnsafeRawPointer?,
            _ shader: UnsafeRawPointer?, _ colorFilter: UnsafeRawPointer?,
            _ imageFilter: UnsafeRawPointer?, _ filterQuality: Int32
        ) -> UnsafePointer<CChar> {
            guard skHandle != 0, let atlas, atlas.skHandle != 0, rectCount > 0 else {
                return noError
            }
            // WEB-TODO: skwasm's drawAtlas takes no sampling argument, so
            // filterQuality is dropped.
            withWebPaint(paintData, shader, colorFilter, imageFilter) { paint in
                withSkStack { stack in
                    let n = Int(rectCount)
                    canvas_drawAtlas(
                        skHandle, atlas.skHandle, stack.copy(transforms, count: n * 4),
                        stack.copy(rects, count: n * 4),
                        colorCount > 0 ? stack.copy(colors, count: Int(colorCount)) : 0,
                        rectCount, blendMode, stack.copy(cullRect, count: 4), paint)
                }
            }
            return noError
        }

        public func DrawShadow(
            _ path: PathBridge?, _ color: Int32, _ elevation: Double,
            _ transparentOccluder: Bool
        ) {
            guard skHandle != 0, let path else { return }
            canvas_drawShadow(
                skHandle, path.skHandle, f(elevation), WebView.devicePixelRatio,
                UInt32(bitPattern: color), transparentOccluder)
        }

        /// The paragraph is not a bridge method natively — ParagraphBridge
        /// paints itself into the builder it is given — so this is ours.
        public func drawParagraph(_ paragraph: sk_ptr, _ x: Double, _ y: Double) {
            if skHandle != 0, paragraph != 0 {
                canvas_drawParagraph(skHandle, paragraph, f(x), f(y))
            }
        }

        public func Invalidate() {}

        public func GetDisplayListBuilderPtr() -> UnsafeRawPointer? { skOpaque(skHandle) }
    }

    public final class PictureBridge {
        /// The DisplayList. 0 once disposed.
        public private(set) var skHandle: sk_ptr

        public init(_ canvas: CanvasBridge?) {
            skHandle = canvas?.takePicture() ?? 0
        }

        deinit { Dispose() }

        public func GetAllocationSize() -> Int64 {
            skHandle != 0 ? Int64(picture_approximateBytesUsed(skHandle)) : 0
        }

        public func GetDisplayListPtr() -> UnsafeRawPointer? { skOpaque(skHandle) }

        public func Dispose() {
            if skHandle != 0 {
                picture_dispose(skHandle)
                skHandle = 0
            }
        }

        // WEB-TODO: a synchronous picture-to-image needs a CPU raster, which
        // skwasm does not export. nil takes the caller's failure path.
        public func ToImage(_ width: Int32, _ height: Int32) -> ImageBridge? { nil }

        public func IsDisposed() -> Bool { skHandle == 0 }
    }
}
