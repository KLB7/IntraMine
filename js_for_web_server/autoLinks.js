/* autoLinks.js: on-demand file links for non-CodeMirror files (.txt, .pl, .pm, .pod etc).
** 
*/

// Track line numbers seen, to avoid doing them twice.
let lineSeen = {};
let isMarkdown = false;

// "sleep" for ms milliseconds.
function sleepABit(ms) {
	return new Promise(resolve => setTimeout(resolve, ms));
}

// Called by addScrollListenerAndSetMarkdown() below, and viewerStart.js#reJumpAndHighlight() on "load".
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
	
	let firstVisibleLineNum = firstVisibleLineNumber(el); // showHideTOC.js
	let lastVisibleLineNum = lastVisibleLineNumber(el);
	// Go past the window bottom, sometimes this makes scrolling smoother.
	lastVisibleLineNum = Math.floor(firstVisibleLineNum + (lastVisibleLineNum - firstVisibleLineNum) * 1.5);
	
	// I've left this line below as an exemplar of how dumb I can be.
	//lastVisibleLineNum = Math.floor(lastVisibleLineNum * 2.1);

	let rowIds = []; // track <tr id='rowId' fo reach line, in sequence.
	getVisibleRowIds(firstVisibleLineNum, lastVisibleLineNum, rowIds);
	
	if (!allLinesHaveBeenSeen(rowIds))
		{
		let visibleText = getVisibleText(firstVisibleLineNum, lastVisibleLineNum);
		// Mark up local file, image, and web links in visible text.
		if (visibleText !== '')
			{
			requestLinkMarkup(visibleText, firstVisibleLineNum, lastVisibleLineNum, rowIds);
			}
		}
}

// Get a Linker port from Main, then call the real "requestLinkMarkup" fn.
async function requestLinkMarkup(visibleText, firstVisibleLineNum, lastVisibleLineNum, rowIds) {
	let tryCounter = 0;
	let maxTries = 2;
	let retry = true;

	while (retry)
		{
		try
			{
			retry = false;
			const port = await fetchPort(mainIP, theMainPort, linkerShortName, errorID);
			if (port !== "")
				{
				requestLinkMarkupWithPort(visibleText, firstVisibleLineNum, lastVisibleLineNum, rowIds, port);
				}
			}
		catch(error)
			{
			++tryCounter;
			if (tryCounter > maxTries)
				{
				retry = false;
				// There was a connection error of some sort
				let e1 = document.getElementById(errorID);
				e1.innerHTML = 'Connection error while attempting to retrieve port number!';
				}
			else
				{
				retry = true;
				// Try again, after a brief pause.
				await sleepABit(1000);
				}
			}
		}
}

//Add link markup to view for newly exposed lines. Remember the lines have been marked up.
async function requestLinkMarkupWithPort(visibleText, firstVisibleLineNum, lastVisibleLineNum, rowIds, linkerPort) {
	let remoteValue = (weAreRemote)? '1': '0';
	let allowEditValue = (allowEditing)? '1': '0';
	let useAppValue = (useAppForEditing)? '1': '0';
	let shouldInline = (shouldInlineImages()) ? '1' : '0';

	try {
		let theAction = 'http://' + mainIP + ':' + linkerPort + '/?req=nonCmLinks'
		+ '&remote=' + remoteValue + '&allowEdit=' + allowEditValue + '&useApp=' + useAppValue
		+ '&text=' + encodeURIComponent(visibleText) + '&peeraddress=' + encodeURIComponent(peeraddress)
		+ '&path=' + encodeURIComponent(thePath) + '&first=' + firstVisibleLineNum + '&last='
		+ lastVisibleLineNum + '&shouldInline=' + shouldInline;
		const response = await fetch(theAction);

		if (response.ok)
			{
			let text = await response.text();
			if (text != 'nope')
				{
				let lines = text.split("\n");
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
							let repStr = lines[ind];
							let regex = /\%2B/gi;
							repStr = repStr.replace(regex, '+');
							let regex2 = /:81\//g;
							repStr = repStr.replace(regex2, ":" + ourSSListeningPort + "/");
							rowElem.innerHTML = repStr;
							}
						}
					}
				}
			// else 'nope', no links
			// Avoid visiting the same lines twice, we're dealing with a read-only file view.
			rememberLinesSeen(rowIds);
			}
		else
			{
			// We reached server but it returned an error. Bummer, no links.
			}
	}
	catch(error) {
	// There was a connection error of some sort. Double bummer, no links.
	console.log('requestLinkMarkupWithPort connection error!');
	}
}

function addAutoLinksForMarkdown() {
	let el = document.getElementById(cmTextHolderName);
	if (el === null)
		{
		cmTextHolderName = specialTextHolderName;
		el = document.getElementById(cmTextHolderName);
		if (el === null)
			{
			console.log("Error, no text holder found in addAutoLinks!");
			return;
			}
		}

	let visibleText = el.innerHTML; // Grab whole file
	requestLinkMarkupForMarkdown(visibleText, el);
}

// Get a Linker port from Main, then call the real "requestLinkMarkup" fn.
async function requestLinkMarkupForMarkdown(visibleText, el) {
	let tryCounter = 0;
	let maxTries = 2;
	let retry = true;

	while (retry)
		{
		try
			{
			retry = false;
			const port = await fetchPort(mainIP, theMainPort, linkerShortName, errorID);
			if (port !== "")
				{
				requestLinkMarkupWithPortForMarkdown(visibleText, port, el);
				}
			}
		catch(error)
			{
			++tryCounter;
			if (tryCounter > maxTries)
				{
				retry = false;
				// There was a connection error of some sort
				let e1 = document.getElementById(errorID);
				e1.innerHTML = 'Connection error while attempting to retrieve port number!';
				}
			else
				{
				retry = true;
				// Try again, after a brief pause.
				await sleepABit(1000);
				}
			}
		}
}

// Add link markup to view all lines. Remember the lines have been marked up.
async function requestLinkMarkupWithPortForMarkdown(visibleText, linkerPort, el) {
	let remoteValue = (weAreRemote)? '1': '0';
	let allowEditValue = (allowEditing)? '1': '0';
	let useAppValue = (useAppForEditing)? '1': '0';
	let shouldInline = '1'; //(shouldInlineImages()) ? '1' : '0';

	try {
		let theAction = 'http://' + mainIP + ':' + linkerPort + '/?req=nonCmLinks'
		+ '&remote=' + remoteValue + '&allowEdit=' + allowEditValue + '&useApp=' + useAppValue
		+ '&text=' + encodeURIComponent(visibleText) + '&peeraddress=' + encodeURIComponent(peeraddress)
		+ '&path=' + encodeURIComponent(thePath) + '&first=' + '0' + '&last='
		+ '0' + '&shouldInline=' + shouldInline;
		const response = await fetch(theAction);

		if (response.ok)
			{
			let text = await response.text();
			if (text != 'nope')
				{
				let lines = text.split("\n");
				let len = lines.length;
			
				for (let ind = 0; ind < len; ++ind)
					{
					let regex = /\%2B/gi;
					lines[ind] = lines[ind].replace(regex, '+');
					let regex2 = /:81\//g;
					lines[ind] = lines[ind].replace(regex2, ":" + ourSSListeningPort + "/");
					}

				text = lines.join("\n");
				el.innerHTML = text;
				}
			}
		else
			{
			// We reached server but it returned an error. Bummer, no links.
			}
	}
	catch(error) {
	// There was a connection error of some sort. Double bummer, no links.
	console.log('requestLinkMarkupWithPort connection error!');
	}
}

function decodeURIComponentSafe(s) {
    if (!s) {
        return s;
    }
    return decodeURIComponent(s.replace(/%(?![0-9a-fA-F]+)/g, '%25'));
}

let isScrollingAuto = null;
function addScrollListenerAndSetMarkdown() {
	// Skip .md files.
	setIsMarkdown();
	if (isMarkdown)
		{
		return;
		}
	
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

function setIsMarkdown() {
	isMarkdown = false;
	let fileName = theEncodedPath.split(/[\\/]/).pop();
	let extPos = fileName.lastIndexOf(".");
	if (extPos > 1)
		{
		let ext = fileName.slice(extPos + 1);
		if (ext === "md" || ext === "MD" || ext === "mkd" || ext === "MKD" || ext === "markdown" || ext === "MARKDOWN")
			{
			// .md files don't have line numbers and need special handling
			// when inserting links and glossary popups - see addAutoLinks().
			isMarkdown = true;
			}
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

window.addEventListener("load", addScrollListenerAndSetMarkdown);

