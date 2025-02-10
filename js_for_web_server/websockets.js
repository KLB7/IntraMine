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
let initializing = true;
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

// Messages have the form "_MG_trigger stuff_MG_" and there
// can be several messages received at once, many not
// containing a trigger word that we're interested in here.
// (MG: Message Guard)
function doCallback(message) {
	for (const trigger in commandTable)
		{
		let regex = new RegExp('_MG_(' + trigger + '.*?)_MG_', "g");
		let currentResult = {};
		while ((currentResult = regex.exec(message)) !== null)
			{
			let relevantMessage = currentResult[1];
			commandTable[trigger](relevantMessage);
			}
		}
}

// First request the WS (WebSockets) port number from Main, then connect to the WS service.
async function wsInit() {
	let tryCount = 0;
	let doRetry = true;

	while (tryCount < 5)
		{
			try {
				let theAction = 'http://' + mainIP + ':' + theMainPort + '/' + wsShortName +  '/?req=portNumber';
				const response = await fetch(theAction);
				if (response.ok)
					{
					doRetry = false;
					let text = await response.text();
					wsInitWithPort(text);
					}
				else
					{
					// We reached our target server, but it returned an error
					console.log('Error, server reached but it could not handle request for ' + wsShortName + ' port number!');
					}
			}
			catch(error) {
				// There was a connection error of some sort
				console.log('CONNECTION ERROR while attempting to retrieve ' + wsShortName + ' port number!');
			}

		if (doRetry)
			{
			await sleepMS(1000);
			}
		else
			{
			break;
			}
		
		++tryCount;
		}
}

// Connect to the WS (WebSockets) service, and handle open and message received events.
function wsInitWithPort(wsPort) {
	let wsURL = 'ws://' + theHost + ':' + wsPort;
	ws = new WebSocket(wsURL);
	
	ws.addEventListener('open', function (event) {
    wsIsConnected = 1;
	});

	ws.addEventListener('close', function (event) {
		wsIsConnected = 0;
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

	if (initializing)
		{
		while (!wsIsConnected && ++i < 10)
			{
			await sleepMS(100);
			}
		}
		
	if (!wsIsConnected && !initializing)
		{
		wsInit();
		await sleepMS(500);
		}

	initializing = false;

	if (wsIsConnected)
		{
		//ws.send('_MG_' + message + '_MG_');
		if (wsIsConnected)
			{
			if (ws.readyState === WebSocket.OPEN)
				{
				ws.send('_MG_' + message + '_MG_');
				}
			else
				{
				console.log("ERROR, WebSockets not connected yet! Could not send |" + message + "|");
				}
			}
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
