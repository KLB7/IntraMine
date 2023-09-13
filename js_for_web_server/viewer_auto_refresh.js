// viewer_auto_refresh.js: for IntraMine's Viewer, refresh display
// when a WebSockets "fileChanged" message is received for a specific file.
// Attempt to to to line number where the change happened.

// Register callback for the auto refresh, "changeDetected".
function registerAutorefreshCallback() {
	addCallback("changeDetected", handleFileChanged);
}

function handleFileChanged(message) {
	// trigger space lineNumber space filePath
	let regex = new RegExp("^(\\w+)\\s+(\\d+)\\s+(.+?)$");
	let currentResult = {};
	if ((currentResult = regex.exec(message)) !== null)
		{
		let lineNumberStr = currentResult[2];
		let pathFromMessage = currentResult[3];
		pathFromMessage = decodeURIComponent(pathFromMessage);
		pathFromMessage = pathFromMessage.replace("%25", /%/g);
		
		if (pathFromMessage === theEncodedPath)
			{
			if (lineNumberStr > 0) // "0" means line number unknown
				{
				location.hash = lineNumberStr;
				}
			window.location.reload();
			}
		}
}


window.addEventListener('wsinit', function (e) { registerAutorefreshCallback(); }, false);
