// todoFlash.js: use SSE to flash the Nav bar when ToDo page changes.

function getRandomInt(min, max) {
	return Math.floor(Math.random() * (max - min + 1) + min);
	}

// flashStatusId, a more or less unique identifier for this client.
let flashStatusId = String(getRandomInt(1, 65000));
flashStatusId += String(getRandomInt(1, 65000));

let flashSource;
let flashSourceURL;

//Ask Main for the port number for the SSEONE server, and set up Server-Side Events listening.
//(Called at the bottom here). Error reporting is crude.
function getSSEPortAndRequestEventsFlash() {
	let request = new XMLHttpRequest();
	let theRequest = 'http://' + theHost + ':' + theMainPort +
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
						console.log('Error, server said ' + resp + '!');
						}
					else
						{
						requestSSEFlash(resp);
						}
					}
				else
					{
					// We reached our target server, but it returned an error
					console.log('Error, server reached but it could not handle request for port number!');
					}
			};
	
	request.onerror = function() {
		// There was a connection error of some sort
		console.log('Connection error while attempting to retrieve port number!');
	};
	
	request.send();
}

function requestSSEFlash(ssePort) {
	flashSourceURL = "http://" + theHost + ":" + ssePort +
					"/" + sseServerShortName + "/IMCHAT/?statusid=" + flashStatusId;
    flashSource = new EventSource(flashSourceURL);
	
	//console.log("Requesting evtsrc with |" + flashSourceURL + "|");
	
	// Trigger a flash of the ToDo item in the Nav bar when a "todoflash"
	// message is received.
	flashSource.addEventListener("todoflash", function(event) {
		flashNavBar();
		if (event.id == "CLOSE") {
			flashSource.close(); 
		}
		
	}, false);
	
	flashSource.onerror = function() {
		console.log("SSE error received");
	}
}

function flashNavBar() {
    let aTags = document.getElementsByTagName("a");
    let searchText = "ToDo";
    let todoElem;
    
    for (let i = 0; i < aTags.length; i++)
        {
        if (aTags[i].textContent == searchText)
            {
            todoElem = aTags[i];
            break;
            }
        }
        
    if (todoElem !== null)
        {
        flashIt(todoElem);
        }
}

function flashIt(todoElem) {
 
    toggleFlash(todoElem, true);
    setTimeout(function() {
        toggleFlash(todoElem, false);
        }, 2000);
}

function toggleFlash(todoElem, flashOn) {
    if (flashOn)
        {
        addClass(todoElem, 'flashOn');
        }
    else
        {
        removeClass(todoElem, 'flashOn');
        }
}

window.addEventListener("load", getSSEPortAndRequestEventsFlash);
