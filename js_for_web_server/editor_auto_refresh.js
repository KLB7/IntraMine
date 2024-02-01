// editor_auto_refresh.js: reload an Editor view if notification comes in
// that the file has changed.

// If a file watcher change notice is received within these many seconds
// of a notice from IntraMine's Editor, we ignore it.
let doubleNoticeSeconds = 3;
let selfTriggerSeconds = 1;
let lastEditorUpdateTime = Date.now(); // Last update from IntraMine's Editor

// Register callback for the auto refresh, "changeDetected".
function registerAutorefreshCallback() {
	addCallback("changeDetected", handleFileChanged);
}

// Remember time of last Save. See editor.js#notifyFileChangedAndRememberCursorLine().
function RememberLastEditorUpdateTime() {
	lastEditorUpdateTime = Date.now();
}

function handleFileChanged(message) {
	// changeDetected space lineNumber space filePath five spaces timestamp
	let regex = new RegExp("^(\\w+) (\\d+) (.+?)     (.+)$");
	let currentResult = {};
	if ((currentResult = regex.exec(message)) !== null)
		{
		let lineNumberStr = currentResult[2];
		let pathFromMessage = currentResult[3];
		let timeStamp = currentResult[4];
		pathFromMessage = decodeURIComponent(pathFromMessage);
		pathFromMessage = pathFromMessage.replace(/%25/g, "%");
		
		if (pathFromMessage === theEncodedPath)
			{
			let currentTime = Date.now();
			// lineNumberStr > 0 means the Viewer should jump to that line
			// number, 0 means don't jump (since line number is unknown).
			if (lineNumberStr > 0) // "0" means line number unknown
				{
				// Avoid self triggering.
				let secondsSinceEditorUpdate = (currentTime - lastEditorUpdateTime) / 1000;
				if (secondsSinceEditorUpdate >= selfTriggerSeconds)
					{
					location.hash = lineNumberStr;
					window.location.reload();
					}
				}
			else
				{
				let timestampKey = theEncodedPath + '?' + 'timestamp';
				let previousTimestamp = "0";

				if (!localStorage.getItem(timestampKey))
					{
					; // first message from Watcher
					}
				else
					{
					previousTimestamp = localStorage.getItem(timestampKey);
					}
				localStorage.setItem(timestampKey, timeStamp);

				// Update only if not immediately following a change
				// notice from IntraMine's Editor (for those, the line
				// number is positive.)
				let secondsSinceEditorUpdate = (currentTime - lastEditorUpdateTime) / 1000;
				if (secondsSinceEditorUpdate >= doubleNoticeSeconds)
					{
					if (previousTimestamp !== timeStamp)
						{
						window.location.reload();
						}
					}
				// else too soon, ignore message from Watcher
				}
			}
		}
}

function xhandleFileChanged(message) {
	// trigger space lineNumber space filePath five spaces timestamp
	let regex = new RegExp("^(\\w+) (\\d+) (.+?)     (.+)$");
	let currentResult = {};
	if ((currentResult = regex.exec(message)) !== null)
		{
		let lineNumberStr = currentResult[2];
		let pathFromMessage = currentResult[3];
		let timeStamp = currentResult[4];
		pathFromMessage = decodeURIComponent(pathFromMessage);
		pathFromMessage = pathFromMessage.replace(/%25/g, "%");
		
		if (pathFromMessage === theEncodedPath)
			{
			let currentTime = Date.now();
			// lineNumberStr > 0 means the Viewer should jump to that line
			// number, 0 means don't jump (since line number is unknown).
			if (lineNumberStr > 0) // "0" means line number unknown
				{
				// Avoid self triggering.
				let secondsSinceEditorUpdate = (currentTime - lastEditorUpdateTime) / 1000;
				if (secondsSinceEditorUpdate >= selfTriggerSeconds)
					{
					location.hash = lineNumberStr;
					window.location.reload();
					}
				}
			else
				{
				// Update only if not immediately following a change
				// notice from IntraMine's Editor (for those, the line
				// number is positive.)
				let secondsSinceEditorUpdate = (currentTime - lastEditorUpdateTime) / 1000;
				if (secondsSinceEditorUpdate >= doubleNoticeSeconds)
					{
					// Sometimes the Watcher sends a duplicate change message:
					// check the last known timestamp, skip reload if the
					// time hasn't changed. Remember timestamp for the next er time.
					let shouldRefresh = true;
					let timestampKey = theEncodedPath + '?' + 'timestamp';

					if (!localStorage.getItem(timestampKey))
						{
						localStorage.setItem(timestampKey, timeStamp);
						}
					else
						{
						let previousTimestamp = localStorage.getItem(timestampKey);
						if (previousTimestamp === timeStamp)
							{
							shouldRefresh = false;
							}
						else
							{
							localStorage.setItem(timestampKey, timeStamp);
							}
						}
				
					if (shouldRefresh)
						{
						window.location.reload();
						}
					}
				}
			}
		}
}


window.addEventListener('wsinit', function (e) { registerAutorefreshCallback(); }, false);
