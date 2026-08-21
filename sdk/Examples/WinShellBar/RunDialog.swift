// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The Run dialog — Win+R.
//
// Explorer owns the native one (shell32's RunFileDlg, invoked by explorer's
// hotkey handler), so with explorer gone Win+R does nothing at all. This is
// the plan's "small launcher mode, not a new app": its own parked overlay
// process (`--run`), pinned to the work area's bottom-LEFT corner where
// Windows puts its own, toggled by the dock's Win+R chord.
//
// Execution is ShellExecuteW via Win32AppCatalog.open — programs, documents,
// folders and URLs alike, which is exactly the native dialog's contract —
// with %VAR% expansion first, which is the other half of what people type
// into Run. No MRU history yet; the field keeps its last command per run of
// the process, which is native behavior too.

#if os(Windows)
import Flutter
import FlutterSwiftBridge
import FlutterWin32
import CupertinoIcons
import Foundation

let kRunWidth = 404.0
let kRunHeight = 170.0
let kRunGap = 16.0

final class StarlingRun: StatefulWidget {
    override func createState() -> State<StatefulWidget> { StarlingRunState() }
}

final class StarlingRunState: State<StatefulWidget> {
    private let field = TextEditingController()
    private var errorText: String?

    private enum Hover: Equatable { case ok, cancel }
    private var hovered: Hover?

    override func initState() {
        super.initState()
        // The parked-black bargain, and a clean slate per open: the command
        // stays but comes back SELECTED, so typing replaces it — native Run's
        // own behavior, and the difference between "keeps history" and
        // "appends garbage". A stale error does not survive the reopen.
        Win32WindowedHost.host?.onToggle { [weak self] in
            guard let self else { return }
            if Win32WindowedHost.host?.isVisible == true {
                self.field.selection = TextSelection(
                    baseOffset: 0, extentOffset: self.field.text.count)
                self.setState { self.errorText = nil }
            }
        }
    }

    // MARK: - Execution

    /// %VAR% expansion, the native dialog's other half: `%windir%\system32`
    /// has to work or the dialog reads as broken to the people who use it.
    private func expandEnv(_ s: String) -> String {
        guard s.contains("%") else { return s }
        var out = s
        for (k, v) in ProcessInfo.processInfo.environment {
            out = out.replacingOccurrences(of: "%\(k)%", with: v,
                                           options: .caseInsensitive)
        }
        return out
    }

    private func execute() {
        let cmd = field.text.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }
        let expanded = expandEnv(cmd)
        if Win32AppCatalog.open(expanded) {
            hide()
        } else {
            // The native dialog's own wording, minus the modal error box —
            // inline is kinder and the Esc to dismiss is the same.
            setState {
                errorText = "Windows cannot find '\(cmd)'. Make sure you "
                    + "typed the name correctly, and then try again."
            }
        }
    }

    private func hide() {
        setState { errorText = nil }
        Win32WindowedHost.host?.setVisible(false)
    }

    // MARK: - Geometry

    private var okRect: (x: Double, y: Double, w: Double, h: Double) {
        (kRunWidth - 2 * 96 - 2 * 8, kRunHeight - 44, 96, 30)
    }
    private var cancelRect: (x: Double, y: Double, w: Double, h: Double) {
        (kRunWidth - 96 - 8, kRunHeight - 44, 96, 30)
    }

    private func hit(_ r: (x: Double, y: Double, w: Double, h: Double),
                     _ x: Double, _ y: Double) -> Bool {
        x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h
    }

    // MARK: - Build

    private func button(_ label: String, accent: Bool, hoveredHere: Bool,
                        _ p: WinPalette) -> Widget {
        ClipRRect(borderRadius: BorderRadius.circular(4)) {
            ColoredBox(color: accent
                           ? (hoveredHere ? p.accent.withOpacity(0.9) : p.accent)
                           : (hoveredHere ? p.buttonHover : p.button)) {
                Center {
                    Text(label,
                         style: TextStyle(color: accent ? p.onAccent : p.ink,
                                          fontSize: 13))
                }
            }
        }
    }

    override func build(_ context: any BuildContext) -> Widget {
        let p = WinPalette.of(dark: Win32Control.isDarkMode)
        return Directionality(
            textDirection: .ltr,
            child: Listener(
                onPointerDown: { [weak self] event in
                    guard let self else { return }
                    let x = event.position.dx, y = event.position.dy
                    if self.hit(self.okRect, x, y) { self.execute() }
                    else if self.hit(self.cancelRect, x, y) { self.hide() }
                },
                onPointerHover: { [weak self] event in
                    guard let self else { return }
                    let x = event.position.dx, y = event.position.dy
                    let over: Hover? = self.hit(self.okRect, x, y) ? .ok
                        : self.hit(self.cancelRect, x, y) ? .cancel : nil
                    if over != self.hovered {
                        self.setState { self.hovered = over }
                    }
                },
                behavior: .opaque,
                child: SizedBox(width: kRunWidth, height: kRunHeight) {
                    ClipRRect(borderRadius: BorderRadius.circular(8)) {
                        ColoredBox(color: p.stroke) {
                            Padding(padding: EdgeInsets(left: 1, top: 1, right: 1, bottom: 1)) {
                                ClipRRect(borderRadius: BorderRadius.circular(7)) {
                                    ColoredBox(color: p.panel) {
                                        Stack(alignment: Alignment.topLeft) {
                                            Positioned(left: 16, top: 12, width: kRunWidth - 32, height: 20) {
                                                Text("Run",
                                                     style: TextStyle(color: p.ink, fontSize: 14,
                                                                      fontWeight: .w600))
                                            }
                                            Positioned(left: 16, top: 36, width: kRunWidth - 32, height: 32) {
                                                Text("Type the name of a program, folder, document, "
                                                         + "or Internet resource, and Windows will open "
                                                         + "it for you.",
                                                     style: TextStyle(color: p.subInk, fontSize: 12),
                                                     maxLines: 2)
                                            }
                                            Positioned(left: 16, top: 78, width: 42, height: 28) {
                                                Center {
                                                    Text("Open:",
                                                         style: TextStyle(color: p.ink, fontSize: 12))
                                                }
                                            }
                                            Positioned(left: 64, top: 78, width: kRunWidth - 80, height: 28) {
                                                MacosTextField(
                                                    controller: field,
                                                    onSubmitted: { [weak self] _ in self?.execute() },
                                                    autofocus: true)
                                            }
                                            if let errorText {
                                                Positioned(left: 16, top: 108, width: kRunWidth - 32, height: 16) {
                                                    Text(errorText,
                                                         style: TextStyle(
                                                             color: Win32Control.isDarkMode
                                                                 ? Color(0xFFFF99A4)
                                                                 : Color(0xFFC42B1C),
                                                             fontSize: 11),
                                                         overflow: .ellipsis, maxLines: 1)
                                                }
                                            }
                                            Positioned(left: okRect.x, top: okRect.y,
                                                       width: okRect.w, height: okRect.h) {
                                                button("OK", accent: true,
                                                       hoveredHere: hovered == .ok, p)
                                            }
                                            Positioned(left: cancelRect.x, top: cancelRect.y,
                                                       width: cancelRect.w, height: cancelRect.h) {
                                                button("Cancel", accent: false,
                                                       hoveredHere: hovered == .cancel, p)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            )
        )
    }
}

#endif
