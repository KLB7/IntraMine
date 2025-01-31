// cmEditorHandlers.js: some event handlers for the built-in editor (intramine_editor.pl).

// TEST ONLY speedup needed.
//Try a "do nothing" function instead of lazyAddAutoLinks:
function doNothing() {
;
}
let lazyAddAutoLinks;
lazyAddAutoLinks = JD.debounce(addAutoLinks, 250);
//myCodeMirror.on("scroll", doNothing);
myCodeMirror.on("scroll", lazyAddAutoLinks);


//myCodeMirror.on("scroll", JD.debounce(addAutoLinks, 250));

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
