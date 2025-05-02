// tooltip.js: show a "tooltip" with text or an image, the main call is showhint().
/**********************************************************************************************
 * Show Hint script- (c) Dynamic Drive (www.dynamicdrive.com) 
 * This notice MUST stay intact for legal use 
 * Visit http://www.dynamicdrive.com/ for this script and 100s more.
 **********************************************************************************************/
// (Modified from the original 2018-19 and 2023-4 for use with IntraMine.)
// IntraMine use, see eg showhint() calls in
// intramine_linker.pl#GetImageFileRep(), intramine_boilerplate.pl#ThePage().

// Cursor position, updated when hintbox is showing.
let cursor_x = -1;
let cursor_y = -1;

// Where to place the hint, relative to cursor position.
const DIRECTION_BELOW = 0;
const DIRECTION_ABOVE = 1;
const DIRECTION_RIGHT = 2;
const DIRECTION_LEFT = 3;

let anchorClassName = "showHintAnchorClass"; 	// applied while mouse over element
let hitAnchorClassName = "invisiblehintanchor"; // applied if not present in element, permanently
let definitionClassName = 'defhint'; // When showing links to a definition

let overAnchorTimer = null;
let shMainPort = 0; // See setMainPort() just below.
let shOurServerPort = (typeof ourServerPort !== 'undefined') ? ourServerPort: 0;
let shOnMobile = (typeof window.ontouchstart !== 'undefined') ? true : false;
let hintElement = {}; // The HTML element holding the hint
let hintParams = {};  // hint HTML, position, width, whether it's an image


// Set the main IntraMine port, 81 by default.
function setMainPort() {
	shMainPort = (typeof theMainPort !== 'undefined') ? theMainPort: 0;
	}

window.addEventListener("load", setMainPort);


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
			let reg = new RegExp('(\\s|^)' + className + '(\\s|$)')
			el.className = el.className.replace(reg, ' ');
			}
		}
}

function isDescendant(parent, child) {
	var node = child.parentNode;
	while (node != null) {
		if (node == parent) {
			return true;
		}
		node = node.parentNode;
	}
	return false;
}

// Helper function to get an element's exact position.
function getPosition(el) {
	"use strict";
	let rect = el.getBoundingClientRect();
	let yPos = rect.top;
	let xPos = rect.left;
	let xScrollTOTAL = 0;
	let yScrollTOTAL = 0;

	while (el)
		{
		if (el.tagName === "BODY")
			{
			// deal with browser quirks with body/window/document and page scroll
			let xScroll = el.scrollLeft || document.documentElement.scrollLeft;
			let yScroll = el.scrollTop || document.documentElement.scrollTop;
			xScrollTOTAL += xScroll;
			yScrollTOTAL += yScroll;
			}
		else
			{
			// for all other non-BODY elements
			xScrollTOTAL += el.scrollLeft;
			yScrollTOTAL += el.scrollTop;
			}

		el = el.offsetParent;
		}
	return {
		x : xPos,
		y : yPos,
		sx : xScrollTOTAL,
		sy : yScrollTOTAL
	};
}


function positionAndShowHint() {
	"use strict";
	let hintContents = hintParams.hintContents;
	let x = hintParams.x;
	let y = hintParams.y;
	let tipwidth = hintParams.tipWidth;
	let isAnImage = hintParams.isAnImage;
	let haveImageWidth = true;
	let gap = 10; // gap between cursor and tip
	let windowHeight = window.innerHeight - gap;
	let windowWidth = window.innerWidth - gap;
	let hintWidth = tipwidth; //450;
	let hintHeight = hintParams.tipHeight; //hintElement.offsetHeight;
	if (isAnImage)
		{
		try
			{
			hintWidth = hintParams.theImage.width;
			hintHeight = hintParams.theImage.height;
			}
		catch(e)
			{
			haveImageWidth = false;
			}
		}
	else
		{
		if (tipwidth !== "")
			{
			hintWidth = parseInt(tipwidth, 10);
			}
		}

	// Calculate tip all four ways, pick the way that produces least shrinkage.
	// Preference order below, above, right, left.
	let ds = bestDirectionAndScale(x, y, hintWidth, hintHeight, windowWidth, windowHeight);
	let bestDirection = ds.bestDirection;
	let scaleFactor = ds.scaleFactor;
	
	// Scale image down to fit in window.
	if (isAnImage)
		{
		if (scaleFactor < 1.0)
			{
			let finalScaleFactor = scaleFactor * 0.95; //temp[bestDirection] * 0.95;
			hintWidth = Math.floor(hintWidth * finalScaleFactor);
			hintHeight = Math.floor(hintHeight * finalScaleFactor);
			}
		}
	
	// Position tip (and scale if image).
	// Try to keep tip close to mouse x,y position.
	let tl = tipTopAndLeft(bestDirection, x, y, hintWidth, hintHeight, windowWidth, windowHeight, gap);

	hintElement.style.top = tl.top;
	hintElement.style.left = tl.left;
	
	// Scale image if it's really needed and we have good width and height.
	if (isAnImage)
		{
		hintElement.style.width = hintWidth + "px";
		hintElement.style.height = hintHeight + "px";
		}
	// For text, shrink the height to fit within window if necessary.
	else
		{
		hintElement.style.width = "650px";
		if (tl.top + hintHeight > windowHeight)
			{
			let reducedHeight = windowHeight - tl.top;
			hintElement.style.height = reducedHeight + "px";
			}
		else
			{
			hintElement.style.height = "auto";
			}
		}

	hintElement.innerHTML = hintContents;

	setTimeout(function() {
		hintElement.style.visibility = "visible";
		}, 100);

}

// Calculate tip all four ways, pick the way that produces least shrinkage.
// Preference order: below, above, right, left.
function bestDirectionAndScale(x, y, hintWidth, hintHeight, windowWidth, windowHeight) {
	// Below:
	let heightAvailable = windowHeight - y;
	let widthAvailable = windowWidth;
	let belowScaleFactor = heightAvailable / hintHeight;
	if (belowScaleFactor > widthAvailable / hintWidth)
		{
		belowScaleFactor = widthAvailable / hintWidth;
		}
	// Above:
	heightAvailable = y;
	let aboveScaleFactor = heightAvailable / hintHeight;
	if (aboveScaleFactor > widthAvailable / hintWidth)
		{
		aboveScaleFactor = widthAvailable / hintWidth;
		}
	// Right:
	heightAvailable = windowHeight;
	widthAvailable = windowWidth - x;
	let rightScaleFactor = heightAvailable / hintHeight;
	if (rightScaleFactor > widthAvailable / hintWidth)
		{
		rightScaleFactor = widthAvailable / hintWidth;
		}
	// Left:
	widthAvailable = x;
	let leftScaleFactor = heightAvailable / hintHeight;
	if (leftScaleFactor > widthAvailable / hintWidth)
		{
		leftScaleFactor = widthAvailable / hintWidth;
		}
	
	// Largest scaleFactor wins, preferring in order below, above, right, left where
	// there's a tie or values are above 1.0.
	let directionalScale = [];
	directionalScale[DIRECTION_BELOW] = (belowScaleFactor > 1.0) ? 1.0 : belowScaleFactor;
	directionalScale[DIRECTION_ABOVE] = (aboveScaleFactor > 1.0) ? 1.0 : aboveScaleFactor;
	directionalScale[DIRECTION_RIGHT] = (rightScaleFactor > 1.0) ? 1.0 : rightScaleFactor;
	directionalScale[DIRECTION_LEFT] = (leftScaleFactor > 1.0) ? 1.0 : leftScaleFactor;
	// bestDirection:
	// 0 == show hint below cursor x,y
	// 1 == show hint above
	// 2 == show hint to right of cursor
	// 3 == show hint to left of cursor
	let bestDirection = -1;
	let i = 0;
	for (i = directionalScale.length - 1; i >= 0; i -= 1)
		{
		if (directionalScale[i] >= 1.0)
			{
			bestDirection = i;
			}
		}
	
	if (bestDirection < 0) // all directionalScale[] are < 1.0
		{
		let curValue = directionalScale[0];
		bestDirection = 0;
		for (i = 1; i < directionalScale.length; i++)
			{
			if (directionalScale[i] > curValue)
				{
				curValue = directionalScale[i];
				bestDirection = i;
				}
			}
		}

	let ds = {};
	ds.bestDirection = bestDirection;
	ds.scaleFactor = directionalScale[bestDirection];
	return(ds);
}

// Position tip (and scale if image).
// Try to keep tip close to mouse x,y position.
function tipTopAndLeft(bestDirection, x, y, hintWidth, hintHeight, windowWidth, windowHeight, gap) {
	let left = 0;
	let top = 0;
	
	if (bestDirection === DIRECTION_BELOW) // below
		{
		top = y + 2*gap; // Double the gap to move tip down slightly.
		left = (x + gap + hintWidth <= windowWidth) ? (x + gap) : windowWidth - hintWidth - gap;
		left = (left < 0) ? 0 : left;
		}
	else if (bestDirection === DIRECTION_ABOVE) // above
		{
		if (y - hintHeight - gap >= 0)
			{
			top = y - hintHeight - gap;
			}
		else
			{
			top = 0;
			}
		let left = (x + gap + hintWidth <= windowWidth) ? (x + gap) : windowWidth - hintWidth - gap;
		left = (left < 0) ? 0 : left;
		}
	else if (bestDirection === DIRECTION_RIGHT) // right
		{
		left = x + gap;
		let top =
			(y + gap + hintHeight <= windowHeight) ? (y + gap) : windowHeight - hintHeight - gap;
		top = (top < 0) ? 0 : top;
		}
	else
		// if (bestDirection === DIRECTION_LEFT) // left
		{
		if (x - hintWidth - gap >= 0)
			{
			left = x - hintWidth - gap;
			}
		else
			{
			left = 0;
			}
		let top =
			(y + gap + hintHeight <= windowHeight) ? (y + gap) : windowHeight - hintHeight - gap;
		top = (top < 0) ? 0 : top;
		}

	// Some fine-tuning to keep as much of the tip visible as possible.
	// Top left portion preferred.
	if (top + hintHeight > windowHeight)
		{
		let offBottom = top + hintHeight - windowHeight;
		top -= offBottom;
		}
	if (top < 0)
		{
		top = 0;
		}
	if (left + hintWidth > windowWidth)
		{
		let offRight = left + hintWidth - windowWidth;		
		left -= offRight;
		}
	if (left < 0)
		{
		left = 0;
		}

	if (top > 0)
		{
		top += "px";
		}
	if (left > 0)
		{
		left += "px";
		}
	
	let topLeft = {};
	topLeft.top = top;
	topLeft.left = left;

	return(topLeft);
}

// The main event.
function showhint(hintContents, obj, e, tipwidth, isAnImage, shouldDecode) {
	"use strict";

	if (shouldDecode === undefined)
		{
		shouldDecode = false;
		}

	if (typeof shouldDecode === "string")
		{
		if (shouldDecode.toLowerCase() === "true")
			{
			shouldDecode = true;
			}
		else
			{
			shouldDecode = false;
			}
		}

	if (typeof isAnImage === "string")
		{
		if (isAnImage.toLowerCase() === "true")
			{
			isAnImage = true;
			}
		else
			{
			isAnImage = false;
			}
		}
	
	if (shouldDecode)
		{
		setTimeout(function() {
			showWithFreshPort(decodeHint(hintContents), obj, e, tipwidth, isAnImage);
			}, 100);
		}
	else
		{
		setTimeout(function() {
			showWithFreshPort(hintContents, obj, e, tipwidth, isAnImage);
			}, 100);
		}
	}

function decodeHint(text) {
	text = decodeURIComponent(text);
	
	return(text);
}

// Special handling for some images: if hintContents looks like
//<img src="http://192.168.1.132:81/Viewer/imagefile.png">
// then we take what's in the "81" position as IntraMine's Main port, and what's in
// the "Viewer" spot as a Short name. Then call back to the Main port requesting a free
// port for the Short name, and replace the "81" in hintContents with the free port number.
// Also strip out the Short name, it was needed only to tell Main which server we wanted.
// For other img src values, just pass them along to showhinAfterDelay unchanged.
// (The fancy footwork with the port is an attempt to get the port number of a service that is
// running and not under maintenance. This allows showhint to show the image if there are two
// or more instances of a service running, even if one is doing maintenance.)
async function showWithFreshPort(hintContents, obj, e, tipwidth, isAnImage) {
	let hintShown = false;
	let image_url = "";

	if (isAnImage)
		{
		image_url = srcURL(hintContents);

		if (image_url !== "")
			{
			// Match eg http://192.168.1.132:81/Viewer/...
			let urlMatch = /^http\:\/\/([0-9\.]+)\:(\d+)\/([A-Za-z_]+)\/(.+?)$/.exec(image_url);
			if (urlMatch !== null)
				{
				let ip = urlMatch[1];
				let port = urlMatch[2];
				let shortName = urlMatch[3];
				let path = urlMatch[4];
				
				if (port === shMainPort) // Request good port number from shMainPort
					{
					hintShown = true; // Give up if we can't show it here.
					// However, if we're on an iPad (shOnMobile), try to use our current server's
					// port rather than asking Main to supply a fresh one - Apple really doesn't
					// like any hanky panky with the port number.
					if (shOnMobile && port === shMainPort && shOurServerPort !== 0)
						{
						let rePort = new RegExp(port);
						hintContents = hintContents.replace(rePort, shOurServerPort);
						let reName = new RegExp(shortName + "\/");
						hintContents = hintContents.replace(reName, "");
						showhintAfterDelay(hintContents, obj, e, tipwidth, isAnImage);
						}
					else
						{
						try {
							let theAction = 'http://' + ip + ':' + port + '/' +
							shortName + '/?req=portNumber';

							const response = await fetch(theAction);
							if (response.ok)
								{
								let resp = await response.text(); 

								if (!isNaN(resp))
									{
									// Replace port with resp in hintContents. And remove
									// server short name.
									let rePort = new RegExp(port);
									hintContents = hintContents.replace(rePort, resp);
									let reName = new RegExp(shortName + "\/");
									hintContents = hintContents.replace(reName, "");
									showhintAfterDelay(hintContents, obj, e, tipwidth, isAnImage);
									}
								}
							}
						catch(error) {
							console.log('Connection error in showWithFreshPort!');
							}
						}
					}
				}
			}
		}
	
	if (!hintShown)
		{
		hintContents = updateImagePortInHintContent(hintContents);
		showhintAfterDelay(hintContents, obj, e, tipwidth, isAnImage);
		}
	}

function updateImagePortInHintContent(hintContent) {
	if (typeof ourSSListeningPort !== 'undefined')
	{
	// src="
	const regex = new RegExp("src=\"http://" + mainIP + ":" + theMainPort + "\/[^\/]+", "g");
	hintContent = hintContent.replace(regex, "src=\"http://" + mainIP + ":" + ourSSListeningPort);
	// src='
	const regex2 = new RegExp("src='http://" + mainIP + ":" + theMainPort + "\/[^\/]+", "g");
	hintContent = hintContent.replace(regex2, "src='http://" + mainIP + ":" + ourSSListeningPort);
	// src=&quot; because you never know....
	const regex3 = new RegExp("src=&quot;http://" + mainIP + ":" + theMainPort + "\/[^\/]+", "g");
	hintContent = hintContent.replace(regex3, "src=\&quot;http://" + mainIP + ":" + ourSSListeningPort);
	}

	return(hintContent);
}
	
function showhintAfterDelay(hintContents, obj, e, tipwidth, isAnImage) {
	"use strict";
	
	if (overAnchorTimer !== null)
		{
		window.clearTimeout(overAnchorTimer);
		overAnchorTimer = null;
		}

	if (document.getElementById("hintbox") !== null)
		{
		hintElement = document.getElementById("hintbox");

		hintElement.innerHTML = hintContents;
		if (isAnImage)
			{
			hintElement.style.width = 'auto';
			}
		else
			{
			hintElement.style.width = "650px";
			}

		setTimeout(function() {
			showhintAtferSettingHTML(hintContents, obj, e, tipwidth, isAnImage);
			}, 200);
		}
}

function showhintAtferSettingHTML(hintContents, obj, e, tipwidth, isAnImage) {
	let rect = hintElement.getBoundingClientRect();
	rect = hintElement.getBoundingClientRect(); // sic
	let currentWidth = rect.width;
	let currentHeight = rect.height;
	tipwidth = currentWidth;
	hintParams.tipWidth = currentWidth;
	hintParams.tipHeight = currentHeight;
	
	if (!hasClass(obj, hitAnchorClassName))
		{
		addClass(obj, hitAnchorClassName);
		}

	removeClass(hintElement, definitionClassName);
	
	hideTipJustInCase(obj);
	
	addClass(obj, anchorClassName);

	// Check if mouse is still over element (which must have
	// class hintanchor or plainhintanchor)
	let stillOver = mouseStillOverTipOwner(obj);

	if (!stillOver)
		{
		hintElement.style.visibility = "hidden";
		hintElement.style.left = "-500px";
		removeClass(obj, anchorClassName);
		return;
		}

	hintElement.style.left = "-500px";
	hintElement.style.top = "-500px";
	if (tipwidth === "")
		{
		tipwidth = "300px";
		}
	hintElement.widthobj = hintElement.style;

	// Horrible hack
	hintContents = hintContents.replace(/__IMSPC__/g, "%20");

	hintParams.hintContents = hintContents;
	hintParams.x = e.clientX;
	
	let viewportOffset = obj.getBoundingClientRect();
	if (viewportOffset.top !== 0)
		{
		hintParams.y = viewportOffset.top;
		}
	else
		{
		// Soldier on, use the cursor position.
		hintParams.y = e.pageY;
		// Change the background color: mostly this will be triggered
		// for a hint showing links to definitions.
		addClass(hintElement, definitionClassName);
		}
	
	hintParams.isAnImage = isAnImage;
	
	// Note we re-get the image_url since it might have changed.
	let image_url = srcURL(hintContents); // Stubbed out, always returns ""
	if (image_url !== "")
		{
		let my_image = new Image();
		my_image.onload = function() {
			positionAndShowHint();
		};
		my_image.src = image_url;
		hintParams.theImage = my_image;
		}
	else
		{
		positionAndShowHint();
		}

	document.addEventListener('mousemove', recordMousePosition);
	document.documentElement.addEventListener('mouseleave', handleMouseLeave);

	if (typeof window.ontouchstart === 'undefined')
		{
		overAnchorTimer = window.setTimeout(function() {
			hideTipIfMouseHasLeft(obj);
		}, 500);
		}
}


function handleMouseLeave() {
	hideTip();
}

// If see src="something", return something, else "".
// The something should be in single or double quotes of some sort.
// Stubbed out, not needed at the moment.
function srcURL(hintContents) {
	let image_url = "";
	// TEST ONLY
	return("");
	
	let arrayMatch = null;

	if ((arrayMatch = /src='([^']+?)'/.exec(hintContents)) ||
		(arrayMatch = /src="([^"]+?)"/.exec(hintContents)) ||
		(arrayMatch = /src=\&quot\;(.+?)\&quot\;/.exec(hintContents)) ||
		(arrayMatch = /src=\&apos\;(.+?)\&apos\;/.exec(hintContents)) )
		{
		image_url = arrayMatch[1];
		}

	return(image_url);
}

function hideTipIfMouseHasLeft(obj) {
	if (mouseStillOverTipOwner(obj) || mouseStillOverHintbox())
		{
		overAnchorTimer = window.setTimeout(function() {
			hideTipIfMouseHasLeft(obj);
		}, 500);
		}
	else
		{
		hideTip();
		}
}

function hideTipJustInCase(obj) {
	hideTip();
}

function mouseStillOverTipOwner(obj) {
	let stillOver = false;

	let anks = document.getElementsByClassName(anchorClassName);
	let el = null;
	if (anks.length > 0)
		{
		el = anks[0];
		}
	else
		{
		el = obj;
		}

	if (el !== null)
		{
		let c = window.getComputedStyle(el).getPropertyValue('border-top-style');
		stillOver = (c === 'hidden') ? true : false;
		if (!stillOver)
			{
			let hoveredElement = document.querySelectorAll(':hover');
			hoveredElement = hoveredElement[hoveredElement.length - 1];
			if (typeof(hoveredElement) !== 'undefined' && typeof(hoveredElement.innerHTML) !== 'undefined' && hoveredElement.innerHTML === obj.innerHTML)
				{
				stillOver = true;
				}
			}
		}

	return (stillOver);
}

function mouseStillOverHintbox() {
	let stillOver = false;

	let elements = document.elementsFromPoint(cursor_x, cursor_y);

	for (var i = 0; i < elements.length; i++) {
		let elementId = elements[i].id;
		if (elementId === "hintbox")
			{
			stillOver = true;
			break;
			}
		}

	return(stillOver);
}

function recordMousePosition(evt) {
	cursor_x = evt.pageX;
	cursor_y = evt.pageY;
}

function hideTip(e) {
	hintElement.style.visibility = "hidden";
	hintElement.innerHTML = '';
	hintElement.style.left = "-500px";
	hintElement.style.width = "auto";
	hintElement.style.height = "auto";
	let anks = document.getElementsByClassName(anchorClassName);
	if (anks.length > 0)
		{
		for (i = anks.length - 1; i >= 0; --i)
			{
			removeClass(anks[i], anchorClassName);
			}
		}

	
	document.removeEventListener('mousemove', recordMousePosition);
	document.removeEventListener('mouseleave', handleMouseLeave);
}

function touchhidetip(e) {
	hintElement.style.visibility = "hidden";
	hintElement.style.left = "-500px";
}

function createhintbox() {
	let divblock = document.createElement("div");
	divblock.setAttribute("id", "hintbox");
	document.body.appendChild(divblock);

	hintElement = document.getElementById("hintbox");
	if (hintElement === null)
		{
		console.log("tooptip.js#createhintbox cannot create hintbox!");
		return;
		}
	hintElement.style.visibility = "hidden";
	hintElement.style.left = "-500px";
	
	if (shOnMobile)
		{
		hintElement.addEventListener("touchstart", function(e) {touchhidetip();});
		}
}

// For remote iPad "debugging" since remotedebug_ios_webkit_adapter has stopped working.
// For Viewer, errorID element is up near the top of the window.
// (iPad has been abandoned, too hard to debug.)
function writeMessageToWindow(str) {
	let errorElem = document.getElementById(errorID);
	if (errorElem !== null)
		{
		errorElem.innerHTML = "<p>" + str + "</p>";
		}
}

if (window.addEventListener)
	window.addEventListener("load", createhintbox, false);
else if (window.attachEvent)
	window.attachEvent("onload", createhintbox);
else if (document.getElementById)
	window.onload = createhintbox;
