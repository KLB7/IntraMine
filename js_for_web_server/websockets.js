// websockets.js
// Open a WebSocket connection to IntraMine's WS service, register trigger strings
// and corresponding callbacks.
// Since the WS (WebSockets) service just echoes any message it received back to all
// clients everywhere, no client should respond to a message with another message
// - unless care is taken, that could cause an endless loop.
// Triggers are matched on the left, so if the trigger is "hello" then both
// messages "hello" and "hello there" will trigger a callback for that trigger.
// If you are concerned about accidentally triggering a callback in some other
// server, put the Short name of your server at the start of the trigger.
//

let commandTable = new Object();
let wsIsConnected = 0;
let ws;


// A custom event, to load callbacks from other JS files.
const wsInitEvent = new Event('wsinit');

// Callbacks should be set up before "load".
// each service will have its own callback(s);
// Eg addCallback("todoflash", flashNavBar);
function addCallback(trigger, callback) {
	commandTable[trigger] = callback;
//	commandTable[trigger] = function() { callback(); };
	}

function doCallback(message) {
	for (const trigger in commandTable)
		{
		if (message.indexOf(trigger) == 0)
			{
			commandTable[trigger](message);
			}
		}
}

// First request the WS (WebSockets) port number from Main, then connect to the WS service.
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
					console.log('Error, server reached but it could not handle request for ' + wsShortName + ' port number!');
					}
			};
	
	request.onerror = function() {
		// There was a connection error of some sort
		console.log('Connection error while attempting to retrieve ' + wsShortName + ' port number!');
	};
	
	request.send();
}

// Connect to the WS (WebSockets) service, and handle open and message received events.
function wsInitWithPort(wsPort) {
	let wsURL = 'ws://' + theHost + ':' + wsPort;
	ws = new WebSocket(wsURL);
	
	ws.addEventListener('open', function (event) {
    wsIsConnected = 1;
	});

	ws.addEventListener('message', function (event) {
		//console.log('Message from server ', event.data);
		handleWsMessage(event.data);
	});
	
	setTimeout(fireInitEvent, 100);
}

function fireInitEvent() {
	window.dispatchEvent(wsInitEvent);
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

// Run any callback associated with the message.
function handleWsMessage(message) {
	doCallback(message);
}

window.addEventListener("load", wsInit);
