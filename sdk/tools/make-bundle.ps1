# Assemble a self-contained Starling SDK distribution for Windows: the framework
# source plus the engine binaries it links against, in one tree. The Windows
# counterpart of tools/make-bundle.sh, and deliberately the same layout, so a
# consumer's Package.swift differs only in which host product it imports.
#
#   tools\make-bundle.ps1 [-Configuration release|debug] [-OutDir <dir>]
#
# Produces <OutDir>\starling-sdk-windows-<arch>\ and a .zip of it. A consumer
# unpacks that and depends on it by path:
#
#   .package(path: "C:/starling-sdk-windows-x86_64")
#
# and needs no engine checkout and no configuration - Package.swift probes for
# engine/lib inside the bundle (candidate 1 on every platform).
#
# WHY A PATH DEPENDENCY AND NOT A VERSIONED ONE. Same reason as the Linux
# bundle: locating the bundled engine needs -L, which SwiftPM classes as
# .unsafeFlags and rejects for dependencies resolved by URL+version. See the
# header of make-bundle.sh for the full argument.
#
# WHAT SHIPS, AND WHAT DELIBERATELY DOES NOT. Both DLLs travel with their import
# libraries, because on Windows the link step needs flutter_engine.dll.lib /
# flutter_windows.dll.lib while the run needs the DLLs themselves. The Swift
# runtime DLLs do NOT travel: they belong to the consumer's toolchain, exactly
# as libswiftCore does on Linux. That matters at *deployment* time rather than
# build time, so the README says so - an app copied to a machine without the
# toolchain dies with STATUS_DLL_NOT_FOUND (0xC0000135) before main().
[CmdletBinding()]
param(
    [ValidateSet('release', 'debug')]
    [string]$Configuration = 'release',
    [string]$OutDir = "$env:TEMP\starling-sdk-bundle",
    # Where the engine was built. Same override name the manifest reads.
    [string]$EngineOut = ''
)

# THIS FILE IS DELIBERATELY PURE ASCII. Windows PowerShell 5.1 reads a .ps1
# with no BOM using the ANSI codepage, so a UTF-8 em-dash arrives as U+201D --
# and PowerShell accepts smart quotes as string delimiters, so every em-dash
# silently opens a string. The result is a parse error blaming a brace far away
# from the real text. Use '-', not an em-dash, anywhere in this file.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$sdk = Split-Path -Parent $PSScriptRoot

# The engine checkout is not at a fixed offset once this package is standalone;
# same candidates as tools/make-bundle.sh and tools/sync-vendored-headers.sh.
if (-not $EngineOut) { $EngineOut = $env:FLUTTER_SWIFT_ENGINE_OUT }
if (-not $EngineOut) {
    foreach ($root in @("$sdk\..\engine", "$sdk\..\starling-engine\engine")) {
        if (Test-Path "$root\src") {
            $EngineOut = "$root\src\out\host_$Configuration"
            break
        }
    }
}
if (-not $EngineOut -or -not (Test-Path $EngineOut)) {
    Write-Error "no engine output directory found (tried '$EngineOut'); build the engine first or pass -EngineOut"
}
$EngineOut = (Resolve-Path $EngineOut).Path

$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x86_64' }
$name = "starling-sdk-windows-$arch"
$dest = Join-Path $OutDir $name

# The four engine artifacts, all required. A missing import library fails the
# consumer's *link*; a missing DLL fails at *startup*, which is much harder to
# read - so refuse here rather than ship a bundle that cannot work.
$engineFiles = @(
    'flutter_engine.dll',       # the engine core, with the Swift bridge merged in
    'flutter_engine.dll.lib',   # its import library - what -lflutter_engine.dll resolves to
    'flutter_windows.dll',      # the Win32 embedder, what FlutterWin32Bridge binds
    'flutter_windows.dll.lib'
)
# NOTE ON STRING BUILDING, here and for the README below: no @"..."@
# here-strings anywhere in this script. Windows PowerShell 5.1 fails to
# terminate a here-string in a file with LF-only line endings, and this file
# reaches a Windows machine by tar, by zip, or by git with core.autocrlf=false
# - none of which guarantee CRLF. The failure is a parse error pointing at a
# brace hundreds of lines away from the actual here-string, so it reads as
# unbalanced code rather than "wrong newlines". Arrays joined with a newline
# behave identically regardless.
foreach ($f in $engineFiles) {
    if (-not (Test-Path (Join-Path $EngineOut $f))) {
        Write-Error (@(
            "$EngineOut\$f is missing.",
            'Build it with:',
            "    ninja -C out\host_$Configuration flutter_engine flutter_windows"
        ) -join [Environment]::NewLine)
    }
}

# Refuse to ship headers that have drifted from the engine we are bundling: the
# vendored bridge headers describe that binary's ABI. The checker is a shell
# script, so this needs the bash that Git for Windows installs; when there is
# none, warn rather than fail - the check is a safety net, not the build.
# Find Git for Windows' bash SPECIFICALLY, not whatever answers to "bash".
# On any machine with WSL installed, Get-Command bash returns
# C:\WINDOWS\system32\bash.exe -- the WSL launcher, whose filesystem has no
# C:\ at all (the same path is /mnt/c/... in there). It then fails with
# "No such file or directory" and the Write-Error below reports that as
# vendored-header drift, which sends you looking at headers for what is
# really a wrong-interpreter problem.
$bash = $null
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if ($gitCmd) {
    $cand = Join-Path (Split-Path (Split-Path $gitCmd.Source -Parent) -Parent) 'bin\bash.exe'
    if (Test-Path $cand) { $bash = $cand }
}
if (-not $bash) {
    foreach ($c in @("$env:ProgramFiles\Git\bin\bash.exe", "${env:ProgramFiles(x86)}\Git\bin\bash.exe")) {
        if (Test-Path $c) { $bash = $c; break }
    }
}
if ($bash) {
    # Forward slashes, because bash reads each backslash in an argument as an
    # escape: the native path arrives as C:Usersstarlingdevstarlingsdk/tools/...
    $checker = ($sdk -replace '\\', '/') + '/tools/sync-vendored-headers.sh'
    # Tell it which engine, rather than letting it guess. Its fallbacks are an
    # `engine` symlink beside the package and a starling-engine clone beside
    # the package -- neither exists on Windows, where bootstrap.sh has not run
    # and the engine is a sibling of the *repo*. We already know the answer:
    # $EngineOut is <root>/engine/src/out/<config>, so the engine root it wants
    # (the directory holding src/) is three levels up.
    $engineRoot = Split-Path (Split-Path (Split-Path $EngineOut -Parent) -Parent) -Parent
    $checkOut = & $bash $checker --check ($engineRoot -replace '\\', '/') 2>&1
    $checkCode = $LASTEXITCODE
    # Only exit 1 means drift. Anything else means the checker did not run, and
    # reporting that as drift is actively misleading -- it has sent three
    # separate investigations at the headers when the real causes were a
    # wrong bash, a CRLF checkout, and swiftc missing from PATH (the script
    # reads the toolchain's resource dir via `swiftc -print-target-info`).
    if ($checkCode -eq 1) {
        $checkOut | ForEach-Object { Write-Host "  $_" }
        Write-Error "vendored headers have drifted from the engine tree; run tools/sync-vendored-headers.sh and rebuild before bundling"
    } elseif ($checkCode -ne 0) {
        $checkOut | ForEach-Object { Write-Host "  $_" }
        Write-Error "the vendored-header check could not run (exit $checkCode); it needs Git bash and swiftc on PATH -- this is not a drift report"
    }
} else {
    Write-Warning "no Git for Windows bash found - skipping the vendored-header drift check"
}

if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
New-Item -ItemType Directory -Force -Path "$dest\engine\lib", "$dest\engine\share" | Out-Null

# --- framework source -------------------------------------------------------
# Sources/, Examples/, Tests/ and tools/ go as-is. .build is deliberately
# excluded - a consumer's toolchain differs from ours. Examples/ must ship: the
# manifest declares those target paths, and SwiftPM refuses to parse a manifest
# whose target directories are missing. README.md is not copied; the bundle gets
# its own, written below.
foreach ($item in @('Package.swift', 'Sources', 'Examples', 'Tests', 'tools', 'LICENSE')) {
    $src = Join-Path $sdk $item
    if (-not (Test-Path $src)) { Write-Error "missing $item" }
    Copy-Item -Recurse -Force $src -Destination $dest
}
# A stale .build copied out of Examples/ or Sources/ would be dead weight and
# would confuse SwiftPM's manifest cache on the consumer's machine.
Get-ChildItem -Path $dest -Directory -Recurse -Filter '.build' -Force -EA SilentlyContinue |
    ForEach-Object { Remove-Item -Recurse -Force $_.FullName }

# --- engine binaries --------------------------------------------------------
foreach ($f in $engineFiles) {
    Copy-Item (Join-Path $EngineOut $f) -Destination "$dest\engine\lib\"
}

# --- runtime data -----------------------------------------------------------
# Needed at *run* time, not link time, but a consumer with neither cannot start
# an engine, so they travel with the bundle.
Copy-Item (Join-Path $EngineOut 'icudtl.dat') -Destination "$dest\engine\share\"

# flutter_assets: the vendored copy in Resources/ normally, overridable. The
# engine's out/ does not contain one on Windows.
$assets = $env:FLUTTER_SWIFT_ASSETS
if (-not $assets) { $assets = "$sdk\Resources\flutter_assets" }
if (Test-Path $assets) {
    Copy-Item -Recurse -Force $assets -Destination "$dest\engine\share\"
} else {
    Write-Warning "no flutter_assets found; the bundle cannot start an engine. Set FLUTTER_SWIFT_ASSETS."
}

# --- README -----------------------------------------------------------------
$readmeLines = @(
    '# Starling SDK - windows/{ARCH} bundle ({CONFIG} engine)',
    '',
    'The Flutter framework ported to Swift, with the engine binaries it links',
    'against. No engine checkout or toolchain configuration needed.',
    '',
    '## Use it',
    '',
    '```swift',
    'dependencies: [.package(path: "C:/{NAME}")],',
    'targets: [',
    '    .executableTarget(',
    '        name: "App",',
    '        dependencies: [',
    '            .product(name: "Flutter", package: "{NAME}"),',
    '            // The dart:ui types - Offset, Size, Rect, Paint, Canvas. Separate',
    '            // from Flutter, which does not re-export them.',
    '            .product(name: "FlutterSwiftBridge", package: "{NAME}"),',
    '            // The desktop host: the engine''s own Win32 embedder, Swift-driven.',
    '            // The counterpart of FlutterGTK on Linux.',
    '            .product(name: "FlutterWin32", package: "{NAME}"),',
    '        ],',
    '        swiftSettings: [',
    '            // Required. The framework is C++-interop; this is not inherited',
    '            // from the dependency, and without it you get:',
    '            //   module ''FlutterSwiftBridgeCxx'' requires feature ''cplusplus''',
    '            .interoperabilityMode(.Cxx),',
    '        ]',
    '    ),',
    ']',
    '```',
    '',
    'Note there are **no `.unsafeFlags` here**. The `-Xcc` math flags in the Linux',
    'bundle''s README work around an Ubuntu 26.04 glibc/libstdc++ clash and must not',
    'be copied to Windows.',
    '',
    '## Build it',
    '',
    '```',
    'tools\build-windows.ps1 -PackagePath C:\path\to\your\package -Configuration release',
    '```',
    '',
    '**Use that script rather than plain `swift build` for the first build.** A cold',
    'Clang module cache makes the first C++-interop compilation fail inside MSVC''s',
    'own `<xmemory>` with `no matching function for call to ''construct_at''`. That is',
    'a toolchain bug (Swift 6.2.3 / MSVC 14.44), not something your package did: the',
    'failing run still writes a usable module, so the same command run again gets',
    'further, and it needs one pass per interop configuration. The script loops only',
    'while that exact signature appears, so a real build error still fails',
    'immediately. Once the cache is warm, plain `swift build` is fine.',
    '',
    '## Run it',
    '',
    'Windows has no rpath: the loader finds a DLL beside the `.exe` or on `PATH`.',
    'So a run needs the engine DLLs next to your binary, plus the engine data:',
    '',
    '```',
    'copy C:\{NAME}\engine\lib\*.dll           .build\release\',
    'mkdir .build\release\data',
    'copy C:\{NAME}\engine\share\icudtl.dat    .build\release\data\',
    'xcopy /E /I C:\{NAME}\engine\share\flutter_assets .build\release\data\flutter_assets',
    '```',
    '',
    'Skip the DLL copy and the app dies at startup with `0xC0000135`',
    '(`STATUS_DLL_NOT_FOUND`) before `main()`; skip the data and the window comes up',
    'black, which looks like a render bug but is a missing file.',
    '',
    '## Ship your app',
    '',
    'Same copy as above, plus **the Swift runtime DLLs**, which this bundle does not',
    'carry - they belong to your toolchain, exactly as `libswiftCore` does on Linux:',
    '',
    '```',
    'copy "%LOCALAPPDATA%\Programs\Swift\Runtimes\<version>\usr\bin\*.dll" dist\',
    '```',
    '',
    'A machine without the Swift toolchain gets `0xC0000135` before `main()` without',
    'them, which reads as "the app is broken" rather than "a DLL is missing".',
    '',
    'This bundle is built for **windows/{ARCH}**; other targets need their own.',
    '',
    '## Layout',
    '',
    '    Package.swift Sources/ Tests/   the framework',
    '    Examples/                       the demo and example apps',
    '    engine/lib/                     flutter_engine.dll + flutter_windows.dll,',
    '                                    each with its .lib import library',
    '    engine/share/icudtl.dat         ICU data, needed to start an engine',
    '    engine/share/flutter_assets/    default asset bundle',
    '',
    '## Overrides',
    '',
    '`FLUTTER_SWIFT_ENGINE_OUT` points at a different engine build.'
)
$readme = ($readmeLines -join [Environment]::NewLine).
    Replace('{NAME}', $name).Replace('{ARCH}', $arch).Replace('{CONFIG}', $Configuration)
# -Encoding utf8 in PowerShell 5.1 means "UTF-8 with a BOM", and a BOM before
# the leading '#' stops some Markdown renderers seeing a heading at all. Write
# it without one.
[System.IO.File]::WriteAllText("$dest\README.md", $readme,
    (New-Object System.Text.UTF8Encoding $false))

# --- archive ----------------------------------------------------------------
# NOT Compress-Archive. It writes entry names with backslashes, which the ZIP
# spec does not allow (APPNOTE says '/' always, on every platform). Windows'
# own Expand-Archive copes, so the mistake is invisible if you only ever test
# there - but this artifact is published, and unzip on Linux/macOS then treats
# the whole path as one filename or recreates the tree with directories that
# have no execute bit, so `engine/lib` reads as "Permission denied". Writing
# the entries by hand with '/' costs nothing and produces a portable archive.
#
# Only files are added; directory entries are unnecessary, and letting the
# extractor create the directories is what gives them sane permissions.
# Both assemblies: ZipArchive/ZipArchiveMode live in System.IO.Compression,
# CreateEntryFromFile in System.IO.Compression.FileSystem. Loading only the
# latter fails with "Unable to find type [System.IO.Compression.ZipArchiveMode]".
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = Join-Path $OutDir "$name.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }

$root = (Get-Item $OutDir).FullName.TrimEnd('\')
$stream = [System.IO.File]::Open($zip, [System.IO.FileMode]::CreateNew)
$archive = New-Object System.IO.Compression.ZipArchive(
    $stream, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in Get-ChildItem -Path $dest -Recurse -File -Force) {
        $entry = $file.FullName.Substring($root.Length + 1).Replace('\', '/')
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, $file.FullName, $entry,
            [System.IO.Compression.CompressionLevel]::Optimal)
    }
} finally {
    $archive.Dispose()
    $stream.Dispose()
}

$zipMB = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Host "bundle:  $dest"
Write-Host "archive: $zip ($zipMB MB)"
Write-Host "engine:  $EngineOut ($Configuration)"
