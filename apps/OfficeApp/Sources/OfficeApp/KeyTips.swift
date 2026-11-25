// Alt key tips: a small letter badge over each ribbon control while the tips are on.
import Flutter
import FlutterSwiftBridge

final class KeyTipLayer: StatefulWidget {
    let child: Widget
    init(child: Widget) { self.child = child; super.init(key: nil) }
    override func createState() -> State<StatefulWidget> { _KeyTipLayerState() }
}

private final class _KeyTipLayerState: State<StatefulWidget> {
    private var _listener: Int?

    override func initState() {
        super.initState()
        _listener = KeyboardTraversal.shared.addTipsListener { [weak self] in
            guard let self, self.mounted else { return }
            self.setState {}
        }
    }

    override func dispose() {
        if let id = _listener { KeyboardTraversal.shared.removeTipsListener(id) }
        super.dispose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let child = (widget as! KeyTipLayer).child
        guard KeyboardTraversal.shared.tipsOn, let box = context.findRenderObject() as? RenderBox, box.attached, box.hasSize else {
            return child
        }
        let fluent = FluentTheme.of(context)
        let home = box.localToGlobal(Offset(0, 0))
        var badges: [Widget] = []
        for (stop, code) in KeyboardTraversal.shared.tipCodes() {
            guard let at = stop.origin() else { continue }
            badges.append(Positioned(left: at.dx - home.dx + 2, top: at.dy - home.dy + 2, child: DecoratedBox(
                decoration: BoxDecoration(color: Color(0xFF222222), borderRadius: BorderRadius.all(Radius(circular: 3))),
                child: Padding(padding: EdgeInsets(left: 4, top: 1, right: 4, bottom: 1),
                               child: Text(code, style: fluent.typography.caption?.copyWith(color: Color(0xFFFFFFFF)))))))
        }
        return Stack(clipBehavior: .none, children: [child] + [IgnorePointer(child: Stack(clipBehavior: .none, children: badges))])
    }
}
