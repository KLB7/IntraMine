param (
    [int]$port
)
#Requires -Version 7.0
#Add-Type -AssemblyName System.Net.WebSockets

[System.Reflection.Assembly]::LoadWithPartialName("System.Net.WebSockets.WebSocketServer")

$server = New-Object System.Net.WebSockets.WebSocketServer -ArgumentList "127.0.0.1", $port

$server.OnConnect = {
    param($context)
    $global:client = $context.WebSocket
    Write-Host "Client connected: $($context.WebSocket.RemoteEndPoint)"
}

$buffer = New-Object byte[] 1024
$result = $client.ReceiveAsync($buffer, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()

if ($result.MessageType -ne [System.Net.WebSockets.WebSocketMessageType]::Close) {
    $message = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
    $client.SendAsync([System.Text.Encoding]::UTF8.GetBytes("Echo: $message"), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None)
}

$server.Start()
Read-Host "Press Enter to stop the server..."
$server.Stop()

