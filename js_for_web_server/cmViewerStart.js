// cmViewerStart.js: CodeMirror handling. Used in: intramine_viewer.pl for read-only
// CodeMirror views.

// Remember top line, restore it during and after resize.
let topLineForResize = -999;
// Delay scrolling a little, to help resize preserve first text line number.
let lazyOnScroll;

// Load contents, handle resize, maintain buttons.

function getFileExtension(filename) {
	let result = '';
	let extMatch = /\.(\w+)['"]?$/.exec(filename);
	if (extMatch !== null)
		{
		result = extMatch[1];
		
		// Try to fool CodeMirror into treating the modern
		// f03 file extension as f90, since it doesn't know f03.
		if (result === "f03")
			{
			result = "f90";
			}
		// Ditto for COBOL
		else if (result === "cbl")
			{
			result = "cpy";
			}
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

function rememberTopLineForResize() {
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
	
	topLineForResize = lineNumber.toString();
}

function doResize() {
	let rule = document.getElementById("rule_above_editor");
	if (rule === null)
		{
		console.log("cmViwerStart.js#doResize rule element is null!");
		return;
		}
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
		else
			{
			tocHeight -= 16;
			}
		let newTocHeightPC = (tocHeight / elHeight) * 100;
		tocMainElement.style.height = newTocHeightPC + "%";
		}

	updateToggleBigMoveLimit();
}

// Try to preserve first displayed line of text while resizing.
function onWindowResize() {
	if (!resizing)
		{
		rememberTopLineForResize();
		}
	
	resizing = true;

	location.hash = topLineForResize;
	restoreColumnWidths();
	setTimeout(function() {
		myCodeMirror.refresh();
		}, 500);
	//myCodeMirror.refresh();
    reJump();
	lazyMouseUp();
	repositionTocToggle();
}

window.addEventListener("resize", onWindowResize);

// Restore scrolled position after a refresh.
function reJump() {
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
		else // perhaps it's a line number
			{
			cmQuickRejumpToLine();
			}
		}
}

function setTextViewPosition(rule_id, id) {
	let rule = document.getElementById(rule_id);
	if (rule === null)
		{
		console.log("cmViwerStart.js#setTextViewPosition rule element is null!");
		return;
		}
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
		ch: 0,
	};

cmCursorStartPos = cursorFileStartPos;
cmCursorEndPos = cursorFileEndPos;

let xt = getFileExtension(theEncodedPath);
let XT = xt.toUpperCase();
let isCOBOL = false;
if (XT === "COB" || XT === "CPY" || XT === "CBL")
	{
	isCOBOL = true;
	}

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
if (isCOBOL)
	{
	highlightSelectionMatches.showToken = /[a-zA-Z0-9-]/;
	}
else
	{
	highlightSelectionMatches.showToken = true;
	}

highlightSelectionMatches.annotateScrollbar = true;
cfg.highlightSelectionMatches = highlightSelectionMatches;
// For the viewer, no editing.
cfg.readOnly = true;

// Experiment, does path affect actual path used for addons?
cfg.path = 'BOGUS/';

let cmHolder = document.getElementById(cmTextHolderName);
let myCodeMirror = CodeMirror(cmHolder, cfg);


let info = CodeMirror.findModeByExtension(xt);
if (info)
	{
	myCodeMirror.setOption("mode", info.mime);
	CodeMirror.autoLoadMode(myCodeMirror, info.mode);
	}

function decodeHTMLEntities(text) {
	let entities =
			[ [ 'amp', '&' ], [ 'apos', '\'' ], [ '#x27', '\'' ], [ '#x2F', '/' ], [ '#39', '\'' ],
					[ '#47', '/' ], [ 'lt', '<' ], [ 'gt', '>' ], [ 'nbsp', ' ' ], [ 'quot', '"' ] ];

	for (let i = 0, max = entities.length; i < max; ++i)
		text = text.replace(new RegExp('&' + entities[i][0] + ';', 'g'), entities[i][1]);

	return text;
}

async function loadFileIntoCodeMirror(cm, path) {
	path = encodeURIComponent(path);

	try {
		let theAction = 'http://' + mainIP + ':' + ourServerPort + '/?req=loadfile&file=' + path;
		const response = await fetch(theAction);
		if (response.ok)
			{
			let respText = await response.text();
			let text = decodeURIComponent(respText);
			cm.setValue(text);
			// No good: cm.setValue(decodeHTMLEntities(request.responseText));
			// Add divider between table of contents and text. This also restores
			// the width of the table of contents column.
			addDragger && addDragger();

			cm.markClean();
			cm.clearHistory();
			if (usingCM)
				{
				resizing = true;
				doResize();
				resizing = false;
				}
			myCodeMirror.display.barWidth = 16;
			cm.setSelection(cursorFileStartPos, cursorFileEndPos, {
				scroll : true
			});
			
			// Complete startup by adding links and jumping to any requested location.
			getLineNumberForTocEntries();
			addAutoLinks();
			highlightInitialItems();
			updateToggleBigMoveLimit();
			updateTogglePositions();
			// Too soon: cmRejumpToAnchor();
			setTimeout(function() {
				cmRejumpToAnchor();
				}, 600);
			lazyOnScroll = JD.debounce(onScroll, 100);
			cm.on("scroll", lazyOnScroll);
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

