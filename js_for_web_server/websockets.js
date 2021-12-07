// websockets.js
// Open a WebSocket connection to IntraMine's WS service, register trigger strings
// and corresponding callbacks.
// Since the WS (WebSockets) service just echoes any message it receives back to all
// clients everywhere, no client should respond to a message with another message
// - unless care is taken, that could cause an endless loop.
// Triggers are matched on the left, so if the trigger is "hello" then both
// messages "hello" and "hello there" will trigger a callback for that trigger.
// If you are concerned about accidentally triggering a callback in some other
// server, put the Short name of your server at the start of the trigger.
// websockets.js is self-initializing,
// <script src="websockets.js"></script>
// is all you need to start the WebSockets connection.
// For an example of registering a callback to respond to particular
// "triggers" at the start of messages, see todoFlash.js.
// To send a message: wsSendMessage("the message");
// The custom event 'wsinit' is emitted to signal that
// callbacks can be registered - see todoFlash.js at the bottom for an example.
// wsSendMessage() will "sleep" for up to a second until the WebSocket
// connection is established, in the case where a message is sent early
// in the startup of a web page.

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

// "sleep" for ms milliseconds.
function sleepMS(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// Send a WebSockets message, without confirmation.
// "sleep" a little if not connected yet.
async function wsSendMessage(message) {
	let i = 0;

	while (!wsIsConnected && ++i < 10)
		{
		await sleepMS(100);
		}
		
	if (wsIsConnected)
		{
		ws.send(message);
		}
	else
		{
		console.log("ERROR, WebSockets not connected! Could not send |" + message + "|");
		}
}

// Run any callback associated with the message.
function handleWsMessage(message) {
	doCallback(message);
}

window.addEventListener("load", wsInit);
