/**
 * cmTocAnchors.js: Implements goToAnchor() etc for Table of Contents entries
such as <a onclick="goToAnchor(&quot;Images::finished&quot;, 145);">Images::finished()</a>
where "Images::finished" is the name of a method. The anchor is scrolled into view.
 */

let goingToAnchor = false;

// To determine if jumpToLine will trigger a scroll, compare previous first visible
// line number with current first visible line number.
let previousFirstLineNumber = -1;

// Notice we are resizing. Set true in doResize().
let resizing = false;

// Line number tracking, determines which TOC entry to highlight
// based on the line number of the corresponding source heading (class, function etc);
let lineNumberForToc = -1;

function setLineNumberForToc(lineNum) {
	lineNumberForToc = lineNum;
	}

function getLineNumberForToc() {
	let lineNum = lineNumberForToc;
	clearLineNumberForToc();
	return(lineNum);
}

function clearLineNumberForToc() {
	lineNumberForToc = -1;
}

// Called by Table of Contents entries. See eg intramine_viewer.pl#GetCTagsTOCForFile().
// And also called for links to internal headings (functions classes etc).
function goToAnchor(anchorText, lineNum) {
	goingToAnchor = true;

	setLineNumberForToc(lineNum);

	// Set location.hash to remember anchor, in case of a refresh.
	location.hash = anchorText;
	
	myCodeMirror.focus();
	
	// Jump to the line number.
	jumpToLine(lineNum, true);
}

// If line above is the end of a C++-style comment, back up to the beginning of the comment
// or 20 lines, whichever comes first. Also look back for lines starting with //.
function jumpToLine(lineNum, adjustToShowComment) {
	if (lineNum > 0)
		{
		--lineNum; // off by one, cm line numbers are 0-based for API calls.
		}

	let lineNumToShow = lineNum;
	if (adjustToShowComment && lineNumToShow > 0)
		{
		--lineNumToShow;
		let textOnLine = myCodeMirror.doc.getRange({
			line : lineNumToShow,
			ch : 0
		}, {
			line : lineNumToShow
		});
		let endCommentMarker = /\*\/$/;
		let jsCommentMarker = /^\/\//;
		if (endCommentMarker.test(textOnLine) && lineNumToShow >= 0) // first line above ends a comment
			{
			let startCommentMarker = /\/\*/;
			let backCounter = 20;
			while (!startCommentMarker.test(textOnLine) && --backCounter >= 0 && lineNumToShow > 0)
				{
				--lineNumToShow;
				textOnLine = myCodeMirror.doc.getRange({
					line : lineNumToShow,
					ch : 0
				}, {
					line : lineNumToShow
				});
				}
			}
		else if (jsCommentMarker.test(textOnLine) && lineNumToShow >= 0)
			{
			let backCounter = 20;
			while (jsCommentMarker.test(textOnLine) && --backCounter >= 0 && lineNumToShow > 0)
				{
				--lineNumToShow;
				textOnLine = myCodeMirror.doc.getRange({
					line : lineNumToShow,
					ch : 0
				}, {
					line : lineNumToShow
				});
				}
			++lineNumToShow;
			}
		else
			{
			++lineNumToShow;
			}
		}
		
	let t = myCodeMirror.charCoords({
		line : lineNumToShow,
		ch : 0
	}, "local").top;
	myCodeMirror.scrollTo(null, t);
	
	let willScroll = true;
	let currentFirstLineNumber = getFirstVisibleLineNumber();
	if ( currentFirstLineNumber === previousFirstLineNumber)
		{
		willScroll = false;
		}
	let previousPreviousFirstLineNumber = previousFirstLineNumber;

	previousFirstLineNumber = currentFirstLineNumber;

	myCodeMirror.setSelection({line: lineNum, ch: 0}, {line: lineNum, ch: 999});
	
	scrollMobileIndicator();

	// Restore any highlighted text selection. Doing it on a time delay is the only
	// way I found that works. Note the "scroll: false" is critical,
	// to preserve the position jumped to just above.
	if (cmCursorStartPos.line >= 0)
		{
		setTimeout(function() {
			myCodeMirror.setSelection(cmCursorStartPos, cmCursorEndPos, {
				scroll : false
			});
		}, 800);
		}

	if (!willScroll)
		{
		let el = document.getElementById(cmTextHolderName);
		let limitLineNum = lastVisibleLineNumber(el);
		let tocElem = getTocElemAfterLineNumber(lineNum, limitLineNum); // cmTocAnchors.
		if (tocElem === null)
			{
			tocElem = getTocElemForLineNumber(lineNum);
			}

		if (tocElem !== null)
			{
			updateTocHighlight(tocElem);
			}
		}
	else if (previousPreviousFirstLineNumber < 0)
		{
		// Initial load, call update the TOC highlight after a delay.
		let el = document.getElementById(cmTextHolderName);
		let limitLineNum = lastVisibleLineNumber(el);
		let tocElem = getTocElemAfterLineNumber(lineNum, limitLineNum); // cmTocAnchors.
		if (tocElem === null)
			{
			tocElem = getTocElemForLineNumber(lineNum);
			}

		if (tocElem !== null)
			{
			setTimeout(function() {
				updateTocHighlight(tocElem);
				}, 1200);
			}
		}
}

function cmRejumpToAnchor() {
	let anchor = location.hash;
	if (anchor.length > 1)
		{
		anchor = anchor.replace(/^#/, '');
		if (isNaN(anchor))
			{
			let lineNumber = lineNumberForAnchor(anchor);
			if (lineNumber >= 0)
				{
				//goingToAnchor = true;
				jumpToLine(lineNumber, true);
				}
			}
		else
			{
			let lineNum = parseInt(anchor, 10);
			if (lineNum > 1)
				{
				jumpToLine(lineNum, true);
				}
			else
				{
				jumpToLine(lineNum, false);
				}
			}
		}
}

// Restore first line of text shown. This is like above jumpToLine
// but doesn't affect the selected text.
function cmQuickRejumpToLine() {
	let anchor = location.hash;
	if (anchor.length > 1)
		{
		anchor = anchor.replace(/^#/, '');
		if (isNaN(anchor))
			{
			return;
			}

		let lineNum = parseInt(anchor, 10);
		quickJumpToLine(lineNum);
		}
}

function quickJumpToLine(lineNum) {
	let lineNumToShow = lineNum - 1;
	let t = myCodeMirror.charCoords({
		line : lineNumToShow,
		ch : 0
	}, "local").top;
	myCodeMirror.scrollTo(null, t);
}

// Find the line number for an anchor, by looking through tocEntries[] for text that
// matches the entry in the supplied anchor.
function lineNumberForAnchor(anchor) {
	let lineNumber = -1; // not a good value
	if (anchor.length > 1)
		{
		anchor = anchor.replace(/^#/, '');
		if (isNaN(anchor))
			{
			let tocElement = document.getElementById("scrollContentsList"); // 
			let tocEntries = tocElement.getElementsByTagName("li");
			for (let i = 0; i < tocEntries.length; i++)
				{
				// eg <a onclick="goToAnchor(&quot;positionAndShowAceHint&quot;, 102);">positionAndShowAceHint()</a>
				let fullAnchor = tocEntries[i].innerHTML;
				let idLineMatch = /goToAnchor\(([^,]+), (\d+)/.exec(fullAnchor);
				if (idLineMatch !== null)
					{
					let anchorText = idLineMatch[1];
					let lineStr = idLineMatch[2];
					// anchorText is in quotes, strip them.
					anchorText = anchorText.replace(/^&quot;/, '');
					anchorText = anchorText.replace(/&quot;$/, '');
					anchorText = anchorText.replace(/^"/, '');
					anchorText = anchorText.replace(/"$/, '');

					if (anchor === anchorText)
						{
						lineNumber = parseInt(lineStr, 10);
						break;
						}
					}
				}
			}
		}

	return (lineNumber);
}

// From eg <a onclick="goToAnchor(&quot;positionAndShowAceHint&quot;, 102);">positionAndShowAceHint()</a>
// extract and return 102. Return -1 if no number found.
function lineNumberForTocLink(fullAnchor) {
	let lineNumber = -1;
	let idLineMatch = /goToAnchor\(([^,]+), (\d+)/.exec(fullAnchor);
	if (idLineMatch !== null)
		{
		let lineStr = idLineMatch[2];
		lineNumber = parseInt(lineStr, 10);
		}

	return (lineNumber);
}

function anchorNameForTocLink(fullAnchor) {
	let result = '';
	let idLineMatch = /goToAnchor\(([^,]+), (\d+)/.exec(fullAnchor);
	if (idLineMatch !== null)
		{
		result = idLineMatch[1];
		// Strip quotes.
		result = result.replace(/^&quot;/, '');
		result = result.replace(/&quot;$/, '');
		}

	return (result);
}

// Eg returns <a onclick="goToAnchor(&quot;QFileDialog::history&quot;, 1874);">QFileDialog::history()</a>
// for anchor == history.
function linkForInternalAnchor(anchor) {
	let result = '';
	let anchorHasColon = (anchor.indexOf(":") > 0);
	if (anchor.length > 1)
		{
		anchor = anchor.replace(/^#/, '');
		if (isNaN(anchor))
			{
			let tocElement = document.getElementById("scrollContentsList"); // 
			let tocEntries = tocElement.getElementsByTagName("li");
			for (let i = 0; i < tocEntries.length; i++)
				{
				// eg <a onclick="goToAnchor(&quot;positionAndShowAceHint&quot;, 102);">positionAndShowAceHint()</a>
				let fullAnchor = tocEntries[i].innerHTML;
				let idLineMatch = /goToAnchor\(([^,]+), (\d+)/.exec(fullAnchor);
				if (idLineMatch !== null)
					{
					let anchorText = idLineMatch[1];
					// anchorText is in quotes, strip them.
					anchorText = anchorText.replace(/^&quot;/, '');
					anchorText = anchorText.replace(/&quot;$/, '');
					if (!anchorHasColon) // strip anchorText down to match
						{
						let colPosLast = -1;
						if ((colPosLast = anchorText.lastIndexOf(":")) > 0)
							{
							anchorText = anchorText.substr(colPosLast + 1);
							}
						}
					let lineStr = idLineMatch[2];
					if (anchor === anchorText)
						{
						result = fullAnchor;
						break;
						}
					}
				}
			}
		}

	return (result);
}

// Get line number at top of view, store it in location.hash. We are not goingToAnchor (going
// to line number instead).
function onScroll() {
	// resizing is true when resizing, set false by finishWindowResize().
	if (resizing)
		{
		return;
		}

	let rect = myCodeMirror.getWrapperElement().getBoundingClientRect();
	let myStartLine = myCodeMirror.lineAtHeight(rect.top, "window");

	if (!goingToAnchor)
		{
		let lineNumber = parseInt(myStartLine.toString(), 10);
		if (lineNumber > 0)
			{
			lineNumber += 2;
			}
		else
			{
			lineNumber = 1;
			}
		location.hash = lineNumber.toString();
		}
	
	// Too soon - this is now done in cmAutoLinks.js#handleFileLinkMouseUp().
	// goingToAnchor = false;
}

function finishWindowResize(el) {
	if (resizing)
		{
		if (typeof topLineForResize !== 'undefined' && topLineForResize >= 0)
			{
			location.hash = topLineForResize;
			cmQuickRejumpToLine(); // Restores first text line in contents
			}
		}
	resizing = false;
}

let lazyMouseUp = JD.debounce(finishWindowResize, 1000);

// Hash holding line numbers for TOC entries, used in cmAutoLinks.js#markUpInternalHeadersOnOneLine().
let lineNumberForTocEntry = {};
let lineNumberHasToc = {};

// lineNumberForTocEntry["Header Name"] = "127" for example.
// Called in cmHandlers.js#cmLoad();
// Note there might not be a table of contents (eg .md files).
// Look through all entries in the table of contents, and pull out the line number
// for each entry.
function getLineNumberForTocEntries() {
	let tocElement = document.getElementById("scrollContentsList");
	if (tocElement === null)
		{
		return;
		}
	let tocEntries = tocElement.getElementsByTagName("li");
	for (let i = 0; i < tocEntries.length; i++)
		{
		// eg <a onclick="goToAnchor(&quot;positionAndShowAceHint&quot;, 102);">positionAndShowAceHint()</a>
		// <a onclick="goToAnchor(&quot;QFutureWatcherBase::QFutureWatcherBase&quot;, 106);">QFutureWatcherBase::QFutureWatcherBase()</a>
		// <a onclick="goToAnchor(&quot;QFutureWatcherBase::isStarted&quot;, 249);">QFutureWatcherBase::isStarted()</a>
		// <a onclick="goToAnchor(&quot;QFutureWatcher&quot;, 115);">QFutureWatcher</a>
		// <a onclick="goToAnchor(&quot;~QFutureWatcher2&quot;, 191);">~QFutureWatcher()</a>
		// <a onmousedown="goToAnchor(&quot;New&quot;, 11);"><span class="circle_red">m</span><strong>New</strong>()</a>
		let fullAnchor = tocEntries[i].innerHTML;
		//let mtch = /goToAnchor\(([^,]+), (\d+)[^>]+\>\<span[^>]+?\>.\<\/span\>([^<]+)\</.exec(fullAnchor);

		// First try: goToAnchor with a letter in a circle (in a <span>) before text.
		let mtch = /goToAnchor\(([^,]+), (\d+)[^>]+\>\<span[^>]+?\>.\<\/span\>([^<]+)\</.exec(fullAnchor);
		// Second try: no letter in circle.
		if (mtch === null)
			{
			mtch = /goToAnchor\(([^,]+), (\d+)[^>]+\>([^<]+)\</.exec(fullAnchor);
			}
		// Third try: letter in circle and >strong> around displayed text.
		if (mtch === null)
			{
			mtch = /goToAnchor\(([^,]+), (\d+)[^>]+\>\<span[^>]+?\>.\<\/span\>\<strong\>([^<]+)\</.exec(fullAnchor);
			}
		
		if (mtch !== null)
			{
			let anchorText = mtch[1];
			let lineNum = parseInt(mtch[2], 10);
			let headerText = mtch[3];
			// Grab just the method name from class::method
			let anchorHasColon = (headerText.indexOf(":") > 0);
			if (anchorHasColon)
				{
				let colPosLast = -1;
				if ((colPosLast = headerText.lastIndexOf(":")) > 0)
					{
					headerText = headerText.substring(colPosLast + 1);
					}
				}
			// Trim any trailing "()" too? Keep them for now.
			// let trailingCloseParenPos = -1;
			// if ((trailingCloseParenPos = headerText.lastIndexOf(")")) > 0)
			// {
			// headerText = headerText.substring(0, trailingCloseParenPos - 1);
			// }

			lineNumberForTocEntry[headerText] = lineNum;
			lineNumberHasToc[lineNum] = 1;
			}
		}
}

// Return Table of Contents <li> element at or closest *above* the lineNum in main text,
// or null.
function getTocElemForLineNumber(lineNum) {
	let tocElement = document.getElementById("scrollContentsList");
	if (tocElement === null)
		{
		return(null);
		}
	
	// Use the line number from jumpToLine() if there is one.
	let tocLineNumber = getLineNumberForToc();
	if (tocLineNumber >= 0)
		{
		lineNum = tocLineNumber;
		}

	let tocElem = null;
	let previousTocElem = null;
	let previousTocElemLineNum = 0;
	let lowestNumberedElem = null;
	let lowestNumberedElemNumber = 0;
	let tocEntries = tocElement.getElementsByTagName("li");
	for (let i = 0; i < tocEntries.length; i++)
		{
		let fullAnchor = tocEntries[i].innerHTML;
		//let mtch = /goToAnchor\(([^,]+), (\d+)[^>]+\>\<span[^>]+?\>.\<\/span\>([^<]+)\</.exec(fullAnchor);
		let mtch = /goToAnchor\(([^,]+), (\d+)[^>]+\>\<span[^>]+?\>.\<\/span\>([^<]+)\</.exec(fullAnchor);
		if (mtch === null)
			{
			mtch = /goToAnchor\(([^,]+), (\d+)[^>]+\>([^<]+)\</.exec(fullAnchor);
			}
		if (mtch === null)
			{
			mtch = /goToAnchor\(([^,]+), (\d+)[^>]+\>\<span[^>]+?\>.\<\/span\>\<strong\>([^<]+)\</.exec(fullAnchor);
			}

		if (mtch !== null)
			{
			let anchorText = mtch[1];
			let tocLineNum = parseInt(mtch[2], 10);
			if (!isNaN(tocLineNum) && tocLineNum <= lineNum)
				{
				if (tocLineNum == lineNum)
					{
					tocElem = tocEntries[i];
					break;
					}
				else if (tocLineNum < lineNum && previousTocElemLineNum <  tocLineNum)
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
		}
	
	if (tocElem === null && previousTocElem !== null)
		{
		tocElem = previousTocElem;
		}
	else if (tocElem === null && lowestNumberedElem !== null)
		{
		tocElem = lowestNumberedElem;
		}
	
	if (tocElem === null)
		{
		let topElement = document.getElementById ("cmTopTocEntry");
		if (topElement !== null)
			{
			tocElem = topElement;
			}
		}
	
	return(tocElem);
}

//Return TOC element that is at or closest *below* the text line number.
//Called after a scroll.
function getTocElemAfterLineNumber(lineNum, limitLineNum) {
	let tocElement = document.getElementById("scrollContentsList");
	if (tocElement === null)
		{
		return(null);
		}
	
	// Use the line number from jumpToLine() if there is one.
	let tocLineNumber = getLineNumberForToc();
	if (tocLineNumber >= 0)
		{
		lineNum = tocLineNumber;
		}
	
	let tocElem = null;
	let nextTocElem = null;
	let nextTocElemLineNum = 999999;
	let lastTocElem = null;
	let lastTocElemLineNum = 0;
	let tocEntries = tocElement.getElementsByTagName("li");
	for (let i = 0; i < tocEntries.length; i++)
		{
		let fullAnchor = tocEntries[i].innerHTML;
		let mtch = /goToAnchor\(([^,]+), (\d+)[^>]+\>\<span[^>]+?\>.\<\/span\>([^<]+)\</.exec(fullAnchor);
		if (mtch === null)
			{
			mtch = /goToAnchor\(([^,]+), (\d+)[^>]+\>([^<]+)\</.exec(fullAnchor);
			}
		if (mtch === null)
			{
			mtch = /goToAnchor\(([^,]+), (\d+)[^>]+\>\<span[^>]+?\>.\<\/span\>\<strong\>([^<]+)\</.exec(fullAnchor);
			}

		if (mtch !== null)
			{
			let anchorText = mtch[1];
			let tocLineNum = parseInt(mtch[2], 10);
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

// Get line number (1-based) from currently selected Table Of Contents <li> element,
function currentTOCLineNum() {
	let tocElement = document.getElementById("scrollContentsList");
	if (tocElement === null)
		{
		return(0);
		}
	let lineNum = 0;
	let tocEntries = tocElement.getElementsByTagName("li");
	for (let i = 0; i < tocEntries.length; i++)
		{
		if (hasClass(tocEntries[i], selectedTocId))
			{
			let fullAnchor = tocEntries[i].innerHTML;
			let mtch = /goToAnchor\(([^,]+), (\d+)[^>]+\>\<span[^>]+?\>.\<\/span\>([^<]+)\</.exec(fullAnchor);
			if (mtch === null)
				{
				mtch = /goToAnchor\(([^,]+), (\d+)[^>]+\>([^<]+)\</.exec(fullAnchor);
				}
			if (mtch === null)
				{
				mtch = /goToAnchor\(([^,]+), (\d+)[^>]+\>\<span[^>]+?\>.\<\/span\>\<strong\>([^<]+)\</.exec(fullAnchor);
				}
			if (mtch !== null)
				{
				lineNum = parseInt(mtch[2], 10);
				}
			}
		}
	return(lineNum);
}
