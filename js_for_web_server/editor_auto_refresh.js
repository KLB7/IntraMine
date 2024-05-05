// editor_auto_refresh.js: reload an Editor view if notification comes in
// that the file has changed.

// If a file watcher change notice is received within these many seconds
// of a notice from IntraMine's Editor, we ignore it.
let doubleNoticeSeconds = 3;
// Also ignore any request from the Editor itself if received soon after a Save.
let selfTriggerMsecs = 1500;
let lastEditorUpdateTime = Date.now(); // Last update from IntraMine's Editor

// Register callback for the auto refresh, "changeDetected".
function registerAutorefreshCallback() {
	addCallback("changeDetected", handleFileChanged);
}

// Remember time of last Save. See editor.js#notifyFileChangedAndRememberCursorLine().
function RememberLastEditorUpdateTime() {
	lastEditorUpdateTime = Date.now();
}

// 'changeDetected' message received from intramine_filewatcher.pl:
// reload unless user has unsaved changes and wants to keep them.
// Go to a specific line number if supplied.
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
			// Currently a line number is passed only if IntraMine's Editor does the change.
			if (lineNumberStr > 0) // "0" means line number unknown
				{
				// Avoid self triggering.
				let msecsSinceEditorUpdate = (currentTime - lastEditorUpdateTime);
				if (msecsSinceEditorUpdate >= selfTriggerMsecs)
					{
					location.hash = lineNumberStr;
					reloadUnlessUserSaysNo();
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
						reloadUnlessUserSaysNo();
						}
					}
				// else too soon, ignore message from Watcher
				}
			}
		}
}

function reloadUnlessUserSaysNo() {
	if (!codeMirrorIsDirty() || userSaysReload())
	{
	window.location.reload();
	}
}

function userSaysReload() {
	let msg = "File has changed on disk, but you have unsaved changes here. Click Yes to reload and lose your changes made here, click No to keep the changes you've made.";
	return (window.confirm(msg));
}

window.addEventListener('wsinit', function (e) { registerAutorefreshCallback(); }, false);
