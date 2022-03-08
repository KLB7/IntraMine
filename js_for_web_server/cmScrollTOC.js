/**
 * cmScrollTOC.js: when a heading is clicked in text, scroll corresponding Table of Contents
 * entry into view.
 */

// Scroll the Table of Contents:
// if click was in text content, to heading at or just before line clicked.
// if scrolling, to heading at or just after first visible line.
function scrollTocEntryIntoView(lineNum, inContent, scrolling) {
	let tocElem = null;
	
	if (inContent)
		{
		tocElem = getTocElemForLineNumber(lineNum); // cmTocAnchors.js#getTocElemForLineNumber()
		}
//	else // mouse or touch in scroll - ignore, "scrolling" handles that
//		{
//		tocElem = getTocElemAfterLineNumber(lineNum); // cmTocAnchors.js#getTocElemAfterLineNumber()
//		}
	else if (scrolling)
		{
		let el = document.getElementById(cmTextHolderName);
		let limitLineNum = lastVisibleLineNumber(el);
		tocElem = getTocElemAfterLineNumber(lineNum, limitLineNum); // cmTocAnchors.js#getTocElemAfterLineNumber()
		if (tocElem === null)
			{
			tocElem = getTocElemForLineNumber(lineNum);
			}
		}
	
	if (tocElem !== null)
		{
		tocElem.scrollIntoView();
		//tocElem.scrollIntoView({block: 'center'});
		updateTocHighlight(tocElem);
		}
}

//https://gomakethings.com/detecting-when-a-visitor-has-stopped-scrolling-with-vanilla-javascript/
let scrollingForToc = null;
function addTocScrollListener() {
	myCodeMirror.on("scroll", function() {
		
		// Clear our timeout throughout the scroll
		window.clearTimeout( scrollingForToc );
	
		// Set a timeout to run after scrolling ends
		scrollingForToc = setTimeout(function() {
			// Run the callback
			let rect = myCodeMirror.getWrapperElement().getBoundingClientRect();				
			startPos  = myCodeMirror.lineAtHeight(rect.top, "window") + 2;
			scrollTocEntryIntoView(startPos, false, true);
		}, 66);
	});
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
