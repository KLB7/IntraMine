/* autoLinks.js: on-demand file links for non-CodeMirror files.
** 
*/

// Track line numbers seen, to avoid doing them twice.
let lineSeen = {};

// Called by addToggleScrollListener() below, and viewerStart.js#reJumpAndHighlight() on "load".
function addAutoLinks() {
	let el = document.getElementById(cmTextHolderName);
	if (el === null)
		{
		cmTextHolderName = specialTextHolderName;
		el = document.getElementById(cmTextHolderName);
		if (el === null)
			{
			console.log("Error, no text holder found in addAutoLinks!");
			}
		}
	let firstVisibleLineNum = firstVisibleLineNumber(el);
	let lastVisibleLineNum = lastVisibleLineNumber(el);
	// Go past the window bottom, sometimes linkage removes so much text
	// that fresh lines come into view.
	lastVisibleLineNum = Math.floor(lastVisibleLineNum * 1.5);

	let rowIds = []; // track <tr id='rowId' fo reach line, in sequence.
	getVisibleRowIds(firstVisibleLineNum, lastVisibleLineNum, rowIds);
	
	if (!allLinesHaveBeenSeen(rowIds))
		{
		let visibleText = getVisibleText(firstVisibleLineNum, lastVisibleLineNum);
		// Mark up local file, image, and web links in visible text.
		requestLinkMarkup(visibleText, firstVisibleLineNum, lastVisibleLineNum, rowIds);
		}
}

// Get a Linker port from Main, then call the real "requestLinkMarkup" fn.
function requestLinkMarkup(visibleText, firstVisibleLineNum, lastVisibleLineNum, rowIds) {
	let request = new XMLHttpRequest();
	let theRequest = 'http://' + mainIP + ':' + theMainPort + '/' + linkerShortName +  '/?req=portNumber';
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
						requestLinkMarkupWithPort(visibleText, firstVisibleLineNum, lastVisibleLineNum, rowIds, resp);
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

//Add link markup to view for newly exposed lines. Remember the lines have been marked up.
function requestLinkMarkupWithPort(visibleText, firstVisibleLineNum, lastVisibleLineNum, rowIds, linkerPort) {
	let request = new XMLHttpRequest();
	let remoteValue = (weAreRemote)? '1': '0';
	let allowEditValue = (allowEditing)? '1': '0';
	let useAppValue = (useAppForEditing)? '1': '0';
	
	request.open('get', 'http://' + mainIP + ':' + linkerPort + '/?req=nonCmLinks'
			+ '&remote=' + remoteValue + '&allowEdit=' + allowEditValue + '&useApp=' + useAppValue
			+ '&text=' + encodeURIComponent(visibleText) + '&peeraddress=' + encodeURIComponent(peeraddress)
			+ '&path=' + encodeURIComponent(thePath) + '&first=' + firstVisibleLineNum + '&last='
			+ lastVisibleLineNum);

	request.onload =
			function() {
				if (request.status >= 200 && request.status < 400)
					{
					let resp = request.responseText;
					if (resp != 'nope')
						{
						let lines = resp.split("\n");
//						console.log("Expected num lines: " + rowIds.length);
//						console.log("Response num lines: " + lines.length);
						let len = rowIds.length;
						if (len > lines.length)
							{
							len = lines.length;
							}
					
						for (let ind = 0; ind < len; ++ind)
							{
							let rowId = rowIds[ind];
							if (!lineHasBeenSeen(rowId))
								{
								let rowElem = document.getElementById(rowId);
								if (rowElem !== null)
									{
									rowElem.innerHTML = lines[ind];
									}
								}
							}
						}
					else
						{
						}

					// Avoid visiting the same lines twice, we're dealing with a read-only file view.
					rememberLinesSeen(rowIds);
					}
				else
					{
					// We reached server but it returned an error. Bummer, no links.
					// console.log('Error, requestLinkMarkupWithPort request status: ' + request.status + '!');
					}
			};

	request.onerror = function() {
		// There was a connection error of some sort. Double bummer, no links.
		console.log('requestLinkMarkupWithPort connection error!');
	};

	request.send();
}

let isScrollingAuto = null;
function addToggleScrollListener() {
	let el = document.getElementById(cmTextHolderName);
	if (el !== null)
		{
		el.addEventListener("scroll", function() {
			// Clear our timeout throughout the scroll
			window.clearTimeout( isScrollingAuto );
	
			// Set a timeout to run after scrolling ends
			isScrollingAuto = setTimeout(function() {
				// Run the callback
			addAutoLinks();
			}, 66);
			});
		}
}

// Get the RNNN from id='RNNN' in all visible rows (where NNN is an integer).
function getVisibleRowIds(firstVisibleLineNum, lastVisibleLineNum, rowIds) {
	for (let row = firstVisibleLineNum; row <= lastVisibleLineNum; ++row)
		{
		let rowID = 'R' + row.toString();
		let rowElem = document.getElementById(rowID);
		if (rowElem !== null)
			{
			rowIds.push(rowID);
			}
		}
}

// Collect text of all visible lines, based on id='RNNN' for table rows, where NNN is an integer.
// Note not all rows have an id, in particular shrunken rows will be skipped.
function getVisibleText(firstVisibleLineNum, lastVisibleLineNum) {
	let result = '';
	for (let row = firstVisibleLineNum; row <= lastVisibleLineNum; ++row)
		{
		let rowID = 'R' + row.toString();
		let rowElem = document.getElementById(rowID);
		if (rowElem !== null)
			{
			let rowContents = rowElem.innerHTML;
			if (result === '')
				{
				result = rowContents;
				}
			else
				{
				result = result + "\n" + rowContents;
				}
			}
		}
	
	return(result);
}


//Links are inserted only when lines become visible, and we want to avoid doing
//the same line twice, so we track all row id's when inserting links.
function rememberLinesSeen(rowIds) {
for (let ind = 0; ind < rowIds.length; ++ind)
		{
		lineSeen[rowIds[ind]] = 1;
		}
}

function lineHasBeenSeen(rowId) {
	if (rowId in lineSeen)
		{
		return (true);
		}

	return(false);
}

function allLinesHaveBeenSeen(rowIds) {
	for (let ind = 0; ind < rowIds.length; ++ind)
		{
		if (!(rowIds[ind] in lineSeen))
			{
			return (false);
			}
		}

	return (true);
}

window.addEventListener("load", addToggleScrollListener);

