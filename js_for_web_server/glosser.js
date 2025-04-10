// glosser.js: respond to "NEWGLOSSMESSAGE" by appending the supplied message
// to the text area (#theTextWithoutJumpList), and resize.

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

function registerGlosserCallback() {
	addCallback("NEWGLOSSMESSAGE", refreshGlosserDisplay);
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

// Handle WebSockets message "NEWGLOSSMESSAGE".
// as sent by intramine_glosser.pl via gloss_to_html.pm.
async function refreshGlosserDisplay(message) {
	message = message.replace(/NEWGLOSSMESSAGE\:?/, '');
	let e1 = document.getElementById('theTextWithoutJumpList');
	e1.innerHTML += message;
	doResize();
	// Scroll last line into view.
	e1.scrollTop = e1.scrollHeight;
}

// Call back to intramine_glossary.pl with req=convert
async function runConversion() {
	let baseAction = 'http://' + theHost + ':' + thePort + '/?req=convert';
	// Gather dir/file, inline, hoverGIF

	try {
		let theAction = baseAction;
		const response = await fetch(theAction);
		if (response.ok)
			{
			let e1 = document.getElementById('theTextWithoutJumpList');
			e1.innerHTML = '<p>CONVERSION START</p>';
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
}

ready(doResize);
ready(hideSpinner);
window.addEventListener("resize", doResize);

window.addEventListener('wsinit', function (e) { registerGlosserCallback(); }, false);