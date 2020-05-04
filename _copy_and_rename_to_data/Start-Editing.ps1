#Requires -RunAsAdministrator

# Before running for the first time:
# 1. Go through "Editing documents.txt#Remote editing" if you haven't already.
# 2. Change $EDITORPATH just below to your preferred editor for your remote PC.
# 3. If you have changed INTRAMINE_FIRST_SWARM_SERVER_PORT
#    in IntraMine's data/intramine_config.txt files,
#    then set "$EDITORPORT" below to the same number. Default "43124".

# Modify the version in IntraMine's data/ folder,
# not the _copy_and_rename_to_data/ folder. Then copy this to your remote PC.

# To start this, open a Powershell prompt using "Run as administrator"
# and then enter the path to this script, eg "C:\somefolder\Start-Editing.ps1".
# To stop this, go back to the Powershell prompt window and type CTRL+C.
# You can also enter the address "http://localhost:43124/?app=quit" in a browser,
# where 43124 is your "EDITORPORT" below. Note your editor won't exit either way.


$EDITORPATH = "C:/eclipse/eclipse/eclipse.exe"
$EDITORPORT = "43124"


Set-ExecutionPolicy Bypass

# Start your preferred editor.
Start-Process -verb runAs -FilePath $EDITORPATH


# Run a tiny service that passes
# a request to edit a document on to your preferred server.
#
# Based on
# https://gallery.technet.microsoft.com/scriptcenter/Powershell-Webserver-74dcf466
# by Markus Scholtes.
# and
# https://gist.github.com/Diagg/f57b330f340e4f42fed26dd5759cca05
# by Diagg
# with hints borrowed from
# https://stackoverflow.com/questions/9188352/is-it-possible-to-call-httplistener-getcontext-with-a-timeout

$BINDING = -join("http://+:", $EDITORPORT, "/")

[console]::TreatControlCAsInput = $true

$TimeOut = 2000

# New-ScriptBlockCallback is a lot of boilerplate that allows
# callbacks to work properly in PowerShell.
function New-ScriptBlockCallback 
    {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
        param(
            [parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [scriptblock]$Callback
        )

        # Is this type already defined?
        if (-not ( 'CallbackEventBridge' -as [type])) {
            Add-Type @' 
                using System; 
 
                public sealed class CallbackEventBridge { 
                    public event AsyncCallback CallbackComplete = delegate { }; 
 
                    private CallbackEventBridge() {} 
 
                    private void CallbackInternal(IAsyncResult result) { 
                        CallbackComplete(result); 
                    } 
 
                    public AsyncCallback Callback { 
                        get { return new AsyncCallback(CallbackInternal); } 
                    } 
 
                    public static CallbackEventBridge Create() { 
                        return new CallbackEventBridge(); 
                    } 
                } 
'@
        }
        $bridge = [callbackeventbridge]::create()
        Register-ObjectEvent -InputObject $bridge -EventName callbackcomplete -Action $Callback -MessageData $args > $null
        $bridge.Callback
    }

$LISTENER = New-Object System.Net.HttpListener
$LISTENER.Prefixes.Add($BINDING)
$LISTENER.Start()
$Error.Clear()

# The main event, send a file path to the preferred editor.
# Stop the service if "app=quit" is received.
$requestListener = {
            [cmdletbinding()]
            param($result)

            [System.Net.HttpListener]$LISTENER = $result.AsyncState;

            # Call EndGetContext to complete the asynchronous operation.
            $CONTEXT = $LISTENER.EndGetContext($result);

            # Capture the details about the request
            $REQUEST = $CONTEXT.Request


            # Setup a place to deliver a response
            $RESPONSE = $CONTEXT.Response
			
			$queryCollection = $REQUEST.QueryString
			$app = $queryCollection["app"]
			$path = $queryCollection["path"]

			# Done if app=quit
			if ($app -eq "quit")
				{
				$LISTENER.Stop(); Write-Host "IntraMine-Remote service has received a quit request."; exit
				}
			
			$responseMessage = "OK"
			$BUFFER = [Text.Encoding]::UTF8.GetBytes($responseMessage)
			$RESPONSE.OutputStream.Write($BUFFER, 0, $BUFFER.Length)
			# Sometimes the response has already been closed by this point.
			# PS will notice and die without the try{}.
			try {$RESPONSE.OutputStream.Close(); $RESPONSE.Close()} catch {}

			$app = -join("`"", $app, "`"")
			$path = -join("`"", $path, "`"")

			# Start-Process will execute properly without the try/catch, but then PowerShell, in
			# one of its introspective moments, might re-examine the command arguments and suffer
			# intolerable, fatal, shame at what it's just done.
			try {Start-Process -NoNewWindow -FilePath $app -ArgumentList $path} catch {}
    }  


# Launch Async request callback for the first time
$CONTEXT = $LISTENER.BeginGetContext((New-ScriptBlockCallback -Callback $requestListener), $LISTENER)

# Listen and handle requests (with $requestListener) until
# CTRL+C is received or $LISTENER has been stopped.
try
    {
    while ($LISTENER.IsListening)
		{
		$Success = $CONTEXT.AsyncWaitHandle.WaitOne($TimeOut, $false)
		
		# Timed out?
		if (!$Success)
			{
			# Check for CTRL+C
			if ([console]::KeyAvailable)
				{
				$key = [system.console]::readkey($true)
				if (($key.modifiers -band [consolemodifiers]"control") -and ($key.key -eq "C"))
					{
					break;
					}
				}
			}
		else
			{
			try {$CONTEXT = $LISTENER.BeginGetContext((New-ScriptBlockCallback -Callback $requestListener), $LISTENER)} catch {}
			}
		}
	}
finally
    {
	# Stop listening.
	$LISTENER.Stop()
	$LISTENER.Close()
	Write-Host "IntraMine-Remote service stopped."
    }
