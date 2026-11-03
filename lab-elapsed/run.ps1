param([string]$Out)
$fmts = @('s:m" @ hour "[hh]', 's" secs and "[m]" mins"', 's:[h]', 'm:[s]', 's:[hh]:mm', '[h]:s', 's:[mm]')
$vals = @(0, 0.5, 1, 0.0854629629, 0.25, 3.14159, 10, 100)
$x = New-Object -ComObject Excel.Application; $x.DisplayAlerts = $false
$lines = @("system`tvalue`tfmt`tvia`ttext")
foreach ($sys in 1900, 1904) {
  $wb = $x.Workbooks.Add(); $ws = $wb.Worksheets.Item(1)
  if ($sys -eq 1904) { $wb.Date1904 = $true }
  for ($i = 0; $i -lt $vals.Count; $i++) {
    $r = $i + 2; $ws.Cells.Item($r, 1).Value2 = [double]$vals[$i]
    for ($j = 0; $j -lt $fmts.Count; $j++) {
      $f = $fmts[$j]
      $ws.Cells.Item($r, 2 + $j).Formula = '=TEXT($A' + $r + ',"' + $f.Replace('"', '""') + '")'
      $c = $ws.Cells.Item($r, 9 + $j); $c.Value2 = [double]$vals[$i]
      try { $c.NumberFormat = $f } catch { }
    }
  }
  $ws.Columns.AutoFit() | Out-Null
  for ($i = 0; $i -lt $vals.Count; $i++) {
    $r = $i + 2
    for ($j = 0; $j -lt $fmts.Count; $j++) {
      $lines += "$sys`t$($vals[$i])`t$($fmts[$j])`tTEXT`t$($ws.Cells.Item($r, 2 + $j).Text)"
      $lines += "$sys`t$($vals[$i])`t$($fmts[$j])`tnumfmt`t$($ws.Cells.Item($r, 9 + $j).Text)"
    }
  }
  $wb.Close($false)
}
$x.Quit()
[IO.File]::WriteAllLines($Out, $lines, (New-Object Text.UTF8Encoding $false))
