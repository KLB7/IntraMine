// reload.js
// Ask Watcher service if file on disk has changed, once a second.
// Expect response of "timeInMilliseconds" or "timeInMilliseconds space linenumber" with anything else meaning "no".

// 'Watcher' should be in a config file, sorry.
let WatcherShortName = 'Watcher';
let watcherPort = 0;
let fileChangedTimeRE = new RegExp("^(\\d+)$");
let fileChangedTimeLineRE = new RegExp("^(\\d+)S(\\d+)$");
let lastModTime = "0";
if (typeof fileModTime !== "undefined") // defined for Viewer and Editor
	{
	lastModTime = "" + fileModTime;
	}

// Moved to intramine_viewer.pl#617 or so.
//let uniqueBrowserID = ""; // "" means unassigned

function setLastSaveTime(theTime) {
	lastModTime = theTime; // epoch seconds for last save
}

async function GetUniqueBrowserID() {
	let theAction = 'http://' + theHost + ':' + ourSSListeningPort + '/?req=uniqueid';
	try {
		const response = await fetch(theAction);
		if (response.ok)
			{
			let text = await response.text();
			uniqueBrowserID = text;
			}
		else
			{
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(errorID);
			e1.innerHTML = '<p>Error, GetUniqueBrowserID request failed!</p>';
			}
	}
	catch(error) {
		// There was a connection error of some sort
		let e1 = document.getElementById(errorID);
		e1.innerHTML = '<p>GetUniqueBrowserID request connection error!</p>';
	}
}

async function pollForReload() {
	const port = await fetchPort(theHost, theMainPort, WatcherShortName, errorID);

	try {
		let theAction = 'http://' + theHost + ':' + port + '/?req=hasFileChanged&path=' + encodeURIComponent(thePath) + '&id=' + uniqueBrowserID + '&caller=' + shortServerName;
		const response = await fetch(theAction);
		if (response.ok)
			{
			let text = await response.text();
			let currentResult = {};
			if ((currentResult = fileChangedTimeLineRE.exec(text)) !== null)
				{
				let currentModTime = currentResult[1];
				let lineNumberStr = currentResult[2];
				if (lastModTime !== currentModTime)
					{
					if (lastModTime === "0")
						{
						lastModTime = currentModTime;
						}
					else
						{
						let oldLastModTime = lastModTime;
						lastModTime = currentModTime;
						
						if (typeof isMarkdown !== "undefined")
							{
							if (isMarkdown)
								{
								// Put line number in local storage so it
								// survives as reload. See 
								// viewerStart.js#jumpToMarkdownLineFromStorage().
								let markdownLineNumberKey = thePath + '?' + "markdownline";
								localStorage.setItem(markdownLineNumberKey, lineNumberStr);
								location.hash = ''; // otherwise hash takes precedence
								}
							else
								{
								sessionStorage.setItem('lineNumberStr', lineNumberStr);
								}
							}
						else
							{
							sessionStorage.setItem('lineNumberStr', lineNumberStr);
							}
						
						// After a file rename, win_wide_filepaths.pm#GetFileModTimeWide
						// and the WATCHER can disagree on the mod time, so we shrug
						// off small differences.
						if (currentModTime - oldLastModTime > 1)
							{
							reloadJustTheContents(thePath, shortServerName, true);
							}
						}
					}
				}
			else if ((currentResult = fileChangedTimeRE.exec(text)) !== null)
				{
				let currentModTime = currentResult[1];
				if (lastModTime !== currentModTime)
					{
					if (lastModTime === "0")
						{
						lastModTime = currentModTime;
						}
					else
						{
						let oldLastModTime = lastModTime;
						lastModTime = currentModTime;

						// After a file rename, win_wide_filepaths.pm#GetFileModTimeWide
						// and the WATCHER can disagree on the mod time, so we shrug
						// off small differences.
						if (currentModTime - oldLastModTime > 1)
							{
							reloadJustTheContents(thePath, shortServerName, false);
							}
						}
					}
				}

			// Clear any error message. Except "NOTE" which is
			// reporting unsaved changes.
			let e1 = document.getElementById(errorID);
			let currentErrorMessage = e1.innerHTML;
			if (currentErrorMessage.indexOf("NOTE") < 0)
				{
				e1.innerHTML = ' ';
				}
			}
		else
			{
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(errorID);
			e1.innerHTML = '<p>Error, File changed request failed!</p>';
			}

	}
	catch(error) {
		// There was a connection error of some sort
		let e1 = document.getElementById(errorID);
		e1.innerHTML = '<p>File changed request connection error!</p>';
	}
}

async function xpollForReload() {
	//const theWatcherPort = await getWatcherPort();
	const port = await fetchPort(theHost, theMainPort, WatcherShortName, errorID);
	//console.log("watcher port: |" + port + "|");

	try {
		let theAction = 'http://' + theHost + ':' + port + '/?req=hasFileChanged&path=' + encodeURIComponent(thePath) + '&id=' + uniqueBrowserID + '&caller=' + shortServerName;
		const response = await fetch(theAction);
		if (response.ok)
			{
			let text = await response.text();
			// if (text !== '')
			// 	{
			// 	console.log(text);
			// 	}
			let currentResult = {};
			if ((currentResult = fileChangedTimeLineRE.exec(text)) !== null)
				{
				//console.log("text has line number");
				// If there's a line number, the report is from the Editor,
				// always reload.
				let lineNumberStr = currentResult[2];
				if (typeof isMarkdown !== "undefined")
					{
					if (isMarkdown)
						{
						// Put line number in local storage so it
						// survives as reload. See 
						// viewerStart.js#jumpToMarkdownLineFromStorage().
						let markdownLineNumberKey = thePath + '?' + "markdownline";
						localStorage.setItem(markdownLineNumberKey, lineNumberStr);
						location.hash = ''; // otherwise hash takes precedence
						}
					else
						{
						;//location.hash = lineNumberStr;
						sessionStorage.setItem('lineNumberStr', lineNumberStr);
						}
					}
				else
					{
					;//location.hash = lineNumberStr;
					sessionStorage.setItem('lineNumberStr', lineNumberStr);
					}

				// Revision, set href with an 'id' param instead of reload.
				if (typeof uniqueBrowserID !== "undefined")
					{
					reloadJustTheContents(thePath, shortServerName, true);
					// Previously, a full reload, didn't work well.
					// const params = new URLSearchParams(window.location.search);
					// params.set('id', uniqueBrowserID);
					// window.location.href = `${window.location.pathname}?${params.toString()}`;
					}
				else
					{
					// Previously, a full reload, didn't work well.
					reloadJustTheContents(thePath, shortServerName, true);
					// window.location.reload();
					}
				}
			else if ((currentResult = fileChangedTimeRE.exec(text)) !== null)
				{
				//console.log("NO LINE NUMBER");
				// No line number: reload unless we just did so.
				let changedTimeStr = currentResult[1];
				let changedTime = parseInt(changedTimeStr, 10);
				let loadTime = parseInt(previousChangeTimeMsecs, 10);
				let deltaTime = changedTime - loadTime;
				if (previousChangeTimeMsecs > 0 && deltaTime > 6000) // 6 seconds
					{
					// Revision, set href with an 'id' param instead of reload.
					if (typeof uniqueBrowserID !== "undefined")
						{
						reloadJustTheContents(thePath, shortServerName, false);
						// Previously, a full reload, didn't work well.
						// const params = new URLSearchParams(window.location.search);
						// params.set('id', uniqueBrowserID);
						// window.location.href = `${window.location.pathname}?${params.toString()}`;
						}
					else
						{
						reloadJustTheContents(thePath, shortServerName, false);
						// Previously, a full reload, didn't work well.
						// window.location.reload();
						}
					}
				else
					{
					previousChangeTimeMsecs = changedTimeStr;
					}
				}
			// else file is unchanged
			// Clear any error message. Except "NOTE" which is
			// reporting unsaved changes.
			let e1 = document.getElementById(errorID);
			let currentErrorMessage = e1.innerHTML;
			if (currentErrorMessage.indexOf("NOTE") < 0)
				{
				e1.innerHTML = ' ';
				}
			}
		else
			{
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(errorID);
			e1.innerHTML = '<p>Error, File changed request failed!</p>';
			}
	}
	catch(error) {
		// There was a connection error of some sort
		let e1 = document.getElementById(errorID);
		e1.innerHTML = '<p>File changed request connection error!</p>';
	}
}

async function getWatcherPort() {
	let doRetry = true;
	let numTries = 5;
	let triesSoFar = 0;
	
	while (doRetry && ++triesSoFar <= numTries)
		{
		//await sleepABit(100); // msec
		try
			{
			const port = await fetchPort(theHost, theMainPort, WatcherShortName, errorID);
			if (port !== '')
				{
				watcherPort = port;
				if (triesSoFar > 1)
					{
					let e1 = document.getElementById(errorID);
					e1.innerHTML = '<p>&nbsp;</p>';
					}
				doRetry = false;
				}
			}
		catch(error)
			{
			// There was a connection error of some sort
			let e1 = document.getElementById(errorID);
			e1.innerHTML = '<p>Watcher port request connection error!</p>';
			}
		}

	return(watcherPort);
}

async function notifyWatcherThatFileHasChanged(lineNumber, modTimeStr) {
	try {
		const port = await fetchPort(mainIP, theMainPort, WatcherShortName, errorID);
		if (port !== "")
			{
			notifyWatcherThatFileHasChangedWithPort(lineNumber, modTimeStr, port);
			}
	}
	catch(error) {
		// There was a connection error of some sort
		let e1 = document.getElementById(errorID);
		e1.innerHTML = '<p>File change error, could not retrieve Watcher port!</p>';
	}
}

async function notifyWatcherThatFileHasChangedWithPort(lineNumber, modTimeStr, port) {
	let theAction = 'http://' + mainIP + ':' + port + '/?req=fileHasChanged' + '&path=' + encodeURIComponent(thePath) + '&lineNumber=' + lineNumber + '&id=' + uniqueBrowserID + '&mtime=' + modTimeStr;

	try {
		const response = await fetch(theAction);
		if (response.ok)
			{
			let resp = await response.text();
			// Update HTML, finish the "startup".

			}
		else
			{
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(errorID);
			e1.innerHTML = '<p>Error, notifyWatcherThatFileHasChangedWithPort request failed!</p>';
			}
	}
	catch(error) {
		// Connection error, could not reach server.
		let e1 = document.getElementById(errorID);
		e1.innerHTML = '<p>File change notification connection error!</p>';
	}
}

// If change notice supplied a line number then the notice was from
// IntraMine's Editor - request cached contents from the Editor instead
// of reloading from disk in the Viewer.
async function reloadJustTheContents(thePath, shortServerName, useEditorCache) {

	try {
		const port = await fetchPort(mainIP, theMainPort, shortServerName, errorID);
		if (port !== "")
			{
			reloadJustTheContentsWithPort(thePath, shortServerName, port, useEditorCache);
			}
	}
	catch(error) {
		// There was a connection error of some sort
		let e1 = document.getElementById(errorID);
		e1.innerHTML = '<p>reloadJustTheContents error, could not retrieve ' + shortServerName + 'port!</p>';
	}
}

// Update TOC and text contents.
// For a CodeMirror-based display, call loadFileIntoCodeMirror(
// Viewer: separate callbacks for CodeMirror (CM) and nonCM.
// For a non-CM display: req=reloadnoncmfile
async function reloadJustTheContentsWithPort(thePath, shortServerName, port, useEditorCache) {
	// TEST ONLY
	//console.log("reloadJustTheContentsWithPort");

	let usingCodeMirror = true;
	if (shortServerName === 'Viewer')
		{		
		reportActivity();

		usingCodeMirror = extensionIsForCM();
		if (!usingCodeMirror)
			{
			reloadNonCM(shortServerName, port, useEditorCache); // viewerStart.js#reloadNonCM()
			previousChangeTimeMsecs = 0; // meaning change just happened
			}
		else
			{
			reloadCM(shortServerName, port, uniqueBrowserID, useEditorCache); // cmViewerStart.js#reloadCM()
			previousChangeTimeMsecs = 0; // meaning change just happened
			}
		}
	else if (shortServerName === 'Editor')
		{
		// Full reload. It is possible that there's a cached version of
		// the newly saved file in another IntraMine Editor,
		// but very unlikely.
		const params = new URLSearchParams(window.location.search);
		params.set('id', uniqueBrowserID);
		window.location.href = `${window.location.pathname}?${params.toString()}`;
		}
}

// For the Viewer, true if CodeMirror is NOT used for display.
function extensionIsForCM() {
	let result = true;
	let extPos = theEncodedPath.lastIndexOf(".");
	if (extPos > 1)
		{
		let ext = theEncodedPath.slice(extPos + 1);
		ext = ext.toLowerCase();
		if (ext === "txt" || ext === "log" || ext === "bat" || ext === "md" || ext === "mkd" || ext === "markdown" || ext === "pod")
			{
			result = false;
			}
		}
	
	return(result);
}


// Ask Watcher service if file on disk has changed, once a second.
let reloadPollingID = 0;

startReloadCheck();

function stopReloadCheck() {
	clearInterval(reloadPollingID);
}

function startReloadCheck() {
	reloadPollingID = setInterval(pollForReload, 1000);
}