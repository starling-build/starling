param($F,$Out)
New-Item -ItemType Directory -Force $Out | Out-Null
$xl=New-Object -ComObject Excel.Application; $xl.Visible=$false; $xl.DisplayAlerts=$false
$wb=$xl.Workbooks.Open($F)
"sheet`tchartW`tchartH`tpaTop`tpaLeft`tpaW`tpaH`tinTop`tinLeft`tinW`tinH`ttitleTop`ttitleLeft`ttitleH`ttitleW`tlegTop`tlegLeft`tlegW`tlegH`tentries"
function g($b){ try{ & $b }catch{ '' } }
foreach($ws in $wb.Worksheets){
  $co=$ws.ChartObjects(1); $ch=$co.Chart; $ca=$ch.ChartArea
  $ti=if($ch.HasTitle){$ch.ChartTitle}else{$null}; $lg=if($ch.HasLegend){$ch.Legend}else{$null}; $pa=$ch.PlotArea
  $ent=''
  if($lg){ try{ $ent=(@($lg.LegendEntries()|%{ '{0:N2}/{1:N2}/{2:N2}/{3:N2}' -f $_.Left,$_.Top,$_.Width,$_.Height }) -join ';') }catch{ $ent='n/a' } }
  $row=@($ws.Name,$ca.Width,$ca.Height,$pa.Top,$pa.Left,$pa.Width,$pa.Height,$pa.InsideTop,$pa.InsideLeft,$pa.InsideWidth,$pa.InsideHeight)
  if($ti){$row+=@($ti.Top,$ti.Left,$ti.Height,$ti.Width)}else{$row+=@('','','','')}
  if($lg){$row+=@($lg.Top,$lg.Left,$lg.Width,$lg.Height)}else{$row+=@('','','','')}
  $row+=$ent
  ($row -join "`t")
  try{ $ws.ExportAsFixedFormat(0,(Join-Path $Out ($ws.Name+'.pdf'))) }catch{ "ERR $($ws.Name) $_"; break }
}
try{$wb.Close($false)}catch{}; try{$xl.Quit()}catch{}
