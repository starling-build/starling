// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-OB-1: the two Picture Format dialogs that ask for a value: Alt Text (the words a screen
// reader says) and Crop (how much of each side to cut off, in percent of the picture).
// Both sit in DialogShell; OK applies as one undoable step on the controller.

import Flutter
import FlutterSwiftBridge
import OfficeText

/// Gives a control a stable id so a test (and a driver) can reach it.
private final class PicKeyed: StatelessWidget {
    let child: Widget
    init(_ id: String, _ child: Widget) { self.child = child; super.init(key: ValueKey(id)) }
    override func build(_ context: any BuildContext) -> Widget { child }
}

/// Which picture dialog is open.
enum PictureDialogKind { case altText, crop, boxText }

final class PictureAltTextDialog: StatefulWidget {
    let initial: String
    let title: String
    let prompt: String
    let onOK: (String) -> Void
    let onCancel: () -> Void
    init(initial: String, title: String = "Alt Text", prompt: String = "Describe the picture for people who cannot see it.",
         onOK: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial; self.title = title; self.prompt = prompt; self.onOK = onOK; self.onCancel = onCancel
        super.init()
    }
    override func createState() -> State<StatefulWidget> { PictureAltTextDialogState() }
}

final class PictureAltTextDialogState: State<StatefulWidget> {
    private var _w: PictureAltTextDialog { widget as! PictureAltTextDialog }
    private let _text = TextEditingController()
    override func initState() { super.initState(); _text.text = _w.initial }
    override func dispose() { _text.dispose(); super.dispose() }

    override func build(_ context: any BuildContext) -> Widget {
        let page = Column(crossAxisAlignment: .start, children: [
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8),
                    child: Text(_w.prompt)),
            PicKeyed(_w.title == "Alt Text" ? "alt-text" : "box-text", SizedBox(height: 90, child: FluentTextBox(controller: _text, maxLines: 4))),
        ])
        return DialogShell(title: _w.title, page: page,
                           onOK: { [weak self] in guard let self else { return }; self._w.onOK(self._text.text) },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}

final class CropDialog: StatefulWidget {
    let initial: PictureCrop?
    let onOK: (PictureCrop?) -> Void
    let onCancel: () -> Void
    init(initial: PictureCrop?, onOK: @escaping (PictureCrop?) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial; self.onOK = onOK; self.onCancel = onCancel
        super.init()
    }
    override func createState() -> State<StatefulWidget> { CropDialogState() }
}

final class CropDialogState: State<StatefulWidget> {
    private var _w: CropDialog { widget as! CropDialog }
    private let _sides = ["left", "top", "right", "bottom"]
    private var _fields: [String: TextEditingController] = [:]

    private static func percent(_ share: Double) -> String {
        let p = (share * 1000).rounded() / 10
        return p == p.rounded() ? String(Int(p)) : String(p)
    }

    override func initState() {
        super.initState()
        let c = _w.initial
        let start: [Double] = [c?.left ?? 0, c?.top ?? 0, c?.right ?? 0, c?.bottom ?? 0]
        for (i, s) in _sides.enumerated() {
            let t = TextEditingController(); t.text = Self.percent(start[i]); _fields[s] = t
        }
    }
    override func dispose() { for t in _fields.values { t.dispose() }; super.dispose() }

    /// The typed crop, or nil when a field is not a number from 0 up (blank counts as 0).
    private func typed() -> PictureCrop?? {
        var v: [Double] = []
        for s in _sides {
            let t = _fields[s]!.text.trimmingWhitespace()
            if t.isEmpty { v.append(0); continue }
            guard let d = Double(t), d >= 0, d < 95 else { return nil }
            v.append(d / 100)
        }
        guard 1 - v[0] - v[2] >= 0.05, 1 - v[1] - v[3] >= 0.05 else { return nil }
        return .some(v.allSatisfy { $0 == 0 } ? nil : PictureCrop(left: v[0], top: v[1], right: v[2], bottom: v[3]))
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        func row(_ side: String) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8), child: Row(crossAxisAlignment: .center, children: [
                SizedBox(width: 90, height: nil, child: Text(side.prefix(1).uppercased() + side.dropFirst() + " (%)")),
                PicKeyed("crop-\(side)", SizedBox(width: 90, height: Chrome.fieldHeight, child: FluentTextBox(
                    controller: _fields[side]!, onChanged: { [weak self] _ in self?.setState {} }))),
            ]))
        }
        let page = Column(crossAxisAlignment: .start, children: [
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8),
                    child: Text("Cut this much off each side of the picture.")),
        ] + _sides.map(row) + [
            PicKeyed("crop-reset", Chrome.textToggle("Reset", false, fluent) { [weak self] in
                guard let self else { return }
                for t in self._fields.values { t.text = "0" }
                self.setState {} }),
        ])
        return DialogShell(title: "Crop", page: page, okEnabled: typed() != nil,
                           onOK: { [weak self] in guard let self, let c = self.typed() else { return }; self._w.onOK(c) },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}
