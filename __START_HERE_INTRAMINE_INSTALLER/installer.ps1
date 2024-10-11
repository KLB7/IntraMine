# installer.ps1: configure IntraMine
# and install various needed additional apps.
#
# Overview
# Elevate privileges ("Run as administator") if needed
# Cannot continue if can't find the IntraMine folder
# Note what's already installed
# If retrying, reset the failed stage (delete files/folders etc)
# Copy IntraMine\_copy_and_rename_to_data to IntraMine\data
# You are asked to enter a list of directories to monitor/index
# Strawberry Perl: download and install
# Perl modules: download and Install
# Elasticsearch: download, unzip, install and start
# File Watcher: install (not started yet)
# Universal ctags: download and Install
# Configure and start File Watcher, build Elasticsearch index
# Start IntraMine, available at localhost:81/Search etc

### Elevate privileges ("Run as Administator") if not done yet.
# If needed, a new PowerShell window will open.
if(!([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
 Start-Process -FilePath PowerShell.exe -Verb Runas -ArgumentList "-File `"$($MyInvocation.MyCommand.Path)`"  `"$($MyInvocation.MyCommand.UnboundArguments)`""
 Exit
}

### Let's get the stopper out of the way, cannot continue if
#   we can't find the IntraMine folder.
$ScriptDirectory = $PSScriptRoot
$IntraMineM1Dir = Split-Path -Parent $ScriptDirectory
$IntraMineM2Dir = Split-Path -Parent $IntraMineM1Dir
$IntraMineDir = '';
if (($IntraMineM1Dir -match 'IntraMine$'))
	{
	$IntraMineDir = $IntraMineM1Dir
	}
else
	{
	if (($IntraMineM2Dir -match 'IntraMine$'))
		{
		$IntraMineDir = $IntraMineM2Dir
		}
	else
		{
		Write-Host -f Red "ERROR CANNOT CONTINUE, could not find the IntraMine main directory."
		Write-Host -f Red "$IntraMineM1Dir is not it."
		Write-Host -f Red "$IntraMineM2Dir is not it."
		Read-Host -Prompt "Sorry about that, press Enter to finish"
		Exit
		}
	}

# Stage completed tracking.
$StageFile = -join($ScriptDirectory, "\tempstage.txt")
$THESTAGEVARIABLEASASTRING = ''
$RECOVEREDStageCompleted = 0
If(Test-Path -Path $StageFile)
	{
	$THESTAGEVARIABLEASASTRING = Get-Content -Path $StageFile -RAW -Encoding ascii
	$RECOVEREDStageCompleted = [int]$THESTAGEVARIABLEASASTRING
	}
# 0..up, 0 means not started, 1 means stage 1 completed etc.
$StageCompleted = $RECOVEREDStageCompleted
# Stages:
$DataFolderCompleted = 1
$FoldersToIndexCompleted = 2
$PerlInstallCompleted = 3
$PerlModulesCompleted = 4
$ElasticsearchCompleted = 5;
$FileWatcherCompleted = 6
$CtagsCompleted = 7
$AllCompleted = 8



### Note what's already installed.
# (From there on the goal is no stoppers, so we will just skip a stage
# if something seems to have been installed already. However, there
# will be a retry if there's a problem.)
# Check Strawberry Perl, Elasticsearch 8.8.1, File Watcher,
# and universal ctags.
$PerlHasBeenInstalled = $false
$EsHasBeenInstalled = $false
$FwwsHasBeenInstalled = $false
$CtagsHasBeenInstalled = $false

$SourceDataFolder = -join($IntraMineDir, "\_copy_and_rename_to_data")
$DestDataFolder = -join($IntraMineDir, "\data")
$DirectoriesListPath = -join($IntraMineDir, "\data\search_directories.txt")
$PerlBinFile = "C:\Strawberry\perl\bin\perl.exe"
$DownloadPerlURL = "https://github.com/StrawberryPerl/Perl-Dist-Strawberry/releases/download/SP_54001_64bit_UCRT/strawberry-perl-5.40.0.1-64bit.msi"
$DownloadPerlPath = "$env:TEMP\perl540.msi"
$BatsFolder = -join($IntraMineDir, "\bats")
$PerlModulesBatsPath = -join($BatsFolder, "\install_perl_modules.bat")
$EsInstalledFolder = "C:\elasticsearch-8.8.1"
$EsDownloadPath = "$env:TEMP\Es.zip"
$EsZipPath = 'https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-8.8.1-windows-x86_64.zip';
$EsExpandedFolder = "$env:TEMP\elasticsearch-8.8.1"
$EsExpanderFolderSlashStar = -join($EsExpandedFolder, "\*")
$EsConfigPath = "C:\elasticsearch-8.8.1\config\elasticsearch.yml"
$FwwsInstalledFolder = "C:\fwws"
$SourceFwwsFolder = -join($IntraMineDir, "\fwws")
$CTagsFolderName = "ctags-p6.0.20230827.0-x64"
$CtagsInstalledFolder = "C:/" + $CTagsFolderName
$CtagsDownloadPath = "$env:TEMP\Ctags.zip"
$CtagsZipPath = 'https://github.com/universal-ctags/ctags-win32/releases/download/p6.1.20240623.0/ctags-p6.1.20240623.0-x64.zip'
$CtagsDestinationPath = -join("$env:TEMP\", $CTagsFolderName)
$CtagsExpandedFolder = $CtagsDestinationPath
$CtagsExpanderFolderSlashStar = -join($CtagsExpandedFolder, "\*")
$ConfigPerlScriptPath = -join($ScriptDirectory, "\update_config.pl")
$ConfigKey = "CTAGS_DIR"
$ConfigValue = $CtagsInstalledFolder
$IMINITBatPath = -join($IntraMineDir, "\bats\IM_INIT_INDEX.bat")

# ERROR RECOVERY.
# If installation has been partially completed, undo the last stage
# that did not complete
if ($StageCompleted -gt 0)
	{
	if ($StageCompleted -lt $AllCompleted)
		{
		# Use $StageCompleted to determine what was *not* completed.
		# Eg if it is $PerlInstallCompleted (3) then the stage not
		# completed was the next one, $PerlModulesCompleted (4)
		# Data folder copy is so simple that no recovery is possible.
		# Likewise, editing folders to index is too simple to fail in a recoverable way.

		# Perl can fail if download did not succeed. Try to delete the installer.
		if ($StageCompleted -eq $FoldersToIndexCompleted)
			{
			Remove-Item $DownloadPerlPath
			}
		# Perl module installation, retry
		elseif ($StageCompleted -eq $PerlInstallCompleted)
			{
			# No action needed, just rerun the batch file for cpan modules.
			}
		# Elasticsearch retry
		elseif ($StageCompleted -eq $PerlModulesCompleted)
			{
			# Stop and uninstall service, delete folder, delete unzipped folder, delete zip.
			try
				{
				C:\elasticsearch-8.8.1\bin\elasticsearch-service.bat stop
				C:\elasticsearch-8.8.1\bin\elasticsearch-service.bat remove
				}
			catch
				{
				# Probably Es isn't installed yet.
				}
			
			If (Test-Path -Path $EsInstalledFolder)
				{
				Remove-Item -Path $EsInstalledFolder -Force -Recurse
				}
			If (Test-Path -Path $EsExpandedFolder)
				{
				Remove-Item -Path $EsExpandedFolder -Force -Recurse
				}
			If (Test-Path -Path $EsDownloadPath)
				{
				Remove-Item $EsDownloadPath
				}
			}
		# File Watcher, failure is very unlikely but give it a shot.
		elseif ($StageCompleted -eq $ElasticsearchCompleted)
			{
			# Stop and delete FileWatcher, delete C:\fwws.
			try
				{
				sc.exe stop "File Watcher Windows Service"
				sc.exe delete "File Watcher Windows Service"
				}
			catch
				{
				# Probably File Watcher isn't installed yet.
				}
			If (Test-Path -Path $FwwsInstalledFolder)
				{
				Remove-Item -Path $FwwsInstalledFolder -Force -Recurse
				}
			}
		# Ctags fail, delete download etc
		elseif ($StageCompleted -eq $FileWatcherCompleted)
			{
			# Delete: C:\ctags..., expanded temp version, and temp .zip.
			If (Test-Path -Path $CtagsInstalledFolder)
				{
				Remove-Item -Path $CtagsInstalledFolder -Force -Recurse
				}
			If (Test-Path -Path $CtagsDestinationPath)
				{
				Remove-Item -Path $CtagsDestinationPath -Force -Recurse
				}
			If (Test-Path -Path $CtagsDownloadPath)
				{
				Remove-Item $CtagsDownloadPath
				}
			}
		# Indexing or IntraMine startup failure, not much we can do.
		elseif ($StageCompleted -eq $CtagsCompleted)
			{
			# Cross fingers and try again.
			}
		} # if $StageCompleted < $AllCompleted
	} # if $StageCompleted > 0

if (Test-Path $PerlBinFile)
	{
	Write-Host "Strawberry Perl has already been installed, will continue." -f Green
	$PerlHasBeenInstalled = $true
	}
If(Test-Path -Path $EsInstalledFolder)
	{
	Write-Host "Elasticsearch 8.8.1 has already been installed, will continue." -f Green
	$EsHasBeenInstalled = $true
	}
If(Test-Path -Path $FwwsInstalledFolder)
	{
	Write-Host "File Watcher has already been installed, will continue." -f Green
	$FwwsHasBeenInstalled = $true
	}
If(Test-Path -Path $CtagsInstalledFolder)
	{
	Write-Host "Universal ctags has already been installed, will continue." -f Green
	$CtagsHasBeenInstalled = $true
	}

# "Try" control.
$NumTries = 0
$MaxTries = 5

while ($NumTries -lt $MaxTries)
{
try {


### Copy \_copy_and_rename_to_data to \data
if ($StageCompleted -eq 0)
	{

	### Preamble, advise user to stick around for any questions.
	Write-Host "############################################" -f Yellow
	Write-Host "You are about to install IntraMine." -f Yellow
	Write-Host "PLEASE check back now and then after starting," -f Yellow
	Write-Host "your input will be needed several times." -f Yellow
	Write-Host "Right at the start, you will be asked to enter your" -f Yellow
	Write-Host "list of directories that you want Elasticsearch to index/monitor." -f Yellow
	Write-Host "Then you will be presented with the installer for Strawberry Perl." -f Yellow
	Write-Host "After you have closed the installer, you may be asked to allow Perl to run." -f Yellow
	Write-Host "Press y and Enter to continue during Perl module installation," -f Yellow
	Write-Host "about 20 minutes in." -f Yellow
	Write-Host "Then finally after a few more minutes you will be asked to" -f Yellow
	Write-Host "configure Elasticsearch to run automatically using a dialog." -f Yellow
	Write-Host "Installation will then continue on its own." -f Yellow
	Write-Host "############################################" -f Yellow
	Read-Host -Prompt "Press Enter to continue"

	If(!(Test-Path -Path $DestDataFolder))
		{
		Write-Host "Making data folder ..." -f Yellow
		Copy-Item -Path $SourceDataFolder -Destination $DestDataFolder -Recurse
		Write-Host "data folder made." -f Green
		}
	else
		{
		Write-Host "data folder already exists, will continue." -f Green
		}
	$StageCompleted = $DataFolderCompleted
	Out-File -FilePath $StageFile -InputObject $StageCompleted -Encoding ascii
	}


### Enter list of directories to monitor/index
if ($StageCompleted -eq $DataFolderCompleted)
	{
	Write-Host "***************************" -f Yellow
	Write-Host "** YOUR ATTENTION NEEDED **" -f Yellow
	Write-Host "***************************" -f Yellow
	Write-Host "You are about to see data\search_directories.txt" -f Yellow
	Write-Host "in your default text editor." -f Yellow
	Write-Host "Please review the instructions at top of the file" -f Yellow
	Write-Host "and then fill in the paths to the directories that" -f Yellow
	Write-Host "you want to be indexed/monitored by Elasticsearch." -f Yellow
	Write-Host "" -f Yellow
		
	Read-Host -Prompt "Press Enter to edit data\search_directories.txt"
	Start-Process $DirectoriesListPath
	Read-Host -Prompt "Press Enter to continue after you have updated search_directories.txt"
	
	$StageCompleted = $FoldersToIndexCompleted
	Out-File -FilePath $StageFile -InputObject $StageCompleted -Encoding ascii
	}

### Strawberry Perl: download and install if not present
# Also install needed Perl modules unconditionally.
if ($StageCompleted -eq $FoldersToIndexCompleted)
	{
	if (!$PerlHasBeenInstalled)
		{
		# Remove installer, insist on downloading here.
		If(Test-Path -Path $DownloadPerlPath)
			{
			Remove-Item $DownloadPerlPath
			}

		#Download the installer
		Write-Host "Downloading the Strawberry Perl Installer..." -f Yellow
		Write-Host "When the Perl installer appears, please nurse it along" -f Yellow
		Write-Host "by clicking Next etc ..." -f Yellow
		$ProgressPreference = 'SilentlyContinue'
		Invoke-WebRequest $DownloadPerlURL -OutFile $DownloadPerlPath
		#Write-Host "Done downloading Perl." -f Green
	
		# Run the installer
		Write-Host "***************************" -f Yellow
		Write-Host "** YOUR ATTENTION NEEDED **" -f Yellow
		Write-Host "***************************" -f Yellow
		Write-Host "Please go through the Perl installer that just popped up" -f Yellow
		Write-Host "and return here when done..." -f Yellow
		Start-Process msiexec.exe -Wait -ArgumentList "/I $DownloadPerlPath"
		Write-Host "Done Perl installation." -f Green
		}
	
	$StageCompleted = $PerlInstallCompleted
	Out-File -FilePath $StageFile -InputObject $StageCompleted -Encoding ascii
	}
	
### Install needed Perl modules.
if ($StageCompleted -eq $PerlInstallCompleted)
	{
	Write-Host "Installing additional Perl modules..." -f Yellow
	Write-Host "If you are asked about running Perl, please click Allow." -f Yellow
	Write-Host "NOTE please type y if requested," -f Yellow
	Write-Host "which will be in roughly 20 minutes." -f Yellow
	Read-Host -Prompt "Press Enter to continue"

	# Let the dust settle after Perl installation.
	# Also reload Powershell's environment "Path" variable to pick up Perl.
	Start-Sleep -Seconds 1.0
	$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

	cmd.exe /c $PerlModulesBatsPath
	Write-Host "Done installing Perl modules." -f Green

	$StageCompleted = $PerlModulesCompleted
	Out-File -FilePath $StageFile -InputObject $StageCompleted -Encoding ascii
	}

### Elasticsearch: download, unzip, copy, start, configure
if ($StageCompleted -eq $PerlModulesCompleted)
	{
	if (!$EsHasBeenInstalled)
		{
		# Download
		Write-Host "Downloading Elasticsearch to $EsDownloadPath" -f Yellow
		Write-Host "(this will take a minute) ..." -f Yellow
		# This is critical, the PS progress bar slows download by a silly amount.
		$ProgressPreference = 'SilentlyContinue'
		Invoke-WebRequest $EsZipPath -OutFile $EsDownloadPath
	
		#Expand
		Expand-Archive -Path $EsDownloadPath -DestinationPath "$env:TEMP"
		Write-Host "Elasticsearch has been downloaded and expanded in $EsExpandedFolder" -f Green
	
		# Copy to top of C:\
		New-Item -ItemType Directory -Path $EsInstalledFolder
		Write-Host "New folder $EsInstalledFolder created." -f Green
	
		Write-Host "Copying Elasticsearch to $EsInstalledFolder ..." -f Yellow
		Copy-Item -Path $EsExpanderFolderSlashStar -Destination $EsInstalledFolder -Recurse
		Write-Host "Elasticsearch has been copied to $EsInstalledFolder." -f Green
	
		# Modify config file to disable security.
		Write-Host "Modifying Elasticsearch config/elasticsearch.yml" -f Yellow
		Write-Host "to update security ..." -f Yellow
		Add-Content -Path $EsConfigPath -Value "xpack.security.enabled: false"
		Write-Host "Elasticsearch config has been updated" -f Green
		
		# Install tokenizer
		Write-Host "Adding analysis-icu tokenizer to Elasticsearch ..." -f Yellow
		C:\elasticsearch-8.8.1\bin\elasticsearch-plugin.bat install analysis-icu
		Write-Host "Elasticsearch tokenizer has been added." -f Green
		
		# Install and start Elasticsearch
		Write-Host "Installing and starting Elasticsearch service ..." -f Yellow
		C:\elasticsearch-8.8.1\bin\elasticsearch-service.bat install
		C:\elasticsearch-8.8.1\bin\elasticsearch-service.bat start
		Write-Host "Elasticsearch has been started." -f Green
		Write-Host ""
		Write-Host ""
		
		# Configure Elasticsearch to start automatically
		Write-Host "***************************" -f Yellow
		Write-Host "** YOUR ATTENTION NEEDED **" -f Yellow
		Write-Host "***************************" -f Yellow
		Write-Host "You are about to see a dialog for managing Elasticsearch." -f Yellow
		Write-Host "Under the General tab, please set the Startup type to Automatic," -f Yellow
		Write-Host "then Apply and OK to return here." -f Yellow
		Read-Host -Prompt "Press Enter to see the dialog"
		C:\elasticsearch-8.8.1\bin\elasticsearch-service.bat manager
		Write-Host "Continuing ..." -f Green
		}
	
	$StageCompleted = $ElasticsearchCompleted
	Out-File -FilePath $StageFile -InputObject $StageCompleted -Encoding ascii
	}

if ($StageCompleted -eq $ElasticsearchCompleted)
	{
	if (!$FwwsHasBeenInstalled)
		{
		# Creating C:\fwws
		Write-Host "Installing File Watcher ..." -f Yellow
		Copy-Item -Path $SourceFwwsFolder -Destination $FwwsInstalledFolder -Recurse
		# Install fwws as a service (not starting it yet).
		#sc create "File Watcher Windows Service" binPath= C:\fwws\FileWatcherWindowsService.exe
		sc.exe create "File Watcher Windows Service" binPath= "C:\fwws\FileWatcherWindowsService.exe"
		sc.exe description "File Watcher Windows Service" "Watches for file system changes in the system."
		sc.exe config "File Watcher Windows Service" start=auto
		Write-Host "File Watcher has been installed." -f Green
		}
	
	$StageCompleted = $FileWatcherCompleted
	Out-File -FilePath $StageFile -InputObject $StageCompleted -Encoding ascii
	}

### Universal ctags: download and Install
if ($StageCompleted -eq $FileWatcherCompleted)
	{
	if (!$CtagsHasBeenInstalled)
		{
		# Download
		Write-Host "Downloading ctags to $CtagsDownloadPath ..." -f Yellow
		$ProgressPreference = 'SilentlyContinue'
		Invoke-WebRequest $CtagsZipPath -OutFile $CtagsDownloadPath
		
		#Expand
		Write-Host "Expanding ctags ..." -f Yellow
		New-Item -ItemType Directory -Path $CtagsDestinationPath
		Expand-Archive -Path $CtagsDownloadPath -DestinationPath $CtagsDestinationPath
		Write-Host "Ctags has been downloaded and expanded in $CtagsDestinationPath" -f Yellow
		
		# Copy to top of C:\
		New-Item -ItemType Directory -Path $CtagsInstalledFolder
		Write-Host "New folder $CtagsInstalledFolder created." -f Green
		
		Write-Host "Copying ctags to $CtagsInstalledFolder ..." -f Yellow
		Copy-Item -Path $CtagsExpanderFolderSlashStar -Destination $CtagsInstalledFolder -Recurse
		Write-Host "Ctags has been copied to $CtagsInstalledFolder." -f Green
	
		# Modify data/intramine.config.txt, update CTAGS_DIR
		Write-Host "Updating Intramine/data/intramine_config.txt for ctags location ..." -f Yellow
		Start-Process -wait $ConfigPerlScriptPath -args """$IntraMineDir""","""$ConfigKey""","""$ConfigValue"""
		Write-Host "Ctags location updated." -f Green
		}
		
	$StageCompleted = $CtagsCompleted
	Out-File -FilePath $StageFile -InputObject $StageCompleted -Encoding ascii
	}
	
### Make Elasticsearch index, configure and start File Watcher service, and start IntraMine.
if ($StageCompleted -eq $CtagsCompleted)
	{
	Write-Host "Starting Elasticsearch index build." -f Yellow
	Write-Host "This will happen in a separate window." -f Yellow
	Write-Host "Please be patient, when indexing is finished you will see that" -f Yellow
	Write-Host "IntraMine has started in that separate window." -f Yellow
	Start-Process $IMINITBatPath
	
	### All done.
	$StageCompleted = $AllCompleted
	Out-File -FilePath $StageFile -InputObject $StageCompleted -Encoding ascii
	
	# Drop out of while loop.
	$NumTries = $MaxTries

	# Clean up.
	Write-Host "Removing temporary files ..." -f Yellow
	If (Test-Path -Path $StageFile)
		{
		Remove-Item $StageFile
		}
	If (Test-Path -Path $DownloadPerlPath)
		{
		Remove-Item $DownloadPerlPath
		}
	If (Test-Path -Path $EsExpandedFolder)
		{
		Remove-Item -Path $EsExpandedFolder -Force -Recurse
		}
	If (Test-Path -Path $EsDownloadPath)
		{
		Remove-Item $EsDownloadPath
		}
	If (Test-Path -Path $CtagsDestinationPath)
		{
		Remove-Item -Path $CtagsDestinationPath -Force -Recurse
		}
	If (Test-Path -Path $CtagsDownloadPath)
		{
		Remove-Item $CtagsDownloadPath
		}
	
	Write-Host "Installation is finishing in a new window." -f Green
	Write-Host "when it's done, you will see a hummingbird and UP! and then you can" -f Green
	Write-Host "visit IntraMine in your browser at http://localhost:81/Search" -f Green
	Write-Host "(No bird, just text off the right? That's a Cmd window bug," -f Green
	Write-Host "visit IntraMine and it will almost certainly be there.)" -f Green
	Write-Host "To STOP IntraMine double-click on bats/STOP_INTRAMINE.bat" -f Green
	Write-Host "To START IntraMine again, double-click on bats/START_INTRAMINE.bat" -f Green
	Write-Host ""
	Read-Host -Prompt "Press Enter when you are done reading the above"
	Write-Host "You can close this window now."	-f Green
	}

} # End try
catch {
	Write-Host "Install failed. The error was:" -f Red
	Write-Host $_
	$NumTries++
	if ($NumTries -lt $MaxTries)
		{
		Write-Host "Will retry ..." -f Yellow
		Start-Sleep -Seconds 2.0
		}
	else
		{
		Write-Host "Alas, the installer is giving up."
		Write-Host "If you are determined, please try the manual install"
		Write-Host "as described in the IntraMine/Documentation/ folder,"
		Write-Host "HOWEVER, if you know what went wrong and can correct the problem,"
		Write-Host "you could try running IntraMine/__START_HERE_INTRAMINE_INSTALLER/uninstaller.ps1"
		Write-Host "and then run this script a second time."
		Read-Host -Prompt "Press Enter when you are done reading the above"
		}
}
}# while