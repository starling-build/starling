# Opens one .xlsx in Microsoft Excel for Windows and has Excel publish the
# entire workbook as a PDF -- every visible sheet, cut into pages as Excel
# would print them. Driven by test/xlsx-excel-render.sh under Git Bash; the
# Sheets counterpart of test/pptx-powerpoint-pdf.ps1.
#
#   powershell -File test\xlsx-excel-pdf.ps1 BOOK.xlsx OUT.pdf [MAXPAGES]
#
# Prints one of: "pdf", "pdf repaired", or "error: ...". Excel is driven over
# COM with its alerts off, links not updated and macros disabled, the
# workbook opened read-only. A workbook Excel would ask to repair fails a
# plain Open, so it is opened again with CorruptLoad = xlRepairFile and the
# verdict says so -- what Excel prints after its own repair is still the
# picture to compare against. MAXPAGES (default 20) stops the job there: a
# sheet with a value in row 1048576 is tens of thousands of pages.
#
# Unlike PowerPoint, Excel starts a new hidden instance for every
# New-Object, so this script quits the one it started; an Excel the user has
# open is another process and is left alone. Excel cuts pages by the metrics
# of the active printer -- the README beside the corpus records which one
# the references were made with.
param(
    [Parameter(Mandatory = $true)][string]$Book,
    [Parameter(Mandatory = $true)][string]$Pdf,
    [int]$MaxPages = 20
)
$ErrorActionPreference = 'Stop'
# Git Bash hands over /c/... or mixed paths; COM wants a real Windows one.
$Book = [System.IO.Path]::GetFullPath($Book)
$Pdf = [System.IO.Path]::GetFullPath($Pdf)
if (-not (Test-Path -LiteralPath $Book)) { Write-Output "error: no such workbook $Book"; exit 0 }
Remove-Item -LiteralPath $Pdf -Force -ErrorAction SilentlyContinue
$name = [System.IO.Path]::GetFileNameWithoutExtension($Book)

$xlTypePDF = 0; $xlQualityStandard = 0
$xlRepairFile = 1
$msoAutomationSecurityForceDisable = 3
$missing = [Type]::Missing

try { $app = New-Object -ComObject Excel.Application }
catch {
    $hint = if ($_.Exception.Message -match '80080005') { ' -- run from a shell that is not elevated' } else { '' }
    Write-Output "error: no Excel ($($_.Exception.Message -replace '\s+', ' '))$hint"; exit 0
}
$app.Visible = $false
$app.DisplayAlerts = $false
$app.AskToUpdateLinks = $false
$app.EnableEvents = $false
try { $app.AutomationSecurity = $msoAutomationSecurityForceDisable } catch {}
# A workbook set up for A4 prints on A4: Excel's "Scale content for A4 or
# 8.5 x 11\" paper sizes" (on by default) would print it on Letter where
# Letter is the region's paper, and the same file would then have two
# references. The option is the user's and is saved with Excel's settings,
# so it is put back before quitting.
$mapPaper = $null
try { $mapPaper = $app.MapPaperSize; $app.MapPaperSize = $false } catch {}

$wb = $null; $repaired = $false; $why = ''
try {
    # Filename, UpdateLinks = 0 (never), ReadOnly
    $wb = $app.Workbooks.Open($Book, 0, $true)
} catch {
    $why = $_.Exception.Message
    try {
        # ... Format, Password, WriteResPassword, IgnoreReadOnlyRecommended,
        # Origin, Delimiter, Editable, Notify, Converter, AddToMru, Local,
        # CorruptLoad
        $wb = $app.Workbooks.Open($Book, 0, $true, $missing, $missing, $missing, $true,
                                  $missing, $missing, $missing, $missing, $missing, $false, $missing, $xlRepairFile)
        $repaired = $true
    } catch { $why = $_.Exception.Message }
}

$verdict = 'pdf'
if ($null -eq $wb) {
    $verdict = "error: Excel refused ${name}: " + ($why -replace '\s+', ' ')
} else {
    try {
        # Type, Filename, Quality, IncludeDocProperties, IgnorePrintAreas,
        # From, To, OpenAfterPublish
        $wb.ExportAsFixedFormat($xlTypePDF, $Pdf, $xlQualityStandard, $false, $false, 1, $MaxPages, $false)
    } catch { $verdict = 'error: export: ' + ($_.Exception.Message -replace '\s+', ' ') }
    try { $wb.Close($false) } catch {}
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($wb)
}
if ($null -ne $mapPaper) { try { $app.MapPaperSize = $mapPaper } catch {} }
try { $app.Quit() } catch {}
[void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($app)

if ($verdict -eq 'pdf') {
    if (-not (Test-Path -LiteralPath $Pdf) -or (Get-Item -LiteralPath $Pdf).Length -eq 0) {
        $verdict = "error: Excel wrote no PDF ($name)"
    } elseif ($repaired) { $verdict = 'pdf repaired' }
}
Write-Output $verdict
