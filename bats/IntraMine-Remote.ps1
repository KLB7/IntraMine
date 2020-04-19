# IntraMine-Remote.ps1: run this script on a remote PC to allow editing files on your IntraMine PC.
#####################
# ABSOLUTELY ESSENTIAL
# Sorry for shouting, but start your remote editor using
# "Run as administrator" before starting this script. The simplest way to do that is make
# a shortcut to your editor, then right-click for Properties and under the Shortcut tab
# click "Advanced..." and select "Run as administrator". Both your editor and this script
# must be started via "Run as administrator" or this just won't work.
#####################
# Based on https://gallery.technet.microsoft.com/scriptcenter/Powershell-Webserver-74dcf466
# by Markus Scholtes.
#
# Configuration, installation and running:
#
# On your IntraMine box:
# 
# 1. First, check the port number on the "$BINDING" line below, "43124" by default.
#    Make it the the same as
#     "INTRAMINE_FIRST_SWARM_SERVER_PORT" in IntraMine's data/intramine_config.txt file.
# 2. Also in data/intramine_config.txt, set ALLOW_REMOTE_EDITING and
#    USE_APP_FOR_REMOTE_EDITING to 1. Set REMOTE_OPENER_APP to the name of one of
#    the editor options listed just below REMOTE_OPENER_APP. You can make up your
#    own if you like. Do verify that the path to the editor is correct, it is for
#    the editor location on each remote PC rather than on your IntraMine box
#    (and note that means you will need the same location on all remote PCs).
#    The default is
#    REMOTE_OPENER_APP	REMOTE_OPENER_ECLIPSE
#    with REMOTE_OPENER_ECLIPSE set just below that to C:\eclipse\eclipse\eclipse.exe
#    - no doubt your location for Eclipse, if you're using it, will differ so fix it up.
#    If any remote PC doesn't have the editor in the specified place, then IntraMine's
#    Editor service will be used instead, if it's running.
# 3. IntraMine needs to know how to come up with a path to a file on the IntraMine box,
#    from the perspective of a remote PC. Near the bottom of intramine_config.txt
#    you'll find "Mappings for use by remote PCs". For best results any directory you
#    share in order to allow remote editing should also be entered in your list of
#    directories to index, in data/search_directories.txt and should match exactly.
#    To make an entry for eg "C:\Qt": first, share the folder on your IntraMine box
#    as eg "devQt", under an account that your remote PC can use; note the host name
#    for your IntraMine box (see "Device name" under Settings -> System -> About);
#    make an entry in intramine_config.txt for the share, eg
#    C:Qt	\\host-name\devQt
#    
#
# On each remote PC:
# 1. Connect to all the shares that you established above for remote editing and
#    enter your credentials for them if needed.
# 2. Save this script to your remote PC. I'll use "C:\PS\IntraMine-Remote.ps1" below.
# 3. Right-click on your remote "C:\PS\IntraMine-Remote.ps1" and select "Unblock".
# 4. Configure a firewall exception to allow access to the chosen port:
#    at a cmd prompt on the remote PC, started with "Run as administrator", enter:
#	netsh advfirewall firewall add rule name="IntraMine-Remote" dir=in action=allow protocol=TCP localport=43124
#     (The name is arbitrary, localport should again be the same as in "$BINDING".)
#   If you no longer want this server later, you can remove the firewall rule by name with, e.g.:
#	netsh advfirewall firewall delete rule name="IntraMine-Remote"
# 5. Start your remote editor using "Run as administrator" (see the shouting above).
# 6. Start PowerShell with administrative rights ("Run as administrator") on the remote PC. Type or paste
#      Set-ExecutionPolicy Bypass
#      C:\PS\IntraMine-Remote.ps1
#    (using your actual path of course) and press Enter.
#
# 7. To stop the server, on the remote PC use http://localhost:43124/?app=quit
# (where of course the 43124 number should agree with "INTRAMINE_FIRST_SWARM_SERVER_PORT").

$BINDING = 'http://+:43124/'

$LISTENER = New-Object System.Net.HttpListener
$LISTENER.Prefixes.Add($BINDING)
$LISTENER.Start()
$Error.Clear()

try
    {
    while ($LISTENER.IsListening)
        {
        $CONTEXT = $LISTENER.GetContext()
        $REQUEST = $CONTEXT.Request
        $RESPONSE = $CONTEXT.Response
         $RECEIVED = '{0} {1}' -f $REQUEST.httpMethod, $REQUEST.Url.LocalPath
        $query = $REQUEST.Url.Query

        $queryCollection = $REQUEST.QueryString
        $app = $queryCollection["app"]
        $path = $queryCollection["path"]

        # Done if app=quit
        if ($app -eq "quit")
            {
            break;
            }

		# Not needed.
        ###$app = [System.Net.WebUtility]::UrlDecode($app)
        ###$path = [System.Net.WebUtility]::UrlDecode($path)

        $responseMessage = "OK"
        $BUFFER = [Text.Encoding]::UTF8.GetBytes($responseMessage)
        $CONTEXT.Response.OutputStream.Write($BUFFER, 0, $BUFFER.Length)
		# Sometimes the response has already been closed by this point.
		# PS will notice and die without the try{}.
        try {$CONTEXT.Response.Close()} catch {}

        $app = -join("`"", $app, "`"")
        $path = -join("`"", $path, "`"")

        # Start-Process will execute properly without the try/catch, but then PowerShell, in
        # one of its introspective moments, might re-examine the command arguments and suffer
        # intolerable, fatal, shame at what it's just done.
        try {Start-Process -NoNewWindow -FilePath $app -ArgumentList $path} catch {}
        }
    }
finally
    {
	# Stop listening.
	$LISTENER.Stop()
	$LISTENER.Close()
	Write-Host "IntraMine-Remote service stopped."
    }