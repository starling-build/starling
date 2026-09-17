import AppKit

/// Damped spring matching CASpringAnimation's parameters (mass, stiffness, damping, initialVelocity).
/// The "shadow spring": same math as the render server runs, evaluated in-app only on demand.
struct Spring {
    var mass: Double = 1, stiffness: Double = 30, damping: Double = 4
    var from: Double, to: Double, v0: Double, start: CFTimeInterval
    /// Closed-form under/critical/over-damped solution for displacement x(t) with x(0)=from-to, x'(0)=v0.
    func sample(_ t: CFTimeInterval) -> (value: Double, velocity: Double) {
        let dt = max(0, t - start)
        let x0 = from - to
        let w0 = sqrt(stiffness / mass)
        let zeta = damping / (2 * sqrt(stiffness * mass))
        if zeta < 1 {
            let wd = w0 * sqrt(1 - zeta * zeta)
            let A = x0, B = (v0 + zeta * w0 * x0) / wd
            let e = exp(-zeta * w0 * dt)
            let x = e * (A * cos(wd * dt) + B * sin(wd * dt))
            let dx = -zeta * w0 * x + e * (-A * wd * sin(wd * dt) + B * wd * cos(wd * dt))
            return (to + x, dx)
        } else {
            let e = exp(-w0 * dt)
            let x = e * (x0 + (v0 + w0 * x0) * dt)
            let dx = e * (v0 - w0 * (v0 + w0 * x0) * dt)
            return (to + x, dx)
        }
    }
}

final class Renderer {
    let root: CALayer
    let scale: CGFloat
    var layerCount = 0
    let rasterQueue = DispatchQueue(label: "raster", qos: .userInteractive)
    init(root: CALayer, scale: CGFloat) { self.root = root; self.scale = scale }

    /// One commit per frame: layout dirty subtrees, then resolve every layer inside a single transaction.
    func commit(_ tree: Node, width: CGFloat) -> (layoutMs: Double, commitMs: Double) {
        let t0 = CACurrentMediaTime()
        if tree.needsLayout { tree.layout(maxWidth: width) }
        let t1 = CACurrentMediaTime()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layerCount = 0
        walk(tree, parentAbs: .zero, hostLayer: root)
        CATransaction.commit()
        let t2 = CACurrentMediaTime()
        return ((t1 - t0) * 1000, (t2 - t1) * 1000)
    }

    private func walk(_ n: Node, parentAbs: CGPoint, hostLayer: CALayer) {
        n.absOrigin = CGPoint(x: parentAbs.x + n.origin.x, y: parentAbs.y + n.origin.y)
        var host = hostLayer
        if let l = n.layer {
            layerCount += 1
            if l.superlayer !== hostLayer { hostLayer.addSublayer(l) }
            // Layer-owned position in the host's coordinate space; anchor at origin so position == frame origin.
            l.anchorPoint = .zero
            l.bounds = CGRect(origin: .zero, size: n.size)
            if l.animation(forKey: "spike.pos") == nil { l.position = n.absOrigin }
            if n.needsPaint { n.apply(scale: scale) }
            host = l
            // children of a content node are positioned relative to it
            for c in n.children { walk(c, parentAbs: .zero, hostLayer: host) }
            return
        }
        for c in n.children { walk(c, parentAbs: n.absOrigin, hostLayer: host) }
    }
}

/// Compositor-owned animation: the render server runs the spring; we keep a shadow for retargeting.
final class CompositorSpring {
    let layer: CALayer
    var shadow: Spring
    let key = "spike.pos"
    init(layer: CALayer, from: CGFloat, to: CGFloat, v0: Double = 0) {
        self.layer = layer
        shadow = Spring(from: from, to: to, v0: v0, start: CACurrentMediaTime())
        submit(fromX: from, v0: v0)
    }
    private func submit(fromX: CGFloat, v0: Double) {
        let target = CGPoint(x: shadow.to, y: layer.position.y)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.position = target                       // model = end state
        let a = CASpringAnimation(keyPath: "position.x")
        a.isAdditive = true
        a.mass = shadow.mass; a.stiffness = shadow.stiffness; a.damping = shadow.damping
        let disp = Double(fromX - target.x)
        // CASpringAnimation.initialVelocity is normalised to the animated distance (like UIView's
        // initialSpringVelocity): 1.0 = the full distance per second, positive = toward the target.
        a.initialVelocity = disp == 0 ? 0 : -v0 / disp
        // Pin the animation's clock to ours instead of letting the commit decide.
        a.beginTime = layer.convertTime(shadow.start, from: nil)
        a.fromValue = fromX - target.x; a.toValue = 0
        a.duration = a.settlingDuration
        a.fillMode = .forwards; a.isRemovedOnCompletion = false
        layer.add(a, forKey: key)
        CATransaction.commit()
    }
    /// Retarget from the shadow's current displacement and velocity; report shadow vs presentation.
    func retarget(to: CGFloat) -> (shadow: Double, presentation: Double?) {
        let now = CACurrentMediaTime()
        let s = shadow.sample(now)
        let pres = layer.presentation()?.position.x
        shadow = Spring(from: s.value, to: to, v0: s.velocity, start: now)
        submit(fromX: s.value, v0: s.velocity)
        return (s.value, pres.map(Double.init))
    }
    var presentationX: Double? { layer.presentation().map { Double($0.position.x) } }
}

/// In-process animation: sampled every display-link tick in the app; written through a
/// presentation override (CABasicAnimation with beginTime -1, forwards, never removed, toValue only).
final class InProcessSpring {
    let layer: CALayer
    var spring: Spring
    init(layer: CALayer, from: CGFloat, to: CGFloat) {
        self.layer = layer
        spring = Spring(from: from, to: to, v0: 0, start: CACurrentMediaTime())
    }
    func tick(_ now: CFTimeInterval) -> Double {
        let v = spring.sample(now).value
        let a = CABasicAnimation(keyPath: "position.x")
        a.beginTime = -1; a.duration = 1
        a.fillMode = .forwards; a.isRemovedOnCompletion = false
        a.toValue = v
        layer.add(a, forKey: "spike.override")
        return v
    }
}
