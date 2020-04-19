/** todoEvents.js: initiate and handle Server-Sent Events reporting ToDo data has changed.
 * 
 */

function getRandomInt(min, max) {
	return Math.floor(Math.random() * (max - min + 1) + min);
	}

// statusId, a more or less unique identifier for this client.
let statusId = String(getRandomInt(1, 65000));
statusId += String(getRandomInt(1, 65000));

//console.log("Client Status ID: |" + statusId + "|");

let source;
let sourceURL;

//Ask Main for the port number for the SSEONE server, and set up Server-Side Events listening.
//(Called at the bottom here).
function getSSEPortAndRequestEvents() {
	let request = new XMLHttpRequest();
	let theRequest = 'http://' + theHost + ':' + mainPort +
						'/' + sseServerShortName + '/?req=portNumber';
	request.open('get', theRequest, true);
	
	request.onload =
			function() {
				if (request.status >= 200 && request.status < 400)
					{
					// Success?
					let resp = request.responseText;
					if (isNaN(resp))
						{
						let e1 = document.getElementById(errorID);
						e1.innerHTML = 'Error, server said ' + resp + '!';
						}
					else
						{
						requestSSE(resp);
						}
					}
				else
					{
					// We reached our target server, but it returned an error
					let e1 = document.getElementById(errorID);
					e1.innerHTML =
							'Error, server reached but it could not handle request for port number!';
					}
			};
	
	request.onerror = function() {
		// There was a connection error of some sort
		let e1 = document.getElementById(errorID);
		e1.innerHTML = 'Connection error while attempting to retrieve port number!';
	};
	
	request.send();
}

function requestSSE(ssePort) {
	sourceURL = "http://" + theHost + ":" + ssePort +
					"/" + sseServerShortName + "/IMCHAT/?statusid=" + statusId;
	source = new EventSource(sourceURL);
	
	//console.log("Requesting evtsrc with |" + sourceURL + "|");
	
	// Trigger a reload of the Todo page when a "todochanged"
	// message is received.
	source.addEventListener("todochanged", function(event) {
		//console.log("TODO SSE received.");
		getToDoData();
		if (event.id == "CLOSE") {
			source.close(); 
		}
		
	}, false);
	
	source.onerror = function() {
		console.log("SSE error received");
	}
}

window.addEventListener("load", getSSEPortAndRequestEvents);
