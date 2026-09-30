// PathBridge and PathMeasureBridge, over skwasm's path.cpp and
// contour_measure.cpp.
import CSkwasm

/// A buffer on skwasm's HEAP, for arrays whose size the caller decides
/// (polygon points, vertex data). skwasm's stack is small and fixed; Flutter's
/// Dart code does put these on it, but a large mesh would run off the end.
struct SkHeapArray {
    private let data: sk_ptr
    /// The address of the first element, in skwasm's memory. 0 if empty.
    let pointer: sk_ptr

    /// Copies `count` elements from `source`, then pads with zeroed elements
    /// up to `capacity` — skwasm reads as many as ITS count argument says, so
    /// a short array must not leave it reading past the end.
    init<T>(_ source: UnsafePointer<T>?, count: Int, capacity: Int? = nil, as: T.Type = T.self) {
        let total = max(capacity ?? count, 0)
        guard let source, total > 0 else {
            data = 0
            pointer = 0
            return
        }
        let stride = MemoryLayout<T>.stride
        data = skData_create(UInt32(total * stride))
        pointer = skData_getPointer(data)
        let copied = min(max(count, 0), total)
        skWrite(pointer, source, count: copied)
        if copied < total {
            let padding = [UInt8](repeating: 0, count: (total - copied) * stride)
            padding.withUnsafeBufferPointer {
                skWrite(pointer + UInt32(copied * stride), $0.baseAddress, count: $0.count)
            }
        }
    }

    func dispose() {
        if data != 0 { skData_dispose(data) }
    }
}

extension flutter.swift_bridge {
    public final class PathBridge {
        /// The SkPath. Never 0. It is a `var` because Op and
        /// SetFromSkHandle replace the path rather than edit it.
        public private(set) var skHandle: sk_ptr

        public init() { skHandle = path_create() }

        /// Takes ownership of an SkPath that skwasm handed out (a copy, a
        /// combined path, a measured segment).
        public init(adopting handle: sk_ptr) {
            skHandle = handle != 0 ? handle : path_create()
        }

        deinit { path_dispose(skHandle) }

        public static func Clone(_ source: PathBridge?) -> PathBridge! {
            guard let source else { return PathBridge() }
            return PathBridge(adopting: path_copy(source.skHandle))
        }

        /// Replaces this path with a copy of the SkPath at `handle`. The
        /// web's form of SetFromSkPathPtr, which takes a real pointer and so
        /// cannot exist here (nor can GetSkPathPtr: use `skHandle`).
        public func SetFromSkHandle(_ handle: sk_ptr) {
            guard handle != 0, handle != skHandle else { return }
            let copy = path_copy(handle)
            path_dispose(skHandle)
            skHandle = copy
        }

        // MARK: Fill type

        // SkPathFillType on both sides, and dart:ui's PathFillType has the
        // same values for the two it defines (0 nonZero, 1 evenOdd).
        public func GetFillType() -> Int32 { path_getFillType(skHandle) }
        public func SetFillType(_ fill_type: Int32) { path_setFillType(skHandle, fill_type) }

        // MARK: Segments

        public func MoveTo(_ x: Double, _ y: Double) {
            path_moveTo(skHandle, pathNarrow(x), pathNarrow(y))
        }

        public func RelativeMoveTo(_ dx: Double, _ dy: Double) {
            path_relativeMoveTo(skHandle, pathNarrow(dx), pathNarrow(dy))
        }

        public func LineTo(_ x: Double, _ y: Double) {
            path_lineTo(skHandle, pathNarrow(x), pathNarrow(y))
        }

        public func RelativeLineTo(_ dx: Double, _ dy: Double) {
            path_relativeLineTo(skHandle, pathNarrow(dx), pathNarrow(dy))
        }

        public func QuadraticBezierTo(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
            path_quadraticBezierTo(
                skHandle, pathNarrow(x1), pathNarrow(y1), pathNarrow(x2), pathNarrow(y2))
        }

        public func RelativeQuadraticBezierTo(
            _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double
        ) {
            path_relativeQuadraticBezierTo(
                skHandle, pathNarrow(x1), pathNarrow(y1), pathNarrow(x2), pathNarrow(y2))
        }

        public func CubicTo(
            _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x3: Double, _ y3: Double
        ) {
            path_cubicTo(
                skHandle, pathNarrow(x1), pathNarrow(y1), pathNarrow(x2), pathNarrow(y2),
                pathNarrow(x3), pathNarrow(y3))
        }

        public func RelativeCubicTo(
            _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x3: Double, _ y3: Double
        ) {
            path_relativeCubicTo(
                skHandle, pathNarrow(x1), pathNarrow(y1), pathNarrow(x2), pathNarrow(y2),
                pathNarrow(x3), pathNarrow(y3))
        }

        public func ConicTo(
            _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ w: Double
        ) {
            path_conicTo(
                skHandle, pathNarrow(x1), pathNarrow(y1), pathNarrow(x2), pathNarrow(y2),
                pathNarrow(w))
        }

        public func RelativeConicTo(
            _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ w: Double
        ) {
            path_relativeConicTo(
                skHandle, pathNarrow(x1), pathNarrow(y1), pathNarrow(x2), pathNarrow(y2),
                pathNarrow(w))
        }

        // MARK: Arcs

        /// dart:ui gives angles in radians; SkPath wants degrees.
        private static func degrees(_ radians: Double) -> Float {
            pathNarrow(radians) * 180 / Float.pi
        }

        public func ArcTo(
            _ left: Double, _ top: Double, _ right: Double, _ bottom: Double,
            _ start_angle: Double, _ sweep_angle: Double, _ force_move_to: Bool
        ) {
            withSkStack { stack in
                path_arcToOval(
                    skHandle,
                    stack.rect(
                        pathNarrow(left), pathNarrow(top), pathNarrow(right),
                        pathNarrow(bottom)),
                    Self.degrees(start_angle), Self.degrees(sweep_angle), force_move_to)
            }
        }

        // `rotation` is already in degrees here (Path.arcToPoint documents
        // it so), and goes through untouched as it does natively.
        public func ArcToPoint(
            _ arc_end_x: Double, _ arc_end_y: Double, _ radius_x: Double, _ radius_y: Double,
            _ rotation: Double, _ large_arc: Bool, _ clockwise: Bool
        ) {
            path_arcToRotated(
                skHandle, pathNarrow(radius_x), pathNarrow(radius_y), pathNarrow(rotation),
                large_arc ? 1 : 0, clockwise ? 0 : 1,
                pathNarrow(arc_end_x), pathNarrow(arc_end_y))
        }

        public func RelativeArcToPoint(
            _ arc_end_dx: Double, _ arc_end_dy: Double, _ radius_x: Double,
            _ radius_y: Double, _ rotation: Double, _ large_arc: Bool, _ clockwise: Bool
        ) {
            path_relativeArcToRotated(
                skHandle, pathNarrow(radius_x), pathNarrow(radius_y), pathNarrow(rotation),
                large_arc ? 1 : 0, clockwise ? 0 : 1,
                pathNarrow(arc_end_dx), pathNarrow(arc_end_dy))
        }

        // MARK: Shapes

        public func AddRect(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double) {
            withSkStack { stack in
                path_addRect(
                    skHandle,
                    stack.rect(
                        pathNarrow(left), pathNarrow(top), pathNarrow(right),
                        pathNarrow(bottom)))
            }
        }

        public func AddOval(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double) {
            withSkStack { stack in
                path_addOval(
                    skHandle,
                    stack.rect(
                        pathNarrow(left), pathNarrow(top), pathNarrow(right),
                        pathNarrow(bottom)))
            }
        }

        public func AddArc(
            _ left: Double, _ top: Double, _ right: Double, _ bottom: Double,
            _ start_angle: Double, _ sweep_angle: Double
        ) {
            withSkStack { stack in
                path_addArc(
                    skHandle,
                    stack.rect(
                        pathNarrow(left), pathNarrow(top), pathNarrow(right),
                        pathNarrow(bottom)),
                    Self.degrees(start_angle), Self.degrees(sweep_angle))
            }
        }

        /// `points` holds `point_count` x,y pairs.
        public func AddPolygon(
            _ points: UnsafePointer<Float>?, _ point_count: Int32, _ close: Bool
        ) {
            guard points != nil, point_count > 0 else { return }
            let buffer = SkHeapArray(points, count: Int(point_count) * 2)
            defer { buffer.dispose() }
            path_addPolygon(skHandle, buffer.pointer, point_count, close)
        }

        /// 12 floats: LTRB, then x,y radii for TL, TR, BR, BL — the layout
        /// skwasm's createSkRRect reads, so they pass through as they are.
        public func AddRRect(_ rrect_values: UnsafePointer<Float>?) {
            guard rrect_values != nil else { return }
            withSkStack { stack in
                path_addRRect(skHandle, stack.copy(rrect_values, count: 12))
            }
        }

        /// skwasm cannot draw this shape itself, so the outline is computed
        /// here and added as cubics, as the native bridge's path builder does.
        public func AddRSuperellipse(
            _ left: Double, _ top: Double, _ right: Double, _ bottom: Double,
            _ tl_rx: Double, _ tl_ry: Double, _ tr_rx: Double, _ tr_ry: Double,
            _ br_rx: Double, _ br_ry: Double, _ bl_rx: Double, _ bl_ry: Double
        ) {
            let bounds = SERect(
                left: pathNarrow(left), top: pathNarrow(top),
                right: pathNarrow(right), bottom: pathNarrow(bottom)
            ).positive
            let radii = SERadii(
                topLeft: SEPoint(pathNarrow(tl_rx), pathNarrow(tl_ry)),
                topRight: SEPoint(pathNarrow(tr_rx), pathNarrow(tr_ry)),
                bottomRight: SEPoint(pathNarrow(br_rx), pathNarrow(br_ry)),
                bottomLeft: SEPoint(pathNarrow(bl_rx), pathNarrow(bl_ry))
            ).scaled(to: bounds)
            RoundSuperellipseParam(bounds: bounds, radii: radii)
                .dispatch(to: Receiver(path: skHandle))
        }

        private struct Receiver: SEPathReceiver {
            let path: sk_ptr
            func moveTo(_ p: SEPoint) { path_moveTo(path, p.x, p.y) }
            func lineTo(_ p: SEPoint) { path_lineTo(path, p.x, p.y) }
            func cubicTo(_ cp1: SEPoint, _ cp2: SEPoint, _ p: SEPoint) {
                path_cubicTo(path, cp1.x, cp1.y, cp2.x, cp2.y, p.x, p.y)
            }
            func close() { path_close(path) }
        }

        // MARK: Paths and matrices

        /// A translation as an SkMatrix: 9 floats, row-major.
        private static func translation(_ dx: Double, _ dy: Double) -> [Float] {
            [1, 0, pathNarrow(dx), 0, 1, pathNarrow(dy), 0, 0, 1]
        }

        /// dart:ui's column-major 4x4 as an SkMatrix. Row by row, the 3x3
        /// takes the 4x4's x, y and perspective rows and its x, y and
        /// translation columns: indices 0,4,12 / 1,5,13 / 3,7,15.
        private static func matrix33(_ matrix4: UnsafePointer<Double>) -> [Float] {
            [0, 4, 12, 1, 5, 13, 3, 7, 15].map { pathNarrow(matrix4[$0]) }
        }

        private func add(
            _ path: PathBridge?, _ dx: Double, _ dy: Double,
            _ matrix4: UnsafePointer<Double>?, extend: Bool
        ) {
            guard let path else { return }
            var matrix: [Float]
            if let matrix4 {
                matrix = Self.matrix33(matrix4)
                matrix[2] += pathNarrow(dx)
                matrix[5] += pathNarrow(dy)
            } else {
                matrix = Self.translation(dx, dy)
            }
            // SkPath::AddPathMode: 0 appends a new contour, 1 extends the
            // last one with a line to the added path's start.
            withSkStack { stack in
                path_addPath(skHandle, path.skHandle, stack.floats(matrix), extend ? 1 : 0)
            }
        }

        public func AddPath(_ path: PathBridge?, _ dx: Double, _ dy: Double) {
            add(path, dx, dy, nil, extend: false)
        }

        public func AddPathWithMatrix(
            _ path: PathBridge?, _ dx: Double, _ dy: Double, _ matrix4: UnsafePointer<Double>?
        ) {
            add(path, dx, dy, matrix4, extend: false)
        }

        public func ExtendWithPath(_ path: PathBridge?, _ dx: Double, _ dy: Double) {
            add(path, dx, dy, nil, extend: true)
        }

        public func ExtendWithPathAndMatrix(
            _ path: PathBridge?, _ dx: Double, _ dy: Double, _ matrix4: UnsafePointer<Double>?
        ) {
            add(path, dx, dy, matrix4, extend: true)
        }

        public func Close() { path_close(skHandle) }
        public func Reset() { path_reset(skHandle) }

        // MARK: Queries and derived paths

        public func Contains(_ x: Double, _ y: Double) -> Bool {
            path_contains(skHandle, pathNarrow(x), pathNarrow(y))
        }

        // skwasm transforms in place, so both of these copy first.
        public static func Shift(_ source: PathBridge?, _ dx: Double, _ dy: Double)
            -> PathBridge!
        {
            guard let source else { return PathBridge() }
            let copy = path_copy(source.skHandle)
            withSkStack { stack in
                path_transform(copy, stack.floats(translation(dx, dy)))
            }
            return PathBridge(adopting: copy)
        }

        public static func Transform(_ source: PathBridge?, _ matrix4: UnsafePointer<Double>?)
            -> PathBridge!
        {
            guard let source else { return PathBridge() }
            let copy = path_copy(source.skHandle)
            if let matrix4 {
                withSkStack { stack in
                    path_transform(copy, stack.floats(matrix33(matrix4)))
                }
            }
            return PathBridge(adopting: copy)
        }

        /// Writes 4 floats, LTRB.
        public func GetBounds(_ out_bounds: UnsafeMutablePointer<Float>?) {
            guard let out_bounds else { return }
            let bounds: [Float] = withSkStack { stack in
                let rect = stack.alloc(4 * MemoryLayout<Float>.stride)
                path_getBounds(skHandle, rect)
                return stack.read(rect, count: 4)
            }
            for i in 0..<4 { out_bounds[i] = bounds[i] }
        }

        /// Makes this path the result of combining the other two.
        /// `operation` is SkPathOp, which dart:ui's PathOperation matches
        /// value for value. False, with this path untouched, if Skia cannot
        /// do it (NaNs in a path, typically).
        public func Op(_ path1: PathBridge?, _ path2: PathBridge?, _ operation: Int32) -> Bool {
            guard let path1, let path2 else { return false }
            let combined = path_combine(operation, path1.skHandle, path2.skHandle)
            guard combined != 0 else { return false }
            path_dispose(skHandle)
            skHandle = combined
            return true
        }
    }

    public final class PathMeasureBridge {
        /// The SkContourMeasureIter. It keeps its own copy of the path, so
        /// the PathBridge it was made from may change or go away.
        public let skHandle: sk_ptr

        /// The contours reached so far, by index: SkContourMeasure objects,
        /// each holding a reference that deinit gives back.
        private var measures: [sk_ptr] = []

        public init(_ path: PathBridge?, _ force_closed: Bool) {
            // resScale 1, as the native bridge and Flutter's web engine use.
            if let path {
                skHandle = contourMeasureIter_create(path.skHandle, force_closed, 1)
            } else {
                let empty = path_create()
                skHandle = contourMeasureIter_create(empty, force_closed, 1)
                path_dispose(empty)
            }
        }

        deinit {
            for measure in measures { contourMeasure_dispose(measure) }
            contourMeasureIter_dispose(skHandle)
        }

        private func measure(_ contour_index: Int32) -> sk_ptr? {
            let index = Int(contour_index)
            return index >= 0 && index < measures.count ? measures[index] : nil
        }

        /// -1 for a contour that has not been reached.
        public func GetLength(_ contour_index: Int32) -> Double {
            guard let measure = measure(contour_index) else { return -1 }
            return Double(contourMeasure_length(measure))
        }

        /// Writes 5 floats: a success flag (0 or 1), then the position's x,y
        /// and the tangent's x,y. Only the flag is written on failure.
        public func GetPosTan(
            _ contour_index: Int32, _ distance: Double,
            _ out_values: UnsafeMutablePointer<Float>?
        ) {
            guard let out_values else { return }
            out_values[0] = 0
            guard let measure = measure(contour_index) else { return }
            let values: [Float]? = withSkStack { stack in
                // Position and tangent side by side, read back in one go.
                let position = stack.alloc(4 * MemoryLayout<Float>.stride)
                let tangent = position + UInt32(2 * MemoryLayout<Float>.stride)
                guard
                    contourMeasure_getPosTan(measure, pathNarrow(distance), position, tangent)
                else { return nil }
                return stack.read(position, count: 4)
            }
            guard let values else { return }
            out_values[0] = 1
            for i in 0..<4 { out_values[i + 1] = values[i] }
        }

        /// The stretch of a contour between two distances; an empty path if
        /// there is none.
        public static func ExtractPath(
            _ measure: PathMeasureBridge?, _ contour_index: Int32, _ start: Double,
            _ end: Double, _ start_with_move_to: Bool
        ) -> PathBridge! {
            guard let contour = measure?.measure(contour_index) else { return PathBridge() }
            return PathBridge(
                adopting: contourMeasure_getSegment(
                    contour, pathNarrow(start), pathNarrow(end), start_with_move_to))
        }

        public func IsClosed(_ contour_index: Int32) -> Bool {
            guard let measure = measure(contour_index) else { return false }
            return contourMeasure_isClosed(measure)
        }

        public func NextContour() -> Bool {
            let next = contourMeasureIter_next(skHandle)
            guard next != 0 else { return false }
            measures.append(next)
            return true
        }
    }
}
