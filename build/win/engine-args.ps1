# Configure and build the Windows engine the way Starling ships it.
#
# WHY THIS IS A SCRIPT AND NOT A NOTE. `flutter/tools/gn` REWRITES args.gn from
# scratch, and it enables Vulkan on every non-Apple target and Impeller on
# every desktop one. So the trims below are not sticky: run the upstream
# configure script again and they vanish, silently, and the next build is 1.9
# MB fatter with nothing to indicate why. This applies them to an existing
# out directory and rebuilds -- run it after any `flutter/tools/gn`.
#
# What comes out, and why Windows does not need it: the Windows embedder
# references Vulkan nowhere, and flutter_windows_engine.cc pushes
# --enable-impeller=false, so the desktop draws Skia on ANGLE and every byte
# of Impeller and Vulkan in the DLL is compiled and never reached.
# docs/BUILDING.md has the full account, including the three fork fixes that
# building without Impeller required.
param(
    [string]$EngineSrc = "$env:USERPROFILE\dev\starling-engine\engine\src",
    [string]$OutDir = "out\host_release",
    # Configure only; skip the build.
    [switch]$NoBuild
)
$ErrorActionPreference = 'Stop'

# depot_tools carries gn's vpython3 and ninja; Build Tools is invisible to
# Chromium's VS detection unless vs2022_install is set. docs/BUILDING.md
# section 2 -- a scheduled task or a fresh shell inherits none of this.
$env:PATH = "C:\depot_tools;" + $env:PATH
$env:DEPOT_TOOLS_WIN_TOOLCHAIN = "0"
$env:GYP_MSVS_VERSION = "2022"
$env:vs2022_install = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools"
$env:GYP_MSVS_OVERRIDE_PATH = $env:vs2022_install

$argsFile = Join-Path $EngineSrc "$OutDir\args.gn"
if (-not (Test-Path $argsFile)) { throw "no args.gn at $argsFile -- run flutter/tools/gn first" }

$trims = @{
    # Skia's and the shell's Vulkan backends.
    'skia_use_vulkan'          = 'false'
    'shell_enable_vulkan'      = 'false'
    # BOTH Impeller backends, which is what makes impeller_supports_rendering
    # false -- the switch the shell and embedder already guard on. One alone
    # is not a configuration: gn fails on a target-name collision between
    # impellerc_gles_entity_shaders and impellerc_gles3_entity_shaders.
    'impeller_enable_opengles' = 'false'
    'impeller_enable_vulkan'   = 'false'
    # Not optional: with Vulkan gone, gn gen fails on the TEST graph
    # (embedder_unittests_library needs //flutter/testing:vulkan) before a
    # single file compiles. Takes gtest out of the build too.
    'enable_unittests'         = 'false'

    # ANGLE's other backends. egl::Manager::Create asks for D3D11 three times
    # -- hardware, feature level 9_3, then WARP, which is still D3D11 -- and
    # never for anything else, but ANGLE defaults to building D3D9, the
    # desktop GL backend and Vulkan on Windows as well. flutter/tools/gn
    # already turns GL and Vulkan off for Apple targets; this is the same
    # thing for the platform that actually ships them.
    #
    # angle_enable_essl and angle_enable_glsl follow angle_enable_gl, so the
    # GLSL and ESSL translators leave with it; angle_enable_hlsl follows d3d9
    # || d3d11 and stays, which is the one we need.
    'angle_enable_vulkan'      = 'false'
    'angle_enable_gl'          = 'false'
    'angle_enable_gl_desktop_backend' = 'false'
    'angle_enable_d3d9'        = 'false'

    # The Dart runtime's optional pieces. The VM itself cannot leave -- the
    # shell's own plumbing types (SceneBuilder, MultiFrameCodec, ImageDecoder,
    # PlatformMessage, SemanticsNode) live in //flutter/lib/ui and are
    # Dart-wrappable classes, so dropping Dart means splitting that library,
    # not guarding call sites. What CAN go is everything the VM only needs to
    # talk to a network it never opens: this engine runs no Dart code at all,
    # because Shell::CreateSwift injects a SwiftRuntimeController and leaves
    # vm_ empty.
    'dart_disable_secure_socket'        = 'true'
    'dart_use_fallback_root_certificates' = 'false'
    'dart_version_git_info'             = 'false'
}

$text = Get-Content $argsFile -Raw
foreach ($k in $trims.Keys) {
    $v = $trims[$k]
    if ($text -match "(?m)^\s*$k\s*=") {
        $text = $text -replace "(?m)^\s*$k\s*=.*$", "$k = $v"
    } else {
        $text = $text.TrimEnd() + "`r`n$k = $v"
    }
}
Set-Content $argsFile $text -Encoding ascii
Write-Host "== args =="
Get-Content $argsFile | Select-String 'vulkan|impeller|unittests' | ForEach-Object { "  $_" }

Push-Location $EngineSrc
try {
    Write-Host "== gn gen =="
    & "$EngineSrc\flutter\third_party\gn\gn.exe" gen $OutDir
    if ($LASTEXITCODE -ne 0) { throw "gn gen failed ($LASTEXITCODE)" }
    if ($NoBuild) { return }
    Write-Host "== ninja =="
    & cmd /c "C:\depot_tools\ninja.bat -C $OutDir flutter_engine.dll flutter_windows.dll"
    if ($LASTEXITCODE -ne 0) { throw "ninja failed ($LASTEXITCODE)" }
} finally { Pop-Location }

Get-ChildItem (Join-Path $EngineSrc $OutDir) -Filter flutter_*.dll |
    ForEach-Object { "  {0,-22} {1,6:N2} MB" -f $_.Name, ($_.Length / 1MB) }
Write-Host "  (untrimmed, for comparison: flutter_engine.dll 11.65 MB)"
