# Build starling-termd.exe. The Makefile cannot do this -- Windows has no
# make -- but it is the same termd.c, compiled against plat_win32.c instead of
# plat_posix.c. Nothing in termd.c is conditional.
#
#   .\build-windows.ps1 [-Out starling-termd.exe] [-Dbg]
#
# clang comes with the Swift toolchain already installed on this box, so there
# is no separate compiler to fetch.
[CmdletBinding()]
param(
    [string]$Out = 'starling-termd.exe',
    [switch]$Dbg
)
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here

$clang = Get-Command clang.exe -ErrorAction SilentlyContinue
if (-not $clang) { throw 'clang.exe not on PATH (install the Swift toolchain)' }

# No ternary here: Windows PowerShell 5.1 is what ships on the box and it
# parses `? :` as an unexpected token.
$flags = @('-std=c11', '-Wall', '-Wextra', '-Wno-unused-parameter')
if ($Dbg) { $flags += @('-O0', '-g') } else { $flags += @('-O2') }

# ws2_32 for AF_UNIX; ConPTY lives in kernel32, which clang links by default.
$libs = @('-lws2_32')

# Not $args -- that is an automatic variable in PowerShell.
$argv = $flags + @('termd.c', 'plat_win32.c', '-o', $Out) + $libs
Write-Output ("clang " + ($argv -join ' '))
& $clang.Source @argv
if ($LASTEXITCODE -ne 0) { throw "build failed ($LASTEXITCODE)" }

Get-Item $Out | Select-Object Name, Length, LastWriteTime | Format-Table -Auto
