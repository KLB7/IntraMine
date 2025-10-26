// reindex.js: size adjustment for the div that holds output.
// Goes with intramine_reindex.pl, reindex.js.

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

// If we're not on the IntraMine PC, disable
// the Reindex button.
function disableReindexIfRemote() {
	if (weAreRemote)
		{
		let showRunMessage = false;
		xableCmdAnchors(false, showRunMessage); // cmd_monitor.js#xableCmdAnchors()
		}
}

// Progress bar, and clamp().
//<progress id="progress-bar" value="0" max="100" visibility="hidden"></progress>

function setProgress(val) {
	//console.log("Setting progress to " + val);
	let progressElements = document.getElementsByTagName('progress');
	if (progressElements.length === 0)
		{
		return;
		}
	let progressElement = progressElements[0];
	
	progressElement.value = clamp(val);
}

function showProgressBar() {
	//console.log("Showing progress bar");
	let progressElements = document.getElementsByTagName('progress');
	if (progressElements.length === 0)
		{
		return;
		}
	let progressElement = progressElements[0];

	progressElement.style.height = "6px";
	progressElement.style.width = "400px";
	progressElement.value = 0;
	progressElement.style.accentColor = 'green';
	progressElement.style.visibility = 'visible';
}

function hideProgressBar() {
	//console.log("Hiding progress bar");
	let progressElements = document.getElementsByTagName('progress');
	if (progressElements.length === 0)
		{
		return;
		}
	let progressElement = progressElements[0];

	progressElement.value = 0;
	progressElement.style.visibility = 'hidden';
}

const clamp = (val, min = 0, max = 100) => Math.min(Math.max(val, min), max);

ready(doResize);
ready(hideSpinner);
ready(disableReindexIfRemote);
ready(hideProgressBar);
window.addEventListener("resize", doResize);
