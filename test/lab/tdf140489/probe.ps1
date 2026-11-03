param($F,$Out)
$xl=New-Object -ComObject Excel.Application; $xl.Visible=$false; $xl.DisplayAlerts=$false
$res=New-Object System.Collections.ArrayList
function Dump($wb,$label){
  $ch=$null
  foreach($ws in $wb.Worksheets){ if($ws.ChartObjects().Count -gt 0){ $ch=$ws.ChartObjects(1).Chart; break } }
  if(-not $ch){ foreach($c in $wb.Charts){ $ch=$c; break } }
  $ch.Refresh()
  foreach($g in 1,2){ foreach($t in 1,2){
    try{ if($ch.HasAxis($t,$g)){ $a=$ch.Axes($t,$g)
      if($t -eq 2 -or $true){ $null=$res.Add("$label`tgroup$g type$t`t$($a.MinimumScale)`t$($a.MaximumScale)`t$($a.MajorUnit)`tminAuto=$($a.MinimumScaleIsAuto) maxAuto=$($a.MaximumScaleIsAuto) majAuto=$($a.MajorUnitIsAuto)") } } }catch{ $null=$res.Add("$label`tgroup$g type$t`tERR $($_.Exception.Message)") }
  } }
}
function Series($wb){
  $ch=$null; foreach($ws in $wb.Worksheets){ if($ws.ChartObjects().Count -gt 0){ $ch=$ws.ChartObjects(1).Chart; break } }
  if(-not $ch){ foreach($c in $wb.Charts){ $ch=$c; break } }
  $i=1; foreach($s in $ch.SeriesCollection()){ $null=$res.Add("series`t$i`t$($s.Name)`ttype=$($s.ChartType)`taxisgroup=$($s.AxisGroup)`tsmooth=$(try{$s.Smooth}catch{'n/a'})`tn=$(try{$s.Values.Count}catch{'?'})`tmax=$(try{($s.Values|Measure-Object -Maximum).Maximum}catch{'?'})"); $i++ }
}
function Chart($wb){ foreach($ws in $wb.Worksheets){ if($ws.ChartObjects().Count -gt 0){ return $ws.ChartObjects(1).Chart } }; foreach($c in $wb.Charts){ return $c } }
function Run($label,[scriptblock]$act){
  $wb=$xl.Workbooks.Open($F,0,$true)
  try{ $ch=Chart $wb; & $act $ch; Dump $wb $label }catch{ $null=$res.Add("$label`tERR`t$($_.Exception.Message)") }
  $wb.Close($false)
}
$wb=$xl.Workbooks.Open($F,0,$true); Series $wb; Dump $wb 'base'; $wb.Close($false)
function Find($ch,$name){ foreach($s in $ch.SeriesCollection()){ if($s.Name -like "*$name*"){ return $s } } }
Run 'a:delete Year Sizing' { param($ch) (Find $ch 'Year Sizing').Delete()|Out-Null }
Run 'b:YearSizing Y={0,0}' { param($ch) $s=Find $ch 'Year Sizing'; $s.Values=@(0,0) }
Run 'c:delete EQUIVALENT NONTAXABLE RATE' { param($ch) (Find $ch 'EQUIVALENT NONTAXABLE').Delete()|Out-Null }
Run 'd:delete IR_Line' { param($ch) (Find $ch 'IR_Line').Delete()|Out-Null }
Run 'e:IR_Line smooth off' { param($ch) (Find $ch 'IR_Line').Smooth=$false }
Run 'f1:scatter to primary' { param($ch) (Find $ch 'Year Sizing').AxisGroup=1 }
Run 'f2:scatter to secondary' { param($ch) (Find $ch 'Year Sizing').AxisGroup=2 }
$res | Set-Content -Encoding utf8 $Out
$xl.Quit()
