// cmHandlers.js: Set up "load" and "scroll" handlers etc for CodeMirror views.

function cmLoad() {
	loadFileIntoCodeMirror(myCodeMirror, theEncodedPath);
}

function cmScroll() {
	onScroll();
	addAutoLinks();
}

function resizeAndRedrawMarkers() {
	//doResize();
	if (initialSearchHitsAreShowing)
		{
		removeInitialHighlights();
		highlightInitialItems();
		}
}

let addHintTimer; // onMobile, to keep trying addHintboxListener() until it succeeds.

function addHintboxListener() {
	let tooltipElement = document.getElementById("hintbox");
	if (tooltipElement !== null)
		{
		tooltipElement.addEventListener("touchstart", cmMobileHandleImgTouch);
		clearInterval(addHintTimer);
		}
}

myCodeMirror.on("refresh", resizeAndRedrawMarkers);
window.addEventListener("load", cmLoad);
myCodeMirror.on("scroll", JD.debounce(addAutoLinks, 250));

if (onMobile)
	{
	myCodeMirror.on("touchstart", cmHandleTouch);
	myCodeMirror.getWrapperElement().addEventListener("touchend", function(e) {
		handleFileLinkMouseUp(e);
	});
	
	markerMainElement.addEventListener("touchend", function(evt) {
		synchTableOfContents(evt);
	});
	
	
	let tocElement = document.getElementById("scrollContentsList");
	if (tocElement !== null)
		{
		tocElement.addEventListener("touchend", function(e) {
			handleFileLinkMouseUp(e);
			return false;
		});
		}
	addHintTimer = setInterval(addHintboxListener, 200);
	}
else
	{
	myCodeMirror.getWrapperElement().addEventListener("mouseover", function(e) {
		handleMouseOver(e);
		// Prevent link firing when all we want is a hover tooltip.
		return false;
	});
	myCodeMirror.getWrapperElement().addEventListener("mousedown", function(e) {
		handleFileLinkClicks(e);
		return false;
	});
	myCodeMirror.getWrapperElement().addEventListener("mouseup", function(e) {
		handleFileLinkMouseUp(e);
		return false;
	});
	
	myCodeMirror.getWrapperElement().addEventListener("dblclick", function(e) {
		handleDoubleClick(e);
	
	});
	
	markerMainElement.addEventListener("mouseup", function(evt) {
	synchTableOfContents(evt);
	});

	let tocElement = document.getElementById("scrollContentsList");
	if (tocElement !== null)
		{
		tocElement.addEventListener("mouseup", function(e) {
			handleFileLinkMouseUp(e);
			return false;
		});
		}
	}
