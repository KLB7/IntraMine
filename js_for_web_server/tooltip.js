// tooltip.js: show a "tooltip" with text or an image, the main call is showhint().
/**********************************************************************************************
 * Show Hint script- (c) Dynamic Drive (www.dynamicdrive.com) 
 * This notice MUST stay intact for legal use 
 * Visit http://www.dynamicdrive.com/ for this script and 100s more.
 **********************************************************************************************/
// (Significantly modified from the original 2018-19 for use with IntraMine.)
// IntraMine use, see eg showhint() calls in
// intramine_file_viewer_cm.pl#GetImageFileRep(), intramine_boilerplate.pl#ThePage().

let anchorClassName = "showHintAnchorClass"; 	// applied while mouse over element
let hitAnchorClassName = "invisiblehintanchor"; // applied if not present in element, permanently
let overAnchorTimer = null;
let shMainPort = 0; // See setMainPort() just below.
let shOurServerPort = (typeof ourServerPort !== 'undefined') ? ourServerPort: 0;
let shOnMobile = (typeof window.ontouchstart !== 'undefined') ? true : false;

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
// Helper function to get an element's exact position
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

let ie = document.all;
let ns6 = document.getElementById && !document.all;

let dropmenuobj = {};
let loadParams = {};

function positionAndShowHint() {
	"use strict";
	let menucontents = loadParams.menucontents;
	let x = loadParams.x;
	let y = loadParams.y;
	let tipwidth = loadParams.tipwidth;
	let isAnImage = loadParams.isAnImage;
	let gap = 10; // gap between cursor and tip
	let windowHeight = window.innerHeight - gap;
	let windowWidth = window.innerWidth - gap;
	let hintWidth = 450;
	let hintHeight = dropmenuobj.offsetHeight;
	if (isAnImage)
		{
		hintWidth = loadParams.theImage.width;
		hintHeight = loadParams.theImage.height;
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
	dropmenuobj.style.top = tl.top;
	dropmenuobj.style.left = tl.left;
	
	if (isAnImage)
		{
		menucontents =
			menucontents.slice(0, -1) + " width='" + hintWidth + "' height='" + hintHeight + "'>";
		}

	dropmenuobj.innerHTML = menucontents;

	// Set width and height for an image. For text, set the desired width and let it flow.
	// dropmenuobj.style.width = hintWidth + "px";
	if (isAnImage)
		{
		dropmenuobj.style.height = hintHeight + "px";
		dropmenuobj.style.width = hintWidth + "px";
		}
	else
		{
		dropmenuobj.style.height = '';
		}

	dropmenuobj.style.visibility = "visible";

}

//Calculate tip all four ways, pick the way that produces least shrinkage.
//Preference order: below, above, right, left.
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
	let temp = [];
	temp[0] = (belowScaleFactor > 1.0) ? 1.0 : belowScaleFactor;
	temp[1] = (aboveScaleFactor > 1.0) ? 1.0 : aboveScaleFactor;
	temp[2] = (rightScaleFactor > 1.0) ? 1.0 : rightScaleFactor;
	temp[3] = (leftScaleFactor > 1.0) ? 1.0 : leftScaleFactor;
	// bestDirection:
	// 0 == show hint below cursor x,y
	// 1 == show hint above
	// 2 == show hint to right of cursor
	// 3 == show hint to left of cursor
	let bestDirection = -1;
	let i = 0;
	for (i = temp.length - 1; i >= 0; i -= 1)
		{
		if (temp[i] >= 1.0)
			{
			bestDirection = i;
			}
		}
	
	if (bestDirection < 0) // all temp[] are < 1.0
		{
		let curValue = temp[0];
		bestDirection = 0;
		for (i = 1; i < temp.length; i++)
			{
			if (temp[i] > curValue)
				{
				curValue = temp[i];
				bestDirection = i;
				}
			}
		}

	let ds = {};
	ds.bestDirection = bestDirection;
	ds.scaleFactor = temp[bestDirection];
	return(ds);
}

// Position tip (and scale if image).
// Try to keep tip close to mouse x,y position.
function tipTopAndLeft(bestDirection, x, y, hintWidth, hintHeight, windowWidth, windowHeight, gap) {
	let left = 0;
	let top = 0;
	
	if (bestDirection === 0) // below
		{
		top = y + gap + "px";
		left = (x + gap + hintWidth <= windowWidth) ? (x + gap) : windowWidth - hintWidth - gap;
		left = (left < 0) ? "0" : left + "px";
		}
	else if (bestDirection === 1) // above
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
	else if (bestDirection === 2) // right
		{
		left = x + gap + "px";
		let top =
			(y + gap + hintHeight <= windowHeight) ? (y + gap) : windowHeight - hintHeight - gap;
		top = (top < 0) ? "0" : top + "px";
		}
	else
		// if (bestDirection === 3) // left
		{
		if (x - hintWidth - gap >= 0)
			{
			left = x - hintWidth - gap + "px";
			}
		else
			{
			dropmenuobj.style.left = "0";
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

function showhint(menucontents, obj, e, tipwidth, isAnImage) {
	"use strict";
	
	setTimeout(function() {
	showWithFreshPort(menucontents, obj, e, tipwidth, isAnImage);
	}, 100);
}

// Special handling for some images: if menucontents looks like
//<img src="http://192.168.1.132:81/Viewer/imagefile.png">
// then we take what's in the "81" position as IntraMine's Main port, and what's in
// the "Viewer" spot as a Short name. Then call back to the Main port requesting a free
// port for the Short name, and replace the "81" in menucontents with the free port number.
// Also strip out the Short name, it was needed only to tell Main which server we wanted.
// For other img src values, just pass them along to showhinAfterDelay unchanged.
// (The fancy footwork with the port is an attempt to get the port number of a service that is
// running and not under maintenance. This allows showhint to show the image if there are two
// or more instances of a service running, even if one is doing maintenance.)
async function showWithFreshPort(menucontents, obj, e, tipwidth, isAnImage) {
	if (isAnImage)
		{
		let arrayMatch = /src='([^']+)'/.exec(menucontents);
		if (arrayMatch === null)
			{
			arrayMatch = /src="([^"]+)"/.exec(menucontents);
			}
		if (arrayMatch === null)
			{
			arrayMatch = /src=\&quot\;(.+)\&quot\;/.exec(menucontents);
			}
		if (arrayMatch !== null)
			{
			let image_url = arrayMatch[1];
			let urlMatch = /^http\:\/\/([0-9\.]+)\:(\d+)\/([A-Za-z_]+)\/(.+?)$/.exec(image_url);
			if (urlMatch !== null)
				{
				let ip = urlMatch[1];
				let port = urlMatch[2];
				let shortName = urlMatch[3];
				let path = urlMatch[4];
				
				if (port === shMainPort) // request good port number from shMainPort
					{
					// However, if we're on an iPad (shOnMobile), try to use our current server's
					// port rather than asking Main to supply a fresh one - Apple really doesn't
					// like any hanky panky with the port number.
					if (shOnMobile && port === shMainPort && shOurServerPort !== 0)
						{
						let rePort = new RegExp(port);
						menucontents = menucontents.replace(rePort, shOurServerPort);
						let reName = new RegExp(shortName + "\/");
						menucontents = menucontents.replace(reName, "");
						showhintAfterDelay(menucontents, obj, e, tipwidth, isAnImage);
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
									// Replace port with resp in menucontents. And remove
									// server short name.
									let rePort = new RegExp(port);
									menucontents = menucontents.replace(rePort, resp);
									let reName = new RegExp(shortName + "\/");
									menucontents = menucontents.replace(reName, "");
									showhintAfterDelay(menucontents, obj, e, tipwidth, isAnImage);
									}
								}
							}
						catch(error) {
							// console.log('Connection error in showWithFreshPort!);
							}
						}
					}
				else // use supplied port as-is
					{
					showhintAfterDelay(menucontents, obj, e, tipwidth, isAnImage);
					}
				}
			else
				{
				showhintAfterDelay(menucontents, obj, e, tipwidth, isAnImage);
				}
			}
		else
			{
			showhintAfterDelay(menucontents, obj, e, tipwidth, isAnImage);
			}
		}
	else
		{
		showhintAfterDelay(menucontents, obj, e, tipwidth, isAnImage);
		}
	}

function showhintAfterDelay(menucontents, obj, e, tipwidth, isAnImage) {
	"use strict";
	
	let image_url = "";
	if (isAnImage)
		{
		let arrayMatch = /src='([^']+)'/.exec(menucontents);
		if (arrayMatch === null)
			{
			arrayMatch = /src="([^"]+)"/.exec(menucontents);
			}
		if (arrayMatch === null)
			{
			arrayMatch = /src=\&quot\;(.+)\&quot\;/.exec(menucontents);
			}
		if (arrayMatch === null)
			{
			arrayMatch = /src=\&apos\;(.+)\&apos\;/.exec(menucontents);
			}
		if (arrayMatch !== null)
			{
			image_url = arrayMatch[1];
			}
		}

	dropmenuobj = document.getElementById("hintbox");
	dropmenuobj.innerHTML = menucontents;
	
	if (overAnchorTimer !== null)
		{
		window.clearTimeout(overAnchorTimer);
		overAnchorTimer = null;
		}

	if (document.getElementById("hintbox"))
		{
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
			dropmenuobj.style.visibility = "hidden";
			dropmenuobj.style.left = "-500px";
			removeClass(obj, anchorClassName);
			return;
			}

		dropmenuobj.style.left = "-500px";
		dropmenuobj.style.top = "-500px";
		if (tipwidth === "")
			{
			tipwidth = "300px";
			}
		dropmenuobj.widthobj = dropmenuobj.style;
		if (dropmenuobj.innerHTML.indexOf('<img') == 0)
			{
			dropmenuobj.style.backgroundColor = 'lightyellow';
			dropmenuobj.style.border = 'thin dotted black';
			}
		dropmenuobj.style.width = tipwidth;
		if (!isAnImage)
			{
			// Reset height to 'auto'.
			dropmenuobj.style.height = '';
			}

		loadParams.menucontents = menucontents;
		loadParams.x = e.clientX;
		loadParams.y = e.clientY;
		loadParams.tipwidth = tipwidth;
		loadParams.isAnImage = isAnImage;
		
		if (image_url !== "")
			{
			let my_image = new Image();
			my_image.onload = function() {
				positionAndShowHint();
			};
			my_image.src = image_url;
			loadParams.theImage = my_image;
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
	dropmenuobj.style.visibility = "hidden";
	dropmenuobj.style.left = "-500px";
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
	dropmenuobj.style.visibility = "hidden";
	dropmenuobj.style.left = "-500px";
}

function createhintbox() {
	let divblock = document.createElement("div");
	divblock.setAttribute("id", "hintbox");
	document.body.appendChild(divblock);

	dropmenuobj = document.getElementById("hintbox");
	dropmenuobj.style.visibility = "hidden";
	dropmenuobj.style.left = "-500px";
	
	if (shOnMobile)
		{
		dropmenuobj.addEventListener("touchstart", function(e) {touchhidetip();});
		}
}

// For remote iPad "debugging" since remotedebug_ios_webkit_adapter has stopped working.
// For Viewer, errorID element is up near the top of the window.
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
