param($Dir)
$xl=New-Object -ComObject Excel.Application; $xl.Visible=$false; $xl.DisplayAlerts=$false
"file`tcell`tcolW_pt`trowH_pt`ttext"
foreach($n in 'lab-calibri','lab-arial','lab-url'){
  $wb=$xl.Workbooks.Open((Join-Path $Dir "$n.xlsx")); $ws=$wb.Worksheets(1); $ur=$ws.UsedRange
  foreach($c in $ur.Cells){ if($c.Value2 -ne $null){ "{0}`t{1}`t{2}`t{3}`t{4}" -f $n,$c.Address($false,$false),$c.ColumnWidth,$c.RowHeight,$c.Value2 } }
  $ws.ExportAsFixedFormat(0,(Join-Path $Dir "$n.pdf"))
  $wb.Close($false)
}
$xl.Quit()
