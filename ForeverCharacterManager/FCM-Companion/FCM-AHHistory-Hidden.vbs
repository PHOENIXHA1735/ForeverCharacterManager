' Run only FCM's installed AHHistory script without a visible console.
' One fixed, validated argument selects personal scans (default) or explicit
' provider-table opt-in. No arbitrary command or filesystem path is accepted.
Option Explicit

Dim fso, shell, companion, addonRoot, scriptPath, psExe, mode, flags, command, result
If WScript.Arguments.Count <> 1 Then WScript.Quit 64

mode = LCase(Trim(WScript.Arguments(0)))
Select Case mode
    Case "personal"
        flags = ""
    Case "provider"
        flags = " -IncludeProviderTables"
    Case Else
        WScript.Quit 64
End Select

Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

companion = fso.GetParentFolderName(WScript.ScriptFullName)
addonRoot = fso.GetParentFolderName(companion)
scriptPath = fso.BuildPath(companion, "FCM-AHHistory.ps1")
psExe = fso.BuildPath(shell.ExpandEnvironmentStrings("%SystemRoot%"), "System32\WindowsPowerShell\v1.0\powershell.exe")

If Not fso.FileExists(scriptPath) Then WScript.Quit 2
If Not fso.FileExists(psExe) Then WScript.Quit 2

command = Chr(34) & psExe & Chr(34) & _
    " -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File " & _
    Chr(34) & scriptPath & Chr(34) & " -Mode Sync -AddonRoot " & _
    Chr(34) & addonRoot & Chr(34) & flags

' 0 hides the child process; True waits and preserves the script exit code.
result = shell.Run(command, 0, True)
WScript.Quit result
