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
    private var _alive = true
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
    }

    override func dispose() {
        _alive = false
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
        FileHandle.standardError.write(Data(
            "[ScreenShellApp] build taps=\(_taps) now=\(_now)\n".utf8))
        let device = ProcessInfo.processInfo
            .environment["STARLING_APP_DRM_DEVICE"] ?? "?"
        return MacosApp(
            theme: MacosThemeData.dark(),
            home: GestureDetector(
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
                    }
                }
                )
            )
        )
    }
}

runApp(ScreenShellRoot())
