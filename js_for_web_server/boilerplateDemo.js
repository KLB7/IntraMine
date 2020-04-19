// boilerplateDemo.js: for intramine_boilerplate.pl. Handle window resizing, and turn
// the spinning pacifier off when load is complete.

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

// Adjust main content height to show/hide scroll bars.
function doResize() {
	let el = document.getElementById("scrollAdjustedHeight");
	let pos = getPosition(el);
	let windowHeight = window.innerHeight;
	el.style.height = ((windowHeight - pos.y - 10) / windowHeight) * 100 + "%";
	el.style.width = window.innerWidth - 4 + "px";
}

// Top Nav includes a gif that's animated while the page is loading.
// Turn it off when page has loaded.
function turnOffTheLoadingSpinner() {
	hideSpinner(); // spinner.js#hideSpinner()
}

ready(doResize);
ready(turnOffTheLoadingSpinner);
window.addEventListener("resize", doResize);
