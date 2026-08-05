Set WshShell = CreateObject("WScript.Shell")

WScript.Sleep 2000

If WshShell.AppActivate("Spotify") Then
    WScript.Sleep 100
    WshShell.SendKeys " "
End If