# The filmed head-to-head, Windows side. The port of race.sh: same three
# tests, same start signal, same verdict card.
#
#   race.ps1 -Label ours|wt -Name "STARLING TERMINAL"
param(
    [string]$Label = 'term',
    [string]$Name  = 'TERMINAL',
    [string]$FilmDir = 'C:\film',
    [string]$BenchDir = 'C:\bench'
)
$ErrorActionPreference = 'Continue'
. (Join-Path $BenchDir 'h\bench-lib.ps1')
$e = [char]27

# UTF-8 on the console, FOR THE FILM ONLY.
#
# Write-Corpus writes the corpus as raw bytes, and the corpus is UTF-8. With
# the console on a legacy code page the host reinterprets those bytes before
# the terminal ever sees them, so the unicode test draws `µùÑµ£¼Ð¬` where it
# should draw Japanese, Chinese and Korean. Both terminals get the identical
# stream either way, so the race stays fair -- but a video of two terminals
# racing to render mojibake is a video of the wrong thing.
#
# NOTE this is a deviation from the measured round, which ran on the inherited
# code page like every archived Windows round before it. Times here are
# therefore close to, but not the same protocol as, the report's.
chcp 65001 > $null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ascii   = Join-Path $BenchDir 'big500-ascii.bin'
$unicode = Join-Path $BenchDir 'big500-unicode.bin'
$reps    = [int](Get-Content (Join-Path $FilmDir 'REPS')   -EA SilentlyContinue)
$ureps   = [int](Get-Content (Join-Path $FilmDir 'UREPS')  -EA SilentlyContinue)
$frames  = [int](Get-Content (Join-Path $FilmDir 'FRAMES') -EA SilentlyContinue)
if ($reps   -le 0) { $reps   = 4 }
if ($ureps  -le 0) { $ureps  = 2 }
if ($frames -le 0) { $frames = 6000 }

# Splash, and publish the grid every 200 ms so the launcher can verify both
# sides match before it starts filming.
Write-Host -NoNewline "$e[2J$e[H"
Write-Host ""
Write-Host ""
Write-Host "   $e[1;44;97m  $Name  $e[0m"
Write-Host ""
Write-Host "   three tests, ~10 seconds each - waiting for the start signal"
while (-not (Test-Path (Join-Path $FilmDir 'GO'))) {
    # [IO.File], not Set-Content: under Windows Terminal's ConPTY the provider
    # throws "Stream was not readable" on every write, five times a second,
    # and the grid file never appears. The .NET call sidesteps the provider.
    [IO.File]::WriteAllText((Join-Path $FilmDir "grid-$Label"), (Get-Grid))
    Start-Sleep -Milliseconds 200
}

function Banner($t) {
    Write-Host -NoNewline "$e[0m$e[?1049l$e[r$e[2J$e[H"
    Write-Host "$e[1;33m=== $t ===$e[0m"
    Start-Sleep -Milliseconds 600
}

$start = [Diagnostics.Stopwatch]::StartNew()

Banner "TEST 1/3: cat ascii, $([math]::Round($reps * 0.5, 1)) GB"
$sw = [Diagnostics.Stopwatch]::StartNew()
for ($i = 0; $i -lt $reps; $i++) { Write-Corpus $ascii }
$sw.Stop(); $A = $sw.Elapsed.TotalSeconds

Banner "TEST 2/3: cat unicode, $([math]::Round($ureps * 0.5, 1)) GB"
$sw = [Diagnostics.Stopwatch]::StartNew()
for ($i = 0; $i -lt $ureps; $i++) { Write-Corpus $unicode }
$sw.Stop(); $U = $sw.Elapsed.TotalSeconds

Banner "TEST 3/3: DOOM-Fire, $frames frames"
Start-Sleep -Milliseconds 500
$doomout = Join-Path $FilmDir "doomout-$Label"
cmd /c "set DOOMFIRE_FRAMES=$frames&& C:\doomfire\DOOM-fire.exe 2> `"$doomout`""
$fps = ''
$m = Select-String -Path $doomout -Pattern 'fps=([0-9.]+)' -EA SilentlyContinue | Select-Object -Last 1
if ($m) { $fps = $m.Matches[0].Groups[1].Value }
$start.Stop(); $T = $start.Elapsed.TotalSeconds

[IO.File]::WriteAllText((Join-Path $FilmDir "times-$Label"),
    ("ascii={0:N2} unicode={1:N2} fps={2} total={3:N1}" -f $A, $U, $fps, $T))

function Show-Card {
    Write-Host -NoNewline "$e[0m$e[?1049l$e[r$e[2J$e[H"
    Write-Host ""
    Write-Host ""
    Write-Host "   $e[1;44;97m  $Name  $e[0m"
    Write-Host ""
    Write-Host ("   ascii cat               $e[1m{0,7:N2} s$e[0m" -f $A)
    Write-Host ("   unicode cat             $e[1m{0,7:N2} s$e[0m" -f $U)
    Write-Host ("   DOOM-Fire, $frames frames  $e[1m{0,5} fps$e[0m" -f [int][double]$fps)
    Write-Host ""
    Write-Host ("   $e[1;42;30m  ALL THREE DONE in {0:N1} s  $e[0m" -f $T)
}
Show-Card
Start-Sleep -Milliseconds 1500
Show-Card
[IO.File]::WriteAllText((Join-Path $FilmDir "done-$Label"), "done")
Start-Sleep -Seconds 600
