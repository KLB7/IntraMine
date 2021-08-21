// websockets.js
// Open a WebSocket connection to IntraMine's WS service, register trigger strings
// and corresponding callbacks.

let commandTable;
let wsIsConnected = 0;
let ws;

// Callbacks should be set up before "load".
// each service will have its own callback(s);
// Eg addCallback("todoflash", flasher);
function addCallback(trigger, callback) {
	commandTable[trigger] = function() { callback(); };
	}

function doCallback(trigger) {
	if (typeof commandTable[trigger] !== 'undefined' && commandTable[trigger] !== null)
		{
		commandTable[trigger]();
		}
	}


function wsInit() {
	let request = new XMLHttpRequest();
	let theRequest = 'http://' + mainIP + ':' + theMainPort + '/' + wsShortName +  '/?req=portNumber';
	request.open('get', theRequest, true);
	
	request.onload =
			function() {
				if (request.status >= 200 && request.status < 400)
					{
					// Success?
					let resp = request.responseText;
					wsInitWithPort(resp);
					}
				else
					{
					// We reached our target server, but it returned an error
					console.log('Error, server reached but it could not handle request for ' + wsShortName + 'port number!');
					}
			};
	
	request.onerror = function() {
		// There was a connection error of some sort
		console.log('Connection error while attempting to retrieve' + wsShortName + 'port number!');
	};
	
	request.send();
}

function wsInitWithPort(wsPort) {
	let wsURL = 'ws://' + theHost + ':' + wsPort;
	ws = new WebSocket(wsURL);
	
	ws.addEventListener('open', function (event) {
    wsIsConnected = 1;
	});

	ws.addEventListener('message', function (event) {
		console.log('Message from server ', event.data);
		handleWsMessage(event.data);
});
}

function wsSendMessage(message) {
	if (wsIsConnected)
		{
		ws.send(message);
		}
	else
		{
		console.log("ERROR, WebSockets client is not connected!");
		}
}

function handleWsMessage(message) {
	doCallback(message);
}

window.addEventListener("load", wsInit);
