// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-CH-1: the ribbon's font size box. Type any size from 1 to 1638 points in
// half-point steps (10.5, 13, 72.5); Enter or leaving the box applies it. A
// small menu beside it keeps the usual list. A value that is not a size puts
// the current one back.

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons

final class FontSizeBox: StatefulWidget {
    let size: Double
    let sizes: [Double]
    let onSize: (Double) -> Void
    init(size: Double, sizes: [Double], onSize: @escaping (Double) -> Void) {
        self.size = size; self.sizes = sizes; self.onSize = onSize
        super.init(key: ValueKey("font-size"))
    }
    override func createState() -> State<StatefulWidget> { FontSizeBoxState() }

    /// What a typed size means: 1 to 1638 points, rounded to a half point; nil when it is not a size.
    static func parse(_ text: String) -> Double? {
        guard let v = Double(text.trimmingWhitespace()), v.isFinite, v >= 0.75, v <= 1638 else { return nil }
        let r = (v * 2).rounded() / 2
        return r >= 1 ? r : nil
    }

    static func format(_ n: Double) -> String { n == n.rounded() ? String(Int(n)) : String(n) }
}

final class FontSizeBoxState: State<StatefulWidget> {
    private var _w: FontSizeBox { widget as! FontSizeBox }
    private let _text = TextEditingController()
    private var _focused = false

    override func initState() { super.initState(); _text.text = FontSizeBox.format(_w.size) }

    override func didUpdateWidget(_ oldWidget: StatefulWidget) {
        super.didUpdateWidget(oldWidget)
        if !_focused { _text.text = FontSizeBox.format(_w.size) }
    }

    private func commit() {
        if let n = FontSizeBox.parse(_text.text) { _text.text = FontSizeBox.format(n); _w.onSize(n) }
        else { _text.text = FontSizeBox.format(_w.size) }
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        return Row(crossAxisAlignment: .center, children: [
            SizedBox(width: 46, height: Chrome.fieldHeight, child: FluentTextBox(
                controller: _text, placeholderText: "Font Size",
                onSubmitted: { [weak self] _ in self?.commit() },
                onFocusChanged: { [weak self] f in self?._focused = f; if !f { self?.commit() } })),
            Chrome.menu(nil, Icon(FluentSystemIcons.chevronDown, size: 12, color: fluent.resources.textFillColorPrimary), fluent,
                        _w.sizes.map { n in (FontSizeBox.format(n), { [weak self] in
                            self?._text.text = FontSizeBox.format(n); self?._w.onSize(n) }) }, tip: "Font Size"),
        ])
    }
}
