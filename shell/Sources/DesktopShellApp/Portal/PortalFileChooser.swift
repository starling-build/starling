// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(Linux)
import Flutter
import FlutterSwiftBridge
import PortalService
import Foundation

// Bridges the XDG Desktop Portal FileChooser to the shell's window system.
//
// When a client (Chrome, VS Code) calls FileChooser.OpenFile/SaveFile, the
// portal service (background thread) invokes `portalChooserLaunchThunk`. We
// launch FileExplorerApp --picker as a DMA-BUF composited child window; when
// it exits it has printed the selected file:// URIs to stdout, which we parse
// and hand back to the portal via completeRequest → D-Bus Response.

/// C-ABI launcher registered with the portal service. Runs on the PORTAL
/// thread; it copies the arguments and hands off to the main thread, then
/// returns 0 (launched — the result arrives later via completeRequest).
let portalChooserLaunchThunk: portal_launch_chooser_fn = {
    (_ /*userdata*/, handle, _ /*executable*/, callerPid, title,
     multiple, directory, saveMode, currentFolder, acceptLabel, suggestedName) -> Int32 in

    guard let handle = handle else { return -1 }
    let handleStr = String(cString: handle)
    let titleStr = title.map { String(cString: $0) } ?? "Open"
    let folderStr = currentFolder.map { String(cString: $0) }
    let acceptStr = acceptLabel.map { String(cString: $0) }
    let nameStr = suggestedName.map { String(cString: $0) }
    let isMultiple = multiple != 0
    let isDirectory = directory != 0
    let isSave = saveMode != 0

    DispatchQueue.main.async {
        guard let shell = _shellState else {
            portalIntegration?.completeRequest(handle: handleStr, uris: [], response: 2)
            return
        }
        shell.launchFileChooser(
            handle: handleStr, title: titleStr, callerPid: pid_t(callerPid),
            multiple: isMultiple, directory: isDirectory, saveMode: isSave,
            currentFolder: folderStr, acceptLabel: acceptStr, suggestedName: nameStr)
    }
    return 0
}

extension _DesktopShellState {

    /// Launch the file-chooser picker as a DMA-BUF child window. Called on the
    /// main thread. The picker prints selected file:// URIs to stdout on exit.
    func launchFileChooser(handle: String, title: String, callerPid: pid_t,
                           multiple: Bool, directory: Bool, saveMode: Bool,
                           currentFolder: String?, acceptLabel: String?,
                           suggestedName: String?) {
        guard let mgr = linuxProcessAppManager else {
            portalIntegration?.completeRequest(handle: handle, uris: [], response: 2)
            return
        }

        var env: [String: String] = ["PORTAL_TITLE": title]
        if multiple { env["PORTAL_MULTIPLE"] = "1" }
        if directory { env["PORTAL_DIRECTORY"] = "1" }
        if saveMode { env["PORTAL_SAVE"] = "1" }
        if let f = currentFolder, !f.isEmpty { env["PORTAL_FOLDER"] = f }
        if let a = acceptLabel, !a.isEmpty { env["PORTAL_ACCEPT_LABEL"] = a }
        if let n = suggestedName, !n.isEmpty { env["PORTAL_SUGGESTED_NAME"] = n }

        // Whose dialog is this? Walk up from the process that made the D-Bus
        // call to the window it owns — the same ancestry walk that pairs an
        // agent with the app driving it. A chooser opened by an AGENT's
        // browser becomes that agent's window: it appears in the agent's
        // workspace where the agent can actually drive it, and it stops
        // landing on the human's desktop, where it blocked the agent forever
        // and put a browser for the human's files on screen uninvited.
        //
        // nil is the ordinary case — the human's own browser asked — and
        // leaves the dialog exactly where it has always been.
        let owner = _ownerForRequestingProcess(callerPid)

        let appId = "portal-chooser-\(handle)"
        let winRect = Rect.fromLTWH(180, 100, 760, 520)
        let contentW = Int(winRect.width)
        let contentH = Int(winRect.height - DesktopTheme.kTitleBarHeight)

        let started = mgr.launchDmaBufApp(
            executableName: "FileExplorerApp",
            contentWidth: contentW,
            contentHeight: contentH,
            extraArgs: ["--picker"],
            extraEnv: env,
            onExit: { (stdout: String, status: Int32) in
                // Sole completion point: the picker always runs its termination
                // handler. Parse file:// URIs (one per line).
                var uris: [String] = []
                for line in stdout.split(separator: "\n") {
                    let t = line.trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("file://") { uris.append(t) }
                }
                let response: UInt32 = (status == 0 && !uris.isEmpty) ? 0 : 1
                portalIntegration?.completeRequest(handle: handle, uris: uris, response: response)
            },
            onReady: { [weak self] (texId: Int64) in
                guard let self = self else { return }
                // Show the window only after the first rendered frame.
                mgr.onFirstFrame(textureId: texId) { [weak self] in
                    self?.setState {
                        self?.windowManager.addWindow(
                            title: title,
                            appId: appId,
                            rect: winRect,
                            textureId: Int(texId),
                            onWindowClose: { mgr.destroyApp(textureId: texId) },
                            onPointerEvent: { (phase, x, y, buttons) in
                                mgr.sendPointerEvent(textureId: texId, phase: phase,
                                                     x: x, y: y, buttons: buttons)
                            },
                            onContentResize: { (width, height) in
                                mgr.sendResize(textureId: texId,
                                               width: Int(width), height: Int(height))
                            },
                            ownerAgentId: owner,
                            appBuilder: { _ in SizedBox(expand: ()) }
                        )
                    }
                }
            },
            onTerminated: { [weak self] in
                // Picker exited — tear down its window. The result was already
                // delivered from onExit (which runs first).
                self?._portalBeginClosingWindow(appId: appId)
            }
        )

        if !started {
            portalIntegration?.completeRequest(handle: handle, uris: [], response: 2)
        }
    }
}
#endif
