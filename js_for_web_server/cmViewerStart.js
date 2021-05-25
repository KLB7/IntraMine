// cmViewerStart.js: CodeMirror handling. Used in: intramine_file_viewer_cm.pl for read-only
// CodeMirror views.
// Load contents, handle resize, maintain buttons.

function getFileExtension(filename) {
	let result = '';
	let extMatch = /\.(\w+)['"]?$/.exec(filename);
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
		return el.classList.contains(className)
	else
	return(typeof el.className !== 'undefined' && !!el.className.match(new RegExp('(\\s|^)' + className + '(\\s|$)')));
}

function addClass(el, className) {
	if (el !== null)
		{
		if (el.classList)
			el.classList.add(className)
		else if (!hasClass(el, className))
			el.className += " " + className
		}
}

function removeClass(el, className) {
	if (el !== null)
		{
		if (el.classList)
			el.classList.remove(className)
		else if (hasClass(el, className))
			{
			let reg = new RegExp('(\\s|^)' + className + '(\\s|$)')
			el.className = el.className.replace(reg, ' ')
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
	
	updateToggleBigMoveLimit();
}

// Restor scrolled position after a refresh.
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

let markerMainElement = document.getElementById("scrollTextRightOfContents");
if (markerMainElement === null)
	{
	markerMainElement = document.getElementById("scrollText");
	}

let sve = document.getElementById("save-button");
addClass(sve, 'disabled-submit-button');
let btn = document.getElementById("undo-button");
addClass(btn, 'disabled-submit-button');
btn = document.getElementById("redo-button");
addClass(btn, 'disabled-submit-button');

setTextViewPosition("rule_above_editor", cmTextHolderName);

let onMobile = false; // true if we have touch events.
if (typeof window.ontouchstart !== 'undefined')
	{
	onMobile = true;
	}

let anchorClicked = false;
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
let highlightSelectionMatches = new Object();
highlightSelectionMatches.showToken = true;
//highlightSelectionMatches.showToken = /\w/;
highlightSelectionMatches.annotateScrollbar = true;
cfg.highlightSelectionMatches = highlightSelectionMatches;
// For the viewer, no editing.
cfg.readOnly = true;
//console.log("hello");

// Experiment, does path affect actual path used for addons?
cfg.path = 'BOGUS/';

let cmHolder = document.getElementById(cmTextHolderName);
let myCodeMirror = CodeMirror(cmHolder, cfg);

let xt = getFileExtension(theEncodedPath);
let info = CodeMirror.findModeByExtension(xt);
if (info)
	{
	myCodeMirror.setOption("mode", info.mime);
	CodeMirror.autoLoadMode(myCodeMirror, info.mode);
	}

myCodeMirror.on("keyup", maintainButtons);

function decodeHTMLEntities(text) {
	let entities =
			[ [ 'amp', '&' ], [ 'apos', '\'' ], [ '#x27', '\'' ], [ '#x2F', '/' ], [ '#39', '\'' ],
					[ '#47', '/' ], [ 'lt', '<' ], [ 'gt', '>' ], [ 'nbsp', ' ' ], [ 'quot', '"' ] ];

	for (let i = 0, max = entities.length; i < max; ++i)
		text = text.replace(new RegExp('&' + entities[i][0] + ';', 'g'), entities[i][1]);

	return text;
}

function loadFileIntoCodeMirror(cm, path) {
	path = encodeURIComponent(path);
	let request = new XMLHttpRequest();
	request.open('get', 'http://' + mainIP + ':' + ourServerPort + '/?req=loadfile&file=' + path, true);

	request.onload = function() {
		if (request.status >= 200 && request.status < 400)
			{
			// Success!
			let theText = decodeURIComponent(request.responseText);
			cm.setValue(theText);
			// No good: cm.setValue(decodeHTMLEntities(request.responseText));
			cm.markClean();
			cm.clearHistory();
			if (usingCM)
				{
				doResize();
				}
			myCodeMirror.display.barWidth = 16;
			//cm.focus();
			cm.setSelection(cursorFileStartPos, cursorFileEndPos, {
				scroll : true
			});
			
			// Complete startup by adding links and jumping to any requested location.
			getLineNumberForTocEntries();
			addAutoLinks();
			cmRejumpToAnchor();
			//decodeSpecialWordCharacters();
			highlightInitialItems();
			updateToggleBigMoveLimit();
			updateTogglePositions();
			
			// Startup done, hide the pacifier in the nav bar.
			hideSpinner();
			}
		else
			{
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(errorID);
			e1.innerHTML = '<p>Error, server reached but it returned an error!</p>';
			hideSpinner();
			}
	};

	request.onerror = function() {
		// There was a connection error of some sort
		let e1 = document.getElementById(errorID);
		e1.innerHTML = '<p>Connection error!</p>';
		hideSpinner();
	};

	request.send();
}

function testNoticeKeyPress(cm, evt) {
	let e1 = document.getElementById(errorID);
	e1.innerHTML = 'KEYPRESS ' + evt.keyCode;
}

function maintainButtons() {
	let sve = document.getElementById("save-button");
	if (!myCodeMirror.isClean())
		{
		removeClass(sve, 'disabled-submit-button');
		let e1 = document.getElementById(errorID);
		e1.innerHTML = '&nbsp;';
		}

	let ur = myCodeMirror.historySize();
	let btn = document.getElementById("undo-button");
	ur.undo ? removeClass(btn, 'disabled-submit-button') : addClass(btn, 'disabled-submit-button');
	btn = document.getElementById("redo-button");
	ur.redo ? removeClass(btn, 'disabled-submit-button') : addClass(btn, 'disabled-submit-button');
}
