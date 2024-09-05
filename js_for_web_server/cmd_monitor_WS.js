// cmd_monitor_WS.js: handle WebSockets messages for a running "Command".
// StartCmd: disable Command buttons
// StopCmd: re-enable the Command buttons.
// Used in intramine_commandserver.pl and intramine_reindex.pl.
// See cmd_monitor.js#xableCmdAnchors() for the wsSendMessage calls.
// The server's short name is included in the message, eg StartCmd:Reindex
// so that both the Cmd and the Reindex servers can use this.
// A typical message call is wsSendMessage("StartCmd:" + shortServerName);
// as found in cmd_monitor.js#runTheCommand().

function registerCommandCallbacks() {
	addCallback("StartCmd:", disableCommands);
	addCallback("StopCmd:", enableCommands);
}

// Eg messages: StartCmd:Cmd, StopCmd:Reindex.
function disableCommands(message) {
	let fieldsArr = message.split(":");
	let shortName = fieldsArr[1];
	if (shortName === shortServerName)
		{
		xableCmdAnchors(false); // cmd_monitor.js#xableCmdAnchors()
		}
}

function enableCommands(message) {
	let fieldsArr = message.split(":");
	let shortName = fieldsArr[1];
	if (shortName === shortServerName)
		{
		xableCmdAnchors(true); // cmd_monitor.js#xableCmdAnchors()
		}
}

window.addEventListener('wsinit', function (e) { registerCommandCallbacks(); }, false);
