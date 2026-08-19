// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The Settings app: the Windows settings people actually reach for, in
// Starling's own surface rather than a link into Windows' own.
//
// Deliberately a SHORT list. Windows' Settings has hundreds of pages and
// almost all of the traffic goes to a handful: what this machine is, the
// display, the sound, how it looks, and how full the disk is. A shell that
// reimplements the long tail badly is worse than one that reimplements the
// head well and leaves the rest to Windows.
//
// The rule from the dock applies to what goes IN: only settings backed by a
// documented Windows API, and nothing shown for hardware that is not there.
// Anything Windows has no public API for — the default audio device, night
// light — is absent rather than faked.
//
// An ORDINARY WINDOW, not a panel or an overlay: it is an app, it belongs in
// Alt+Tab, and the user should be able to move and close it like anything
// else. That also puts it on the input path that works — a GestureDetector
// inside a normal Column/Row fires here, which is not true inside a
// `Positioned` in a `Stack` (see the dock's menus).

#if os(Windows)
import CupertinoIcons
import Flutter
import FlutterSwiftBridge
import FlutterWin32
import FlutterWin32Bridge
import Foundation
import Observation

let kSettingsSidebar = 208.0

final class StarlingSettings: StatefulWidget {
    override func createState() -> State<StatefulWidget> { StarlingSettingsState() }
}

final class StarlingSettingsState: State<StatefulWidget> {
    private let bloc = settingsBloc

    override func initState() {
        super.initState()
        CupertinoIcons.registerFont()
        bloc.add(.start)
    }

    override func build(_ context: any BuildContext) -> Widget {
        withObservationTracking {
            _buildContent()
        } onChange: { [weak self] in
            guard let self, self.mounted else { return }
            self.setState {}
        }
    }

    private func _buildContent() -> Widget {
        Directionality(
            textDirection: .ltr,
            child: ColoredBox(color: Color(0xFF1B1D22)) {
                Row(crossAxisAlignment: .stretch) {
                    sidebar()
                    Expanded { pane() }
                }
            })
    }

    // MARK: - Sidebar

    private func sidebar() -> Widget {
        SizedBox(width: kSettingsSidebar) {
            ColoredBox(color: Color(0xFF16181C)) {
                Padding(padding: EdgeInsets(left: 8, top: 14, right: 8, bottom: 8)) {
                    Column(crossAxisAlignment: .stretch) {
                        Padding(padding: EdgeInsets(left: 10, top: 0, right: 10, bottom: 14)) {
                            Text("Settings",
                                 style: TextStyle(color: Color(0xFFF2F5FA),
                                                  fontSize: 20, fontWeight: .w600))
                        }
                        for item in SettingsPane.allCases { sidebarRow(item) }
                    }
                }
            }
        }
    }

    private func sidebarRow(_ item: SettingsPane) -> Widget {
        let selected = bloc.state.pane == item
        return GestureDetector(
            onTap: { self.bloc.add(.show(item)) },
            child: Padding(padding: EdgeInsets(left: 0, top: 1, right: 0, bottom: 1)) {
                ClipRRect(borderRadius: BorderRadius.circular(7)) {
                    ColoredBox(color: selected ? Color(0x2E6FA8FF) : Color(0x00000000)) {
                        SizedBox(height: 36) {
                            Padding(padding: EdgeInsets(horizontal: 8, vertical: 0)) {
                                Row(crossAxisAlignment: .center, spacing: 10) {
                                    ClipRRect(borderRadius: BorderRadius.circular(6)) {
                                        ColoredBox(color: item.tint) {
                                            SizedBox(width: 22, height: 22) {
                                                Center {
                                                    MacosIcon(icon: item.icon,
                                                              color: Color(0xFFFFFFFF),
                                                              size: 13)
                                                }
                                            }
                                        }
                                    }
                                    Text(item.title,
                                         style: TextStyle(color: Color(0xFFE6EAF0),
                                                          fontSize: 13))
                                }
                            }
                        }
                    }
                }
            })
    }

    // MARK: - Panes

    private func pane() -> Widget {
        Padding(padding: EdgeInsets(left: 26, top: 22, right: 26, bottom: 22)) {
            Column(crossAxisAlignment: .stretch) {
                Text(bloc.state.pane.title,
                     style: TextStyle(color: Color(0xFFF2F5FA), fontSize: 24,
                                      fontWeight: .w600))
                SizedBox(height: 18)
                if let notice = bloc.state.notice { noticeRow(notice) }
                switch bloc.state.pane {
                case .system: systemPane()
                case .display: displayPane()
                case .sound: soundPane()
                case .personalisation: personalisationPane()
                case .storage: storagePane()
                }
            }
        }
    }

    private func noticeRow(_ text: String) -> Widget {
        Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 14)) {
            ClipRRect(borderRadius: BorderRadius.circular(8)) {
                ColoredBox(color: Color(0x33F0B24A)) {
                    Padding(padding: EdgeInsets(horizontal: 12, vertical: 9)) {
                        Text(text, style: TextStyle(color: Color(0xFFF6E3C0),
                                                    fontSize: 13))
                    }
                }
            }
        }
    }

    // MARK: System

    private func systemPane() -> Widget {
        guard let m = bloc.state.machine else { return loading() }
        return card {
            Column(crossAxisAlignment: .stretch) {
                infoRow("Device name", m.deviceName)
                infoRow("Edition", m.osName)
                infoRow("OS build", m.osBuild)
                infoRow("Processor", "\(m.cpuName)  (\(m.cpuCores) threads)")
                infoRow("Memory", "\(gigabytes(m.totalRam)) installed, "
                                  + "\(gigabytes(m.availableRam)) available")
                infoRow("Graphics", m.gpuName)
                infoRow("Power plan", m.powerScheme)
            }
        }
    }

    // MARK: Display

    private func displayPane() -> Widget {
        Column(crossAxisAlignment: .stretch) {
            if let brightness = bloc.state.brightness {
                card {
                    Column(crossAxisAlignment: .stretch) {
                        label("Brightness")
                        SizedBox(height: 8)
                        slider(percent: Double(brightness),
                               fill: Color(0xFFE8B84B)) { self.bloc.add(.setBrightness($0)) }
                    }
                }
                SizedBox(height: 14)
            }
            card {
                Column(crossAxisAlignment: .stretch) {
                    label("Resolution")
                    SizedBox(height: 4)
                    // The adapter's list, deduplicated. Changing one restarts
                    // the display pipeline, so each is a deliberate tap rather
                    // than anything that happens on hover or drag.
                    for mode in bloc.state.modes.prefix(12) { modeRow(mode) }
                }
            }
        }
    }

    private func modeRow(_ mode: Win32DisplayMode) -> Widget {
        // Width, height AND refresh. Comparing only the size marks every
        // refresh rate of the current resolution as selected — five filled
        // radios in a row that is supposed to have one.
        let selected = bloc.state.currentMode == mode
        return GestureDetector(
            onTap: { self.bloc.add(.setDisplayMode(mode)) },
            child: SizedBox(height: 32) {
                Row(crossAxisAlignment: .center, spacing: 10) {
                    MacosIcon(icon: selected ? CupertinoIcons.largecircle_fill_circle
                                             : CupertinoIcons.circle,
                              color: selected ? Color(0xFF4C8DF6) : Color(0xFF6E7683),
                              size: 15)
                    Text("\(mode.label)   ·   \(mode.refresh) Hz",
                         style: TextStyle(color: Color(0xFFE6EAF0), fontSize: 13))
                }
            })
    }

    // MARK: Sound

    private func soundPane() -> Widget {
        guard let volume = bloc.state.volume else {
            return card {
                Text("No audio output device.",
                     style: TextStyle(color: Color(0xFF9AA3B0), fontSize: 13))
            }
        }
        return card {
            Column(crossAxisAlignment: .stretch) {
                label("Volume")
                SizedBox(height: 8)
                slider(percent: Double(volume.percent),
                       fill: Color(0xFF4C8DF6)) { self.bloc.add(.setVolume($0)) }
                SizedBox(height: 14)
                toggleRow("Mute", on: volume.isMuted) { self.bloc.add(.toggleMute) }
            }
        }
    }

    // MARK: Personalisation

    private func personalisationPane() -> Widget {
        card {
            Column(crossAxisAlignment: .stretch) {
                toggleRow("Dark mode", on: bloc.state.darkMode) {
                    self.bloc.add(.toggleDarkMode)
                }
                SizedBox(height: 16)
                label("Wallpaper")
                SizedBox(height: 6)
                Text(shortPath(bloc.state.wallpaper),
                     style: TextStyle(color: Color(0xFF9AA3B0), fontSize: 12),
                     maxLines: 1)
                SizedBox(height: 10)
                button("Choose a picture…") { self.bloc.add(.pickWallpaper) }
            }
        }
    }

    // MARK: Storage

    private func storagePane() -> Widget {
        guard !bloc.state.drives.isEmpty else { return loading() }
        return card {
            Column(crossAxisAlignment: .stretch) {
                for drive in bloc.state.drives {
                    Padding(padding: EdgeInsets(left: 0, top: 6, right: 0, bottom: 14)) {
                        Column(crossAxisAlignment: .stretch) {
                            Row(crossAxisAlignment: .center) {
                                Text("Drive \(drive.letter):",
                                     style: TextStyle(color: Color(0xFFE6EAF0),
                                                      fontSize: 13, fontWeight: .w600))
                                Expanded { SizedBox(height: 1) }
                                Text("\(gigabytes(drive.free)) free of \(gigabytes(drive.total))",
                                     style: TextStyle(color: Color(0xFF9AA3B0),
                                                      fontSize: 12))
                            }
                            SizedBox(height: 8)
                            bar(fraction: drive.usedFraction)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Pieces

    private func loading() -> Widget {
        Column(crossAxisAlignment: .center) {
            SizedBox(height: 40)
            SizedBox(width: 240) { MacosProgressIndicator() }
            SizedBox(height: 14)
            Text("Reading the machine",
                 style: TextStyle(color: Color(0xFF6E7683), fontSize: 13))
        }
    }

    private func card(_ body: () -> Widget) -> Widget {
        ClipRRect(borderRadius: BorderRadius.circular(10)) {
            ColoredBox(color: Color(0xFF23262C)) {
                Padding(padding: EdgeInsets(horizontal: 16, vertical: 14)) {
                    body()
                }
            }
        }
    }

    private func label(_ text: String) -> Widget {
        Text(text, style: TextStyle(color: Color(0xFFE6EAF0), fontSize: 13,
                                    fontWeight: .w600))
    }

    private func infoRow(_ name: String, _ value: String) -> Widget {
        SizedBox(height: 30) {
            Row(crossAxisAlignment: .center) {
                SizedBox(width: 150) {
                    Text(name, style: TextStyle(color: Color(0xFF9AA3B0), fontSize: 13))
                }
                Expanded {
                    Text(value.isEmpty ? "—" : value,
                         style: TextStyle(color: Color(0xFFE6EAF0), fontSize: 13),
                         maxLines: 1)
                }
            }
        }
    }

    private func toggleRow(_ text: String, on: Bool, _ action: @escaping () -> Void)
        -> Widget {
        GestureDetector(
            onTap: action,
            child: SizedBox(height: 30) {
                Row(crossAxisAlignment: .center, spacing: 10) {
                    ClipRRect(borderRadius: BorderRadius.circular(10)) {
                        ColoredBox(color: on ? Color(0xFF4C8DF6) : Color(0x33FFFFFF)) {
                            SizedBox(width: 38, height: 20) {
                                Align(alignment: on ? Alignment.centerRight
                                                    : Alignment.centerLeft) {
                                    Padding(padding: EdgeInsets(horizontal: 3, vertical: 0)) {
                                        ClipRRect(borderRadius: BorderRadius.circular(7)) {
                                            ColoredBox(color: Color(0xFFF2F5FA)) {
                                                SizedBox(width: 14, height: 14)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Text(text, style: TextStyle(color: Color(0xFFE6EAF0), fontSize: 13))
                }
            })
    }

    private func button(_ text: String, _ action: @escaping () -> Void) -> Widget {
        GestureDetector(
            onTap: action,
            child: ClipRRect(borderRadius: BorderRadius.circular(7)) {
                ColoredBox(color: Color(0x1AFFFFFF)) {
                    SizedBox(height: 32) {
                        Padding(padding: EdgeInsets(horizontal: 14, vertical: 0)) {
                            Center {
                                Text(text, style: TextStyle(color: Color(0xFFE6EAF0),
                                                            fontSize: 13))
                            }
                        }
                    }
                }
            })
    }

    /// A drawn slider, for the same reason the control centre draws its own:
    /// a pan recognizer is not something to rely on in this framework, and a
    /// row of taps along a track is honest and reliable.
    private func slider(percent: Double, fill: Color,
                        _ action: @escaping (Int) -> Void) -> Widget {
        SizedBox(height: 22) {
            Row(crossAxisAlignment: .center) {
                for step in 0..<20 {
                    Expanded {
                        GestureDetector(
                            onTap: { action((step + 1) * 5) },
                            child: Padding(padding: EdgeInsets(horizontal: 1, vertical: 0)) {
                                ClipRRect(borderRadius: BorderRadius.circular(2)) {
                                    ColoredBox(color: Double(step + 1) * 5 <= percent
                                                   ? fill : Color(0x33FFFFFF)) {
                                        SizedBox(height: 8)
                                    }
                                }
                            })
                    }
                }
            }
        }
    }

    private func bar(fraction: Double) -> Widget {
        SizedBox(height: 8) {
            Row(crossAxisAlignment: .stretch) {
                for step in 0..<40 {
                    Expanded {
                        Padding(padding: EdgeInsets(horizontal: 0.5, vertical: 0)) {
                            ColoredBox(color: Double(step) / 40 < fraction
                                           ? Color(0xFF4C8DF6) : Color(0x22FFFFFF)) {
                                SizedBox(height: 8)
                            }
                        }
                    }
                }
            }
        }
    }

    private func gigabytes(_ bytes: Int64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }

    /// The last two components. A wallpaper path is routinely 140 characters
    /// of Windows Spotlight cache and says nothing useful in full.
    private func shortPath(_ path: String) -> String {
        guard !path.isEmpty else { return "None" }
        let parts = path.split(separator: "\\")
        return parts.count <= 2 ? path : "…\\" + parts.suffix(2).joined(separator: "\\")
    }
}
#endif
