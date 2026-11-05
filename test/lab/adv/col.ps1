$xl=New-Object -ComObject Excel.Application; $xl.Visible=$true; $xl.DisplayAlerts=$false
$wb=$xl.Workbooks.Add(); $ws=$wb.Worksheets(1); $w=$xl.ActiveWindow
"normal font: $($xl.StandardFont) $($xl.StandardFontSize)"
"zoom=$($w.Zoom)  ver=$($xl.Version)"
"what`tColumnWidth`tpoints`tpx(PointsToScreenPixelsX)`tpx(from-pt-96dpi)"
function row($n,$c){ $pt=$c.Width; "{0}`t{1}`t{2}`t{3}`t{4}" -f $n,$c.ColumnWidth,$pt,$w.PointsToScreenPixelsX($pt),($pt*96/72) }
row 'default(A)' $ws.Columns(1)
"stdWidth=$($ws.StandardWidth) $($ws.Cells(1,1).EntireColumn.ColumnWidth)"
foreach($v in [double[]](7,9.0667,8.43,10,12)){ $ws.Columns(2).ColumnWidth=$v; row "set $v" $ws.Columns(2) }
$wb.Close($false); $xl.Quit()
