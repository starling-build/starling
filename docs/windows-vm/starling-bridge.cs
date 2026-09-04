// starling-bridge — the guest half of the seamless channel, M2 Phase 2.
//
// docs/plans/guest-seamless.md. Speaks one JSON object per line over the
// virtio-serial port `org.starling.agent.0`, in AgentBroker's vocabulary:
// {"op":…,"id":…} answered by {"id":…,"ok":…}, plus unsolicited {"event":…}.
//
// WHY C# AND NOT THE REAL HELPER. The shipping helper is a `--bridge` role of
// WinShellBar, which already owns Win32WindowManager, the session slot and the
// dock (docs/plans/guest-seamless.md §Phase 2). That is Swift, and building
// Swift for Windows needs a Windows toolchain — which the Linux dev box does
// not have and the guest does not either. This does not need one: every
// Windows install ships csc.exe under %WINDIR%\Microsoft.NET\Framework64, so
// the guest can build it from a single file with nothing installed.
//
// So this is the PROTOCOL REFERENCE and the fixture that unblocks Phase 3,
// exactly as the PowerShell stub was for Phase 1 — not a second
// implementation to keep in sync. The window filter below is transcribed from
// flwin32_wm.c's is_manageable() and must stay a transcription: if the two
// disagree about which windows exist, the desktop gets one answer while
// developing and another once the real helper lands, which is the worst
// possible way to find out.
//
//   csc.exe /nologo /out:starling-bridge.exe /unsafe starling-bridge.cs
//   starling-bridge.exe            (writes to the virtio port)
//   starling-bridge.exe --stdout   (prints to the console, for eyeballing)

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

static class Bridge {

    // ── Win32 ───────────────────────────────────────────────────────────────

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr CreateFileW(string path, uint access, uint share,
        IntPtr sa, uint disposition, uint flags, IntPtr template);

    delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lparam);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc cb, IntPtr p);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("user32.dll", SetLastError = true)]
    static extern IntPtr GetWindowLongPtrW(IntPtr h, int index);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern int GetWindowTextW(IntPtr h, StringBuilder s, int max);
    [DllImport("user32.dll")] static extern int GetWindowTextLengthW(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern int GetClassNameW(IntPtr h, StringBuilder s, int max);
    [DllImport("user32.dll")]
    static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("dwmapi.dll")]
    static extern int DwmGetWindowAttribute(IntPtr h, int attr, out RECT v, int size);

    [StructLayout(LayoutKind.Sequential)]
    struct RECT { public int Left, Top, Right, Bottom; }

    const int GWL_EXSTYLE = -20;
    const uint GW_OWNER = 4;
    const int WS_EX_TOOLWINDOW = 0x00000080;
    const int WS_EX_APPWINDOW  = 0x00040000;
    const int DWMWA_CLOAKED = 14;
    const int DWMWA_EXTENDED_FRAME_BOUNDS = 9;

    // ── the filter, transcribed from flwin32_wm.c is_manageable() ───────────
    // Keep it a transcription. Every clause here earns its place there:
    // WS_EX_APPWINDOW is the documented "show me anyway" override and wins over
    // the two tests it precedes; an owned window is a dialog OF something, so
    // the owner is the taskbar entry, not this; and the cloaked test is what
    // turns ~40 candidates into the ~6 a person can see, because it catches
    // both suspended UWP apps and windows on another virtual desktop.

    static bool IsCloaked(IntPtr h) {
        RECT dummy;
        int cloaked = 0;
        // DWMWA_CLOAKED returns an int, not a RECT; marshal it the same way by
        // reading only the first field.
        if (DwmGetWindowAttribute(h, DWMWA_CLOAKED, out dummy, 4) == 0)
            cloaked = dummy.Left;
        return cloaked != 0;
    }

    static bool IsShellFurniture(string cls) {
        switch (cls) {
            case "Shell_TrayWnd":
            case "Shell_SecondaryTrayWnd":
            case "Progman":
            case "WorkerW":
            case "Windows.UI.Core.CoreWindow":
            case "ApplicationFrameWindow_DesktopWindowXamlSource":
                return true;
        }
        return false;
    }

    static bool VisibleFrame(IntPtr h, out RECT r) {
        // The window rect includes an invisible resize border on Windows 10+;
        // DWM's extended bounds is the frame the user actually sees, and the
        // difference between the two is the correction to apply when moving.
        if (DwmGetWindowAttribute(h, DWMWA_EXTENDED_FRAME_BOUNDS, out r,
                                  Marshal.SizeOf(typeof(RECT))) == 0)
            return true;
        return GetWindowRect(h, out r);
    }

    static bool IsManageable(IntPtr h) {
        if (h == IntPtr.Zero || !IsWindow(h)) return false;
        if (!IsWindowVisible(h)) return false;

        long ex = GetWindowLongPtrW(h, GWL_EXSTYLE).ToInt64();
        if ((ex & WS_EX_APPWINDOW) == 0) {
            if (GetWindow(h, GW_OWNER) != IntPtr.Zero) return false;
            if ((ex & WS_EX_TOOLWINDOW) != 0) return false;
        }
        if (IsCloaked(h)) return false;
        if (GetWindowTextLengthW(h) == 0) return false;

        var cls = new StringBuilder(256);
        if (GetClassNameW(h, cls, 256) == 0) return false;
        if (IsShellFurniture(cls.ToString())) return false;

        RECT r;
        if (!VisibleFrame(h, out r)) return false;
        if (r.Right - r.Left <= 0 || r.Bottom - r.Top <= 0) return false;
        return true;
    }

    static string ExePath(uint pid) {
        try {
            using (var p = System.Diagnostics.Process.GetProcessById((int)pid))
                return p.MainModule.FileName;
        } catch {
            // A service, or a higher integrity level, refused to be opened.
            // Empty rather than absent: the shell falls back to the class,
            // which is what Win32Window.appName does.
            return "";
        }
    }

    // ── JSON, hand-rolled ───────────────────────────────────────────────────
    // No dependency is worth taking for six field types, and csc.exe alone has
    // no JSON library on a stock Windows.

    static string Esc(string s) {
        var b = new StringBuilder();
        foreach (char c in s) {
            switch (c) {
                case '"':  b.Append("\\\""); break;
                case '\\': b.Append("\\\\"); break;
                case '\n': b.Append("\\n");  break;
                case '\r': b.Append("\\r");  break;
                case '\t': b.Append("\\t");  break;
                default:
                    if (c < 0x20) b.Append("\\u").Append(((int)c).ToString("x4"));
                    else b.Append(c);
                    break;
            }
        }
        return b.ToString();
    }

    static string ListWindows() {
        var sb = new StringBuilder();
        sb.Append("[");
        bool first = true;
        IntPtr fg = GetForegroundWindow();
        // EnumWindows walks in z-order, topmost first — the same order a
        // taskbar and Alt+Tab show, and the order the crop needs.
        EnumWindows((h, _) => {
            if (!IsManageable(h)) return true;
            var title = new StringBuilder(512);
            GetWindowTextW(h, title, 512);
            var cls = new StringBuilder(256);
            GetClassNameW(h, cls, 256);
            uint pid; GetWindowThreadProcessId(h, out pid);
            RECT r; VisibleFrame(h, out r);
            if (!first) sb.Append(",");
            first = false;
            sb.Append("{\"hwnd\":").Append(h.ToInt64())
              .Append(",\"pid\":").Append(pid)
              .Append(",\"title\":\"").Append(Esc(title.ToString()))
              .Append("\",\"class\":\"").Append(Esc(cls.ToString()))
              .Append("\",\"exe\":\"").Append(Esc(ExePath(pid)))
              .Append("\",\"x\":").Append(r.Left)
              .Append(",\"y\":").Append(r.Top)
              .Append(",\"w\":").Append(r.Right - r.Left)
              .Append(",\"h\":").Append(r.Bottom - r.Top)
              .Append(",\"min\":").Append(IsIconic(h) ? "true" : "false")
              .Append(",\"max\":").Append(IsZoomed(h) ? "true" : "false")
              .Append(",\"fg\":").Append(h == fg ? "true" : "false")
              .Append("}");
            return true;
        }, IntPtr.Zero);
        sb.Append("]");
        return sb.ToString();
    }

    // Only the fields this helper answers on, read without a parser: the
    // protocol is small and fixed, and a hand-rolled reader that understands
    // exactly two keys cannot mis-parse a third.
    static string Field(string line, string key) {
        string needle = "\"" + key + "\"";
        int i = line.IndexOf(needle, StringComparison.Ordinal);
        if (i < 0) return null;
        i = line.IndexOf(':', i + needle.Length);
        if (i < 0) return null;
        i++;
        while (i < line.Length && (line[i] == ' ' || line[i] == '\t')) i++;
        if (i >= line.Length) return null;
        if (line[i] == '"') {
            int end = line.IndexOf('"', i + 1);
            return end < 0 ? null : line.Substring(i + 1, end - i - 1);
        }
        int j = i;
        while (j < line.Length && line[j] != ',' && line[j] != '}') j++;
        return line.Substring(i, j - i).Trim();
    }

    static int Main(string[] args) {
        bool toStdout = Array.IndexOf(args, "--stdout") >= 0;
        TextWriter w;
        TextReader r = null;

        if (toStdout) {
            w = Console.Out;
        } else {
            const uint GENERIC_RW = 0xC0000000;
            IntPtr h = CreateFileW(@"\\.\Global\org.starling.agent.0",
                                   GENERIC_RW, 0, IntPtr.Zero, 3, 0, IntPtr.Zero);
            if (h == new IntPtr(-1)) {
                Console.Error.WriteLine("cannot open the port: " +
                    Marshal.GetLastWin32Error() +
                    " (is org.starling.agent.0 in the domain XML?)");
                return 2;
            }
            var fs = new FileStream(new SafeFileHandle(h, true),
                                    FileAccess.ReadWrite);
            // AutoFlush, because a line the host never sees is the same as a
            // line never written, and virtio-serial gives no push-back to
            // notice it by.
            w = new StreamWriter(fs) { AutoFlush = true };
            r = new StreamReader(fs);
        }

        if (toStdout) {
            w.WriteLine("{\"id\":0,\"ok\":true,\"windows\":" + ListWindows() + "}");
            return 0;
        }

        w.WriteLine("{\"event\":\"helper-up\",\"helper\":\"starling-bridge/cs 1\"}");
        string line;
        while ((line = r.ReadLine()) != null) {
            if (line.Length == 0) continue;
            string op = Field(line, "op");
            string id = Field(line, "id") ?? "0";
            if (op == "hello") {
                w.WriteLine("{\"id\":" + id +
                            ",\"ok\":true,\"helper\":\"starling-bridge/cs 1\"}");
            } else if (op == "list_windows") {
                w.WriteLine("{\"id\":" + id + ",\"ok\":true,\"windows\":" +
                            ListWindows() + "}");
            } else if (op == "quit") {
                w.WriteLine("{\"id\":" + id + ",\"ok\":true}");
                break;
            } else {
                w.WriteLine("{\"id\":" + id + ",\"ok\":false,\"error\":\"" +
                            Esc("no such op: " + (op ?? "?")) + "\"}");
            }
        }
        return 0;
    }
}
