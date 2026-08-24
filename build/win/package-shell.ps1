# Package the Starling desktop for Windows: one folder, one zip, one setup.exe.
#
# This is `build/package-desktop.sh`'s counterpart, and it holds the same
# position: the SINGLE definition of what a Windows install contains. The dev
# loop's staging (deploy-main.ps1 and friends on the test box) copies the same
# set; if the two ever disagree, this file is the one that is right, because
# it is what a machine that never built anything receives.
#
# ONE BINARY, several faces. WinShellBar.exe is the dock, the desktop, the
# launcher, the notification centre, the Run dialog AND the file explorer:
# the explorer is an engine VIEW inside the shell's process rather than a
# program of its own, which is why there is no second exe to ship and why
# Win+E opens a window without starting anything.
param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$EngineOut = "$env:USERPROFILE\dev\starling-engine\engine\src\out\host_release",
    [string]$SwiftRuntime = "$env:LOCALAPPDATA\Programs\Swift\Runtimes\6.2.3\usr\bin",
    [string]$Version = "0.1.0",
    [string]$OutDir = "$env:USERPROFILE\dist",
    [switch]$SkipBuild,
    # Ship Chromium's full 10.5 MB ICU instead of the 1.6 MB desktop slice.
    # Here for the day something turns out to need a locale table we dropped:
    # flip it, and the difference is one file.
    [switch]$FullIcu,
    # Ship every DLL in the Swift runtime directory, including the ones no
    # binary in the package imports. The escape hatch if something turns out
    # to be loaded dynamically rather than linked.
    [switch]$KeepAllRuntime,

    # --- signing -------------------------------------------------------
    # Off by default, so an unsigned developer package costs nothing. What
    # signing buys is NOT the SmartScreen dialog -- that stays until the
    # publisher and each file hash accumulate download reputation -- it is
    # Smart App Control, which blocks "unknown, unsigned code" outright and
    # allows an unknown binary signed by a CA in the Trusted Root Program.
    # Unsigned, this package cannot run at all on a SAC machine.
    [switch]$Sign,
    # Azure Artifact Signing (formerly Trusted Signing): the metadata.json
    # naming the account, certificate profile and REGION endpoint.
    [string]$SigningMetadata,
    # Or a certificate in the local store / on a FIPS token, by thumbprint.
    [string]$CertThumbprint,
    [string]$SignToolPath,
    [string]$DlibPath,
    # Artifact Signing certificates live for THREE DAYS. The timestamp is not
    # a nicety there, it is the only reason a signature outlives the week.
    [string]$TimestampUrl = "http://timestamp.acs.microsoft.com"
)
$ErrorActionPreference = 'Stop'

# --- signing -----------------------------------------------------------
#
# One function for both certificate sources, because everything except the
# credential flag is identical and the two must not drift: same digest, same
# timestamp authority, same verification.
function Resolve-SignTool {
    if ($SignToolPath) { return $SignToolPath }
    # Newest SDK wins. The dlib needs 10.0.22621.755 or later; the 20348 SDK
    # is explicitly unsupported, and picking it produces a signing failure
    # that reads like an authentication problem.
    $found = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe" -ErrorAction SilentlyContinue |
        Sort-Object {
            # bin\<version>\x64\signtool.exe on any current SDK; the older
            # bin\x64 layout has no version to parse and sorts oldest.
            $v = $null
            if ([version]::TryParse($_.Directory.Parent.Name, [ref]$v)) { $v } else { [version]'0.0' }
        } | Select-Object -Last 1
    if (-not $found) { throw "signtool.exe not found; pass -SignToolPath or install the Windows SDK" }
    return $found.FullName
}

function Resolve-Dlib {
    if ($DlibPath) { return $DlibPath }
    foreach ($root in @("${env:ProgramFiles}\Microsoft", "${env:ProgramFiles(x86)}\Microsoft", $OutDir)) {
        $hit = Get-ChildItem $root -Recurse -Filter 'Azure.CodeSigning.Dlib.dll' -ErrorAction SilentlyContinue |
            Where-Object { $_.DirectoryName -match '\\x64$' } | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    throw ("the Artifact Signing dlib was not found. Install the client tools:`n" +
           "  winget install -e --id Microsoft.Azure.ArtifactSigningClientTools`n" +
           "or pass -DlibPath")
}

# Sign a batch of files. signtool takes many paths per invocation, and each
# file is one signature either way, so batching costs nothing and saves the
# per-call overhead of standing up the dlib.
function Invoke-SignFiles([string[]]$Paths, [string]$What) {
    if (-not $Paths -or $Paths.Count -eq 0) { return }
    $tool = Resolve-SignTool
    # NOT $args: that is an automatic variable inside a function, and
    # shadowing it is the kind of thing that works until it doesn't.
    $signArgs = @('sign', '/v', '/fd', 'SHA256', '/tr', $TimestampUrl, '/td', 'SHA256')
    if ($CertThumbprint) {
        $signArgs += @('/sha1', $CertThumbprint)
    } else {
        $signArgs += @('/dlib', (Resolve-Dlib), '/dmdf', $SigningMetadata)
    }
    Write-Host ("  signing {0} {1}" -f $Paths.Count, $What)
    & $tool @signArgs @Paths
    if ($LASTEXITCODE -ne 0) { throw "signing failed ($LASTEXITCODE)" }
    # Verify against the machine's own policy, every signature in the file.
    # A sign that "succeeded" but does not verify is the failure mode worth
    # catching here rather than on a tester's SAC machine.
    & $tool verify /pa /all @Paths | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "verification failed after signing ($LASTEXITCODE)" }
}

# Everything we redistribute that nobody has signed: our exe, the engine, and
# the whole Swift runtime. NOT the MSVC redistributables -- those carry
# Microsoft's own signature, and replacing it with ours would be a downgrade
# that also burns quota. SAC judges every binary a process loads, so an
# unsigned DLL beside a signed exe earns "Smart App Control has blocked PART
# of this app", which is a worse bug report than a clean block.
function Get-UnsignedBinaries([string]$Dir) {
    Get-ChildItem $Dir -Recurse -Include *.exe, *.dll -File |
        Where-Object { (Get-AuthenticodeSignature $_.FullName).Status -ne 'Valid' } |
        ForEach-Object { $_.FullName }
}

if ($Sign -and -not ($SigningMetadata -or $CertThumbprint)) {
    throw "-Sign needs either -SigningMetadata (Artifact Signing) or -CertThumbprint"
}

$sdk = Join-Path $Root 'sdk'
$name = "Starling-$Version-win-x64"
$stage = Join-Path $OutDir $name

Write-Host "== 1. build =="
if ($SkipBuild) {
    Write-Host "  skipped"
} else {
    $env:FLUTTER_SWIFT_ENGINE_OUT = $EngineOut
    Push-Location $sdk
    & .\tools\build-windows.ps1 -Product WinShellBar -Configuration release
    $code = $LASTEXITCODE
    Pop-Location
    if ($code -ne 0) { throw "build failed ($code)" }
}
$built = Join-Path $sdk '.build\release\WinShellBar.exe'
if (-not (Test-Path $built)) { throw "no WinShellBar.exe at $built" }

Write-Host "== 2. assemble =="
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'data') | Out-Null

Copy-Item $built $stage -Force
# The engine, and the ICU data it will not start without.
foreach ($dll in 'flutter_engine.dll','flutter_windows.dll') {
    Copy-Item (Join-Path $EngineOut $dll) $stage -Force
}
# ICU data, and NOT the one the build drops in the out directory. ICU ships
# several prebuilt slices and //flutter/third_party/icu/BUILD.gn picks
# `common` for every desktop target -- Chromium's full browser set, 10.5 MB
# of which 372 language bundles, 293 currency, 251 region, 250 timezone and
# 245 unit-name tables are for formatting we do not do: there is no Dart here,
# and Foundation does our dates and numbers. `flutter_desktop` is upstream's
# own slice for desktop embedders -- the break iterators (including the CJK,
# Thai and Burmese line-break dictionaries), collation, layout and emoji
# tables -- and it is 1.6 MB. The engine loads this file at runtime
# (ICU_UTIL_DATA_FILE), so which bytes ship is a packaging decision, not a
# build one, and no fork divergence is needed to make it.
$engineSrc = Split-Path (Split-Path $EngineOut -Parent) -Parent
$icuSlice = Join-Path $engineSrc 'flutter\third_party\icu\flutter_desktop\icudtl.dat'
if ($FullIcu -or -not (Test-Path $icuSlice)) {
    Copy-Item (Join-Path $EngineOut 'icudtl.dat') (Join-Path $stage 'data') -Force
    Write-Host ("  icudtl.dat: full set, {0:N1} MB" -f ((Get-Item (Join-Path $stage 'data\icudtl.dat')).Length / 1MB))
} else {
    Copy-Item $icuSlice (Join-Path $stage 'data') -Force
    Write-Host ("  icudtl.dat: desktop slice, {0:N1} MB" -f ((Get-Item (Join-Path $stage 'data\icudtl.dat')).Length / 1MB))
}
# The asset bundle and the icon font, both resolved relative to the exe.
Copy-Item (Join-Path $sdk 'Resources\flutter_assets') (Join-Path $stage 'data') -Recurse -Force
Copy-Item (Join-Path $sdk '.build\release\FlutterSwift_CupertinoIcons.resources') $stage -Recurse -Force
# The Swift runtime, because a machine that never installed the toolchain has
# none of it. This is most of the package's size and all of its portability.
if (Test-Path $SwiftRuntime) {
    Copy-Item (Join-Path $SwiftRuntime '*.dll') $stage -Force
} else {
    Write-Warning "Swift runtime not found at $SwiftRuntime -- the package will only run where the toolchain is installed"
}

# Then throw away the ones nothing loads. The toolchain's runtime directory is
# every library Swift on Windows can need -- networking, XML, distributed
# actors, autodiff, the remote-mirror reflection library a debugger uses -- and
# we copy the lot because there is no manifest saying which a given binary
# wants. So ask the binaries: walk the static import graph out from the exe and
# drop what it never reaches. That is ~3.5 MB, and unlike a hand-written
# exclusion list it stays right when the shell starts using something new.
#
# THE LIMIT OF THIS: it sees static imports only. Anything a library loads with
# LoadLibrary at runtime is invisible to it and would be pruned wrongly, which
# is what -KeepAllRuntime is for, and why the skipped list is printed rather
# than silently dropped.
if (-not $KeepAllRuntime) {
    $dumpbin = Get-ChildItem "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\*\VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $dumpbin) {
        Write-Warning "dumpbin not found -- shipping the whole Swift runtime directory"
    } else {
        function Get-Imports([string]$path) {
            & $dumpbin.FullName /dependents $path 2>$null |
                Select-String -Pattern '^\s{4}(\S+\.dll)$' |
                ForEach-Object { $_.Matches[0].Groups[1].Value.ToLower() }
        }
        $present = @{}
        Get-ChildItem $stage -Filter *.dll -File | ForEach-Object { $present[$_.Name.ToLower()] = $_ }
        $reached = @{}
        $queue = New-Object System.Collections.Queue
        # Roots: the exe, and the engine DLLs it loads. NOT $root as the loop
        # variable -- PowerShell variables are case-INSENSITIVE, so that is the
        # $Root parameter, and the loop leaves it holding a DLL name. The
        # symptom lands three steps later, on `git -C $Root` reporting it
        # cannot change to 'flutter_windows.dll'.
        foreach ($rootBinary in 'WinShellBar.exe', 'flutter_engine.dll', 'flutter_windows.dll') {
            $queue.Enqueue($rootBinary)
            $reached[$rootBinary.ToLower()] = $true
        }
        while ($queue.Count) {
            $cur = Join-Path $stage $queue.Dequeue()
            if (-not (Test-Path $cur)) { continue }
            foreach ($dep in Get-Imports $cur) {
                if ($present.ContainsKey($dep) -and -not $reached.ContainsKey($dep)) {
                    $reached[$dep] = $true
                    $queue.Enqueue($dep)
                }
            }
        }
        $dropped = $present.Keys | Where-Object { -not $reached.ContainsKey($_) } | Sort-Object
        if ($dropped) {
            $freed = ($dropped | ForEach-Object { $present[$_].Length } | Measure-Object -Sum).Sum
            Write-Host ("  unreferenced runtime libraries dropped ({0:N1} MB): {1}" -f ($freed / 1MB), (($dropped | ForEach-Object { $_ -replace '\.dll$','' }) -join ', '))
            $dropped | ForEach-Object { Remove-Item $present[$_].FullName -Force }
        }
    }
}
Copy-Item (Join-Path $PSScriptRoot 'install.ps1') (Join-Path $stage 'Install.ps1') -Force
Copy-Item (Join-Path $PSScriptRoot 'uninstall.ps1') (Join-Path $stage 'Uninstall.ps1') -Force

# A stamp, for the same reason the Linux tree carries BUILD-STAMP: "which
# build is this" must be answerable from the installed copy, not from whoever
# remembers what they shipped.
$sha = (& git -C $Root rev-parse --short HEAD 2>$null)
if (-not $sha) { $sha = 'unknown' }
@(
    "Starling desktop for Windows"
    "version   $Version"
    "commit    $sha"
    "built     $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "engine    $EngineOut"
) | Set-Content (Join-Path $stage 'BUILD-STAMP.txt') -Encoding ascii

$files = Get-ChildItem $stage -Recurse -File
Write-Host ("  {0} files, {1:N1} MB" -f $files.Count, (($files | Measure-Object -Property Length -Sum).Sum / 1MB))

if ($Sign) {
    Write-Host "== 2b. sign the payload =="
    # BEFORE the zip: a signature is the last write to a file, and zipping a
    # tree and signing it afterwards would mean signing nothing at all.
    Invoke-SignFiles (Get-UnsignedBinaries $stage) "binaries"
} else {
    Write-Host "  (unsigned -- Smart App Control machines will refuse this package)"
}

Write-Host "== 3. zip =="
$zip = Join-Path $OutDir "$name.zip"
Remove-Item $zip -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal
Write-Host ("  $zip  {0:N1} MB" -f ((Get-Item $zip).Length / 1MB))

Write-Host "== 4. setup.exe =="
# iexpress ships with Windows, which is the whole reason it is used here: no
# toolchain to install on a machine whose only job is to hand someone a file
# they can double-click. It packs a FLAT list of files, so the payload is the
# zip plus a one-line bootstrap rather than the tree itself.
$iexpress = Join-Path $env:SystemRoot 'System32\iexpress.exe'
$setup = Join-Path $OutDir "StarlingSetup-$Version.exe"
if (-not (Test-Path $iexpress)) {
    Write-Warning "iexpress not present; the zip above is the deliverable"
    return
}
$boot = Join-Path $OutDir 'starling-bootstrap.cmd'
@(
    '@echo off'
    'setlocal'
    'set "T=%TEMP%\starling-setup-%RANDOM%"'
    'mkdir "%T%" 2>nul'
    "powershell -NoProfile -ExecutionPolicy Bypass -Command ""Expand-Archive -LiteralPath '%~dp0$name.zip' -DestinationPath '%T%' -Force"""
    'powershell -NoProfile -ExecutionPolicy Bypass -File "%T%\Install.ps1" %*'
    'rmdir /s /q "%T%" 2>nul'
) | Set-Content $boot -Encoding ascii

$sed = Join-Path $OutDir 'starling.sed'
@(
    '[Version]'
    'Class=IEXPRESS'
    'SEDVersion=3'
    '[Options]'
    'PackagePurpose=InstallApp'
    'ShowInstallProgramWindow=1'
    'HideExtractAnimation=1'
    'UseLongFileName=1'
    'InsideCompressed=0'
    'CAB_FixedSize=0'
    'CAB_ResvCodeSigning=0'
    'RebootMode=N'
    'InstallPrompt=%InstallPrompt%'
    'DisplayLicense=%DisplayLicense%'
    'FinishMessage=%FinishMessage%'
    "TargetName=%TargetName%"
    'FriendlyName=%FriendlyName%'
    'AppLaunched=%AppLaunched%'
    'PostInstallCmd=%PostInstallCmd%'
    'AdminQuietInstCmd=%AdminQuietInstCmd%'
    'UserQuietInstCmd=%UserQuietInstCmd%'
    'SourceFiles=SourceFiles'
    '[Strings]'
    'InstallPrompt=Install the Starling desktop for this account?'
    'DisplayLicense='
    'FinishMessage=Installed. It becomes your desktop at the next sign-in.'
    "TargetName=$setup"
    'FriendlyName=Starling desktop'
    'AppLaunched=cmd /c starling-bootstrap.cmd'
    'PostInstallCmd=<None>'
    # A quiet install (/Q:A) runs the *QuietInstCmd*, NOT AppLaunched. Leave
    # these empty and the SFX extracts the payload perfectly and then exits
    # 0x80070002 -- "file not found", for the empty command, which reads like a
    # broken package rather than a missing line.
    'AdminQuietInstCmd=cmd /c starling-bootstrap.cmd'
    'UserQuietInstCmd=cmd /c starling-bootstrap.cmd'
    'FILE0="starling-bootstrap.cmd"'
    "FILE1=`"$name.zip`""
    '[SourceFiles]'
    'SourceFiles0=' + $OutDir
    '[SourceFiles0]'
    '%FILE0%='
    '%FILE1%='
) | Set-Content $sed -Encoding ascii

Remove-Item $setup -Force -ErrorAction SilentlyContinue
& $iexpress /N /Q $sed | Out-Null
if (Test-Path $setup) {
    # AFTER iexpress, for the same reason the payload is signed before the
    # zip: whoever writes the file last wins, and iexpress writes the whole
    # PE. The wrapper and its payload are signed separately -- the SFX
    # signature covers what the user double-clicks, the payload signatures
    # cover what SAC judges when the desktop actually runs.
    if ($Sign) { Invoke-SignFiles @($setup) "setup.exe" }
    Write-Host ("  $setup  {0:N1} MB" -f ((Get-Item $setup).Length / 1MB))
} else {
    Write-Warning "iexpress produced nothing; the zip is the deliverable"
}
Remove-Item $boot, $sed -Force -ErrorAction SilentlyContinue
