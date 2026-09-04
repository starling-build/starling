// starling-bridge — the guest half of the seamless channel, M2 Phases 2-3.
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
// possible way to find out. activate/move/close are transcriptions of the
// same file's flwin32_wm_activate/_move/_close, for the same reason.
//
// Ops:
//   hello                      -> {"ok":true,"helper":…,"screen":{x,y,w,h,dpi}}
//   list_windows               -> {"ok":true,"fg":hwnd,"windows":[…]}
//   observe {"interval":ms}    -> ok; then {"event":"windows",…} on every change
//   activate|close|minimize|maximize|restore {"hwnd":n}
//   move {"hwnd":n,"x":…,"y":…,"w":…,"h":…}   (the VISIBLE frame)
//   launch {"path":…,"args":…}  (an exe path, or shell:AppsFolder\… for a Store app)
//   apps                       -> {"ok":true,"apps":[{id,name,exe,icon}]} — the
//                                 AppsFolder: every app Start would list, packaged
//                                 or not, `id` launchable as shell:AppsFolder\<id>,
//                                 `icon` a base64 PNG (48px) when the shell has one
//   quit
//
// ONE DIVERGENCE from the real helper, on purpose: events come from a poll
// (default 100 ms), not from WinEvent hooks. Hooks need a message loop on the
// installing thread, which this single-file fixture does not have, and a poll
// reports what the hooks deliberately do not — continuous motion during a
// drag, and programmatic moves — which is the better behaviour for a crop that
// follows the window. A windows() walk is single-digit milliseconds; ten a
// second is a rounding error. The event carries the WHOLE list, so the host
// reconciles against it and never depends on which of the two produced it.
//
//   csc.exe /nologo /target:winexe /out:starling-bridge.exe starling-bridge.cs
//   starling-bridge.exe                    (serves the virtio port)
//   starling-bridge.exe --stdout > wins.json   (one list, for eyeballing)
//
// /target:winexe, or the helper's own console is a window — the first thing
// the desktop showed as "a Windows app" was C:\starling-bridge.exe. A GUI
// subsystem process still inherits a redirected stdout, so --stdout works
// through `cmd /c ... > file`, which is how the task runs it anyway.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using Microsoft.Win32.SafeHandles;

static class Bridge {

    const string Version = "starling-bridge/cs 2";

    // ── Win32 ───────────────────────────────────────────────────────────────

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr CreateFileW(string path, uint access, uint share,
        IntPtr sa, uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();

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
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after,
        int x, int y, int w, int hh, uint flags);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr SetFocus(IntPtr h);
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("user32.dll")] static extern void SwitchToThisWindow(IntPtr h, bool altTab);
    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern bool PostMessageW(IntPtr h, uint msg, IntPtr wp, IntPtr lp);
    [DllImport("user32.dll")] static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll")] static extern uint GetDpiForSystem();
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("dwmapi.dll")]
    static extern int DwmGetWindowAttribute(IntPtr h, int attr, out RECT v, int size);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    static extern int GetApplicationUserModelId(IntPtr process, ref uint len, StringBuilder id);
    [DllImport("shell32.dll")]
    static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid riid,
        [MarshalAs(UnmanagedType.Interface)] out IPropertyStore store);
    [DllImport("ole32.dll")] static extern int PropVariantClear(ref PROPVARIANT pv);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SHCreateItemFromParsingName(string path, IntPtr ctx, ref Guid riid,
        [MarshalAs(UnmanagedType.Interface)] out IShellItemImageFactory factory);
    [DllImport("shell32.dll")]
    static extern int SHGetKnownFolderPath(ref Guid id, uint flags, IntPtr token, out IntPtr path);
    [DllImport("ole32.dll")] static extern void CoTaskMemFree(IntPtr p);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr h);
    [DllImport("gdi32.dll")] static extern int GetObject(IntPtr h, int size, out BITMAP bm);

    [StructLayout(LayoutKind.Sequential)]
    struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    struct SIZE { public int cx, cy; public SIZE(int w, int h) { cx = w; cy = h; } }
    [StructLayout(LayoutKind.Sequential)]
    struct BITMAP {
        public int bmType, bmWidth, bmHeight, bmWidthBytes;
        public ushort bmPlanes, bmBitsPixel;
        public IntPtr bmBits;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct PROPERTYKEY { public Guid fmtid; public uint pid; }
    [StructLayout(LayoutKind.Sequential)]
    struct PROPVARIANT {
        public ushort vt; ushort r1, r2, r3;
        public IntPtr p; IntPtr p2;
    }
    [ComImport, Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore {
        int GetCount(out uint c);
        int GetAt(uint i, out PROPERTYKEY k);
        int GetValue(ref PROPERTYKEY k, out PROPVARIANT v);
        int SetValue(ref PROPERTYKEY k, ref PROPVARIANT v);
        int Commit();
    }
    [ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IShellItemImageFactory {
        int GetImage(SIZE size, int flags, out IntPtr hbitmap);
    }
    // PKEY_AppUserModel_ID, spelled out as flwin32_wm.c does.
    static readonly Guid kAppUserModelFmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");
    static readonly Guid kIID_IPropertyStore = new Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99");
    static readonly Guid kIID_IShellItemImageFactory = new Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b");
    const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
    const int SIIGBF_ICONONLY = 0x4, SIIGBF_BIGGERSIZEOK = 0x1;

    const int GWL_EXSTYLE = -20;
    const uint GW_OWNER = 4;
    const int WS_EX_TOOLWINDOW = 0x00000080;
    const int WS_EX_APPWINDOW  = 0x00040000;
    const int DWMWA_CLOAKED = 14;
    const int DWMWA_EXTENDED_FRAME_BOUNDS = 9;
    const int SW_RESTORE = 9, SW_MINIMIZE = 6, SW_MAXIMIZE = 3;
    const uint SWP_NOZORDER = 0x0004, SWP_NOACTIVATE = 0x0010, SWP_NOOWNERZORDER = 0x0200;
    const uint WM_CLOSE = 0x0010;
    const byte VK_MENU = 0x12;
    const uint KEYEVENTF_KEYUP = 0x0002;
    const int SM_XVIRTUALSCREEN = 76, SM_YVIRTUALSCREEN = 77;
    const int SM_CXVIRTUALSCREEN = 78, SM_CYVIRTUALSCREEN = 79;

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

    // Which packaged app a window belongs to, "" for an ordinary program —
    // a transcription of flwin32_wm.c's window_app_id(): the process first (a
    // plain kernel call; Notepad, Paint, Terminal carry the id there and
    // nothing on the window), then, only for the CoreWindow generation's
    // ApplicationFrameWindow (Settings, Calculator — whose host process is
    // not packaged), the frame's own property store, which is what
    // explorer's taskbar reads too. A packaged id has a '!' in it; a bare
    // label like Edge's "MSEdge" is not one, and is not taken.
    static string WindowAumid(IntPtr h, uint pid, string cls) {
        IntPtr p = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (p != IntPtr.Zero) {
            var sb = new StringBuilder(512);
            uint len = 512;
            int rc = GetApplicationUserModelId(p, ref len, sb);
            CloseHandle(p);
            string id = sb.ToString();
            if (rc == 0 && id.IndexOf('!') >= 0) return id;
        }
        if (cls != "ApplicationFrameWindow") return "";
        try {
            IPropertyStore store;
            Guid iid = kIID_IPropertyStore;
            if (SHGetPropertyStoreForWindow(h, ref iid, out store) != 0 || store == null) return "";
            var key = new PROPERTYKEY { fmtid = kAppUserModelFmtid, pid = 5 };
            PROPVARIANT v;
            string result = "";
            if (store.GetValue(ref key, out v) == 0) {
                if (v.vt == 31 /* VT_LPWSTR */ && v.p != IntPtr.Zero) {
                    string s = Marshal.PtrToStringUni(v.p);
                    if (s != null && s.IndexOf('!') >= 0) result = s;
                }
                PropVariantClear(ref v);
            }
            Marshal.ReleaseComObject(store);
            return result;
        } catch {
            return "";
        }
    }

    // A known-folder-relative AppsFolder id ("{1AC14E77-…}\cmd.exe" — how
    // Windows 11 files System32's tools) resolved to a real path, so a
    // classic app's window (matched by exe) can find its record. "" for any
    // other shape of id; a plain path is returned as-is.
    static string ExpandAppId(string id) {
        if (id.Length > 38 && id[0] == '{' && id[37] == '}' && id[38] == '\\') {
            Guid g;
            if (Guid.TryParse(id.Substring(0, 38), out g)) {
                IntPtr path;
                if (SHGetKnownFolderPath(ref g, 0, IntPtr.Zero, out path) == 0) {
                    string root = Marshal.PtrToStringUni(path);
                    CoTaskMemFree(path);
                    return root + id.Substring(38);
                }
            }
            return "";
        }
        if (id.Length > 2 && id[1] == ':' && id[2] == '\\') return id;
        return "";
    }

    // The app's icon as the shell draws it for Start, 48px, as a PNG — the
    // one source that works for packaged and classic apps alike. The HBITMAP
    // is a 32-bit DIB with premultiplied alpha; Image.FromHbitmap throws the
    // alpha away, so the pixels are read straight from the section instead.
    static string AppIconPng(string id) {
        try {
            IShellItemImageFactory f;
            Guid iid = kIID_IShellItemImageFactory;
            if (SHCreateItemFromParsingName("shell:AppsFolder\\" + id, IntPtr.Zero, ref iid, out f) != 0 || f == null)
                return null;
            IntPtr hbmp;
            int rc = f.GetImage(new SIZE(48, 48), SIIGBF_ICONONLY | SIIGBF_BIGGERSIZEOK, out hbmp);
            Marshal.ReleaseComObject(f);
            if (rc != 0 || hbmp == IntPtr.Zero) return null;
            try {
                BITMAP bm;
                if (GetObject(hbmp, Marshal.SizeOf(typeof(BITMAP)), out bm) == 0 ||
                    bm.bmBitsPixel != 32 || bm.bmBits == IntPtr.Zero) return null;
                using (var wrapped = new Bitmap(bm.bmWidth, bm.bmHeight, bm.bmWidthBytes,
                                                PixelFormat.Format32bppPArgb, bm.bmBits))
                using (var copy = new Bitmap(wrapped))
                using (var ms = new MemoryStream()) {
                    // The section is bottom-up: row 0 in memory is the bottom.
                    copy.RotateFlip(RotateFlipType.RotateNoneFlipY);
                    copy.Save(ms, ImageFormat.Png);
                    return Convert.ToBase64String(ms.ToArray());
                }
            } finally {
                DeleteObject(hbmp);
            }
        } catch {
            return null;
        }
    }

    // The AppsFolder, through the same Shell object explorer's Start reads —
    // packaged apps have no shortcut anywhere and live only here. Late-bound
    // COM, so the file needs nothing beyond csc's default references. Works
    // only in an interactive session: from session 0 the folder enumerates
    // as empty, which looks like a guest with no apps.
    static string Apps() {
        var sb = new StringBuilder();
        sb.Append("[");
        bool first = true;
        try {
            Type t = Type.GetTypeFromProgID("Shell.Application");
            dynamic shell = Activator.CreateInstance(t);
            dynamic folder = shell.NameSpace("shell:AppsFolder");
            dynamic items = folder.Items();
            foreach (dynamic item in items) {
                string name = item.Name as string;
                string id = item.Path as string;
                if (string.IsNullOrEmpty(name) || string.IsNullOrEmpty(id)) continue;
                if (!first) sb.Append(",");
                first = false;
                sb.Append("{\"id\":\"").Append(Esc(id))
                  .Append("\",\"name\":\"").Append(Esc(name))
                  .Append("\",\"exe\":\"").Append(Esc(ExpandAppId(id))).Append("\"");
                string png = AppIconPng(id);
                if (png != null) sb.Append(",\"icon\":\"").Append(png).Append("\"");
                sb.Append("}");
            }
        } catch (Exception e) {
            Console.Error.WriteLine("apps: " + e.Message);
        }
        sb.Append("]");
        return sb.ToString();
    }

    static string ExePath(uint pid) {
        try {
            using (var p = Process.GetProcessById((int)pid))
                return p.MainModule.FileName;
        } catch {
            // A service, or a higher integrity level, refused to be opened.
            // Empty rather than absent: the shell falls back to the class,
            // which is what Win32Window.appName does.
            return "";
        }
    }

    // ── acting, transcribed from flwin32_wm.c ───────────────────────────────

    static bool Activate(IntPtr hwnd) {
        if (hwnd == IntPtr.Zero || !IsWindow(hwnd)) return false;
        // Restore first: a minimized window can be made foreground and stay
        // minimized, which looks exactly like the click did nothing.
        if (IsIconic(hwnd)) ShowWindow(hwnd, SW_RESTORE);
        IntPtr fg = GetForegroundWindow();
        if (fg == hwnd) { SetFocus(hwnd); return true; }
        // Windows only lets the process that already owns the foreground hand
        // it away. Sharing an input queue with the current owner makes us
        // count as that process for the length of the call.
        uint dummy;
        uint current = GetWindowThreadProcessId(fg, out dummy);
        uint mine = GetCurrentThreadId();
        bool attached = false;
        if (current != 0 && current != mine)
            attached = AttachThreadInput(mine, current, true);
        BringWindowToTop(hwnd);
        bool ok = SetForegroundWindow(hwnd);
        if (!ok || GetForegroundWindow() != hwnd) {
            // Refused: the foreground lock. WinShellBar gets away with the
            // attach alone because it is a window the person just clicked;
            // this helper has no window and sent no input, so from here
            // SetForegroundWindow returns false and does nothing (measured:
            // Notepad behind Calculator, activate -> ok:false, fg unchanged).
            // SwitchToThisWindow is what Alt+Tab does and is not subject to
            // the lock; failing that, an Alt tap makes us the last process to
            // send input, which is one of the conditions that lifts it.
            SwitchToThisWindow(hwnd, true);
            ok = GetForegroundWindow() == hwnd;
            if (!ok) {
                keybd_event(VK_MENU, 0, 0, UIntPtr.Zero);
                keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
                ok = SetForegroundWindow(hwnd) && GetForegroundWindow() == hwnd;
            }
        }
        SetFocus(hwnd);
        if (attached) AttachThreadInput(mine, current, false);
        return ok;
    }

    static bool Move(IntPtr hwnd, int x, int y, int w, int h) {
        if (hwnd == IntPtr.Zero || !IsWindow(hwnd)) return false;
        // A maximized or minimized window ignores SetWindowPos geometry -- it
        // snaps back the moment anything repaints. Restore, then place.
        if (IsZoomed(hwnd) || IsIconic(hwnd)) ShowWindow(hwnd, SW_RESTORE);
        // Ask for the rectangle that puts the VISIBLE frame where the caller
        // wants it: the raw rect is larger by the invisible border.
        RECT raw, shown;
        if (GetWindowRect(hwnd, out raw) &&
            DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, out shown,
                                  Marshal.SizeOf(typeof(RECT))) == 0 &&
            shown.Right > shown.Left && shown.Bottom > shown.Top) {
            x -= shown.Left - raw.Left;
            y -= shown.Top - raw.Top;
            w += (raw.Right - raw.Left) - (shown.Right - shown.Left);
            h += (raw.Bottom - raw.Top) - (shown.Bottom - shown.Top);
        }
        return SetWindowPos(hwnd, IntPtr.Zero, x, y, w, h,
                            SWP_NOACTIVATE | SWP_NOZORDER | SWP_NOOWNERZORDER);
    }

    static bool SetState(IntPtr hwnd, int show) {
        if (hwnd == IntPtr.Zero || !IsWindow(hwnd)) return false;
        ShowWindow(hwnd, show);
        return true;
    }

    static bool Close(IntPtr hwnd) {
        if (hwnd == IntPtr.Zero || !IsWindow(hwnd)) return false;
        // Post, never Send: SendMessage blocks on the target app's "save
        // changes?" dialog, and the bridge would stop answering.
        return PostMessageW(hwnd, WM_CLOSE, IntPtr.Zero, IntPtr.Zero);
    }

    static bool Launch(string path, string args) {
        try {
            var psi = new ProcessStartInfo();
            psi.UseShellExecute = true;   // resolves shell: names and App Paths
            psi.FileName = path;
            psi.Arguments = args ?? "";
            Process.Start(psi);
            return true;
        } catch {
            return false;
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

    static string WindowJson(IntPtr h, IntPtr fg) {
        var title = new StringBuilder(512);
        GetWindowTextW(h, title, 512);
        var cls = new StringBuilder(256);
        GetClassNameW(h, cls, 256);
        uint pid; GetWindowThreadProcessId(h, out pid);
        RECT r; VisibleFrame(h, out r);
        var sb = new StringBuilder();
        sb.Append("{\"hwnd\":").Append(h.ToInt64())
          .Append(",\"pid\":").Append(pid)
          .Append(",\"title\":\"").Append(Esc(title.ToString()))
          .Append("\",\"class\":\"").Append(Esc(cls.ToString()))
          .Append("\",\"exe\":\"").Append(Esc(ExePath(pid)))
          .Append("\",\"aumid\":\"").Append(Esc(WindowAumid(h, pid, cls.ToString())))
          .Append("\",\"x\":").Append(r.Left)
          .Append(",\"y\":").Append(r.Top)
          .Append(",\"w\":").Append(r.Right - r.Left)
          .Append(",\"h\":").Append(r.Bottom - r.Top)
          .Append(",\"min\":").Append(IsIconic(h) ? "true" : "false")
          .Append(",\"max\":").Append(IsZoomed(h) ? "true" : "false")
          .Append(",\"fg\":").Append(h == fg ? "true" : "false")
          .Append("}");
        return sb.ToString();
    }

    // The list plus the foreground: `"fg"` is whatever GetForegroundWindow
    // says even when it is NOT in the list, and then `fgTitle` says what it
    // is — that is how the host learns the guest is showing a UAC prompt or an
    // elevated window it cannot represent (UIPI), instead of looking hung.
    static string ListWindows() {
        var sb = new StringBuilder();
        IntPtr fg = GetForegroundWindow();
        sb.Append("\"fg\":").Append(fg.ToInt64());
        if (fg != IntPtr.Zero && !IsManageable(fg)) {
            var t = new StringBuilder(512);
            GetWindowTextW(fg, t, 512);
            var c = new StringBuilder(256);
            GetClassNameW(fg, c, 256);
            // Furniture (the desktop, the taskbar) is not "something we
            // cannot show" — it is nothing at all.
            if (!IsShellFurniture(c.ToString()) && t.Length > 0)
                sb.Append(",\"fgTitle\":\"").Append(Esc(t.ToString())).Append("\"");
        }
        sb.Append(",\"windows\":[");
        bool first = true;
        // EnumWindows walks in z-order, topmost first — the same order a
        // taskbar and Alt+Tab show, and the order the crop needs.
        EnumWindows((h, _) => {
            if (!IsManageable(h)) return true;
            if (!first) sb.Append(",");
            first = false;
            sb.Append(WindowJson(h, fg));
            return true;
        }, IntPtr.Zero);
        sb.Append("]");
        return sb.ToString();
    }

    static string Screen() {
        uint dpi = 96;
        try { dpi = GetDpiForSystem(); } catch { }
        return "{\"x\":" + GetSystemMetrics(SM_XVIRTUALSCREEN) +
               ",\"y\":" + GetSystemMetrics(SM_YVIRTUALSCREEN) +
               ",\"w\":" + GetSystemMetrics(SM_CXVIRTUALSCREEN) +
               ",\"h\":" + GetSystemMetrics(SM_CYVIRTUALSCREEN) +
               ",\"dpi\":" + dpi + "}";
    }

    // Only the fields this helper answers on, read without a parser: the
    // protocol is small and fixed, and a hand-rolled reader that understands
    // exactly these keys cannot mis-parse another.
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
            var b = new StringBuilder();
            for (int j = i + 1; j < line.Length; j++) {
                char c = line[j];
                if (c == '\\' && j + 1 < line.Length) {
                    char n = line[++j];
                    switch (n) {
                        case 'n': b.Append('\n'); break;
                        case 'r': b.Append('\r'); break;
                        case 't': b.Append('\t'); break;
                        case 'u':
                            if (j + 4 < line.Length) {
                                b.Append((char)int.Parse(line.Substring(j + 1, 4),
                                    NumberStyles.HexNumber));
                                j += 4;
                            }
                            break;
                        default: b.Append(n); break;
                    }
                } else if (c == '"') {
                    return b.ToString();
                } else {
                    b.Append(c);
                }
            }
            return null;
        }
        int k = i;
        while (k < line.Length && line[k] != ',' && line[k] != '}') k++;
        return line.Substring(i, k - i).Trim();
    }

    static long Num(string line, string key, long dflt) {
        string s = Field(line, key);
        long v;
        if (s != null && long.TryParse(s, NumberStyles.Integer,
                                       CultureInfo.InvariantCulture, out v))
            return v;
        return dflt;
    }

    // ── the observer ────────────────────────────────────────────────────────

    static readonly object writeLock = new object();
    static TextWriter port;
    static volatile int observeInterval = 0;

    // A write while no host is attached to the channel does not pend, as the
    // PowerShell stub made it look: .NET's synchronous FileStream turns the
    // port's ERROR_IO_PENDING into an IOException ("cannot continue without
    // blocking for I/O"), and an uncaught one here killed the helper on its
    // very first line whenever it started before the desktop connected —
    // which is the normal order at logon. The bytes stay in the FileStream's
    // buffer on that failure, so dropping the exception loses nothing: they
    // go out with the next write once a host is there.
    static bool Emit(string line) {
        lock (writeLock) {
            try { port.WriteLine(line); return true; }
            catch (IOException) { return false; }
        }
    }

    // Diff by the serialised list: it carries every field the host cares
    // about, so "the string changed" is exactly "something the host would act
    // on changed", with no second notion of equality to keep in step.
    static void ObserveLoop() {
        string last = null;
        while (true) {
            int ms = observeInterval;
            if (ms <= 0) { Thread.Sleep(250); last = null; continue; }
            string now;
            try { now = ListWindows(); } catch { Thread.Sleep(ms); continue; }
            if (now != last) {
                // Not sent (no host attached): forget it, so the next poll
                // sends the full picture rather than nothing, the host that
                // eventually attaches having asked to observe first anyway.
                if (Emit("{\"event\":\"windows\"," + now + "}")) last = now;
            }
            Thread.Sleep(ms);
        }
    }

    [STAThread]
    static int Main(string[] args) {
        // Physical pixels, whatever the session's scaling: an unaware process
        // is handed virtualised coordinates at anything but 100%, and the
        // host's crop is in scanout pixels.
        try { SetProcessDPIAware(); } catch { }

        bool toStdout = Array.IndexOf(args, "--stdout") >= 0;
        if (toStdout) {
            Console.Out.WriteLine("{\"id\":0,\"ok\":true,\"screen\":" + Screen() + "," +
                                  ListWindows() + "}");
            return 0;
        }

        // OVERLAPPED, and the stream unbuffered (bufferSize 1). Two threads
        // use this one handle — the reader blocked in ReadLine, the observer
        // writing events — and on a synchronous handle the I/O manager
        // serialises them: the observer's WriteFile queues behind the pending
        // ReadFile and completes only when the host next sends something. The
        // first build had exactly that: every event after the first arrived
        // only when the desktop happened to ask for a list. An overlapped
        // handle lets the two proceed independently; unbuffered, so a write
        // never discards bytes the FileStream had read ahead.
        const uint GENERIC_RW = 0xC0000000;
        const uint FILE_FLAG_OVERLAPPED = 0x40000000;
        IntPtr h = CreateFileW(@"\\.\Global\org.starling.agent.0",
                               GENERIC_RW, 0, IntPtr.Zero, 3, FILE_FLAG_OVERLAPPED,
                               IntPtr.Zero);
        if (h == new IntPtr(-1)) {
            Console.Error.WriteLine("cannot open the port: " +
                Marshal.GetLastWin32Error() +
                " (is org.starling.agent.0 in the domain XML?)");
            return 2;
        }
        var fs = new FileStream(new SafeFileHandle(h, true), FileAccess.ReadWrite,
                                1, true);
        // AutoFlush, because a line the host never sees is the same as a line
        // never written, and virtio-serial gives no push-back to notice it by.
        port = new StreamWriter(fs) { AutoFlush = true };
        var r = new StreamReader(fs);

        var observer = new Thread(ObserveLoop) { IsBackground = true };
        observer.Start();

        Emit("{\"event\":\"helper-up\",\"helper\":\"" + Version + "\"}");
        string line;
        while (true) {
            try { line = r.ReadLine(); }
            catch (IOException) { Thread.Sleep(500); continue; }
            if (line == null) { Thread.Sleep(500); continue; }
            if (line.Length == 0) continue;
            string op = Field(line, "op");
            string id = Field(line, "id") ?? "0";
            string head = "{\"id\":" + id;
            switch (op) {
                case "hello":
                    Emit(head + ",\"ok\":true,\"helper\":\"" + Version +
                         "\",\"screen\":" + Screen() + "}");
                    break;
                case "list_windows":
                    Emit(head + ",\"ok\":true," + ListWindows() + "}");
                    break;
                case "apps":
                    Emit(head + ",\"ok\":true,\"apps\":" + Apps() + "}");
                    break;
                case "observe":
                    observeInterval = (int)Num(line, "interval", 100);
                    Emit(head + ",\"ok\":true,\"interval\":" + observeInterval + "}");
                    break;
                case "activate":
                case "close":
                case "minimize":
                case "maximize":
                case "restore":
                case "move": {
                    var hwnd = new IntPtr(Num(line, "hwnd", 0));
                    bool ok;
                    switch (op) {
                        case "activate": ok = Activate(hwnd); break;
                        case "close":    ok = Close(hwnd); break;
                        case "minimize": ok = SetState(hwnd, SW_MINIMIZE); break;
                        case "maximize": ok = SetState(hwnd, SW_MAXIMIZE); break;
                        case "restore":  ok = SetState(hwnd, SW_RESTORE); break;
                        default:
                            ok = Move(hwnd, (int)Num(line, "x", 0), (int)Num(line, "y", 0),
                                      (int)Num(line, "w", 0), (int)Num(line, "h", 0));
                            break;
                    }
                    Emit(head + ",\"ok\":" + (ok ? "true" : "false") + "}");
                    break;
                }
                case "launch": {
                    string path = Field(line, "path");
                    bool ok = path != null && Launch(path, Field(line, "args"));
                    Emit(head + ",\"ok\":" + (ok ? "true" : "false") + "}");
                    break;
                }
                case "quit":
                    Emit(head + ",\"ok\":true}");
                    return 0;
                default:
                    Emit(head + ",\"ok\":false,\"error\":\"" +
                         Esc("no such op: " + (op ?? "?")) + "\"}");
                    break;
            }
        }
        return 0;
    }
}
