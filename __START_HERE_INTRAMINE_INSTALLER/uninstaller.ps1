# Uninstall_IntraMine.ps1
# Remove everything installed by IntraMine
# except Perl and the IntraMine folder.
# To remove Perl, use Windows to uninstall Strawberry Perl.
# To remove the IntraMine folder - just delete it.

### Elevate privileges ("Run as Administator") if not done yet.
# If needed, a new PowerShell window will open.
if(!([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
	Start-Process -FilePath PowerShell.exe -Verb Runas -ArgumentList "-File `"$($MyInvocation.MyCommand.Path)`"  `"$($MyInvocation.MyCommand.UnboundArguments)`""
	Exit
   }

$ScriptDirectory = $PSScriptRoot

# The uninstaller has no "stage" tracking, just try to
# delete everything.

# Various locations:
$StageFile = -join($ScriptDirectory, "\tempstage.txt")
$DownloadPerlPath = "$env:TEMP\perl540.msi"
$OlderDownloadPerlPath = "$env:TEMP\perl53822.msi"
$EsDownloadPath = "$env:TEMP\Es.zip"
$EsInstalledFolder = "C:\elasticsearch-9.0.1"
$OlderEsInstalledFolder = "C:\elasticsearch-8.8.1"
$EsExpandedFolder = "$env:TEMP\elasticsearch-9.0.1"
$OlderEsExpandedFolder = "$env:TEMP\elasticsearch-8.8.1"
$FwwsInstalledFolder = "C:\fwws"
$CTagsFolderName = "ctags-p6.1.20250504.0-x64"
$OlderCTagsFolderName = "ctags-p6.0.20230827.0-x64"
$CtagsInstalledFolder = "C:/" + $CTagsFolderName
$OlderCtagsInstalledFolder = "C:/" + $OlderCTagsFolderName
$CtagsDownloadPath = "$env:TEMP\Ctags.zip"
$CtagsDestinationPath = -join("$env:TEMP\", $CTagsFolderName)
$OlderCtagsDestinationPath = -join("$env:TEMP\", $OlderCTagsFolderName)

try {

# Remove the file that tracks completed stage number.
If (Test-Path -Path $StageFile)
	{
	Remove-Item $StageFile
	}

# Remove StrawberryPerl installer.
If (Test-Path -Path $DownloadPerlPath)
	{
	Remove-Item $DownloadPerlPath
	}
If (Test-Path -Path $OlderDownloadPerlPath)
	{
	Remove-Item $OlderDownloadPerlPath
	}

# Elasticsearch:
# Stop and uninstall service, delete folder, delete unzipped folder, delete zip.
If (Test-Path -Path $EsInstalledFolder)
	{
	try
		{
		C:\elasticsearch-9.0.1\bin\elasticsearch-service.bat stop
		C:\elasticsearch-9.0.1\bin\elasticsearch-service.bat remove
		}
	catch
		{
		# Probably Es isn't installed.
		}
	}

If (Test-Path -Path $OlderEsInstalledFolder)
	{
	try
		{
		C:\elasticsearch-8.8.1\bin\elasticsearch-service.bat stop
		C:\elasticsearch-8.8.1\bin\elasticsearch-service.bat remove
		}
	catch
		{
		# Probably Es isn't installed.
		}
	}

If (Test-Path -Path $EsInstalledFolder)
	{
	Remove-Item -Path $EsInstalledFolder -Force -Recurse
	}
If (Test-Path -Path $EsExpandedFolder)
	{
	Remove-Item -Path $EsExpandedFolder -Force -Recurse
	}
	
If (Test-Path -Path $OlderEsInstalledFolder)
	{
	Remove-Item -Path $OlderEsInstalledFolder -Force -Recurse
	}
If (Test-Path -Path $OlderEsExpandedFolder)
	{
	Remove-Item -Path $OlderEsExpandedFolder -Force -Recurse
	}

If (Test-Path -Path $EsDownloadPath)
	{
	Remove-Item $EsDownloadPath
	}

# File Watcher
If (Test-Path -Path $FwwsInstalledFolder)
	{
	try
		{
		sc.exe stop "File Watcher Windows Service"
		sc.exe delete "File Watcher Windows Service"
		}
	catch
		{
		# Probably File Watcher isn't running.
		}
	
	Start-Sleep -Seconds 3
	Remove-Item -Path $FwwsInstalledFolder -Force -Recurse
	}

# Ctags
# Delete: C:\ctags..., expanded temp version, and temp .zip.
If (Test-Path -Path $CtagsInstalledFolder)
	{
	Remove-Item -Path $CtagsInstalledFolder -Force -Recurse
	}
If (Test-Path -Path $OlderCtagsInstalledFolder)
	{
	Remove-Item -Path $OlderCtagsInstalledFolder -Force -Recurse
	}

If (Test-Path -Path $CtagsDestinationPath)
	{
	Remove-Item -Path $CtagsDestinationPath -Force -Recurse
	}
If (Test-Path -Path $OlderCtagsDestinationPath)
	{
	Remove-Item -Path $OlderCtagsDestinationPath -Force -Recurse
	}

If (Test-Path -Path $CtagsDownloadPath)
	{
	Remove-Item $CtagsDownloadPath
	}

Write-Host "Done. Elasticsearch, Universal ctags, and" -f Green
Write-Host "File Watcher Utilities have been removed." -f Green
Write-Host "To remove Perl, use Settings -> Apps -> Installed apps." -f Green
Write-Host "To remove IntraMine proper, just delete its folder." -f Green
Read-Host -Prompt "Press Enter to finish"
}
catch {
	Write-Host "Uninstall failed. Please see IntraMine's Documentation folder" -f Red
	Write-Host "in the INSTALLING AND RUNNING INTRAMINE section for details on what" -f Red
	Write-Host "was installed, and how to remove services etc by hand." -f Red
}