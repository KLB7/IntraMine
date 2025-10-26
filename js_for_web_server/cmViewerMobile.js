/**
 * cmViewerMobile.js: for the iPad, handle indicator and Find/Undo/Redo buttons. For the Viewer only
 * not the Editor - the Viewer is intramine_viewer.pl.
 * An attempt has been made. An iPad view of a file using IntraMine is "adequate" I suppose,
 * but lacks some bells and whistles. Links work, even image hovers, and the syntax highlighting
 * is there. Find is hopeless, but browser's built-in Find works somewhat.
 */

let indicatorElemMobile = document.getElementById('indicator');
let indicatorM_Mobile = 0;
let lazyMobileScrollIndicator = JD.debounce(scrollMobileIndicator, 100);
let lzySetUpMobileIndicator = JD.debounce(setUpMobileIndicator, 100); // sic, sorry

if (onMobile) // iPad only for now....
	{
	addTouchEndHandler("search-button", showSearch);
	// TEST ONLY
	addClickHandler("search-button", showSearch);
	lzySetUpMobileIndicator();
	window.addEventListener("resize", lzySetUpMobileIndicator);
	myCodeMirror.on("scroll", scrollMobileIndicator);

	// TEST ONLY - triggered for text body, but not Find dialog.
	// myCodeMirror.on('keydown', function(cm, e) {showKey(e); return(false);});

	// TEST ONLY try a shotgun approach.
	// DOES NOT FIRE document.addEventListener("keydown",showKey_keydown,false);
	// DOES NOT FIRE document.addEventListener("keypress",showKey_keypress,false);
	// FIRES document.addEventListener("keyup",showKey_keyup,false);
	// FIRES but NO DETAILS document.addEventListener("textInput",showKey_textInput,false);

	// VERY experimental:
	// myCodeMirror.display.barWidth = 18;

	document.addEventListener("keyup", handleKeyUpForFind, false);
	}
else
	{
	indicatorElemMobile.style.display = 'none';
	hideIt("search-button");
	hideIt("small-tip");
	}

function scrollMobileIndicator() {
	if (!onMobile)
		{
		return;
		}

	if (indicatorM_Mobile > 0)
		{
		let cmScrollInfo = myCodeMirror.getScrollInfo();
		let mainScrollY = cmScrollInfo.top;
		let rect = markerMainElement.getBoundingClientRect();
		let yTop = rect.top;
		let arrowHeight = 2; // Small gap above and below scroll area.
		let newThumbTop = indicatorM_Mobile * mainScrollY + yTop + arrowHeight;
		indicatorElemMobile.style.top = newThumbTop + "px";
		}
}

//The indicator is a long rectangle on the right side that indicates scroll position on an iPad.
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
	indicatorElemMobile.style.height = indicatorHeight + "px";
	indicatorM_Mobile = (usableTextHeight - indicatorHeight) / (mainScrolllHeight - usableTextHeight);
	scrollMobileIndicator();
}

// This needs a physical keyboard.
function showSearch(e) {
	// findPersistent: marks all hits, but highlights are cleared if one clicks in the text.
	// Also, last search phrase is lost if click.
	// CodeMirror.commands.findPersistent(myCodeMirror);
	// find: highlights are not cleared by clicking in the text, have to search for '' to do that.
	// Last search phrase is still remembered after clicking in text. Mostly.
	// CodeMirror.commands.findPersistent(myCodeMirror);
	CodeMirror.commands.find(myCodeMirror);

	// Boy that iOS auto-cap of first letter is annoying.
	turnOffAutoCaps();
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
	let errElem = document.getElementById("editor_error");
	errElem.textContent = "Key: |" + e.key + "|";
	console.log("Key: |" + e.key + "|");
}

function handleKeyUpForFind(e) {
	let keyName = e.key;
	if (e.key === 'Enter')
		{
		// TEST ONLY
		// let errElem = document.getElementById("editor_error");
		// errElem.textContent = "ENTER";
		// console.log("ENTER");

		// CodeMirror.commands.findNext(); // mostly works, but triggers error
		CodeMirror.commands.findPersistentNext(myCodeMirror);

		}
}

// So far no luck....
function turnOffAutoCaps() {
	// let allSearchFields = document.getElementsByClassName("CodeMirror-search-field");
	// //console.log("Num search fields: |" + allSearchFields.length + "|"); => 1
	// let elem = allSearchFields[0];
	// elem.setAttribute("autocorrect", "none");
	// elem.setAttribute("autocapitalize", "none");
	// elem.setAttribute("spellcheck", "false");
}

// document.addEventListener("keydown",showKey_keydown,false);
// document.addEventListener("keypress",showKey_keypress,false);
// document.addEventListener("keyup",showKey_keyup,false);
// document.addEventListener("textInput",showKey_textInput,false);
function showKey_keydown(e) {
	let errElem = document.getElementById("editor_error");
	errElem.textContent = "Key showKey_keydown: |" + e.key + "|";
	console.log("Key showKey_keydown: |" + e.key + "|");
}

function showKey_keypress(e) {
	let errElem = document.getElementById("editor_error");
	errElem.textContent = "Key showKey_keypress: |" + e.key + "|";
	console.log("Key showKey_keypress: |" + e.key + "|");
}

function showKey_keyup(e) {
	let errElem = document.getElementById("editor_error");
	errElem.textContent = "Key showKey_keyup: |" + e.key + "|";
	console.log("Key showKey_keyup: |" + e.key + "|");
}

function showKey_textInput(e) {
	let errElem = document.getElementById("editor_error");
	errElem.textContent = "Key showKey_textInput: |" + e.key + "|";
	console.log("Key showKey_textInput: |" + e.key + "|");
}
