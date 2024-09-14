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

ready(doResize);
ready(hideSpinner);
ready(disableReindexIfRemote);
window.addEventListener("resize", doResize);
