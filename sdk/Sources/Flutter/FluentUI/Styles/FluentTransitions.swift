// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The motion a transient Fluent surface makes when it appears: Windows'
// "direct entrance" — a short slide toward its final place with a fade, on
// the decelerate curve, 167 ms. Every flyout, menu and teaching tip enters
// this way, which is the "consistent" principle of Windows motion: surfaces
// sharing an entry point invoke the same way.
//
// One widget, so the desktop's own flyouts (Start, Quick Settings, the
// notification centre) can enter exactly as the SDK's menus do by wrapping
// their content in it, and so the tokens are applied in one place.

import FlutterSwiftBridge

// MARK: - FluentEntrance

/// Plays a slide-and-fade in on mount, then stays. Honours
/// `FluentMaterialSettings.animationEffects`: off, the child simply appears.
public final class FluentEntrance: StatefulWidget {
    public let child: Widget

    /// Where the child starts relative to its final place, in logical
    /// pixels. A flyout below its target comes down from a little above it.
    public let slideFrom: Offset

    /// Duration and curve; Windows' fast direct entrance by default.
    public let spec: FluentMotion.Spec

    public init(
        key: (any Key)? = nil,
        child: Widget,
        slideFrom: Offset = Offset(0, -8),
        spec: FluentMotion.Spec = FluentMotion.directEntranceFast
    ) {
        self.child = child
        self.slideFrom = slideFrom
        self.spec = spec
        super.init(key: key)
    }

    public override func createState() -> State<StatefulWidget> {
        _FluentEntranceState()
    }
}

private final class _FluentEntranceState: State<StatefulWidget>, TickerProvider {
    private var _controller: AnimationController?
    private var _curved: CurvedAnimation?
    private var _done = false

    private var entrance: FluentEntrance { widget as! FluentEntrance }

    func createTicker(_ onTick: @escaping TickerCallback) -> Ticker {
        Ticker(onTick)
    }

    override func initState() {
        super.initState()
        let controller = AnimationController(duration: entrance.spec.duration, vsync: self)
        _curved = CurvedAnimation(parent: controller, curve: entrance.spec.curve)
        controller.addListener { [weak self] in
            self?.setState {}
        }
        controller.addStatusListener { [weak self] status in
            guard let self, status == .completed else { return }
            self.setState { self._done = true }
        }
        _controller = controller
    }

    override func didChangeDependencies() {
        super.didChangeDependencies()
        // Start once the settings are readable; a disabled animation lands
        // on its end state without a frame of motion.
        guard let controller = _controller, let ctx = context, !_done, controller.value == 0 else { return }
        if FluentMaterialSettings.of(ctx).animationEffects {
            _ = controller.forward()
        } else {
            _done = true
        }
    }

    override func dispose() {
        _controller?.dispose()
        _controller = nil
        super.dispose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        if _done { return entrance.child }
        let t = _curved?.value ?? 1.0
        let dx = entrance.slideFrom.dx * (1 - t)
        let dy = entrance.slideFrom.dy * (1 - t)
        var result: Widget = entrance.child
        if dx != 0 || dy != 0 {
            result = Transform(translate: Offset(dx, dy), child: result)
        }
        return Opacity(opacity: max(0, min(1, t)), child: result)
    }
}
