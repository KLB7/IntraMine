// showHideTOC.js: shrink/expand the Table Of Contents via a "#tocShrinkExpand" element
// at top of the Table Of Contents. The TOC isn't shrunk away to nothing, a bit is left
// visible (which reminds one that it's there, and makes the design easier:).
// TODO this is a bit fragile, scrollContentsList and scrollTextRightOfContents are hard-coded.
// However, any ambitious person who changes those has bought the rights to full maintenance.
// This is used in the Viewer (intramine_file_viewer_cm.pl) when a view has a table of contents,
// and in gloss2html.pl (which generates HTML from .txt, and there is always a table of contents).

// Shrink/expand the Table Of Contents when the "#tocShrinkExpand" element is clicked.
// If toggleElem is null then shrinkIt will be false and the TOC will expand. This is
// currently called with null by dragTOC.js#addDragger() since for some unknown reason the
// TOC pane is coming up too narrow.
function toggleTOC(toggleElem) {
	// Avoid spurious highlighting after TOC toggle causes redraw.
	if (document.activeElement !== null)
		{
		document.activeElement.blur();
		}

	rememberLocation();
	
	let elementToAdjust = document.getElementById('scrollContentsList');
	let textElement = document.getElementById('scrollTextRightOfContents');
	if (elementToAdjust === null || textElement === null)
		{
		console.log("showHideTOC.js#toggleTOC top elements are missing!");
		return (false);
		}
	let divContainer = elementToAdjust.parentElement;
	if (elementToAdjust !== null && textElement !== null)
		{
		let widthStrTOC = window.getComputedStyle(elementToAdjust, null).getPropertyValue('width');
		let widthStrParent = window.getComputedStyle(divContainer, null).getPropertyValue('width');
		let widthTOC = parseFloat(widthStrTOC);
		let widthParent = parseFloat(widthStrParent);
		let oldTocWidthPC = 100 * widthTOC / widthParent;
		let paneSeparator = document.getElementById('panes-separator');;
		let widthPaneSep = 3; // pixels
		if (paneSeparator !== null)
			{
			let widthStrSep = window.getComputedStyle(paneSeparator, null).getPropertyValue('width');
			widthPaneSep = parseFloat(widthStrSep); // pixels
			}
		let newWidthPaneSep = widthPaneSep / widthParent * 100;
		
		let shrinkIt = (oldTocWidthPC < 10) ? false : true;
		if (toggleElem === null)
			{
			shrinkIt = false;
			}
		let newWidthTOCPC, newWidthTextPC;
		if (shrinkIt)
			{
			newWidthTOCPC = 5;
			}
		else
			{
			newWidthTOCPC = 23;
			}
		newWidthTextPC = 100 - newWidthPaneSep - newWidthTOCPC;

		elementToAdjust.style.width = newWidthTOCPC + "%";
		textElement.style.width = newWidthTextPC + "%";

		location.hash = topLineNumber;

		if (usingCM)
			{
			// Especially for CodeMirror, force a recalc.
			myCodeMirror.refresh();
			cmQuickRejumpToLine();
			}
		else
			{
			// TEST ONLY
			//console.log("toggleTOC.js#76");
			reJumpToLineNumber(topLineNumber);
			///// was restoreTopPosition(textElement, theTopPos);
			}

		// Redo initial scrollbar markers
		if (initialSearchHitsAreShowing)
			{
			removeInitialHighlights();
			highlightInitialItems();
			}

		// Also redo scroll bar markers for selection hits in the scroll bar.
		if (!usingCM)
			{
			removeAllScrollbarHighlights(scrollMarkerClass);
			markHitsInScrollbar(textMarkerClass, scrollMarkerClass);
			}
		
		// Remember current TOC width in pixels.
		if (toggleElem !== null) // Not first call
			{
			let leftPaneStr = elementToAdjust.style.width;
			let leftPanePC = parseFloat(leftPaneStr);
			let leftPanePixels = leftPanePC * widthParent / 100;
			let leftPaneWidthKey = thePath + '?' + "leftPaneWidth";
			localStorage.setItem(leftPaneWidthKey, leftPanePixels);
			}
		}

	return (false);
}

function addTocToggle(idToggle) {
	let scrollContentsElement = document.getElementById('scrollContentsList');
	if (scrollContentsElement !== null)
		{
		// Add in the shrink/expand element at top of Table Of Contents.
		let toggleElem;
		if (b64ToggleImage !== '')
			{
			toggleElem = createElementFromHTML("<img src=\"data:image/png;base64,"
						+ b64ToggleImage + "\" id='" + idToggle + "'>");
			}
		else
			{
			toggleElem = createElementFromHTML("<img src='707788g4.png' id='" + idToggle + "'>");
			}
		
		document.body.insertBefore(toggleElem, document.body.firstChild);
		toggleElem.addEventListener('click', function() {
			toggleTOC(toggleElem);
		});

		// Default position is absolute relative to the page. We want to set the top so that it
		// nestles down in the Table of Contents at the top, where 20px of margin has been
		// left for it. Top should be just below the horizontal rule that divides upper part
		// of page from content proper.
		let rule = document.getElementById("rule_above_editor");
		let pos = getPosition(rule);
		let toggleTop = pos.y + 4;

		toggleElem.style.top = toggleTop + "px";
		}
}

// If the nav bar wraps and grows taller, or shrinks back down,
// it's nice to reposition the green double-headed arrow.
function repositionTocToggle() {
	let toggleElem = document.getElementById("tocShrinkExpand");
	let rule = document.getElementById("rule_above_editor");
	if (toggleElem === null || rule === null)
		{
		//console.log("showHideTOC.js#repositionTocToggle elements are missing!");
		return;
		}
	let pos = getPosition(rule);
	let toggleTop = pos.y + 4;

	toggleElem.style.top = toggleTop + "px";
}

// Get line number of first visible line in text.
// For non-codemirror, look for table row with bounding rect top that is
// >= elem bounding rect top. On that row, <td n="(\d+)" gives the line number.
function firstVisibleLineNumber(elem) {
	let topPos = 0;
	//let undefCounter = 0;

	if (usingCM)
		{
		let rect = myCodeMirror.getWrapperElement().getBoundingClientRect();
		let firstVisibleLineNum = myCodeMirror.lineAtHeight(rect.top, "window");
		topPos = firstVisibleLineNum;
		}
	else
		{
		topPos = quickGetPosition(elem, true);
		}

	return (topPos);
}

// For non-CodeMirror files, the text of the document is in one or more consecutive <table>s.
// - find first table whose top is too far, look at the one before that - or if top
// is dead on, use that one.
// - check every 100th or 10th entry for element that is too far or dead on
// - if checked 100, now check every 10th starting from the "100" row just found
// - step through from there to find the exact number, skipping shrunk rows that have no number.
// "elem" is the main text holder, having tables as direct children (at least one).
function quickGetPosition(elem, getTop) {
	if (elem === null)
		{
		return;
		}
	let topPos = 0;
	let undefCounter = 0;
	let enclosingRect = elem.getBoundingClientRect();
	let enclosingRectTopOrBot = (getTop) ? enclosingRect.top : enclosingRect.bottom;
	
	let kids = null;
	for (; undefCounter < 100; ++undefCounter)
		{
		if (typeof(elem.children) !== 'undefined')
			{
			kids = elem.children;
			break;
			}
		}
	
	if (typeof(elem.children) === 'undefined')
		{
		//console.log("ERROR could not get children!");
		return(0);
		}
	
	//let done = false;
	
	// If "kids" doesn't have a table, try going down one more level - this is needed
	// with "index.txt" for example, which has a "special-index-wrapper" holding its one table
	if (!elementHasTableAsChild(kids))
		{
		kids = elem.children[0].children;
		}
	
	// - find first table whose BOTTOM is past the top or bottom of the view.
	let table = wantedTableForPosition(kids, enclosingRectTopOrBot, getTop);
	
	if (table !== null)
		{
		let tableBody = getTableBody(table);
		
		if (tableBody !== null)
			{
			let rowNum = getRowCandidateAbovePosition(table, 100, 10, enclosingRectTopOrBot);
			topPos = rowTopPosition(table, rowNum, 10, enclosingRectTopOrBot);
			}
		}
	
	return (topPos);
}

function getTableBody(table) {
	let tableBody = null;
	
	if (table !== null)
		{
		let tableKids = table.children; // there should be only one TBODY
		for (let m = 0; m < tableKids.length; ++m)
			{
			if (tableKids[m].nodeName === "TBODY")
				{
				tableBody = tableKids[m];
				break;
				}
			}
		}
	
	return(tableBody);
}

//Look at last row bottom in each table body, return current table if its bottom is
// at or past enclosingRectTopOrBot.
// // Sometimes rounding errors get in the way, hence the "Math.ceil()"
function wantedTableForPosition(topChildren, enclosingRectTopOrBot, getTop) {
	let wantedTable = null;
	
	
	//enclosingRectTopOrBot -= 1;
	
	for (let i = 0; i < topChildren.length; ++i)
		{
		if (!getTop)
			{
			//console.log("Checking table " + i);
			}
		
		let tagName = topChildren[i].nodeName;
		if (tagName === "TABLE")
			{
			let tableBody = getTableBody(topChildren[i]);
			
			if (tableBody !== null)
				{
				let rows = tableBody.children;
				if (rows.length > 0)
					{
					let rowToCheck = rows.length - 1;
					let bounding = rows[rowToCheck].getBoundingClientRect();
					let bottomCeiling = Math.ceil(bounding.bottom);
					
					if (!getTop)
						{
						//console.log("Checking table " + i + " row " + rowToCheck + " bottom " + bottomCeiling + " of " + rows.length + " against " + enclosingRectTopOrBot);
						}
					
					if (bottomCeiling >= enclosingRectTopOrBot) // too far, or just far enough
						{
						wantedTable = topChildren[i];
						break;
						}
					}
				}
			} // if (tagName === "TABLE")
		}
		
	if (wantedTable === null)
		{
		if (!getTop)
			{
			//console.log("Did NOT find bottom!");
			}
		
		if (topChildren.length > 0)
			{
			if (getTop)
				{
				for (let i = 0; i < topChildren.length; ++i)
					{
					let tagName = topChildren[i].nodeName;
					if (tagName === "TABLE")
						{
						wantedTable = topChildren[i];
						break;
						}
					}
				}
			else // bottom
				{
				for (let i = topChildren.length - 1; i >= 0; --i)
					{
					let tagName = topChildren[i].nodeName;
					if (tagName === "TABLE")
						{
						wantedTable = topChildren[i];
						break;
						}
					}
				}
			}
		else
			{
			//console.log("ERROR no tables in document!");
			}
		}
	
	return(wantedTable);
}

function elementHasTableAsChild(topChildren) {
	let result = false;
	
	for (let i = 0; i < topChildren.length; ++i)
		{
		let tagName = topChildren[i].nodeName;
		if (tagName === "TABLE")
			{
			result = true;
			break;
			}
		}
	
	return(result);
}

// We are looking for a row with bottom above or at enclosingRectTopOrBot.
// 
// Starting at table bottom, look upwards rowInc at a time for the row bottom
// that is <= enclosingRectTopOrBot. If none found, the default 0 is returned.
// There are two passes, crude (100 row jumps) and fine (10 row jumps).
function getRowCandidateAbovePosition(table, majorInc, minorInc, enclosingRectTopOrBot) {
	let wantedRow = 0;
	//let lastRowCheckedInFirstPass = 0;
	let tableBody = getTableBody(table);
	
	if (tableBody !== null)
		{
		let rows = tableBody.children;
		let rowToCheck = rows.length - 1;
		
		// Look backwards in big jumps, from end of table.
		while (rowToCheck >= wantedRow)
			{
			let bounding = rows[rowToCheck].getBoundingClientRect();
			if (bounding.bottom <= enclosingRectTopOrBot)
				{
				wantedRow = rowToCheck;
				break;
				}
			else
				{
				rowToCheck -= majorInc;
				}
			}
		
		// Look backwards in small jumps, from wantedRow just found plus majorInc.
		rowToCheck = wantedRow + majorInc;
		if (rowToCheck > rows.length - 1)
			{
			rowToCheck = rows.length - 1;
			}
		while (rowToCheck >= wantedRow)
			{
			let bounding = rows[rowToCheck].getBoundingClientRect();
			if (bounding.bottom <= enclosingRectTopOrBot)
				{
				wantedRow = rowToCheck;
				break;
				}
			else
				{
				rowToCheck -= minorInc;
				}
			}
		}
	
	return(wantedRow);
}

// startRow should have a bottom that is <= enclosingRectTopOrBot, and not be too far
// above one that's >. Look down from startRow for a row with bottom >= enclosingRectTopOrBot.
// Try to adjust down slightly from that to a row with TOP >= enclosingRectTopOrBot.
// On a complete fail, which can happen when scrolling to bottom of document, take
// the last line number in the table. What can I say, it works.
function rowTopPosition(table, startRow, minorInc, enclosingRectTopOrBot) {
	let topPos = 0;
	let tableBody = getTableBody(table);
	
	enclosingRectTopOrBot = Math.ceil(enclosingRectTopOrBot);
	
	if (tableBody !== null)
		{
		let foundIt = false;
		let rows = tableBody.children;
		let lastToCheck = startRow + minorInc + 1;
		if (lastToCheck > rows.length)
			{
			lastToCheck = rows.length;
			}
		
		for (let j = startRow; j < lastToCheck; ++j)
			{
			let bounding = rows[j].getBoundingClientRect();
			let bottomCeiling = Math.ceil(bounding.bottom);
			if (bottomCeiling >= enclosingRectTopOrBot) // too far, or just far enough
				{
				let lastToCheck_K =  j + 3;
				if (lastToCheck_K > rows.length)
					{
					lastToCheck_K = rows.length;
					}
				for (let k = j; k < lastToCheck_K; ++k)
					{
					let bounding_K = rows[k].getBoundingClientRect();
					let bottomCeiling_K = Math.ceil(bounding_K.bottom);
					if (bottomCeiling_K > enclosingRectTopOrBot)
						{
						let contents = rows[k].innerHTML;
						let lineNumMatch = /^<td n="(\d+)/.exec(contents);
						if (lineNumMatch !== null)
							{
							topPos = parseInt(lineNumMatch[1], 10);
							foundIt = true;
							break;
							}
						}
					}
				
				// For the very last line, it's possible that the bottom of the last row
				// won't be visible (perhaps by only a pixel or so) or that it's a shrunk
				// row with no line number. If so, look up starting at row j for a row
				// with visible top and a line number.
				if (!foundIt)
					{
					for (let k = j; k < lastToCheck_K; ++k)
						{
						let bounding_K = rows[k].getBoundingClientRect();
						if (bounding_K.top >= enclosingRectTopOrBot)
							{
							let contents = rows[k].innerHTML;
							let lineNumMatch = /^<td n="(\d+)/.exec(contents);
							if (lineNumMatch !== null)
								{
								topPos = parseInt(lineNumMatch[1], 10);
								foundIt = true;
								break;
								}
							}
						}
					}
				
				break;
				}
			}
		
		if (!foundIt)
			{
			// Find last row with a line number.
			let k = rows.length - 1;
			while (k >= 0)
				{
				let contents = rows[k].innerHTML;
				let lineNumMatch = /^<td n="(\d+)/.exec(contents);
				if (lineNumMatch !== null)
					{
					topPos = parseInt(lineNumMatch[1], 10);
					foundIt = true;
					break;
					}
				--k;
				}
			}
		} // if (tableBody !== null)
	
	return (topPos);
}

function lastVisibleLineNumber(elem) {
	let bottomPos = 0;
	//let undefCounter = 0;
	
	if (usingCM)
		{
		let rect = myCodeMirror.getWrapperElement().getBoundingClientRect();
		let lastVisibleLineNum = myCodeMirror.lineAtHeight(rect.bottom, "window");
		bottomPos = lastVisibleLineNum;
		}
	else
		{
		bottomPos = quickGetPosition(elem, false);
		}

	return (bottomPos);
}

function restoreTopPosition(elem, topPos) {
	if (usingCM)
		{
		jumpToLine(topPos + 2, false);
		}
	else
		{
		restoreTopPositionNonCM(elem, topPos);
		}
}

// Find <tr> in elem with <td n="topPos"..., scroll it into view.
function restoreTopPositionNonCM(elem, topPos) {
	let children = elem.children;
	let done = false;

	for (let i = 0; i < children.length; ++i)
		{
		let tagName = children[i].nodeName;
		if (tagName === "TABLE")
			{
			let tableBody = children[i].children;
			for (let k = 0; k < tableBody.length; ++k)
				{
				let tableChildren = tableBody[k].children;
				for (let j = 0; j < tableChildren.length; ++j)
					{
					let contents = tableChildren[j].innerHTML;
					let lineNumMatch = /^<td n="(\d+)/.exec(contents);
					if (lineNumMatch !== null)
						{
						let currentLine = lineNumMatch[1];
						if (currentLine == topPos)
							{
							tableChildren[j].scrollIntoView();
							// Set top of nav to zero, fixes an iPad scroll problem where nav
							// goes off the top.
							let nav = document.getElementById("nav"); // nope nav.style.top = 0;
							if (nav !== null)
								{
								nav.parentNode.scrollTop = 0;
								}
							done = true;
							break;
							}
						}
					}
				if (done)
					{
					break;
					}
				}
			}
		if (done)
			{
			break;
			}
		}
}

// Handle Table of Contents (TOC) width in views. The goal is to keep the
// same TOC width in pixels as much as possible.

function rememberTocWidthPixels() {
	let leftPane = document.getElementById('scrollContentsList'); // TOC column
	if (leftPane === null)
		{
		return;
		}
	let leftPaneWidthStr = window.getComputedStyle(leftPane, null).getPropertyValue('width');
	let widthLeftPane = parseFloat(leftPaneWidthStr);
	let leftPaneWidthKey = thePath + '?' + "leftPaneWidth";
	localStorage.setItem(leftPaneWidthKey, widthLeftPane);
}

// Return width in pixels of table of contents column from localStorage,
// also set localStorage value if that hasn't been done yet.
function getTocWidthPixels() {
	let leftPaneWidthKey = thePath + '?' + "leftPaneWidth";
	let widthLeftPane; // pixels
	if (!localStorage.getItem(leftPaneWidthKey))
		{
		rememberTocWidthPixels(); // sets leftPaneWidthKey in localStorage
		}
	
	let leftPaneWidthStr = localStorage.getItem(leftPaneWidthKey);
	widthLeftPane = parseFloat(leftPaneWidthStr);
	if (widthLeftPane < 50)
		{
		//leftPaneWidthStr = "100.0";
		widthLeftPane = 100.0;
		}
	

	return(widthLeftPane);
}

// Use width in pixels of table of contents column as last save
// to set widths of table of contents and text in percentages.
function restoreColumnWidths() {	
	let leftPane = document.getElementById('scrollContentsList'); // TOC column
	let panesContainer = document.getElementById('scrollAdjustedHeight');
	let paneSep = document.getElementById('panes-separator');
	if (leftPane === null || panesContainer === null || paneSep === null)
		{
		return;
		}

	let widthLeftPane = getTocWidthPixels();
	let panesContainerWidthStr = window.getComputedStyle(panesContainer, null).getPropertyValue('width');
	let widthPanesContainer = parseFloat(panesContainerWidthStr);
	let paneSepWidthStr = window.getComputedStyle(paneSep, null).getPropertyValue('width');
	let paneSepWidth = parseFloat(paneSepWidthStr);
	//let paneSepInfo = paneSep.getBoundingClientRect();
	//let paneSepWidth = paneSepInfo.width;
	let separatorPercent = paneSepWidth / widthPanesContainer * 100;
	let leftPanePC = widthLeftPane / widthPanesContainer * 100;
	leftPane.style.width = leftPanePC + '%';
	let right = (100-leftPanePC-separatorPercent);
	rightPane.style.width = right + '%';

	//TEST ONLY
	// console.log("widthLeftPane: " + widthLeftPane);
	// console.log("panesContainerWidthStr: " + panesContainerWidthStr);
	// //console.log("paneSepWidthStr: " + paneSepWidthStr);
	// console.log("paneSepWidth: " + paneSepWidth);
	// console.log("separatorPercent: " + separatorPercent);
	// console.log("leftPanePC: " + leftPanePC);
	// console.log("right: " + right);
}

function markdownCurrentHeaderID() {
	let currentHeaderID = '';
	let currentHeaderElement = null;
	let el = document.getElementById("scrollTextRightOfContents");
	if (el === null)
		{
		return(currentHeaderID);
		}
	let enclosingRect = el.getBoundingClientRect();
	let enclosingRectTop = enclosingRect.top;
	let enclosingRectBottom = enclosingRect.bottom;
	// Get h1 h2 etc elements.
	let headerNodes = new Array();
	for (let i=1; i<=6; ++i)
		{
		let headers = document.getElementsByTagName('h'+i);
		for (let j = 0; j < headers.length; ++j)
			{
			headerNodes.push(headers[j]);
			}
		}
	
	let highestBottomCeiling = 9999;
	for (let i = 0; i < headerNodes.length; ++i)
		{
		let bounding = headerNodes[i].getBoundingClientRect();
		let bottomCeiling = Math.ceil(bounding.bottom);
		if (bottomCeiling >= enclosingRectTop && bottomCeiling <= enclosingRectBottom)
			{
			if (highestBottomCeiling > bottomCeiling)
				{
				highestBottomCeiling = bottomCeiling;
				currentHeaderElement = headerNodes[i];
				}
			}
		}
	
	if (currentHeaderElement !== null)
		{
		currentHeaderID = currentHeaderElement.id;
		}

	return(currentHeaderID);
}

window.addEventListener("load", function() {
	addTocToggle('tocShrinkExpand');
});
