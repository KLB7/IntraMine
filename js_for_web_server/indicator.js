/**
 * indicator.js: Mainly a scroll indicator for PCs and iPads in non-codemirror views (text, perl etc).
 */

// 'indicator is for mobile', 'indicatorPC' is for a regular Windows box.
let indicatorElem = onMobile ? document.getElementById('indicator') : document.getElementById('indicatorPC');
let otherIndicatorElem = onMobile ? document.getElementById('indicatorPC') : document.getElementById('indicator');
//let indicatorElem = document.getElementById('indicator');
let indicatorM = 0; // for mobile and non-mobile
let lazySetUpMobileIndicator = JD.debounce(setUpMobileIndicator, 100);
let lazyMobileScroll = JD.debounce(scrollMobileIndicator, 500);
let lazyResetTopNavPosition = JD.debounce(resetTopNavPosition, 400);

let lazySetUpIndicator = JD.debounce(setUpIndicator, 100);
let lazyScroll = JD.debounce(scrollIndicator, 500);
let arrowHeight = 18; // Needed for PC only.

otherIndicatorElem.style.display = 'none';


if (onMobile) // iPad only supported for now....
	{
	//console.log("WE ARE MOBILE.");
	window.addEventListener("load", lazySetUpMobileIndicator);
	window.addEventListener("resize", lazySetUpMobileIndicator);
	markerMainElement.addEventListener("scroll", scrollMobileIndicator);
	markerMainElement.addEventListener("touchend", lazyResetTopNavPosition);

	let tocElement = document.getElementById("scrollContentsList");
	if (tocElement !== null)
		{
		tocElement.addEventListener("touchend", lazyMobileScroll);
		tocElement.addEventListener("touchend", lazyResetTopNavPosition);
		}
	}
else
	{
	window.addEventListener("load", lazySetUpIndicator);
	window.addEventListener("resize", lazySetUpIndicator);
	
	markerMainElement.addEventListener("scroll", scrollIndicator);
	window.addEventListener("load", addHideIndicatorScrollListener);
	
	hideIt("search-button");
	hideIt("small-tip");
	hideIt("undo-button");
	hideIt("redo-button");
	}

// Mobile, mainly set indicatorM. "M" as in y = Mx + b.
function setUpMobileIndicator() {
	if (!onMobile)
		{
		return;
		}

	let rect = markerMainElement.getBoundingClientRect();
	let yTop = rect.top;
	let yBottom = rect.bottom;
	let textViewableHeight = yBottom - yTop;
	let mainScrolllHeight = markerMainElement.scrollHeight;

	if (mainScrolllHeight > textViewableHeight)
		{
		let indicatorHeight = (textViewableHeight / mainScrolllHeight) * textViewableHeight;
		indicatorM =
				(textViewableHeight - indicatorHeight) / (mainScrolllHeight - textViewableHeight);

		if (indicatorHeight < 2.0)
			{
			indicatorHeight = 2.0;
			}
		indicatorElem.style.height = indicatorHeight + "px";
		}

	lazyMobileScroll();
}

// Non-mobile, mainly set indicatorM. "M" as in y = Mx + b.
function setUpIndicator() {
	if (onMobile)
		{
		return;
		}
	
	recalculateIndicatorM();
	// let rect = markerMainElement.getBoundingClientRect();
	// let yTop = rect.top;
	// let yBottom = rect.bottom;
	// let textViewableHeight = yBottom - yTop;
	// let mainScrolllHeight = markerMainElement.scrollHeight;
	
	// let viewWidth = rect.right - rect.left;
	// let widthDifference = viewWidth - markerMainElement.clientWidth;
	// let heightDifference = textViewableHeight - markerMainElement.clientHeight;
	// let haveVerticalScroll = (widthDifference > 2) ? true : false;
	// let haveHorizontalScroll = (heightDifference > 2) ? true : false;

	// let arrowMultiplier = 2;
	// if (typeof window.ontouchstart !== 'undefined')
	// 	{
	// 	arrowHeight = 2;
	// 	}
	// else
	// 	{
	// 	if (haveVerticalScroll)
	// 		{
	// 		if (widthDifference > 6.0 && widthDifference < 30.0)
	// 			{
	// 			arrowHeight = widthDifference;
	// 			}
	// 		if (haveHorizontalScroll)
	// 			{
	// 			arrowMultiplier = 3;
	// 			}
	// 		}
	// 	else
	// 		{
	// 		arrowHeight = 0;
	// 		}
	// 	}

	// let usableTextHeight = textViewableHeight - arrowMultiplier * arrowHeight;
	
	// if (mainScrolllHeight > usableTextHeight)
	// 	{
	// 	let indicatorHeight = usableTextHeight * (textViewableHeight/(mainScrolllHeight));
		
	// 	// Show the indicator only if thumb is too small to reflect actual page size.
	// 	if (indicatorHeight <= 20)
	// 		{
	// 		indicatorM =
	// 				(usableTextHeight - indicatorHeight) / (mainScrolllHeight - textViewableHeight);
	
	// 		if (indicatorHeight < 2.0)
	// 			{
	// 			indicatorHeight = 2.0;
	// 			}
	// 		indicatorElem.style.height = indicatorHeight + "px";
	// 		}
	// 	else
	// 		{
	// 		indicatorM = 0;
	// 		}
	// 	}
	// else
	// 	{
	// 	indicatorM = 0;
	// 	}

	lazyScroll();
	
	setTimeout(function() {
				hideIndicator();
			}, 1000);
}

function recalculateIndicatorM() {
	if (onMobile)
		{
		return;
		}
	
	let rect = markerMainElement.getBoundingClientRect();
	let yTop = rect.top;
	let yBottom = rect.bottom;
	let textViewableHeight = yBottom - yTop;
	let mainScrolllHeight = markerMainElement.scrollHeight;
	
	let viewWidth = rect.right - rect.left;
	let widthDifference = viewWidth - markerMainElement.clientWidth;
	let heightDifference = textViewableHeight - markerMainElement.clientHeight;
	let haveVerticalScroll = (widthDifference > 2) ? true : false;
	let haveHorizontalScroll = (heightDifference > 2) ? true : false;

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
				arrowHeight = widthDifference;
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
	
	if (mainScrolllHeight > usableTextHeight)
		{
		let indicatorHeight = usableTextHeight * (textViewableHeight/(mainScrolllHeight));
		
		// Show the indicator only if thumb is too small to reflect actual page size.
		if (indicatorHeight <= 20)
			{
			indicatorM =
					(usableTextHeight - indicatorHeight) / (mainScrolllHeight - textViewableHeight);
	
			if (indicatorHeight < 2.0)
				{
				indicatorHeight = 2.0;
				}
			indicatorElem.style.height = indicatorHeight + "px";
			}
		else
			{
			indicatorM = 0;
			}
		}
	else
		{
		indicatorM = 0;
		}
}

// Mobile, set indicatorElem.top
function scrollMobileIndicator() {
	if (!onMobile)
		{
		return;
		}

	if (indicatorM > 0)
		{
		let mainScrollY = markerMainElement.scrollTop;
		let rect = markerMainElement.getBoundingClientRect();
		let yTop = rect.top;
		let newThumbTop = indicatorM * mainScrollY + yTop;
		indicatorElem.style.top = newThumbTop + "px";
		}
}

// Non-mobile, set indicatorElem.top
function scrollIndicator() {
	if (onMobile)
		{
		return;
		}

	if (indicatorM > 0)
		{
		indicatorElem.style.display = 'block';
		
		let mainScrollY = markerMainElement.scrollTop;
		let rect = markerMainElement.getBoundingClientRect();
		let yTop = rect.top;
		let newThumbTop = indicatorM * mainScrollY + yTop + arrowHeight;
		indicatorElem.style.top = newThumbTop + "px";
		}

	// Sometimes the lines change, reset indicatorM.
	recalculateIndicatorM();
}

// Add a scroll listener that hides the 'indicatorPC' box after a few seconds.
let isScrollingIndicator = null;
function addHideIndicatorScrollListener() {
	let el = document.getElementById(cmTextHolderName);
	if (el !== null)
		{
		el.addEventListener("scroll", function() {
			// Clear our timeout throughout the scroll
			window.clearTimeout( isScrollingIndicator );
	
			// Set a timeout to run after scrolling ends
			isScrollingIndicator = setTimeout(function() {
				// Run the callback
				hideIndicator();
			}, 3000);
			});
		}
}

function hideIndicator() {
	if (indicatorElem !== null)
		{
		indicatorElem.style.display = 'none';
		}
}
