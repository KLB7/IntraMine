/**
 * files.js: for intramine_filetree.pl. Uses jqueryFileTree.js to display two file browser
 * lists. All files that IntraMine can handle have Viewer links, and most also have Editor links.
 * Images are displayed in-window if the cursor pauses over them, elsewhere called "hover" images.
 * For that, see intramine_filetree.pl#GetDirsAndFiles().
 */

window.addEventListener("load", doResize);
window.addEventListener("resize", doResize);

let onMobile = false; // Set below, true if we have touch events.
if (typeof window.ontouchstart !== 'undefined')
	{
	onMobile = true;
	}

// Using an app for editing isn't possible on an iPad.
if (onMobile)
	{
	useAppForEditing = false;
	}

function getRandomInt(min, max) {
	return Math.floor(Math.random() * (max - min + 1) + min);
}

// Ask jqueryFileTree.js to cook up two file trees. Called at the bottom of this file.
function startFileTreeUp() {
	$('#scrollDriveListLeft').fileTree({
		root : 'C:/',
		script : 'http://' + theHost + ':' + thePort + '/',
		expandSpeed : 200,
		collapseSpeed : 200,
		multiFolder : true,
		pacifierID : 'spinner',
		remote : weAreRemote,
		allowEdit : allowEditing,
		useApp : useAppForEditing,
		mobile : onMobile
	}, function(el, file) {
		openTheFile(el, file);
	}, function(dir) {
		dummyCollapse(dir);
	}, function() {
		doResize();
	});

	$('#scrollDriveListRight').fileTree({
		root : 'C:/',
		script : 'http://' + theHost + ':' + thePort + '/',
		expandSpeed : 200,
		collapseSpeed : 200,
		multiFolder : true,
		pacifierID : 'spinner',
		remote : weAreRemote,
		allowEdit : allowEditing,
		useApp : useAppForEditing,
		mobile : onMobile
	}, function(el, file) {
		openTheFile(el, file);
	}, function(dir) {
		dummyCollapse(dir);
	}, function() {
		doResize();
	});
}

// Link clicked, respond by opening the file in IntraMine's Viewer or an editor, depending
// on which link for a file was clicked. The "edit" link is associated with an edit icon
// image, currently a tiny pencil.
function openTheFile(el, file) {
	let errM = document.getElementById(errorID);
	errM.innerHTML = '&nbsp;';

	// For some reason File Tree tacks a '/' on at end of file name.
	let trimmedFile = file.replace(/\/$/, '');
	trimmedFile = encodeURIComponent(trimmedFile);

	let sFieldType = el.toUpperCase();
	if (sFieldType === "IMG") // local or remote, **edit** pencil icon (not an "image")
		{
		if (useAppForEditing && !onMobile)
			{
			editWithPreferredApp(trimmedFile);
			}
		else // Use IntraMine's Editor service
			{
			editWithIntraMine(trimmedFile);
//			let url =
//			'http://' + theHost + ':' + theMainPort + '/' + editorShortName + '/?href=' + trimmedFile
//					+ '&rddm=' + String(getRandomInt(1, 65000));
//			window.open(url, "_blank");
			}
		}
	else
		// Viewer anchor, read only
		{
		let url =
		'http://' + theHost + ':' + theMainPort + '/' + viewerShortName + '/?href='
			+ trimmedFile + '&rddm=' + String(getRandomInt(1, 65000));
		window.open(url, "_blank");
		}
}

function dummyCollapse(dir) {

}

// Open file in IntraMine's Editor (intramine_editor.pl).
function editWithIntraMine(href) {
	showSpinner();
	let request = new XMLHttpRequest();
	let theRequest = 'http://' + theHost + ':' + theMainPort + '/'
					+ editorShortName + '/?req=portNumber';
	request.open('get', theRequest, true);
	
	request.onload = function() {
		  if (request.status >= 200 && request.status < 400) {
			// Success?
			let resp = request.responseText;
			if (isNaN(resp))
				{
				let e1 = document.getElementById(errorID);
				e1.innerHTML = '<p>Error, server said ' + resp + '!</p>';
				}
			else
				{
				let properHref = href.replace(/^file\:\/\/\//, '');
				let url = 'http://' + theHost + ':' + resp + '/' + editorShortName + '/?href=' +
							properHref + '&rddm=' + String(getRandomInt(1, 65000));
	
				window.open(url, "_blank");
				}
			hideSpinner();
		  } else {
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(errorID);
			e1.innerHTML = '<p>Error, server reached but it could not handle request for port number!</p>';
			hideSpinner();
		  }
		};
		
		request.onerror = function() {
			// There was a connection error of some sort
			let e1 = document.getElementById(errorID);
			e1.innerHTML = '<p>Connection error while attempting to retrieve port number!</p>';
			hideSpinner();
		};
		
	request.send();
}

// Request Opener port from main at theMainPort, then call Opener service directly using
// the right port.
function editWithPreferredApp(href) {
	let errM = document.getElementById(errorID);
	errM.innerHTML = '&nbsp;';
	showSpinner();

	let request = new XMLHttpRequest();
//	let theRequest = 'http://' + theHost + ':' + theMainPort + '/Opener/?req=portNumber';
	let theRequest = 'http://' + theHost + ':' + theMainPort + '/' + openerShortName + '/?req=portNumber';
	request.open('get', theRequest, true);

	request.onload =
			function() {
				if (request.status >= 200 && request.status < 400)
					{
					// Success?
					let resp = request.responseText;
					if (isNaN(resp))
						{
						let e1 = document.getElementById(errorID);
						e1.innerHTML = 'Error, server said ' + resp + '!';
						}
					else
						{
						appEditWithPort(href, resp);
						}
					hideSpinner();
					}
				else
					{
					// We reached our target server, but it returned an error
					let e1 = document.getElementById(errorID);
					e1.innerHTML =
							'Error, server reached but it could not handle request for port number!';
					hideSpinner();
					}
			};

	request.onerror = function() {
		// There was a connection error of some sort
		let e1 = document.getElementById(errorID);
		e1.innerHTML = 'Connection error while attempting to retrieve port number!';
		hideSpinner();
	};

	request.send();
}

// Punt the edit request to the Opener service (intramine_open_with.pl), which will
// call the editor specified in data/intramine_config.txt to open the file.
function appEditWithPort(href, openerPort) {
	showSpinner();
	let request = new XMLHttpRequest();
	let properHref = href.replace(/^file\:\/\/\//, '');
	
//	let theRequest =
//			'http://' + theHost + ':' + openerPort + '/Opener/?req=open&file=' + properHref;
	let theRequest =
	'http://' + theHost + ':' + openerPort + '/' + openerShortName + '/?req=open&clientipaddress=' +
		clientIPAddress + '&file=' + properHref;
	request.open('get', theRequest, true);

	request.onload = function() {
		if (request.status >= 200 && request.status < 400)
			{
			// Success?
			let resp = request.responseText;
			if (resp !== 'OK')
				{
				let e1 = document.getElementById(errorID);
				e1.innerHTML = 'Error, server said ' + resp + '!';
				}
			hideSpinner();
			}
		else
			{
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(errorID);
			e1.innerHTML = 'Error, server reached but it could not open the file!';
			hideSpinner();
			}
	};

	request.onerror = function() {
		// There was a connection error of some sort
		let e1 = document.getElementById(errorID);
		e1.innerHTML = 'Connection error while attempting to open file!';
		hideSpinner();
	};

	request.send();
}


// Re-init the tree display if a drive is selected using the drive dropdown at top of window.
function driveChanged(tree_id, value) {
	showSpinner();
	let e1 = document.getElementById(tree_id);
	e1.innerHTML = '';
	$('#' + tree_id).fileTree({
		root : value,
		script : 'http://' + theHost + ':' + thePort + '/',
		expandSpeed : 200,
		collapseSpeed : 200,
		multiFolder : true,
		pacifierID : 'spinner',
		remote : weAreRemote,
		allowEdit : allowEditing,
		useApp : useAppForEditing,
		mobile : onMobile
	}, function(el, file) {
		openTheFile(el, file);
	}, function(dir) {
		dummyCollapse(dir);
	}, function() {
		doResize();
	});
}

function doResize() {
	let el = document.getElementById(contentID);

	let pos = getPosition(el);
	let windowHeight = window.innerHeight;
	let elHeight = windowHeight - pos.y;
	el.style.height = elHeight - 20 + "px";

	let windowWidth = window.innerWidth;
	el.style.width = windowWidth - 4 + "px";
	
	// Hide the spinner, and replace it with the help question mark.
	hideSpinner();
}

// This is for the "Open" button at the top of the window. If the associated text in
// the pathFieldElement looks like a full path, ask the Viewer to open it. For such a
// direct request, we can just ask the Main server to redirect to any running Viewer.
// Otherwise, for a presumed partial path, we would like to first ask the Viewer to provide
// a speculative full path for what was typed, and then open that full path in the Viewer.
// Which is what OpenAutoLink() does.
function openUserPath(oFormElement) {
	if (!oFormElement.action)
		{
		return;
		}
	let pathFieldElement = document.getElementById("openfile");
	let path = pathFieldElement.value;
	path = path.replace(/\\/g, "/");

	let fullPathMatch = /[a-zA-Z]\:\//.exec(path);
	if (fullPathMatch != null)
		{
		// href='http://192.168.1.132:81/Viewer/?href=c:/perlprogs/mine/images_for_web_server/ser
		// ver-128x128 60.png'
//		let url =
//				'http://' + theHost + ':' + theMainPort + '/Viewer/?href='
//						+ encodeURIComponent(path) + '&rddm=' + String(getRandomInt(1, 65000));
		let url =
		'http://' + theHost + ':' + theMainPort + '/' + viewerShortName + '/?href='
				+ encodeURIComponent(path) + '&rddm=' + String(getRandomInt(1, 65000));
		window.open(url, "_blank");
		}
	else
		{
		openAutoLink(path);
		}
}

// Request Linker port from main at theMainPort, then call Linker directly using
// the right port to get a fullPath, then get port for Viewer and ask Viewer to open the path.
function openAutoLink(path) {
	let errM = document.getElementById(errorID);
	errM.innerHTML = '&nbsp;';
	showSpinner();

	let request = new XMLHttpRequest();
	let theRequest = 'http://' + theHost + ':' + theMainPort + '/' +
						linkerShortName + '/?req=portNumber';
	request.open('get', theRequest, true);
	request.setRequestHeader("Content-Type", "text/plain;charset=UTF-8");

	request.onload =
			function() {
				if (request.status >= 200 && request.status < 400)
					{
					// Success?
					let resp = request.responseText; // Linker port number
					if (isNaN(resp))
						{
						let e1 = document.getElementById(errorID);
						e1.innerHTML = 'Error, server said ' + resp + '!';
						}
					else
						{
						openAutoLinkWithPort(path, resp);
						}
					hideSpinner();
					}
				else
					{
					// We reached our target server, but it returned an error
					let e1 = document.getElementById(errorID);
					e1.innerHTML =
							'Error, server reached but it could not handle request for port number!';
					hideSpinner();
					}
			};

	request.onerror = function() {
		// There was a connection error of some sort
		let e1 = document.getElementById(errorID);
		e1.innerHTML = 'Connection error while attempting to retrieve port number!';
		hideSpinner();
	};

	request.send();
}

// Ask Linker for full path, call openFullPath to ask Viewer to open it.
function openAutoLinkWithPort(path, linkerPort) {
	showSpinner();
	let oReq = new XMLHttpRequest();

	oReq.onload =
			function() {
				if (oReq.status >= 200 && oReq.status < 400)
					{
					// Success! Provided response wasn't 'nope'.
					let fullPath = oReq.responseText;
					if (fullPath !== 'nope')
						{
						openFullPath(fullPath);
						}
					else
						{
						let e1 = document.getElementById(errorID);
						e1.innerHTML = 'File not found!';
						}
					hideSpinner();
					}
				else
					{
					// We reached our target server, but it returned an error
					hideSpinner();
					let e1 = document.getElementById(errorID);
					e1.innerHTML = 'Error, server reached but it could not open the file!';
					}
			};
	oReq.onerror = function() {
		let e1 = document.getElementById(errorID);
		e1.innerHTML = 'File not found!';
		hideSpinner();
	};

	let theAction =
	'http://' + theHost + ':' + linkerPort + '/' + linkerShortName + '/?req=autolink&partialpath='
			+ encodeURIComponent(path);
	oReq.open('get', theAction, true);
	oReq.setRequestHeader("Content-Type", "text/plain;charset=UTF-8");
	oReq.send();
}

// Get Viewer port, ask Viewer to open fullPath.
function openFullPath(fullPath) {
	let errM = document.getElementById(errorID);
	errM.innerHTML = '&nbsp;';
	showSpinner();
	
	let request = new XMLHttpRequest();
	let theRequest = 'http://' + theHost + ':' + theMainPort + '/' +
						viewerShortName + '/?req=portNumber';
	request.open('get', theRequest, true);
	request.setRequestHeader("Content-Type", "text/plain;charset=UTF-8");
	
	request.onload =
			function() {
				if (request.status >= 200 && request.status < 400)
					{
					// Success?
					let resp = request.responseText; // Viewer port number
					if (isNaN(resp))
						{
						let e1 = document.getElementById(errorID);
						e1.innerHTML = 'Error, server said ' + resp + '!';
						}
					else
						{
						openFullPathWithViewerPort(fullPath, resp);
						}
					hideSpinner();
					}
				else
					{
					// We reached our target server, but it returned an error
					let e1 = document.getElementById(errorID);
					e1.innerHTML =
							'Error, server reached but it could not handle request for port number!';
					hideSpinner();
					}
			};
	
	request.onerror = function() {
		// There was a connection error of some sort
		let e1 = document.getElementById(errorID);
		e1.innerHTML = 'Connection error while attempting to retrieve port number!';
		hideSpinner();
	};
	
	request.send();
	}

function openFullPathWithViewerPort(fullPath, viewerPort) {
	showSpinner();
//	let oReq = new XMLHttpRequest();
	let url =
	'http://' + theHost + ':' + viewerPort + '/' + viewerShortName + '/?href='
			+ encodeURIComponent(fullPath) + '&rddm='
			+ String(getRandomInt(1, 65000));
	let didit = window.open(url, "_blank");
	if (didit === null)
		{
		if (typeof window.ontouchstart !== 'undefined')
			{
			alert("Please turn off your browser's pop-up blocker, with"
					+ " Settings->Safari->Block Pop-ups or equivalent. If you're using"
					+ "Chrome, you can instead select 'Always show' at the bottom"
					+ "of this window.");
			}
		}
	
	
//	oReq.onload =
//			function() {
//				if (oReq.status >= 200 && oReq.status < 400)
//					{
//					// Success! Provided response wasn't 'nope'.
//					let fullPath = oReq.responseText;
//					if (fullPath !== 'nope')
//						{
//						let url =
//						'http://' + theHost + ':' + viewerPort + '/' + viewerShortName + '/?href='
//								+ encodeURIComponent(fullPath) + '&rddm='
//								+ String(getRandomInt(1, 65000));
//						let didit = window.open(url, "_blank");
//						if (didit === null)
//							{
//							if (typeof window.ontouchstart !== 'undefined')
//								{
//								alert("Please turn off your browser's pop-up blocker, with"
//										+ " Settings->Safari->Block Pop-ups or equivalent. If you're using"
//										+ "Chrome, you can instead select 'Always show' at the bottom"
//										+ "of this window.");
//								}
//							}
//						
//						
//						}
//					else
//						{
//						let e1 = document.getElementById(errorID);
//						e1.innerHTML = 'File not found!';
//						}
//					hideSpinner();
//					}
//				else
//					{
//					// We reached our target server, but it returned an error
//					hideSpinner();
//					let e1 = document.getElementById(errorID);
//					e1.innerHTML = 'Error, server reached but it could not open the file!';
//					}
//			};
//	oReq.onerror = function() {
//		let e1 = document.getElementById(errorID);
//		e1.innerHTML = 'File not found!';
//		hideSpinner();
//	};
//	
//	let theAction =
//	'http://' + theHost + ':' + linkerPort + '/' + linkerShortName + '/?req=autolink&partialpath='
//			+ encodeURIComponent(path);
//	oReq.open('get', theAction, true);
//	oReq.setRequestHeader("Content-Type", "text/plain;charset=UTF-8");
//	oReq.send();
}

// Shrink/expand the file tree on the right. Initially it is shrunk, most of the time
// only one tree is wanted. Probably.
function toggleRightListWidth() {
	let rightTree = document.getElementById('fileTreeRight');
	if (rightTree === null)
		{
		return;
		}
	let rightWidthStr = window.getComputedStyle(rightTree, null).getPropertyValue('width');
	let rightWidth = parseInt(rightWidthStr, 10);
	let treeContainer = document.getElementById('scrollAdjustedHeight');
	let treeWidthStr = window.getComputedStyle(treeContainer, null).getPropertyValue('width');
	let treeContainerWidth = parseInt(treeWidthStr, 10);
	let currentRightWidthPC = 100 * rightWidth / treeContainerWidth;
	
	if (currentRightWidthPC < 40) // right tree is shrunk down
		{
		document.getElementById('fileTreeRight').style.width = "48%";
		document.getElementById('fileTreeLeft').style.width = "48%";
		}
	else // both trees have equal width
		{
		document.getElementById('fileTreeRight').style.width = "28%";
		document.getElementById('fileTreeLeft').style.width = "70%";
		}
}

function currentSortOrder() {
	let sortElem = document.getElementById( "sort_1" );
	return( sortElem.options[ sortElem.selectedIndex ].value );
	}

window.addEventListener("load", startFileTreeUp);
