/**
 * cmMobile.js: handle indicator and Find/Undo/Redo buttons in CodeMirror Editor views, on an iPad.
 * IntraMine's (CodeMirror based) Editor is intramine_editor.pl
 * This is very much an experiment, and I can't recommend editing a
 * file on an iPad unless it's a very small change, fixing a typo for example. Not that it's
 * broken, it's just that too many expected capabilities are missing.
 */

// Find Undo Redo buttons are NOT WORKING. Don't know why.
// For now, I will attempt to use option+z, shift+option+z for undo/redo on iPad.
// Find is hopeless, but browser's built-in Find works somewhat.
// NEEDED, a note that undo is option+z, redo is shift+option+z.
let onMobile = false; // Set below, true if we have touch events.
if (typeof window.ontouchstart !== 'undefined')
	{
	onMobile = true;
	}

let markerMainElement = document.getElementById("scrollTextRightOfContents");
if (markerMainElement === null)
	{
	markerMainElement = document.getElementById("scrollText");
	}

let indicatorElem = document.getElementById('indicator');
let indicatorM = 0;
let lazyMobileScrollIndicator = JD.debounce(scrollMobileIndicator, 100); // Unused
let lazySetUpMobileIndicator = JD.debounce(setUpMobileIndicator, 100);

if (onMobile) // iPad only for now....
	{
	addTouchEndHandler("search-button", showSearch);
	// TEST ONLY
	addClickHandler("search-button", showSearch);
	addTouchEndHandler("undo-button", editorUndo);
	addTouchEndHandler("redo-button", editorRedo);
	lazySetUpMobileIndicator();
	window.addEventListener("resize", lazySetUpMobileIndicator);
	// TEST ONLY, try for quicker updates, "lazy" version is not very responsive:
	myCodeMirror.on("scroll", scrollMobileIndicator);
	// myCodeMirror.on("scroll", lazyMobileScrollIndicator);

	myCodeMirror.on("keypress", handleUndoRedo);

	document.addEventListener("keyup", handleKeyUpForFind, false);
	}
else
	{
	indicatorElem.style.display = 'none';
	hideIt("search-button");
	hideIt("small-tip");
	hideIt("undo-button");
	hideIt("redo-button");
	}

function scrollMobileIndicator() {
	if (!onMobile)
		{
		return;
		}

	if (indicatorM > 0)
		{
		let cmScrollInfo = myCodeMirror.getScrollInfo();
		let mainScrollY = cmScrollInfo.top;
		let rect = markerMainElement.getBoundingClientRect();
		let yTop = rect.top;
		let arrowHeight = 2; // Small gap above and below scroll area.
		let newThumbTop = indicatorM * mainScrollY + yTop + arrowHeight;
		indicatorElem.style.top = newThumbTop + "px";
		}
}

// The indicator is a long rectangle on the right side that indicates scroll position on an iPad.
function setUpMobileIndicator() {
	if (!onMobile)
		{
		return;
		}

	let rect = markerMainElement.getBoundingClientRect();
	let yTop = rect.top;
	let yBottom = rect.bottom;
	let textViewableHeight = yBottom - yTop;
	// Fine-tuning: gray area of scrollbar is shortened by the up and down arrows, and starts
	// after the top arrow. There are no arrows on an iPad.
	let cmScrollInfo = myCodeMirror.getScrollInfo();
	// let clientHeight = cmScrollInfo.clientHeight;
	// let clientWidth = cmScrollInfo.clientWidth;
	// let mainScrollY = cmScrollInfo.top;
	let mainScrolllHeight = cmScrollInfo.height;
	let arrowHeight = 2; // Small gap above and below scroll area.
	let usableTextHeight = textViewableHeight - 2 * arrowHeight;

	let indicatorHeight = (usableTextHeight / mainScrolllHeight) * usableTextHeight;
	indicatorElem.style.height = indicatorHeight + "px";
	indicatorM = (usableTextHeight - indicatorHeight) / (mainScrolllHeight - usableTextHeight);
	scrollMobileIndicator();
}

// option+z (937) for Undo, shift+option+z (184) for Redo.
// That's the best I can do so far.
function handleUndoRedo(cm, evt) {
	// let e1 = document.getElementById(errorID);
	// e1.innerHTML = 'KEYPRESS ' + evt.keyCode;
	if (evt.keyCode === 937)
		{
		evt.preventDefault();
		myCodeMirror.undo();
		maintainButtons();
		}
	else if (evt.keyCode === 184)
		{
		evt.preventDefault();
		myCodeMirror.redo();
		maintainButtons();
		}
}

// This needs a physical keyboard.
function showSearch(e) {
	// CodeMirror.commands.findPersistent(myCodeMirror);
	CodeMirror.commands.find(myCodeMirror);
}

function editorUndo(e) {
	// e.preventDefault();
	// myCodeMirror.focus();
	myCodeMirror.undo();
	maintainButtons();
}

function editorRedo(e) {
	// e.preventDefault();
	// myCodeMirror.focus();
	myCodeMirror.redo();
	maintainButtons();
}

function addTouchEndHandler(id, fn) {
	let el = document.getElementById(id);
	if (el !== null)
		{
		el.addEventListener('touchend', fn, false);
		}
}

function addClickHandler(id, fn) {
	let el = document.getElementById(id);
	if (el !== null)
		{
		el.addEventListener('click', fn, false);
		}
}

function hideIt(id) {
	let el = document.getElementById(id);
	if (el !== null)
		{
		el.style.display = 'none';
		}
}

function showKey(e) {
	console.log("Key: |" + e.key + "|");
}

function handleKeyUpForFind(e) {
	let keyName = e.key;
	if (e.key === 'Enter')
		{
		// CodeMirror.commands.findNext(); // mostly works, but triggers error
		CodeMirror.commands.findPersistentNext(myCodeMirror);
		}
}
