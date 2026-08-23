# Build this package on Windows.
#
#   tools\build-windows.ps1 [-Product CounterApp] [-Configuration debug|release]
#
# Why this exists rather than just `swift build`:
#
# The first C++-interop compilation against a cold Clang module cache fails,
# every time, with a wall of errors inside the MSVC standard library:
#
#   ...\MSVC\14.44.35207\include\xmemory:614:13:
#       error: no matching function for call to 'construct_at'
#
# Underneath it the instantiation chain is
# std::vector<std::atomic<bool>, std::_Parallelism_allocator<...>> being
# copy-constructed — MSVC's <execution> internals. Swift's C++ importer walks
# them while building the `std` module, and std::atomic is not copyable, so
# overload resolution fails. This is a toolchain bug (Swift 6.2.3 against MSVC
# 14.44), not something the package can express its way out of: none of the
# bridge headers include <execution> or <vector>, and stripping <string> from
# them changes nothing. The trigger is only ever the first compile that has to
# build the module.
#
# The failing run still writes a usable .pcm, so the same command run again
# gets past that target. It has to be the same command — warming with some
# other target does not help, because each distinct set of interop flags keys
# a different module. That is also why one retry is not enough: from cold,
# this package needs three passes, one per configuration that has to be
# populated —
#
#   pass 1  FlutterSwiftBridge   fails (6 errors)
#   pass 2  Flutter              fails (375) — it builds under language mode 5,
#                                so its module is keyed separately
#   pass 3  everything           succeeds
#
# So: repeat while the failure carries exactly that signature, up to a small
# cap. The signature is matched deliberately rather than retrying on any
# failure — a blind retry would turn a real, reproducible build error into the
# same message after three times the wait.
#
# Re-check after any toolchain upgrade: delete .build, run plain `swift build`,
# and if it passes, delete this script.
[CmdletBinding()]
param(
    [string]$Product = '',
    [ValidateSet('debug', 'release')]
    [string]$Configuration = 'debug',
    # The app packages hit the same bug — they compile the same interop
    # targets through their path dependency on this one — so point this at
    # e.g. ..\apps\TerminalApp rather than keeping a copy of this script there.
    [string]$PackagePath = ''
)

$ErrorActionPreference = 'Continue'

$pkg = if ($PackagePath) { (Resolve-Path $PackagePath).Path }
       else { Split-Path -Parent $PSScriptRoot }
Set-Location $pkg

$buildArgs = @('build', '-c', $Configuration)
if ($Product) { $buildArgs += @('--product', $Product) }

# -suppress-warnings is load-bearing, not tidiness. Once a module's diagnostic
# output grows past the pipe buffer, swift-build stops draining the frontend's
# stderr and the frontend blocks forever in NtWriteFile — the build "hangs"
# with the compile actually finished (the .o files are all on disk, CPU flat
# at zero). WinShellBar crossed that line in 2026-08: ~170 lines of Sendable
# warnings was enough. Diagnose a recurrence with a noninvasive cdb attach
# (`cdb -p <pid> -pv -c "~*k; qd"`; the toolchain's lldb is unusable — it
# wants a python39.dll that isn't installed): the giveaway is the main thread
# parked in NtWriteFile. Errors still fail the build normally; this only
# silences the warning stream that jams the pipe.
$buildArgs += @('-Xswiftc', '-suppress-warnings')

# The failure is recognisable by the MSVC header and the call that fails; both
# have to appear for this to count as the known bug.
function Test-ModuleCacheBug([string[]]$lines) {
    $hasCall = $lines | Select-String -Pattern "no matching function for call to 'construct_at'" -Quiet
    $hasHeader = $lines | Select-String -Pattern 'MSVC.*include.xmemory' -Quiet
    return ($hasCall -and $hasHeader)
}

# One pass per interop configuration that needs populating, plus the real
# build, plus slack. If it has not converged by then something else is wrong
# and the output should be shown rather than retried forever.
$maxPasses = 5

for ($pass = 1; $pass -le $maxPasses; $pass++) {
    Write-Host "==> swift $($buildArgs -join ' ')"
    $out = & swift @buildArgs 2>&1
    $code = $LASTEXITCODE

    if ($code -eq 0) { break }
    if (-not (Test-ModuleCacheBug $out)) { break }
    if ($pass -eq $maxPasses) { break }

    Write-Host "    cold module cache hit the known MSVC/std interop bug (pass $pass);"
    Write-Host '    that run still wrote the module, so building again.'
}

$out | ForEach-Object { $_ }
exit $code
