// polledShouldReload.js
// Ask Watcher service if file on disk has changed, once a second.
// Expect response of "timeInMilliseconds" or "timeInMilliseconds space linenumber" with anything else meaning "no".

// 'Watcher' should be in a config file, sorry.
let WatcherShortName = 'Watcher';
let watcherPort = 0;
let fileChangedTimeRE = new RegExp("^(\\d+)$");
let fileChangedTimeLineRE = new RegExp("^(\\d+) (\\d+)$");

async function pollForReload() {
	if (watcherPort === 0)
		{
		return;
		}
	
	try {
		let theAction = 'http://' + theHost + ':' + watcherPort + '/?req=hasFileChanged&file=' + path;
		const response = await fetch(theAction);
		if (response.ok)
			{
			let text = await response.text();
			let currentResult = {};
			if ((currentResult = fileChangedTimeLineRE.exec(text)) !== null)
				{
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
						location.hash = lineNumberStr;
						}
					}
				else
					{
					location.hash = lineNumberStr;
					}
				window.location.reload();
				}
			else if ((currentResult = fileChangedTimeRE.exec(text)) !== null)
				{
				// No line number: reload unless we just did so.
				let changedTimeStr = currentResult[1];
				let changedTime = parseInt(changedTimeStr, 10);
				let loadTime = parseInt(previousChangeTimeMsecs, 10);
				let deltaTime = changedTime - loadTime;
				if (deltaTime > 6000) // 6 seconds
					{
					window.location.reload();
					}
				else
					{
					previousChangeTimeMsecs = changedTimeStr;
					}
				}
			// else file is unchanged
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
		await sleepABit(100); // msec
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
}

window.addEventListener("load", getWatcherPort);

// Ask Watcher service if file on disk has changed, once a second.
let reloadPollingID = setInterval(pollForReload, 1000);