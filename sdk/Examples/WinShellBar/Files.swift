// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The file explorer.
//
// An ordinary window, like Settings, and for the same reasons: it is an app,
// and a normal Column/Row is the input path that works in this framework.
//
// Deliberately modest. Windows' Explorer has ribbons, a preview pane, forty
// context-menu verbs and the whole shell namespace; this browses the file
// system and opens things, and hands the folder to Explorer when the user
// wants the rest. Doing that well is worth more than a bad imitation of the
// long tail — the same line the Settings app draws.

#if os(Windows)
import CupertinoIcons
import Flutter
import FlutterSwiftBridge
import FlutterWin32
import FlutterWin32Bridge
import Foundation
import Observation

let kFilesSidebar = 200.0
let kFilesRow = 30.0

final class StarlingFiles: StatefulWidget {
    override func createState() -> State<StatefulWidget> { StarlingFilesState() }
}

final class StarlingFilesState: State<StatefulWidget> {
    private let bloc = filesBloc

    /// Double-click, by hand.
    ///
    /// `onDoubleTap` is not usable here — registering it kills the plain tap
    /// as well on at least one embedder, and this framework's gesture arena
    /// is not something to rely on. So: a tap selects, and a second tap on
    /// the same row within the interval opens. Windows' own behaviour, out of
    /// two ordinary taps.
    private var lastTapPath: String?
    private var lastTapAt = Date.distantPast

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
                    Expanded {
                        Column(crossAxisAlignment: .stretch) {
                            toolbar()
                            Expanded { listing() }
                        }
                    }
                }
            })
    }

    // MARK: - Sidebar

    private func sidebar() -> Widget {
        SizedBox(width: kFilesSidebar) {
            ColoredBox(color: Color(0xFF16181C)) {
                Padding(padding: EdgeInsets(left: 8, top: 12, right: 8, bottom: 8)) {
                    Column(crossAxisAlignment: .stretch) {
                        sidebarHeading("Places")
                        for place in bloc.state.places { placeRow(place) }
                        SizedBox(height: 12)
                        sidebarHeading("Drives")
                        for drive in bloc.state.drives { placeRow(drive) }
                    }
                }
            }
        }
    }

    private func sidebarHeading(_ text: String) -> Widget {
        Padding(padding: EdgeInsets(left: 10, top: 0, right: 10, bottom: 6)) {
            Text(text, style: TextStyle(color: Color(0xFF6E7683), fontSize: 11,
                                        fontWeight: .w600))
        }
    }

    private func placeRow(_ place: Win32Place) -> Widget {
        let selected = bloc.state.directory == place.path
        return GestureDetector(
            onTap: { self.bloc.add(.open(place.path)) },
            child: Padding(padding: EdgeInsets(left: 0, top: 1, right: 0, bottom: 1)) {
                ClipRRect(borderRadius: BorderRadius.circular(6)) {
                    ColoredBox(color: selected ? Color(0x2E6FA8FF) : Color(0x00000000)) {
                        SizedBox(height: 30) {
                            Padding(padding: EdgeInsets(horizontal: 10, vertical: 0)) {
                                Row(crossAxisAlignment: .center, spacing: 9) {
                                    MacosIcon(icon: CupertinoIcons.folder_fill,
                                              color: Color(0xFF7FA9DE), size: 14)
                                    Text(place.name,
                                         style: TextStyle(color: Color(0xFFE6EAF0),
                                                          fontSize: 13),
                                         maxLines: 1)
                                }
                            }
                        }
                    }
                }
            })
    }

    // MARK: - Toolbar

    private func toolbar() -> Widget {
        SizedBox(height: 46) {
            Padding(padding: EdgeInsets(left: 14, top: 0, right: 14, bottom: 0)) {
                Row(crossAxisAlignment: .center, spacing: 8) {
                    toolButton(CupertinoIcons.chevron_left) { self.bloc.add(.goBack) }
                    toolButton(CupertinoIcons.chevron_up) { self.bloc.add(.goUp) }
                    toolButton(CupertinoIcons.arrow_clockwise) { self.bloc.add(.refresh) }
                    Expanded {
                        Padding(padding: EdgeInsets(horizontal: 6, vertical: 0)) {
                            ClipRRect(borderRadius: BorderRadius.circular(6)) {
                                ColoredBox(color: Color(0xFF23262C)) {
                                    SizedBox(height: 28) {
                                        Padding(padding: EdgeInsets(horizontal: 10, vertical: 0)) {
                                            Align(alignment: Alignment.centerLeft) {
                                                Text(bloc.state.directory,
                                                     style: TextStyle(color: Color(0xFFB0B7C3),
                                                                      fontSize: 12),
                                                     maxLines: 1)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    textButton("Open in Explorer") { self.bloc.add(.openInExplorer) }
                }
            }
        }
    }

    private func toolButton(_ icon: IconData, _ action: @escaping () -> Void) -> Widget {
        GestureDetector(
            onTap: action,
            child: ClipRRect(borderRadius: BorderRadius.circular(6)) {
                ColoredBox(color: Color(0x1AFFFFFF)) {
                    SizedBox(width: 30, height: 28) {
                        Center { MacosIcon(icon: icon, color: Color(0xFFD5DAE3), size: 14) }
                    }
                }
            })
    }

    private func textButton(_ text: String, _ action: @escaping () -> Void) -> Widget {
        GestureDetector(
            onTap: action,
            child: ClipRRect(borderRadius: BorderRadius.circular(6)) {
                ColoredBox(color: Color(0x1AFFFFFF)) {
                    SizedBox(height: 28) {
                        Padding(padding: EdgeInsets(horizontal: 12, vertical: 0)) {
                            Center {
                                Text(text, style: TextStyle(color: Color(0xFFD5DAE3),
                                                            fontSize: 12))
                            }
                        }
                    }
                }
            })
    }

    // MARK: - Listing

    private func listing() -> Widget {
        if let error = bloc.state.error { return message(error) }
        if bloc.state.loading && bloc.state.entries.isEmpty {
            return Column(mainAxisAlignment: .center, crossAxisAlignment: .center) {
                SizedBox(width: 240) { MacosProgressIndicator() }
                SizedBox(height: 12)
                Text("Reading the folder",
                     style: TextStyle(color: Color(0xFF6E7683), fontSize: 13))
            }
        }
        if bloc.state.entries.isEmpty { return message("This folder is empty.") }

        // Lazy: a folder of ten thousand files builds only the rows on screen.
        return ListView(
            itemExtent: kFilesRow,
            itemCount: bloc.state.entries.count,
            itemBuilder: { [weak self] _, index in self?.row(index) })
    }

    private func message(_ text: String) -> Widget {
        Column(mainAxisAlignment: .center, crossAxisAlignment: .center) {
            Text(text, style: TextStyle(color: Color(0xFF6E7683), fontSize: 13))
        }
    }

    private func row(_ index: Int) -> Widget {
        guard index < bloc.state.entries.count else { return SizedBox(height: kFilesRow) }
        let entry = bloc.state.entries[index]
        let selected = bloc.state.selected == entry.path
        let key = FilesBloc.iconKey(entry)

        return GestureDetector(
            onTap: { self.tapped(entry) },
            child: ColoredBox(color: selected ? Color(0x2E6FA8FF) : Color(0x00000000)) {
                SizedBox(height: kFilesRow) {
                    Padding(padding: EdgeInsets(left: 16, top: 0, right: 16, bottom: 0)) {
                        Row(crossAxisAlignment: .center, spacing: 10) {
                            SizedBox(width: 18, height: 18) {
                                Center {
                                    if let icon = bloc.icons.view(key, side: 16) {
                                        icon
                                    } else {
                                        MacosIcon(icon: entry.isDirectory
                                                      ? CupertinoIcons.folder_fill
                                                      : CupertinoIcons.doc,
                                                  color: Color(0xFF8B93A1), size: 14)
                                    }
                                }
                            }
                            Expanded {
                                Text(entry.name,
                                     style: TextStyle(color: Color(0xFFE6EAF0), fontSize: 13),
                                     maxLines: 1)
                            }
                            SizedBox(width: 150) {
                                Align(alignment: Alignment.centerRight) {
                                    Text(modifiedText(entry),
                                         style: TextStyle(color: Color(0xFF8B93A1),
                                                          fontSize: 12),
                                         maxLines: 1)
                                }
                            }
                            SizedBox(width: 90) {
                                Align(alignment: Alignment.centerRight) {
                                    Text(entry.isDirectory ? "" : sizeText(entry.size),
                                         style: TextStyle(color: Color(0xFF8B93A1),
                                                          fontSize: 12),
                                         maxLines: 1)
                                }
                            }
                        }
                    }
                }
            })
    }

    /// Select on the first tap, open on a second within half a second. See
    /// `lastTapPath` for why this is not `onDoubleTap`.
    private func tapped(_ entry: Win32FileEntry) {
        let now = Date()
        let again = lastTapPath == entry.path
            && now.timeIntervalSince(lastTapAt) < 0.5
        lastTapPath = entry.path
        lastTapAt = now
        if again {
            lastTapPath = nil
            bloc.add(.activate(entry))
        } else {
            bloc.add(.select(entry.path))
        }
    }

    private func sizeText(_ bytes: Int64) -> String {
        if bytes >= 1_073_741_824 {
            return String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
        }
        if bytes >= 1_048_576 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576)
        }
        if bytes >= 1024 { return "\(bytes / 1024) KB" }
        return "\(bytes) B"
    }

    private func modifiedText(_ entry: Win32FileEntry) -> String {
        guard let date = entry.modified else { return "" }
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy  HH:mm"
        return f.string(from: date)
    }
}
#endif
