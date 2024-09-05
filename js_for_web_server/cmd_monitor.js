/**
 * cmdServer.js: for intramine_commandserver.pl.
 * Load Cmd page, run a command, monitor its output.
 */

//  Unused.
function getRandomInt(min, max) {
	return Math.floor(Math.random() * (max - min + 1) + min);
}

// "sleep" for ms milliseconds.
function sleepABit(ms) {
	return new Promise(resolve => setTimeout(resolve, ms));
}

// Enable/disable all Cmd anchors.
// They have id's Cmd1, Cmd2 etc.
function xableCmdAnchors(enableThem) {
	let baseId = "Cmd";
	let cmdNumber = 1;
	let id = baseId + String(cmdNumber);

	let el = document.getElementById(id);
	while (el !== null)
		{
		if (enableThem)
			{
			el.style.opacity = "1.0";
			el.style.pointerEvents = "auto";
			el.style.cursor = "pointer";
			}
		else
			{
			el.style.opacity = "0.5";
			el.style.pointerEvents = "none";
			el.style.cursor = "default";
			}

		++cmdNumber;
		id = baseId + String(cmdNumber);
		el = document.getElementById(id);
		}

	// Optional run message
	let runSpan = document.getElementById('running');
	if (runSpan !== null)
		{
		if (enableThem)
			{
			runSpan.innerHTML = '';
			}
		else
			{
				runSpan.innerHTML = ' Running';
			}
		}
}

// Load and set page content.
// See intramine_commandserver.pl#CommandPage() for theHost and thePort.
// 'req=content' goes to the $RequestAction{'req|content'} handler.
async function loadPageContent() {
	showSpinner();

	try {
		let theAction = 'http://' + theHost + ':' + thePort + '/?req=content';
		const response = await fetch(theAction);
		if (response.ok)
			{
			// Success!
			let text = await response.text();
			let e1 = document.getElementById(commandContainerDiv);
			e1.innerHTML = text;
			hideSpinner();
			}
		else
			{
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(commandContainerDiv);
			e1.innerHTML = '<p>Error, server reached but it returned an error!</p>';
			hideSpinner();
			}
	}
	catch(error) {
		// There was a connection error of some sort
		let e1 = document.getElementById(commandContainerDiv);
		e1.innerHTML = '<p>Connection error!</p>';
		hideSpinner();
	}
}

// Call intramine_commandserver.pl's $RequestAction{'req|open'} handler to run a command,
// optionally monitor restart or command output.
// See intramine_commandserver.pl#OneCommandString() for the call to this function.
async function runTheCommand(ank) {
	let hrefplusRand = ank.href;
	let arrayMatch = /^([^?]+)\?(.*)$/.exec(hrefplusRand);
	let href = arrayMatch[1];
	let trailer = arrayMatch[2]; // eg willrestart=1&srvrip='$peeraddress'&rddm=$rdm
	let properHref1 = href.replace(/^file\:\/\/\//, '');
	// Browser prepends http://192.168.0.3:43124/ or http://192.168.0.3:43124/Cmd/
	// or even uses 'localhost' in place of numeric IP. We will trim all of those.
	let numRegex = new RegExp('^http:\/\/' + theHost + '\:' + thePort + '\/(Cmd\/)?');
	let localRegex = new RegExp('^http:\/\/localhost\:' + thePort + '\/(Cmd\/)?');
	let properHref2 = properHref1.replace(numRegex, '');
	let properHref = properHref2.replace(localRegex, '');
	let otherArgs = additionalArgsForCommand(ank);
	properHref += otherArgs;
	
	// Send "activity" message.
	wsSendMessage('activity ' + shortServerName + ' ' + ourSSListeningPort);

	let e1 = document.getElementById(runMessageDiv);
	e1.innerHTML = 'Running...';
	showSpinner();
	ank.style.color = '#88FF88';

	// Disable commands while one is running.
	wsSendMessage("StartCmd:" + shortServerName);

	try {
		let theAction = 'http://' + theHost + ':' + thePort + '/?req=open&file=' + properHref + '&'
		+ trailer;
		const response = await fetch(theAction);
		if (response.ok)
			{
			let text = await response.text();
			ank.style.color = '#FFFFFF';
			if (text !== 'OK')
				{
				let e1 = document.getElementById(runMessageDiv);
				e1.innerHTML = 'Error trying to run the command: ' + text;
				wsSendMessage("StopCmd:" + shortServerName);
				hideSpinner();
				}
			else
				{
				let e1 = document.getElementById(runMessageDiv);
				e1.innerHTML = '&nbsp;';
				
				// If main server stop/stop expected, monitor until restart
				if (trailer.indexOf("willrestart=1") >= 0)
					{
					ank.style.color = '#808080';
					await sleepABit(5000);
					monitorUntilRestart(ank);
					}
				else if (trailer.indexOf("monitor=1") >= 0) // Ask regularly for cmd output and display it
					{
					let properHrefDec = decodeURIComponent(properHref);
					let e1 = document.getElementById('cmdOutputTitle');
					e1.innerHTML = '<h3>Output from ' + properHrefDec + '</h3>';
					e1 = document.getElementById(runMessageDiv);
					e1.innerHTML = 'Monitoring command output...';
					e1 = document.getElementById(commandOutputDiv);
					e1.innerHTML = '';
					ank.style.color = '#88FF88';
					await sleepABit(1000);
					monitorCmdOutUntilDone(ank);
					}
				else
					{
					let e1 = document.getElementById(runMessageDiv);
					e1.innerHTML = '&nbsp;';
					wsSendMessage("StopCmd:" + shortServerName);
					hideSpinner();
					}
				}
			}
		else
			{
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(runMessageDiv);
			e1.innerHTML = 'Error, server reached but it could not run the command!';
			wsSendMessage("StopCmd:" + shortServerName);
			hideSpinner();
			ank.style.color = '#FFFFFF';
			}
	}
	catch(error) {
		// There was a connection error of some sort
		let e1 = document.getElementById(runMessageDiv);
		e1.innerHTML = 'Connection error while attempting to run command!';
		wsSendMessage("StopCmd:" + shortServerName);
		hideSpinner();
		ank.style.color = '#FFFFFF';
	}
}

function additionalArgsForCommand(ank) {
	let args = '';
	let numArgs = 0;

	let pnode = ank.parentNode; // div
	if (pnode !== null)
		{
		pnode = pnode.parentNode; // td
		if (pnode !== null)
			{
			pnode = pnode.parentNode; // tr
			if (pnode !== null && pnode.hasChildNodes)
				{
				let nextCell = pnode.firstChild.nextSibling; // second td
				if (nextCell !== null && nextCell.hasChildNodes)
					{
					let children = nextCell.childNodes; // a mix of text and input
					for (let i = 0; i < children.length; i++)
						{
						let ele = children[i];
						let nodeName = ele.nodeName.toUpperCase();
						if (nodeName === "INPUT" && ele.hasAttribute("name"))
							{
							let value = ele.value;
							if (value !== '')
								{
								if (numArgs === 0)
									{
									args = ' ' + value;
									}
								else
									{
									args += ' ' + value;
									}
								++numArgs;
								}
							}
						}
					}
				}
			}
		}

	return (args);
}

// Repeatedly ping main server. We're waiting for a restart, then clear pacifier.
// Errors are unlikely, will probably be due to a maintenance err.
async function monitorUntilRestart(ank) {
	let e1 = document.getElementById(runMessageDiv);
	e1.innerHTML = 'Waiting for main server restart...';

	let theAction = 'http://' + theHost + ':' + thePort + '/?req=ping';
	let keepGoing = true;

	while (keepGoing)
		{
		try {
			const response = await fetch(theAction);
			if (response.ok)
				{
				let text = await response.text();
				if (text.indexOf("OK") === 0) // OK stopped vs OK restarted - no errors expected here
					{
					if (text.indexOf("restarted") >= 0) // done, all ok
						{
						keepGoing = false;
						let e1 = document.getElementById(runMessageDiv);
						e1.innerHTML = '&nbsp;';
						ank.style.color = '#FFFFFF';
						wsSendMessage("StopCmd:" + shortServerName);
						hideSpinner();
						}
					else // not restarted yet, keep going but don't be a pest
						{
						await sleepABit(2000);
						}
					}
				else // unexpected error, details in text
					{
					keepGoing = false;
					let e1 = document.getElementById(runMessageDiv);
					e1.innerHTML = 'ERROR: ' + text;
					ank.style.color = '#FF8888';
					wsSendMessage("StopCmd:" + shortServerName);
					hideSpinner();
					}
				}
			else
				{
				// We reached our target server, but it returned an error
				keepGoing = false;
				let e1 = document.getElementById(runMessageDiv);
				e1.innerHTML = 'Error, Main server reached but it ran into trouble!';
				ank.style.color = '#FF8888';
				wsSendMessage("StopCmd:" + shortServerName);
				hideSpinner();
				}
			}
		catch(error) {
			// There was a connection error of some sort
			keepGoing = false;
			let e1 = document.getElementById(runMessageDiv);
			e1.innerHTML = 'Connection error to Main while attempting to monitor restart!';
			ank.style.color = '#FF8888';
			wsSendMessage("StopCmd:" + shortServerName);
			hideSpinner();
			}
		}
	}

// Ask for output from current "command" being run, show it on the Cmd page.
// Called by runTheCommand() above.
// Send a 'req=monitor' request to this server, which calls the Perl
// sub CommandOutput() and sends back new output to here in its response.
// This is slightly 'delicate' in that three specific text strings are prepended
// to the responseText to signal what's happening:
// ***A-L-L***D-O-N-E*** - command has finished running
// ***E-R-R-O-R*** - something blew up, command has stopped abnormally
// ***N-O-T-H-I-N-G***N-E-W*** - no new output since last request
// and absence of those means something new in response, to be added to displayed results.
// Of course, if the command being run outputs "***E-R-R-O-R***"" then that could cause
// us to drop out here, so it's not perfect.
async function monitorCmdOutUntilDone(ank) {
	let theAction = 'http://' + theHost + ':' + thePort + '/?req=monitor';
	let keepGoing = true;

	while (keepGoing)
		{
		try {
			const response = await fetch(theAction);
			if (response.ok)
				{
				let text = await response.text();

				if (text.indexOf("***A-L-L***D-O-N-E***") >= 0)
					{
					keepGoing = false;
					let e1 = document.getElementById(runMessageDiv);
					e1.innerHTML = '&nbsp;';
					ank.style.color = '#FFFFFF';
					wsSendMessage("StopCmd:" + shortServerName);

					let textNoDone = text.replace("***A-L-L***D-O-N-E***", "");;
					e1 = document.getElementById(commandOutputDiv);
					e1.innerHTML += textNoDone;
					doResize();
					// Scroll last line into view.
					e1.scrollTop = e1.scrollHeight;
					hideSpinner();
					}
				else if (text.indexOf("***E-R-R-O-R***") === 0)
					{
					keepGoing = false;
					let errorMessage = text.replace(/^\*\*\*E-R-R-O-R\*\*\*/, '');
					let e1 = document.getElementById(runMessageDiv);
					e1.innerHTML = 'Command Exec Error: ' + errorMessage;
					ank.style.color = '#FF8888';
					wsSendMessage("StopCmd:" + shortServerName);
					hideSpinner();
					}
				else if (text.indexOf("***N-O-T-H-I-N-G***N-E-W***") === 0)
					{
					// Send an additional StartCmd message, in the rare
					// case that someone opens a new tab on our service.
					wsSendMessage("StartCmd:" + shortServerName);
					await sleepABit(1000);
					}
				else // we have something to show
					{
					wsSendMessage("StartCmd:" + shortServerName);
					let e1 = document.getElementById(commandOutputDiv);
					e1.innerHTML += text;
					doResize();
					// Scroll last line into view.
					e1.scrollTop = e1.scrollHeight;
					await sleepABit(1000);
					}
				}
			else
				{
				// We reached our target server, but it returned an error
				keepGoing = false;
				let e1 = document.getElementById(runMessageDiv);
				e1.innerHTML = 'Error, server reached but it ran into trouble!';
				ank.style.color = '#FF8888';
				wsSendMessage("StopCmd:" + shortServerName);
				hideSpinner();
				}
			}
		catch(error) {
			// There was a connection error of some sort
			keepGoing = false;
			let e1 = document.getElementById(runMessageDiv);
			e1.innerHTML = 'Connection error while attempting to monitor output!';
			ank.style.color = '#FF8888';
			wsSendMessage("StopCmd:" + shortServerName);
			hideSpinner();
			}
		} // while keepGoing
	}
