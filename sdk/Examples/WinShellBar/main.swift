// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Starling shell chrome on Windows — the desktop port's prototype shell.
//
// Phase 0 proved the five things a panel needs from the HOST rather than from
// the UI: an undecorated topmost edge-anchored window (WS_POPUP +
// WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE), monitor geometry, the
// Starling look through the Win32 embedder, a periodic timer reaching the UI
// thread through the message loop, and an appbar reservation so maximized
// windows stop at the strip instead of sliding under it.
//
// Phase 1 is window management, because DWM cannot be replaced: a Starling
// shell on Windows never owns anyone's pixels, it owns their GEOMETRY.
//
// ONE BAR, on the bottom edge. There was a menu bar along the top for a
// while, macOS-shaped, with the dock below it — and that was two strips to
// reach for on a system whose users have one. The dock is the whole of the
// chrome now, and it covers the taskbar it replaces: launcher where Start
// was, running apps in the middle, clock and status at the right. Explorer's
// own taskbar is hidden (`--keep-taskbar` opts out, `--restore-taskbar` puts
// it back and exits); explorer itself keeps running, because it still owns
// the wallpaper, the desktop icons, drag-and-drop and every shell dialog,
// none of which we are ready to take over.
//
// ONE SURFACE PER PROCESS. The Flutter framework mounts a single root and the
// Win32 host owns a single window, so the dock and the launcher are two runs
// of this binary rather than two windows of one — the same shape the Linux
// shell uses for its per-output shells:
//
//   WinShellBar.exe             the dock, bottom edge
//   WinShellBar.exe --launcher  the launcher, hidden until asked for
//   ... --monitor N             put either on a screen other than the primary
//
//   swift build -c release --product WinShellBar

#if os(Windows)
import Flutter
import FlutterSwiftBridge
import FlutterWin32
import FlutterWin32Bridge
import Foundation

Win32WindowedHost.install()

// Diagnostics. `--plain` skips the panel/overlay restyle entirely and comes
// up as an ordinary window; `--no-appbar` keeps the restyle but does not
// reserve the strip. Between them they bisect "the surface came up blank"
// into restyle-vs-reservation without a rebuild.
let wantsPlain = CommandLine.arguments.contains("--plain")
let wantsAppbar = !CommandLine.arguments.contains("--no-appbar")
let wantsLauncher = CommandLine.arguments.contains("--launcher")
let wantsSettings = CommandLine.arguments.contains("--settings")
let wantsFiles = CommandLine.arguments.contains("--files")
let wantsNotifications = CommandLine.arguments.contains("--notifications")
let wantsBanners = CommandLine.arguments.contains("--banners")
let wantsRun = CommandLine.arguments.contains("--run")

// `--monitor N` indexes Win32Display.monitors(); absent means the primary.
// One value, given to BOTH the placement that puts the window on a screen and
// the tree that lays itself out against that screen — see ShellScreen for
// what went wrong when those were decided separately.
let wantsMonitor: Int? = CommandLine.arguments.firstIndex(of: "--monitor")
    .flatMap { i in i + 1 < CommandLine.arguments.count ? Int(CommandLine.arguments[i + 1]) : nil }
ShellScreen.use(monitor: wantsMonitor)

// `--restore-taskbar` does nothing else and exits, so it can be run from
// anywhere to recover a machine whose Starling was killed rather than closed
// (atexit covers the tidy path, and nothing covers taskkill /f).
if CommandLine.arguments.contains("--restore-taskbar") {
    Win32Shell.showNativeTaskbar()
    // AND THE TRAY. Putting the taskbar back leaves its notification area
    // EMPTY: every icon is still registered to our window, which by now does
    // not exist, and nothing repopulates a tray on its own — there is no
    // enumeration to re-run. This is the recovery path for a shell that was
    // killed rather than closed, so it is exactly the case where the tidy
    // handover did not happen.
    Win32Tray.reannounce()
    print("[WinShell] Explorer's taskbar restored, and the tray asked to refill")
    exit(0)
}

// `--print-status` prints what the status readout reads and exits.
//
// It is the oracle for the control centre: the panel's job is to CHANGE these
// values, and the only way to know a toggle did anything is to ask the system
// again from outside the running shell. This process links the same readers
// the dock does, so there is nothing to reimplement — and the readers
// themselves were checked against the system independently, by pressing the
// keyboard's mute key and pulling the network adapter and watching them
// follow.
if CommandLine.arguments.contains("--print-status") {
    let volume = Win32Status.volume()
    let network = Win32Status.network()
    let power = Win32Status.power()
    print("volume=\(volume.map { String($0.percent) } ?? "n/a")",
          "muted=\(volume.map { String($0.isMuted) } ?? "n/a")",
          "network=\(network.kind) signal=\(network.signal) ssid=\(network.ssid)",
          // Whether the machine HAS Wi-Fi, which is what decides if the status
          // bar draws a signal meter at all.
          "wifiAdapter=\(network.hasWifiAdapter)",
          "battery=\(power.hasBattery) percent=\(power.percent.map(String.init) ?? "n/a")",
          "dark=\(Win32Control.isDarkMode)",
          separator: "  ")
    exit(0)
}

// `--print-notifications` reads the toast store and exits — the oracle for
// the notification centre, the same bargain --print-status makes for Quick
// Settings: the only honest check of the panel's list is asking the system
// again from outside the process that draws it.
if CommandLine.arguments.contains("--print-notifications") {
    print("access=\(Win32Notifications.access())")
    let toasts = Win32Notifications.read()
    print("count=\(toasts.count)")
    for t in toasts {
        print("[\(t.id)] \(t.app) @ \(t.time) :: \(t.title) :: \(t.body.replacingOccurrences(of: "\n", with: " | "))")
    }
    exit(0)
}

// `--tray-probe [seconds]` takes the "Shell_TrayWnd" class the tray protocol
// looks up, broadcasts TaskbarCreated so every app re-adds its icons, prints
// what arrives, hands the class back to explorer and exits.
//
// A probe rather than a flag anyone should keep: the tray protocol is entirely
// undocumented, and the three things that decide whether a shell can host it —
// whether OUR window is the one Shell_NotifyIcon finds while explorer is still
// running, what the payload looks like on this Windows build, and what else
// arrives on the same channel that we would be swallowing — can only be
// answered on a real machine.
if let index = CommandLine.arguments.firstIndex(of: "--tray-probe") {
    let seconds = index + 1 < CommandLine.arguments.count
        ? Int32(CommandLine.arguments[index + 1]) ?? 20 : 20
    flwin32_tray_probe(seconds)
    exit(0)
}

// `--print-machine` prints what the Settings app reports and exits — the
// oracle for that pane, the same bargain `--print-status` makes for the
// control centre: the only honest way to know a readout is right is to ask
// the system from outside the process that draws it.
// `--set-mode 1920x1080@60` changes the display mode and exits, and
// `--print-modes` lists what the adapter offers.
//
// The Settings pane has had this writer since it was built; putting it on the
// CLI is what lets a benchmark run at a refresh rate other than the one the
// machine happens to be in — this monitor is 3840x2160 at 29Hz, so a frame is
// 34ms and no screen-sampling measurement can resolve better than that.
// `--thumb-probe [hwnd] [seconds]` puts the same window in two destination
// windows -- one plain, one layered and colour-keyed exactly as the dock is --
// and holds them on screen to be photographed.
//
// A probe rather than a flag anyone should keep, for the reason --tray-probe
// is one: DwmRegisterThumbnail is documented, but whether DWM will composite
// onto the LAYERED window our dock actually is, is not documented either way,
// and the whole design depends on the answer. With no hwnd it picks the
// foreground window, which is the easy way to aim it at something specific.
if let index = CommandLine.arguments.firstIndex(of: "--thumb-probe") {
    let given = index + 1 < CommandLine.arguments.count
        ? UInt64(CommandLine.arguments[index + 1]) : nil
    let seconds = index + 2 < CommandLine.arguments.count
        ? Int32(CommandLine.arguments[index + 2]) ?? 12 : 12
    let target = given ?? Win32WindowManager.windows().first(where: {
        !$0.title.isEmpty && !$0.title.contains("Starling")
    })?.handle ?? 0
    print("[WinShell] thumb-probe target=0x\(String(target, radix: 16))")
    flwin32_thumb_probe(target, seconds)
    exit(0)
}

// `--menu-probe <path>` prints the shell's context-menu verbs for a path and
// exits; `--background` asks for the folder's menu instead of the item's, and
// `--extended` is Shift+right-click.
//
// A WARM-UP WAS TRIED AND REMOVED, so that the cold numbers below are not
// read as a problem this app has. They belong to a process that does nothing
// but query: 517ms for a file against 61ms for the same query again, and 21
// rows cold against 23 warm, because a handler still loading contributes
// nothing to the query loading it.
//
// The file explorer never sees that. Measured in the app, the FIRST
// right-click of a session completes in 233ms and the third in 202ms; every
// menu comes back with the same 19 verbs. Warming one throwaway session at
// startup changed the first click from 265ms to 253ms -- inside the noise --
// and the handler DLLs are already resident from explorer.exe anyway. A
// one-file folder, where the listing's own icon work cannot be doing the
// warming, measured the same 233ms.
//
// The oracle for the file explorer's context menu, and the same bargain
// `--print-status` makes for the control centre: the menu HOSTS other
// people's verbs, so what is in it is a property of this machine's installed
// handlers and not of our code. Reading it from outside the running shell is
// the only way to know whether a row is missing because we dropped it or
// because the shell never offered it. It also times the query, which is the
// number the whole asynchronous design exists to hide.
if let index = CommandLine.arguments.firstIndex(of: "--menu-probe") {
    let path = index + 1 < CommandLine.arguments.count
        ? CommandLine.arguments[index + 1] : ""
    guard !path.isEmpty else {
        print("[menu-probe] expected a path")
        exit(2)
    }
    let background = CommandLine.arguments.contains("--background")
    let extended = CommandLine.arguments.contains("--extended")
    guard let session = Win32ShellMenu(path: path, background: background,
                                       extended: extended, owner: 0) else {
        print("[menu-probe] could not start a session for \(path)")
        exit(1)
    }
    // The blocking form on purpose: this process has no frames to draw, and
    // the whole point is to see how long the shell takes.
    let started = Date()
    let rows = session.itemsSync()
    let elapsed = Int(Date().timeIntervalSince(started) * 1000)
    let split = session.timings()
    print("[menu-probe] \(path)\(background ? " (background)" : "") "
          + "-> \(rows.count) rows in \(elapsed)ms")
    // WHERE the time went, which is the only way to know whether
    // QueryContextMenu is the cost or merely the call it is easiest to blame.
    print(String(format: "[menu-probe] bind %.0fms  QueryContextMenu %.0fms  "
                       + "walk %.2fms (of which GetCommandString %.2fms)",
                 split.bind, split.query, split.walk, split.verbs))
    for row in rows {
        if row.isSeparator {
            print("  --------")
            continue
        }
        let flags = [row.isEnabled ? "" : " disabled",
                     row.isDefault ? " default" : "",
                     row.isSubmenu ? " submenu" : ""].joined()
        print("  id=\(row.id) verb=\(row.verb.isEmpty ? "-" : row.verb) "
              + "\"\(row.title)\"\(flags)")
        if row.isSubmenu {
            let started = Date()
            let children = session.expandSync(.full, row.submenu)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            print("      (\(children.count) children in \(ms)ms)")
            for child in children.prefix(8) where !child.isSeparator {
                print("      id=\(child.id) verb=\(child.verb.isEmpty ? "-" : child.verb) "
                      + "\"\(child.title)\"")
            }
        }
    }
    session.close()

    // The SAME query again, in the same process. Everything a handler needed
    // loading is loaded now, so the difference between these two lines is
    // what a cold shell costs -- and it is the reason a probe (a fresh
    // process every time) reports so much more than the running app does.
    if let warm = Win32ShellMenu(path: path, background: background,
                                 extended: extended, owner: 0) {
        let started = Date()
        let rows = warm.itemsSync()
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        let split = warm.timings()
        print("[menu-probe] again, warm: \(rows.count) rows in \(elapsed)ms")
        print(String(format: "[menu-probe] bind %.0fms  QueryContextMenu %.0fms  "
                           + "walk %.2fms (of which GetCommandString %.2fms)",
                     split.bind, split.query, split.walk, split.verbs))
        // Itemized like the cold list, because the warm menu is the LONGER
        // one -- handlers still loading contribute nothing to the query that
        // is loading them -- and "23 rows" alone cannot say which rows a
        // regression lost.
        for row in rows {
            if row.isSeparator {
                print("  --------")
                continue
            }
            print("  id=\(row.id) verb=\(row.verb.isEmpty ? "-" : row.verb) "
                  + "\"\(row.title)\"")
        }
        warm.close()
    }
    exit(0)
}

// `--menu-handlers <path>` times every registered context-menu handler for a
// path, one at a time, and prints them worst first.
//
// The answer to "where is the bottleneck" that --menu-probe cannot give:
// it can say QueryContextMenu is 99% of the assembly, but QueryContextMenu is
// a loop over other people's DLLs and the useful question is which one. This
// runs that loop by hand. Read-only, and it instantiates nothing the real menu
// would not instantiate a moment later.
if let index = CommandLine.arguments.firstIndex(of: "--menu-handlers") {
    let path = index + 1 < CommandLine.arguments.count
        ? CommandLine.arguments[index + 1] : ""
    guard !path.isEmpty else {
        print("[menu-handlers] expected a path")
        exit(2)
    }
    let max = 64
    var buffer = [FlWin32HandlerCost](repeating: FlWin32HandlerCost(), count: max)
    let started = Date()
    let n = buffer.withUnsafeMutableBufferPointer {
        flwin32_shellmenu_handler_costs(path, $0.baseAddress, Int32(max))
    }
    let elapsed = Date().timeIntervalSince(started) * 1000
    // GENERIC, not `Any`. A fixed-size C char array imports as a tuple, and
    // passing a tuple as `Any` boxes it -- withUnsafeBytes then reads the
    // BOX, which prints as a pointer's worth of mojibake and looks exactly
    // like a corrupted registry read.
    func text<T>(_ tuple: T) -> String {
        var copy = tuple
        return withUnsafeBytes(of: &copy) { bytes in
            String(cString: bytes.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
    }
    struct Row {
        let key: String, dll: String, create: Double, initMs: Double
        let query: Double, items: Int32, failed: Bool
        var total: Double { create + initMs + query }
    }
    let rows = buffer.prefix(Int(n)).map { raw -> Row in
        var raw = raw
        return Row(key: text(raw.key), dll: text(raw.dll),
                   create: raw.create_ms, initMs: raw.init_ms,
                   query: raw.query_ms, items: raw.items, failed: raw.failed != 0)
    }
    print("[menu-handlers] \(path): \(rows.count) registered handlers, "
          + String(format: "%.0fms to run them all", elapsed))
    // Padded by hand: String(format:)'s %s wants a C string, and handing it a
    // Swift String prints the pointer's bytes as text -- which looks exactly
    // like a corrupted registry read and is not one.
    func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? String(text.prefix(width))
                            : text + String(repeating: " ", count: width - text.count)
    }
    func ms(_ value: Double) -> String {
        pad(String(format: "%.1fms", value), 8)
    }
    print("  " + pad("handler", 44) + pad("dll", 26)
          + pad("create", 8) + pad("init", 8) + pad("query", 8) + "items")
    for row in rows.sorted(by: { $0.total > $1.total }) {
        print("  " + pad(row.key, 44) + pad(row.dll.isEmpty ? "-" : row.dll, 26)
              + ms(row.create) + ms(row.initMs) + ms(row.query)
              + "\(row.items)" + (row.failed ? "  (no menu)" : ""))
    }
    let total = rows.reduce(0.0) { $0 + $1.total }
    let worst = rows.sorted { $0.total > $1.total }.first
    print(String(format: "  -- these handlers account for %.0fms", total))
    if let worst {
        print("  -- worst: \(worst.key) (\(worst.dll.isEmpty ? "-" : worst.dll)) at "
              + String(format: "%.0fms, %.0f%% of the handlers' total",
                       worst.total, total > 0 ? worst.total / total * 100 : 0))
    }
    exit(0)
}

// `--menu-static <path>` prints the static registry verbs for a path and how
// long reading them took.
//
// The question behind it: a menu could draw the cheap verbs at once and let
// the COM handlers fill in behind them, which is only worth building if the
// cheap half is both fast to read and worth reading. This says what it costs
// and what it yields, per item type, before anything is built on it.
if let index = CommandLine.arguments.firstIndex(of: "--menu-static") {
    let path = index + 1 < CommandLine.arguments.count
        ? CommandLine.arguments[index + 1] : ""
    guard !path.isEmpty else {
        print("[menu-static] expected a path")
        exit(2)
    }
    var buffer = [FlWin32StaticVerb](repeating: FlWin32StaticVerb(), count: 64)
    let started = Date()
    let n = buffer.withUnsafeMutableBufferPointer {
        flwin32_static_verbs(path, $0.baseAddress, 64)
    }
    let elapsed = Date().timeIntervalSince(started) * 1000
    func text<T>(_ tuple: T) -> String {
        var copy = tuple
        return withUnsafeBytes(of: &copy) { bytes in
            String(cString: bytes.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
    }
    print(String(format: "[menu-static] %@: %d verbs in %.1fms",
                 path, Int(n), elapsed))
    for raw in buffer.prefix(Int(n)) {
        var raw = raw
        print("  \(text(raw.label))   [\(text(raw.verb)) from \(text(raw.source))]")
    }
    exit(0)
}

// `--menu-flags <path>` times QueryContextMenu under each CMF_ flag set.
//
// Before building anything that duplicates the shell -- a static-verb tier, a
// hardcoded label table -- the cheaper question is whether the shell's own
// call can simply be asked to do less. These are the documented flags; the
// two worth the trouble are ASYNCVERBSTATE, which tells handlers not to block
// working out whether a verb is enabled, and OPTIMIZEFORINVOKE, which says
// the menu is not going to be shown.
if let index = CommandLine.arguments.firstIndex(of: "--menu-flags") {
    let path = index + 1 < CommandLine.arguments.count
        ? CommandLine.arguments[index + 1] : ""
    guard !path.isEmpty else {
        print("[menu-flags] expected a path")
        exit(2)
    }
    let sets: [(String, UInt32)] = [
        ("CMF_NORMAL", 0x0000),
        ("CMF_EXPLORE (what we send)", 0x0004),
        ("CMF_ITEMMENU", 0x0080),
        ("CMF_EXPLORE|CMF_ASYNCVERBSTATE", 0x0004 | 0x0400),
        ("CMF_EXPLORE|CMF_OPTIMIZEFORINVOKE", 0x0004 | 0x0800),
        ("CMF_EXPLORE|CMF_DISABLEDVERBS", 0x0004 | 0x0200),
        ("CMF_EXPLORE|CMF_SYNCCASCADEMENU", 0x0004 | 0x1000),
        ("CMF_EXPLORE|CMF_DONOTPICKDEFAULT", 0x0004 | 0x2000),
        ("CMF_DEFAULTONLY (floor)", 0x0001),
    ]
    // One query first, thrown away: otherwise the first flag set in the list
    // pays for loading every handler DLL and looks like the slow one.
    var warm: Int32 = 0
    _ = flwin32_shellmenu_time_flags(path, 0x0004, &warm)

    // And the lever that is not a flag: the same shell, asked about fewer
    // classes. If this is fast and its rows are useful, a fast tier needs no
    // hardcoded labels and no registry parsing of our own.
    for (label, mode) in [("first class only (Directory / ProgID)", Int32(3)),
                          ("no classes (shell built-ins only)", Int32(2)),
                          ("cheap classes only (ProgID/ext)", Int32(0)),
                          ("every class (what the shell does)", Int32(1))] {
        var best = Double.greatestFiniteMagnitude
        var rows: Int32 = 0
        for _ in 0..<3 {
            var items: Int32 = 0
            let ms = flwin32_shellmenu_time_keys(path, mode, &items)
            if ms >= 0 && ms < best { best = ms; rows = items }
        }
        let padded = label.count >= 38 ? String(label.prefix(38))
            : label + String(repeating: " ", count: 38 - label.count)
        print("  " + padded + String(format: "%6.0fms   %d rows", best, Int(rows)))
    }

    // The subset question, answered by listing both.
    func keyRows(_ mode: Int32) -> [String] {
        var buffer = [FlWin32StaticVerb](repeating: FlWin32StaticVerb(), count: 64)
        let n = buffer.withUnsafeMutableBufferPointer {
            flwin32_shellmenu_keys_rows(path, mode, $0.baseAddress, 64)
        }
        func text<T>(_ tuple: T) -> String {
            var copy = tuple
            return withUnsafeBytes(of: &copy) { bytes in
                String(cString: bytes.baseAddress!.assumingMemoryBound(to: CChar.self))
            }
        }
        return buffer.prefix(Int(n)).map { text($0.label) }
    }
    let fastRows = keyRows(0)
    let fullRows = keyRows(1)
    print("  fast tier (\(fastRows.count)): " + fastRows.joined(separator: " | "))
    let strays = fastRows.filter { !fullRows.contains($0) }
    print("  in the fast tier but NOT in the full menu: "
          + (strays.isEmpty ? "none -- a strict subset" : strays.joined(separator: " | ")))
    print("  the full menu adds: "
          + fullRows.filter { !fastRows.contains($0) }.joined(separator: " | "))

    print("[menu-flags] \(path)")
    for (name, flags) in sets {
        // Three runs, best of, because a handler that touches the network can
        // spike and one sample would read as a difference between flag sets.
        var best = Double.greatestFiniteMagnitude
        var rows: Int32 = 0
        for _ in 0..<3 {
            var items: Int32 = 0
            let ms = flwin32_shellmenu_time_flags(path, flags, &items)
            if ms >= 0 && ms < best { best = ms; rows = items }
        }
        let label = name.count >= 38 ? String(name.prefix(38))
                                     : name + String(repeating: " ", count: 38 - name.count)
        print("  " + label + String(format: "%6.0fms   %d rows", best, Int(rows)))
    }
    exit(0)
}

// `--menu-invoke <path> <fast|full> <verb>` runs one canonical verb from one
// tier and exits.
//
// The tiered session numbers its verbs per tier, so invoking with the wrong
// tier runs whatever sits at that offset in the other menu -- a bug that
// would be silent in the worst way, because both menus contain plausible
// verbs. Timing a click in the UI cannot pin down which tier answered; this
// can, because it names the tier.
if let index = CommandLine.arguments.firstIndex(of: "--menu-invoke") {
    let args = CommandLine.arguments
    guard index + 3 < args.count else {
        print("[menu-invoke] expected <path> <fast|full> <verb>")
        exit(2)
    }
    let path = args[index + 1]
    let tier: Win32ShellMenuTier = args[index + 2] == "fast" ? .fast : .full
    let wanted = args[index + 3].lowercased()
    guard let session = Win32ShellMenu(path: path, owner: 0) else {
        print("[menu-invoke] could not start a session")
        exit(1)
    }
    let rows = session.itemsSync(tier)
    guard let row = rows.first(where: { $0.verb == wanted }) else {
        print("[menu-invoke] \(args[index + 2]) tier has no \"\(wanted)\" verb; it has: "
              + rows.filter { !$0.verb.isEmpty }.map(\.verb).joined(separator: " "))
        session.close()
        exit(3)
    }
    print("[menu-invoke] \(args[index + 2]) tier: invoking \(row.verb) "
          + "(id \(row.id), \"\(row.title)\")")
    session.invoke(tier, row.id)
    // The invoke is queued on the session's serial queue and the close behind
    // it; both have to run before this process may exit, and the clipboard
    // formats are rendered by the close (OleFlushClipboard).
    session.close()
    Thread.sleep(forTimeInterval: 1.5)
    exit(0)
}

if CommandLine.arguments.contains("--print-modes") {
    for mode in Win32SystemInfo.displayModes() {
        print("\(mode.width)x\(mode.height)@\(mode.refresh)")
    }
    exit(0)
}

if let index = CommandLine.arguments.firstIndex(of: "--set-mode"),
   index + 1 < CommandLine.arguments.count {
    let spec = CommandLine.arguments[index + 1]
    let parts = spec.split(separator: "@")
    let size = parts.first?.split(separator: "x") ?? []
    guard size.count == 2, let width = Int(size[0]), let height = Int(size[1]) else {
        print("[set-mode] expected WxH@Hz, got \(spec)")
        exit(2)
    }
    let refresh = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
    let wanted = Win32SystemInfo.displayModes().first {
        $0.width == width && $0.height == height
            && (refresh == 0 || $0.refresh == refresh)
    }
    guard let wanted else {
        print("[set-mode] no such mode: \(spec)")
        exit(3)
    }
    let ok = Win32SystemInfo.setDisplayMode(wanted)
    let now = Win32SystemInfo.currentDisplayMode()
    print("[set-mode] \(wanted.label) -> \(ok ? "ok" : "REFUSED"); now "
          + (now.map { "\($0.width)x\($0.height)@\($0.refresh)" } ?? "unknown"))
    exit(ok ? 0 : 1)
}

if CommandLine.arguments.contains("--print-recent") {
    // What Start's Recommended list would show, and why an entry was dropped.
    // The Recent folder is full of shortcuts to shell namespaces and URIs, not
    // only files, so "8 shortcuts, 0 entries" is a real answer and this is how
    // to tell it apart from a reader that is simply broken.
    var folderBuf = [CChar](repeating: 0, count: 1024)
    let fn = folderBuf.withUnsafeMutableBufferPointer {
        flwin32_known_path(7, $0.baseAddress, 1024)
    }
    let folder = fn > 0 ? String(cString: folderBuf) : "<none>"
    print("[recent] folder: \(folder) (n=\(fn))")
    let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
    print("[recent] entries in folder: \(names.count)")
    for name in names.prefix(12) where name.lowercased().hasSuffix(".lnk") {
        let link = Win32Files.join(folder, name)
        var target = [CChar](repeating: 0, count: 1024)
        var args = [CChar](repeating: 0, count: 8)
        var dir = [CChar](repeating: 0, count: 8)
        let ok = target.withUnsafeMutableBufferPointer { t in
            args.withUnsafeMutableBufferPointer { a in
                dir.withUnsafeMutableBufferPointer { w in
                    flwin32_shortcut_info(link, t.baseAddress, 1024,
                                          a.baseAddress, 8, w.baseAddress, 8)
                }
            }
        }
        let path = String(cString: target)
        print("[recent] lnk \(name) -> rc=\(ok) '\(path)' exists=\(FileManager.default.fileExists(atPath: path))")
    }
    for entry in Win32Files.recent(limit: 20) {
        print("[recent] KEPT \(entry.name)  <-  \(entry.path)")
    }
    print("[recent] user: \(Win32Files.userName())")
    exit(0)
}

if CommandLine.arguments.contains("--print-machine") {
    let m = Win32SystemInfo.machine()
    print("os=\(m.osName) build=\(m.osBuild)")
    print("device=\(m.deviceName)")
    print("cpu=\(m.cpuName) cores=\(m.cpuCores)")
    print("ram=\(m.totalRam / 1_048_576)MB available=\(m.availableRam / 1_048_576)MB")
    print("gpu=\(m.gpuName)")
    print("power=\(m.powerScheme)")
    if let mode = Win32SystemInfo.currentDisplayMode() {
        print("display=\(mode.width)x\(mode.height)@\(mode.refresh)")
    }
    let modes = Win32SystemInfo.displayModes()
    print("modes=\(modes.count): "
          + modes.prefix(6).map { "\($0.width)x\($0.height)@\($0.refresh)" }
              .joined(separator: " "))
    for drive in Win32SystemInfo.drives() {
        print("drive \(drive.letter): \(drive.total / 1_073_741_824)GB total, "
              + "\(drive.free / 1_073_741_824)GB free")
    }
    print("wallpaper=\(Win32SystemInfo.wallpaper())")
    for adapter in Win32Adapters.all() {
        print("adapter \(adapter.name) [\(adapter.kind)] up=\(adapter.isUp) "
              + "speed=\(adapter.speedText) ip=\(adapter.ipv4) "
              + "gw=\(adapter.gateway) dns=\(adapter.dns) "
              + "mac=\(adapter.mac) dhcp=\(adapter.usesDHCP)")
    }
    exit(0)
}

// Span the chosen monitor. Reading the geometry rather than assuming 1920 is
// the point — a panel sized to the wrong screen is the first thing that goes
// wrong on a laptop plus an external.
let screen = ShellScreen.monitor
// PHYSICAL pixels, not logical.
//
// runStarlingApp's size becomes the window's client size in pixels, and the
// engine's view is created for it. The panel restyle then resizes the window
// to the strip — and on a 200% display that is a resize from 1920x44 to
// 3840x88 BEFORE the first frame, which is exactly when the tree has not
// mounted yet. Creating it at the size it is going to be means there is no
// resize to survive. (On the 100% VM the two happened to be equal, which is
// why this never showed up there.)
let panelWidth = Int(screen?.width ?? 1280)
let panelScale = screen?.scale ?? 1.0
print("[WinShell] monitors: \(Win32Display.monitors())")

// The palette follows the system's APPS theme, decided before any window
// exists so no frame is ever painted in the wrong one. The seed only:
// mid-session flips arrive by WM_SETTINGCHANGE through the host's
// theme-change callback (see Win11.light and StarlingFilesState.initState).
Win11.light = Win32SystemInfo.appsUseLightTheme()

// takesFocus stays at its default of false for both: clicking a dock icon
// must not take the keyboard off the window the click is about to raise.
if wantsFiles {
    // One pair of numbers for the window and for the tree, the same bargain
    // ShellScreen makes for a panel: the menu has to know where the window's
    // bottom edge is to flip itself up, and a tree laying out against a size
    // the window does not have is how that goes silently wrong.
    runStarlingApp(title: "Starling Files",
                   width: Int(kFilesWidth * panelScale),
                   height: Int(kFilesHeight * panelScale)) {
        StarlingFiles()
    }
} else if wantsSettings {
    // An ORDINARY WINDOW: no panel, no overlay, no restyle. Settings is an
    // app — it belongs in Alt+Tab, and the user should be able to move and
    // close it like anything else.
    runStarlingApp(title: "Starling Settings",
                   width: Int(980 * panelScale),
                   height: Int(680 * panelScale)) {
        StarlingSettings()
    }
} else if wantsNotifications {
    // The notification centre: the launcher's bargain exactly — a parked
    // overlay, hidden until its toggle — but pinned to the work area's
    // right edge and listening on its OWN channel, so Win+N does not toggle
    // the launcher too.
    if !wantsPlain {
        Win32WindowedHost.overlay = OverlayPlacement(
            monitor: wantsMonitor, opacity: 1.0,
            size: (width: kAcWidth, height: kAcHeightPt),
            bottomMargin: kAcPanelGap,
            rightMargin: 13,
            channel: "notifications",
            transparent: true)
    }
    runStarlingApp(title: "Starling Notifications",
                   width: Int(kAcWidth * panelScale),
                   height: Int(kAcHeightPt * panelScale)) {
        StarlingActionCenter()
    }
} else if wantsBanners {
    // The toast banner: a parked overlay like the others, with two
    // differences. It is PASSIVE — a surface that appears while the user is
    // typing must not steal focus or the next Escape — and no user gesture
    // shows it: the controller polls the store and shows it on arrival,
    // which is why it starts OFF the widget lifecycle (a parked overlay's
    // tree does not mount until first shown).
    if !wantsPlain {
        Win32WindowedHost.overlay = OverlayPlacement(
            monitor: wantsMonitor, opacity: 1.0,
            size: (width: kBannerWidth, height: kBannerHeight),
            bottomMargin: kBannerGap,
            rightMargin: 13,
            channel: "banners",
            transparent: true,
            passive: true)
    }
    BannerController.shared.start()
    runStarlingApp(title: "Starling Banners",
                   width: Int(kBannerWidth * panelScale),
                   height: Int(kBannerHeight * panelScale)) {
        StarlingBanner()
    }
} else if wantsRun {
    // The Run dialog: a parked overlay pinned to the work area's bottom-left
    // corner, where Windows puts its own. It takes focus deliberately — the
    // whole surface is a text field — so it is NOT passive, and the standard
    // overlay Escape/focus-loss dismissal is exactly right for it.
    if !wantsPlain {
        Win32WindowedHost.overlay = OverlayPlacement(
            monitor: wantsMonitor, opacity: 1.0,
            size: (width: kRunWidth, height: kRunHeight),
            bottomMargin: kRunGap,
            leftMargin: kRunGap,
            channel: "run",
            transparent: true)
    }
    runStarlingApp(title: "Starling Run",
                   width: Int(kRunWidth * panelScale),
                   height: Int(kRunHeight * panelScale)) {
        StarlingRun()
    }
} else if wantsLauncher {
    // An overlay, not a panel: it is not an edge and it reserves nothing. It
    // also comes up HIDDEN — see Launcher.swift for why it runs at all while
    // invisible.
    // --plain: a diagnostic escape hatch. The overlay restyle happens before
    // the tree mounts, so when the launcher comes up blank this is how you
    // find out whether the restyle is what stopped it.
    if !wantsPlain {
        Win32WindowedHost.overlay = OverlayPlacement(
            monitor: wantsMonitor, opacity: 1.0,
            size: (width: kLauncherWidth, height: kLauncherHeight),
            bottomMargin: kLauncherGap)
    }
    // Read the Start Menu and rasterize its icons NOW, off the widget
    // lifecycle: a parked overlay is not sent frames, so its tree does not
    // mount until it is first shown, and everything initState did was landing
    // on the keypress that asked for it. See LauncherPreload.
    launcherBloc.add(.start)
    // PHYSICAL pixels, and the same size the restyle will give it: a window
    // that is not already its final size when the first frame is due does not
    // mount its tree (see flwin32_host.c's parking notes).
    runStarlingApp(title: "Starling Launcher",
                   width: Int(kLauncherWidth * panelScale),
                   height: Int(kLauncherHeight * panelScale)) {
        StarlingLauncher()
    }
} else {
    // Hide Explorer's taskbar BEFORE reserving our own strip: ABM_QUERYPOS
    // moves a new appbar clear of every existing one, so reserving first and
    // hiding second leaves the dock floating a taskbar's height off the
    // bottom of the screen.
    if !keepsNativeTaskbar {
        let hidden = Win32Shell.hideNativeTaskbar()
        print("[WinShell] Explorer taskbar hidden: \(hidden)")
    }

    // The tray class, taken BEFORE the panel registers its appbar below:
    // SHAppBarMessage resolves Shell_TrayWnd at call time, so this ordering is
    // what points the dock's own reservation at the appbar service in this
    // process when that service is the one answering (explorer absent, or
    // STARLING_TRAY_OWN=1 forcing it). With explorer present the service
    // forwards and nothing changes. DockBloc starts the tray again later,
    // which is only a callback rewire.
    if !keepsNativeTray {
        Win32Tray.start {}
    }

    // The Windows key, pointed at our Start instead of Explorer's. It lives in
    // the DOCK because the dock is the process that stays running — and
    // because two hooks would replay the keyup twice and toggle the launcher
    // back closed. Installed here, on the thread that is about to become the
    // message loop, which is where a low-level hook has to be.
    if !keepsWindowsKey {
        let captured = Win32Shell.captureSuperKey { Win32Shell.toggleOverlay() }
        print("[WinShell] Windows key captured: \(captured)")
    } else {
        // Said out loud, because "we chose not to" and "we tried and failed"
        // are the same silence in a log otherwise.
        print("[WinShell] Windows key left to Windows (--keep-winkey)")
    }
    // transparent: the dock is a slab floating over the wallpaper, so the
    // strip around it has to be a hole rather than a black band. overhang:
    // the window extends above the reserved strip so the hover label and the
    // right-click menu have somewhere to draw — a window is a hard clip, and
    // both are taller than the dock.
    if !wantsPlain {
        // The edge the user last chose, read before the window is made: the
        // tree and the window must agree from the first frame, or the dock
        // draws itself as a column inside a bar-shaped window.
        Win32WindowedHost.panel = PanelPlacement(edge: DockBloc.loadEdge(),
                                                 thickness: kDockHeight,
                                                 monitor: wantsMonitor,
                                                 reserveSpace: wantsAppbar,
                                                 transparent: true,
                                                 overhang: kDockOverhang)
    }
    runStarlingApp(title: "Starling Dock", width: panelWidth,
                   height: Int(Double(kDockHeight + kDockOverhang) * panelScale)) {
        StarlingDock()
    }
}

#else
fatalError("WinShellBar is the Windows shell-chrome prototype.")
#endif
