# Assemble a runnable, distributable Windows app directory from a build.
#
#   tools\stage-windows.ps1 -PackagePath ..\apps\TerminalApp -Product TerminalApp
#                           [-Out C:\dist\TerminalApp] [-Configuration release] [-Zip]
#
# This is the single definition of the Windows app layout, the counterpart of
# build/stage.sh on Linux. Change assembly HERE, never in a packaging step that
# copies files itself, or a shipped app quietly diverges from what was tested.
#
# The layout, and why each part is in it:
#
#   <out>\
#     <Product>.exe                     the build
#     *.dll                             Swift runtime (32), engine (2), conpty
#     OpenConsole.exe                   the console host we run instead of the
#                                       inbox conhost -- see fetch-conpty.ps1
#     data\icudtl.dat                   engine ICU data
#     data\flutter_assets\              engine assets
#     FlutterSwift_*.resources\         font + icon bundles emitted by the build
#
# `data\` beside the executable is a contract, not a convention: ExampleHost's
# ensureEngineData() returns immediately when data\icudtl.dat exists, and
# otherwise tries to copy from an engine checkout. A staged app must therefore
# carry it, or it only runs on a machine that has the source tree.
#
# Every DLL must sit beside the exe. Windows resolves imports from the
# executable's directory, and the Swift runtime is NOT on a default search
# path -- an app missing them dies with STATUS_DLL_NOT_FOUND (0xC0000135)
# before main(), which looks like a crash with no message at all.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PackagePath,
    [Parameter(Mandatory = $true)][string]$Product,
    [ValidateSet('debug', 'release')][string]$Configuration = 'release',
    [string]$Out = '',
    [string]$EngineOut = '',
    [string]$SwiftRuntime = '',
    [switch]$Zip
)
$ErrorActionPreference = 'Stop'

$sdk = Split-Path -Parent $PSScriptRoot
$pkg = (Resolve-Path $PackagePath).Path
$build = Join-Path $pkg ".build\x86_64-unknown-windows-msvc\$Configuration"
if (-not (Test-Path (Join-Path $build "$Product.exe"))) {
    throw "stage-windows: no $Product.exe in $build -- build first (tools\build-windows.ps1)"
}
if (-not $Out) { $Out = Join-Path $pkg "dist\$Product" }

# --- engine -----------------------------------------------------------------
# Two layouts, because a release build takes its engine from an SDK bundle
# rather than an engine checkout:
#
#   engine checkout   out\host_release\{flutter_engine.dll, icudtl.dat, ...}
#   SDK bundle        engine\lib\*.dll  +  engine\share\{icudtl.dat, flutter_assets}
#
# The bundle splits link-time from run-time data, so icudtl.dat is a directory
# away from the DLLs and the old check rejected a perfectly good bundle with
# "set -EngineOut to an engine out dir containing icudtl.dat". Detect the split
# instead of demanding the flat shape.
if (-not $EngineOut) { $EngineOut = $env:STARLING_ENGINE_OUT }
if (-not $EngineOut) { $EngineOut = $env:FLUTTER_SWIFT_ENGINE_OUT }
if (-not $EngineOut) {
    throw "stage-windows: set -EngineOut (or STARLING_ENGINE_OUT) to an engine out dir, or an SDK bundle's engine\lib"
}
$engineShare = Join-Path (Split-Path -Parent $EngineOut) 'share'
$bundleLayout = Test-Path (Join-Path $engineShare 'icudtl.dat')
if (-not $bundleLayout -and -not (Test-Path (Join-Path $EngineOut 'icudtl.dat'))) {
    throw "stage-windows: no icudtl.dat in $EngineOut, nor in $engineShare (bundle layout)"
}
# Where the run-time data actually is, under whichever layout.
$dataSrc = if ($bundleLayout) { $engineShare } else { $EngineOut }
# In bundle mode the bundle is also where flutter_assets and conpty come from --
# staging a release against a bundle must not reach back into a source tree that
# may not exist, and on a build box that does have one would silently mix the
# two. The bundle root is engine\lib\..\..
$bundleRoot = if ($bundleLayout) { Split-Path -Parent (Split-Path -Parent $EngineOut) } else { '' }

# --- swift runtime ----------------------------------------------------------
# Not on any default search path, so the whole bin\ goes beside the exe. It
# also carries the MSVC CRT redistributables, so no separate redist copy.
if (-not $SwiftRuntime) {
    $roots = @("$env:LOCALAPPDATA\Programs\Swift\Runtimes", "$env:ProgramFiles\Swift\Runtimes")
    $cand = foreach ($r in $roots) {
        if (Test-Path $r) { Get-ChildItem $r -Directory | Sort-Object Name -Descending }
    }
    foreach ($c in $cand) {
        $b = Join-Path $c.FullName 'usr\bin'
        if (Test-Path $b) { $SwiftRuntime = $b; break }
    }
}
if (-not $SwiftRuntime -or -not (Test-Path $SwiftRuntime)) {
    throw "stage-windows: could not find the Swift runtime bin -- pass -SwiftRuntime"
}

# --- conpty -----------------------------------------------------------------
# A bundle carries its own copy, so a release stage needs no network and cannot
# pick up a different build than the SDK it came from. Outside bundle mode it is
# fetched into the source tree, where it is gitignored.
$vendor = if ($bundleLayout -and (Test-Path (Join-Path $bundleRoot 'Vendor\conpty\conpty.dll'))) {
    Join-Path $bundleRoot 'Vendor\conpty'
} else {
    Join-Path $sdk 'Vendor\conpty'
}
if (-not (Test-Path (Join-Path $vendor 'conpty.dll'))) {
    Write-Host '==> conpty not vendored yet, fetching'
    & (Join-Path $PSScriptRoot 'fetch-conpty.ps1') -Dest $vendor
}

# --- assemble ---------------------------------------------------------------
Remove-Item $Out -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $Out -Force | Out-Null

Copy-Item (Join-Path $build "$Product.exe") $Out -Force
Get-ChildItem $build -Directory -Filter '*.resources' | ForEach-Object {
    Copy-Item $_.FullName $Out -Recurse -Force
}
Copy-Item (Join-Path $SwiftRuntime '*.dll') $Out -Force
foreach ($d in @('flutter_windows.dll', 'flutter_engine.dll')) {
    $p = Join-Path $EngineOut $d
    if (Test-Path $p) { Copy-Item $p $Out -Force }
}
Copy-Item (Join-Path $vendor 'conpty.dll') $Out -Force
Copy-Item (Join-Path $vendor 'OpenConsole.exe') $Out -Force

$data = Join-Path $Out 'data'
New-Item -ItemType Directory -Path $data -Force | Out-Null
Copy-Item (Join-Path $dataSrc 'icudtl.dat') $data -Force
# In bundle mode the assets ship beside icudtl.dat; otherwise they come from the
# framework's vendored copy in the source tree.
$assets = if ($bundleLayout) { Join-Path $dataSrc 'flutter_assets' }
          else { Join-Path $sdk 'Resources\flutter_assets' }
if (-not (Test-Path $assets)) { throw "stage-windows: no flutter_assets at $assets" }
Copy-Item $assets $data -Recurse -Force

# --- verify -----------------------------------------------------------------
# Assert the contract rather than trusting the copies: a staged app that is
# missing one DLL fails before main() with no diagnostic.
$problems = @()
if (-not (Test-Path (Join-Path $Out "$Product.exe"))) { $problems += 'exe missing' }
if (-not (Test-Path (Join-Path $Out 'data\icudtl.dat'))) { $problems += 'data\icudtl.dat missing' }
if (-not (Test-Path (Join-Path $Out 'data\flutter_assets'))) { $problems += 'data\flutter_assets missing' }
foreach ($must in @('swiftCore.dll', 'Foundation.dll', 'vcruntime140.dll',
                    'flutter_windows.dll', 'conpty.dll')) {
    if (-not (Test-Path (Join-Path $Out $must))) { $problems += "$must missing" }
}
if (-not (Test-Path (Join-Path $Out 'OpenConsole.exe'))) {
    $problems += 'OpenConsole.exe missing (conpty.dll finds it beside itself)'
}
if ($problems.Count) {
    $problems | ForEach-Object { Write-Host "  FAIL: $_" }
    throw 'stage-windows: staged tree is incomplete'
}

$dllCount = (Get-ChildItem $Out -Filter *.dll).Count
$size = (Get-ChildItem $Out -Recurse -File | Measure-Object -Property Length -Sum).Sum
Write-Host ("staged {0}" -f $Out)
Write-Host ("  {0} dlls, data + {1} resource bundles, {2:N1} MB" -f `
    $dllCount, (Get-ChildItem $Out -Directory -Filter '*.resources').Count, ($size / 1MB))

if ($Zip) {
    $zipPath = "$Out.zip"
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    # Entries are written one at a time with forward-slash names, NOT by
    # ZipFile.CreateFromDirectory: on Windows PowerShell 5.1 that helper writes
    # the separator verbatim, so every nested path lands as `data\icudtl.dat`.
    # The ZIP spec says forward slash, and Windows' own tools tolerate the
    # backslash form, so the archive looks fine here and then extracts as one
    # long flat filename on Linux and macOS. (Compress-Archive is not the
    # answer either -- see the PowerShell authoring notes.)
    # NB: not $zip -- PowerShell variables are case-insensitive, so that would
    # be the [switch]$Zip parameter and assigning a ZipArchive to it throws
    # "Cannot convert ... to SwitchParameter" at bind time.
    $archive = [System.IO.Compression.ZipFile]::Open($zipPath, 'Create')
    try {
        $root = (Resolve-Path $Out).Path.TrimEnd('\') + '\'
        foreach ($f in (Get-ChildItem $Out -Recurse -File)) {
            $name = $f.FullName.Substring($root.Length).Replace('\', '/')
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive, $f.FullName, $name, 'Optimal')
        }
    } finally {
        $archive.Dispose()
    }

    # Assert it, so the separator bug cannot come back silently.
    $check = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $bad = @($check.Entries | Where-Object { $_.FullName -like '*\*' }).Count
        $hasData = @($check.Entries | Where-Object { $_.FullName -eq 'data/icudtl.dat' }).Count
        if ($bad -gt 0) { throw "stage-windows: $bad zip entries use backslash separators" }
        if ($hasData -ne 1) { throw 'stage-windows: data/icudtl.dat missing from the zip' }
        $entries = $check.Entries.Count
    } finally {
        $check.Dispose()
    }
    Write-Host ("  zip {0} ({1:N1} MB, {2} entries, separators verified)" -f `
        $zipPath, ((Get-Item $zipPath).Length / 1MB), $entries)
}
