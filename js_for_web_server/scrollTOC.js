/**
 * scrollTOC.js: when a heading is clicked in text, scroll corresponding Table of Contents
 * entry into view. Non-CodeMirror files only. See cmScrollTOC.js for CodeMirror handling.
 */

// Scroll the Table of Contents:
// if click was in text content, to heading at or just before line clicked.
// if scrolling, to heading at or just after first visible line.
function scrollTocEntryIntoView(evt, weAreScrolling) {
	let tocElem = null;

	if (!weAreScrolling)
		{
		let lineNum = lineNumberforAnchor();
		if (lineNum >= 0)
			{
			tocElem = getTocElemForLineNumber(lineNum);
			}
		else
			{
			// Treat as for scrolling.
			weAreScrolling = true;
			}
		}
	
	if (weAreScrolling)
		{
		let el = document.getElementById(cmTextHolderName);
		let limitLineNum = lastVisibleLineNumber(el) + 1;
		let lineNum = firstVisibleLineNumber(el);
		tocElem = getTocElemAfterLineNumber(lineNum, limitLineNum);
		if (tocElem === null)
			{
			tocElem = getTocElemForLineNumber(lineNum);
			}

		// For restoring scrolled position after a reload.
		//let deductionForInlineHTMLChunks = inlineHTMLDeductionBeforeLine(lineNum);
		//lineNum -= deductionForInlineHTMLChunks;
		location.hash = lineNum.toString();
		}
		
	if (tocElem !== null)
		{
		tocElem.scrollIntoView({block: 'center'});
		updateTocHighlight(tocElem);
		}
}

// No longer used.
// For .txt documents displayed by IntraMine's Viewer, deduct
// 1 from the line number to show for each inline HTML chunk
// that is before lineNum. This makes the row count for
// regular (non-line HTML) text agree with the
// wanted lineNum.
// Return (+ve) correction to deduct from lineNum.
function inlineHTMLDeductionBeforeLine(lineNum) {
	let correction = 0;
	if (!hasTextExtension())
		{
		return(0);
		}
	
	let rawHTMLElements = document.getElementsByClassName("rawHTML");
	if (rawHTMLElements === null)
		{
		return(0);
		}

	for (let i = 0; i < rawHTMLElements.length; i++)
		{
		const elementId = rawHTMLElements[i].id;
		if (elementId !== '')
			{
			if (elementId.indexOf("rawH_") == 0)
				{
				let elementLineNumStr = elementId.substring(5);
				let elNum = Number(elementLineNumStr);
				if (elNum !== NaN && elNum < lineNum)
					{
					++correction;
					}
				}
			}
		}

	return(correction);
}

// This is called only for Markdown files, see addTocScrollListener() below.
function scrollMarkdownTocEntryIntoView(evt) {
	let tocDiv = document.getElementById('scrollContentsList');
	if (tocDiv === null)
		{
		return;
		}
	
	const idRegExp = /mdJump\(\'([^\']+)/;
	let tocElemIdentifier = markdownCurrentHeaderID();
	let tocElem = null;
	if (tocElemIdentifier !== '')
		{
		// Find corresponding entry in the TOC, scroll it into view and highlight.
		// The tocDiv contains a <ul> which contains <li>'s which each contain an <a>.
		let ulElement = tocDiv.firstElementChild;
		if (ulElement !== null)
			{
			let listElements = ulElement.children;			
			for (let i = 0; i < listElements.length; i++)
				{
				let anchorElement = listElements[i].firstElementChild;
				if (anchorElement !== null)
					{
					// Get the <li> element's contents, eg
					// <a onclick="mdJump('intraminesservices');">IntraMine's services</a>
					let listItemContents = listElements[i].innerHTML;

					let idMatchArr = listItemContents.match(idRegExp);
					if (idMatchArr !== null)
						{
						let potentialID = idMatchArr[1];
						if (potentialID === tocElemIdentifier)
							{
							tocElem = listElements[i];
							break;
							}
						}
					}
				}
			}
		}

	if (tocElem !== null)
		{
		tocElem.scrollIntoView({block: 'center'});
		updateTocHighlight(tocElem);
		}
}

// Restore scrolled position of Table of Contents.
// Called by  viewerStart.js#reJumpToLineNumber().
function restoreTocSelection(lineNum) {
	let tocElem = null;

	let el = document.getElementById(cmTextHolderName);
	let limitLineNum = lastVisibleLineNumber(el) + 1;
	tocElem = getTocElemAfterLineNumber(lineNum, limitLineNum);
	if (tocElem === null)
		{
		tocElem = getTocElemForLineNumber(lineNum);
		}
	if (tocElem !== null)
		{
		tocElem.scrollIntoView({block: 'center'});
		updateTocHighlight(tocElem);
		}
}

// Get text line number for current selection anchor, or -1.
function lineNumberforAnchor() {
	let currSelection = window.getSelection();
	if (currSelection === null)
		{
		return(-1);
		}
	
	let lineNum = -1;
	let rangeCount = currSelection.rangeCount;
	if (rangeCount > 0)
		{
		let currRange = currSelection.getRangeAt(0);
		let commonA = currRange.startContainer;
		let tdElem = commonA;
		
		while (tdElem !== null && tdElem.nodeName !== "TD")
			{
			tdElem = tdElem.parentNode;
			}
		if (tdElem !== null)
			{
			let previousElem = tdElem.previousElementSibling;
			if (previousElem !== null)
				{
				let tdLineNum = previousElem.getAttribute("n");
				if (tdLineNum !== null)
					{
					lineNum = tdLineNum;
					}
				}
			}
		}
	
	return (lineNum);
}

// Return TOC element that is at or closest above the text line number.
// Called for mouse/touch in actual text content.
// Typical non-CodeMirror TOC entry:
// <li class="h2" im-text-ln="123">
function getTocElemForLineNumber(lineNum) {
	let tocElement = document.getElementById("scrollContentsList");
	if (tocElement === null)
		{
		return(null);
		}
	
	let tocElem = null;
	let previousTocElem = null;
	let previousTocElemLineNum = 0;
	let lowestNumberedElem = null;
	let lowestNumberedElemNumber = 0;
	let tocEntries = tocElement.getElementsByTagName("li");
	for (let i = 0; i < tocEntries.length; i++)
		{
		let li = tocEntries[i];
		let tocLineNum = parseInt(li.getAttribute("im-text-ln"), 10); // IntraMine line number of heading in main text
		if (!isNaN(tocLineNum) && tocLineNum <= lineNum)
			{
			if (tocLineNum == lineNum)
				{
				tocElem = tocEntries[i];
				break;
				}
			else if (previousTocElemLineNum <  tocLineNum)
				{
				previousTocElemLineNum = tocLineNum;
				previousTocElem = tocEntries[i];
				}
			
			if (lowestNumberedElemNumber == 0 || lowestNumberedElemNumber > tocLineNum)
				{
				lowestNumberedElemNumber = tocLineNum;
				lowestNumberedElem = tocEntries[i];
				}
			}
		}
	
	if (tocElem === null && previousTocElem !== null)
		{
		tocElem = previousTocElem;
		}
	else if (tocElem === null && lowestNumberedElem !== null)
		{
		tocElem = lowestNumberedElem;
		}
	
	return(tocElem);
}

// Return TOC element that is at or closest *below* the text line number.
// Called after a scroll. Element must be before the visible bottom of the page,
// otherwise we should be looking upwards from the top of page for the heading
// that applies to the current position.
function getTocElemAfterLineNumber(lineNum, limitLineNum) {
	let tocElement = document.getElementById("scrollContentsList");
	if (tocElement === null)
		{
		return(null);
		}
	
	let tocElem = null;
	let nextTocElem = null;
	let nextTocElemLineNum = 999999;
	let lastTocElem = null;
	let lastTocElemLineNum = 0;
	let tocEntries = tocElement.getElementsByTagName("li");
	for (let i = 0; i < tocEntries.length; i++)
		{
		let li = tocEntries[i];
		let tocLineNum = parseInt(li.getAttribute("im-text-ln"), 10); // IntraMine line number of heading in main text
		if (!isNaN(tocLineNum) && tocLineNum >= lineNum && tocLineNum <= limitLineNum)
			{
			if (tocLineNum == lineNum)
				{
				tocElem = tocEntries[i];
				break;
				}
			else if (nextTocElemLineNum >  tocLineNum)
				{
				nextTocElemLineNum = tocLineNum;
				nextTocElem = tocEntries[i];
				}
			
			if (lastTocElemLineNum < tocLineNum)
				{
				lastTocElemLineNum = tocLineNum;
				lastTocElem = tocEntries[i];
				}
			}
		}

	
	if (tocElem === null && nextTocElem !== null)
		{
		tocElem = nextTocElem;
		}
	else if (tocElem === null && lastTocElem !== null)
		{
		tocElem = lastTocElem;
		}
	
	return(tocElem);
}

let scrollingForToc = null;
let isMarkdownFile = pathIsForMarkdown(thePath);
function addTocScrollListener(evt) {
	let el = document.getElementById(cmTextHolderName);
	if (el !== null)
		{
		el.addEventListener("scroll", function(evt) {
			// Clear our timeout throughout the scroll
			window.clearTimeout( scrollingForToc );
	
			// Set a timeout to run after scrolling ends
			scrollingForToc = setTimeout(function() {
				// Run the callback.
				if (isMarkdownFile)
					{
					scrollMarkdownTocEntryIntoView(evt);
					}
				else
					{
					scrollTocEntryIntoView(evt, true);
					}
				// Trying to stabilize nav bar, sometimes it randomly
				// jumps off the top of the window.
				resetTopNavPosition();
			}, 66);
			});
		}
}

function pathIsForMarkdown(path)
	{
	const markdownRegex = new RegExp("\.(md|mkd|markdown)$");
	let result = markdownRegex.test(path);
	return(result);
	}

function updateTocHighlight(elem) {
	if (elem === null)
		{
		return;
		}
	let tocElement = document.getElementById("scrollContentsList");
	if (tocElement === null)
		{
		return(null);
		}
	
	let tocEntries = tocElement.getElementsByTagName("li");
	for (let i = 0; i < tocEntries.length; i++)
		{
		if (hasClass(tocEntries[i], selectedTocId))
			{
			removeClass(tocEntries[i], selectedTocId);
			}
		}
	
	addClass(elem, selectedTocId);
}

window.addEventListener("load", addTocScrollListener);
