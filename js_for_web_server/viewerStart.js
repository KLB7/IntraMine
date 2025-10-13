// viewerStart.js: used for non-CodeMirror views in intramine_viewer.pl.
// Manage layout changes on resize, jump to an anchor
// Put highlight hits in text and on scrollbar.
// Show/hide any initial search hits provided in highlightitems.
// Preserve user selection when marking, by remembering selection range, removing selected
// text before marking, then restoring text and selection range after marking (patent not pending).

const delay = ms => new Promise(res => setTimeout(res, ms));

let markerMainElement = document.getElementById(cmTextHolderName);
if (markerMainElement === null)
	{
	markerMainElement = document.getElementById("scrollText");
	}
if (markerMainElement === null)
	{
	markerMainElement = document.getElementById(specialTextHolderName);
	}

let tocMainElement = document.getElementById("scrollContentsList");

let onMobile = false; // Set below, true if we have touch events.
if (typeof window.ontouchstart !== 'undefined')
	{
	onMobile = true;
	}

window.addEventListener("load", reJumpAndHighlight);
window.addEventListener("resize", JD.debounce(doResize, 100));

// Adjust some element heights so scrolling works properly.
function doResize() {
	restoreColumnWidths();

	let rule = document.getElementById("rule_above_editor");
	let pos = getPosition(rule);
	let rect = rule.getBoundingClientRect();
	let ruleHeight = rect.height;

	let windowHeight = window.innerHeight;
	let elHeight = windowHeight - pos.y - ruleHeight - 8;
	let newHeightPC = (elHeight / windowHeight) * 100;
	let el = document.getElementById("scrollAdjustedHeight");
	el.style.height = newHeightPC + "%";

	if (tocMainElement !== null)
		{
		let tocMarginTop =
				parseInt(window.getComputedStyle(tocMainElement).getPropertyValue('margin-top'));
		let tocHeight = elHeight - tocMarginTop;
		if (onMobile)
			{
			tocHeight -= 20;
			}
		else
			{
			tocHeight -= 16;
			}
		let newTocHeightPC = (tocHeight / elHeight) * 100;
		tocMainElement.style.height = newTocHeightPC + "%";
		}

	if (initialSearchHitsAreShowing)
		{
		removeInitialHighlights();
		highlightInitialItems();
		}

	if (!onMobile)
		{
		scrollIndicator();
		}
	else
		{
		scrollMobileIndicator(); // if mobile
		}
	
	// TEST ONLY
	//console.log("doResize");
	reJump();
	
	updateToggleBigMoveLimit();

	repositionTocToggle();
}

// On "load", scroll any location.hash position into view, and put highlights on any
// words that formed part of a search that produced this file as a hit.
// See intramine_viewer.pl#InitialHighlightItems().
async function reJumpAndHighlight() {
	addDragger && addDragger(); // dragTOC.js#addDragger()
	
	reJump(100); // "100" adds a slight delay before line number scrollIntoView().
	updateToggleBigMoveLimit();
	updateTogglePositions();
	highlightInitialItems();

	setIsMarkdown();

	await delay(150);

	if (isMarkdown)
		{
		addAutoLinksForMarkdown();
		}
	else
		{
		addAutoLinks();
		}
}

// Set top of nav to zero, fixes an iPad scroll problem where nav goes off the top.
function resetTopNavPosition() {
	let nav = document.getElementById("nav"); // nope nav.style.top = 0;
	if (nav !== null)
		{
		nav.parentNode.scrollTop = 0;
		}
}

// Scroll element into view, based on ID named in location.hash.
function reJump(delayMsec) {
	// Markdown is special since it has no line numbers.
	// We look at localStorage for a line number, if found
	// attempt to count through the elements in the contents
	// and jump. False if no jump.
	if (jumpToMarkdownLineFromStorage())
		{
		return;
		}
	
	if (delayMsec === undefined)
		{
		delayMsec = 0;
		}
	
	let h = location.hash;
	if (h.length > 1)
		{
		// strip leading '#'
		h = h.replace(/^#/, '');
		h = decodeURIComponent(h);
		
		if (isNaN(h))
			{
			let el = getElementForHash(h);
			if (el === null)
				{
				let simplerHCopy = h.toLowerCase();
				simplerHCopy = simplerHCopy.replace(/\W/g, '');
				el = document.getElementById(simplerHCopy);
				}		
			
			if (el !== null)
				{
				el.scrollIntoView();
				resetTopNavPosition();
				if (!onMobile)
					{
					scrollIndicator();
					}
				else
					{
					scrollMobileIndicator(); // if mobile
					}
				}
			}
		else
			{
			// TEST ONLY
			//console.log("viewerStart.js#166");
			reJumpToLineNumber(h, delayMsec);
			}
		}
}

// Retrieve line number to scroll to from localStorage.
// Count up through the elements in the HTML until line number is reached,
// scroll to that element.
// Each P, H1..H6, HR counts as two lines.
//
function jumpToMarkdownLineFromStorage() {
	let markdownLineNumberKey = thePath + '?' + "markdownline";
	let markdownLineNumberStr = localStorage.getItem(markdownLineNumberKey);
	if (markdownLineNumberStr === null)
		{
		return(false);
		}
	let markdownLineNumber = Number(markdownLineNumberStr);
	++markdownLineNumber;

	// TEST ONLY
	//console.log("jumpToMarkdownLineFromStorage looking for " + markdownLineNumberStr);

	// Note sure why I was deleting the remembered line number,
	// leaving it in for now.
	//localStorage.removeItem(markdownLineNumberKey);

	const textDiv = document.getElementById("scrollTextRightOfContents");
	if (textDiv === null)
		{
		return(false);
		}
	if (typeof(textDiv.children) === 'undefined')
		{
		return(false);
		}
	
	const kids = textDiv.children;
	if (kids.length === 0)
		{
		return(false);
		}

	let preHeight = preLineHeight();
	let el = null; // the goal element
	let lineNumber = 1;
	let done = false;
	let isSubElement = false;
	let textDivOffset = textDiv.offsetTop;
	let parentElementOffset = 0;
	let elementOffset = 0;
	for (let i = 0; i < kids.length; ++i)
		{
		let kidsName = kids[i].nodeName;

		// TEST ONLY
		//console.log("NODENAME: " + kidsName + " at i " + i);

		if ( kidsName === 'P' || kidsName === 'DIV' || kidsName === 'H1'
				|| kidsName === 'H2' || kidsName === 'H3' || kidsName === 'H4'
				|| kidsName === 'H5' || kidsName === 'H6' || kidsName === 'HR'
				|| kidsName === 'CODE' )
			{
			++lineNumber;
			++lineNumber; // sic, HTML puts in a blank line with margin on bottom
			if (lineNumber >= markdownLineNumber)
				{
				el = kids[i];
				break;
				}

			const paraKids = kids[i].children;
			for (j = 0; j < paraKids.length; ++j)
				{
				let paraKidsName = paraKids[j].nodeName;
				if (paraKidsName === 'IMG')
					{
					++lineNumber;
					if (lineNumber >= markdownLineNumber)
						{
						el = kids[i];
						done = true;
						break;
						}		
					}
				}
			}
		else if (kidsName === 'TABLE')
			{
			const rows = kids[i].rows;
			if (rows.length === 0)
				{
				continue;
				}
			for (let j = 0; j < rows.length; ++j)
				{
				++lineNumber;
				if (j === 0)
					{
					++lineNumber; // for the | :---- row at top of table
					}
				if (lineNumber >= markdownLineNumber)
					{
					if (j > 1)
						{
						el = rows[j-1];
						}
					else
						{
						el = rows[j];
						}
					isSubElement = true;
					parentElementOffset = kids[i].offsetTop - textDivOffset;
					elementOffset = rows[j].offsetTop;
					//el = kids[i];
					done = true;
					break;
					}
				}
			}
		else if (kidsName === 'UL' || kidsName === 'OL')
			{
			const listItems = kids[i].children;
			if (listItems.length === 0)
				{
				continue;
				}

			//++lineNumber;
			
			for (let j = 0; j < listItems.length; ++j)
				{
				++lineNumber;
				if (lineNumber >= markdownLineNumber)
					{
					el = listItems[j];
					isSubElement = true;
					parentElementOffset = kids[i].offsetTop - textDivOffset;
					// TEST ONLY
					//console.log("j " + j);

					elementOffset = j * el.offsetHeight; // odd hack, but it works
					//el = kids[i];
					done = true;
					break;
					}
				}
			}
		else if (kidsName === 'PRE')
			{
			let preLength = kids[i].textContent.split('\n').length;
			lineNumber += preLength;
			if (lineNumber >= markdownLineNumber)
				{
				el = kids[i];
				// Another hack
				isSubElement = true;
				parentElementOffset = kids[i].offsetTop - textDivOffset;
				let lineDiff = lineNumber - markdownLineNumber;
				elementOffset = -lineDiff * preHeight; // scroll back from bottom
				done = true;
				break;
				}
			}
		else
			{
			//console.log("UNHANDLED: " + kidsName + "ca line " + lineNumber);
			++lineNumber;
			}
		
		if (done)
			{
			break;
			}
		} // for (let i = 0; i < kids.length; ++i)

	let result = false;
	if (el !== null)
		{
		// TEST ONLY
		//const elemName = el.nodeName;
		//console.log("FOUND " + elemName + " on line " + lineNumber + " vs wanted " + markdownLineNumber);
		//console.log("|" + el.innerHTML + "|");

		if (isSubElement)
			{
			// TEST ONLY
			//console.log("Scrolling to subelement.");
			//el.style.backgroundColor = "yellow";

			// TEST ONLY
			//const elemName = el.nodeName;
			//console.log(elemName + " " + parentElementOffset + " " + elementOffset);

			textDiv.scrollTo({
				top: parentElementOffset + elementOffset
				});
			}
		else
			{
			//el.style.backgroundColor = "lightblue";
			el.scrollIntoView();
			}
		
		resetTopNavPosition();
		if (!onMobile)
			{
			scrollIndicator();
			}
		else
			{
			scrollMobileIndicator(); // if mobile
			}
		result = true;
		}

	return(result);
}

function preLineHeight() {
	const preElement = document.querySelector('pre');
	const computedStyle = window.getComputedStyle(preElement);
	const lineHeight = computedStyle.lineHeight;

	let lineHeightInPixels;
	if (lineHeight.endsWith('px')) {
		lineHeightInPixels = parseFloat(lineHeight);
	} else if (lineHeight === 'normal') {
		// If line-height is "normal", you'll need to estimate based on the font-size
		const fontSize = parseFloat(computedStyle.fontSize);
		lineHeightInPixels = fontSize * 1.2; // common default for "normal" line-height
	} else {
		// For other units like 'em', you'll need to convert to pixels
		const fontSize = parseFloat(computedStyle.fontSize);
		if (lineHeight.endsWith('em')) {
			lineHeightInPixels = parseFloat(lineHeight) * fontSize;
		} else {
			// handle other units as needed
			lineHeightInPixels = 17; // Set to null or handle appropriately
		}
	}

	//console.log("PRE height: " + lineHeightInPixels); // Typ. around 17
	return (lineHeightInPixels);
}

// Progressively shorten 'h' word by word as necessary until an anchor id is found. If the
// remaining part of 'h' is a number, though, jump to that line. If an anchor id is found,
// return the corresponding element in the html text.
//
// This "shortening" approach is needed because 'h' may be too long, if it was part of a link
// in a text file where the link was not quoted: when making the link, we didn't know where
// the hash stopped, and just grabbed a hundred or so characters after the '#'.
// [See intramine_file_viewer_cm.pl#RememberTextOrImageFileMention().]
function getElementForHash(h) {
	let hCopy = h;
	hCopy = hCopy.replace(/ /g, '_');
	hCopy = hCopy.replace(/\%20/g, '_');
	hCopy = hCopy.replace(/\(\)$/, '');
	let el = document.getElementById(hCopy);
	if (el === null)
		{
		let simplerHCopy = h.toLowerCase();
		simplerHCopy = simplerHCopy.replace(/\W/g, '');
		el = document.getElementById(simplerHCopy);
		}
	
	while(el === null && h.length > 0)
		{
		let lastIndexOfSpace = h.lastIndexOf(" ");
		let lastIndexOfPct = h.lastIndexOf("%");
		let trimIndex = (lastIndexOfSpace > lastIndexOfPct) ? lastIndexOfSpace: lastIndexOfPct;
		if (trimIndex > 0)
			{
			h = h.substring(0, trimIndex);
			let hCopy = h;
			hCopy = hCopy.replace(/ /g, '_');
			hCopy = hCopy.replace(/\%20/g, '_');
			el = document.getElementById(hCopy);
			if (el === null)
				{
				if (!isNaN(hCopy))
					{
					// TEST ONLY
					//console.log("viewerStart.js#449");
					reJumpToLineNumber(hCopy);
					break;
					}
				}
			}
		else
			{
			break;
			}
		}
	
	return(el);
}

// Scroll a line into view, based on line number. Synch the TOC too.
async function reJumpToLineNumber(h, delayMsec) {
	if (delayMsec === undefined)
		{
		delayMsec = 0;
		}

	let lineNum = parseInt(h, 10);
	///let lineNum = parseInt(h, 10) - 1;
	if (lineNum < 0)
		{
		lineNum = 0;
		}
	
	// Try for class "imt" tables first (found in .txt files),
	// if not found look for rows in all tables.
	let rows;
	let isText = hasTextExtension();
	if (isText)
		{
		const rowNodes = document.querySelectorAll(`table.${'imt'} tr`);
		rows = Array.from(rowNodes);
		}
	else
		{
		rows = markerMainElement.getElementsByTagName('tr');
		}	

	if (lineNum >= rows.length)
		{
		lineNum = rows.length - 1;
		}

	// TEST ONLY
	//console.log("Looking for line number |" + lineNum + "|");
	
	if (lineNum >= 0)
		{
		let el = rows[lineNum];
		if (el === null)
			{
			// Currently the Editor saves and shows blank lines at the bottom
			// but some Viewers suppress them. Back up the lineNum until
			// we hit an actual existing row. This probably isn't needed
			// thanks to the limit on lineNum above, but I've left it in.
			let revCounter = 0;
			while (el === null && ++revCounter <= 100 && --lineNum >= 0)
				{
				el = rows[lineNum];
				if (el !== null)
					{
					break;
					}
				}
			}
		
		if (lineNum < 0)
			{
			lineNum = 0;
			}
		
		if (el !== null)
			{
			// If inline HTML is present, then we have gone too far, need to back
			// up to the row with id 'RNNN' where NNN is the wanted line number.
			if (isText && el.hasAttribute('id') && lineNum > 0)
				{
				let rowNum = lineNum;
				let rowID = el.id;
				let rowLineStr = rowID.substring(1);
				let rowLineNumber = parseInt(rowLineStr, 10);

				// TEST ONLY
				//console.log("Line number for that row is |" + rowLineNumber + "|");

				while (rowLineNumber > lineNum && rowNum > 0)
					{
					--rowNum;
					el = rows[rowNum];
					if (el.hasAttribute('id'))
						{
						rowID = el.id;
						rowLineStr = rowID.substring(1);
						rowLineNumber = parseInt(rowLineStr, 10);
						// TEST ONLY
						//console.log("rowline " + rowLineNumber + " seen on row " + rowNum);
						}
					else
						{
						// TEST ONLY
						//console.log("No line id for row |" + rowNum + "|");
						}
					}
				}

			if (delayMsec > 0)
				{
				await delay(delayMsec);
				}

			el.scrollIntoView(true);
			resetTopNavPosition();
			if (!onMobile)
				{
				scrollIndicator();
				}
			else
				{
				scrollMobileIndicator(); // if mobile
				}
			}

		// Restore Table of Contents scrolled position and highlight.
		restoreTocSelection(lineNum);
		}
}

function hasTextExtension() {
	let result = false;
	let extPos = theEncodedPath.lastIndexOf(".");
	if (extPos > 1)
		{
		let ext = theEncodedPath.slice(extPos + 1);
		if (ext === "txt" || ext === "TXT")
			{
			result = true;
			}
		else
			{
			if (typeof weAreStandalone !== 'undefined')
				{
				if (weAreStandalone)
					{
					result = true; // hack, pretend we are .txt in the Viewer
					}
				}
			}
		}
	
	return(result);
}

// Just for Markdown files, go straight to an id.
function mdJump(tocid, lineNum) {
	location.hash = '#' + tocid;
}

// Adust the top of "id" (the main text holder) so scrolling will work properly etc.
function setTextViewPosition(rule_id, id) {
	let el = document.getElementById(id);
	if (el === null)
		{
		return;
		}
	let rule = document.getElementById(rule_id);
	let pos = getPosition(rule);
	let rect = rule.getBoundingClientRect();
	let ruleHeight = rect.height;
	let yPos = pos.y + ruleHeight + 8;
	el.style.top = yPos + "px";
}

// Position the main text-holding element.
function positionViewItems() {
	let viewElement = document.getElementById(cmTextHolderName);
	if (viewElement !== null)
		{
		setTextViewPosition("rule_above_editor", cmTextHolderName);
		}
	else
		{
		viewElement = document.getElementById(specialTextHolderName);
		if (viewElement !== null)
			{
			setTextViewPosition("rule_above_editor", specialTextHolderName);
			}
		}
	doResize();
}

function finishStartup() {
	if (thePath.match(/\.(txt|log|bat)$/))
		{
		// use lolight highlighting
		putInLolightElements();
		}

	hideIt("search-button");
	hideIt("small-tip");
	positionViewItems();
	loadCommonestEnglishWords(); // See commonEnglishWords.js.
	setImagesButtonText();
	
	// TEST ONLY
	//console.log("finishStartup");
	reJump();
}

// Code block highlighting with lolight, used
// by intramine_viewer.pl and gloss2html.pl.
function putInLolightElements() {
	document.querySelectorAll('td').forEach((el) => {
		putInLolightPreAndClass(el);
	});
}

function putInLolightPreAndClass(el) {
	let text = el.innerHTML;
	let codeMarkerPosition = text.indexOf('_STARTCB_');
	if (codeMarkerPosition == 0)
		{
		// FL = First/Last line of a code block. These are
		// shrunk down, emptied out, and colored gray.
		// Other rows starting with 'STARTCB_' are given
		// a class of 'lolight', and lolight JS styles
		// them up when the document is ready.
		if (text.indexOf('_STARTCB_FL_') == 0)
			{
			el.innerHTML = '';
			el.parentNode.classList.add("reallyshrunkrow");
			el.parentNode.firstElementChild.removeAttribute("n");
			el.style.backgroundColor = "#d0d0d0";
			}
		else
			{
			text = text.substring(9);
			el.innerHTML = '<pre class="lolight">' + text + '</pre>';
			el.style.backgroundColor = "#f3f3f3";
			}
		}
}

function createElementFromHTML(htmlString) {
	let div = document.createElement('div');
	div.innerHTML = htmlString.trim();

	// Change this to div.childNodes to support multiple top-level nodes
	return div.firstChild; // or div.firstElementChild?
}

function hideIt(id) {
	let el = document.getElementById(id);
	if (el !== null)
		{
		el.style.display = 'none';
		}
}

// Set up for highlighting text, with marks in scrollbar, keeping user's selection
// or expanding it to a word. mark.js (mark.min.js) does the actual marking.
// Marks are used for both the initial highlight items and a user text selection.
let markerInstance = null;
let mouseEvt;

let textMarkerClass = "marker-highlight";
let scrollMarkerClass = "scroll-hilite";
let initialHitsTextMarkersClass = "initial-hits-highlight";
let initialHitsScrollMarkerClass = "initial-scroll-hl";
let toggleHitsButtonID = "sihits";
let initialSearchHitsAreShowing = false;
let currentTextForHighlighting = '';
let justUpdateScrollbar = false;


// Selection management: on a single click, expand to a word. If selection is on one row,
// the <td> holding it is removed before marking, and then restored, complete with selection.
// Done because marking the current selection will collapse it to an insertion point.
let theSelection = {};
theSelection.selectionIsTooBig = false;
theSelection.isDoubleClick = false;
theSelection.doingDoubleClick = false;
theSelection.userDragged = false;
//For LightRange.min.js range representing text selection.
theSelection.ltRange = null;
theSelection.currentSelectionElem = null; // Hide/show this element when marking
theSelection.currentSelPreviousSibling = null; // The target for re-insertion of currentSelectionElem
theSelection.selChildren = []; // Contents of TD containing current selection
theSelection.startNodeIndexes = [];
theSelection.startNodeOffset = 0;
theSelection.endNodeIndexes = [];
theSelection.endNodeOffset = 0;
theSelection.topStartNode = null;
theSelection.topEndNode = null;

let linkClicked = false;
let hintboxClicked = false;
let cmCursorPos = {
	line : -1,
	ch : -1
};

// mark.js mark/unmark options, "done" is fired at the end of the mark/unmark. Normally
// one calls unmark, with unmarkOptions "done" calling the mark function.
let markerOptions = {
	// "element": "span",
	"className" : textMarkerClass,
	"separateWordSearch" : false,
	"acrossElements" : true,
	"done" : function(counter) {
		markHitsInScrollbar(textMarkerClass, scrollMarkerClass);
	}
};
let markerOptionsInitialHits = {
	// "element": "span",
	"className" : initialHitsTextMarkersClass,
	"separateWordSearch" : false,
	"acrossElements" : true,
	"done" : function(counter) {
		markHitsInScrollbar(initialHitsTextMarkersClass, initialHitsScrollMarkerClass);
	}
};

let unmarkOptions = {
	// "element": "span",
	"className" : textMarkerClass,
	"done" : function() {
		removeAllScrollbarHighlights(scrollMarkerClass);
		markCurrentSelection();
	}
};
let unmarkOptionsInitialHits = {
	// "element": "span",
	"className" : initialHitsTextMarkersClass,
	"done" : function() {
		removeAllScrollbarHighlights(initialHitsScrollMarkerClass);
	}
};

if (markerMainElement !== null)
	{
	markerInstance = new Mark(markerMainElement);
	}

// After a click, update markers in text and scroll corresponding TOC element into view.
function delayedUpdateMarkersAndTOC(evt) {
	let doubleClickDelay = doubleClickTime + 100; // milliseconds
	setTimeout(function() {
		updateMarkers(evt);
	}, doubleClickDelay);
	
	scrollTocEntryIntoView(evt, false);
}

// Highlight user's selection, unless it was a click on a link or in the scrollbar, or the
// first click in a double-click, or there's too much text selected to be worth higlighting.
function updateMarkers(evt) {
	if (linkClicked)
		{
		return;
		}
	if (theSelection.isDoubleClick)
		{
		theSelection.isDoubleClick = false;
		theSelection.doingDoubleClick = true;
		return;
		}
	if (markerMainElement === null || evtIsInScrollbar(evt))
		{
		return;
		}

	// No marking if selection is "too big" (spreads over more than one line).
	theSelection.selectionIsTooBig = selectionIsTooBig();
	
	if (!justUpdateScrollbar && currentSelectionTouchesLink())
		{
		theSelection.doingDoubleClick = false;
		return;
		}

	mouseEvt = evt;
	
	theSelection.userDragged = false;

	// full highlight, selection, and scrollbar marking
	if (!justUpdateScrollbar && !theSelection.selectionIsTooBig) 
		{
		storeSelection();
		// Get current text to highlight, or set theSelection.selectionTooBig = true.
		// Also set current text to "" if it's fewer than three characters, meaning remove
		// all markers and don't mark anything new or change the selection (this is a way to
		// clear markers).
		currentTextForHighlighting = getCurrentTextForMarkup();
		
		hideSelectionRow(); // Don't mark up row where text is selected
		
		markerInstance.unmark(unmarkOptions);
		}
	else if (justUpdateScrollbar)
		{
		removeAllScrollbarHighlights(scrollMarkerClass);
		markHitsInScrollbar(textMarkerClass, scrollMarkerClass);
		}

	// EXPERIMENT, try showing hint for Go to definition.
	if (!theSelection.selectionIsTooBig)
		{
		let text = window.getSelection().toString();
		showDefinitionHint(text, evt);
		}

	theSelection.doingDoubleClick = false;
	justUpdateScrollbar = false;
}

//See intramine_viewer.pl#InitialHighlightItems().
function highlightInitialItems() {
	if (markerMainElement !== null && highlightItems.length > 0)
		{
		for (let i = 0; i < highlightItems.length; ++i)
			{
			markerInstance.mark(highlightItems[i], markerOptionsInitialHits);
			}
		initialSearchHitsAreShowing = true;
		let toggleButton = document.getElementById(toggleHitsButtonID);
		if (toggleButton !== null)
			{
			toggleButton.value = "Hide Initial Hits";
			}
		}
}

function removeInitialHighlights() {
	if (markerMainElement !== null && highlightItems.length > 0)
		{
		for (let i = 0; i < highlightItems.length; ++i)
			{
			markerInstance.unmark(unmarkOptionsInitialHits);
			}
		initialSearchHitsAreShowing = false;
		let toggleButton = document.getElementById(toggleHitsButtonID);
		if (toggleButton !== null)
			{
			toggleButton.value = "Show Initial Hits";
			}
		}
}

function toggleInitialSearchHits() {
	if (initialSearchHitsAreShowing)
		{
		removeInitialHighlights();
		}
	else
		{
		highlightInitialItems();
		}
}

function noteWasDoubleClick(evt) {
	//let nons = '';
	theSelection.isDoubleClick = true;
}

function updateScrollbarMarkers() {
	justUpdateScrollbar = true;
	updateMarkers(null);
}

// This is called by mark.js after an unmark, see unmarkOptions above.
function markCurrentSelection() {

	if (currentTextForHighlighting !== "")
		{
		markerInstance.mark(currentTextForHighlighting, markerOptions);
		}
	
	showSelectionRow(); // Restore visibiliy of element containing current user selecton.
	
	showStoredSelections();

	theSelection.userDragged = false;
}

function getCurrentTextForMarkup() {
	let result = getSelectionText();

	return (result);
}

// Get text for marking, unless it's too big to be worth marking. This is a bit of a gamble,
// but a "too big" selection usually means the user is just intending to copy some text,
// not see other instances of it in the same file.
function getSelectionText() {
	let text = "";
	
	theSelection.userDragged = false;
	
	if (window.getSelection && !theSelection.doingDoubleClick)
		{
		let currSelection = window.getSelection();
		if (!theSelection.selectionTooBig)
			{
			text = currSelection.toString();
			if (text !== '')
				{
				theSelection.userDragged = true;
				}
			}
		else
			{
			theSelection.userDragged = true;
			}
		}

	
	if (!theSelection.selectionTooBig && !theSelection.userDragged)
		{
		// Empty selection: expand to nearest word.
		if (text === '')
			{
			//text = expandSelectionToWordIfPossible();
			let wordObj = expandSelectionToWordIfPossible();
			text = wordObj.theWord;
			if (typeof text === 'undefined')
				{
				text = '';
				}
			if (text !== '')
				{
				let beginOffset = wordObj.theBegin;
				let endOffset = wordObj.theEnd;
				// Re-capture the selection for later restoration.
				if (typeof theSelection.ltRange !== 'undefined')
					{
					try  {
						let startContainer = theSelection.ltRange.startContainer;
						theSelection.ltRange.setStart(startContainer, beginOffset);
						theSelection.ltRange.setEnd(startContainer, endOffset);
						}
					catch(e) {
						; // not much we can do.
						}
					}
				}
			}
		}

	// Avoid highlighting just one or two characters. Or a common English word (top 100);
	if (text.length <= 2 || (text.length > 2 && isCommonEnglishWord(text)))
		{
		text = "";
		}

	return text;
}


// "Too big" means selected text spreads across two or more lines.
// Or we're in a CODE block and more than a word is selected.
function selectionIsTooBig() {
	let selectionTooBig = false;
	let withinPRE = false;
	let currSelection = window.getSelection();
	let rangeCount = currSelection.rangeCount;
	if (rangeCount > 0)
		{
		let currRange = currSelection.getRangeAt(0);
		let commonA = currRange.commonAncestorContainer;
		let tdElem = commonA;
		
		while (tdElem !== null && tdElem.nodeName !== "TD")
			{
			if (tdElem.nodeName === "PRE")
				{
				withinPRE = true;
				}
			tdElem = tdElem.parentNode;
			}
		if (tdElem === null)
			{
			selectionTooBig = true;
			}
		else
			{
			if (withinPRE)
				{
				let text = window.getSelection().toString();
				if (containsMoreThanOneWord(text))
					{
					selectionTooBig = true;
					}
				}
			}
		}

	return (selectionTooBig);
}

function containsMoreThanOneWord(text) {
	let result = false;
	let nonWordHitPosition = text.search(/\W/);
	if (nonWordHitPosition >= 0) // more than just a word is there
		{
		result = true;
		}

	return(result);
}

function currentSelectionTouchesLink() {
	let result = false;
	let currSelection = window.getSelection();
	let rangeCount = currSelection.rangeCount;
	if (rangeCount > 0)
		{
		let currRange = currSelection.getRangeAt(0);
		let nodes = getNodesInRange(currRange);
		for (let i = 0; i < nodes.length; ++i)
			{
			if (nodes[i].nodeName === "A")
				{
				result = true;
				break;
				}
			}
		}
	
	return(result);
}

function getNextNode(node) {
    if (node.firstChild)
        return node.firstChild;
    while (node)
    {
        if (node.nextSibling)
            return node.nextSibling;
        node = node.parentNode;
    }
}

function getNodesInRange(range) {
    var start = range.startContainer;
    var end = range.endContainer;
    var commonAncestor = range.commonAncestorContainer;
    var nodes = [];
    var node;

    // Walk parent nodes from start to common ancestor.
    for (node = start.parentNode; node; node = node.parentNode)
    {
        nodes.push(node);
        if (node == commonAncestor)
            break;
    }
    nodes.reverse();

    // Walk children and siblings from start until end is found.
    for (node = start; node; node = getNextNode(node))
    {
        nodes.push(node);
        if (node == end)
            break;
    }

    return nodes;
}

function expandSelectionToWordIfPossible() {
	return (getFullWord(mouseEvt)); // see wordAtInsertionPt.js

}

// Add handlers for marker updating etc.
if (markerMainElement !== null)
	{
	markerMainElement.addEventListener("click", delayedUpdateMarkersAndTOC);
	markerMainElement.addEventListener("dblclick", noteWasDoubleClick);
	window.addEventListener("resize", updateScrollbarMarkers);

	markerMainElement.addEventListener("mouseup", resetTopNavPosition);
	if (tocMainElement !== null)
		{
		tocMainElement.addEventListener("mouseup", resetTopNavPosition);
		}
	}

// Show/hide highlight markers on scroll bar.

function removeAllScrollbarHighlights(mClass) {
	removeElementsByClass(mClass);
}

function removeElementsByClass(className) {
	let elements = document.getElementsByClassName(className);
	while (elements.length > 0)
		{
		elements[0].parentNode.removeChild(elements[0]);
		}
}

// Put little rectangles in the scrollbar region, placed vertically in proportion to
// where the selected text occurrences happen in the document.
function markHitsInScrollbar(textClassName, scrollHitClassName) {	
	let rect = markerMainElement.getBoundingClientRect();
	let yTop = rect.top;
	let yBottom = rect.bottom;
	let textViewableHeight = yBottom - yTop;
	// Fine-tuning: gray area of scrollbar is shortened by the up and down arrows, and starts
	// after the top arrow. There are no arrows on an iPad.
	let mainScrollY = markerMainElement.scrollTop;
	let mainScrolllHeight = markerMainElement.scrollHeight;
	// let usableTextHeight = textViewableHeight - 2*arrowHeight;

	let viewWidth = rect.right - rect.left;
	let widthDifference = viewWidth - markerMainElement.clientWidth;
	let heightDifference = textViewableHeight - markerMainElement.clientHeight;
	let haveVerticalScroll = (widthDifference > 2) ? true : false;
	let haveHorizontalScroll = (heightDifference > 2) ? true : false;

	let arrowHeight = 18;
	let arrowMultiplier = 2;
	if (typeof window.ontouchstart !== 'undefined')
		{
		arrowHeight = 2;
		}
	else
		{
		if (haveVerticalScroll)
			{
			if (widthDifference > 6.0 && widthDifference < 30.0)
				{
				//arrowHeight = Math.round(widthDifference) + 1;
				arrowHeight = widthDifference;
				}
			if (haveHorizontalScroll)
				{
				arrowMultiplier = 3;
				}
			}
		else
			{
			arrowHeight = 0;
			}
		}
	
	let usableTextHeight = textViewableHeight - arrowMultiplier * arrowHeight;
	
	let elements = document.getElementsByClassName(textClassName);
	for (let i = 0; i < elements.length; ++i)
		{
		let hitElement = elements[i];
		let elementBoundRect = hitElement.getBoundingClientRect();
		let textHitY = elementBoundRect.top;
		let positionInDoc = mainScrollY + textHitY - yTop;
		let positionRatio = positionInDoc / mainScrolllHeight;
		let relativeMarkerPos = positionRatio * usableTextHeight;
		let absMarkerPos = relativeMarkerPos + yTop + arrowHeight;

		let mk = document.createElement("mark");
		mk.setAttribute("class", scrollHitClassName);
		mk.style.top = absMarkerPos + "px";
		markerMainElement.appendChild(mk);
		}
}

function evtIsInScrollbar(evt) {
	let result = false;
	if (evt !== null)
		{
		if (evt.offsetX >= markerMainElement.clientWidth
				|| evt.offsetY >= markerMainElement.clientHeight)
			{
			// Mouse down over scroll element
			result = true;
			}
		}
	return (result);
}

// Remember the element that starts the selection.
function storeSelection() {
	theSelection.ltRange = lightrange.saveSelection();
}

// Look at siblings of startElement, advance until element does not contain a <mark> subelement.
function showStoredSelections() {
	lightrange.restoreSelection(theSelection.ltRange);
}

function saveSelection() {
	if (window.getSelection) {
	    var sel = window.getSelection();
	    if (sel.getRangeAt && sel.rangeCount) {
	        return sel.getRangeAt(0);
	    }
	} else if (document.selection && document.selection.createRange) {
	    return document.selection.createRange();
	}
return null;
}

// Set theSelection.currentSelectionElem to TD holding selection, 
// and clone and remove the TD - only if not "too big".
function hideSelectionRow() {
	theSelection.currentSelectionElem = null;
	theSelection.currentSelPreviousSibling = null;
	if (theSelection.selectionIsTooBig)
		{
		return;
		}

	let currSelection = window.getSelection();
	let rangeCount = currSelection.rangeCount;
	if (rangeCount > 0)
		{
		let currRange = currSelection.getRangeAt(0);
		let commonA = currRange.commonAncestorContainer;
		let tdElem = commonA;
		
		while (tdElem !== null && tdElem.nodeName !== "TD")
			{
			tdElem = tdElem.parentNode;
			}
		if (tdElem === null)
			{
			selectionTooBig = true;
			}
		else
			{
			theSelection.currentSelectionElem = tdElem;
			theSelection.currentSelPreviousSibling = theSelection.currentSelectionElem.previousSibling;
			}
		}

	if (theSelection.currentSelectionElem !== null)
		{
		let currSelTD = theSelection.currentSelectionElem;
		let i = 0;
		theSelection.selChildren = [];
		
		findRangeTopContainers();
		
		let tdChildNodes = currSelTD.childNodes;
		for  (let j = 0; j < tdChildNodes.length; ++j)
			{
			
			if (tdChildNodes[j] === theSelection.topStartNode)
				{
				recordStartSelIndexes(j, tdChildNodes[j]);
				}

			if (tdChildNodes[j] === theSelection.topEndNode)
				{
				recordEndSelIndexes(j, tdChildNodes[j]);
				}
			}
		
		
		while (theSelection.currentSelectionElem.firstChild)
			{
			theSelection.selChildren[i++] = theSelection.currentSelectionElem.firstChild.cloneNode(true);
			theSelection.currentSelectionElem.removeChild(theSelection.currentSelectionElem.firstChild);
			}
		}
	}

function findRangeTopContainers() {
	let topStartNode = theSelection.ltRange.startContainer;
	while (topStartNode !== null && topStartNode.parentNode !== null && topStartNode.parentNode.nodeName !== "TD")
		{
		topStartNode = topStartNode.parentNode;
		}
	
	let topEndNode = theSelection.ltRange.endContainer;
	while (topEndNode !== null && topEndNode.parentNode !== null && topEndNode.parentNode.nodeName !== "TD")
		{
		topEndNode = topEndNode.parentNode;
		}
	
	theSelection.topStartNode = topStartNode;
	theSelection.topEndNode = topEndNode;
}

function recordStartSelIndexes(topIdx, topNode) {
	theSelection.startNodeIndexes = [];
	let topStartNode = theSelection.ltRange.startContainer;
	
	while (topStartNode !== null && topStartNode !== topNode
			&& topStartNode.parentNode.nodeName !== "TD")
		{
		// Figure out where we are in list of parent's children
		let parentNode = topStartNode.parentNode;
		let kids = parentNode.childNodes;
		for (let i = 0; i < kids.length; ++i)
			{
			if (kids[i] === topStartNode)
				{
				theSelection.startNodeIndexes.unshift(i);
				}
			}
		topStartNode = topStartNode.parentNode;
		}
	theSelection.startNodeIndexes.unshift(topIdx);
	theSelection.startNodeOffset = theSelection.ltRange.startOffset;
}

function recordEndSelIndexes(topIdx, topNode) {
	theSelection.endNodeIndexes = [];
	let topStartNode = theSelection.ltRange.startContainer;
	
	while (topStartNode !== null && topStartNode !== topNode
			&& topStartNode.parentNode.nodeName !== "TD")
		{
		// Figure out where we are in list of parent's children
		let parentNode = topStartNode.parentNode;
		let kids = parentNode.childNodes;
		for (let i = 0; i < kids.length; ++i)
			{
			if (kids[i] === topStartNode)
				{
				theSelection.endNodeIndexes.unshift(i);
				}
			}
		topStartNode = topStartNode.parentNode;
		}
	theSelection.endNodeIndexes.unshift(topIdx);
	theSelection.endNodeOffset = theSelection.ltRange.endOffset;
}

// Restore display of any TD element holding the current selection.
function showSelectionRow() {
	if (theSelection.currentSelectionElem !== null && theSelection.selChildren.length)
		{
		for (let i = 0; i < theSelection.selChildren.length; ++i)
			{
			theSelection.currentSelectionElem.appendChild(theSelection.selChildren[i]);
			
			
			if (i === theSelection.startNodeIdx)
				{
				let node = theSelection.currentSelectionElem.lastChild;
				theSelection.ltRange.setStart(node, theSelection.startNodeOffset);
				}
			if (i === theSelection.endNodeIdx)
				{
				let node = theSelection.currentSelectionElem.lastChild;
				theSelection.ltRange.setEnd(node, theSelection.endNodeOffset);
				}
			}
		
		restoreRangeStartsAndEnds();
		}
}

function restoreRangeStartsAndEnds() {
	let topNode = theSelection.currentSelectionElem;
	
	let drillDownNode = topNode;

	if (typeof drillDownNode === 'undefined')
		{
		return;
		}

	for (let i = 0; i < theSelection.startNodeIndexes.length; ++i)
		{
		drillDownNode = drillDownNode.childNodes[theSelection.startNodeIndexes[i]];
		}
	theSelection.ltRange.setStart(drillDownNode, theSelection.startNodeOffset);
	
	drillDownNode = topNode;
	for (let i = 0; i < theSelection.endNodeIndexes.length; ++i)
		{
		drillDownNode = drillDownNode.childNodes[theSelection.endNodeIndexes[i]];
		}
	theSelection.ltRange.setEnd(drillDownNode, theSelection.endNodeOffset);
}

// Skip along through childNodes until we hit a MARK and accumulated offset is
// >= targetOffset.
// Returns MARK node or null in [0], accumulated textLength in [1].
function markToSelect(node, textLength, targetOffset, markerNode) {
	if (markerNode !== null)
		{
		return ([ markerNode, textLength ]);
		}
	let lengthSoFar = textLength;
	let tagName = node.nodeName;
	if (tagName === "MARK")
		{
		let markLength = node.textContent.length;
		if (lengthSoFar + markLength >= targetOffset)
			{
			return ([ node, lengthSoFar + markLength ]);
			}
		}

	// Still here, go deeper.
	let numChildren = node.childNodes.length;
	if (numChildren == 0)
		{
		lengthSoFar += node.textContent.length;
		}
	else
		{
		for (let i = 0; i < node.childNodes.length; ++i)
			{
			let markNodeToSelectArray =
					markToSelect(node.childNodes[i], lengthSoFar, targetOffset, markerNode);
			lengthSoFar = markNodeToSelectArray[1];
			if (markNodeToSelectArray[0] !== null)
				{
				markerNode = markNodeToSelectArray[0];
				break;
				}
			}
		}

	return ([ markerNode, lengthSoFar ]);
}

// Link clicked means don't update markers for user's text selection.
function notelinkClicked(evt) {
	if (hintboxClicked)
		{
		hintboxClicked = false;
		return;
		}
	linkClicked = false;

	let target = evt.target || null;
	// Click might be on an "edit" pencil (edit1.png), move up to parent.
	if (target !== null && target.nodeName === "IMG")
		{
		target = target.parentNode;
		}
	if (target !== null && target.nodeName === "A")
		{
		linkClicked = true;
		}
	else
		{
		if (typeof target.id !== 'undefined')
			{
			if (target.id === "hintbox")
				{
				linkClicked = true;
				}
			}
		}
}

// The "hint" box shows a possibly reduced view of an image in text views. On an iPad,
// it's clickable. If clicked, we treat it as a click on a link and don't change the
// marked text.
function noteHintboxClicked() {
	hintboxClicked = true;
	linkClicked = true;
}

// Match braces, for Perl only.
const braceElements = [];
const braceSearchLinesMax = 1000;

function matchBraces() {
	removeBraceHighlights();

	let dir = 0;
	let withinPRE = false;
	let currSelection = window.getSelection();
	let rangeCount = currSelection.rangeCount;
	if (rangeCount === 1)
		{
		let currRange = currSelection.getRangeAt(0);
		let commonA = currRange.commonAncestorContainer;
		let tdElem = commonA;
			
		while (tdElem !== null && tdElem.nodeName !== "TD")
			{
			if (tdElem.nodeName === "PRE")
				{
				withinPRE = true;
				// PRE is not currently handled.
				return;
				}
			tdElem = tdElem.parentNode;
			}
		
		if (tdElem !== null)
			{
			let tdChildren = tdElem.children;
			for (let i = 0; i < tdChildren.length; ++i)
				{
				if (tdChildren[i].nodeName === "SPAN")
					{
					let classes = tdChildren[i].className;
					if (classes.indexOf('Symbol') >= 0 && classes.indexOf('b-') >= 0)
						{
						// Contains curly brace { or }
						let brace = tdChildren[i].textContent; // or innerHTML?
						if (brace === '{')
							{
							dir = 1;
							}
						else if (brace === '}')
							{
							dir = 2;
							}
						// else serious error somewhere
						// Remember and highlight the span.
						addClass(tdChildren[i], 'brace-highlight');
						// Put color on the TD for line number.
						addClass(tdElem.previousSibling, 'brace-line-highlight');
						braceElements.push(tdElem);

						// Now find, remember, and highlight the other end.
						let braceClassMatches = classes.match(/(b-\d+)/i);
						if (braceClassMatches !== null)
							{
							let braceClass = braceClassMatches[1];
							// TEST ONLY
							//console.log("Brace class: " + braceClass);
							doOtherBrace(tdElem, dir, braceClass);
							}
						break;
						}
					}
				}
			}
		}
	
		if (dir > 0)
			{
			;//console.log("braceSeen: " + braceSeen);
			}
		
		return(dir);
	}

function removeBraceHighlights() {
	while (braceElements.length > 0)
		{
		let tdElem = braceElements.pop();
		removeClass(tdElem.previousSibling, 'brace-line-highlight');
		let tdChildren = tdElem.children;
		for (let i = 0; i < tdChildren.length; ++i)
			{
			removeClass(tdChildren[i], 'brace-highlight');
			}
		}
}

// dir: 1 == down/forward, 2 == back/upwards
function doOtherBrace(firstTD, dir, braceClass) {
	let parent = firstTD.parentElement;
	if (parent === null)
		{
		return;
		}

	let prevTR = parent;
	let foundIt = false;
	let counter = 0;
	while (prevTR !== null && !foundIt)
		{
		if (prevTR.firstChild !== null)
			{
			let tdElem = prevTR.firstChild.nextSibling;
			if (tdElem !== null)
				{
				let tdChildren = tdElem.children;
				for (let i = 0; i < tdChildren.length; ++i)
					{
					if (tdChildren[i].nodeName === "SPAN")
						{
						let classes = tdChildren[i].className;
						if (classes.indexOf('Symbol') >= 0 && classes.indexOf(braceClass) >= 0)
							{
							if (counter > 0 || classes.indexOf('brace-highlight') < 0)
								{
								addClass(tdChildren[i], 'brace-highlight');
								// Put color on the TD for line number.
								addClass(tdElem.previousSibling, 'brace-line-highlight');
								braceElements.push(tdElem);
								foundIt = true;
								break;
								}
							}
						}
					}
				// No good, with too many line numbers colored, removal is glitchy.
				//addClass(tdElem.previousSibling, 'brace-line-highlight');
				braceElements.push(tdElem);
				}
			else
				{
				break;
				}
			if (++counter >= braceSearchLinesMax)
				{
				removeBraceHighlights();
				break;
				}

			}
		prevTR = (dir === 1) ? prevTR.nextSibling : prevTR.previousSibling;
		}
}

let addHintTimer; // onMobile, to keep trying addHintboxListener() until it succeeds.

function addHintboxListener() {
	let tooltipElement = document.getElementById("hintbox");
	if (tooltipElement !== null)
		{
		tooltipElement.addEventListener("touchstart", noteHintboxClicked);
		clearInterval(addHintTimer);
		}
}

// Jump from footnote/citation reference to the note,
// remembering the line number we came from.
function scrollToFootnote(newIndexId, refLineNumber) {
	let noteElement = document.getElementById(newIndexId);
	if (noteElement !== null)
		{
		localStorage.setItem(thePath + '?' + 'noteRefLine' , refLineNumber);
		noteElement.scrollIntoView();
		}
}

// Scroll (jump) from footnote back to the reference that triggered
// the jump. If none, pot luck.
function scrollBackToFootnoteRef(ourAnchor) {
	let refLine = localStorage.getItem(thePath + '?' + 'noteRefLine');
	if (refLine !== null)
		{
		reJumpToLineNumber(refLine, 0);
		}
	// else try for the first reference
	else
		{
		let id = ourAnchor.href;
		if (id !== null)
			{
			let idProperPos = id.indexOf('fnref');
			if (idProperPos >= 0)
				{
				let firstrefId = id.substring(idProperPos + 5);
				firstrefId = 'fnref' + firstrefId;
				let firstRef = document.getElementById(firstrefId);
				if (firstRef !== null)
					{
					firstRef.scrollIntoView();
					}
				}
			}
		}
}

if (onMobile)
	{
	addHintTimer = setInterval(addHintboxListener, 200);
	}

document.addEventListener("mousedown", notelinkClicked);

if (thePath.match(/\.(pl|pm|cgi|t)$/i))
	{
	document.addEventListener("mouseup", matchBraces);
	}

ready(finishStartup);
