// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Alt+Tab: a centred panel of the open windows as live thumbnails, most
// recent first. Tab with Alt held opens it on the second window and steps
// through; Shift steps back; letting Alt go switches to the one under the
// ring; Esc puts it away with nothing changed; a click on a card is the
// same as landing on it. Both styles use it — Windows' shape is the
// reference, so the panel is the SDK's flyout surface with the accent ring
// and 8px cards of Windows' Alt+Tab.

import Flutter
import FlutterSwiftBridge

enum AltTabMetrics {
    static let thumbW: Double = 208
    static let thumbH: Double = 117
    static let titleH: Double = 22
    static let pad: Double = FluentSpacing.m
    static let gap: Double = FluentSpacing.m
    static let perRow = 5
}

extension _DesktopShellState {

    /// Windows on the pointer's output, most recently focused first.
    private func _altTabCandidates() -> [WindowInfo] {
        windowManager.windows
            .filter { $0.ownerAgentId == nil && !$0.isMinimized
                && $0.spaceId == windowManager.activeSpace.id }
            .sorted { $0.zIndex > $1.zIndex }
    }

    /// Tab pressed with Alt down: open on the second window, or step.
    func _altTabStep(backwards: Bool) {
        if !_altTabOpen {
            let order = _altTabCandidates().map { $0.id }
            guard !order.isEmpty else { return }
            setState {
                _altTabOrder = order
                _altTabIndex = order.count > 1 ? 1 : 0
                _altTabOpen = true
            }
            return
        }
        guard !_altTabOrder.isEmpty else { return }
        let n = _altTabOrder.count
        setState { _altTabIndex = ((_altTabIndex + (backwards ? -1 : 1)) % n + n) % n }
    }

    /// Alt released: land on the ringed window.
    func _altTabCommit() {
        guard _altTabOpen else { return }
        let id = _altTabOrder.indices.contains(_altTabIndex) ? _altTabOrder[_altTabIndex] : nil
        setState {
            _altTabOpen = false
            _altTabOrder = []
        }
        if let id, windowManager.windows.contains(where: { $0.id == id }) {
            setState { windowManager.bringToFront(id) }
        }
    }

    func _altTabCancel() {
        guard _altTabOpen else { return }
        setState {
            _altTabOpen = false
            _altTabOrder = []
        }
    }

    func altTabWidget(_ context: any BuildContext) -> Widget? {
        guard _altTabOpen else { return nil }
        let m = AltTabMetrics.self
        let wins = _altTabOrder.compactMap { id in windowManager.windows.first { $0.id == id } }
        guard !wins.isEmpty else { return nil }
        var rows: [Widget] = []
        var i = 0
        while i < wins.count {
            let slice = Array(wins[i..<min(i + m.perRow, wins.count)])
            rows.append(Row(mainAxisSize: .min, spacing: m.gap,
                            children: slice.enumerated().map { j, win in
                                _altTabCard(win, selected: i + j == _altTabIndex, index: i + j, context)
                            }))
            i += m.perRow
        }
        let panel = fluentFlyoutFrame(
            width: Double(min(wins.count, m.perRow)) * (m.thumbW + m.gap) - m.gap + m.pad * 2,
            child: Padding(padding: EdgeInsets(all: m.pad),
                           child: Column(mainAxisSize: .min, spacing: m.gap, children: rows)))
        return Positioned(
            fill: (),
            child: Listener(
                onPointerDown: { [self] _ in _altTabCancel() },
                behavior: .translucent,
                child: Center(child: FluentEntrance(child: panel, slideFrom: Offset(0, 0)))))
    }

    private func _altTabCard(_ win: WindowInfo, selected: Bool, index: Int,
                             _ context: any BuildContext) -> Widget {
        let m = AltTabMetrics.self
        return Listener(
            onPointerDown: { [self] _ in
                setState { _altTabIndex = index }
                _altTabCommit()
            },
            behavior: .opaque,
            child: SizedBox(
                width: m.thumbW, height: m.thumbH + m.titleH,
                child: Column(crossAxisAlignment: .stretch, spacing: 4) {
                    DecoratedBox(
                        decoration: BoxDecoration(
                            border: Border.all(color: selected ? shellTheme.accent : shellTheme.controlStroke,
                                               width: selected ? 2 : FluentStrokeWidth.thin),
                            borderRadius: FluentCorners.overlayRadius),
                        child: SizedBox(
                            height: m.thumbH,
                            child: ClipRRect(
                                borderRadius: FluentCorners.overlayRadius,
                                child: _mcWindowContent(win, context))))
                    Text(String(win.title.prefix(28)),
                         style: fluentType.styled({ $0.caption },
                                                  selected ? shellTheme.fgPrimary : shellTheme.fgSecondary),
                         textAlign: .center, overflow: .ellipsis, maxLines: 1)
                }))
    }
}
