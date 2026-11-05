param($Dir)
$xl=New-Object -ComObject Excel.Application; $xl.Visible=$false; $xl.DisplayAlerts=$false
"file`trow2_height_pt`trow30_height_pt`tstdHeight`tdefaultRowH"
foreach($n in 'asis','view','fmtpr','cols'){
  $wb=$xl.Workbooks.Open((Join-Path $Dir "rowfmt-$n.xlsx")); $ws=$wb.Worksheets(1)
  "{0}`t{1}`t{2}`t{3}" -f $n,$ws.Rows(2).RowHeight,$ws.Rows(30).RowHeight,$ws.StandardHeight
  $ws.ExportAsFixedFormat(0,(Join-Path $Dir "rowfmt-$n.pdf")); $wb.Close($false)
}
$xl.Quit()
