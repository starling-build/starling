// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// The permission sheet — milestone 5 of docs/plans/ipad-ui.md.
//
// An extension on the tabs state, like TerminalSwitcher.swift and
// TerminalHelp.swift, because none of this is chrome: watching for a question
// and deciding what a tap sends must be identical on every platform, and the
// sheet is worth having on all of them. The Mac terminal is where it is
// developed — Claude Code runs there without a simulator or an ssh hop in the
// way — and nothing below is conditioned on the platform.
//
// What it is NOT: a Claude Code client. It draws whatever numbered choice the
// program on the other end put on screen, in that program's own order and
// wording, and sends that program's own key. `GridRegions` finds the shape and
// `PromptDetector` decides whether we are sure enough to offer it; this file
// only draws and writes.
//
// The safety rule, restated because it lives here: prefer revealing over
// acting. The terminal underneath keeps the keyboard the whole time. This adds
// a second way to answer; it never removes the first, which is what makes a
// wrong sheet survivable — a person can see it is wrong and just type.

import Flutter
import FlutterSwiftBridge
import Foundation

/// The sheet's own metrics. Not shared with either chrome's palette: this is
/// the one surface that acts on the far machine, and it should not quietly
/// restyle when a sidebar colour changes.
enum PromptChrome {
    static let bg: Int = 0xFF_1B1E28
    static let scrim: Int = 0xB3_06070B
    static let hint: Int = 0xFF_6E7484
    static let item: Int = 0xFF_C7CCD8
    static let itemActive: Int = 0xFF_E9EBF0
    /// The option the program itself is pointing at. Marked, not pre-pressed —
    /// nothing here presses anything on the person's behalf.
    static let pick: Int = 0x2E_8AA0FF
    static let row: Double = 52
}

extension _TerminalTabsState {

    // MARK: - Watching for a question

    /// Poll the focused pane for something to offer.
    ///
    /// A poll rather than a hook because the emulator has no "screen settled"
    /// signal, and the generation counter makes a poll cheap: a scan happens
    /// only when the grid changed since the last one. 0.2s is under the time
    /// it takes to read a prompt and well over the cost of the scan.
    func _tickPrompt() {
        let mine = _promptTick
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self, mine == self._promptTick else { return }
            defer { self._tickPrompt() }

            guard let tab = self.tabs.indices.contains(self.active)
                    ? self.tabs[self.active] : nil,
                  let pane = tab.activePane else {
                if self._prompt != nil { self.setState { self._prompt = nil } }
                return
            }

            pane.session.lock.lock()
            let generation = pane.session.emulator.generation
            let unchanged = generation == self._promptGeneration
                && pane.id == self._promptPaneId
            let grid = unchanged ? nil : pane.session.emulator.grid
            pane.session.lock.unlock()

            guard let grid = grid else { return }
            self._promptGeneration = generation
            self._promptPaneId = pane.id
            // The screen moved, so a dismissal no longer applies to what is
            // on it now.
            if self._promptDismissedAt != 0, generation != self._promptDismissedAt {
                self._promptDismissedAt = 0
            }

            let found = PromptDetector.actionable(grid)
            let offered = self._promptDismissedAt == 0 ? found : nil
            if offered != self._prompt {
                self.setState { self._prompt = offered }
            }
        }
    }

    /// Answer the prompt by sending the key the program drew.
    ///
    /// Nothing here inspects the label. `PromptChoice.keystroke(for:)` is the
    /// only place that decides what goes on the wire, and it returns the digit
    /// as rendered — verified against a real session, where writing `1` with
    /// no Return confirmed an `rm` and the file was gone afterwards.
    func _answer(_ option: GridOption) {
        guard let prompt = _prompt,
              let tab = tabs.indices.contains(active) ? tabs[active] : nil,
              let pane = tab.activePane else { return }
        pane.session.write(prompt.keystroke(for: option))
        // Drop the sheet immediately rather than waiting for the next poll:
        // the far side takes a moment to redraw, and a sheet still sitting
        // there reads as "the tap did not land" and invites a second one.
        setState { _prompt = nil }
    }

    /// Ask the host what else it is holding.
    ///
    /// Failure is silence: an unreachable daemon leaves the list as it was
    /// rather than emptying it, because "there are no other workspaces" and
    /// "I could not ask" look identical in a sidebar and only one of them is
    /// worth redrawing for.
    func _promptOverlay(_ prompt: PromptChoice, _ window: Size) -> Widget {
        let width = min(560, max(280, window.width - 64))

        var rows: [Widget] = [
            SizedBox(width: width, height: 14),
            Row(crossAxisAlignment: .center, children: [
                SizedBox(width: 16, height: 14),
                _promptLabel("the terminal is asking", PromptChrome.hint, 11),
            ]),
            SizedBox(width: width, height: 8),
        ]
        for option in prompt.options {
            let isMarked = prompt.options.firstIndex(of: option) == prompt.selected
            rows.append(_sheetRow(option, marked: isMarked, width: width))
        }
        rows.append(SizedBox(width: width, height: 6))
        // Not a "cancel": nothing is cancelled, the question is still on
        // screen and still answerable by typing. This only puts the sheet
        // away for the person who would rather use the keyboard.
        rows.append(Listener(
            onPointerDown: { [self] _ in
                setState { _promptDismissedAt = _promptGeneration; _prompt = nil }
            },
            behavior: .opaque,
            child: SizedBox(
                width: width, height: PromptChrome.row,
                child: Row(crossAxisAlignment: .center, children: [
                    SizedBox(width: 16, height: PromptChrome.row),
                    _promptLabel("answer in the terminal instead",
                                 PromptChrome.hint, 13),
                ]))))
        rows.append(SizedBox(width: width, height: 10))

        let sheet = DecoratedBox(
            decoration: BoxDecoration(
                color: Color(PromptChrome.bg),
                borderRadius: BorderRadius.circular(12)),
            child: SizedBox(
                width: width,
                child: Column(crossAxisAlignment: .stretch, children: rows)))

        return Positioned(
            left: 0, top: 0, right: 0, bottom: 0,
            child: DecoratedBox(
                decoration: BoxDecoration(color: Color(PromptChrome.scrim)),
                child: Center(child: sheet)))
    }

    func _sheetRow(_ option: GridOption, marked: Bool,
                           width: Double) -> Widget {
        return Listener(
            onPointerDown: { [self] _ in _answer(option) },
            behavior: .opaque,
            child: SizedBox(
                width: width, height: PromptChrome.row,
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: Color(marked ? PromptChrome.pick : 0x00_000000)),
                    child: Row(crossAxisAlignment: .center, children: [
                        SizedBox(width: 16, height: PromptChrome.row),
                        // The digit, shown because it is also what gets sent —
                        // so the sheet and the keyboard visibly agree.
                        _promptLabel(String(option.key), PromptChrome.hint, 13),
                        SizedBox(width: 12, height: PromptChrome.row),
                        Expanded(child: _promptLabel(
                            option.label,
                            marked ? PromptChrome.itemActive : PromptChrome.item,
                            14)),
                        SizedBox(width: 16, height: PromptChrome.row),
                    ]))))
    }


    func _promptLabel(_ text: String, _ color: Int, _ size: Double) -> Widget {
        Text(text, style: TextStyle(
            color: Color(color), fontSize: size,
            fontFamily: TerminalFontLoader.family,
            fontFamilyFallback: TerminalFontLoader.fallback))
    }
}
