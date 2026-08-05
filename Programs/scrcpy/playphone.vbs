Set WshShell = CreateObject("WScript.Shell")

Set fso = CreateObject("Scripting.FileSystemObject")


' ==============================
' SCRCPY DIRECTORY
' ==============================

' Automatically gets the folder where this VBS is located

scrcpyFolder = fso.GetParentFolderName(WScript.ScriptFullName)

scrcpy = scrcpyFolder & "\scrcpy.exe"



' ==============================
' VERIFY SCRCPY EXISTS
' ==============================

If Not fso.FileExists(scrcpy) Then

    MsgBox "scrcpy.exe not found:" & vbCrLf & scrcpy, vbCritical, "scrcpy Error"

    WScript.Quit

End If



' ==============================
' SET WORKING DIRECTORY
' ==============================

WshShell.CurrentDirectory = scrcpyFolder



' ==============================
' START SCRCPY
' ==============================

WshShell.Run """" & scrcpy & """ --video-codec=h264 --video-bit-rate=16M --max-fps=120 --audio-bit-rate=128K --audio-buffer=100 --video-buffer=0 --stay-awake --window-title=""Phone"" --power-off-on-close", 0, False



' ==============================
' WAIT FOR UNLOCK
' ==============================

WScript.Sleep 15000



' ==============================
' SCREEN OFF
' ==============================

WshShell.AppActivate "Pixel 9"

WshShell.SendKeys "%o"