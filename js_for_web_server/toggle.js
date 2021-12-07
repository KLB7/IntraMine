// toggle.js: toggle between two positions in a document.
// This is for non-CodeMirror file views, as presented by IntraMine's Viewer service.
// Track "proximal" (current) and "distal" (previous) positions
// in response to all changes in scrolled position.
// If it's a small move, update the proximal position.
// If it's a big move, call the new position proximal, and the old
// proximal becomes distal.
// Toggle: scroll distal into view, and switch proximal with distal.

let proximalLineNumber = 1;	// "here"
let distalLineNumber = 1;	// "there"
let bigMoveLineLimit = 100; // Big move vs small move

function toggle() {
	//console.log("Toggle click");
	//console.log("Toggle, before: here " + proximalLineNumber + ", there " + distalLineNumber);
	let tempNum = proximalLineNumber;
	proximalLineNumber = distalLineNumber;
	distalLineNumber = tempNum;
	let el = document.getElementById(cmTextHolderName);
	//console.log("Toggle, AFTER: here " + proximalLineNumber + ", there " + distalLineNumber);
	restoreTopPositionNonCM(el, proximalLineNumber);
}

function updateTogglePositions() {
	let el = document.getElementById(cmTextHolderName);
	let myStartLine = firstVisibleLineNumber(el);
	//console.log("update myStartLine " + myStartLine);
	if (myStartLine < 1)
		{
		myStartLine = 1;
		}
	//console.log("update here " + proximalLineNumber);
	let linesScrolled = proximalLineNumber - myStartLine;
	//console.log("update lines scrolled: " + linesScrolled);
	if (linesScrolled < 0)
		{
		linesScrolled = -linesScrolled;
		}
	if (linesScrolled <= bigMoveLineLimit)
		{
		//console.log("small move, here " + proximalLineNumber + ", there " + distalLineNumber + " before update");
		proximalLineNumber = myStartLine;
		//console.log(" here is " + proximalLineNumber + " after update.)");
		}
	else
		{
		//console.log("Big move! here " + proximalLineNumber + ", there " + distalLineNumber + " before update")
		distalLineNumber = proximalLineNumber;
		proximalLineNumber = myStartLine;
		//console.log("AFTER BIG MOVE: here "+ proximalLineNumber + ", there " + distalLineNumber);
		}
	//console.log("Toggle position update top line " + myStartLine);
}

// Borrowed from
//https://gomakethings.com/detecting-when-a-visitor-has-stopped-scrolling-with-vanilla-javascript/
let isScrolling = null;
function addToggleScrollListener() {
	let el = document.getElementById(cmTextHolderName);
	if (el !== null)
		{
		el.addEventListener("scroll", function() {
			// Clear our timeout throughout the scroll
			window.clearTimeout( isScrolling );
	
			// Set a timeout to run after scrolling ends
			isScrolling = setTimeout(function() {
				// Run the callback
				updateTogglePositions();
			}, 66);
			});
		}
}

// Set the number of lines that counts as a "big move"
// (meaning a real change of position, not just an adjustment
// of current position).
// Called by viewerStart.js#doResize() and on load by
// viewerStart.js#reJumpAndHighlight().
function updateToggleBigMoveLimit() {
	let el = document.getElementById(cmTextHolderName);
	let firstVisibleLineNum = firstVisibleLineNumber(el);
	let lastVisibleLineNum = lastVisibleLineNumber(el);
	
	// Problem, sometimes lastVisibleLineNumber() can return 0.
	if (lastVisibleLineNum === 0)
		{
		lastVisibleLineNum = lastVisibleLineNumber(el);
		if (lastVisibleLineNum === 0)
			{
			//console.log("EARLY EXIT in updateToggleBigMoveLimit!");
			return;
			}
		}
	
	let numVisibleLines = lastVisibleLineNum - firstVisibleLineNum;
	if (numVisibleLines <= 10)
		{
		bigMoveLineLimit = 20;
		//console.log("TINY WINDOW!");
		}
	else
		{
		bigMoveLineLimit = numVisibleLines + 10;
		}
	
	//console.log("First vis: " + firstVisibleLineNum);
	//console.log("LAST vis: " + lastVisibleLineNum);
	//console.log("Big move limit: " + bigMoveLineLimit);
}

window.addEventListener("load", addToggleScrollListener);

