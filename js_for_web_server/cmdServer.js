/**
 * cmdServer.js: for intramine_commandserver.pl.
 * Load Cmd page, run a command, monitor its output.
 */

window.addEventListener("load", doResize);
window.addEventListener("resize", doResize);

//  Unused.
function getRandomInt(min, max) {
	return Math.floor(Math.random() * (max - min + 1) + min);
}

// xmlhttprequest, load and set page content.
// See intramine_commandserver.pl#CommandPage() for theHost and thePort.
// 'req=content' goes to the $RequestAction{'req|content'} handler.
function loadPageContent() {
	showSpinner();
	let request = new XMLHttpRequest();
	request.open('get', 'http://' + theHost + ':' + thePort + '/?req=content', true);

	request.onload = function() {
		if (request.status >= 200 && request.status < 400)
			{
			// Success!
			let e1 = document.getElementById(commandContainerDiv);
			e1.innerHTML = request.responseText;
			hideSpinner();
			}
		else
			{
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(commandContainerDiv);
			e1.innerHTML = '<p>Error, server reached but it returned an error!</p>';
			hideSpinner();
			}
	};

	request.onerror = function() {
		// There was a connection error of some sort
		let e1 = document.getElementById(commandContainerDiv);
		e1.innerHTML = '<p>Connection error!</p>';
		hideSpinner();
	};

	request.send();
}

// Call intramine_commandserver.pl's $RequestAction{'req|open'} handler to run a command,
// optionally set timers to monitor restart or command output.
// See intramine_commandserver.pl#OneCommandString() for the call to this function.
function runTheCommand(ank) {
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
	let request = new XMLHttpRequest();
	request.open('get', 'http://' + theHost + ':' + thePort + '/?req=open&file=' + properHref + '&'
			+ trailer, true);

	request.onload = function() {
		if (request.status >= 200 && request.status < 400)
			{
			// Success?
			ank.style.color = '#FFFFFF';
			let resp = request.responseText;
			if (resp !== 'OK')
				{
				let e1 = document.getElementById(runMessageDiv);
				e1.innerHTML = 'Error trying to run the command: ' + resp;
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
					setTimeout(function() {
						monitorUntilRestart(ank);
					}, 5000); // give main server time to quit
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
					setTimeout(function() {
						monitorCmdOutUntilDone(ank);
					}, 1000); // give cmd time to start
					}
				else
					{
					let e1 = document.getElementById(runMessageDiv);
					e1.innerHTML = '&nbsp;';
					hideSpinner();
					}
				}
			}
		else
			{
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(runMessageDiv);
			e1.innerHTML = 'Error, server reached but it could not run the command!';
			hideSpinner();
			ank.style.color = '#FFFFFF';
			}
	};

	request.onerror = function() {
		// There was a connection error of some sort
		let e1 = document.getElementById(runMessageDiv);
		e1.innerHTML = 'Connection error while attempting to run command!';
		hideSpinner();
		ank.style.color = '#FFFFFF';
	};

	request.send();
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
function monitorUntilRestart(ank) {
	let e1 = document.getElementById(runMessageDiv);
	e1.innerHTML = 'Waiting for main server restart...';

	let request = new XMLHttpRequest();
	request.open('get', 'http://' + theHost + ':' + thePort + '/?req=ping', true);

	request.onload = function() {
		if (request.status >= 200 && request.status < 400)
			{
			// Success?
			let resp = request.responseText;
			if (resp.indexOf("OK") === 0) // OK stopped vs OK restarted - no errors expected here
				{
				if (resp.indexOf("restarted") >= 0) // done, all ok
					{
					let e1 = document.getElementById(runMessageDiv);
					e1.innerHTML = '&nbsp;';
					ank.style.color = '#FFFFFF';
					hideSpinner();
					}
				else
					// not restarted yet, keep going but don't be a pest
					{
					setTimeout(function() {
						monitorUntilRestart(ank);
					}, 2000); // RECURSIVE
					}
				}
			else
				// unexpected error, details in resp
				{
				let e1 = document.getElementById(runMessageDiv);
				e1.innerHTML = 'ERROR: ' + resp;
				ank.style.color = '#FF8888';
				hideSpinner();
				}
			}
		else
			{
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(runMessageDiv);
			e1.innerHTML = 'Error, server reached but it ran into trouble!';
			ank.style.color = '#FF8888';
			hideSpinner();
			}
	};

	request.onerror = function() {
		// There was a connection error of some sort
		let e1 = document.getElementById(runMessageDiv);
		e1.innerHTML = 'Connection error while attempting to monitor restart!';
		ank.style.color = '#FF8888';
		hideSpinner();
	};

	request.send();
}

// Ask for output from current "command" being run, show it on the Cmd page.
// Called by runTheCommand() above.
// Send a 'req=monitor' AJAX request to this server, which calls the Perl
// sub CommandOutput() and sends back new output to here in request.responseText.
// This is slightly 'delicate' in that three specific text strings are prepended
// to the responseText to signal what's happening:
// ***A-L-L***D-O-N-E*** - command has finished running
// ***E-R-R-O-R*** - something blew up, command has stopped abnormally
// ***N-O-T-H-I-N-G***N-E-W*** - no new output since last request
// and absence of those means something new in responseText, to be added to displayed results.
// Of course, if the command being run outputs ***E-R-R-O-R*** then that could cause
// us to drop out here, so it's not perfect.
function monitorCmdOutUntilDone(ank) {
	let request = new XMLHttpRequest();
	request.open('get', 'http://' + theHost + ':' + thePort + '/?req=monitor', true);

	request.onload = function() {
		if (request.status >= 200 && request.status < 400)
			{
			// Success?
			let resp = request.responseText;
			if (resp.indexOf("***A-L-L***D-O-N-E***") === 0)
				{
				let e1 = document.getElementById(runMessageDiv);
				e1.innerHTML = '&nbsp;';
				ank.style.color = '#FFFFFF';
				hideSpinner();
				}
			else if (resp.indexOf("***E-R-R-O-R***") === 0)
				{
				let errorMessage = resp.replace(/^\*\*\*E-R-R-O-R\*\*\*/, '');
				let e1 = document.getElementById(runMessageDiv);
				e1.innerHTML = 'Command Exec Error: ' + errorMessage;
				ank.style.color = '#FF8888';
				hideSpinner();
				}
			else if (resp.indexOf("***N-O-T-H-I-N-G***N-E-W***") === 0)
				{
				setTimeout(function() {
					monitorCmdOutUntilDone(ank);
				}, 1000); // RECURSIVE
				}
			else
				// we have something
				{
				e1 = document.getElementById(commandOutputDiv);
				e1.innerHTML += resp;
				doResize();
				// Scroll last line into view.
				e1.scrollTop = e1.scrollHeight;
				setTimeout(function() {
					monitorCmdOutUntilDone(ank);
				}, 1000); // RECURSIVE
				}
			}
		else
			{
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(runMessageDiv);
			e1.innerHTML = 'Error, server reached but it ran into trouble!';
			ank.style.color = '#FF8888';
			hideSpinner();
			}
	};

	request.onerror = function() {
		// There was a connection error of some sort
		let e1 = document.getElementById(runMessageDiv);
		e1.innerHTML = 'Connection error while attempting to monitor output!';
		ank.style.color = '#FF8888';
		hideSpinner();
	};

	request.send();
}

// Resize the Cmd window.
function doResize() {
	let el = document.getElementById(cmdOutputContainerDiv);

	let pos = getPosition(el);
	let windowHeight = window.innerHeight;
	let elHeight = windowHeight - pos.y - 10;
	let newHeightPC = (elHeight / windowHeight) * 100;
	el.style.height = newHeightPC + "%";

	let windowWidth = window.innerWidth;
	el.style.width = windowWidth - 4 + "px";
}

// Get things going.
window.addEventListener("load", loadPageContent);
