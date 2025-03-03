// mon.js: respond to WebSockets "NEWRUNMESSAGE" message by asking
// intramine_mon.pl for the latest main log entries
// and showing them in the #theTextWithoutJumpList div.
// And resize the display area.

let filePosition = "0"; // Passed back to and updated by Perl back end.

// Call fn when ready.
function ready(fn) {
	if (document.readyState != 'loading')
		{
		fn();
		}
	else
		{
		document.addEventListener('DOMContentLoaded', fn);
		}
}

function registerMonCallback() {
	addCallback("NEWRUNMESSAGE", refreshMonDisplay);
	// Also refresh the display as we come up.
	refreshMonDisplay("NEWRUNMESSAGE");
}

// Adjust the command output container to fill the bottom of the window.
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

// Handle WebSockets message "NEWRUNMESSAGE".
// as sent by (Perl) Monitor() calls.
// See intramine_mon.pl#LatestMessages() for the response.
// filePosition is remembered between calls.
async function refreshMonDisplay(message) {
	let newText = '';
	let baseAction = 'http://' + theHost + ':' + thePort + '/?req=monitor';

	try {
		let theAction = baseAction + '&filepos=' + filePosition;
		const response = await fetch(theAction);
		if (response.ok)
			{
			let text = await response.text();
			let filePosMatch = /^\|(\d+)\|/.exec(text);
			if (filePosMatch !== null)
				{
				filePosition = filePosMatch[1];
				newText = text.replace(/^\|\d+\|/, '');
				}
			}
		else
			{
			let e1 = document.getElementById('theTextWithoutJumpList');
			e1.innerHTML += '<strong>Error, server reached but it ran into trouble!</strong><br>';
			doResize();
			// Scroll last line into view.
			e1.scrollTop = e1.scrollHeight;
			}
		}
	catch(error) {
		// There was a connection error of some sort
		let e1 = document.getElementById('theTextWithoutJumpList');
		e1.innerHTML += '<strong>Connection error while attempting to monitor output!</strong><br>';
		doResize();
		// Scroll last line into view.
		e1.scrollTop = e1.scrollHeight;
		}


	if (newText !== '')
		{
		let e1 = document.getElementById('theTextWithoutJumpList');
		e1.innerHTML += newText;
		doResize();
		// Scroll last line into view.
		e1.scrollTop = e1.scrollHeight;
		}
}

ready(doResize);
ready(hideSpinner);
window.addEventListener("resize", doResize);

window.addEventListener('wsinit', function (e) { registerMonCallback(); }, false);
