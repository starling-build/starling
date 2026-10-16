# Opens one .docx in Microsoft Word for Windows and has Word export it as a
# PDF -- test/docx-word-pdf.applescript's counterpart, for lab documents on
# the Windows box.
#
#   powershell -File test\docx-word-pdf.ps1 DOC.docx OUT.pdf
#
# Prints "pdf" or "error: ...". Word is driven over COM with its alerts off
# and the document opened read-only, without a window, and without
# converting or repairing anything. A Word already running is used and left
# running; otherwise the script starts one and quits it afterwards.
# (`New-Object -ComObject Word.Application` starts a NEW hidden Word every
# time, never the one there is: when this script left its Word running, two
# days of lab prints left 259 of them, 32 GB, and the box out of memory.)
#
# Word for Windows has other faces than Word for Mac, and the corpus's
# prints (test/corpus/docx/word) are the Mac's: a lab printed here settles
# a layout rule only when it is set in a face both have (宋体, 黑体, 楷体,
# 仿宋, Times New Roman, Arial).
param(
    [Parameter(Mandatory = $true)][string]$Doc,
    [Parameter(Mandatory = $true)][string]$Pdf
)
$ErrorActionPreference = 'Stop'
$Doc = [System.IO.Path]::GetFullPath($Doc)
$Pdf = [System.IO.Path]::GetFullPath($Pdf)
if (-not (Test-Path -LiteralPath $Doc)) { Write-Output "error: no such document $Doc"; exit 0 }
Remove-Item -LiteralPath $Pdf -Force -ErrorAction SilentlyContinue

$wdExportFormatPDF = 17
$wdAlertsNone = 0
$started = $false
try { $app = [System.Runtime.InteropServices.Marshal]::GetActiveObject('Word.Application') }
catch {
    try { $app = New-Object -ComObject Word.Application; $started = $true }
    catch { Write-Output "error: no Word ($($_.Exception.Message -replace '\s+', ' '))"; exit 0 }
}
$app.DisplayAlerts = $wdAlertsNone
try {
    # Open(FileName, ConfirmConversions, ReadOnly, AddToRecentFiles, …, Visible)
    $d = $app.Documents.Open($Doc, $false, $true, $false, '', '', $true, '', '', 0, 0, $false)
    try {
        $d.ExportAsFixedFormat($Pdf, $wdExportFormatPDF)
        Write-Output 'pdf'
    } finally { $d.Close(0) }
} catch {
    Write-Output "error: $($_.Exception.Message -replace '\s+', ' ')"
} finally {
    if ($started) { try { $app.Quit(0) } catch {} }
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($app)
}
