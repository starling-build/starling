// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Quick Settings: the panel the taskbar's status group opens on Windows.
//
// A grid of toggle tiles — the accent when on, with the accent's own ink,
// which is BLACK in dark mode — then the brightness and volume sliders, and
// a bottom row with the battery and the Settings gear. The Wi-Fi tile has a
// chevron that turns the panel into the network page: the list, a password
// prompt, a back arrow. Every control drives the same backend its Settings
// pane does, so the tile IS the setting and the two cannot disagree.
//
// The Wi-Fi page is the shell's `.wifi` popup kind, so the key router that
// feeds the password prompt and the broker's Wi-Fi bookkeeping keep working
// unchanged; only the drawing is new. The edit pencil Windows shows (reorder
// and hide tiles) is not built: a pencil that does nothing is worse than no
// pencil. Night light is left out for the same reason until the backlight
// service can do it.

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import StarlingNet
import StarlingRegistry
import StarlingPower
import StarlingAudio
import Foundation

// MARK: - Geometry

enum QuickSettingsMetrics {
    /// Windows' panel is 360 wide; its tiles sit three across.
    static let width: Double = 360
    static let pad: Double = FluentSpacing.xl          // 20
    static let columns = 3
    static let tileGap: Double = FluentSpacing.s        // 8
    static let tileHeight: Double = 52
    static let sliderRow: Double = 32
    static var tileWidth: Double {
        (width - pad * 2 - tileGap * Double(columns - 1)) / Double(columns)
    }
}

extension _DesktopShellState {

    /// A Fluent flyout's frame: acrylic, the flyout stroke, 8px corners and
    /// the elevation-32 shadow — the SDK's own flyout surface, at a width.
    func fluentFlyoutFrame(width: Double, child: Widget) -> Widget {
        FluentTheme(
            data: fluentThemeData(),
            child: DecoratedBox(
                decoration: BoxDecoration(
                    borderRadius: FluentCorners.overlayRadius,
                    boxShadow: FluentElevation.shadows(
                        FluentElevation.flyout,
                        brightness: shellTheme.isDark ? .dark : .light)),
                child: Acrylic(
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            border: Border.all(color: shellTheme.panelStroke,
                                               width: FluentStrokeWidth.thin),
                            borderRadius: FluentCorners.overlayRadius),
                        position: .foreground,
                        child: SizedBox(width: width, child: child)),
                    borderRadius: FluentCorners.overlayRadius)))
    }

    /// Which of the shell's popup kinds Quick Settings answers for in this
    /// style: the status group, the Wi-Fi page, and battery (which lives in
    /// the bottom row rather than a panel of its own).
    func fluentIsQuickSettings(_ kind: StatusBarPopup) -> Bool {
        switch kind {
        case .controlCenter, .wifi, .battery: return true
        default: return false
        }
    }

    func fluentQuickSettings(_ kind: StatusBarPopup) -> Widget {
        let m = QuickSettingsMetrics.self
        let body: Widget = kind == .wifi ? _qsWifiPage() : _qsTilesPage()
        return fluentFlyoutFrame(
            width: m.width,
            child: Padding(padding: EdgeInsets(all: m.pad), child: body))
    }

    // MARK: Tiles page

    private func _qsTilesPage() -> Widget {
        let m = QuickSettingsMetrics.self
        let net = networkService.snapshot
        let wifiOn = net.available && net.wifiEnabled
        let recording = recordingService?.isRecording == true

        let tiles: [Widget] = [
            _qsTile(icon: wifiOn ? FluentSystemIcons.wifiFull : FluentSystemIcons.wifiOff,
                    label: wifiOn ? (net.active?.ssid ?? "Wi-Fi") : "Wi-Fi",
                    active: wifiOn, enabled: net.available,
                    onTap: { [self] in setState { networkService.setWifiEnabled(!net.wifiEnabled) } },
                    onMore: { [self] in
                        setState { activeStatusBarPopup = .wifi }
                        networkService.refreshWithScan()
                    }),
            _qsTile(icon: FluentSystemIcons.moon, label: "Dark mode",
                    active: shellTheme.isDark,
                    onTap: { [self] in _setAppearance(dark: !shellTheme.isDark) }),
            _qsTile(icon: FluentSystemIcons.grid, label: "Tiling",
                    active: windowManager.tilingEnabled,
                    onTap: { [self] in _setTiling(!windowManager.tilingEnabled) }),
            _qsTile(icon: _ccAudio.muted ? FluentSystemIcons.mute : FluentSystemIcons.volume,
                    label: _ccAudio.muted ? "Muted" : "Sound",
                    active: !_ccAudio.muted, enabled: _ccAudio.available,
                    onTap: { [self] in
                        let muted = !_ccAudio.muted
                        setState { _ccAudio.muted = muted }
                        DispatchQueue.global(qos: .userInitiated).async { _ = AudioControl.setMuted(muted) }
                    }),
            _qsTile(icon: FluentSystemIcons.video,
                    label: recording ? "Recording" : "Record",
                    active: recording, enabled: recordingService?.available == true,
                    onTap: { [self] in
                        if recording {
                            recordingService?.stop()
                        } else {
                            // Close the panel first and give it a beat to leave
                            // the screen — footage of the button is not the
                            // desktop.
                            setState { activeStatusBarPopup = nil }
                            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300)) {
                                recordingService?.start()
                            }
                        }
                    }),
            _qsTile(icon: FluentSystemIcons.window,
                    label: recording ? "Recording" : "Record app",
                    active: recording && recordingService?.windowLabel != nil,
                    enabled: recordingService?.available == true,
                    onTap: { [self] in
                        if recording { recordingService?.stop(); return }
                        guard windowManager.visibleWindows.contains(where: { $0.textureId != nil }) else {
                            _postLocalNotification(summary: "Nothing to record",
                                                   body: "Open the app first — Record app captures one window.")
                            return
                        }
                        _openMissionControl(pickRecordTarget: true)
                    }),
        ]
        var rows: [Widget] = []
        var i = 0
        while i < tiles.count {
            let slice = Array(tiles[i..<min(i + m.columns, tiles.count)])
            rows.append(Row(crossAxisAlignment: .start, spacing: m.tileGap, children: slice))
            i += m.columns
        }

        var children: [Widget] = []
        children.append(Column(spacing: m.tileGap, children: rows))
        children.append(SizedBox(height: FluentSpacing.l))
        if _ccBacklight.present {
            let backlight = _ccBacklight
            children.append(_qsSliderRow(icon: FluentSystemIcons.brightness,
                                         value: Double(backlight.percent), enabled: true) { [self] v in
                let pct = Int(v.rounded())
                let scale = Double(backlight.maxBrightness) / 100.0
                setState { _ccBacklight.brightness = max(1, Int((Double(pct) * scale).rounded())) }
                let work: () -> Void = { BacklightControl.setPercent(pct, status: backlight) }
                DispatchQueue.global(qos: .userInitiated).async(
                    execute: unsafeBitCast(work, to: (@Sendable () -> Void).self))
            })
            children.append(SizedBox(height: FluentSpacing.xs))
        }
        children.append(_qsSliderRow(icon: _ccAudio.muted ? FluentSystemIcons.mute : FluentSystemIcons.volume,
                                     value: min(_ccAudio.volume, 1.0) * 100,
                                     enabled: _ccAudio.available) { [self] v in
            setState { _ccAudio.volume = v / 100 }
            DispatchQueue.global(qos: .userInitiated).async { _ = AudioControl.setVolume(v / 100) }
        })
        children.append(SizedBox(height: FluentSpacing.m))
        children.append(_qsFooter())
        return Column(crossAxisAlignment: .stretch, children: children)
    }

    /// One tile: the control on the accent when on, on the control fill
    /// when off, its label in the caption ramp beneath. `onMore` adds the
    /// chevron that opens a page of its own.
    private func _qsTile(icon: IconData, label: String, active: Bool,
                         enabled: Bool = true,
                         onTap: @escaping () -> Void,
                         onMore: (() -> Void)? = nil) -> Widget {
        let m = QuickSettingsMetrics.self
        let on = active && enabled
        let ink: Color = !enabled ? shellTheme.fgTertiary
            : (on ? shellTheme.accentInk : shellTheme.fgPrimary)
        func face(_ hot: Bool) -> Color {
            if !enabled { return shellTheme.controlFill }
            if on { return hot ? shellTheme.accent.mixed(toward: shellTheme.fgPrimary, by: 0.1) : shellTheme.accent }
            return hot ? shellTheme.controlHover : shellTheme.controlFill
        }
        let mainWidth = onMore == nil ? m.tileWidth : m.tileWidth - 30
        var parts: [Widget] = [
            SizedBox(
                width: mainWidth, height: m.tileHeight,
                child: HoverButton(
                    builder: { _, states in
                        let hot = states.isHovered || states.isPressed
                        return DecoratedBox(
                            decoration: BoxDecoration(
                                color: face(hot),
                                border: Border.all(color: on ? Color(0x00000000) : shellTheme.controlStroke,
                                                   width: FluentStrokeWidth.thin),
                                borderRadius: onMore == nil
                                    ? FluentCorners.controlRadius
                                    : BorderRadius.only(topLeft: Radius(circular: FluentCorners.control),
                                                        bottomLeft: Radius(circular: FluentCorners.control))),
                            child: Center(child: Icon(icon, size: 18, color: ink)))
                    },
                    onPressed: enabled ? onTap : nil)),
        ]
        if let onMore {
            parts.append(SizedBox(
                width: 30, height: m.tileHeight,
                child: HoverButton(
                    builder: { _, states in
                        let hot = states.isHovered || states.isPressed
                        return DecoratedBox(
                            decoration: BoxDecoration(
                                color: face(hot),
                                border: Border.all(color: on ? Color(0x00000000) : shellTheme.controlStroke,
                                                   width: FluentStrokeWidth.thin),
                                borderRadius: BorderRadius.only(
                                    topRight: Radius(circular: FluentCorners.control),
                                    bottomRight: Radius(circular: FluentCorners.control))),
                            child: Center(child: FluentGlyph(.chevronRight, size: 10, color: ink)))
                    },
                    onPressed: enabled ? onMore : nil)))
        }
        return SizedBox(
            width: m.tileWidth,
            child: Column(crossAxisAlignment: .center, spacing: FluentSpacing.xs) {
                Row(mainAxisSize: .min, children: parts)
                Text(label, style: fluentType.styled({ $0.caption }, shellTheme.fgPrimary),
                     textAlign: .center, overflow: .ellipsis, maxLines: 1)
            })
    }

    private func _qsSliderRow(icon: IconData, value: Double, enabled: Bool,
                              onChanged: @escaping (Double) -> Void) -> Widget {
        SizedBox(
            height: QuickSettingsMetrics.sliderRow,
            child: Row(crossAxisAlignment: .center, spacing: FluentSpacing.m) {
                Icon(icon, size: 16, color: enabled ? shellTheme.fgPrimary : shellTheme.fgTertiary)
                Expanded {
                    Slider(value: value, onChanged: enabled ? onChanged : nil, min: 0, max: 100)
                }
                SizedBox(width: 36, child: Text(
                    "\(Int(value.rounded()))",
                    style: fluentType.styled({ $0.caption }, shellTheme.fgSecondary),
                    textAlign: .right))
            })
    }

    /// Battery at the left, the Settings gear at the right.
    private func _qsFooter() -> Widget {
        let snap = batteryService.snapshot
        var left: [Widget] = []
        if snap.present {
            let icon: IconData = snap.state == .charging ? FluentSystemIcons.batteryCharging
                : (snap.percent < 13 ? FluentSystemIcons.batteryEmpty
                   : (snap.percent < 45 ? FluentSystemIcons.batteryHalf : FluentSystemIcons.battery))
            left = [
                Icon(icon, size: 16, color: shellTheme.fgPrimary),
                SizedBox(width: FluentSpacing.xs),
                Text("\(snap.percent)%", style: fluentType.styled({ $0.caption }, shellTheme.fgPrimary)),
            ]
        }
        return Row(mainAxisAlignment: .spaceBetween, crossAxisAlignment: .center) {
            Row(mainAxisSize: .min, children: left)
            _qsIconButton(FluentSystemIcons.settings) { [self] in
                setState { activeStatusBarPopup = nil }
                _launchOrFocusApp("settings", extraArgs: [])
            }
        }
    }

    private func _qsIconButton(_ icon: IconData, onTap: @escaping () -> Void) -> Widget {
        SizedBox(
            width: 32, height: 32,
            child: HoverButton(
                builder: { _, states in
                    let hot = states.isHovered || states.isPressed
                    return DecoratedBox(
                        decoration: BoxDecoration(
                            color: hot ? shellTheme.controlHover : Color(0x00000000),
                            borderRadius: FluentCorners.controlRadius),
                        child: Center(child: Icon(icon, size: 16, color: shellTheme.fgPrimary)))
                },
                onPressed: onTap))
    }

    // MARK: Wi-Fi page

    private func _qsWifiPage() -> Widget {
        let snap = networkService.snapshot
        if let ssid = _wifiPasswordSSID {
            return _qsWifiPassword(ssid: ssid)
        }
        var children: [Widget] = [
            Row(crossAxisAlignment: .center) {
                _qsIconButton(FluentSystemIcons.back) { [self] in
                    setState { activeStatusBarPopup = .controlCenter }
                    _refreshControlCenter()
                }
                SizedBox(width: FluentSpacing.s)
                Expanded { Text("Wi-Fi", style: fluentType.styled({ $0.bodyStrong }, shellTheme.fgPrimary, strong: true)) }
                if snap.available {
                    ToggleSwitch(checked: snap.wifiEnabled, onChanged: { [self] on in
                        setState { networkService.setWifiEnabled(on) }
                    })
                }
            },
            SizedBox(height: FluentSpacing.m),
        ]
        // The broker's row bookkeeping is the top-anchored macOS panel's;
        // this panel hangs from the bar, so it reports nothing here.
        _wifiRowCenters = []
        if !snap.available {
            children.append(Text("Wi-Fi is not available on this system.",
                                 style: fluentType.styled({ $0.body }, shellTheme.fgSecondary)))
        } else if !snap.wifiEnabled {
            children.append(Text("Wi-Fi is off.",
                                 style: fluentType.styled({ $0.body }, shellTheme.fgSecondary)))
        } else {
            if let active = snap.active {
                children.append(_qsNetworkRow(
                    ssid: active.ssid, signal: active.signal, secured: !active.security.isEmpty,
                    connected: true, detail: active.ipAddress,
                    onTap: nil,
                    trailing: _qsTextButton("Disconnect") { [self] in
                        networkService.disconnect(connectionName: active.ssid)
                    }))
            }
            let others = snap.networks.filter { !$0.inUse }
            for net in others.prefix(8) {
                let known = snap.savedNames.contains(net.ssid)
                children.append(_qsNetworkRow(
                    ssid: net.ssid, signal: net.signal, secured: !net.isOpen,
                    connected: false,
                    detail: _wifiConnecting == net.ssid ? "Connecting…" : (known ? "Saved" : ""),
                    onTap: { [self] in
                        guard _wifiConnecting == nil else { return }
                        if net.isOpen || known {
                            _wifiJoin(ssid: net.ssid, security: net.security, password: nil)
                        } else {
                            setState {
                                _wifiPasswordSSID = net.ssid
                                _wifiPasswordSecurity = net.security
                                _wifiPassword = ""
                                _wifiError = nil
                            }
                            _restartWifiCaret()
                        }
                    },
                    trailing: nil))
            }
            if others.isEmpty && snap.active == nil {
                children.append(Text("No networks found.",
                                     style: fluentType.styled({ $0.body }, shellTheme.fgSecondary)))
            }
        }
        if let err = _wifiError {
            children.append(SizedBox(height: FluentSpacing.xs))
            children.append(Text(err, style: fluentType.styled(
                { $0.caption }, fluentThemeData().resources.systemFillColorCritical)))
        }
        children.append(SizedBox(height: FluentSpacing.m))
        children.append(Row(mainAxisAlignment: .end) {
            _qsTextButton("More Wi-Fi settings") { [self] in
                setState { activeStatusBarPopup = nil }
                _launchOrFocusApp("settings", extraArgs: ["--pane=network"])
            }
        })
        return Column(crossAxisAlignment: .stretch, children: children)
    }

    private func _qsNetworkRow(ssid: String, signal: Int, secured: Bool, connected: Bool,
                               detail: String, onTap: (() -> Void)?, trailing: Widget?) -> Widget {
        let icon: IconData = signal > 66 ? FluentSystemIcons.wifiFull
            : (signal > 40 ? FluentSystemIcons.wifiGood
               : (signal > 15 ? FluentSystemIcons.wifiFair : FluentSystemIcons.wifiWeak))
        return HoverButton(
            builder: { [self] _, states in
                let hot = states.isHovered || states.isPressed
                return DecoratedBox(
                    decoration: BoxDecoration(
                        color: hot && onTap != nil ? shellTheme.controlHover
                            : (connected ? shellTheme.controlFill : Color(0x00000000)),
                        borderRadius: FluentCorners.controlRadius),
                    child: Padding(
                        padding: EdgeInsets(left: FluentSpacing.s, top: FluentSpacing.s,
                                            right: FluentSpacing.s, bottom: FluentSpacing.s),
                        child: Row(crossAxisAlignment: .center, spacing: FluentSpacing.m) {
                            Icon(icon, size: 18, color: shellTheme.fgPrimary)
                            Expanded {
                                Column(crossAxisAlignment: .start, spacing: 2) {
                                    Row(mainAxisSize: .min, spacing: FluentSpacing.xs) {
                                        Text(ssid, style: fluentType.styled({ $0.body }, shellTheme.fgPrimary),
                                             overflow: .ellipsis, maxLines: 1)
                                        if secured { Icon(FluentSystemIcons.lock, size: 11, color: shellTheme.fgTertiary) }
                                    }
                                    if !detail.isEmpty {
                                        Text(detail, style: fluentType.styled({ $0.caption }, shellTheme.fgSecondary),
                                             overflow: .ellipsis, maxLines: 1)
                                    }
                                }
                            }
                            if let trailing { trailing }
                        }))
            },
            onPressed: onTap)
    }

    private func _qsTextButton(_ label: String, onTap: @escaping () -> Void) -> Widget {
        HoverButton(
            builder: { [self] _, states in
                let hot = states.isHovered || states.isPressed
                return Padding(
                    padding: EdgeInsets(left: FluentSpacing.xs, top: 2, right: FluentSpacing.xs, bottom: 2),
                    child: Text(label, style: fluentType.styled(
                        { $0.caption }, hot ? shellTheme.fgPrimary : shellTheme.accent)))
            },
            onPressed: onTap)
    }

    /// The password prompt. The shell's key router feeds `_wifiPassword`
    /// while the `.wifi` popup shows this, exactly as for the macOS panel.
    private func _qsWifiPassword(ssid: String) -> Widget {
        let dots = String(repeating: "\u{2022}", count: _wifiPassword.count)
        return Column(crossAxisAlignment: .stretch, spacing: FluentSpacing.m) {
            Row(crossAxisAlignment: .center) {
                _qsIconButton(FluentSystemIcons.back) { [self] in
                    setState { _wifiPasswordSSID = nil; _wifiPassword = "" }
                }
                SizedBox(width: FluentSpacing.s)
                Expanded { Text(ssid, style: fluentType.styled({ $0.bodyStrong }, shellTheme.fgPrimary, strong: true),
                                overflow: .ellipsis, maxLines: 1) }
            }
            Text("Enter the network security key", style: fluentType.styled({ $0.body }, shellTheme.fgSecondary))
            DecoratedBox(
                decoration: BoxDecoration(
                    color: shellTheme.controlFill,
                    border: Border.all(color: shellTheme.controlStroke, width: FluentStrokeWidth.thin),
                    borderRadius: FluentCorners.controlRadius),
                child: SizedBox(
                    height: FluentSpacing.controlHeight,
                    child: Padding(
                        padding: EdgeInsets(left: FluentSpacing.m, top: 0, right: FluentSpacing.m, bottom: 0),
                        child: Row(crossAxisAlignment: .center) {
                            Text(dots.isEmpty ? "Password" : dots,
                                 style: fluentType.styled({ $0.body },
                                                          dots.isEmpty ? shellTheme.fgTertiary : shellTheme.fgPrimary),
                                 overflow: .ellipsis, maxLines: 1)
                            ShellCaret(color: shellTheme.fgPrimary, fontSize: 13,
                                       fontFamily: shellTheme.fontFamily, resetToken: _wifiCaretToken)
                        })))
            if let err = _wifiError {
                Text(err, style: fluentType.styled({ $0.caption }, fluentThemeData().resources.systemFillColorCritical))
            }
            Row(mainAxisAlignment: .end, spacing: FluentSpacing.s) {
                Button(onPressed: { [self] in
                    setState { _wifiPasswordSSID = nil; _wifiPassword = "" }
                }, child: Text("Cancel"))
                FilledButton(onPressed: { [self] in
                    _wifiJoin(ssid: ssid, security: _wifiPasswordSecurity, password: _wifiPassword)
                }, child: Text("Connect"))
            }
        }
    }
}
