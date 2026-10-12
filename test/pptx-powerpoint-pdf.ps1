# Opens one .pptx in Microsoft PowerPoint for Windows and has PowerPoint
# export it as a PDF -- test/pptx-powerpoint-pdf.applescript's counterpart,
# driven by test/pptx-powerpoint-render.sh under Git Bash.
#
#   powershell -File test\pptx-powerpoint-pdf.ps1 DECK.pptx OUT.pdf
#
# Prints one of: "pdf", "pdf repaired", or "error: ...", as the AppleScript
# does. There is no sandbox here and no dialogs to click: PowerPoint is driven
# over COM with its alerts off, the deck opened read-only and without a
# window. A deck PowerPoint would ask to repair fails a plain Open, so it is
# opened again through Open2007 with OpenAndRepair and the verdict says so --
# what PowerPoint draws after its own repair is still the picture to compare
# against.
#
# One PowerPoint serves a whole sweep: the script attaches to the running
# instance and leaves it running (starting it costs seconds per deck, and
# quitting someone's open PowerPoint is not this script's call). A deck that
# hangs it is the caller's to time out; kill POWERPNT.EXE and go on.
param(
    [Parameter(Mandatory = $true)][string]$Deck,
    [Parameter(Mandatory = $true)][string]$Pdf
)
$ErrorActionPreference = 'Stop'
# Git Bash hands over /c/... or mixed paths; COM wants a real Windows one.
$Deck = [System.IO.Path]::GetFullPath($Deck)
$Pdf = [System.IO.Path]::GetFullPath($Pdf)
if (-not (Test-Path -LiteralPath $Deck)) { Write-Output "error: no such deck $Deck"; exit 0 }
Remove-Item -LiteralPath $Pdf -Force -ErrorAction SilentlyContinue

$msoTrue = -1; $msoFalse = 0
$ppSaveAsPDF = 32
$ppAlertsNone = 1

try { $app = New-Object -ComObject PowerPoint.Application }
catch {
    # 0x80080005 after a 30 s wait is nearly always integrity levels: this
    # shell is elevated, PowerPoint is already running as the desktop user,
    # and it will neither be reached nor start a second instance.
    $hint = if ($_.Exception.Message -match '80080005') { ' -- run from a shell that is not elevated, or close PowerPoint' } else { '' }
    Write-Output "error: no PowerPoint ($($_.Exception.Message -replace '\s+', ' '))$hint"; exit 0
}
$app.DisplayAlerts = $ppAlertsNone

$pres = $null; $repaired = $false; $why = ''
try {
    $pres = $app.Presentations.Open($Deck, $msoTrue, $msoFalse, $msoFalse)
} catch {
    $why = $_.Exception.Message
    try {
        $pres = $app.Presentations.Open2007($Deck, $msoTrue, $msoFalse, $msoFalse, $msoTrue)
        $repaired = $true
    } catch { $why = $_.Exception.Message }
}
if ($null -eq $pres) {
    Write-Output ("error: PowerPoint refused " + [System.IO.Path]::GetFileNameWithoutExtension($Deck) + ": " + ($why -replace '\s+', ' '))
    exit 0
}

$verdict = 'pdf'
try { $pres.SaveAs($Pdf, $ppSaveAsPDF, $msoFalse) }
catch { $verdict = 'error: export: ' + ($_.Exception.Message -replace '\s+', ' ') }
try { $pres.Close() } catch {}
[void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($pres)
[void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($app)

if ($verdict -eq 'pdf') {
    if (-not (Test-Path -LiteralPath $Pdf) -or (Get-Item -LiteralPath $Pdf).Length -eq 0) {
        $verdict = 'error: PowerPoint wrote no PDF (' + [System.IO.Path]::GetFileNameWithoutExtension($Deck) + ')'
    } elseif ($repaired) { $verdict = 'pdf repaired' }
}
Write-Output $verdict
