' Launcher.vbs - Convention de nommage
On Error Resume Next

Dim strPath, objFSO, objShell, strCommand, strArgs

Set objShell = CreateObject("WScript.Shell")
Set objFSO = CreateObject("Scripting.FileSystemObject")

strPath = objFSO.GetParentFolderName(WScript.ScriptFullName)

If WScript.Arguments.Count > 0 Then
    strArgs = WScript.Arguments(0)
    strArgs = Replace(strArgs, """", "\""")
    strCommand = "powershell.exe -NoExit -ExecutionPolicy Bypass -NoProfile -File """ & strPath & "\src\Main.ps1"" """ & strArgs & """"
Else
    strCommand = "powershell.exe -NoExit -ExecutionPolicy Bypass -NoProfile -File """ & strPath & "\src\Main.ps1"""
End If

objShell.Run strCommand, 1, False

Set objShell = Nothing
Set objFSO = Nothing
