import Flutter
import FlutterSwiftBridge

/// `starling.debug('controls')`: every labelled control the shell shows, one
/// line each, `kind<TAB>x<TAB>y<TAB>label` with the centre in logical pixels
/// (the page's CSS pixels): `tip` for a control known by its tooltip (the
/// ribbon's icon buttons), `text` for a plain text (the ribbon's tab names).
/// The browser's control walk (build/tools/web-drive.mjs `walk`) clicks each
/// one and records the commands that throw: the web counterpart of
/// ControlSweepTests, which taps the same controls natively.
enum ControlList {
    static func text(_ context: (any BuildContext)?) -> String {
        guard let root = context as? Element else { return "" }
        var lines: [String] = []
        func centre(_ e: Element) -> Offset? {
            guard let box = e.findRenderObject() as? RenderBox, box.hasSize, box.attached else { return nil }
            return box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2))
        }
        func clean(_ s: String) -> String {
            String(s.map { $0 == "\t" || $0 == "\n" ? " " : $0 })
        }
        func walk(_ e: Element) {
            if let t = e.widget as? Tooltip, let message = t.message, !message.isEmpty, let c = centre(e) {
                lines.append("tip\t\(Int(c.dx))\t\(Int(c.dy))\t\(clean(message))")
            } else if let t = e.widget as? Text, let data = t.data, !data.isEmpty, let c = centre(e) {
                lines.append("text\t\(Int(c.dx))\t\(Int(c.dy))\t\(clean(data))")
            }
            e.visitChildElements(walk)
        }
        walk(root)
        return lines.joined(separator: "\n")
    }
}
