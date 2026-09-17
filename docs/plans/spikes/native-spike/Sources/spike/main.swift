import AppKit

// ---- Host: NSWindow + layer-backed view + display link. No Auto Layout anywhere.

final class HostView: NSView {
    override var isFlipped: Bool { true }
    override func makeBackingLayer() -> CALayer { let l = CALayer(); l.isGeometryFlipped = true; return l }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let W: CGFloat = 900, H: CGFloat = 420
let win = NSWindow(contentRect: NSRect(x: 100, y: 200, width: W, height: H), styleMask: [.titled], backing: .buffered, defer: false)
win.title = "native spike"
let view = HostView(frame: NSRect(x: 0, y: 0, width: W, height: H))
view.wantsLayer = true
view.layer!.backgroundColor = NSColor(white: 0.97, alpha: 1).cgColor
win.contentView = view
win.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
let scale = win.backingScaleFactor
let renderer = Renderer(root: view.layer!, scale: scale)

// ---- Scene: a header, a card with text, two balls (A: compositor-owned, B: in-process), and a stress list.

let ballA = Box(color: .systemBlue, radius: 24, fixed: CGSize(width: 48, height: 48))
let ballB = Box(color: .systemOrange, radius: 24, fixed: CGSize(width: 48, height: 48))
let card = Box(color: .white, radius: 12, padding: 14, Column(spacing: 6, [
    Label("Native spike", size: 22, weight: .semibold),
    Label("Retained tree → CALayer, CoreText bitmaps, one CATransaction per frame", size: 13, color: NSColor(white: 0.45, alpha: 1)),
]))
var stressLabels: [Node] = []
for i in 0..<400 { stressLabels.append(Label("row \(i)  lorem ipsum dolor", size: 11, color: NSColor(white: 0.6, alpha: 1))) }
let stress = Column(spacing: 0, stressLabels)   // deliberately overflows; measures layout+raster cost
let tree = Column(spacing: 16, [
    card,
    Row(spacing: 0, [Label("A compositor-owned (blue)   B in-process (orange)", size: 12)]),
    ballA, ballB,
    stress,
])
tree.origin = CGPoint(x: 20, y: 20)

// Stress: first commit rasterizes 400 labels.
let first = renderer.commit(tree, width: W - 40)
print(String(format: "first commit: layout %.2f ms, commit+raster %.2f ms, layers %d", first.layoutMs, first.commitMs, renderer.layerCount))
let second = renderer.commit(tree, width: W - 40)
print(String(format: "steady commit (nothing dirty): layout %.3f ms, commit %.3f ms", second.layoutMs, second.commitMs))
// Relayout only (mark dirty, no repaint): the retained-tree cost.
tree.needsLayout = true
let third = renderer.commit(tree, width: W - 40)
print(String(format: "relayout, no repaint: layout %.2f ms, commit %.3f ms", third.layoutMs, third.commitMs))

// ---- Animations
let startX = ballA._layer.position.x
let travel: CGFloat = 600
var compositor: CompositorSpring! = nil
var inproc: InProcessSpring! = nil
var t0: CFTimeInterval = 0
var retargeted = false, blocked = false
var lastLog: CFTimeInterval = 0
var overrideUs = 0.0; var overrideN = 0

final class Ticker: NSObject {
    @objc func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        if compositor == nil {
            t0 = now
            compositor = CompositorSpring(layer: ballA._layer, from: startX, to: startX + travel)
            inproc = InProcessSpring(layer: ballB._layer, from: startX, to: startX + travel)
            return
        }
        let tw0 = CACurrentMediaTime(); let bx = inproc.tick(now); overrideUs += (CACurrentMediaTime()-tw0)*1e6; overrideN += 1
        let t = now - t0
        if t > 0.25 && !retargeted {
            retargeted = true
            let r = compositor.retarget(to: startX + travel * 0.4)
            print(String(format: "RETARGET at %.3fs: shadow x=%.2f  presentation x=%@  diff=%@", t, r.shadow,
                         r.presentation.map { String(format: "%.2f", $0) } ?? "nil",
                         r.presentation.map { String(format: "%.2f", $0 - r.shadow) } ?? "n/a"))
        }
        if t > 0.5 && !blocked {
            blocked = true
            print(String(format: "BLOCKING main thread 2.0s at %.3fs; A(pres)=%.1f B=%.1f", t, compositor.presentationX ?? -1, bx))
            Thread.sleep(forTimeInterval: 2.0)
            print(String(format: "UNBLOCKED at %.3fs; A(pres)=%.1f B=%.1f", CACurrentMediaTime() - t0, compositor.presentationX ?? -1, bx))
        }
        let sh = compositor.shadow.sample(now).value
        print(String(format: "t=%.3f  A(pres)=%.1f  A(shadow)=%.1f  d=%.1f  B=%.1f", t, compositor.presentationX ?? -1, sh, (compositor.presentationX ?? 0) - sh, bx))
        if t > 4.0 { print(String(format: "override write avg %.1f us over %d frames", overrideUs/Double(overrideN), overrideN)); print("done"); exit(0) }
    }
}
let ticker = Ticker()
let link = view.displayLink(target: ticker, selector: #selector(Ticker.tick(_:)))
link.add(to: .main, forMode: .common)
app.run()
