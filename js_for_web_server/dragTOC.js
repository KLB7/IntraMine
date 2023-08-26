// dragTOC.js: drag pane-separator to vary width of Table of Contents.
// localStorage is used to remember and restore the TOC width.
// See also dragTOC.css.
// Used by intramine_viewer.pl.

let leftPane = document.getElementById('scrollContentsList'); // 'left-pane'
let rightPane = document.getElementById('scrollTextRightOfContents'); // 'right-pane'
let panesContainer = document.getElementById('scrollAdjustedHeight'); // 'panes-container'
let paneSep; // 'panes-separator', eventually (see below)
let topLineNumber; // for restoring scrolled position when the separator is dragged.

// This is done in viewerStart.js#reJumpAndHighlight(). Doing it earlier there
// results in a stable first line number for the text.
/////window.addEventListener("load", addDragger);

function addDragger() {
    if (leftPane === null || rightPane === null || panesContainer === null)
        {
        return;
        }
    
    let paneSepString = "<div class='panes-separator' id='panes-separator'></div>";
    let paneSeparator = createElementFromHTML(paneSepString);
    panesContainer.insertBefore(paneSeparator, rightPane);

    paneSep = document.getElementById('panes-separator');
    let panesContainerWidthStr = window.getComputedStyle(panesContainer, null).getPropertyValue('width');
    let widthPanesContainer = parseFloat(panesContainerWidthStr);
    let paneSepWidthStr = window.getComputedStyle(paneSep, null).getPropertyValue('width');
    let paneSepWidth = parseFloat(paneSepWidthStr);
    let separatorPercent = paneSepWidth / widthPanesContainer * 100;
    // Retrieve left pane width from localStorage if possible, else leave width alone.
    let leftPaneWidthKey = thePath + '?' + "leftPaneWidth";
    let leftPaneWidthStr;
    let widthLeftPane;
    let cur;
    if (!localStorage.getItem(leftPaneWidthKey))
        {
        cur = 23; // toc width default is 23%
        widthLeftPane = cur * widthPanesContainer / 100;
        localStorage.setItem(leftPaneWidthKey, widthLeftPane);
        leftPane.style.width = cur + '%';
        }
    else
        {
        leftPaneWidthStr = localStorage.getItem(leftPaneWidthKey);
        widthLeftPane = parseFloat(leftPaneWidthStr);
        cur = widthLeftPane / widthPanesContainer * 100;
        leftPane.style.width = cur + '%';
        }
    
    let right = (100-cur-separatorPercent);
    rightPane.style.width = right + '%';

    paneSep.addEventListener('mousedown', startDraggingSeparator);
}

function separatorMouseUp() {
    window.removeEventListener('mousemove', moveSeparator);
    window.removeEventListener('selectstart', disableSelect);
    document.body.style.cursor = '';

    if (usingCM)
        {
        let rect = myCodeMirror.getWrapperElement().getBoundingClientRect();
        let startPos  = myCodeMirror.lineAtHeight(rect.top, "window");
        scrollTocEntryIntoView(startPos, false, true);

        if (typeof topLineNumber !== 'undefined')
            {
            location.hash = topLineNumber;
            }
        cmQuickRejumpToLine(); // Restores first text line in contents
        }

    // Remember left pane (TOC) width.
    let panesContainerWidthStr = window.getComputedStyle(panesContainer, null).getPropertyValue('width');
    let widthPanesContainer = parseFloat(panesContainerWidthStr);
    let leftPaneStr = leftPane.style.width;
    let leftPanePC = parseFloat(leftPaneStr);
    let leftPanePixels = leftPanePC * widthPanesContainer / 100;
    let leftPaneWidthKey = thePath + '?' + "leftPaneWidth";
    localStorage.setItem(leftPaneWidthKey, leftPanePixels);
    
    // Remove this function from mouseup, otherwise it's called for any mouseup.
    window.removeEventListener('mouseup', separatorMouseUp);
}

// Poke top line number of text into topLineNumber, for restoring scrolled position.
function rememberLocation() {
	if (usingCM)
		{
		let rect = myCodeMirror.getWrapperElement().getBoundingClientRect();
		let myStartLine = myCodeMirror.lineAtHeight(rect.top, "window");
		let lineNumber = parseInt(myStartLine.toString(), 10);
		if (lineNumber > 0)
			{
			lineNumber += 2;
			}
		else
			{
			lineNumber = 1;
			}
        topLineNumber = lineNumber.toString();
		}
	else // text mainly
		{
		let el = document.getElementById(cmTextHolderName);
		let lineNumber = firstVisibleLineNumber(el);
        topLineNumber = lineNumber.toString();
		}
	}

function getFirstVisibleLineNumber() {
    let firstLineNumber = -1;
	if (usingCM)
		{
		let rect = myCodeMirror.getWrapperElement().getBoundingClientRect();
		let myStartLine = myCodeMirror.lineAtHeight(rect.top, "window");
		let lineNumber = parseInt(myStartLine.toString(), 10);
		if (lineNumber > 0)
			{
			lineNumber += 2;
			}
		else
			{
			lineNumber = 1;
			}
        firstLineNumber = lineNumber;
 		}
	else // text mainly
		{
		let el = document.getElementById(cmTextHolderName);
		firstLineNumber = firstVisibleLineNumber(el);
 		}

    return(firstLineNumber);
}

function startDraggingSeparator(e) {
    rememberLocation();
    document.body.style.cursor = 'col-resize';
    window.addEventListener('mousemove', moveSeparator);
    window.addEventListener('selectstart', disableSelect);
    window.addEventListener('mouseup', separatorMouseUp);
}

function moveSeparator(e) {
    let sepLeft = e.clientX - 20;
    let panesContainerWidthStr = window.getComputedStyle(panesContainer, null).getPropertyValue('width');
    let widthPanesContainer = parseFloat(panesContainerWidthStr);

    let leftPanePC = sepLeft / widthPanesContainer * 100;
    if (leftPanePC < 5)
        {
        leftPanePC = 5;
        }
    else if (leftPanePC > 90)
        {
        leftPanePC = 90;
        }
    leftPane.style.width = leftPanePC + '%';
    let paneSepWidthStr = window.getComputedStyle(paneSep, null).getPropertyValue('width');
    let paneSepWidth = parseFloat(paneSepWidthStr);
    let separatorPercent = paneSepWidth / widthPanesContainer * 100;
    let right = (100-leftPanePC-separatorPercent);
    rightPane.style.width = right + '%';

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
        location.hash = topLineNumber;
        reJump();
        }
    else
        {
        //let rect = myCodeMirror.getWrapperElement().getBoundingClientRect();
        //let startPos  = myCodeMirror.lineAtHeight(rect.top, "window") + 2;
        location.hash = topLineNumber;
        myCodeMirror.refresh();
        reJump();
        }
}

function disableSelect(event) {
    event.preventDefault();
}