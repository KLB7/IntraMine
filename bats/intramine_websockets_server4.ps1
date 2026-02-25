param (
    [int]$port
)

write-host "Web Listener: Start"

# maybe need to allow script execution via
# Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine

try {
   $listener = New-Object System.Net.HttpListener
#    $listener.Prefixes.Add('http://+:81/')  # listen on ony interface (matching netsh or running on admin console required)
   $listener.Prefixes.Add('http://localhost:5000/')
   $listener.Start()
}
catch {
   write-error "Unable to open listener. Check Admin permission or NETSH Binding"
   exit 1
}

# Helper for awaiting async tasks on powershell
# see https://blog.ironmansoftware.com/powershell-async-method/#:~:text=PowerShell%20does%20not%20provide%20an,when%20calling%20async%20methods%20in%20.
function Wait-Task {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [System.Threading.Tasks.Task[]]$Task
    )
    Begin {
        $Tasks = @()
    }
    Process {
        $Tasks += $Task
    }
    End {
        While (-not [System.Threading.Tasks.Task]::WaitAll($Tasks, 200)) {}
        $Tasks.ForEach( { $_.GetAwaiter().GetResult() })
    }
}
Set-Alias -Name await -Value Wait-Task -Force

# Create a simple Websocke server proving a Message including teh current time
Write-host "Web Listener listening"
[console]::TreatControlCAsInput = $true
while (!([console]::KeyAvailable)) {
   Write-host "Press any key to Stop (requires client to be connected, yet)"
   $context = await $listener.GetContextAsync()
   if ($context.Request.IsWebSocketRequest)
   {
      write-host ("Received Websocket-Request on " + $listener.Prefixes )
      $webSocketContext = await $context.AcceptWebSocketAsync(([NullString]::Value)) # # https://docs.microsoft.com/de-de/dotnet/api/system.net.httplistenercontext.acceptwebsocketasync?view=netframework-4.5
      $webSocket = $webSocketContext.WebSocket;
      $ct = New-Object Threading.CancellationToken($false)
      while ($webSocket.State -eq [System.Net.WebSockets.WebSocketState]::Open -and !([console]::KeyAvailable))
      {
         $date = (get-date -Format yyyy-MM-dd-HH:mm:ss)
         $workitem = "Hello World "+$date;
         [ArraySegment[byte]]$msg = [Text.Encoding]::UTF8.GetBytes($workitem)
         $_ = await $webSocket.SendAsync(
            $msg,
            [System.Net.WebSockets.WebSocketMessageType]::Text, # Binary
            $true,
            $ct
            );
         $_ = await([System.Threading.Tasks.Task]::Delay(1000)); # wait one second # ignore result (ie. write to dummy-variable $_)
      }
   }
   $response = $context.Response
   $response.OutputStream.close()
   $listener.Stop()
}
Write-host "Web Listener Stopping"
$listener.Stop()

