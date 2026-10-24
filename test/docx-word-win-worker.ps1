# One batch of test/docx-word-win-reprint.py: prints each key in KEYS (a file,
# one key per line) from DOCS\<key>.docx to OUT\<key>-orig.pdf with ONE Word,
# then quits it. The driver restarts it every batch, so a long run cannot
# drift the way the Mac's one Word did (embedded faces printing blank, CJK
# faces falling back) -- and watches it, since a COM call that hangs never
# returns.
#
# Prints one line per event, for the driver to read:
#   word <pid>              the Word this batch started (the driver kills it on a hang)
#   start <key>             about to open it
#   ok <key> <pages> <sec>
#   error <key> <message>
param(
    [Parameter(Mandatory = $true)][string]$Keys,
    [Parameter(Mandatory = $true)][string]$Docs,
    [Parameter(Mandatory = $true)][string]$Out
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$wdExportFormatPDF = 17
$wdStatisticPages = 2
$before = @(Get-Process WINWORD -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
try { $app = New-Object -ComObject Word.Application }
catch { Write-Output "fatal no Word ($($_.Exception.Message -replace '\s+', ' '))"; exit 1 }
$mine = @(Get-Process WINWORD -ErrorAction SilentlyContinue | Where-Object { $before -notcontains $_.Id })
if ($mine.Count -eq 1) { Write-Output "word $($mine[0].Id)" }
[Console]::Out.Flush()
$app.DisplayAlerts = 0
$app.Visible = $false
# Macros never run (msoAutomationSecurityForceDisable); layout is Word's own.
try { $app.AutomationSecurity = 3 } catch {}
try { $app.Options.Pagination = $true } catch {}
try {
    foreach ($key in Get-Content -LiteralPath $Keys -Encoding UTF8) {
        $key = $key.Trim()
        if (-not $key) { continue }
        # [string]: Join-Path's result is a wrapped string, and handed to
        # ExportAsFixedFormat as one, Word hangs for good, with no error.
        [string]$doc = Join-Path $Docs "$key.docx"
        [string]$pdf = Join-Path $Out "$key-orig.pdf"
        [string]$tmp = Join-Path $Out "$key-orig.part.pdf"
        Write-Output "start $key"; [Console]::Out.Flush()
        $t0 = Get-Date
        try {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            # Open(FileName, ConfirmConversions, ReadOnly, AddToRecentFiles, …, Visible)
            $d = $app.Documents.Open($doc, $false, $true, $false, '', '', $true, '', '', 0, 0, $false)
            try {
                # Lay the whole document out before printing it: the Mac's
                # prints fired mid-layout and later pages came out wrong.
                # (A document locked for editing refuses Repaginate; counting
                # its pages lays it out all the same.)
                try { $d.Repaginate() } catch {}
                $pages = $d.ComputeStatistics($wdStatisticPages)
                $d.ExportAsFixedFormat($tmp, $wdExportFormatPDF)
            } finally { $d.Close(0) }
            Move-Item -LiteralPath $tmp -Destination $pdf -Force
            Write-Output ("ok {0} {1} {2:N1}" -f $key, $pages, ((Get-Date) - $t0).TotalSeconds)
        } catch {
            Write-Output "error $key $($_.Exception.Message -replace '\s+', ' ')"
        }
        [Console]::Out.Flush()
    }
} finally {
    # (Quit() bare: Quit(0) throws in PowerShell 5.1, its argument a ref.)
    try { $app.Quit() } catch {}
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($app)
}
