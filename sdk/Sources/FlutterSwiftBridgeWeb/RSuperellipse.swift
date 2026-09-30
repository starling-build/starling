// RSuperellipseBridge, and the rounded-superellipse geometry behind it.
//
// skwasm has no rounded superellipse of its own: Flutter's web engine turns
// one into a path in Dart before skwasm ever sees it. The native bridge gets
// its answers from impeller's RoundSuperellipseParam, so that is ported here
// (impeller/geometry/round_superellipse_param.cc), in Float like the
// original so containment agrees with the other platforms at the boundary.
// PathBridge.AddRSuperellipse draws from the same parameters.
#if canImport(WASILibc)
import WASILibc
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// `SafeNarrow` from the native bridge: a double narrowed to a float, with
/// finite values clamped to the float range rather than becoming infinite.
func pathNarrow(_ value: Double) -> Float {
    if value.isNaN || value.isInfinite { return Float(value) }
    let narrowed = Float(value)
    if narrowed.isInfinite {
        return value < 0 ? -Float.greatestFiniteMagnitude : Float.greatestFiniteMagnitude
    }
    return narrowed
}

/// impeller::Point (and Size, as width/height), as far as this port needs it.
struct SEPoint {
    var x: Float
    var y: Float

    init(_ x: Float, _ y: Float) {
        self.x = x
        self.y = y
    }

    static func + (a: SEPoint, b: SEPoint) -> SEPoint { SEPoint(a.x + b.x, a.y + b.y) }
    static func - (a: SEPoint, b: SEPoint) -> SEPoint { SEPoint(a.x - b.x, a.y - b.y) }
    static func * (a: SEPoint, b: SEPoint) -> SEPoint { SEPoint(a.x * b.x, a.y * b.y) }
    static func / (a: SEPoint, b: SEPoint) -> SEPoint { SEPoint(a.x / b.x, a.y / b.y) }
    static func * (a: SEPoint, s: Float) -> SEPoint { SEPoint(a.x * s, a.y * s) }
    static func / (a: SEPoint, s: Float) -> SEPoint { SEPoint(a.x / s, a.y / s) }

    var length: Float { (x * x + y * y).squareRoot() }
    var abs: SEPoint { SEPoint(Swift.abs(x), Swift.abs(y)) }
    var flipped: SEPoint { SEPoint(y, x) }
    /// Size::IsEmpty. Written as a negation so that NaN counts as empty.
    var isEmptySize: Bool { !(x > 0 && y > 0) }
    var isFinite: Bool { x.isFinite && y.isFinite }

    var normalized: SEPoint {
        let l = length
        return l == 0 ? SEPoint(1, 0) : SEPoint(x / l, y / l)
    }

    func distanceSquared(to p: SEPoint) -> Float {
        let dx = p.x - x
        let dy = p.y - y
        return dx * dx + dy * dy
    }

    func angle(to p: SEPoint) -> Float {
        atan2f(x * p.y - y * p.x, x * p.x + y * p.y)
    }

    func rotated(by radians: Float) -> SEPoint {
        let c = cosf(radians)
        let s = sinf(radians)
        return SEPoint(x * c - y * s, x * s + y * c)
    }
}

/// impeller::RoundingRadii. Each corner is a Size held as (width, height).
struct SERadii {
    var topLeft: SEPoint
    var topRight: SEPoint
    var bottomRight: SEPoint
    var bottomLeft: SEPoint

    static let zero = SERadii(
        topLeft: SEPoint(0, 0), topRight: SEPoint(0, 0),
        bottomRight: SEPoint(0, 0), bottomLeft: SEPoint(0, 0))

    var areAllCornersEmpty: Bool {
        topLeft.isEmptySize && topRight.isEmptySize
            && bottomLeft.isEmptySize && bottomRight.isEmptySize
    }

    var areAllCornersSame: Bool {
        // kEhCloseEnough
        func near(_ a: Float, _ b: Float) -> Bool { Swift.abs(a - b) <= 1e-3 }
        return near(topLeft.x, topRight.x) && near(topLeft.x, bottomRight.x)
            && near(topLeft.x, bottomLeft.x) && near(topLeft.y, topRight.y)
            && near(topLeft.y, bottomRight.y) && near(topLeft.y, bottomLeft.y)
    }

    /// RoundingRadii::Scaled: flat corners become zero, then everything is
    /// shrunk by one factor until no two neighbours overrun their side.
    func scaled(to bounds: SERect) -> SERadii {
        let finite = topLeft.isFinite && topRight.isFinite
            && bottomLeft.isFinite && bottomRight.isFinite
        if bounds.isEmpty || areAllCornersEmpty || !finite { return .zero }

        var r = self
        if r.topLeft.isEmptySize { r.topLeft = SEPoint(0, 0) }
        if r.topRight.isEmptySize { r.topRight = SEPoint(0, 0) }
        if r.bottomLeft.isEmptySize { r.bottomLeft = SEPoint(0, 0) }
        if r.bottomRight.isEmptySize { r.bottomRight = SEPoint(0, 0) }

        var scale: Float = 1
        func adjust(_ a: Float, _ b: Float, _ dimension: Float) {
            if a + b > dimension { scale = min(scale, dimension / (a + b)) }
        }
        adjust(r.topLeft.x, r.topRight.x, bounds.width)
        adjust(r.bottomLeft.x, r.bottomRight.x, bounds.width)
        adjust(r.topLeft.y, r.bottomLeft.y, bounds.height)
        adjust(r.topRight.y, r.bottomRight.y, bounds.height)
        if scale < 1 {
            r.topLeft = r.topLeft * scale
            r.topRight = r.topRight * scale
            r.bottomLeft = r.bottomLeft * scale
            r.bottomRight = r.bottomRight * scale
        }
        return r
    }
}

struct SERect {
    var left: Float
    var top: Float
    var right: Float
    var bottom: Float

    var isEmpty: Bool { !(left < right && top < bottom) }
    var width: Float { right - left }
    var height: Float { bottom - top }

    /// Rect::GetPositive: the same rectangle with its edges in order.
    var positive: SERect {
        SERect(
            left: min(left, right), top: min(top, bottom),
            right: max(left, right), bottom: max(top, bottom))
    }

    /// Rect::Contains: the left and top edges are inside, the others are not.
    func contains(_ p: SEPoint) -> Bool {
        !isEmpty && p.x >= left && p.y >= top && p.x < right && p.y < bottom
    }
}

/// Where a rounded superellipse's outline goes. PathBridge supplies one.
protocol SEPathReceiver {
    func moveTo(_ p: SEPoint)
    func lineTo(_ p: SEPoint)
    func cubicTo(_ cp1: SEPoint, _ cp2: SEPoint, _ p: SEPoint)
    func close()
}

/// impeller::RoundSuperellipseParam.
struct RoundSuperellipseParam {
    /// One eighth of a square-like rounded superellipse: a superellipse
    /// segment from the middle of the side, then a circular arc to the
    /// diagonal.
    struct Octant {
        var offset: SEPoint
        var seA: Float
        var seN: Float
        var seMaxTheta: Float = 0
        var circleStart: SEPoint
        var circleCenter = SEPoint(0, 0)
        var circleMaxAngle: Float = 0
    }

    struct Quadrant {
        var offset: SEPoint
        var signedScale: SEPoint
        var top: Octant
        var right: Octant
    }

    var topRight: Quadrant
    var bottomRight: Quadrant
    var bottomLeft: Quadrant
    var topLeft: Quadrant
    var allCornersSame: Bool

    // 1 - cos(pi/4)
    static let gapFactor: Float = 0.29289321881

    // MARK: Construction

    // Columns: n, and k_xJ = 1 / (1 - xJ / a), by the ratio a*2/radius.
    private static let precomputed: [(Float, Float)] = [
        /*ratio=2.00*/ (2.00000000, 1.13276676),
        /*ratio=2.10*/ (2.18349805, 1.20311921),
        /*ratio=2.20*/ (2.33888662, 1.28698796),
        /*ratio=2.30*/ (2.48660575, 1.36351941),
        /*ratio=2.40*/ (2.62226596, 1.44717976),
        /*ratio=2.50*/ (2.75148990, 1.53385819),
        /*ratio=3.00*/ (3.36298265, 1.98288283),
        /*ratio=3.50*/ (4.08649929, 2.23811846),
        /*ratio=4.00*/ (4.85481134, 2.47563463),
        /*ratio=4.50*/ (5.62945551, 2.72948597),
        /*ratio=5.00*/ (6.43023796, 2.98020421),
    ]

    /// The table is dense up to ratio 2.5, sparse up to 5, and a straight
    /// line beyond. Returns n and xJ / a.
    private static func computeNAndXj(_ ratioIn: Float) -> (Float, Float) {
        let minRatio: Float = 2.00
        let firstStepInverse: Float = 10
        let firstMaxRatio: Float = 2.50
        let firstNumRecords: Float = 6
        let secondStepInverse: Float = 2
        let secondMaxRatio: Float = 5.00
        let thirdNSlope: Float = 1.559599389
        let thirdKxjSlope: Float = 0.522807185
        let last = precomputed[precomputed.count - 1]

        if ratioIn > secondMaxRatio {
            let n = thirdNSlope * (ratioIn - secondMaxRatio) + last.0
            let kxj = thirdKxjSlope * (ratioIn - secondMaxRatio) + last.1
            return (n, 1 - 1 / kxj)
        }
        // A NaN ratio (a degenerate corner) falls to the first record, as
        // std::clamp leaves it for the C++ and the cast then floors it.
        let ratio = ratioIn.isNaN ? minRatio : min(max(ratioIn, minRatio), secondMaxRatio)
        let steps: Float
        if ratio < firstMaxRatio {
            steps = (ratio - minRatio) * firstStepInverse
        } else {
            steps = (ratio - firstMaxRatio) * secondStepInverse + firstNumRecords - 1
        }
        let left = min(max(Int(steps.rounded(.down)), 0), precomputed.count - 2)
        let frac = steps - Float(left)
        let n = (1 - frac) * precomputed[left].0 + frac * precomputed[left + 1].0
        let kxj = (1 - frac) * precomputed[left].1 + frac * precomputed[left + 1].1
        return (n, 1 - 1 / kxj)
    }

    /// The centre of the circle of radius `r` through `a` and `b`.
    private static func findCircleCenter(_ a: SEPoint, _ b: SEPoint, _ r: Float) -> SEPoint {
        let aToB = b - a
        let m = (a + b) / 2
        let cToM = SEPoint(-aToB.y, aToB.x)
        let distanceAM = aToB.length / 2
        let distanceCM = (r * r - distanceAM * distanceAM).squareRoot()
        return m - cToM.normalized * distanceCM
    }

    private static func computeOctant(_ center: SEPoint, _ a: Float, _ radius: Float) -> Octant {
        if radius <= 0 {
            return Octant(offset: center, seA: a, seN: 0, circleStart: SEPoint(a, a))
        }

        let ratio = a * 2 / radius
        let g = gapFactor * radius

        let (n, xjOverA) = computeNAndXj(ratio)
        let xJ = xjOverA * a
        let yJ = powf(1 - powf(xjOverA, n), 1 / n) * a
        let maxTheta = asinf(powf(xjOverA, n / 2))

        let tanPhiJ = powf(xJ / yJ, n - 1)
        let d = (xJ - tanPhiJ * yJ) / (1 - tanPhiJ)
        let R = (a - d - g) * Float(2).squareRoot()

        let pointM = SEPoint(a - g, a - g)
        let pointJ = SEPoint(xJ, yJ)
        let circleCenter = findCircleCenter(pointJ, pointM, R)
        let circleMaxAngle = (pointM - circleCenter).angle(to: pointJ - circleCenter)

        return Octant(
            offset: center, seA: a, seN: n, seMaxTheta: maxTheta,
            circleStart: pointJ, circleCenter: circleCenter,
            circleMaxAngle: circleMaxAngle)
    }

    /// `sign` says which quadrant this is ({±1, ±1}); it stands in for the
    /// sign of `corner - center` where that is zero.
    private static func computeQuadrant(
        _ center: SEPoint, _ corner: SEPoint, _ inRadii: SEPoint, _ sign: SEPoint
    ) -> Quadrant {
        let cornerVector = corner - center
        let radii = inRadii.abs

        // "norm" is short for "normalized": the quadrant is squeezed until
        // its radii are equal, solved there, and scaled back when drawn.
        let normRadius = min(radii.x, radii.y)
        let forwardScale = normRadius == 0 ? SEPoint(1, 1) : radii / normRadius
        let normHalfSize = cornerVector.abs / forwardScale
        var signedScale = cornerVector / normHalfSize
        if signedScale.x.isNaN { signedScale.x = sign.x }
        if signedScale.y.isNaN { signedScale.y = sign.y }

        // The two octants belong to two square-like shapes whose centres sit
        // the same distance `c` from the quadrant's, in different directions.
        let c = normHalfSize.x - normHalfSize.y

        return Quadrant(
            offset: center, signedScale: signedScale,
            top: computeOctant(SEPoint(0, -c), normHalfSize.x, normRadius),
            right: computeOctant(SEPoint(c, 0), normHalfSize.y, normRadius))
    }

    /// Splits left...right in the ratio ratioLeft : ratioRight.
    private static func split(
        _ left: Float, _ right: Float, _ ratioLeft: Float, _ ratioRight: Float
    ) -> Float {
        if ratioLeft == 0 && ratioRight == 0 { return (left + right) / 2 }
        return (left * ratioRight + right * ratioLeft) / (ratioLeft + ratioRight)
    }

    init(bounds: SERect, radii: SERadii) {
        let rightTop = SEPoint(bounds.right, bounds.top)
        // Four empty corners make a rectangle, which treats its border
        // differently and so is not "all corners same".
        if radii.areAllCornersSame && !radii.topLeft.isEmptySize {
            let center = SEPoint(
                (bounds.left + bounds.right) / 2, (bounds.top + bounds.bottom) / 2)
            let q = Self.computeQuadrant(center, rightTop, radii.topRight, SEPoint(-1, 1))
            topRight = q
            bottomRight = q
            bottomLeft = q
            topLeft = q
            allCornersSame = true
            return
        }
        let topSplit = Self.split(
            bounds.left, bounds.right, radii.topLeft.x, radii.topRight.x)
        let rightSplit = Self.split(
            bounds.top, bounds.bottom, radii.topRight.y, radii.bottomRight.y)
        let bottomSplit = Self.split(
            bounds.left, bounds.right, radii.bottomLeft.x, radii.bottomRight.x)
        let leftSplit = Self.split(
            bounds.top, bounds.bottom, radii.topLeft.y, radii.bottomLeft.y)

        topRight = Self.computeQuadrant(
            SEPoint(topSplit, rightSplit), rightTop, radii.topRight, SEPoint(1, -1))
        bottomRight = Self.computeQuadrant(
            SEPoint(bottomSplit, rightSplit), SEPoint(bounds.right, bounds.bottom),
            radii.bottomRight, SEPoint(1, 1))
        bottomLeft = Self.computeQuadrant(
            SEPoint(bottomSplit, leftSplit), SEPoint(bounds.left, bounds.bottom),
            radii.bottomLeft, SEPoint(-1, 1))
        topLeft = Self.computeQuadrant(
            SEPoint(topSplit, leftSplit), SEPoint(bounds.left, bounds.top),
            radii.topLeft, SEPoint(-1, -1))
        allCornersSame = false
    }

    // MARK: Containment

    /// Points outside the first octant (0 to pi/4 clockwise from +Y) are not
    /// this octant's to reject, so they pass.
    private static func octantContains(_ param: Octant, _ p: SEPoint) -> Bool {
        if p.x < 0 || p.y < 0 || p.y < p.x { return true }
        if p.x <= param.circleStart.x {
            let pSe = p / param.seA
            return powf(pSe.x, param.seN) + powf(pSe.y, param.seN) <= 1
        }
        let radiusSquared = param.circleStart.distanceSquared(to: param.circleCenter)
        let pCircle = p - param.circleCenter
        return pCircle.distanceSquared(to: SEPoint(0, 0)) < radiusSquared
    }

    private static func cornerContains(
        _ param: Quadrant, _ p: SEPoint, checkQuadrant: Bool = true
    ) -> Bool {
        var normPoint = (p - param.offset) / param.signedScale
        if checkQuadrant {
            if normPoint.x < 0 || normPoint.y < 0 { return true }
        } else {
            normPoint = normPoint.abs
        }
        if param.top.seN < 2 || param.right.seN < 2 {
            // A square corner: the top and left borders are inside, the
            // bottom and right are not (as Rect.contains has it).
            let xDelta = param.right.offset.x + param.right.seA - normPoint.x
            let yDelta = param.top.offset.y + param.top.seA - normPoint.y
            let xWithin = xDelta > 0 || (xDelta == 0 && param.signedScale.x < 0)
            let yWithin = yDelta > 0 || (yDelta == 0 && param.signedScale.y < 0)
            return xWithin && yWithin
        }
        return octantContains(param.top, normPoint - param.top.offset)
            && octantContains(param.right, (normPoint - param.right.offset).flipped)
    }

    func contains(_ point: SEPoint) -> Bool {
        if allCornersSame {
            return Self.cornerContains(topRight, point, checkQuadrant: false)
        }
        return Self.cornerContains(topRight, point)
            && Self.cornerContains(bottomRight, point)
            && Self.cornerContains(bottomLeft, point)
            && Self.cornerContains(topLeft, point)
    }

    // MARK: Outline

    // Bezier factors for the superellipse segment's start and end tangents,
    // by n from 2 to 15. Found by brute-force search for THIS shape; they
    // are not good for superellipses in general.
    private static let bezierFactors: [(Float, Float)] = [
        /*n=2.0*/ (0.01339448, 0.05994973),
        /*n=3.0*/ (0.13664115, 0.13592082),
        /*n=4.0*/ (0.24545546, 0.14099516),
        /*n=5.0*/ (0.32353151, 0.12808021),
        /*n=6.0*/ (0.39093068, 0.11726264),
        /*n=7.0*/ (0.44847800, 0.10808278),
        /*n=8.0*/ (0.49817452, 0.10026175),
        /*n=9.0*/ (0.54105583, 0.09344429),
        /*n=10.0*/ (0.57812578, 0.08748984),
        /*n=11.0*/ (0.61050961, 0.08224722),
        /*n=12.0*/ (0.63903989, 0.07759639),
        /*n=13.0*/ (0.66416338, 0.07346530),
        /*n=14.0*/ (0.68675338, 0.06974996),
        /*n=15.0*/ (0.70678034, 0.06529512),
    ]

    private static func superellipseBezierFactors(_ n: Float) -> (Float, Float) {
        let minN: Float = 2
        let maxN = minN + Float(bezierFactors.count - 1)
        if n >= maxN {
            // Heuristic formula derived from fitting.
            return (
                1.07 - expf(1.307649835) * powf(n, -0.8568516731),
                -0.01 + expf(-0.9287690322) * powf(n, -0.6120901398)
            )
        }
        let steps = n.isNaN ? 0 : min(max(n - minN, 0), Float(bezierFactors.count - 1))
        let left = min(max(Int(steps.rounded(.down)), 0), bezierFactors.count - 2)
        let frac = steps - Float(left)
        return (
            (1 - frac) * bezierFactors[left].0 + frac * bezierFactors[left + 1].0,
            (1 - frac) * bezierFactors[left].1 + frac * bezierFactors[left + 1].1
        )
    }

    private static func superellipseArcPoints(_ param: Octant) -> [SEPoint] {
        let start = SEPoint(0, param.seA)
        let end = param.circleStart
        let startTangent = SEPoint(1, 0)
        let circleStartVector = param.circleStart - param.circleCenter
        let endTangent = SEPoint(-circleStartVector.y, circleStartVector.x).normalized
        let factors = superellipseBezierFactors(param.seN)
        return [
            start,
            start + startTangent * factors.0 * param.seA,
            end + endTangent * factors.1 * param.seA,
            end,
        ]
    }

    private static func circularArcPoints(_ param: Octant) -> [SEPoint] {
        let startVector = param.circleStart - param.circleCenter
        let endVector = startVector.rotated(by: -param.circleMaxAngle)
        let circleEnd = param.circleCenter + endVector
        let startTangent = SEPoint(startVector.y, -startVector.x).normalized
        let endTangent = SEPoint(-endVector.y, endVector.x).normalized
        let bezierFactor = tanf(param.circleMaxAngle / 4) * 4 / 3
        let radius = startVector.length
        return [
            param.circleStart,
            param.circleStart + startTangent * bezierFactor * radius,
            circleEnd + endTangent * bezierFactor * radius,
            circleEnd,
        ]
    }

    /// One eighth, from 0 to pi/4 clockwise from +Y (or back, if `reverse`).
    /// `flip` mirrors it in the line y = x. Points are flipped, moved by the
    /// octant's offset, then scaled and moved into place by the quadrant.
    private static func addOctant(
        _ param: Octant, reverse: Bool, flip: Bool,
        scale: SEPoint, translate: SEPoint, to receiver: SEPathReceiver
    ) {
        func place(_ p: SEPoint) -> SEPoint {
            ((flip ? p.flipped : p) + param.offset) * scale + translate
        }
        let circle = circularArcPoints(param)
        let se = superellipseArcPoints(param)
        if !reverse {
            receiver.cubicTo(place(se[1]), place(se[2]), place(se[3]))
            receiver.cubicTo(place(circle[1]), place(circle[2]), place(circle[3]))
        } else {
            receiver.cubicTo(place(circle[2]), place(circle[1]), place(circle[0]))
            receiver.cubicTo(place(se[2]), place(se[1]), place(se[0]))
        }
    }

    /// One quarter, from 0 to pi/2 clockwise from +Y (or back, if
    /// `reverse`). `scaleSign` lets one quadrant's parameters draw all four
    /// when the radii are uniform.
    private static func addQuadrant(
        _ param: Quadrant, reverse: Bool, scaleSign: SEPoint = SEPoint(1, 1),
        to receiver: SEPathReceiver
    ) {
        let scale = param.signedScale * scaleSign
        let translate = param.offset
        func place(_ p: SEPoint) -> SEPoint { p * scale + translate }

        if param.top.seN < 2 || param.right.seN < 2 {
            receiver.lineTo(place(param.top.offset + SEPoint(param.top.seA, param.top.seA)))
            if !reverse {
                receiver.lineTo(place(param.right.offset + SEPoint(param.right.seA, 0)))
            } else {
                receiver.lineTo(place(param.top.offset + SEPoint(0, param.top.seA)))
            }
            return
        }
        if !reverse {
            addOctant(
                param.top, reverse: false, flip: false,
                scale: scale, translate: translate, to: receiver)
            addOctant(
                param.right, reverse: true, flip: true,
                scale: scale, translate: translate, to: receiver)
        } else {
            addOctant(
                param.right, reverse: false, flip: true,
                scale: scale, translate: translate, to: receiver)
            addOctant(
                param.top, reverse: true, flip: false,
                scale: scale, translate: translate, to: receiver)
        }
    }

    /// Emits the outline as one closed contour, clockwise from the middle of
    /// the top edge.
    func dispatch(to receiver: SEPathReceiver) {
        let start = topRight.offset
            + topRight.signedScale * (topRight.top.offset + SEPoint(0, topRight.top.seA))
        receiver.moveTo(start)

        if allCornersSame {
            Self.addQuadrant(topRight, reverse: false, scaleSign: SEPoint(1, 1), to: receiver)
            Self.addQuadrant(topRight, reverse: true, scaleSign: SEPoint(1, -1), to: receiver)
            Self.addQuadrant(topRight, reverse: false, scaleSign: SEPoint(-1, -1), to: receiver)
            Self.addQuadrant(topRight, reverse: true, scaleSign: SEPoint(-1, 1), to: receiver)
        } else {
            Self.addQuadrant(topRight, reverse: false, to: receiver)
            Self.addQuadrant(bottomRight, reverse: true, to: receiver)
            Self.addQuadrant(bottomLeft, reverse: false, to: receiver)
            Self.addQuadrant(topLeft, reverse: true, to: receiver)
        }

        receiver.lineTo(start)
        receiver.close()
    }
}

extension flutter.swift_bridge {
    /// Containment for a rounded superellipse. Pure geometry: there is no
    /// skwasm object behind it, hence no `skHandle`.
    public final class RSuperellipseBridge {
        private let bounds: SERect
        private let radii: SERadii

        public init(
            _ left: Double, _ top: Double, _ right: Double, _ bottom: Double,
            _ tl_radius_x: Double, _ tl_radius_y: Double,
            _ tr_radius_x: Double, _ tr_radius_y: Double,
            _ br_radius_x: Double, _ br_radius_y: Double,
            _ bl_radius_x: Double, _ bl_radius_y: Double
        ) {
            bounds = SERect(
                left: pathNarrow(left), top: pathNarrow(top),
                right: pathNarrow(right), bottom: pathNarrow(bottom)
            ).positive
            // Taken as given, like the native bridge: dart:ui has already
            // scaled the radii to fit by the time it asks.
            radii = SERadii(
                topLeft: SEPoint(pathNarrow(tl_radius_x), pathNarrow(tl_radius_y)),
                topRight: SEPoint(pathNarrow(tr_radius_x), pathNarrow(tr_radius_y)),
                bottomRight: SEPoint(pathNarrow(br_radius_x), pathNarrow(br_radius_y)),
                bottomLeft: SEPoint(pathNarrow(bl_radius_x), pathNarrow(bl_radius_y)))
        }

        public func Contains(_ x: Double, _ y: Double) -> Bool {
            let point = SEPoint(pathNarrow(x), pathNarrow(y))
            if !bounds.contains(point) { return false }
            return RoundSuperellipseParam(bounds: bounds, radii: radii).contains(point)
        }
    }
}
