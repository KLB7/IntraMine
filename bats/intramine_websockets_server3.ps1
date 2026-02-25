param (
    [int]$port
)
# Define the server details
$ip = "127.0.0.1"
$url = "http://$ip`:$port/" # WebSocket servers usually use a URL format for the listener

# Create a CancellationToken source for graceful shutdown
$cancelTokenSource = New-Object System.Threading.CancellationTokenSource
$cancellationToken = $cancelTokenSource.Token

# Create the HttpListener to handle incoming HTTP requests and upgrade them to WebSockets
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($url)
$listener.Start()
Write-Host "WebSocket Server listening on $url"

# Global variable to store active connections (optional, for simple single client example)
$global:clients = @()

# Function to handle individual client connections
function HandleClient($context) {
    # Accept the WebSocket request
    $websocketContext = $context.AcceptWebSocketAsync("powershell-protocol", $cancellationToken).Result
    $webSocket = $websocketContext.WebSocket
    $global:clients += $webSocket
    Write-Host "Client connected: $($context.Request.RemoteEndPoint)"

    # Handle incoming messages
    $buffer = New-Object System.ArraySegment[byte]::new(1024)
    while ($webSocket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
        try {
            $result = $webSocket.ReceiveAsync($buffer, $cancellationToken).Result
            
            if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Text) {
                $message = [System.Text.Encoding]::UTF8.GetString($buffer.Array, 0, $result.Count)
                Write-Host "Received: $message"

                # Echo message back to client
                $sendBuffer = [System.Text.Encoding]::UTF8.GetBytes("Echo: $message")
                $sendSegment = New-Object System.ArraySegment[byte]::new($sendBuffer)
                $webSocket.SendAsync($sendSegment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cancellationToken) | Out-Null
            } elseif ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                Write-Host "Client requested close."
                $webSocket.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "Closing", $cancellationToken) | Out-Null
            }
        } catch {
            Write-Host "Error with client connection: $_.Exception.Message"
            break
        }
    }
    Write-Host "Client disconnected."
    $global:clients = $global:clients | Where-Object { $_ -ne $webSocket }
    $webSocket.Dispose()
}

# Start accepting client requests in a background job or separate thread
# This is crucial so PowerShell doesn't block on the Accept action
$job = Start-Job -ScriptBlock {
    param($listener, $cancelToken)
    while ($listener.IsListening -and !$cancelToken.IsCancellationRequested) {
        try {
            $context = $listener.GetContextAsync().Result
            # Handle each client in its own thread/task for concurrency
            [System.Threading.Tasks.Task]::Run( { HandleClient -context $context } ) | Out-Null
        } catch [System.Net.HttpListenerException] {
            # Listener might throw an exception when stopping
            if ($_.ErrorCode -ne 995) { Write-Host "Listener error: $_.Exception.Message" }
        }
    }
} -ArgumentList $listener, $cancellationToken

Write-Host "Press Enter to stop the server..."
[Console]::ReadLine() | Out-Null

# Stop the server gracefully
$cancelTokenSource.Cancel()
$listener.Stop()
$listener.Close()
Receive-Job $job # Clean up the job
Remove-Job $job
Write-Host "Server stopped."
