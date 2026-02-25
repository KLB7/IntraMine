param (
    [int]$port
)
#Requires -Version 7.0
#Add-Type -AssemblyName System.Net.WebSockets
[System.Reflection.Assembly]::LoadWithPartialName("System.Net.WebSockets")


$clients = New-Object System.Collections.Generic.List[System.Net.WebSockets.WebSocket]
$listener = New-Object System.Net.HttpListener
###$url = "http://localhost:$port/"
$url = -join("http://", "127.0.0.1:", $port, "/")
$listener.Prefixes.Add($url)
$listener.Start()
Write-Host "WebSocket server listening on $url"

# Function to broadcast a message to all connected clients
function Send-Message($message) {
    # Convert string message to byte array
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($message)
    $segment = New-Object System.ArraySegment[byte[]]($buffer, 0, $buffer.Length)

    # Iterate through all clients and send the message
    foreach ($client in $clients) {
        if ($client.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            $client.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None) | Out-Null
        }
    }
}

# Async function to handle client connections
$handleConnectionsAsync = [Action]{
    while ($listener.IsListening) {
        $context = $listener.GetContextAsync().Result
        if ($context.Request.IsWebSocketRequest) {
            $webSocketContext = $context.AcceptWebSocketAsync().Result
            $webSocket = $webSocketContext.WebSocket
            $clients.Add($webSocket)
            Write-Host "Client connected: $($context.Request.RemoteEndPoint). Total clients: $($clients.Count)"
            Send-Message "A new client has joined the chat."

            # Handle messages from this client in a separate thread/task
            # ... (see function below)
            [System.Threading.Tasks.Task]::Run( {
                $buffer = New-Object byte[](1024)
                $bufferSegment = New-Object System.ArraySegment[byte[]]($buffer)
                try {
                    while ($webSocket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
                        $receiveResult = $webSocket.ReceiveAsync($bufferSegment, [System.Threading.CancellationToken]::None).Result

                        if ($receiveResult.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Text) {
                            $message = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $receiveResult.Count)
                            Write-Host "Received message: $message"
                            Send-Message "$message" # Broadcast the received message
                        }
                        elseif ($receiveResult.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                            Write-Host "Client disconnected: $($context.Request.RemoteEndPoint)"
                            $clients.Remove($webSocket)
                            Send-Message "A client has left."
                            break
                        }
                    }
                }
                catch {
                    Write-Host "Error with client connection: $_"
                    $clients.Remove($webSocket)
                }
            }) | Out-Null
        } else {
            $context.Response.StatusCode = 400
            $context.Response.Close()
        }
    }
}

# Run the connection handling function in the background
[System.Threading.Tasks.Task]::Run($handleConnectionsAsync) | Out-Null

Write-Host "Server is running. Press Enter to stop."
Read-Host
$listener.Stop()
Write-Host "Server stopped."
