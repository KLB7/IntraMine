' Run .\foldermonitor.ps1 without a window.
Dim objShell,objFSO,objFile,sCurPath,strPath,strCMD

Set objShell = CreateObject("WScript.Shell")
Set objFSO = CreateObject("Scripting.FileSystemObject")

'Path for PowerShell Script "foldermonitor.ps1" in our folder, eg
'strPath="C:\perlprogs\mine\bats\filewatcher.ps1"
' TEMP OUT
'sCurPath = objFSO.GetParentFolderName(WScript.ScriptFullName)
'strPath = sCurPath & "\foldermonitor.ps1"
strPath = "C:\perlprogs\mine\test\test_dummy_foldermonitor.ps1"

'verify file exists
If objFSO.FileExists(strPath) Then
'return short path name
    set objFile=objFSO.GetFile(strPath)
    strCMD="powershell -nologo -command " & Chr(34) & "&{" &_
     objFile.ShortPath & "}" & Chr(34) 
    'Uncomment next line for debugging
    'WScript.Echo strCMD
    
    'use 0 to hide window
    objShell.Run strCMD,0

Else

'Display error message
    WScript.Echo "Failed to find " & strPath
    WScript.Quit
    
End If
