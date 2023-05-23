// tooltip.js: show a "tooltip" with text or an image, the main call is showhint().
/**********************************************************************************************
 * Show Hint script- (c) Dynamic Drive (www.dynamicdrive.com) 
 * This notice MUST stay intact for legal use 
 * Visit http://www.dynamicdrive.com/ for this script and 100s more.
 **********************************************************************************************/
// (Significantly modified from the original 2018-19 and 2023 for use with IntraMine.)
// IntraMine use, see eg showhint() calls in
// intramine_linker.pl#GetImageFileRep(), intramine_boilerplate.pl#ThePage().

// Where to place the hint, relative to cursor position.
const DIRECTION_BELOW = 0;
const DIRECTION_ABOVE = 1;
const DIRECTION_RIGHT = 2;
const DIRECTION_LEFT = 3;

let anchorClassName = "showHintAnchorClass"; 	// applied while mouse over element
let hitAnchorClassName = "invisiblehintanchor"; // applied if not present in element, permanently
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
	let tipwidth = hintParams.tipwidth;
	let isAnImage = hintParams.isAnImage;
	let gap = 10; // gap between cursor and tip
	let windowHeight = window.innerHeight - gap;
	let windowWidth = window.innerWidth - gap;
	let hintWidth = 450;
	let hintHeight = hintElement.offsetHeight;
	if (isAnImage)
		{
		hintWidth = hintParams.theImage.width;
		hintHeight = hintParams.theImage.height;
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
	
	// For now, just scale images. Text tips are usually small enough.
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
	
	if (isAnImage)
		{
		hintContents =
			hintContents.slice(0, -1) + " width='" + hintWidth + "' height='" + hintHeight + "'>";
		}

	hintElement.innerHTML = hintContents;

	// Set width and height for an image. For text, set the desired width and let it flow.
	// hintElement.style.width = hintWidth + "px";
	if (isAnImage)
		{
		hintElement.style.height = hintHeight + "px";
		hintElement.style.width = hintWidth + "px";
		}
	else
		{
		hintElement.style.height = '';
		}

	hintElement.style.visibility = "visible";
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
		top = y + gap + "px";
		left = (x + gap + hintWidth <= windowWidth) ? (x + gap) : windowWidth - hintWidth - gap;
		left = (left < 0) ? "0" : left + "px";
		}
	else if (bestDirection === DIRECTION_ABOVE) // above
		{
		if (y - hintHeight - gap >= 0)
			{
			top = y - hintHeight - gap + "px";
			}
		else
			{
			top = "0";
			}
		let left = (x + gap + hintWidth <= windowWidth) ? (x + gap) : windowWidth - hintWidth - gap;
		left = (left < 0) ? "0" : left + "px";
		}
	else if (bestDirection === DIRECTION_RIGHT) // right
		{
		left = x + gap + "px";
		let top =
			(y + gap + hintHeight <= windowHeight) ? (y + gap) : windowHeight - hintHeight - gap;
		top = (top < 0) ? "0" : top + "px";
		}
	else
		// if (bestDirection === DIRECTION_LEFT) // left
		{
		if (x - hintWidth - gap >= 0)
			{
			left = x - hintWidth - gap + "px";
			}
		else
			{
			left = "0";
			}
		let top =
			(y + gap + hintHeight <= windowHeight) ? (y + gap) : windowHeight - hintHeight - gap;
		top = (top < 0) ? "0" : top + "px";
		}

	let topLeft = {};
	topLeft.top = top;
	topLeft.left = left;

	return(topLeft);
}

function showhint(hintContents, obj, e, tipwidth, isAnImage) {
	"use strict";
	
	setTimeout(function() {
	showWithFreshPort(hintContents, obj, e, tipwidth, isAnImage);
	}, 100);
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
		showhintAfterDelay(hintContents, obj, e, tipwidth, isAnImage);
		}
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

		if (!hasClass(obj, hitAnchorClassName))
			{
			addClass(obj, hitAnchorClassName);
			}
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
		if (hintElement.innerHTML.indexOf('<img') == 0)
			{
			hintElement.style.backgroundColor = 'lightyellow';
			hintElement.style.border = 'thin dotted black';
			}
		hintElement.style.width = tipwidth;
		if (!isAnImage)
			{
			// Reset height to 'auto'.
			hintElement.style.height = '';
			}

		hintParams.hintContents = hintContents;
		hintParams.x = e.clientX;
		hintParams.y = e.clientY;
		hintParams.tipwidth = tipwidth;
		hintParams.isAnImage = isAnImage;
		
		// Note we re-get the image_url since it might have changed.
		let image_url = srcURL(hintContents);
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

		obj.onmouseout = hidetip;

		if (typeof window.ontouchstart === 'undefined')
			{
			overAnchorTimer = window.setTimeout(function() {
				hideTipIfMouseHasLeft(obj);
			}, 1000);
			}
		}
}

// If see src="something", return something, else "".
// The something should be in single or double quotes of some sort.
function srcURL(hintContents) {
	let image_url = "";
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
	if (mouseStillOverTipOwner(obj))
		{
		overAnchorTimer = window.setTimeout(function() {
			hideTipIfMouseHasLeft(obj);
		}, 1000);
		}
	else
		{
		hidetip();
		removeClass(obj, anchorClassName);
		}
}

function mouseStillOverTipOwner(obj) {
	let stillOver = false;

	let anks = document.getElementsByClassName(anchorClassName);
	if (anks.length > 0)
		{
		let el = anks[0];
		let c = window.getComputedStyle(el).getPropertyValue('border-top-style');
		stillOver = (c === 'hidden') ? true : false;
		}
	return (stillOver);
}

function hidetip(e) {
	hintElement.style.visibility = "hidden";
	hintElement.style.left = "-500px";
	let anks = document.getElementsByClassName(anchorClassName);
	if (anks.length > 0)
		{
		for (i = anks.length - 1; i >= 0; --i)
			{
			removeClass(anks[i], anchorClassName);
			}
		}
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
