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
let distalSampleLines = ''; // Sample text from the distal position
let bigMoveLineLimit = 100; // Big move vs small move
let maxLinesForTogglePopup = 4;
let maxCharsForTogglePopup = 200;

function toggle() {
	//console.log("Toggle click");
	//console.log("Toggle, before: here " + proximalLineNumber + ", there " + distalLineNumber);
	distalSampleLines = linesAtLineNumber(proximalLineNumber, maxLinesForTogglePopup);

	// TEST ONLY
	//console.log("Go to: |" + distalSampleLines + "|");

	let tempNum = proximalLineNumber;
	proximalLineNumber = distalLineNumber;
	distalLineNumber = tempNum;
	let el = document.getElementById(cmTextHolderName);
	//console.log("Toggle, AFTER: here " + proximalLineNumber + ", there " + distalLineNumber);
	restoreTopPositionNonCM(el, proximalLineNumber);
}

function resetToggle() {
	proximalLineNumber = 1;
	distalLineNumber = 1;
	distalSampleLines = '';
}

function showToggleHint(obj, e) {
	if (distalSampleLines !== '')
		{
		showhint(distalSampleLines, obj, e, "400px", false);
		}
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
		distalSampleLines = linesAtLineNumber(proximalLineNumber, maxLinesForTogglePopup);

		// TEST ONLY
		//console.log("Go to: |" + distalSampleLines + "|");

		distalLineNumber = proximalLineNumber;
		proximalLineNumber = myStartLine;
		//console.log("AFTER BIG MOVE: here "+ proximalLineNumber + ", there " + distalLineNumber);
		}

	let toggleButton = document.getElementById("togglehits");
	if (toggleButton !== null)
		{
		if (distalLineNumber === proximalLineNumber)
			{
			toggleButton.disabled = true;
			}
		else
			{
			toggleButton.disabled = false;
			}
		}
		
	//console.log("Toggle position update top line " + myStartLine);
}

// Pull text at lineNumber, for showing in the Toggle button onmouseover.
function linesAtLineNumber(lineNumber, numLines) {
	let lines = '';
	let linesSoFar = 0;
	let firstLineNumber = lineNumber;
	let tdElement = document.getElementById('R' + lineNumber);
	while (tdElement !== null && ++linesSoFar <= numLines)
		{
		let lineText = tdElement.innerText;
		lines += lineText + "<br>";
		if (lines.length >= maxCharsForTogglePopup)
			{
			lines = lines.substring(0, maxCharsForTogglePopup);
			lines += '...';
			break;
			}
		++lineNumber;
		tdElement = document.getElementById('R' + lineNumber);
		if (tdElement === null) // probably a shrunkrow
			{
			++lineNumber;
			tdElement = document.getElementById('R' + lineNumber);
			}
		}

	if (lines !== '')
		{
		lines = 'Go to ' + firstLineNumber + ':<br>' + lines;
		lines = '<p>' + lines + '</p>';
		}
	
	return(lines);
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

