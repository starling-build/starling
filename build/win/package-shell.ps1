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
    [switch]$SkipBuild
)
$ErrorActionPreference = 'Stop'

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
Copy-Item (Join-Path $EngineOut 'icudtl.dat') (Join-Path $stage 'data') -Force
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
    Write-Host ("  $setup  {0:N1} MB" -f ((Get-Item $setup).Length / 1MB))
} else {
    Write-Warning "iexpress produced nothing; the zip is the deliverable"
}
Remove-Item $boot, $sed -Force -ErrorAction SilentlyContinue
