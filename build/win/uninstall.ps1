# Starling desktop for Windows — uninstaller.
#
# Puts the machine back the way it was: Explorer is the shell again, its
# taskbar is visible again, and the files are gone. Nothing here needs an
# administrator either, for the same reason the installer does not.
param(
    [string]$Destination = "$env:LOCALAPPDATA\Programs\Starling",
    # Leave the files, just stop being the shell.
    [switch]$KeepFiles
)
$ErrorActionPreference = 'Continue'

$exe = Join-Path $Destination 'WinShellBar.exe'

if (Test-Path $exe) {
    # Un-register FIRST, while the binary that owns the value is still there:
    # deleting the files and then trying to undo the registration leaves a
    # Winlogon\Shell pointing at nothing, which signs you into a black screen.
    & $exe --unregister-shell
    # Give Explorer's taskbar back before stopping our dock -- our dock hides
    # it rather than closing it, so stopping first leaves a desktop with
    # neither bar until the next sign-in.
    & $exe --restore-taskbar
}

Get-Process WinShellBar -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

if ((Get-Process explorer -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) {
    Start-Process explorer.exe
    Start-Sleep -Seconds 5
}

if (-not $KeepFiles) {
    # The uninstaller is running FROM the directory it is deleting when it was
    # started by the installed copy, so the last step is scheduled rather than
    # done here: a directory cannot delete the script reading it.
    $cmd = "Start-Sleep -Seconds 3; Remove-Item -LiteralPath '$Destination' -Recurse -Force -ErrorAction SilentlyContinue"
    Start-Process powershell -ArgumentList '-NoProfile','-WindowStyle','Hidden','-Command',$cmd
    Write-Host "Removing $Destination"
}

Write-Host "Explorer is the shell again. Sign out and back in to be sure of a clean session."
