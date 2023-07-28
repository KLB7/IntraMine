// viewerStart.js: used for non-CodeMirror views in intramine_viewer.pl.
// Manage layout changes on resize, jump to an anchor
// Put highlight hits in text and on scrollbar.
// Show/hide any initial search hits provided in highlightitems.
// Preserve user selection when marking, by remembering selection range, removing selected
// text before marking, then restoring text and selection range after marking (patent not pending).

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
	
	updateToggleBigMoveLimit();
}

// On "load", scroll any location.hash position into view, and put highlights on any
// words that formed part of a search that produced this file as a hit.
// See intramine_viewer.pl#InitialHighlightItems().
function reJumpAndHighlight() {
	addDragger && addDragger(); // dragTOC.js#addDragger()
	reJump();
	updateToggleBigMoveLimit();
	updateTogglePositions();
	highlightInitialItems();
	addAutoLinks();
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
function reJump() {
	let h = location.hash;
	if (h.length > 1)
		{
		// strip leading '#'
		h = h.replace(/^#/, '');
		
		if (isNaN(h))
			{
			let el = getElementForHash(h);
			
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
			reJumpToLineNumber(h);
			}
		}
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
function reJumpToLineNumber(h) {
	let lineNum = parseInt(h, 10) - 1;
	if (lineNum <= 0)
		{
		lineNum = 0;
		}
	// Look for row number lineNum.
	let rows = markerMainElement.getElementsByTagName('tr');
	if (lineNum < rows.length)
		{
		let el = rows[lineNum];
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

		// Restore Table of Contents scrolled position and highlight.
		restoreTocSelection(lineNum);
		}
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
	if (thePath.match(/\.txt$/))
		{
		// use lolight highlighting
		putInLolightElements();
		}

	hideIt("search-button");
	hideIt("small-tip");
	positionViewItems();
	loadCommonestEnglishWords(); // See commonEnglishWords.js.
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

	// No marking if selection is "too big" (spreads over more than on line).
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

	theSelection.doingDoubleClick = false;
	justUpdateScrollbar = false;
}

//See intramine_file_viewer_cm.pl#InitialHighlightItems().
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

//function decodeSpecialWordCharacters() {
//	if (markerMainElement !== null && highlightItems.length > 0)
//		{
//		for (let i = 0; i < highlightItems.length; ++i)
//			{
//			highlightItems[i] = highlightItems[i].replace(/ *__D_ */g, ".");
//			highlightItems[i] = highlightItems[i].replace(/__DS_([A-Za-z])/g, "\$$1");
//			highlightItems[i] = highlightItems[i].replace(/__PC_([A-Za-z])/g, "\%$1");
//			highlightItems[i] = highlightItems[i].replace(/__AT_([A-Za-z])/g, "\@$1");
//			}
//		}
//}

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
					let startContainer = theSelection.ltRange.startContainer;
					theSelection.ltRange.setStart(startContainer, beginOffset);
					theSelection.ltRange.setEnd(startContainer, endOffset);
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
// Revision, this affects the actual current selection so stop doing it.
// I can't remember why I wrote the above line.
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

    // walk parent nodes from start to common ancestor
    for (node = start.parentNode; node; node = node.parentNode)
    {
        nodes.push(node);
        if (node == commonAncestor)
            break;
    }
    nodes.reverse();

    // walk children and siblings from start until end is found
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
	
	// indicatorHeight: ideal height of the thumb. In practice the actual thumb height
	// needs to be a minimum of about 18 pixels.
	////let indicatorHeight = (textViewableHeight / mainScrolllHeight) * textViewableHeight;

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

let addHintTimer; // onMobile, to keep trying addHintboxListener() until it succeeds.

function addHintboxListener() {
	let tooltipElement = document.getElementById("hintbox");
	if (tooltipElement !== null)
		{
		tooltipElement.addEventListener("touchstart", noteHintboxClicked);
		clearInterval(addHintTimer);
		}
}

if (onMobile)
	{
	addHintTimer = setInterval(addHintboxListener, 200);
	}

document.addEventListener("mousedown", notelinkClicked);

ready(finishStartup);
