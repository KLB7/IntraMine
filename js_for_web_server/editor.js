// editor.js: CodeMirror handling for Edit views. Used in:
// intramine_editor.pl.
// Load, Save file, manage content resizing.
// March 2022, autolinks are now supported.

let debouncedAddLinks; // See makeDebouncedClearAddLinks() at bottom.
let firstMaintainButtonsCall = true;

// Borrowed from cmViewerStart.js, just so the Toggle button will work.
//let anchorClicked = false;
let cmCursorStartPos = {
	line : -1,
	ch : -1
};
let cmCursorEndPos = {
	line : -1,
	ch : -1
};

let cursorFileStartPos = {
	line: 0,
	ch: 0,
};

let cursorFileEndPos = {
		line: 0,
		ch: 1,
	};

cmCursorStartPos = cursorFileStartPos;
cmCursorEndPos = cursorFileEndPos;

function getFileExtension(filename) {
	let result = '';
	let extMatch = /\.(\w+)$/.exec(filename);
	if (extMatch !== null)
		{
		result = extMatch[1];
		}
	return (result);
}

function hasClass(el, className) {
	if (el === null || el.nodeName === "#TEXT" || el.nodeName === "#text")
		{
		return false;
		}
	if (el.classList)
		return el.classList.contains(className);
	else
	return(typeof el.className !== 'undefined' && !!el.className.match(new RegExp('(\\s|^)' + className + '(\\s|$)')));
}

function addClass(el, className) {
	if (el !== null)
		{
		if (el.classList)
			el.classList.add(className);
		else if (!hasClass(el, className))
			el.className += " " + className;
		}
}

function removeClass(el, className) {
	if (el !== null)
		{
		if (el.classList)
			el.classList.remove(className);
		else if (hasClass(el, className))
			{
			let reg = new RegExp('(\\s|^)' + className + '(\\s|$)');
			el.className = el.className.replace(reg, ' ');
			}
		}
}

function removeElementsByClass(className) {
	let elements = document.getElementsByClassName(className);
	while (elements.length > 0)
		{
		elements[0].parentNode.removeChild(elements[0]);
		}
}

window.addEventListener("load", reJump);
window.addEventListener("load", makeDebouncedClearAddLinks);
window.addEventListener("resize", JD.debounce(doResize, 100)); // swarmserver.pm#TooltipSource()

function doResize() {
	let rule = document.getElementById("rule_above_editor");
	let pos = getPosition(rule);
	let rect = rule.getBoundingClientRect();
	let ruleHeight = rect.height;

	let windowHeight = window.innerHeight;
	let elHeight = windowHeight - pos.y - ruleHeight - 8;
	// let elHeight = windowHeight - pos.y - 16;
	let newHeightPC = (elHeight / windowHeight) * 100;
	let el = document.getElementById("scrollAdjustedHeight");
	el.style.height = newHeightPC + "%";

	let tocMainElement = document.getElementById("scrollContentsList");
	if (tocMainElement !== null)
		{
		let tocMarginTop =
				parseInt(window.getComputedStyle(tocMainElement).getPropertyValue('margin-top'));
		let tocHeight = elHeight - tocMarginTop;
		if (typeof window.ontouchstart !== 'undefined') // onMobile
			{
			tocHeight -= 20;
			}
		let newTocHeightPC = (tocHeight / elHeight) * 100;
		tocMainElement.style.height = newTocHeightPC + "%";
		}
}

// TODO For the viewer mainly, this needs to go to a line number, not an element.
function reJump() {
	return;
	let h = location.hash;
	if (h.length > 1)
		{
		// strip leading '#'
		h = h.replace(/^#/, '');

		let el = document.getElementById(h);
		if (el !== null)
			{
			el.scrollIntoView();
			}
		}
}

function setTextViewPosition(rule_id, id) {
	let rule = document.getElementById(rule_id);
	let pos = getPosition(rule);
	let rect = rule.getBoundingClientRect();
	let ruleHeight = rect.height;
	let el = document.getElementById(id);
	let yPos = pos.y + ruleHeight + 8;
	el.style.top = yPos + "px";
}

function positionViewItems() {
	setTextViewPosition("rule_above_editor", cmTextHolderName);
	doResize();
}


let sve = document.getElementById("save-button");
addClass(sve, 'disabled-submit-button');
let btn = document.getElementById("undo-button");
addClass(btn, 'disabled-submit-button');
btn = document.getElementById("redo-button");
addClass(btn, 'disabled-submit-button');

setTextViewPosition("rule_above_editor", cmTextHolderName);

let cfg = new Object();
cfg.lineNumbers = true;
cfg.viewportMargin = Infinity;
cfg.lineWrapping = true;
cfg.extraKeys = {
	"Alt-F" : "findPersistent",
	"Ctrl-Z" : function(cm) {
		cm.undo();
	}
};
cfg.highlightSelectionMatches = true;

let cmHolder = document.getElementById(cmTextHolderName);
let myCodeMirror = CodeMirror(cmHolder, cfg);

let xt = getFileExtension(theEncodedPath);
let info = CodeMirror.findModeByExtension(xt);
if (info)
	{
	myCodeMirror.setOption("mode", info.mime);
	CodeMirror.autoLoadMode(myCodeMirror, info.mode);
	}
	
window.addEventListener("load", function() {loadFileIntoCodeMirror(myCodeMirror, theEncodedPath);});

CodeMirror.commands.save = function(cm) {
	saveFile(theEncodedPath);
};

myCodeMirror.on("change", onCodeMirrorChange);

// TEST ONLY - not great. Can get option-Z but not cmd or ctrl. 937/184 for option-Z, shift-option-Z.
// myCodeMirror.on("keypress", testNoticeKeyPress);
// No help on iPad, and doesn't pick up modifiers in keyCode: myCodeMirror.on("keydown", testNoticeKeyPress);

function decodeHTMLEntities(text) {
	let entities =
			[ [ 'amp', '&' ], [ 'apos', '\'' ], [ '#x27', '\'' ], [ '#x2F', '/' ], [ '#39', '\'' ],
					[ '#47', '/' ], [ 'lt', '<' ], [ 'gt', '>' ], [ 'nbsp', ' ' ], [ 'quot', '"' ] ];

	for (let i = 0, max = entities.length; i < max; ++i)
		text = text.replace(new RegExp('&' + entities[i][0] + ';', 'g'), entities[i][1]);

	return text;
}

// Call back to intramine_editor.pl#LoadTheFile() with a req=loadfile request.
// On success, start clean, resize the text area, and add autolinks.
async function loadFileIntoCodeMirror(cm, path) {
	path = encodeURIComponent(path);
	try {
		let theAction = 'http://' + mainIP + ':' + ourServerPort + '/?req=loadfile&file=' + path;
		const response = await fetch(theAction);
		if (response.ok)
			{
			let text = decodeURIComponent(await response.text());
			cm.setValue(text);
			cm.markClean();
			cm.clearHistory();
			doResize();
			myCodeMirror.display.barWidth = 16;
			addAutoLinks();
			hideSpinner();
			}
		else
			{
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(errorID);
			e1.innerHTML = '<p>Error, server reached but it returned an error!</p>';
			hideSpinner();
			}
	}
	catch(error) {
		// There was a connection error of some sort
		let e1 = document.getElementById(errorID);
		e1.innerHTML = '<p>Connection error!</p>';
		hideSpinner();
	}
}

function testNoticeKeyPress(cm, evt) {
	let e1 = document.getElementById(errorID);
	e1.innerHTML = 'KEYPRESS ' + evt.keyCode;
}

// Show a confirmation dialog it user wants to leave without saving changes.
// Note browsers often substitute their own string in place of
// "You have unsaved changes...".
// This isn't 100% reliable, but it's close enough for most uses.
// This listener is only added when needed
// (see https://developer.mozilla.org/en-US/docs/Web/API/Window/beforeunload_event).
const beforeUnloadListener = (event) => {
  event.preventDefault();
  return event.returnValue = "You have unsaved changes. Are you sure you want to leave without saving them? Click Cancel if you want to Save.";
};
let unloadListenerAdded = false;

// Maintain the save/undo etc buttons, and redo autolinks.
function onCodeMirrorChange() {
	let sve = document.getElementById("save-button");
	
	if (firstMaintainButtonsCall)
		{
		firstMaintainButtonsCall = false;
		addClass(sve, 'disabled-submit-button');
		let btn = document.getElementById("undo-button");
		addClass(btn, 'disabled-submit-button');
		btn = document.getElementById("redo-button");
		addClass(btn, 'disabled-submit-button');
		
		// Note CodeMirror emits a "change" event when text is loaded, we ignore
		// since loadFileIntoCodeMirror() calls addAutoLinks() directly.
		return;
		}
	
	if (!myCodeMirror.isClean())
		{
		removeClass(sve, 'disabled-submit-button');
		let e1 = document.getElementById(errorID);
		e1.innerHTML = '&nbsp;';
		
		if (!unloadListenerAdded)
			{
			unloadListenerAdded = true;
			addEventListener("beforeunload", beforeUnloadListener, {capture: true});
			}
		}
	else
		{
		addClass(sve, 'disabled-submit-button');
		if (unloadListenerAdded)
			{
			unloadListenerAdded = false;
			removeEventListener("beforeunload", beforeUnloadListener, {capture: true});
			}
		}

	let ur = myCodeMirror.historySize();
	let btn = document.getElementById("undo-button");
	ur.undo ? removeClass(btn, 'disabled-submit-button') : addClass(btn, 'disabled-submit-button');
	btn = document.getElementById("redo-button");
	ur.redo ? removeClass(btn, 'disabled-submit-button') : addClass(btn, 'disabled-submit-button');

	// Restore marks when editing pauses for a couple of seconds.
	debouncedAddLinks();
}

//Call back to intramine_editor.pl#Save() with a req=save POST request.
async function saveFile(path) {
	let e1 = document.getElementById(errorID);
	let sve = document.getElementById("save-button");
	if (hasClass(sve, 'disabled-submit-button'))
		{
		e1.innerHTML = '(nothing to save yet)';
		return;
		}
	else
		{
		e1.innerHTML = '&nbsp;';
		}

	showSpinner();
	let contents = myCodeMirror.getValue();
	// '%' needs encoding in contents, to survive the encodeURIComponent() below.
	contents = contents.replace(/%/g, "%25");
	// And the same for path.
	path = path.replace(/%/g, "%25");
	contents = encodeURIComponent(contents);
	contents = encodeURIComponent(contents); // sic

	try {
		let theAction = 'http://' + mainIP + ':' + ourServerPort + '/';
		const response = await fetch(theAction, {
			method: 'POST',
			headers: {
			'Content-Type': 'application/x-www-form-urlencoded',
		  },
		  body: 'req=save&file=' + encodeURIComponent(path) + '&contents='
		  + contents
		});
		if (response.ok)
			{
			let resp = await response.text();
			if (resp !== 'OK')
				{
				let e1 = document.getElementById("editor_error");
				e1.innerHTML = '<p>Error, server said ' + resp + '!</p>';
				}
			else
				{
				myCodeMirror.markClean();
				let sve = document.getElementById("save-button");
				addClass(sve, 'disabled-submit-button');
				if (unloadListenerAdded)
					{
					unloadListenerAdded = false;
					removeEventListener("beforeunload", beforeUnloadListener, {capture: true});
					}
				}
			hideSpinner();
			}
		else
			{
			// We reached our target server, but it returned an error
			// TODO make this less offensive.
			let e1 = document.getElementById("editor_error");
			e1.innerHTML = '<p>Error, server reached but it could not open the file!</p>';
			hideSpinner();
			}
	}
	catch(error) {
		// There was a connection error of some sort
		// TODO make this less vague.
		let e1 = document.getElementById("editor_error");
		e1.innerHTML = '<p>Connection error while attempting to open file!</p>';
		hideSpinner();
	}
}

function makeDebouncedClearAddLinks() {
	debouncedAddLinks = JD.debounce(clearAndAddAutoLinks, 2000);
}

function addClickHandler(id, fn) {
	let el = document.getElementById(id);
	if (el !== null)
		{
		el.addEventListener('click', fn, false);
		}
}

function editorUndo(e) {
	// e.preventDefault();
	// myCodeMirror.focus();
	myCodeMirror.undo();
	onCodeMirrorChange();
}

function editorRedo(e) {
	// e.preventDefault();
	// myCodeMirror.focus();
	myCodeMirror.redo();
	onCodeMirrorChange();
}

function showSearch(e) {
	// CodeMirror.commands.findPersistent(myCodeMirror);
	CodeMirror.commands.find(myCodeMirror);
}

addClickHandler("undo-button", editorUndo);
addClickHandler("redo-button", editorRedo);
addClickHandler("search-button", showSearch);
