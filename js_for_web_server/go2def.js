// go2def.js: on selection of a word W, ask Elasticsearch for
// files containing definitions such as "sub W" or "function W"
// - if found, put in a showhint() for display.

async function showDefinitionHint(term, event) {

	// TEST ONLY
	//console.log("showDefinitionHint");
	if (term === '')
		{
		return;
		}

	const re = /\w+/;
	if (!re.test(term))
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

async function showDefinitionHintWithPort(term, event, linkerPort) {
	// TEST ONLY
	//.log("showdefwithport linkerPort |" + linkerPort + "|");
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

// A shameless copy while I'm fooling around.
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
