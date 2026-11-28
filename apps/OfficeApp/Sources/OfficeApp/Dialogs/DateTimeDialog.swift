// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-FD-1: Insert → Date & Time. The formats show today's moment; "Update automatically" inserts a DATE or TIME
// field (F9 brings it up to date) rather than plain text. OK is one undo step.

import Flutter
import FlutterSwiftBridge
import OfficeText

final class DateTimeDialog: StatefulWidget {
    let clock: FieldClock
    let onOK: (_ picture: String, _ automatic: Bool) -> Void
    let onCancel: () -> Void

    /// The pictures Word offers, dates then times.
    static let pictures = ["M/d/yyyy", "dddd, MMMM d, yyyy", "MMMM d, yyyy", "d MMMM yyyy", "yyyy-MM-dd", "d-MMM-yy",
                           "MMMM yy", "h:mm AM/PM", "h:mm:ss AM/PM", "HH:mm", "HH:mm:ss"]

    /// The format list's box, in pixels.
    static let listHeight: Double = 210

    init(clock: FieldClock, onOK: @escaping (String, Bool) -> Void, onCancel: @escaping () -> Void) {
        self.clock = clock; self.onOK = onOK; self.onCancel = onCancel
        super.init()
    }
    override func createState() -> State<StatefulWidget> { DateTimeDialogState() }
}

final class DateTimeDialogState: State<StatefulWidget> {
    private var _w: DateTimeDialog { widget as! DateTimeDialog }
    private var _picked = 1
    /// The format list's scroll (a test reads how far it moved).
    let listScroll = ScrollController()
    private var _automatic = false

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        var rows: [Widget] = []
        for (i, picture) in DateTimeDialog.pictures.enumerated() {
            let shown = _w.clock.format(picture: picture, english: true) ?? picture
            let on = i == _picked
            rows.append(GestureDetector(onTap: { [weak self] in self?.setState { self?._picked = i } }, child:
                ColoredBox(color: on ? Color(0xFFCCE4F7) : Color(0x00000000), child:
                    Padding(padding: EdgeInsets(left: 8, top: 4, right: 8, bottom: 4), child:
                        Text(shown, style: fluent.typography.body)))))
        }
        let page: Widget = Column(crossAxisAlignment: .start, children: [
            Text("Available formats:", style: fluent.typography.body),
            SizedBox(width: nil, height: 6),
            // A fixed box that scrolls, as Word's list does: the eleven formats are taller than the dialog may grow.
            SizedBox(width: nil, height: DateTimeDialog.listHeight, child: DecoratedBox(decoration: BoxDecoration(
                border: Border.all(color: fluent.resources.controlStrokeColorDefault, width: 1)), child:
                Padding(padding: EdgeInsets(left: 1, top: 1, right: 1, bottom: 1), child:
                    SingleChildScrollView(controller: listScroll, child: Column(crossAxisAlignment: .stretch, children: rows))))),
            SizedBox(width: nil, height: 8),
            Checkbox(checked: _automatic, onChanged: { [weak self] v in self?.setState { self?._automatic = v ?? false } },
                     content: Text("Update automatically", style: fluent.typography.body)),
        ])
        return DialogShell(title: "Date and Time", page: page, okEnabled: true, width: 320,
                           onOK: { [weak self] in
                               guard let self else { return }
                               self._w.onOK(DateTimeDialog.pictures[self._picked], self._automatic)
                           },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}
