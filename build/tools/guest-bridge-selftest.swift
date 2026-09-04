// guest-bridge-selftest — does the seamless channel carry JSON both ways?
//
// M2 Phase 1's proof, and the counterpart of guest-display-selftest.c: it
// drives GuestBridge against a real domain with no shell in the way, so a
// failure here is the channel and not the compositor.
//
// Pair it with the stub helper in the guest (docs/plans/guest-seamless.md
// §Phase 1) — five lines of PowerShell that open the pipe and echo. Without
// the stub this still proves the useful half: that the socket resolves out of
// the domain's XML and connects, which is where the runtime-id path bites.
//
//   swiftc -O -o /tmp/gb build/tools/guest-bridge-selftest.swift \
//       shell/Sources/DesktopShellApp/Guest/GuestBridge.swift \
//       -I shell/Sources/GuestDisplay/include \
//       -Xlinker -lvirt -Xlinker -lsystemd  ... (see the plan)
//
// Simpler in practice: `swift build` the shell and run the same steps from
// the desktop. This file documents the sequence.

import Foundation

#if os(Linux)
import GuestDisplay

@main
enum GuestBridgeSelftest {
 static func main() {
  let domain = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "win11-dbus"
  let seconds = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 15 : 15

// 1. The path has to come from libvirt: it carries the domain's runtime id
//    (/run/libvirt/qemu/channel/<N>-<domain>/...) and changes every boot.
  var buf = [CChar](repeating: 0, count: 4096)
  let rc = domain.withCString { d in
    "org.starling.agent.0".withCString { c in
        guest_display_channel_path(d, c, &buf, buf.count)
    }
  }
  guard rc == 0 else {
    FileHandle.standardError.write(Data(
        "no org.starling.agent.0 channel on \(domain) — add one to the domain XML\n".utf8))
    exit(2)
  }
  print("channel path: \(String(cString: buf))")

  // 2. Connecting proves libvirt's end. It says NOTHING about the guest: the
  //    socket exists whether or not anything inside has opened its side.
  let bridge = GuestBridge(domain: domain)
  var ready = false
  bridge.onReady = { v in
    print(">>> helper answered hello: \(v)")
    ready = true
  }
  bridge.onEvent = { e in print("event: \(e)") }
  bridge.onClosed = { print("channel closed") }

  guard bridge.open() else {
    print("socket resolved but nothing accepted — no helper end open yet.")
    print("That is the expected result until the guest stub is running,")
    print("and it still proves the path discovery above.")
    exit(3)
  }
  print("connected; waiting \(seconds)s for a hello reply")

  let deadline = Date().addingTimeInterval(TimeInterval(seconds))
  while Date() < deadline && !ready {
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
  }
  if ready {
    bridge.send(op: "list_windows") { reply in
        print("list_windows -> \(reply)")
    }
    RunLoop.main.run(until: Date().addingTimeInterval(3))
  }
  bridge.close()
  exit(ready ? 0 : 4)
 }
}
#else
@main
enum GuestBridgeSelftest {
 static func main() { print("Linux only"); exit(1) }
}
#endif
