// editor.js: CodeMirror handling for Edit views. Used in:
// intramine_editor.pl.
// Load, Save file, manage content resizing.

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
		return el.classList.contains(className)
	else
		return !!el.className.match(new RegExp('(\\s|^)' + className + '(\\s|$)'))
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

window.addEventListener("load", reJump);
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

if (!usingCM)
	{
	ready(positionViewItems);
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
	saveFile(theEncodedPath)
};

myCodeMirror.on("keyup", maintainButtons);

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
function loadFileIntoCodeMirror(cm, path) {
	path = encodeURIComponent(path);
	//console.log("path |" + path + "|");
	let request = new XMLHttpRequest();
	request.open('get', 'http://' + mainIP + ':' + ourServerPort + '/?req=loadfile&file=' + path, true);

	request.onload = function() {
		if (request.status >= 200 && request.status < 400)
			{
			// Success!
			let theText = decodeURIComponent(request.responseText);
			cm.setValue(theText);
//			cm.setValue(decodeHTMLEntities(request.responseText));
			cm.markClean();
			cm.clearHistory();
			if (usingCM)
				{
				doResize();
				}
			myCodeMirror.display.barWidth = 16;
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

//Call back to intramine_editor.pl#Save() with a req=save POST request.
function saveFile(path) {
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
	let request = new XMLHttpRequest();
	request.open('post', 'http://' + mainIP + ':' + ourServerPort + '/', true);
	request.setRequestHeader("Content-type", "application/x-www-form-urlencoded");

	request.onload = function() {
		if (request.status >= 200 && request.status < 400)
			{
			// Success?
			let resp = request.responseText;
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
	};

	request.onerror = function() {
		// There was a connection error of some sort
		// TODO make this less offensive.
		let e1 = document.getElementById("editor_error");
		e1.innerHTML = '<p>Connection error while attempting to open file!</p>';
		hideSpinner();
	};

	// '%' needs encoding in contents, to survive the encodeURIComponent() below.
	contents = contents.replace(/%/g, "%25");
	// And the same for path.
	path = path.replace(/%/g, "%25");
	
	contents = encodeURIComponent(contents);
	contents = encodeURIComponent(contents);
	
	request.send('req=save&file=' + encodeURIComponent(path) + '&contents='
			+ contents);
}

//Call back to intramine_editor.pl#Save() with a req=save POST request.
function oldersaveFile(path) {
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
	let request = new XMLHttpRequest();
	request.open('post', 'http://' + mainIP + ':' + ourServerPort + '/', true);
	request.setRequestHeader("Content-type", "application/x-www-form-urlencoded");

	request.onload = function() {
		if (request.status >= 200 && request.status < 400)
			{
			// Success?
			let resp = request.responseText;
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
	};

	request.onerror = function() {
		// There was a connection error of some sort
		// TODO make this less offensive.
		let e1 = document.getElementById("editor_error");
		e1.innerHTML = '<p>Connection error while attempting to open file!</p>';
		hideSpinner();
	};

	// '%' needs encoding in contents, to survive the encodeURIComponent() below.
	contents = contents.replace(/%/g, "%25");
	// And the same for path.
	path = path.replace(/%/g, "%25");
	// which leaves "&" as in "&nbsp;", encode "&" as "&amp;"
	contents = contents.replace(/\&/g, "&amp;");
	
	request.send('req=save&file=' + encodeURIComponent(path) + '&contents='
			+ encodeURIComponent(contents));
}
