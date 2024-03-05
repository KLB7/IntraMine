// cmAutoLinks.js: insert links automatically in CodeMirror for local and web files,
// and (Viewer only) mentions of headers in the document. Links are done on demand, when new lines
// are scrolled into view.
// Handle clicks on links, too.
// See intramine_linker.pl#CmLinks(), which is called in response to a req=cmLinks
// request. See requestLinkMarkupWithPort() below, which also adds links to internal headers.
// Links are started off here with a call to addAutoLinks(), in response to a scroll, load
// or (for the Editor) and edit.

// Track lines that have been looked at, by line number.
let lineSeen = {};
let linkOrLineNumForText = new Map();

// Remember markers (links), for editor only - in the editor,
// All marks are cleared after an edit (see eg editor.js#onCodeMirrorChange()).
const markers = [];

// Editor only, clear all marks before re-marking the autolinks.
function clearAndAddAutoLinks() {
	clearMarks();
	addAutoLinks();
}

// On "load" or "scroll" add links to visible text. Links can be to a web page, a local file
// (with special handling for local images), or (Viewer only) a mention of some heading in the table of contents.
// Header mentions are done here in JS, for the others we call back to Perl.
// We avoid doing the same line more than once.
function addAutoLinks() {
	
	if (!weAreEditing)
		{
		let tocElement = document.getElementById("scrollContentsList");
		if (tocElement === null)
			{
			return;
			}
		}

	let cm = myCodeMirror;

	// Get line numbers for the first and last visible lines.
	let rect = cm.getWrapperElement().getBoundingClientRect();
	let firstVisibleLineNum = cm.lineAtHeight(rect.top, "window");
	let lastVisibleLineNum = cm.lineAtHeight(rect.bottom, "window");
	
	// Go past the window bottom, sometimes linkage removes so much text
	// that fresh lines come into view. And this makes scrolling smoother.
	// Later: no it doesn't, not with large files. Possibly this has to do
	// with CM not loading lines until they become visible.
	/////lastVisibleLineNum = Math.floor(lastVisibleLineNum * 2.1);
	if (lastVisibleLineNum > cm.doc.lastLine())
		{
		lastVisibleLineNum = cm.doc.lastLine();
		}
	
	// Adjust line range to a block of consecutive lines not seen yet.
	// Note it's possible all have been seen. In that case,
	// firstVisibleLineNum will be equal to lastVisibleLineNum, and in lineSeen.
	let firstLast = adjustedFirstAndLastVisLineNums(firstVisibleLineNum, lastVisibleLineNum);
	firstVisibleLineNum = firstLast[0];
	lastVisibleLineNum = firstLast[1];
	
	let rowIds = []; // For CodeMirror, rowIds are line numbers
	getVisibleRowIds(firstVisibleLineNum, lastVisibleLineNum, rowIds);
	
	// Get the visible text, as one big string with '\n' between lines.
	if (!allLinesHaveBeenSeen(rowIds))
		{
		let visibleText = cm.doc.getRange({
			line : firstVisibleLineNum,
			ch : 0
		}, {
			line : lastVisibleLineNum
		});

		requestLinkMarkup(cm, visibleText, firstVisibleLineNum, lastVisibleLineNum);
		}
}

// Get a Linker port from Main, then call the real "requestLinkMarkup" fn.
async function requestLinkMarkup(cm, visibleText, firstVisibleLineNum, lastVisibleLineNum) {
	try {
		const port = await fetchPort(mainIP, theMainPort, linkerShortName, errorID);
		if (port !== "")
			{
			requestLinkMarkupWithPort(cm, visibleText, firstVisibleLineNum, lastVisibleLineNum, port);
			}
		// else error, reported by fetchPort().
	}
	catch(error) {
		// There was a connection error of some sort
		let e1 = document.getElementById(errorID);
		e1.innerHTML = 'Connection error while attempting to retrieve port number!';
	}
}

// Add link markup to view for newly exposed lines. Remember the lines have been marked up.
async function requestLinkMarkupWithPort(cm, visibleText, firstVisibleLineNum, lastVisibleLineNum, linkerPort) {
	let remoteValue = (weAreRemote)? '1': '0';
	let allowEditValue = (allowEditing)? '1': '0';
	let useAppValue = (useAppForEditing)? '1': '0';

	try {
		let theAction = 'http://' + mainIP + ':' + linkerPort + '/?req=cmLinks'
		+ '&remote=' + remoteValue + '&allowEdit=' + allowEditValue + '&useApp=' + useAppValue
		+ '&text=' + encodeURIComponent(visibleText) + '&peeraddress=' + encodeURIComponent(peeraddress)
		+ '&path=' + encodeURIComponent(thePath) + '&first=' + firstVisibleLineNum + '&last='
		+ lastVisibleLineNum;
		const response = await fetch(theAction);
		if (response.ok)
			{
			let resp = await response.text();
			if (resp != 'nope')
				{
				let jsonResult = JSON.parse(resp);

				for (let ind = 0; ind < jsonResult.arr.length; ++ind)
					{
					let markupArrEntry = jsonResult.arr[ind];
					let len = markupArrEntry["textToMarkUp"].length;

					if (!(markupArrEntry["lineNumInText"] in lineSeen))
						{
						addLinkMarkup(cm, markupArrEntry["lineNumInText"],
								markupArrEntry["columnInText"], len,
								markupArrEntry["linkPath"], markupArrEntry["linkType"],
								markupArrEntry["textToMarkUp"]);
						// Add position of last char to mark, for checking against jsonResults below.
						markupArrEntry["lastColumnInText"] =
								markupArrEntry["columnInText"] + len;
						}
					else
						{
						markupArrEntry["lineNumInText"] = -1; // meaning already seen, skip for internal mentions
						}
					}
				// Mark up mentions of Table of Contents entries, avoiding other links.
				if (!weAreEditing)
					{
					markUpInternalHeaderMentions(cm, visibleText, firstVisibleLineNum,
						lastVisibleLineNum, jsonResult);
					}
				}
			else
				{
				if (!weAreEditing)
					{
					// Maybe there are some TOC mentions, in spite of no file/image/web links.
					let jsonResult = {};
					jsonResult.arr = [];
					markUpInternalHeaderMentions(cm, visibleText, firstVisibleLineNum,
							lastVisibleLineNum, jsonResult);
					}
				}

			// Avoid visiting the same lines twice.
			rememberLinesSeen(firstVisibleLineNum, lastVisibleLineNum);
			}
		else
			{
			// We reached server but it returned an error. Bummer, no links.
			// console.log('Error, requestLinkMarkupWithPort request status: ' + request.status + '!');
			}
	}
	catch(error) {
		// There was a connection error of some sort. Double bummer, no links.
		console.log('requestLinkMarkupWithPort connection error!');
	}
}

// iPad, add poke-a-link handlers. NOT USED.
function addTouchHandlersForLinkMarkup(className) {
	let linkElems = document.getElementsByClassName(className);
	for (let i = 0; i < linkElems.length; ++i)
		{
		let el = linkElems[i];
		el.addEventListener("touchstart", handleFileLinkClicks);
		el.addEventListener("touchend", handleFileLinkMouseUp);
		}
}

function addClickHandlersForLinkMarkup(className) {
	let linkElems = document.getElementsByClassName(className);
	for (let i = 0; i < linkElems.length; ++i)
		{
		let el = linkElems[i];
		el.addEventListener("mousedown", handleFileLinkClicks);
		}
}

// Mark up mentions of headings (typically functions and classes) within our document.
function markUpInternalHeaderMentions(cm, visibleText, firstVisibleLineNum, lastVisibleLineNum, jsonResult) {
	let myLines = visibleText.split("\n");
	let numLines = lastVisibleLineNum - firstVisibleLineNum + 1;
	let actualLineNumber = firstVisibleLineNum;
	for (let ind = 0; ind < numLines; ++ind)
		{
		if (!(actualLineNumber in lineSeen))
			{
			markUpInternalHeadersOnOneLine(cm, myLines[ind], actualLineNumber, jsonResult);
			}
		++actualLineNumber;
		}
}

// See cmTocAnchors.js#getLineNumberForTocEntries() for the filling of lineNumberHasToc etc.
function markUpInternalHeadersOnOneLine(cm, lineText, lineNum, jsonResult) {
	// Avoid lines that already have a TOC entry.
	let tocLineNum = lineNum + 1;
	if (tocLineNum in lineNumberHasToc)
		{
		return;
		}

	// Search for and look at tokens.
	let regex = /([$_~A-Za-z0-9]+)/g;
	if (isCOBOL)
		{
		regex = /([A-Za-z0-9-]+)/g;
		}

	let currentResult = {};
	while ((currentResult = regex.exec(lineText)))
		{
		let tok = currentResult[1];
		let pos = currentResult.index;

		let tokForMethod = tok + "()";
		let haveTocEntry =
				((tok in lineNumberForTocEntry) || (tokForMethod in lineNumberForTocEntry));

		if (haveTocEntry)
			{
			let charEnd = pos + tok.length;
			// If file and internal link text overlap, file wins.
			if (!tokenOverlapsExistingMarkup(lineNum, pos, charEnd, jsonResult))
				{
				let nextCharPos = pos + tok.length;
				let nextChar = (nextCharPos < lineText.length) ? lineText.charAt(nextCharPos) : '';
				let preferFn = (nextChar === "(");
				let tocLineNum = 0;
				if (preferFn && (tokForMethod in lineNumberForTocEntry))
					{
					tocLineNum = lineNumberForTocEntry[tokForMethod];
					}
				else
					{
					tocLineNum =
							(tok in lineNumberForTocEntry) ? lineNumberForTocEntry[tok]
									: lineNumberForTocEntry[tokForMethod];
					}

				addInternalHeaderMarkup(cm, lineNum, tok, pos, tocLineNum);
				}
			}
		}
}

// Return true if range for potential markup overlaps at all with existing markup for
// a file, image, or web link.
function tokenOverlapsExistingMarkup(lineNum, firstCharPos, lastCharPos, jsonResult) {
	let result = false;

	for (let ind = 0; ind < jsonResult.arr.length; ++ind)
		{
		let markupArrEntry = jsonResult.arr[ind];
		if (markupArrEntry["lineNumInText"] == lineNum)
			{
			// Check overlap: either firstCharPos or lastCharPos between
			// markupArrEntry["columnInText"] and markupArrEntry["lastColumnInText"]
			if (firstCharPos >= markupArrEntry["columnInText"]
					&& firstCharPos <= markupArrEntry["lastColumnInText"])
				{
				result = true;
				}
			else if (lastCharPos >= markupArrEntry["columnInText"]
					&& lastCharPos <= markupArrEntry["lastColumnInText"])
				{
				result = true;
				}
			// else no overlap.
			}
		}

	return (result);
}

// Add <span onclick=goToAnchor(...)> markup around mentions of table of contents items.
function addMobileInternalHeaderMarkup(cm, lineNum, tok, pos, tocLineNum) {
	let nameOfCSSclass = 'cmInternalLink';
	let displayedTok = tok;
	let charEndAddition = 0;
	let displayedPos = pos;
	
	// Shorten link overlay to expose first and last char. Or two at each end if enough text.
	// That way, if text is highlighted the highlight will show through at the start and end.
	// Out for the moment.
	if (0)
		{
		if (displayedTok.length >= 4)
			{
			displayedTok = displayedTok.substring(1);
			displayedTok = displayedTok.substring(0, displayedTok.length - 1);
			displayedPos += 1;
			charEndAddition += 1;
			}
		if (displayedTok.length >= 6)
			{
			displayedTok = displayedTok.substring(1);
			displayedTok = displayedTok.substring(0, displayedTok.length - 1);
			displayedPos += 1;
			charEndAddition += 1;
			}
		}

	let ank = document.createElement("span");
	let ankText = document.createTextNode(displayedTok);
	ank.appendChild(ankText);
	ank.setAttribute("class", nameOfCSSclass);
	let gotoJS = 'goToAnchor("' + tok + '", ' + tocLineNum + ');';
	ank.setAttribute("onclick", gotoJS);
	let charEnd = pos + displayedTok.length + charEndAddition;

	myCodeMirror.doc.markText({
		line : lineNum,
		ch : displayedPos
	}, {
		line : lineNum,
		ch : charEnd
	}, {
		className : nameOfCSSclass,
		replacedWith : ank
	});
}

// Add <span onclick=goToAnchor(...)> markup around mentions of table of contents items.
function addInternalHeaderMarkup(cm, lineNum, tok, pos, tocLineNum) {
	if (onMobile)
		{
		addMobileInternalHeaderMarkup(cm, lineNum, tok, pos, tocLineNum);
		return;
		}
	let nameOfCSSclass = "cmInternalLink";
	let charEnd = pos + tok.length;
	myCodeMirror.doc.markText({
		line : lineNum,
		ch : pos
	}, {
		line : lineNum,
		ch : charEnd
	}, {
		className : nameOfCSSclass
	});
	// Track link for later use.
	linkOrLineNumForText.set(tok, tocLineNum);
}

// Add <a> links for local files, images, and web pages.
function addLinkMarkup(cm, lineNum, chStart, len, rep, linkType, markerText) {
	let nameOfCSSclass = "cmAutoLink";

	if (linkType === "image")
		{
		nameOfCSSclass = "cmAutoLinkImg";
		}
	else if (linkType === "web")
		{
		nameOfCSSclass = "cmAutoLinkNoEdit";
		}
	else if (linkType === "video")
		{
		nameOfCSSclass = "cmAutoLinkVideo";
		}
	else if (linkType === "directory")
		{
		nameOfCSSclass = "cmAutoLinkDirectory";
		}
	else if (linkType === "glossary")
		{
		nameOfCSSclass = "cmAutoLinkGlossary";
		}

	let charEnd = chStart + len;

	if (onMobile)
		{
		let useASpan = false;
		if (nameOfCSSclass === "cmAutoLink" || nameOfCSSclass === "cmAutoLinkImg")
			{
			// cmAutoLink and cmAutoLinkImg classes have :before/:after css showing
			// images. Those images are imbedded in the markText "ank" overlays for mobile, so we
			// use different class names to avoid duplicated pencils (edit) and birds (image).
			if (nameOfCSSclass === "cmAutoLink")
				{
				nameOfCSSclass = 'cmAutoLinkMobile';
				}
			else if (nameOfCSSclass === "cmAutoLinkImg")
				{
				nameOfCSSclass = 'cmAutoLinkImgMobile';
				}
			let hrefMatch = /href\=\"([^"]+)\"/.exec(rep);
			if (hrefMatch !== null)
				{
				let href = hrefMatch[1];
				let hrefMatch2 = /href\=(.+)$/.exec(href);
				if (hrefMatch2 !== null)
					{
					let href2 = hrefMatch2[1];
					href2 = href2.replace(/\%25/g, "%");
					let indexOfHash = -1;
					if ((indexOfHash = href2.indexOf('#')) > 0)
						{
						let pathBeforeHash = href2.substring(0, indexOfHash);
						let pathAfterHash = href2.substring(indexOfHash + 1);
						pathBeforeHash = encodeURIComponent(pathBeforeHash);
						pathAfterHash = encodeURI(pathAfterHash);
						href2 = pathBeforeHash + '#' + pathAfterHash;
						}
					else
						{
						href2 = encodeURIComponent(href2);
						}

					let href2Enc = href2;

					href2 = href.replace(/href\=(.+)$/, 'href=' + href2Enc);
					rep = rep.replace(/href\=\"([^"]+)\"/, 'href="' + href2 + '"');
					}
				}

			useASpan = true;
			}

		let ank =
				useASpan ? createSpanElementFromHTML(rep, nameOfCSSclass)
						: createElementFromHTML(rep);
		myCodeMirror.doc.markText({
			line : lineNum,
			ch : chStart
		}, {
			line : lineNum,
			ch : charEnd
		}, {
			className : nameOfCSSclass,
			replacedWith : ank
		});
		}
	else
		{
		markers.push(myCodeMirror.doc.markText({
			line : lineNum,
			ch : chStart
		}, {
			line : lineNum,
			ch : charEnd
		}, {
			className : nameOfCSSclass
		}));
		}

	// Track link for later use.
	linkOrLineNumForText.set(markerText, rep);
}

// For a touch or click, return link type and associated CodeMirror class for the link.
// File (non-image), image, web, and internal header links have different handling.
function typeAndClass(target, checkForIMG) {
	let linkType = '';
	let className = '';

	if (hasClass(target, "cmAutoLink"))
		{
		linkType = "file";
		className = "cmAutoLink";
		}
	else if (hasClass(target, "cmAutoLinkVideo"))
		{
		linkType = "video";
		className = "cmAutoLinkVideo";
		}
	else if (hasClass(target, "cmAutoLinkDirectory"))
		{
		linkType = "directory";
		className = "cmAutoLinkDirectory";
		}
	else if (hasClass(target, "cmAutoLinkMobile"))
		{
		linkType = "file";
		className = "cmAutoLinkMobile";
		}
	else if (hasClass(target, "cmAutoLinkImg"))
		{
		linkType = "image";
		className = "cmAutoLinkImg";
		}
	else if (hasClass(target, "cmAutoLinkImgMobile"))
		{
		linkType = "image";
		className = "cmAutoLinkImgMobile";
		}
	else if (hasClass(target, "cmAutoLinkNoEdit"))
		{
		linkType = "web";
		className = "cmAutoLinkNoEdit";
		}
	else if (hasClass(target, "cmInternalLink"))
		{
		linkType = "internal";
		className = "cmInternalLink";
		}
	else if (checkForIMG && target.nodeName === "IMG") // A click on a "hover" image on mobile device.
		{
		linkType = "file";
		className = "cmAutoLink";
		}
	// glossary, return linkType "" since it doesn't respond to clicks.
	return {theType: linkType, theClass: className};
}

// For the iPad, handle touch events. If a link is being fired, try to preserve
// user's text selection, if any.
function cmHandleTouch(cm, evt) {
	let target = evt.target;
	//let targetName = target.nodeName;
	if (target.nodeName === "A")
		{
		let targetParent = target.parentNode;
		if (targetParent !== null
				&& (hasClass(targetParent, "cmAutoLink") || hasClass(targetParent,
						"cmAutoLinkMobile")))
			{
			target = targetParent;
			}
		}
	else if (target.nodeName === "IMG")
		{
		let targetParent = target.parentNode;
		if (targetParent !== null)
			{
			if (targetParent !== null
					&& (hasClass(targetParent, "cmAutoLink") || hasClass(targetParent,
							"cmAutoLinkMobile")))
				{
				target = targetParent;
				}
			else
				{
				let targetGrandParent = targetParent.parentNode;
				if (targetGrandParent !== null
						&& (hasClass(targetGrandParent, "cmAutoLink") || hasClass(
								targetGrandParent, "cmAutoLinkMobile")))
					{
					target = targetGrandParent;
					}
				}
			}
		}
	
	let typeClass = typeAndClass(target, true); // true == check for IMG
	let linkType = typeClass.theType;
	let className = typeClass.theClass;
	let forEdit = false;

	if (linkType !== "")
		{
		// Note anchor (ie link) clicks, in an attempt to suppress highlighting changes for clicks in TOC.
		anchorClicked = true;
		// Restore user selection, so highlighting doesn't change when link is clicked.
		// if (cmCursorStartPos.line > 0 && !(onMobile && linkType === "internal"))
		if (cmCursorStartPos.line >= 0)
			{
			myCodeMirror.setSelection(cmCursorStartPos, cmCursorEndPos, {
				scroll : false
			});
			}
		}
}

// iPad, restore user selection, so highlighting doesn't change when link is clicked.
function cmMobileHandleImgTouch(evt) {
	anchorClicked = true;
	
	// if (cmCursorStartPos.line > 0 && !(onMobile && linkType === "internal"))
	if (cmCursorStartPos.line >= 0)
		{
		setTimeout(function() {
			myCodeMirror.setSelection(cmCursorStartPos, cmCursorEndPos, {
				scroll : false
			});
		}, 800);
		// myCodeMirror.setSelection(cmCursorStartPos, cmCursorEndPos, {scroll: false});
		}
}

// If a link was clicked, immediately fire it off, first restoring user selection so that
// highlighting doesn't change. If not a link, no worries, nothing needed here. But see
// handleFileLinkMouseUp just below where user selection is saved when click is not over link.
function handleFileLinkClicks(evt) {
	let target = evt.target;
	let typeClass = typeAndClass(target, false); // false == don't check for IMG
	let linkType = typeClass.theType;
	let className = typeClass.theClass;
	let forEdit = false;

	if (linkType !== "")
		{
		// If click is within 15 of right edge, it is in the edit "pencil" image.
		if (linkType === "file")
			{
			let pencilLeft = target.offsetLeft + target.offsetWidth - 15;
			if (evt.offsetX >= pencilLeft)
				{
				forEdit = true;
				}
			}

		// Note anchor clicks, in an attempt to suppress highlighting changes for clicks in TOC.
		anchorClicked = true;
		// Restore user selection, so highlighting doesn't change when link is clicked.
		if (!weAreEditing && cmCursorStartPos.line >= 0)
			{
			myCodeMirror.setSelection(cmCursorStartPos, cmCursorEndPos, {
				scroll : false
			});
			}

		// Off we go, not waiting for the mouse up.
		fireOneLink(target, linkType, className, forEdit);
		}
}

// Get current selection if a link was not clicked.
// In the Viewer only, for a single click the selection is expanded to a word.
function handleFileLinkMouseUp(evt) {
	let target = evt.target;
	let typeClass = typeAndClass(target, false); // false == don't check for IMG
	let linkType = typeClass.theType;
	//let className = typeClass.theClass;
	
	if (!weAreEditing && linkType === "" && !goingToAnchor)
		{
		// If nothing selected, expand selection to any word under the cursor.
		// Removed, CM does this already - see cmViewerStart.js#245 or so.
		//expandEmptySelectionToWord();

		// Get current selection (for restoration later if a link is clicked).
		let startPos = myCodeMirror.doc.getCursor("anchor");
		cmCursorStartPos = startPos;
		cmCursorEndPos = myCodeMirror.doc.getCursor("head");
		}
	
	// Reset goingToAnchor - it was used here to avoid setting the selection if goingToAnchor,
	// because goToAnchor() will restore the selection after jumping to the anchor.
	goingToAnchor = false;

	// Clear any remembered line number for table of contents use.
	setTimeout(function() {
        clearLineNumberForToc();
        }, 500);
}

// Expand selection to any word under the cursor.
function expandEmptySelectionToWord() {
	let selText = myCodeMirror.doc.getSelection();
	if (selText !== '' || weAreEditing)
		{
		return;
		}
	let startPos = myCodeMirror.doc.getCursor("anchor");
	let lineText = myCodeMirror.doc.getLine(startPos.line);
	if (lineText === '')
		{
		return;
		}
	
	// Expand selection to left.
	let charAtPos = lineText.charAt(startPos.ch); // char just to right of insertion pt
	let chartAtStart = lineText.charAt(0);
	let nextAfterStart = lineText.charAt(1);
	let charBefore = lineText.charAt(startPos.ch-1);
	
	let idx = startPos.ch;
	let lookRightOnly = (idx == 0 || isW(lineText.charAt(idx-1)));
	let lookLeftOnly = (idx >= lineText.length || isW(lineText.charAt(idx))); // isW.js
	let newStartPos = startPos.ch;
	if (!lookRightOnly)
		{
		--idx;
		while (idx >= 0 && !isW(lineText.charAt(idx)))
			{
			--idx;
			}
		newStartPos = idx+1;
		}
	
	// Expand selection to right.
	let newEndPos = startPos.ch;
	if (!lookLeftOnly)
		{
		idx = newEndPos;
		while (idx < lineText.length && !isW(lineText.charAt(idx)))
			{
			++idx;
			}
		newEndPos = idx;
		}

	// Update CM to select the word.
	if (newStartPos !== startPos || newEndPos !== startPos)
		{
		if (newStartPos < 0)
			{
			newStartPos = 0;
			}
		if (newEndPos > lineText.length)
			{
			newEndPos = lineText.length;
			}
		let anchor = {line: startPos.line, ch: newStartPos};
		let head = {line: startPos.line, ch: newEndPos};
		myCodeMirror.setSelection(anchor, head, {
			scroll : false
		});
		}
	
}

// For a click in text, scroll closest corresponding Table of Contents item that's at or
// above the clicking line into view.
function synchTableOfContents(evt) {
	let startPos = 0;
	let inContent = inCodeMirrorText(evt);
	if (inContent)
		{
		startPos = myCodeMirror.doc.getCursor("anchor").line;
		}
	else
		{
		let rect = myCodeMirror.getWrapperElement().getBoundingClientRect();
		startPos = myCodeMirror.lineAtHeight(rect.top, "window") + 2;
		}
	
	scrollTocEntryIntoView(startPos + 1, inContent, false);
}

function inCodeMirrorText(evt) {
	let result = true;
	let target = evt.target;
	
	if ( hasClass(target, "CodeMirror-vscrollbar")
	  || hasClass(target, "CodeMirror-hscrollbar") )
		{
		result = false;
		}

	
	return(result);
	}

// Dispatch of link handling, based on link type (file (non-image), image, web, internal link).
function fireOneLink(target, linkType, className, forEdit) {
	let targetText = target.textContent;
	if (targetText === "")
		{
		return;
		}
	// Look ahead and behind for siblings with class "cmAutoLink".
	let sib = target.nextSibling;
	while (sib !== null)
		{
		if (hasClass(sib, className))
			{
			targetText = targetText + sib.textContent;
			sib = sib.nextSibling;
			}
		else
			{
			break;
			}
		}
	sib = target.previousSibling;
	while (sib !== null)
		{
		if (hasClass(sib, className))
			{
			targetText = sib.textContent + targetText;
			sib = sib.previousSibling;
			}
		else
			{
			break;
			}
		}

	// <a href="http://192.168.1.132:81/Viewer/?href=c:/perlprogs/mine/data/swarmserver.txt" target
	// ="_blank">swarmserver.txt</a>... - file
	// <a href='http://www.qt.io/licensing/' target='_blank'>http://www.qt.io/licensing/</a> - web
	// <a href='http://192.168.1.132:81/Viewer/?href=c:/perlprogs/mine/images_for_web_server/ser
	// ver-128x128 60.png' target='_blank' onmouseover=... - image

	let linkPath = linkOrLineNumForText.get(targetText);

	if (typeof linkPath !== 'undefined')
		{
		if (linkType === "file")
			{
			let serviceName = '';
			if (forEdit)
				{
				serviceName = editorShortName;
				}
			else
				{
				serviceName = viewerShortName;
				}
			fireOneFileLink(linkPath, forEdit, serviceName);
			}
		else if (linkType === "video")
			{
			fireOneFileLink(linkPath, forEdit, videoShortName);
			}
		else if (linkType === "directory")
			{
			fireOneDirectoryLink(linkPath);
			}
		else if (linkType === "image")
			{
			fireOneImageLink(linkPath, className);
			}
		else if (linkType === "web")
			{
			fireOneWebLink(linkPath);
			}
		else if (linkType === "internal")
			{
			fireOneInternalLink(targetText, linkPath);
			}
		}
}

// <a href="http://192.168.1.132:81/Viewer/?href=c:/perlprogs/mine/data/swarmserver.txt"
// target="_blank">swarmserver.txt</a>... - file
// Link can be for view only or for editing. Dispatch accordingly to other JS functions.
// Added later, link can be for a video in which case serviceName is videoShortName.
function fireOneFileLink(linkPath, forEdit, serviceName) {
	// Encode the linkPath
	let hrefMatch = /href\=\"([^"]+)\"/.exec(linkPath);
	if (hrefMatch !== null)
		{
		let href = hrefMatch[1];
		let hrefMatch2 = /href\=(.+)$/.exec(href);
		if (hrefMatch2 !== null)
			{
			let href2 = hrefMatch2[1];
			let indexOfHash = -1;
			if ((indexOfHash = href2.indexOf('#')) > 0)
				{
				let pathBeforeHash = href2.substring(0, indexOfHash);
				let pathAfterHash = href2.substring(indexOfHash + 1);
				pathBeforeHash = encodeURIComponent(pathBeforeHash);
				pathAfterHash = encodeURI(pathAfterHash);
				href2 = pathBeforeHash + '#' + pathAfterHash;
				}
			else
				{
				href2 = encodeURIComponent(href2);
				}

			let href2Enc = href2;

			if (serviceName === videoShortName)
				{
				let hrefEnc = href.replace(/href\=(.+)$/, 'href=' + href2Enc);
				fireOneViewerLink(hrefEnc, serviceName);
				}

			else if (forEdit)
				{
				if (allowEditing)
					{
					if (useAppForEditing)
						{
						editWithPreferredApp(href2Enc);
						}
					else
						{
						editWithIntraMine(href2Enc);
						}
					}
				// else maintenance error, shouldn't get here if editing is not wanted
				}
			else
				{
				let hrefEnc = href.replace(/href\=(.+)$/, 'href=' + href2Enc);
				//window.open(hrefEnc, "_blank");
				// Replace the "81" with a good Viewer port, call window.open().
				fireOneViewerLink(hrefEnc, serviceName);
				}
			}
		}
}

function fireOneViewerLink(href, serviceName) {
	openView(href, serviceName); // See viewerLinks.js#openView()
}

// linkPath: |<a href="c:/perlprogs/intramine/docs/" onclick="openDirectory(this.href); return false;">"docs"</a>|
function fireOneDirectoryLink(linkPath) {
	let hrefMatch = /href\=\"([^"]+)\"/.exec(linkPath);
	if (hrefMatch !== null)
		{
		let href = hrefMatch[1];
		href = encodeURIComponent(href);
		openDirectory(href); // viewerLinks.js#openDirectory()
		}
}

//Open image in a new browser tab.
// <a href='http://192.168.1.132:81/Viewer/?href=c:/perlprogs/mine/images_for_web_server/ser
// ver-128x128 60.png' target='_blank' onmouseover=... - image
function fireOneImageLink(linkPath, className) {
	let hrefMatch = /href\=\"([^']+)\"/.exec(linkPath);
	if (hrefMatch !== null)
		{
		let href = hrefMatch[1];
		let hrefMatch2 = /href\=(.+)$/.exec(href);
		if (hrefMatch2 !== null)
			{
			let href2 = hrefMatch2[1];
			href2 = href2.replace(/\%25/g, "%");
			let href2Enc = encodeURIComponent(href2);
			let hrefEnc = href.replace(/href\=(.+)$/, 'href=' + href2Enc);
			window.open(hrefEnc, "_blank");
			}
		}

}

// Open a web link in a new tab.
// <a href='http://www.qt.io/licensing/' target='_blank'>http://www.qt.io/licensing/</a> - web
function fireOneWebLink(linkPath) {
	let hrefMatch = /href\=\'([^']+)\'/.exec(linkPath);
	if (hrefMatch !== null)
		{
		let hrefProper = hrefMatch[1];
		window.open(hrefProper, "_blank");
		}
}

// Scroll to a header in the same file.
function fireOneInternalLink(targetText, lineNum) {
	goToAnchor(targetText, lineNum); // cmTocAnchors.js#goToAnchor().
}

// Show popup of image if we're over class "cmAutoLinkImg".
function handleMouseOver(e) {
	let className = "cmAutoLinkImg";
	let classNameGlossary = "cmAutoLinkGlossary";
	let target = e.target;
	if (hasClass(target, className) || hasClass(target, classNameGlossary))
		{
		let targetText = target.textContent;
		if (targetText === "")
			{
			return;
			}
		// Look ahead and behind for siblings with class "cmAutoLinkImg".
		let sib = target.nextSibling;
		while (sib !== null)
			{
			if (hasClass(sib, className))
				{
				targetText = targetText + sib.textContent;
				sib = sib.nextSibling;
				}
			else
				{
				break;
				}
			}
		sib = target.previousSibling;
		while (sib !== null)
			{
			if (hasClass(sib, className))
				{
				targetText = sib.textContent + targetText;
				sib = sib.previousSibling;
				}
			else
				{
				break;
				}
			}

		let linkPath = linkOrLineNumForText.get(targetText);
		if (typeof linkPath !== 'undefined')
			{
			callShowHint(e, target, linkPath);
			}
		}
}

// Look in linkPath for
// "showhint('<img src=&quot;http://192.168.1.132:81/c:/perlprogs/mine/images_for_web_server/ser
// ver-128x128 60.png&quot;>', this, event, '500px', true);"
// Call showhint() to pop up a (possibly reduced) view of the image.
function callShowHint(e, target, linkPath) {
	callShowHintWithCorrectPort(e, target, linkPath);
}

function callShowHintWithCorrectPort(e, target, linkPath) {
	// Pull args for showhint() and call it.
	let showHintMatch =
			/showhint\(\'([^\']+)\',\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*([^\)]+)\);\"\>/
					.exec(linkPath);
	if (showHintMatch === null)
		{
		showHintMatch =
				/showhint\(\'([^\']+)\',\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*([^\)]+)\);\"\>/
						.exec(linkPath);
		}
	if (showHintMatch !== null)
		{
		let hintContent = showHintMatch[1];
		let thismatch = showHintMatch[2];
		let evyMatch = showHintMatch[3];
		let widthMatch = showHintMatch[4];
		let isImgMatch = showHintMatch[5];
		let shouldDecodeMatch = showHintMatch[6];
		if (shouldDecodeMatch === null)
			{
			shouldDecodeMatch = false;
			}

		if (shouldDecodeMatch)
			{
			hintContent = decodeURIComponent(hintContent);
			}
		hintContent = hintContent.replace(/&quot;/g, '"');
		hintContent = updatePortInHintContent(hintContent);
		widthMatch = widthMatch.replace(/'/g, ""); // get rid of single quotes
		if (shouldDecodeMatch)
			{
			hintContent = encodeURIComponent(hintContent);
			}
		
		showhint(hintContent, target, e, widthMatch, isImgMatch, shouldDecodeMatch); // tooltip.js#showhint()
		}
	// else
	// 	{
	// 	console.log("showHintMatch is null!");
	// 	}
}

// Change http://mainIP:theMainPort/Viewer to http://mainIP:port everywhere.
// Strip the short server name (eg Viewer or Editor), it's not wanted.
function updatePortInHintContent(hintContent) {
	// TEST ONLY
	return(hintContent);
	
	//testPortUpdate(ourSSListeningPort);

	const regex = new RegExp("http://" + mainIP + ":" + theMainPort + "\/[^\/]+", "g");
	hintContent = hintContent.replace(regex, "http://" + mainIP + ":" + ourSSListeningPort);
	//hintContent = hintContent.replace(regex, "http://" + mainIP + ":" + port);
	return(hintContent);
}

function testPortUpdate(port) {
	console.log("Main IP: " + mainIP);
	console.log("The main port: " + theMainPort);
	console.log("Viewer port: " + port);
	let testStr = '<img src="http://192.168.40.8:81/Viewer/c:/common/images/2016-06-29 18_27_10-ouray mine shaft close full (760×570) -%2520 too.png">';
	console.log("testStr BEFORE: |" + testStr + "|");
	const regex = new RegExp("http://" + mainIP + ":" + theMainPort + "\/[^\/]+", "g");
	testStr = testStr.replace(regex, "http://" + mainIP + ":" + ourSSListeningPort);
	//testStr = testStr.replace(regex, "http://" + mainIP + ":" + port);
	//testStr = testStr.replace(/http\:\/\/mainIP\:theMainPort/g, "http://" + mainIP + ":" + port);
	console.log("testStr AFTER: |" + testStr + "|");
}

function createElementFromHTML(htmlString) {
	let div = document.createElement('div');
	div.innerHTML = htmlString.trim();

	// Change this to div.childNodes to support multiple top-level nodes
	return div.firstChild; // or div.firstElementChild?
}

function createSpanElementFromHTML(htmlString, spanClassName) {
	let div = document.createElement('div');
	htmlString = "<span class='" + spanClassName + "'>" + htmlString.trim()
	+"</span>";
	div.innerHTML = htmlString;

	// Change this to div.childNodes to support multiple top-level nodes
	return div.firstChild; // or div.firstElementChild?
}

// Links are inserted only when lines become visible, and we want to avoid doing
// the same line twice, so we track all line numbers when inserting links.
function rememberLinesSeen(firstVisibleLineNum, lastVisibleLineNum) {
	for (let lineNumber = firstVisibleLineNum; lineNumber <= lastVisibleLineNum; ++lineNumber)
		{
		lineSeen[lineNumber] = 1;
		}
}

// Trim lines seen from beginning and end of first/last range.
function adjustedFirstAndLastVisLineNums(firstVisibleLineNum, lastVisibleLineNum) {
	let adjustedFirst = firstVisibleLineNum;
	let adjustedLast = lastVisibleLineNum;
	for (let lineNum = firstVisibleLineNum; lineNum <= lastVisibleLineNum; ++lineNum)
		{
		if (lineNum in lineSeen)
			{
			adjustedFirst = lineNum;
			}
		else
			{
			break;
			}
		}
		
	for (let lineNum = lastVisibleLineNum; lineNum >= firstVisibleLineNum; --lineNum)
		{
		if (lineNum in lineSeen)
			{
			if (lineNum >= adjustedFirst)
				{
				adjustedLast = lineNum;
				}
			}
		else
			{
			break;
			}
		}
		
	return [adjustedFirst, adjustedLast];
}

// Remove all mark-related data. For editor only.
function clearMarks() {
	markers.forEach(marker => marker.clear());
	//lineSeen = {};
	for (var member in lineSeen)
		{
		if (lineSeen.hasOwnProperty(member))
			{
			delete lineSeen[member];
			}
		}
	linkOrLineNumForText.clear();
}

function getVisibleRowIds(firstVisibleLineNum, lastVisibleLineNum, rowIds) {
	for (let row = firstVisibleLineNum; row <= lastVisibleLineNum; ++row)
		{
		rowIds.push(row);
		}
}

function allLinesHaveBeenSeen(rowIds) {
	for (let ind = 0; ind < rowIds.length; ++ind)
		{
		if (!(rowIds[ind] in lineSeen))
			{
			return (false);
			}
		}

	return (true);
}