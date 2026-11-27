// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// View → Zoom: PowerPoint's Zoom dialog. Fit or a preset (400, 200, 100, 66, 50, 33 %), or a percent
// typed or stepped from 10 to 400. Zoom is a way of looking: no undo step, nothing saved.

import Flutter
import OfficeText
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

final class ZoomDialog: StatefulWidget {
    let percent: Int
    let fit: Bool
    /// nil: Fit; otherwise the percent to zoom to.
    let onApply: (Int?) -> Void
    let onCancel: () -> Void

    init(percent: Int, fit: Bool, onApply: @escaping (Int?) -> Void, onCancel: @escaping () -> Void) {
        self.percent = percent
        self.fit = fit
        self.onApply = onApply
        self.onCancel = onCancel
        super.init()
    }

    override func createState() -> State<StatefulWidget> { ZoomDialogState() }
}

final class ZoomDialogState: State<StatefulWidget> {
    /// PowerPoint's choices, in its order; 0 stands for Fit.
    static let presets = [0, 400, 200, 100, 66, 50, 33]
    static let range = 10 ... 400

    private var _w: ZoomDialog { widget as! ZoomDialog }
    private let _percent = TextEditingController()
    /// The chosen preset (0 is Fit), or nil when the typed percent matches none.
    private var _choice: Int? = nil

    override func initState() {
        super.initState()
        _percent.text = "\(_w.percent)%"
        _choice = _w.fit ? 0 : (Self.presets.contains(_w.percent) ? _w.percent : nil)
    }

    override func dispose() {
        _percent.dispose()
        super.dispose()
    }

    /// The typed percent ("150" or "150%"), or nil when it is not a whole number from 10 to 400.
    static func parse(_ s: String) -> Int? {
        let t = String(s.filter { $0 != " " && $0 != "%" })
        guard let v = Int(t), range.contains(v) else { return nil }
        return v
    }

    private func _step(_ d: Int) {
        let now = Self.parse(_percent.text) ?? _w.percent
        let v = max(Self.range.lowerBound, min(Self.range.upperBound, now + d))
        setState {
            _percent.text = "\(v)%"
            _choice = Self.presets.contains(v) ? v : nil
        }
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let caption = fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary)
        func gap(_ h: Double) -> Widget { SizedBox(width: nil, height: h, child: nil) }
        let radios = Self.presets.map { p -> Widget in
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 4), child: RadioButton<Int>(
                key: ValueKey("zoomdlg.preset.\(p)"), value: p, groupValue: _choice ?? -1,
                onChanged: { [weak self] _ in
                    guard let self else { return }
                    self.setState {
                        self._choice = p
                        // Fit shows the percent the window fits at now, as PowerPoint does.
                        self._percent.text = "\(p == 0 ? self._w.percent : p)%"
                    }
                },
                content: Text(p == 0 ? "Fit" : "\(p)%")))
        }
        let typed = Self.parse(_percent.text)
        let ok = _choice == 0 || typed != nil
        let page = Row(crossAxisAlignment: .start, children: [
            SizedBox(width: 150, height: nil, child: Column(mainAxisSize: .min, crossAxisAlignment: .start, children:
                [Text("Zoom to", style: caption), gap(6)] + radios)),
            Column(mainAxisSize: .min, crossAxisAlignment: .start, children: [
                Text("Percent:", style: caption), gap(6),
                Row(children: [
                    SizedBox(width: 80, height: 30, child: PKeyed("zoomdlg.percent", FluentTextBox(controller: _percent, onChanged: { [weak self] s in
                        self?.setState { self?._choice = Self.parse(s).flatMap { Self.presets.contains($0) ? $0 : nil } }
                    }))),
                    SizedBox(width: 4, height: nil, child: nil),
                    Column(mainAxisSize: .min, children: [
                        PKeyed("zoomdlg.up", IconButton(icon: Icon(FluentSystemIcons.chevronUp, size: 10), onPressed: { [weak self] in self?._step(1) })),
                        PKeyed("zoomdlg.down", IconButton(icon: Icon(FluentSystemIcons.chevronDown, size: 10), onPressed: { [weak self] in self?._step(-1) })),
                    ]),
                ]),
                ok ? gap(0) : Padding(padding: EdgeInsets(left: 0, top: 6, right: 0, bottom: 0),
                                      child: Text("Enter a whole number from 10 to 400.", style: caption)),
            ]),
        ])
        return DialogShell(title: "Zoom", page: page, okEnabled: ok, width: 340,
                           onOK: { [weak self] in
                               guard let self else { return }
                               let typed = Self.parse(self._percent.text)
                               guard self._choice == 0 || typed != nil else { return }
                               self._w.onApply(self._choice == 0 ? nil : typed)
                           },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}
