/**
 * cmShowSearchItems.js: Highlight search terms provided in URL, if any.
 * For CodeMirror views only.
 * Typically hits are put in the URL by (IntraMine) Search.
 * highlightItems holds the hits, filled in by Viewer,
 * see intramine_file_viewer_cm.pl#FullFileTemplate(). 
 */

let markerArray = [];
let markerArrayCleared = false;
let scrollMarkerClass = "scroll-hilite";
let initialSearchHitsAreShowing = false;
let toggleHitsButtonID = "sihits";

// Add CodeMirror markers for all instances of the initial items to be highlighted.
function highlightInitialItems() {
	let cmDoc = myCodeMirror.doc;
	// highlightItems: array of [cmline, charStart, charEnd].
	if (!initialSearchHitsAreShowing && highlightItems.length > 0)
		{
		for (let i = 0; i < highlightItems.length; ++i)
			{
			let cmline = highlightItems[i][0];
			let charStart = highlightItems[i][1];
			let charEnd = highlightItems[i][2];
			let thisMarker = cmDoc.markText({
				line : cmline,
				ch : charStart
			}, {
				line : cmline,
				ch : charEnd
			}, {
				css : "background-color: #ffcccc"
			});
			markerArray.push(thisMarker);
			}
		addInitialCmScrollMarkers(scrollMarkerClass);
		initialSearchHitsAreShowing = true;
		let toggleButton = document.getElementById(toggleHitsButtonID);
		if (toggleButton !== null)
			{
			toggleButton.value = "Hide Initial Hits";
			}
		}
}

function removeInitialHighlights() {
	if (initialSearchHitsAreShowing)
		{
		for (let i = 0; i < markerArray.length; ++i)
			{
			markerArray[i].clear();
			}
		markerArray = [];
		removeInitialCmScrollMarkers();
		initialSearchHitsAreShowing = false;
		let toggleButton = document.getElementById(toggleHitsButtonID);
		if (toggleButton !== null)
			{
			toggleButton.value = "Show Initial Hits";
			}
		}
}

// Called for a click in the Show/Hide Initial Hits button, see
// intramine_file_viewer_cm.pl#InitialHighlightItems().
function toggleInitialSearchHits() {
	if (initialSearchHitsAreShowing)
		{
		removeInitialHighlights();
		}
	else
		{
		highlightInitialItems();
		}
}

// Add hit occurrence "markers" in the scroll region on the right of view.
// These are HTML "mark" elements, not CodeMirror markers.
function addInitialCmScrollMarkers(scrollHitClassName) {
	if (markerArray.length == 0)
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
	let clientHeight = cmScrollInfo.clientHeight;
	let clientWidth = cmScrollInfo.clientWidth;
	let mainScrollY = cmScrollInfo.top;
	let mainScrolllHeight = cmScrollInfo.height;
	let viewWidth = rect.right - rect.left;
	let widthDifference = viewWidth - clientWidth;
	let heightDifference = textViewableHeight - clientHeight;
	let haveVerticalScroll = (widthDifference > 2) ? true : false;
	let haveHorizontalScroll = (heightDifference > 2) ? true : false;

	let arrowHeight = 18;
	let arrowMultiplier = 2;
	if (typeof window.ontouchstart !== 'undefined')
		{
		arrowHeight = 2;
		}
	else
		{
		if (haveVerticalScroll)
			{
			if (widthDifference > 6.0 && widthDifference < 30.0)
				{
				arrowHeight = Math.round(widthDifference) + 2;
				}
			if (haveHorizontalScroll)
				{
				arrowMultiplier = 3;
				}
			}
		else
			{
			arrowHeight = 0;
			}
		}
	let usableTextHeight = textViewableHeight - arrowMultiplier * arrowHeight;

	for (let i = 0; i < markerArray.length; ++i)
		{
		let markerPos = markerArray[i].find();
		let startCmLine = markerPos.from.line;
		let textHitY = myCodeMirror.heightAtLine(startCmLine);
		let positionInDoc = mainScrollY + textHitY - yTop;
		let positionRatio = positionInDoc / mainScrolllHeight;
		let relativeMarkerPos = positionRatio * usableTextHeight;
		let absMarkerPos = relativeMarkerPos + yTop + arrowHeight;

		let mk = document.createElement("mark");
		mk.setAttribute("class", scrollHitClassName);
		mk.style.top = absMarkerPos + "px";
		markerMainElement.appendChild(mk);
		}
}

function removeInitialCmScrollMarkers() {
	removeElementsByClass(scrollMarkerClass);
}

// On load, show the initial hit markers, in text and in the scroll region on right.
//window.addEventListener("load", highlightInitialItems);
