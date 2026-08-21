//cmToggle.js: toggle between two positions in a document.
// Track "proximal" (current) and "distal" (previous) positions
// in response to all changes in scrolled position.
// If it's a small move, update the proximal position.
// If it's a big move, call the new position proximal, and the old
// proximal becomes distal.
// Toggle: switch proximal with distal, and scroll proximal into view.

let proximalLineNumber = 0; // "here"
let distalLineNumber = 0;	// "there"
let distalSampleLines = ''; // Sample text from the distal position
let bigMoveLineLimit = 100; // Big move vs small move
let maxLinesForTogglePopup = 4;
let maxCharsForTogglePopup = 200;

function toggle() {
	//console.log("Toggle click");
	distalSampleLines = linesAtLineNumber(proximalLineNumber, maxLinesForTogglePopup);
	let tempNum = proximalLineNumber;
	proximalLineNumber = distalLineNumber;
	distalLineNumber = tempNum;
	jumpToLine(proximalLineNumber, false);
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
		distalSampleLines = linesAtLineNumber(proximalLineNumber, maxLinesForTogglePopup);
		distalLineNumber = proximalLineNumber;
		proximalLineNumber = myStartLine;
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

	//console.log("Toggle position call, top line is " + myStartLine);
}

// Pull text at lineNumber, for showing in the Toggle button onmouseover.
function linesAtLineNumber(lineNumber, numLines) {
	let lines = '';
	let linesSoFar = 0;
	let maximumLines = myCodeMirror.lineCount();
	let firstLineNumber = lineNumber;

	while (++linesSoFar <= numLines && lineNumber < maximumLines)
		{
		let lineText = myCodeMirror.getLine(lineNumber);
		lines += lineText + "<br>";
		if (lines.length >= maxCharsForTogglePopup)
			{
			lines = lines.substring(0, maxCharsForTogglePopup);
			lines += '...';
			break;
			}
		++lineNumber;
		}

	if (lines !== '')
		{
		let displayedLineNumber = firstLineNumber + 1;
		lines = 'Go to ' + displayedLineNumber + ':<br>' + lines;
		lines = '<p>' + lines + '</p>';
		}
	
	return(lines);
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
