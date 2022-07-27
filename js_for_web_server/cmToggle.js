//cmToggle.js: toggle between two positions in a document.
// Track "proximal" (current) and "distal" (previous) positions
// in response to all changes in scrolled position.
// If it's a small move, update the proximal position.
// If it's a big move, call the new position proximal, and the old
// proximal becomes distal.
// Toggle: switch proximal with distal, and scroll proximal into view.

let proximalLineNumber = 0; // "here"
let distalLineNumber = 0;	// "there"
let bigMoveLineLimit = 100; // Big move vs small move

function toggle() {
	//console.log("Toggle click");
	let tempNum = proximalLineNumber;
	proximalLineNumber = distalLineNumber;
	distalLineNumber = tempNum;
	jumpToLine(proximalLineNumber, false);
}

function updateTogglePositions() {
	let rect = myCodeMirror.getWrapperElement().getBoundingClientRect();
	let myStartLine = myCodeMirror.lineAtHeight(rect.top, "window");
	if (myStartLine > 0)
		{
		myStartLine += 2;
		}
	let linesScrolled = proximalLineNumber - myStartLine;
	if (linesScrolled < 0)
		{
		linesScrolled = -linesScrolled;
		}
	if (linesScrolled <= bigMoveLineLimit)
		{
		proximalLineNumber = myStartLine;
		}
	else
		{
		distalLineNumber = proximalLineNumber;
		proximalLineNumber = myStartLine;
		}
	//console.log("Toggle position call, top line is " + myStartLine);
}

// Borrowed from
//https://gomakethings.com/detecting-when-a-visitor-has-stopped-scrolling-with-vanilla-javascript/
let isScrolling = null;
function addToggleScrollListener() {
	myCodeMirror.on("scroll", function() {
		
		// Clear our timeout throughout the scroll
		window.clearTimeout( isScrolling );

		// Set a timeout to run after scrolling ends
		isScrolling = setTimeout(function() {
			// Run the callback
			updateTogglePositions();
		}, 66);
	});
}

// Set the number of lines that counts as a "big move"
// (meaning a real change of position, not just an adjustment
// of current position).
// Called by cmviewerstart.js#loadFileIntoCodeMirror() and
// cmviewerstart.js#doResize().
function updateToggleBigMoveLimit() {
	let cm = myCodeMirror;

	// Get the number of visible lines, add a little bit.
	let rect = cm.getWrapperElement().getBoundingClientRect();
	let firstVisibleLineNum = cm.lineAtHeight(rect.top, "window");
	let lastVisibleLineNum = cm.lineAtHeight(rect.bottom, "window");
	
	let numVisibleLines = lastVisibleLineNum - firstVisibleLineNum;
	if (numVisibleLines <= 10)
		{
		bigMoveLineLimit = 20;
		}
	else
		{
		bigMoveLineLimit = numVisibleLines + 10;
		}
		
	//console.log("Big move limit: " + bigMoveLineLimit);
}

window.addEventListener("load", addToggleScrollListener);
