// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// The per-screen shell (docs/plans/nv-view.md, Stage B): the fullscreen
// surface an externally sourced output shows, run as a child process that
// renders on that screen's GPU (STARLING_APP_DRM_DEVICE) through the
// swapchain path. Today it is a proof surface — wallpaper, clock, GPU
// label; the real per-screen shell UI grows here.

import Flutter
import FlutterSwiftBridge
import Foundation

class ScreenShellRoot: StatefulWidget {
    override func createState() -> State<StatefulWidget> {
        return _ScreenShellRootState()
    }
}

class _ScreenShellRootState: State<StatefulWidget> {
    private var _now = ""
    private var _taps = 0
    private var _typed = ""
    private var _alive = true
    private let _focus = FocusNode(debugLabel: "ScreenShell")
    private let _fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    override func initState() {
        super.initState()
        _now = _fmt.string(from: Date())
        // Foundation.Timer never fires on the DRM embedder — the documented
        // asyncAfter pattern instead.
        scheduleTick()
        // Keyboard proof: echo what the shell relays while this screen holds
        // output-level key focus (a click here claims it).
        _focus.onKeyData = { [weak self] keyData in
            guard let self, keyData.type == .down || keyData.type == .repeat
            else { return false }
            FileHandle.standardError.write(Data(
                "[ScreenShellApp] KEY phys=0x\(String(keyData.physical, radix: 16))\n".utf8))
            self.setState {
                if keyData.physical == 0x2A {  // Backspace
                    if !self._typed.isEmpty { self._typed.removeLast() }
                } else if let ch = keyData.character,
                          let s = ch.unicodeScalars.first,
                          s.value >= 0x20, s.value != 0x7F {
                    self._typed += ch
                    if self._typed.count > 40 {
                        self._typed.removeFirst(self._typed.count - 40)
                    }
                }
            }
            return true
        }
        _focus.requestFocus()
        // Desktop windows overlapping this screen arrive over the window
        // stream as external textures; placement changes land here (the
        // callback runs on the drained GCD main queue, i.e. this thread —
        // same unsafeBitCast shape as scheduleTick). Texture CONTENT
        // repaints through the engine without this firing.
        let poke: () -> Void = { [weak self] in self?.setState {} }
        gpuDmaBufRendererState?.onExternalWindowsChanged =
            unsafeBitCast(poke, to: (@Sendable () -> Void).self)
    }

    override func dispose() {
        _alive = false
        _focus.dispose()
        super.dispose()
    }

    private func scheduleTick() {
        // Same unsafeBitCast shape as SettingsApp's battery tick: the
        // closure runs on the main queue, which is where this state lives.
        let work: () -> Void = { [weak self] in
            guard let self, self._alive else { return }
            self.setState { self._now = self._fmt.string(from: Date()) }
            self.scheduleTick()
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 1.0,
            execute: unsafeBitCast(work, to: (@Sendable () -> Void).self))
    }

    override func build(_ context: any BuildContext) -> Widget {
        let device = ProcessInfo.processInfo
            .environment["STARLING_APP_DRM_DEVICE"] ?? "?"
        let desk = GestureDetector(
                onTap: { [weak self] in
                    guard let self else { return }
                    FileHandle.standardError.write(Data("[ScreenShellApp] TAP\n".utf8))
                    self.setState { self._taps += 1 }
                },
                behavior: .opaque,
                child: ColoredBox(
                color: Color(0xFF10141C),
                child: Center {
                    Column(mainAxisAlignment: .center) {
                        SizedBox(
                            width: 900, height: 30,
                            child: Center {
                                Text("per-screen shell — rendering on \(device)" +
                                     (_taps > 0 ? " — taps: \(_taps)" : ""),
                                     style: TextStyle(color: Color(0xFF7A8494),
                                                      fontSize: 22))
                            })
                        SizedBox(height: 24)
                        Text(_now,
                             style: TextStyle(color: Color(0xFFF0F2F6),
                                              fontSize: 120,
                                              fontWeight: .w200))
                        SizedBox(height: 24)
                        SizedBox(
                            width: 900, height: 30,
                            child: Center {
                                Text(_typed.isEmpty
                                     ? "click, then type — keys land here"
                                     : "typed: \(_typed)",
                                     style: TextStyle(color: Color(0xFF7A8494),
                                                      fontSize: 22))
                            })
                    }
                }
                )
        )
        // Desktop windows relayed from the shell, unchromed for now —
        // placement is already in this screen's logical coordinates.
        let windows = gpuDmaBufRendererState?.externalWindows ?? []
        return Stack(fit: .expand) {
            Positioned(fill: (), child: desk)
            for win in windows {
                Positioned(
                    key: ValueKey("ext-\(win.window)"),
                    left: win.x, top: win.y,
                    width: win.width, height: win.height,
                    child: TextureWidget(textureId: Int(win.textureId),
                                         filterQuality: .low))
            }
        }
    }
}

class ScreenShellOuter: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        return MacosApp(theme: MacosThemeData.dark(), home: ScreenShellRoot())
    }
}

runApp(ScreenShellOuter())
