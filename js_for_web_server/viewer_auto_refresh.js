// viewer_auto_refresh.js: for IntraMine's Viewer, refresh display
// when a WebSockets "fileChanged" message is received for a specific file.
// Attempt to go to line number where the change happened.

// There are currently two separate file change notifications,
// one from IntraMine's Editor editor.js#notifyFileChangedAndRememberCursorLine()
// and one from intramine_filewatcher.pl#SendFileContentsChanged().
// The Editor notice will happen first, and sends a line number that
// the Viewer should go to. The file watcher notice is slightly delayed,
// and does not include a line number. So the file watcher notice is
// ignored if it occurs just after the Editor notice. File watcher
// can emit duplicate change notices, so its message includes a
// timestamp - duplicate timestamps are ignored.

// If a file watcher change notice is received within these many seconds
// of a notice from IntraMine's Editor, we ignore it.
let doubleNoticeSeconds = 3;
let doubleNoticeMilliseconds = 3000;
let lastEditorUpdateTime = Date.now(); // Last update from IntraMine's Editor

// Register callback for the auto refresh, "changeDetected".
function registerAutorefreshCallback() {
	addCallback("changeDetected", handleFileChanged);
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
		pathFromMessage = pathFromMessage.replace(/%25/g, "%");

		let lcTheEncodedPath = theEncodedPath.toLowerCase();
		let lcPathFromMessage = pathFromMessage.toLowerCase();
		
		if (lcPathFromMessage === lcTheEncodedPath)
			{
			// lineNumberStr > 0 means the Viewer should jump to that line
			// number, 0 means don't jump (since line number is unknown).
			if (lineNumberStr > 0) // "0" means line number unknown
				{
				// Message is from IntraMine's Editor, always reload.
				location.hash = lineNumberStr;
				window.location.reload();
				}
			else
				{
				let currentTime = Date.now();
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
						// Last check, reload only if Editor here and the timeStamp
						// from the Watcher WebSockets message
						// disagree by more than three thousand milliseconds.
						let timesAreClose = false;
						if (lastEditorUpdateTime >= 0 && timeStamp >= 0)
							{
							let diffMsecs = timeStamp - lastEditorUpdateTime;
							if (diffMsecs < 0)
								{
								diffMsecs = -diffMsecs;
								}
							if (diffMsecs <= doubleNoticeMilliseconds)
								{
								timesAreClose = true;
								}
							}
						if (!timesAreClose)
							{
							window.location.reload();
							}
						// TEST ONY
						// else
						// 	{
						// 	console.log("Reload skipped, times are close.");
						// 	}
						}
					}
				// else too soon, ignore message from Watcher
				}
			}
		}
}


window.addEventListener('wsinit', function (e) { registerAutorefreshCallback(); }, false);
