/**
 * cmdServer.js: for intramine_commandserver.pl.
 * Load Cmd page, run a command, monitor its output.
 */

window.addEventListener("load", doResize);
window.addEventListener("resize", doResize);

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
