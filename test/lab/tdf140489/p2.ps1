param($F)
$xl=New-Object -ComObject Excel.Application; $xl.Visible=$false; $xl.DisplayAlerts=$false
$wb=$xl.Workbooks.Open($F,0,$true)
foreach($ws in $wb.Worksheets){ if($ws.ChartObjects().Count -gt 0){ $ch=$ws.ChartObjects(1).Chart; break } }
foreach($s in $ch.SeriesCollection()){ "$($s.Name) formula=$($s.Formula)"; if($s.Name -like '*Sizing*'){ "X=" + ($s.XValues -join ','); "Y=" + ($s.Values -join ',') } }
"HasAxis(2,1)=$($ch.HasAxis(2,1)) HasAxis(2,2)=$($ch.HasAxis(2,2)) HasAxis(1,1)=$($ch.HasAxis(1,1)) HasAxis(1,2)=$($ch.HasAxis(1,2))"
foreach($t in 1,2){ foreach($g in 1,2){ try{ $a=$ch.Axes($t,$g); "Axes($t,$g) min=$($a.MinimumScale) max=$($a.MaximumScale) major=$($a.MajorUnit)" }catch{ "Axes($t,$g) ERR" } } }
$wb.Close($false); $xl.Quit()
