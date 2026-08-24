# Starling desktop for Windows — installer.
#
# Shipped INSIDE the package and run from it, the same way build/session/'s
# files are installed verbatim on Linux: edit it here, never re-inline it as a
# heredoc in the packager, or a built package ships a stale copy.
#
# PER-USER, and no administrator anywhere. That is not a compromise, it is
# what the shell already is: Windows reads the shell for a session from
# HKCU\Software\Microsoft\Windows NT\CurrentVersion\Winlogon\Shell, so one
# account opts in and every other account on the machine still gets Explorer.
# Nothing here writes to HKLM, Program Files, or a service.
param(
    # Where the desktop lands. Per-user by default; nothing outside it is
    # touched except the one registry value below.
    [string]$Destination = "$env:LOCALAPPDATA\Programs\Starling",
    # Switch to it now as well as at the next logon: stop Explorer, start
    # Starling in this session. Without it the change takes effect when you
    # next sign in, which is the reversible way to try it.
    [switch]$Now,
    # Install the files and DO NOT register as the shell. For running it
    # beside Explorer, or for a machine you are only staging.
    [switch]$NoRegister
)
$ErrorActionPreference = 'Stop'

$source = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe = Join-Path $Destination 'WinShellBar.exe'

Write-Host "Starling -> $Destination"

# A running copy holds its own exe open, so stop one before overwriting it --
# otherwise the copy fails halfway and leaves a tree that is half of each
# build.
Get-Process WinShellBar -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

New-Item -ItemType Directory -Force -Path $Destination | Out-Null
Copy-Item (Join-Path $source '*') $Destination -Recurse -Force -Exclude 'Install.ps1','Uninstall.ps1'
Copy-Item (Join-Path $source 'Uninstall.ps1') $Destination -Force

if (-not (Test-Path $exe)) { throw "WinShellBar.exe is missing from $Destination" }
$size = (Get-ChildItem $Destination -Recurse -File | Measure-Object -Property Length -Sum).Sum
Write-Host ("  {0:N0} files, {1:N1} MB" -f (Get-ChildItem $Destination -Recurse -File).Count, ($size / 1MB))

if ($NoRegister) {
    Write-Host "Installed. Not registered as the shell (-NoRegister)."
    Write-Host "Run it beside Explorer with:  `"$exe`""
    exit 0
}

# The registration itself is the exe's own job -- it writes the value it will
# be started by, so the path can never disagree with the binary that wrote it.
& $exe --register-shell
if ($LASTEXITCODE -ne 0) { throw "registering the shell failed" }

Write-Host ""
Write-Host "Installed and registered for $env:USERNAME."
Write-Host "It takes effect at your next sign-in. To undo:"
Write-Host "  powershell -File `"$Destination\Uninstall.ps1`""
Write-Host ""
Write-Host "If the shell ever fails to start, it un-registers ITSELF: the"
Write-Host "supervisor deletes that same registry value after a crash loop,"
Write-Host "so the next sign-in gets Explorer back without a recovery console."

if ($Now) {
    Write-Host ""
    Write-Host "Switching this session over..."
    # Explorer's taskbar is hidden by our dock rather than closed, so put it
    # back first: stopping Explorer with the bar still hidden leaves a desktop
    # with neither.
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-Process -FilePath $exe -ArgumentList '--session'
    Start-Sleep -Seconds 8
    $running = (Get-Process WinShellBar -ErrorAction SilentlyContinue | Measure-Object).Count
    Write-Host "  WinShellBar processes: $running"
    if ($running -eq 0) {
        Write-Warning "it did not start; restarting Explorer"
        Start-Process explorer.exe
    }
}
