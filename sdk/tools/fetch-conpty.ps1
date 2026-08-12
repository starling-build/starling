# Fetch the ConPTY host we run instead of the inbox conhost.exe.
#
#   tools\fetch-conpty.ps1 [-Dest <dir>] [-Version 1.24.260710001]
#
# Why we ship our own host at all: CreatePseudoConsole() always launches
# %SystemRoot%\System32\conhost.exe, and profiling put 7.27 CPU-seconds of a
# 9.73 s run in it where Windows Terminal's OpenConsole.exe cost 2.23 for the
# same stream (docs/perf/terminal-windows-readpath-2026-08-11/). OpenConsole is
# the same console host, built from microsoft/terminal and years newer than
# whatever the OS shipped.
#
# Source is the MIT-licensed Microsoft.Windows.Console.ConPTY package on
# nuget.org -- the same one node-pty (and so VS Code) uses. A .nupkg is a zip,
# so no NuGet client is required. Do NOT copy these out of an installed
# Windows Terminal or VS Code: same bits, no provenance.
#
# Two files land in -Dest and must stay together: conpty.dll finds
# OpenConsole.exe relative to its own module.
[CmdletBinding()]
param(
    [string]$Dest = '',
    [string]$Version = '1.24.260710001',
    # Optional: also copy the pair next to a built executable, which is the
    # layout the loader expects. Typically
    #   -Stage apps\TerminalApp\.build\x86_64-unknown-windows-msvc\release
    [string]$Stage = ''
)
$ErrorActionPreference = 'Stop'

if (-not $Dest) {
    $Dest = Join-Path (Split-Path -Parent $PSScriptRoot) 'Vendor\conpty'
}
New-Item -ItemType Directory -Path $Dest -Force | Out-Null

$pkg = "microsoft.windows.console.conpty"
$url = "https://www.nuget.org/api/v2/package/$pkg/$Version"
$tmp = Join-Path $env:TEMP "conpty-$Version.zip"
$work = Join-Path $env:TEMP "conpty-$Version"

Write-Host "==> $url"
Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing

Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive -Path $tmp -DestinationPath $work -Force

# The package lays runtimes out per-architecture; take x64 and be explicit
# about it rather than grabbing the first match of each name.
$dll = Get-ChildItem $work -Recurse -Filter 'conpty.dll' |
    Where-Object { $_.FullName -match 'x64' } | Select-Object -First 1
$exe = Get-ChildItem $work -Recurse -Filter 'OpenConsole.exe' |
    Where-Object { $_.FullName -match 'x64' } | Select-Object -First 1
if (-not $dll -or -not $exe) {
    Write-Host 'Package layout changed -- x64 conpty.dll / OpenConsole.exe not found in:'
    Get-ChildItem $work -Recurse -Include '*.dll', '*.exe' |
        ForEach-Object { '  ' + $_.FullName.Substring($work.Length + 1) }
    throw 'fetch-conpty: could not locate the runtime files'
}

Copy-Item $dll.FullName (Join-Path $Dest 'conpty.dll') -Force
Copy-Item $exe.FullName (Join-Path $Dest 'OpenConsole.exe') -Force
$lic = Get-ChildItem $work -Recurse -Include 'LICENSE*', '*.md' |
    Where-Object { $_.Name -match 'LICENSE' } | Select-Object -First 1
if ($lic) { Copy-Item $lic.FullName (Join-Path $Dest 'LICENSE') -Force }

foreach ($f in @('conpty.dll', 'OpenConsole.exe')) {
    $i = Get-Item (Join-Path $Dest $f)
    "{0,-18} {1,9:N0} bytes  v{2}" -f $i.Name, $i.Length, $i.VersionInfo.FileVersion
}
if ($Stage) {
    if (-not (Test-Path $Stage)) { throw "fetch-conpty: -Stage path does not exist: $Stage" }
    Copy-Item (Join-Path $Dest 'conpty.dll') $Stage -Force
    Copy-Item (Join-Path $Dest 'OpenConsole.exe') $Stage -Force
    Write-Host "staged beside the executable in $Stage"
} else {
    Write-Host "conpty staged in $Dest -- copy BOTH beside the app executable, or re-run with -Stage."
}
