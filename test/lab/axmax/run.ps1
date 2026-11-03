param($Out)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Force $Out | Out-Null
$xl=New-Object -ComObject Excel.Application; $xl.Visible=$false; $xl.DisplayAlerts=$false
$wb=$xl.Workbooks.Add(); $ws=$wb.Worksheets.Item(1); $ws.Name='d'
$rows=@(); $r=1; $res=@()
function Add-Chart($name,$type,$cols,$data){
  # data: array of arrays (series), 4 categories
  $script:r0=$script:r
  $ws.Cells.Item($script:r,1).Value2=$name
  for($k=0;$k -lt 4;$k++){ $ws.Cells.Item($script:r+1+$k,1).Value2="C$($k+1)" }
  for($s=0;$s -lt $data.Count;$s++){ for($k=0;$k -lt 4;$k++){ $ws.Cells.Item($script:r+1+$k,2+$s).Value2=[double]$data[$s][$k] } }
  $co=$ws.ChartObjects().Add(300,10+($script:n*260),420,250); $script:n++
  $ch=$co.Chart; $ch.ChartType=$type
  while($ch.SeriesCollection().Count -gt 0){$ch.SeriesCollection(1).Delete()|Out-Null}
  for($s=0;$s -lt $data.Count;$s++){
    $se=$ch.SeriesCollection().NewSeries(); $se.Values=$ws.Range($ws.Cells.Item($script:r+1,2+$s),$ws.Cells.Item($script:r+4,2+$s)); $se.XValues=$ws.Range($ws.Cells.Item($script:r+1,1),$ws.Cells.Item($script:r+4,1))
    $se.ChartType=$cols[$s]
  }
  $ch.HasTitle=$false; $ch.HasLegend=$false
  $ch.Refresh()
  $ax=$ch.Axes(2)
  $mx=$ax.MaximumScale; $mn=$ax.MinimumScale; $mu=$ax.MajorUnit
  $script:res+= "$name`t$mn`t$mx`t$mu`t$($ax.MaximumScaleIsAuto)"
  $script:r+=7
}
$script:n=0; $script:r=1; $script:res=@()
foreach($m in 70000,72000,75000,75900,78000,80000,82000,85000,90000,95000){ Add-Chart "a-col-$m" 51 @(51) @(,@($m,5000,30000,10000)) }
foreach($m in 70000,72000,75000,75900,78000,80000,82000,85000,90000,95000){ Add-Chart "b-col-min20k-$m" 51 @(51) @(,@($m,20000,40000,30000)) }
foreach($m in 75900,85000){ Add-Chart "c-area-$m" 1 @(1) @(,@($m,5000,30000,10000)); Add-Chart "c-line-$m" 4 @(4) @(,@($m,5000,30000,10000)) }
Add-Chart "d-stackarea-38500+37400" 76 @(76,76) @(@(38500,5000,20000,10000),@(37400,5000,10000,10000))
Add-Chart "d-arealine-area75900" 1 @(1,4) @(@(75900,5000,30000,10000),@(40000,3000,20000,8000))
Add-Chart "d-arealine-line75900" 1 @(1,4) @(@(40000,3000,20000,8000),@(75900,5000,30000,10000))
Add-Chart "d-arealine-both75900" 1 @(1,4) @(@(75900,5000,30000,10000),@(75900,2000,15000,6000))
$res | Set-Content -Encoding utf8 (Join-Path $Out 'axmax.tsv')
$wb.SaveAs((Join-Path $Out 'axmax.xlsx'),51)
$i=1; foreach($co in $ws.ChartObjects()){ $co.Chart.Export((Join-Path $Out ("chart{0:00}.png" -f $i)))|Out-Null; $i++ }
$wb.Close($false); $xl.Quit()
