# "Starling on Windows, through WSL" -- a recorded walkthrough.
#
# Everything here is the real thing: the .deb really installs, the desktop
# really starts, and Windows' own Remote Desktop really connects to it.
# Nothing is faked and nothing is sped up.
#
# CAPTURE IS A 1920x1080 REGION, not the 4K screen scaled down. Scaling a 4K
# desktop into 1080p makes console text unreadable, which for a walkthrough is
# the whole content. Every window is placed inside that region instead.
#
# ORDER MATTERS: every wsl.exe launch steals the foreground, and once mstsc has
# lost it the session looks frozen though it is fine. So all the WSL work
# happens BEFORE Remote Desktop opens, and nothing touches wsl.exe after.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public struct RECT { public int L, T, R, B; }
public struct POINT { public int X, Y; }
public class W {
    [DllImport("shcore.dll")] public static extern int SetProcessDpiAwareness(int v);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h,int x,int y,int w,int t,bool r);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint x,uint y,uint d,IntPtr e);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
}
"@
try { [W]::SetProcessDpiAwareness(2) | Out-Null } catch { }

$out = "C:\dist\vid"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$marks = "$out\marks.txt"; Remove-Item $marks -ErrorAction SilentlyContinue

# The capture window, and where the action is placed inside it.
# The region is the screen's top-left, because that is where mstsc puts its
# session window and it will not be moved: MoveWindow succeeds and the window
# snaps straight back, 25 tries running. Cheaper to record where it lands than
# to fight it, so the console goes here too.
$RX = 0; $RY = 0; $RW = 1920; $RH = 1080

function Mark($n) {
    Add-Content $marks ("$n " + [int][double]::Parse((Get-Date -UFormat %s))); "[mark] $n"
}
function TypeText($t, $ms = 42) {
    foreach ($c in $t.ToCharArray()) {
        [System.Windows.Forms.SendKeys]::SendWait([regex]::Replace($c, '[+^%~(){}\[\]]', '{$0}'))
        Start-Sleep -Milliseconds $ms
    }
}
function Enter() { [System.Windows.Forms.SendKeys]::SendWait("{ENTER}") }
function Shot($n) {
    $bmp = New-Object System.Drawing.Bitmap $RW, $RH
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($RX, $RY, 0, 0, $bmp.Size)
    $bmp.Save("$out\$n.png", [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}
function Click($x, $y) {
    [W]::SetCursorPos($x, $y) | Out-Null
    Start-Sleep -Milliseconds 900          # the dock wants a hover first
    [W]::mouse_event(0x02,0,0,0,[IntPtr]::Zero); Start-Sleep -Milliseconds 90
    [W]::mouse_event(0x04,0,0,0,[IntPtr]::Zero)
}

# A console font a viewer can actually read. Affects consoles opened after it.
reg add "HKCU\Console" /v FontSize /t REG_DWORD /d 1310720 /f | Out-Null
reg add "HKCU\Console" /v FaceName /t REG_SZ /d "Consolas" /f | Out-Null

# ---- stage ------------------------------------------------------------------
Get-Process mstsc,mspaint,SystemSettings -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
(New-Object -ComObject Shell.Application).Windows() | ForEach-Object { try { $_.Quit() } catch {} }
Start-Sleep -Seconds 2
(New-Object -ComObject Shell.Application).MinimizeAll()
Start-Sleep -Seconds 3

# ---- roll -------------------------------------------------------------------
$mp4 = "$out\wsl-walkthrough.mp4"
Remove-Item $mp4 -ErrorAction SilentlyContinue
$ff = Start-Process ffmpeg.exe -PassThru -WindowStyle Hidden -ArgumentList @(
    "-y","-f","gdigrab","-framerate","30",
    "-offset_x","$RX","-offset_y","$RY","-video_size","${RW}x${RH}","-i","desktop",
    "-t","195","-c:v","libx264","-preset","veryfast","-crf","21",
    "-pix_fmt","yuv420p", $mp4)
Start-Sleep -Seconds 3
Mark start

# ---- 1. what WSL has --------------------------------------------------------
Start-Process powershell.exe -ArgumentList "-NoProfile","-NoExit","-Command","Clear-Host"
Start-Sleep -Seconds 4
$ps = Get-Process powershell | Where-Object { $_.MainWindowTitle -ne "" } | Select-Object -First 1
[W]::MoveWindow($ps.MainWindowHandle, 0, 22, 1616, 939, $true) | Out-Null
[W]::SetForegroundWindow($ps.MainWindowHandle) | Out-Null
Start-Sleep -Seconds 2
Mark beat1
TypeText "wsl -l -v"; Enter
Start-Sleep -Seconds 6

# ---- 2. install the desktop inside WSL --------------------------------------
Mark beat2
TypeText "wsl -d Ubuntu-26.04 -u root dpkg -i /mnt/c/dist/starling-gate.deb"; Enter
Start-Sleep -Seconds 26

# ---- 3. start it ------------------------------------------------------------
Mark beat3
TypeText "wsl -d Ubuntu-26.04 -u root bash /mnt/c/dist/wsl-start-fluent.sh"; Enter
Start-Sleep -Seconds 30

# ---- 4. connect with Windows' own Remote Desktop ----------------------------
Mark beat4
TypeText "mstsc /v:127.0.0.1:3390 /w:1600 /h:900"; Enter
Start-Sleep -Seconds 14
# Take mstsc where it lands. It puts its session window at the screen's
# top-left and refuses to be moved -- MoveWindow returns true and the window
# snaps back -- so the capture region was put there instead. All that is
# needed here is the client origin, once the session is really up.
$cx = 0; $cy = 0; $placed = $false
for ($try = 1; $try -le 25; $try++) {
    $m = Get-Process mstsc -ErrorAction SilentlyContinue |
         Where-Object { $_.MainWindowTitle -like "*Remote Desktop*" } | Select-Object -First 1
    if ($m -and $m.MainWindowHandle -ne [IntPtr]::Zero) {
        [W]::SetForegroundWindow($m.MainWindowHandle) | Out-Null
        $pt = New-Object POINT
        [W]::ClientToScreen($m.MainWindowHandle, [ref]$pt) | Out-Null
        $r = New-Object RECT
        [W]::GetClientRect($m.MainWindowHandle, [ref]$r) | Out-Null
        if (($r.R - $r.L) -ge 1500) {
            $cx = $pt.X; $cy = $pt.Y; $placed = $true
            "session up: client origin $cx,$cy size $($r.R-$r.L)x$($r.B-$r.T) (try $try)"
            break
        }
    }
    Start-Sleep -Seconds 1
}
if (-not $placed) { "COULD NOT PLACE the Remote Desktop window"; }
Start-Sleep -Seconds 3
Mark connected

# ---- 5. use it --------------------------------------------------------------
# Wake it: the desktop screensaves when left alone, exactly as it should.
[W]::SetCursorPos(($cx+800), ($cy+450)) | Out-Null
Start-Sleep -Milliseconds 500
[W]::SetCursorPos(($cx+840), ($cy+500)) | Out-Null
Start-Sleep -Seconds 4
Mark beat5
Shot "v-desktop"
# Slot centres reported by the desktop itself (agent broker, dock_rects):
# launcher 618, files 722, terminal 774 -- all at y=872.
# Open Start, so the viewer sees what is installed...
Click ($cx+618) ($cy+872)
Start-Sleep -Seconds 6
Shot "v-start"
# ...close it, then launch from the taskbar. Clicking a taskbar tile while
# Start is open only dismisses Start -- the click never reaches the tile.
[System.Windows.Forms.SendKeys]::SendWait("{ESC}")
Start-Sleep -Seconds 3
Click ($cx+722) ($cy+872)
Start-Sleep -Seconds 16
Shot "v-app"
Start-Sleep -Seconds 8
Mark done

# ---- stop -------------------------------------------------------------------
# Let -t expire: a killed ffmpeg never writes the moov atom.
$ff.WaitForExit(90000) | Out-Null
"recorded: " + (Get-Item $mp4 -ErrorAction SilentlyContinue).Length + " bytes"
Get-Content $marks
