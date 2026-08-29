// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Task Manager — an Activity-Monitor-style system monitor as a FlutterSwift
// app: live CPU / memory / disk / network overview tiles with sparklines, and
// a sortable table of running processes with select-and-terminate. All data
// comes from /proc (SystemStats.swift); startPeriodicTimer dispatches .tick
// to the BLoC once a second on whichever loop the host runs the UI on.
//
// Host-neutral (runStarlingApp): the shell spawns it as a DMA-BUF child; a
// GTK-linked build of the same sources runs it windowed.

#if os(Linux)
import CupertinoIcons
import Flutter
import FlutterSwiftBridge
import Foundation
import Observation

let taskManagerBloc = TaskManagerBloc()

// MARK: - Palette and table metrics

private enum Style {
    /// Follows the shell's appearance — flipped by ThemedTaskManagerRoot
    /// before the rebuild, so every var below reads the right side.
    nonisolated(unsafe) static var dark = false

    static let accent = Color(0xFF007AFF)
    static var body: Color { dark ? Color(0xDDFFFFFF) : Color(0xDD000000) }
    static var dim: Color { dark ? Color(0x8AFFFFFF) : Color(0x8A000000) }
    static var faint: Color { dark ? Color(0x61FFFFFF) : Color(0x61000000) }
    static var cardBorder: Color { dark ? Color(0x26FFFFFF) : Color(0x1F000000) }
    static var card: Color { dark ? Color(0xFF232326) : Color(0xFFFFFFFF) }
    static var chrome: Color { dark ? Color(0xFF2A2A2D) : Color(0xFFF5F5F5) }
    static var stripe: Color { dark ? Color(0x0AFFFFFF) : Color(0x05000000) }
    static var divider: Color { dark ? Color(0x1FFFFFFF) : Color(0x14000000) }

    static let cpuSeries = Color(0xFF2E7CF6)
    static let memorySeries = Color(0xFF34A853)
    static let readSeries = Color(0xB32E7CF6)     // translucent so overlap shows
    static let writeSeries = Color(0xB3E5533A)
    static let downSeries = Color(0xB334A853)
    static let upSeries = Color(0xB3F0A202)
}

private enum Columns {
    static let pid: Double = 64
    static let cpu: Double = 72
    static let threads: Double = 64
    static let memory: Double = 92
    static let rowHeight: Double = 24
}

// MARK: - Sparkline

private struct SparkSeries {
    let values: [Double]
    let color: Color
}

/// The overview tiles' history graph: one thin bar per sample, newest at the
/// right edge, all series sharing one scale (the drawRect-bars approach of
/// FlutterDemoApp's frame-time graph).
private class SparklinePainter: CustomPainter {
    let series: [SparkSeries]
    /// Fixed top of the scale; nil auto-scales to the series' maximum.
    let maxValue: Double?
    let capacity: Int

    init(series: [SparkSeries], maxValue: Double? = nil,
         capacity: Int = TaskManagerBloc.historyLength) {
        self.series = series
        self.maxValue = maxValue
        self.capacity = capacity
        super.init()
    }

    override func paint(_ canvas: Canvas, _ size: Size) {
        let paint = Paint()
        paint.color = Style.divider
        canvas.drawRect(Rect.fromLTRB(0, size.height - 1, size.width, size.height), paint)

        var top = maxValue ?? series.flatMap { $0.values }.max() ?? 1
        if top <= 0 { top = 1 }
        let slot = size.width / Double(capacity)
        let barWidth = Swift.max(slot - 1, 1)

        for s in series {
            paint.color = s.color
            for (i, value) in s.values.enumerated() {
                let x = size.width - Double(s.values.count - i) * slot
                let h = Swift.min(Swift.max(value / top, 0), 1) * (size.height - 1)
                guard h >= 0.5 else { continue }
                canvas.drawRect(
                    Rect.fromLTRB(x, size.height - 1 - h, x + barWidth, size.height - 1),
                    paint
                )
            }
        }
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        return true  // fresh values every tick
    }
}

// MARK: - Overview tile

/// One stat card: caption, headline value, sparkline, footnote.
private class StatTile: StatelessWidget {
    let title: String
    let value: String
    let detail: String
    let series: [SparkSeries]
    let maxValue: Double?

    init(title: String, value: String, detail: String,
         series: [SparkSeries], maxValue: Double? = nil) {
        self.title = title
        self.value = value
        self.detail = detail
        self.series = series
        self.maxValue = maxValue
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        return DecoratedBox(
            decoration: BoxDecoration(
                color: Style.card,
                border: Border.all(color: Style.cardBorder),
                borderRadius: BorderRadius.all(Radius(circular: 6))
            )
        ) {
            Padding(padding: EdgeInsets(horizontal: 12, vertical: 10)) {
                Column(crossAxisAlignment: .stretch) {
                    Text(title, style: TextStyle(
                        color: Style.dim, fontSize: 11, fontWeight: .w600))
                    SizedBox(width: 1, height: 3)
                    Text(value, style: TextStyle(
                        color: Style.body, fontSize: 16, fontWeight: .w600), maxLines: 1)
                    SizedBox(width: 1, height: 8)
                    SizedBox(
                        height: 32,
                        child: CustomPaint(painter: SparklinePainter(
                            series: series, maxValue: maxValue))
                    )
                    SizedBox(width: 1, height: 6)
                    Text(detail, style: TextStyle(
                        color: Style.faint, fontSize: 11), maxLines: 1)
                }
            }
        }
    }
}

// MARK: - Page

class TaskManagerPage: StatefulWidget {
    override func createState() -> State<StatefulWidget> {
        return _TaskManagerPageState()
    }
}

class _TaskManagerPageState: State<StatefulWidget> {

    override func build(_ context: any BuildContext) -> Widget {
        return withObservationTracking {
            _buildContent()
        } onChange: { [weak self] in
            guard let self, self.mounted else { return }
            self.setState {}
        }
    }

    private func _buildContent() -> Widget {
        let s = taskManagerBloc.state
        let content = Column(crossAxisAlignment: .stretch) {
            _buildOverview(s)
            _buildTableHeader(s)
            _divider()
            Expanded {
                // Lazy rows: only the visible slice of a few-hundred-row
                // table is built each tick. itemExtent skips per-row
                // intrinsic sizing — every row is Columns.rowHeight tall.
                ListView(
                    itemExtent: Columns.rowHeight,
                    itemCount: s.processes.count,
                    itemBuilder: { [weak self] _, index in self?._buildRow(s, index) }
                )
            }
            _divider()
            _buildFooter(s)
        }
        return MacosScaffold(
            children: [content],
            toolBar: MacosToolBar(
                title: Text("Task Manager"),
                actions: [
                    PushButton(
                        child: Text("End Process"),
                        onPressed: s.selectedPid != nil
                            ? { taskManagerBloc.add(.terminateSelected) }
                            : nil,
                        secondary: true
                    )
                ]
            )
        )
    }

    // MARK: Overview strip

    private func _buildOverview(_ s: TaskManagerState) -> Widget {
        let snapshot = s.snapshot
        // No .stretch here: the tiles share one intrinsic height (identical
        // structure), and stretch under an unbounded cross axis blows the
        // cards up to cover everything below.
        return Padding(padding: EdgeInsets(left: 12, top: 12, right: 12, bottom: 12)) {
            Row(crossAxisAlignment: .start) {
                Expanded {
                    StatTile(
                        title: "CPU",
                        value: String(format: "%.1f%%", snapshot.cpuPercent),
                        detail: String(format: "%d cores · load %.2f",
                                       snapshot.coreCount, snapshot.loadAverage[0]),
                        series: [SparkSeries(values: s.cpuHistory, color: Style.cpuSeries)],
                        maxValue: 100
                    )
                }
                SizedBox(width: 8, height: 1)
                Expanded {
                    StatTile(
                        title: "MEMORY",
                        value: "\(formatBytes(snapshot.memUsed)) of \(formatBytes(snapshot.memTotal))",
                        detail: snapshot.swapTotal > 0
                            ? "swap \(formatBytes(snapshot.swapUsed)) of \(formatBytes(snapshot.swapTotal))"
                            : "no swap",
                        series: [SparkSeries(values: s.memoryHistory, color: Style.memorySeries)],
                        maxValue: 1
                    )
                }
                SizedBox(width: 8, height: 1)
                Expanded {
                    StatTile(
                        title: "DISK",
                        value: formatRate(snapshot.diskReadPerSec + snapshot.diskWritePerSec),
                        detail: "R \(formatRate(snapshot.diskReadPerSec))"
                            + " · W \(formatRate(snapshot.diskWritePerSec))",
                        series: [
                            SparkSeries(values: s.diskReadHistory, color: Style.readSeries),
                            SparkSeries(values: s.diskWriteHistory, color: Style.writeSeries),
                        ]
                    )
                }
                SizedBox(width: 8, height: 1)
                Expanded {
                    StatTile(
                        title: "NETWORK",
                        value: formatRate(snapshot.netRxPerSec + snapshot.netTxPerSec),
                        detail: "↓ \(formatRate(snapshot.netRxPerSec))"
                            + " · ↑ \(formatRate(snapshot.netTxPerSec))",
                        series: [
                            SparkSeries(values: s.netRxHistory, color: Style.downSeries),
                            SparkSeries(values: s.netTxHistory, color: Style.upSeries),
                        ]
                    )
                }
            }
        }
    }

    // MARK: Process table

    private func _headerCell(
        _ s: TaskManagerState, _ label: String, _ column: SortColumn, numeric: Bool
    ) -> Widget {
        let active = s.sortColumn == column
        let title = active ? "\(label) \(s.sortDescending ? "▼" : "▲")" : label
        return GestureDetector(
            onTap: { taskManagerBloc.add(.sortBy(column)) },
            behavior: .opaque,
            child: Align(
                alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
                child: Text(title, style: TextStyle(
                    color: active ? Style.accent : Style.dim,
                    fontSize: 11, fontWeight: .w600), maxLines: 1)
            )
        )
    }

    private func _buildTableHeader(_ s: TaskManagerState) -> Widget {
        return SizedBox(height: 26) {
            ColoredBox(color: Style.chrome) {
                Padding(padding: EdgeInsets(horizontal: 12)) {
                    Row {
                        Expanded { _headerCell(s, "Process Name", .name, numeric: false) }
                        SizedBox(width: Columns.pid,
                                 child: _headerCell(s, "PID", .pid, numeric: true))
                        SizedBox(width: Columns.cpu,
                                 child: _headerCell(s, "CPU %", .cpu, numeric: true))
                        SizedBox(width: Columns.threads,
                                 child: _headerCell(s, "Threads", .threads, numeric: true))
                        SizedBox(width: Columns.memory,
                                 child: _headerCell(s, "Memory", .memory, numeric: true))
                    }
                }
            }
        }
    }

    private func _cell(_ text: String, width: Double, color: Color) -> Widget {
        return SizedBox(
            width: width,
            child: Align(
                alignment: Alignment.centerRight,
                child: Text(text, style: TextStyle(color: color, fontSize: 12),
                            maxLines: 1)
            )
        )
    }

    private func _buildRow(_ s: TaskManagerState, _ index: Int) -> Widget? {
        guard index < s.processes.count else { return nil }
        let process = s.processes[index]
        let selected = s.selectedPid == process.pid
        let body = selected ? Color(0xFFFFFFFF) : Style.body
        let dim = selected ? Color(0xB3FFFFFF) : Style.dim
        let background = selected
            ? Style.accent
            : (index % 2 == 1 ? Style.stripe : Color(0x00000000))

        // A zombie stays visible but is clearly marked.
        let name = process.state == "Z" ? "\(process.name) (zombie)" : process.name

        return GestureDetector(
            onTap: { taskManagerBloc.add(.select(pid: process.pid)) },
            behavior: .opaque,
            child: SizedBox(height: Columns.rowHeight) {
                ColoredBox(color: background) {
                    Padding(padding: EdgeInsets(horizontal: 12)) {
                        Row {
                            Expanded {
                                Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(name, style: TextStyle(
                                        color: process.state == "Z" ? dim : body,
                                        fontSize: 12), maxLines: 1)
                                )
                            }
                            _cell("\(process.pid)", width: Columns.pid, color: dim)
                            _cell(String(format: "%.1f", process.cpuPercent),
                                  width: Columns.cpu, color: body)
                            _cell("\(process.threads)", width: Columns.threads, color: dim)
                            _cell(process.memoryBytes > 0 ? formatBytes(process.memoryBytes) : "–",
                                  width: Columns.memory, color: body)
                        }
                    }
                }
            }
        )
    }

    // MARK: Footer

    private func _divider() -> Widget {
        return SizedBox(width: 1, height: 1) {
            DecoratedBox(decoration: BoxDecoration(color: Style.divider))
        }
    }

    private func _formatUptime(_ seconds: Double) -> String {
        let total = Int(seconds)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "up \(days)d \(hours)h" }
        if hours > 0 { return "up \(hours)h \(minutes)m" }
        return "up \(minutes)m"
    }

    private func _buildFooter(_ s: TaskManagerState) -> Widget {
        return SizedBox(height: 30) {
            ColoredBox(color: Style.chrome) {
                Padding(padding: EdgeInsets(horizontal: 12)) {
                    Row {
                        MacosCheckbox(
                            value: s.showKernelThreads,
                            onChanged: { taskManagerBloc.add(.setShowKernelThreads($0)) }
                        )
                        SizedBox(width: 6, height: 1)
                        Text("Kernel tasks",
                             style: TextStyle(color: Style.dim, fontSize: 11))
                        Expanded { SizedBox(width: 1, height: 1) }
                        Text(
                            "\(s.processes.count) processes · "
                                + "\(s.snapshot.threadCount) threads · "
                                + _formatUptime(s.snapshot.uptime),
                            style: TextStyle(color: Style.dim, fontSize: 11)
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Run

/// Rebuilds MacosApp with the pushed appearance (shell sends the theme at
/// connect and on every switch) and flips the Style palette — the same
/// shape as FileExplorer's ThemedFilesRoot, so the app matches the desktop
/// instead of shipping its standalone-era hardcoded light.
private class ThemedTaskManagerRoot: StatefulWidget {
    override func createState() -> State<StatefulWidget> {
        return _ThemedTaskManagerRootState()
    }
}

private class _ThemedTaskManagerRootState: State<StatefulWidget> {
    private var _dark = false

    override func initState() {
        super.initState()
        // The shell pushed the desktop appearance when we connected, before
        // this tree existed. Seed from it so the first frame is already right.
        if let dark = GpuDmaBufRenderer.lastPushedThemeIsDark {
            _dark = dark
            Style.dark = dark
        }
        GpuDmaBufRenderer.onThemeChanged = { [weak self] dark in
            guard let self, self._dark != dark else { return }
            Style.dark = dark
            self.setState { self._dark = dark }
            // The process table rebuilds every tick anyway; pull the next
            // one forward so rows re-read the palette immediately.
            taskManagerBloc.add(.tick)
        }
    }

    override func build(_ context: any BuildContext) -> Widget {
        return MacosApp(
                // The ACTIVE STYLE's colours: `StarlingPalette` answers
                // with the macOS values this app shipped with, or WinUI's own
                // tokens when the desktop is in the Windows style. MacosApp
                // either way -- FluentApp's scaffold traps on mount as a
                // DMA-BUF child -- so the widget family stays put and only
                // the palette moves.
            theme: StarlingPalette.current(dark: _dark).macosTheme(),
            home: TaskManagerPage(),
            title: "Task Manager"
        )
    }
}

// Sample once a second, on whatever loop the host runs the UI on — the BLoC
// mutates state right where the rebuild happens. Registered before the loop
// starts; it first fires once the tree is mounted.
startPeriodicTimer(seconds: 1) {
    taskManagerBloc.add(.tick)
}

runStarlingApp(title: "Task Manager", width: 960, height: 700) {
    ThemedTaskManagerRoot()
}

#else
fatalError("The example apps currently target Linux desktop sessions.")
#endif
