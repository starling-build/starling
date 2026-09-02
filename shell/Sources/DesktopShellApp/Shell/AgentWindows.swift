// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

//
// Headless windows for broker clients.
//
// What is left of the AI Space after its UI was removed. The workbench — the
// sessions rail, the conversation column, the stage, the demo — is gone;
// workspace mode (WorkspaceSpace.swift) is the desktop-facing version of that
// idea. What survives is the ability to launch a window that belongs to a
// broker client rather than to the desktop.
//
// Those windows are now genuinely headless: they are owned, so every desktop
// query filters them out, and there is no longer any space that draws them.
// That is exactly what their remaining consumer wants — `test/functional.py`
// launches a Settings or Files pane and asserts on its SEMANTIC TREE, never on
// pixels, which is how this suite avoids the screenshot-diffing trap. The child
// still runs and still builds its widget tree; nothing composites it.
//
// So: keep this file working, or the functional tier loses its ability to drive
// panes. In particular STARLING_AGENT_ENDPOINT below is what starts the child's
// semantics server (sdk/Sources/Flutter/Platform/AgentSemanticsEndpoint.swift),
// and it is set in exactly one place — here.
//

import Flutter
import FlutterSwiftBridge
import Foundation

extension _DesktopShellState {

    // MARK: Sizes
    //
    // Agent windows are displayed in the workspace's tab pane, which FITS
    // them (they are never resized after birth — their size is the
    // coordinate space the agent works in). So the launch size IS the
    // display size: born at the pane's size a window fills it at scale 1.0;
    // born at anything else it is letterboxed for its whole life. These
    // returned the old workbench-stage sizes long after that layout was
    // gone, which is why a terminal sat in a pillar of scrim while Chrome —
    // born near the pane's aspect by accident — looked full-pane.

    /// Size for an app window a broker client drives: the workspace tab
    /// pane it will be shown in.
    func _agentStageContentSize() -> Size {
        _workspaceTabPaneContentSize()
    }

    /// Size for a terminal a broker client drives. The same pane: the
    /// "narrower, so a TUI reflows" reasoning belonged to the workbench's
    /// chat column — in the workspace the terminal gets the whole pane like
    /// every other window, and a narrow one just letterboxes.
    func _agentChatContentSize() -> Size {
        _workspaceTabPaneContentSize()
    }

    #if os(Linux)

    /// Launch a host app for a broker client, claiming its Wayland connection.
    ///
    /// `recipe` is the app record's `Exec` — the `app-run` recipe name, which
    /// owns every per-app flag and env there is. The shell does not know what
    /// Chrome or IntelliJ need and must not learn: this is the same call the
    /// dock makes, minus the desktop presence.
    ///
    /// The claim is armed immediately before spawning and consumed by the
    /// first toplevel from a new client (see the onNewToplevel handler). Left
    /// armed it would still be armed when a human opens a browser later, and
    /// their window would become the client's — which is why the broker
    /// disarms it on a launch timeout.
    func _launchAgentHostApp(agentId: String, recipe: String, arg: String? = nil,
                             discreteGpu: Bool = false,
                             onWindow: ((String) -> Void)? = nil) -> Bool {
        guard let wayland = waylandIntegration, let socketName = wayland.socketName else {
            return false
        }
        let xdgDir = LoginUser.runtimeDir
        let appRun = ProcessInfo.processInfo.environment["STARLING_APP_RUN"] ?? "/usr/bin/app-run"
        let process = Process()
        let args = arg.map { [recipe, $0] } ?? [recipe]
        // setsid, for the same non-optional reason _spawnLauncher does it: an
        // app left in the SHELL's process group turns any kill(-pgid, …) meant
        // for the app into one that takes the desktop down. The dock's path
        // has had this since the quit-by-group work; this one was spawning
        // Chrome straight into our group.
        if FileManager.default.isExecutableFile(atPath: "/usr/bin/setsid") {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/setsid")
            process.arguments = [appRun] + args
        } else {
            process.executableURL = URL(fileURLWithPath: appRun)
            process.arguments = args
        }
        var env = ProcessInfo.processInfo.environment
        env["STARLING_WAYLAND"] = socketName
        env["STARLING_XDG_DIR"] = xdgDir
        env["STARLING_APP_SCALE"] = String(currentShellDpi)
        // PRIME offload, as policy from the record and mechanism in app-run —
        // the dock's rule, applied here too rather than re-derived.
        if discreteGpu, DiscreteGpu.renderNode != nil {
            env["STARLING_APP_GPU"] = "discrete"
        }
        // Per-client CDP profile: the broker's cdp_endpoint op reads the
        // DevToolsActivePort this drops in the app home. Chrome only — for
        // anything else the variable means nothing and the recipe ignores it,
        // but setting it would imply a DevTools endpoint that never appears.
        if recipe == "chrome" {
            env["STARLING_CDP"] = agentId
        }
        process.environment = env
        _pendingAgentWayland = (agentId, onWindow)
        do {
            try process.run()
            return true
        } catch {
            _pendingAgentWayland = nil
            return false
        }
    }

    /// Launch a first-party app as a window owned by a broker client: the same
    /// DMA-BUF plumbing the dock uses, but tagged `ownerAgentId` so it has no
    /// desktop presence and steals no focus. `onWindow` fires on the main
    /// thread once the window exists — the broker answers `launch` with it.
    func _launchAgentChildApp(agentId: String, execName: String,
                              appId: String, title: String,
                              rect: Rect, isTerminal: Bool,
                              onWindow: ((String) -> Void)? = nil) {
        guard let mgr = linuxProcessAppManager else { return }
        let contentW = Int(rect.width)
        let contentH = Int(rect.height - DesktopTheme.kTitleBarHeight)
        // The child's semantics endpoint, which the broker's semantic_tree and
        // perform_action are proxied to. Setting this is the whole reason the
        // functional tier can assert on structure instead of pixels.
        let endpointPath = (ProcessInfo.processInfo.environment["XDG_RUNTIME_DIR"] ?? "/tmp")
            + "/starling-sem-\(getpid())-\(appId.replacingOccurrences(of: ":", with: "-")).sock"
        _ = mgr.launchDmaBufApp(
            executableName: execName,
            contentWidth: contentW,
            contentHeight: contentH,
            extraEnv: ["STARLING_AGENT_ENDPOINT": endpointPath],
            onReady: { [self] (texId: Int64) in
                mgr.onFirstFrame(textureId: texId) { [self] in
                    setState {
                        processTextureIds[appId] = texId
                        let winId = windowManager.addWindow(
                            title: title,
                            appId: appId,
                            rect: rect,
                            textureId: Int(texId),
                            onWindowClose: {
                                mgr.destroyApp(textureId: texId)
                            },
                            onPointerEvent: { (phase, x, y, buttons) in
                                mgr.sendPointerEvent(
                                    textureId: texId, phase: phase,
                                    x: x, y: y, buttons: buttons)
                            },
                            onContentResize: { (width, height) in
                                mgr.sendResize(
                                    textureId: texId,
                                    width: Int(width), height: Int(height))
                            },
                            onScrollEvent: { (x, y, dx, dy) in
                                mgr.sendScrollEvent(
                                    textureId: texId,
                                    x: x, y: y, dx: dx, dy: dy)
                            },
                            ownerAgentId: agentId,
                            appBuilder: { _ in SizedBox(expand: ()) }
                        )
                        windowManager.windows.first(where: { $0.id == winId })?
                            .agentEndpointPath = endpointPath
                        if isTerminal {
                            windowManager.agents.first(where: { $0.id == agentId })?
                                .terminalWindowId = winId
                        }
                        onWindow?(winId)
                    }
                }
            },
            onTerminated: { [self] in
                setState {
                    processTextureIds.removeValue(forKey: appId)
                    if isTerminal {
                        windowManager.agents.first(where: { $0.id == agentId })?
                            .terminalWindowId = nil
                    }
                    // Never mounted in the desktop tree — no close animation
                    // to play; drop the window directly.
                    if let win = windowManager.windows.first(where: { $0.appId == appId }) {
                        windowManager.closeWindow(win.id)
                    }
                }
            }
        )
    }

    #endif
}
