// go2def.js: on selection of a word or short phrase W, ask IntraMine's Linker
// for a list of links to files containining important
// instances of W.
// This is part of "Go2", see Documentation/Go2.html.

// Track mouse, we show the definition links if the mouse doesn't move much.
let defStartingX = 0;
let defStartingY = 0;
let maximumDeltaX = 20;
let maximumDeltaY = 20;
let mouseHasMovedALot = false;
let definitionMouseMoveTimeout = 250; // milliseconds

// If mouse doesn't move much call back to the Linker with req=defs
// and then call showhint() to pop up a list of links that have
// definitions or mentions of the term (can be a word or short phrase).
// Called by cmAutoLinks.js#handleFileLinkMouseUp() and viewerStart.js#updateMarkers()
// to cover off CodeMirror and nonCM displays.
async function showDefinitionHint(term, event) {
	if (term === '' || term.length < 3)
	// was if (term === '' || !/\w/.test(term))
		{
		return;
		}

	// Note initial mouse position. We haven't moved much yet.
	defStartingX = event.pageX;
	defStartingY = event.pageY;
	mouseHasMovedALot = false;
	
	// Install a temporary mousemove tracker.
	window.addEventListener('mousemove', monitorMouseMoves);

	// After a brief delay, if mouse has not moved much
	// show the definition links.
	setTimeout(function() {
        ShowDefIfHovering(term, event);
		}, definitionMouseMoveTimeout);

}

function monitorMouseMoves(event) {
	if (mouseHasMovedALot)
		{
		return;
		}
	
	let currentX = event.pageX;
	let currentY = event.pageY;
	let currentDeltaX = currentX - defStartingX;
	if (currentDeltaX < 0)
		{
		currentDeltaX = -currentDeltaX;
		}
	let currentDeltaY = currentY - defStartingY;
	if (currentDeltaY < 0)
		{
		currentDeltaY = -currentDeltaY;
		}
	if (currentDeltaX > maximumDeltaX || currentDeltaY > maximumDeltaY)
		{
		mouseHasMovedALot = true;
		}
}

async function ShowDefIfHovering(term, event) {
	// Remove temporary mousemove tracker.
	window.removeEventListener('mousemove', monitorMouseMoves);

	if (mouseHasMovedALot)
		{
		return;
		}

	try {
		const port = await fetchPort(mainIP, theMainPort, linkerShortName, '');
		if (port !== "")
			{
			showDefinitionHintWithPort(term, event, port);
			}
	}
	catch(error) {
		return;
	}
}

// Call back to intramine_linker.pl#Go2(), which will ask Elasticsearch
// for mentions of the term (word or short phrase),
// winnowed by universal ctags in some cases to find real definitions.
// Show any result with tooltip.js#showhint().
async function showDefinitionHintWithPort(term, event, linkerPort) {
	try {
		let theAction = 'http://' + mainIP + ':' + linkerPort + '/?req=defs&findthis=' + encodeURIComponent(term) + '&path=' + encodeURIComponent(thePath);
		const response = await fetch(theAction);
		if (response.ok)
			{
			let text = await response.text();
			if (text !== '')
				{

				if (text !== '<p>nope</p>')
					{
					text = text.replace(/%2B/g, "+");
					//text = text.replace(/__IMSPC__/g, " ");
					let hintContent = text;

					// Show the definition links via tooltip.js#showhint().
					showhint(hintContent, event.target, event, '500px', false); 
					}
				}
			else
				{
				// TEST ONLY
				//console.log("text is empty.");
				}
			}
		else
			{
			// We reached our target server, but it returned an error
			// TEST ONLY
			////console.log("We reached our target server, but it returned an error");
			return;
			}
	}
	catch(error) {
		// TEST ONLY
		//console.log("Try failed.");

		return;
	}
}

// A shameless copy from intramine_search.js.
function viewerOpenAnchor(href) {
	// Browser keeps tacking on file:///, which wrecks the link.	
	let properHref = href.replace(/^file\:\/\/\//, '');
	properHref = properHref.replace(/^file:/, '');

// Argument-based 'href=path' approach:
	let url = 'http://' + theHost + ':' + theMainPort + '/' + viewerShortName + '/?href=' +
				properHref + '&rddm=' + String(getRandomInt(1, 65000));
	
	// A more RESTful 'Viewer/file/path/' approach
//	let url = 'http://' + theHost + ':' + theMainPort + '/' + viewerShortName + '/file/' +
//				properHref + '&rddm=' + String(getRandomInt(1, 65000));

	// TEST ONLY
	//console.log("url: |" + url + "|");

	window.open(url, "_blank");
	}
