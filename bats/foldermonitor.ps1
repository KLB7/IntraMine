# foldermonitor.ps1: signal Watcher (intramine_filewatcher.pl) whenever there is a file
# or folder change in the folders monitored by IntraMine. This is done at most once
# per second. The signal causes Watcher to check the log file created by
# the File Watcher service, which contains details on the changes. Alas, File Watcher
# doesn't report the old name for a folder when it is renamed, so this script saves
# the old and new names for a folder change to a file. When Watcher notices a folder
# rename in the File Watcher log, it reads the old name from that file.
# So this script does two things: it signals when a file change has happened, which
# cuts down file re-indexing time, and it supplies the old folder name when a folder
# is renamed.

$ErrorActionPreference='SilentlyContinue'
$ProgressPreference='SilentlyContinue'

$mainPort = $args[0]
$dirListPath = $args[1]
$global:oldNewBasePath = $args[2]
$changeSignal = $args[3]
$heartbeatSignal = $args[4]
$watcherURL = -join("http://localhost:", $mainPort, $changeSignal)
$heartbeatURL = -join("http://localhost:", $mainPort, $heartbeatSignal)
#
# Original author's notice:
#By BigTeddy 05 September 2011 
#Modified by Mohamed Said "MohamedSaid82" 
# Version 1.1 
# (Below is not 1.1, it is heavily modified from the original.)

#This script uses the .NET FileSystemWatcher class to monitor file events in folder(s). 
#The advantage of this method over using WMI eventing is that this can monitor sub-folders. 
#The -Action parameter can contain any valid Powershell commands.

# Just send a WebRequest once per second.
$global:thereWasAnEvent = $false
# For tracking folder renames:
$global:oldNewPaths = ''
$global:oldNewCounter = 1
$global:heartbeatCounter = 1

# define the code that should execute when a file change is detected
$Action = {
    # $details = $event.SourceEventArgs
    # $Name = $details.Name
    # $FullPath = $details.FullPath
    # $OldFullPath = $details.OldFullPath
    # $OldName = $details.OldName
    # $ChangeType = $details.ChangeType
    # $Timestamp = $event.TimeGenerated
	
	$details = $event.SourceEventArgs
	if ($details.ChangeType -eq 'Renamed')
		{
		# We will write out a list of old and new names for a rename event. This picks up
		# file as well as folder renames, but renames are not common and Watcher will
		# ignore the file renames.
		$global:oldNewPaths = $global:oldNewPaths + $details.OldFullPath + '|' + $details.FullPath + '|' + [Environment]::NewLine
		}

    #Invoke-WebRequest -AllowUnencryptedAuthentication -Uri $watcherURL # For as-it-happens notifications
    $global:thereWasAnEvent = $true
}

 
# Get list of paths to monitor.
$paths = Get-Content $dirListPath

# Remember the various $fsw's
$fswList = @()

# Make a unique SourceIdentifier for each path and event name.  
$i=0

foreach ($path in $paths)
{
$fsw = New-Object System.IO.FileSystemWatcher
$fsw.Path  = $path
$fsw.IncludeSubdirectories = $true
# This += scales poorly, apparently.
$fswList += $fsw

# Make sure the watcher emits events
$fsw.EnableRaisingEvents = $true

$handlers = . {
    # Register-ObjectEvent -InputObject $fsw -EventName Changed -Action $Action -SourceIdentifier "$i+FSChange"
    # Register-ObjectEvent -InputObject $fsw -EventName Created -Action $Action -SourceIdentifier "$i+FSCreate"
    # Register-ObjectEvent -InputObject $fsw -EventName Deleted -Action $Action -SourceIdentifier "$i+FSDelete"
    # Register-ObjectEvent -InputObject $fsw -EventName Renamed -Action $Action -SourceIdentifier "$i+FSRename"
	
    Register-ObjectEvent $fsw Changed -SourceIdentifier "$i+FSChange" -Action $Action
    # Create/Delete aren't that urgent, and are fully picked up in fwws.
    #Register-ObjectEvent $fsw Created -SourceIdentifier "$i+FSCreate" -Action $Action
    #Register-ObjectEvent $fsw Deleted -SourceIdentifier "$i+FSDelete" -Action $Action
    Register-ObjectEvent $fsw Renamed -SourceIdentifier "$i+FSRename" -Action $Action

    # Register-ObjectEvent $fsw Changed -SourceIdentifier "$i+FSChange" -Action { $global:thereWasAnEvent = $true }
    # Register-ObjectEvent $fsw Created -SourceIdentifier "$i+FSCreate" -Action {
	# $global:thereWasAnEvent = $true }
    # Register-ObjectEvent $fsw Deleted -SourceIdentifier "$i+FSDelete" -Action { $global:thereWasAnEvent = $true }
    # Register-ObjectEvent $fsw Renamed -SourceIdentifier "$i+FSRename" -Action { $global:thereWasAnEvent = $true }
    }
$i = $i+1
} 

 try
{
    do
    {
    Wait-Event -Timeout 1
    if ($global:thereWasAnEvent)
        {
        $global:thereWasAnEvent = $false
			# Stop if IntraMine does not respond:
			#Invoke-WebRequest -Uri $watcherURL | Out-Null
		# Stop only if forced to stop: 
        try {Invoke-WebRequest -UseBasicParsing -Uri $watcherURL | Out-Null} catch {}
		
		# Save list of folder renames to disk, one old name pipe new name per line.
		if ($global:oldNewPaths -ne '')
			{
			try {
			$counter = [string]$global:oldNewCounter
			# Old-new path for renames, eg 'C:\fwws\oldnew4.txt'
			$oldnewFilePath = $global:oldNewBasePath + $counter + '.txt'
			$global:oldNewPaths | Out-File -Encoding UTF8 $oldnewFilePath -NoNewline
			} catch {}
			
			$global:oldNewPaths = ''
			$global:oldNewCounter = $global:oldNewCounter + 1
			if ($global:oldNewCounter -gt 10)
				{
				$global:oldNewCounter = 1
				}
			}
        }
    
    # Send a "heartbeat" signal once a minute;
    $global:heartbeatCounter = $global:heartbeatCounter + 1
    if ($global:heartbeatCounter -gt 60)
        {
        try {Invoke-WebRequest -UseBasicParsing -Uri $heartbeatURL | Out-Null} catch {}
        $global:heartbeatCounter = 1
        }
    #Write-Host "." -NoNewline
    } while ($true)
}
finally
{
    # this gets executed when user presses CTRL+C or on $proc->Kill().
    # remove the event handlers
    $i=0
    foreach ($path in $paths)
    {
    Unregister-Event -SourceIdentifier "$i+FSChange"
    Unregister-Event -SourceIdentifier "$i+FSCreate"
    Unregister-Event -SourceIdentifier "$i+FSDelete"
    Unregister-Event -SourceIdentifier "$i+FSRename"
    # remove filesystemwatcher
    $fsw = $fswList[$i]
    $fsw.EnableRaisingEvents = $false
    $fsw.Dispose()
    $i = $i+1
   }
    # remove background jobs
    $handlers | Remove-Job
	
	# Neither of these gets the job done.
	#$host.Exit()
	#[Environment]::Exit(1)
	Exit
}
