param($Out)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Force $Out | Out-Null
$fonts=@(@('Segoe UI',8),@('Segoe UI',9),@('Segoe UI',10),@('Arial',8),@('Arial',9),@('Arial',10),@('Verdana',8),@('Tahoma',8),@('Times New Roman',8),@('Calibri',8),@('Calibri',9),
 @('Segoe UI',14),@('Arial',14),@('Verdana',14),@('Tahoma',14),@('Times New Roman',14),@('Calibri',14))
$xl=New-Object -ComObject Excel.Application; $xl.Visible=$false; $xl.DisplayAlerts=$false
$tsv=@()
foreach($book in @(@('calibri11','Calibri',11),@('verdana10','Verdana',10))){
  $wb=$xl.Workbooks.Add(); $ws=$wb.Worksheets.Item(1)
  $st=$wb.Styles.Item('Normal'); $st.Font.Name=$book[1]; $st.Font.Size=$book[2]
  $ws.Cells.Item(1,1).Value2='A1 control'; $ws.Cells.Item(1,2).Value2='B1 default'
  for($i=0;$i -lt $fonts.Count;$i++){
    $r=$i+2; $ws.Cells.Item($r,1).Value2="A$r"; $c=$ws.Cells.Item($r,2); $c.Value2="B$r $($fonts[$i][0]) $($fonts[$i][1])"
    $c.Font.Name=$fonts[$i][0]; $c.Font.Size=$fonts[$i][1]
  }
  $rg=$ws.Range($ws.Cells.Item(1,1),$ws.Cells.Item($fonts.Count+1,1)); foreach($e in 8,9,12){ $rg.Borders.Item($e).LineStyle=1; $rg.Borders.Item($e).Color=255 }
  $ws.Columns.Item(2).ColumnWidth=40
  $ws.Rows.AutoFit()|Out-Null
  for($r=1;$r -le $fonts.Count+1;$r++){ $lab= if($r -eq 1){'control'}else{"$($fonts[$r-2][0]) $($fonts[$r-2][1])"}; $tsv+="$($book[0])`t$r`t$lab`t$($ws.Rows.Item($r).RowHeight)" }
  $wb.SaveAs((Join-Path $Out ($book[0]+'.xlsx')),51); $wb.Close($false)
}
$xl.Quit()
$tsv | Set-Content -Encoding utf8 (Join-Path $Out 'rowheights-com.tsv')
