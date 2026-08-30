Set sh = CreateObject("WScript.Shell")
rc = sh.Run("cmd /c powershell -NoProfile -ExecutionPolicy Bypass -File C:\dist\vid\take.ps1 > C:\dist\vid\take.log 2>&1", 0, True)
Set fso = CreateObject("Scripting.FileSystemObject")
Set f = fso.CreateTextFile("C:\dist\vid\take.done")
f.WriteLine rc
f.Close
