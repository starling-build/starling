param($Dir)
$xl=New-Object -ComObject Excel.Application; $xl.Visible=$false; $xl.DisplayAlerts=$false
"file`trow`trowH_afterAutoFit`tlast_used_col`tnames"
foreach($n in 'lab-calibri','lab-arial','lab-url'){
  $wb=$xl.Workbooks.Open((Join-Path $Dir "$n.xlsx")); $ws=$wb.Worksheets(1)
  $null=$ws.UsedRange.Rows.AutoFit()
  $ur=$ws.UsedRange
  foreach($r in $ur.Rows){ "{0}`t{1}`t{2}`t{3}`t{4}" -f $n,$r.Row,$r.RowHeight,$ur.Columns.Count,'' }
  $ws.ExportAsFixedFormat(0,(Join-Path $Dir "$n-af.pdf"))
  $wb.Close($false)
}
$xl.Quit()
