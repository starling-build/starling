Start-Sleep -Seconds 3
$s = $Host.UI.RawUI.WindowSize
"grid $($s.Height)x$($s.Width)" | Out-File -Encoding ascii 'C:\bench\gridprobe.txt'
Start-Sleep 600
