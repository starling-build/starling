param($F,$Out)
New-Item -ItemType Directory -Force $Out | Out-Null
$xl=New-Object -ComObject Excel.Application; $xl.Visible=$false; $xl.DisplayAlerts=$false
$wb=$xl.Workbooks.Open($F)
"sheet`tchartW`tchartH`tpaTop`tpaLeft`tpaW`tpaH`tinTop`tinLeft`tinW`tinH`ttitleTop`ttitleLeft`ttitleH`ttitleW`tlegTop`tlegLeft`tlegW`tlegH`tnEntries`tentries (L/T/W/H|key L/T/W/H)"
function g($b){ try{ & $b }catch{ '' } }
foreach($ws in $wb.Worksheets){
  $co=$ws.ChartObjects(1); $ch=$co.Chart; $ca=$ch.ChartArea
  $ti=if($ch.HasTitle){$ch.ChartTitle}else{$null}; $lg=if($ch.HasLegend){$ch.Legend}else{$null}; $pa=$ch.PlotArea
  $ent=''; $nent=0
  if($lg){ try{ $nent=$lg.LegendEntries().Count; $ent=(@($lg.LegendEntries()|%{ '{0:N2}/{1:N2}/{2:N2}/{3:N2}|key {4:N2}/{5:N2}/{6:N2}/{7:N2}' -f $_.Left,$_.Top,$_.Width,$_.Height,$_.LegendKey.Left,$_.LegendKey.Top,$_.LegendKey.Width,$_.LegendKey.Height }) -join ';') }catch{ $ent="n/a $_" } }
  $row=@($ws.Name,$ca.Width,$ca.Height,$pa.Top,$pa.Left,$pa.Width,$pa.Height,$pa.InsideTop,$pa.InsideLeft,$pa.InsideWidth,$pa.InsideHeight)
  if($ti){$row+=@($ti.Top,$ti.Left,$ti.Height,$ti.Width)}else{$row+=@('','','','')}
  if($lg){$row+=@($lg.Top,$lg.Left,$lg.Width,$lg.Height)}else{$row+=@('','','','')}
  $row+=@($nent,$ent)
  ($row -join "`t")
  try{ $ws.ExportAsFixedFormat(0,(Join-Path $Out ($ws.Name+'.pdf'))) }catch{ "ERR $($ws.Name) $_"; break }
}
try{$wb.Close($false)}catch{}; try{$xl.Quit()}catch{}
