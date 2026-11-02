# mk.ps1 -Out DIR -Type NAME -Scale M : one Word doc with 4 inline charts (widths 200,300,450,600 x 200pt) of one type, one per page; prints axis auto scales.
param([string]$Out, [string]$Type, [double]$M, [string]$Dim = "w")
$ErrorActionPreference = 'Stop'
$types = @{ col2d = 51; bar2d = 57; col3d = 54; stk3d = 61 }
$code = $types[$Type]
$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0
$doc = $word.Documents.Add()
$res = @()
$widths = 200, 300, 450, 600
$heights = 120, 200, 300, 450
$stacked = ($Type -eq 'stk3d')
$fr = @(0.55, 0.8, 0.6, 1.0)   # per-category total/max fraction
$sh = @(0.45, 0.33, 0.22)      # series shares (stacked)
for ($wi = 0; $wi -lt 4; $wi++) {
    $w = $widths[$wi]
    $rng = $doc.Content
    $rng.Collapse(0)
    if ($wi -gt 0) { $rng.InsertBreak(7); $rng = $doc.Content; $rng.Collapse(0) }
    $ish = $doc.InlineShapes.AddChart2(-1, $code, $rng, $true)
    $ch = $ish.Chart
    $ch.ChartData.Activate()
    Start-Sleep -Seconds 3; $wb = $ch.ChartData.Workbook
    $ws = $wb.Worksheets(1)
    $ws.Range("A1:Z50").ClearContents() | Out-Null
    $ws.Cells(1, 1).Value2 = "Cat"
    for ($s = 0; $s -lt 3; $s++) { $ws.Cells(1, $s + 2).Value2 = "S" + ($s + 1) }
    for ($c = 0; $c -lt 4; $c++) {
        $ws.Cells($c + 2, 1).Value2 = "C" + ($c + 1)
        for ($s = 0; $s -lt 3; $s++) {
            if ($stacked) { $v = $M * $fr[$c] * $sh[$s] } else { $v = $M * $fr[$c] * (1.0 - 0.2 * $s) }
            $ws.Cells($c + 2, $s + 2).Formula = ([math]::Round($v, 3)).ToString([cultureinfo]::InvariantCulture)
        }
    }
    try { $ws.ListObjects(1).Resize($ws.Range("A1:D5")) } catch {}
    $ch.SetSourceData("='" + $ws.Name + "'!`$A`$1:`$D`$5")
    $wb.Close()
    if ($Dim -eq "w") { $ish.Width = $w; $ish.Height = 200 } else { $ish.Width = 450; $ish.Height = $heights[$wi]; $w = $heights[$wi] }
    $ax = $ch.Axes(2)
    $res += ("{0}`t{1}`t{2}`t{3}`t{4}`t{5}`t{6}" -f $Type, $M, $w, $ax.MinimumScale, $ax.MaximumScale, $ax.MajorUnit, $ax.MinimumScaleIsAuto) + ("`t{0}`t{1}`t{2}`t{3}" -f $ch.PlotArea.InsideLeft, $ch.PlotArea.InsideTop, $ch.PlotArea.InsideWidth, $ch.PlotArea.InsideHeight)
}
$pdf = Join-Path $Out ("chart2{2}-{0}-{1}.pdf" -f $Type, $M, $Dim)
$dx = [string](Join-Path $Out ("chart2{2}-{0}-{1}.docx" -f $Type, $M, $Dim)); $doc.SaveAs([ref]$dx)
$doc.ExportAsFixedFormat([string]$pdf, 17)
$doc.Close($false)
$word.Quit()
$res
