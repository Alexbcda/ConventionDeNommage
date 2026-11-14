' Launcher.vbs - Lance ASSISTANT sans fenetre console (raccourci + clic droit PDF).
' Conservez STA via powershell.exe -STA. PDF transmis via ASSISTANT_PDF (chemins avec espaces OK).
Option Explicit

Dim sh, fso, root, psExe, ps1, cmd, pdfArg

Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

root = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = root & "\src\LaunchAssistant.ps1"
psExe = sh.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"

If Not fso.FileExists(ps1) Then
    MsgBox "LaunchAssistant.ps1 introuvable :" & vbCrLf & ps1, vbCritical, "ASSISTANT"
    WScript.Quit 1
End If

If Not fso.FileExists(psExe) Then
    MsgBox "powershell.exe introuvable :" & vbCrLf & psExe, vbCritical, "ASSISTANT"
    WScript.Quit 1
End If

If WScript.Arguments.Count > 0 Then
    pdfArg = Trim(WScript.Arguments(0))
    If Len(pdfArg) > 0 Then
        sh.Environment("PROCESS").Item("ASSISTANT_PDF") = pdfArg
    End If
End If

cmd = """" & psExe & """ -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """"
' 0 = fenetre masquee ; False = ne pas attendre la fin
sh.Run cmd, 0, False

Set sh = Nothing
Set fso = Nothing
