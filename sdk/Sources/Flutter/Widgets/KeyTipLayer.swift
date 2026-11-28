// Alt key tips: a small letter badge over each control that has one while the tips are on. The ribbon draws the
// letters of its tabs and commands; a menu (a flyout) draws its own items' letters, above the ribbon.
import FlutterSwiftBridge

public final class KeyTipLayer: StatefulWidget {
    let child: Widget
    /// True for a layer inside a menu or dialog: it draws the letters of the open menu's items only.
    public let modal: Bool
    public init(modal: Bool = false, child: Widget) { self.modal = modal; self.child = child; super.init(key: nil) }
    public override func createState() -> State<StatefulWidget> { _KeyTipLayerState() }
}

private final class _KeyTipLayerState: State<StatefulWidget> {
    private var _listener: Int?

    override func initState() {
        super.initState()
        if (widget as! KeyTipLayer).modal { KeyboardTraversal.shared.tipMenuOpened() }
        _listener = KeyboardTraversal.shared.addTipsListener { [weak self] in
            guard let self, self.mounted else { return }
            self.setState {}
        }
    }

    override func dispose() {
        if (widget as! KeyTipLayer).modal { KeyboardTraversal.shared.tipMenuClosed() }
        if let id = _listener { KeyboardTraversal.shared.removeTipsListener(id) }
        super.dispose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let layer = widget as! KeyTipLayer
        let child = layer.child
        guard KeyboardTraversal.shared.tipsOn, let box = context.findRenderObject() as? RenderBox, box.attached, box.hasSize else {
            return child
        }
        let home = box.localToGlobal(Offset(0, 0))
        var badges: [Widget] = []
        for (stop, code) in KeyboardTraversal.shared.tipCodes() where stop.modal == layer.modal {
            guard let at = stop.origin() else { continue }
            badges.append(Positioned(left: at.dx - home.dx + 2, top: at.dy - home.dy + 2, child: DecoratedBox(
                decoration: BoxDecoration(color: Color(0xFF222222), borderRadius: BorderRadius.all(Radius(circular: 3))),
                child: Padding(padding: EdgeInsets(left: 4, top: 1, right: 4, bottom: 1),
                               child: Text(code, style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 12))))))
        }
        return Stack(clipBehavior: .none, children: [child] + [IgnorePointer(child: Stack(clipBehavior: .none, children: badges))])
    }
}
