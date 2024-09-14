// cmd_monitor_WS.js: handle WebSockets messages for a running "Command".
// StartCmd: disable Command buttons and begin monitoring.
// StopCmd: re-enable the Command buttons. Unless it's the Reindex
// button, where we don't re-enable unless it's on the IntraMine PC.
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
	let id = '';
	if (fieldsArr.length >= 3)
		{
		id = fieldsArr[2];
		}
	
	if (shortName === shortServerName)
		{
		if (shortServerName === 'Reindex' && weAreRemote)
			{
			let showRunMessage = false;
			xableCmdAnchors(false, showRunMessage);
			}
		else
			{
			xableCmdAnchors(false); // cmd_monitor.js#xableCmdAnchors()
			}
		monitorCmdOutUntilDone("ignore", false, id); // cmd_monitor.js
		}
}

function enableCommands(message) {
	let fieldsArr = message.split(":");
	let shortName = fieldsArr[1];
	if (shortName === shortServerName)
		{
		// There's always an exception, isn't there?
		// the Reindex button on the Reindex page should
		// not be enabled if it's remote (ie the page is not
		// on the IntraMine PC), Raa is required to run and
		// the prompt for that will appear only on the IntraMine PC.
		if (!(shortServerName === 'Reindex' && weAreRemote))
			{
			xableCmdAnchors(true); // cmd_monitor.js#xableCmdAnchors()
			}
		else
			{
			let showRunMessage = false;
			xableCmdAnchors(false, showRunMessage);
			}
		}
}

window.addEventListener('wsinit', function (e) { registerCommandCallbacks(); }, false);
