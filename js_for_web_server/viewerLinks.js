/**
 * viewerLinks.js: handle links in file views. Used in intramine_viewer.pl
 *  for both CodeMirror and non-CodeMirror source and text files.
 *  See eg intramine_linker.pl#GetTextFileRep().
 * Also used in gloss2html.pl, which generates HTML files from .txt.
 */

function getRandomInt(min, max) {
	return Math.floor(Math.random() * (max - min + 1) + min);
}

// Call IntraMine's editor (editWithIntraMine) or a specific app (editWithPreferredApp).
function editOpen(href) {
	if (!allowEditing)
		{
		return;
		}
	
	href = href.replace(/^file\:\/\/\//, '');
	
	if (useAppForEditing && !onMobile)
		{
		editWithPreferredApp(href);
		}
	else // Use IntraMine's Editor service.
		{
		editWithIntraMine(href);
		}
}

// Request Opener port from main at theMainPort, then call Opener directly using the right port.
async function editWithPreferredApp(href) {
	showSpinner();

	try {
		const port = await fetchPort(mainIP, theMainPort, openerShortName, errorID);
		if (port !== "")
			{
			appEditWithPort(href, port);
			}
			hideSpinner();
	}
	catch(error) {
		let e1 = document.getElementById(errorID);
		e1.innerHTML = 'Connection error while attempting to open file!';
		hideSpinner();
	}
}

// Call Opener intramine_open_with.pl to open a file using user's preferred editor
// (as specified in data/intramine_config.txt, "LOCAL_OPENER_APP" etc).
async function appEditWithPort(href, openerPort) {
	try {
		let properHref = href.replace(/^file\:\/\/\//, '');
		let theAction = 'http://' + mainIP + ':' + openerPort + '/' + openerShortName + '/?req=open&clientipaddress=' + clientIPAddress + '&file=' + properHref;
		const response = await fetch(theAction);
		if (response.ok)
			{
			let text = await response.text();
			if (text !== 'OK')
				{
				let e1 = document.getElementById(errorID);
				e1.innerHTML = 'Error, server said ' + text + '!';
				}
			}
		else
			{
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(errorID);
			e1.innerHTML = 'Error, server reached but it could not open the file!';
			}
	}
	catch(error) {
		let e1 = document.getElementById(errorID);
		e1.innerHTML = 'Connection error while attempting to open file!';
	}
}

// Use IntraMine's CodeMirror-based editor (intramine_editor.pl).
async function editWithIntraMine(href) {
	showSpinner();

	href = decodeURIComponent(href);

	// Pull any #Header from the href, put it back on the end later.
	let header = '';
	let headerMatch = /(#.+?$)/.exec(href);
	if (headerMatch !== null)
		{
		header = headerMatch[1]; 
		header = header.substring(1);
		href = href.replace(/#.+?$/, ''); // Take out the '#' temporarily
		}
	
	try {
		const port = await fetchPort(theHost, theMainPort, editorShortName, errorID);
		if (port !== "")
			{
			hideSpinner();
			let properHref = href.replace(/^file\:\/\/\//, '');

			properHref = encodeURIComponent(properHref);
			if (header !== '')
				{
				header = encodeURIComponent(header);
				header = '#' + header;
				}
			
			let url = 'http://' + theHost + ':' + port + '/' + editorShortName + '/?href=' + properHref + header;

			window.open(url, "_blank");
			}
		else
			{
			// Trouble getting Editor port number.
			let e1 = document.getElementById(errorID);
			e1.innerHTML = 'Error, could not retrieve port number for the Editor!';
			}
	}
	catch(error) {
		let e1 = document.getElementById(errorID);
		e1.innerHTML = 'Connection error while attempting to open file!';
		hideSpinner();
	}
}

// Not used.
// Avoid encodeURIComponent when inViewer.
async function openViewNoEncode(href, serviceShortName) {
	openView(href, serviceShortName, false, true);
}

// openView, but force encodeURIComponent() on the href
// for reasons unknown to me.
async function openViewEncode(href, serviceShortName) {
	openView(href, serviceShortName, true, false);
}

// Viewer links. Get a good port, do a window.open().
// openView() calls are put in by eg intramine_linker.pl#GetTextFileRep().
// overrideNoEncode is not used.
async function openView(href, serviceShortName, forceEncode = false, overrideNoEncode = false) {
	href = decodeURIComponent(href);

	let actualShortName = serviceShortName;

	// We want the port for a Viewer, there is no actual Video service.
	if (serviceShortName === videoShortName)
		{
		actualShortName = viewerShortName;
		}
	
	try {
		const port = await fetchPort(mainIP, theMainPort, actualShortName, errorID);
		if (port !== "")
			{
			openViewWithPort(href, port, serviceShortName, forceEncode, overrideNoEncode);
			}
	}
	catch(error) {
		// There was a connection error of some sort
	//		let e1 = document.getElementById(errorID);
	//		e1.innerHTML = 'Connection error while attempting to retrieve port number!';
	}
}

// Open a view of a file, using the Viewer (intramine_file_viewer_cm.pl).
function openViewWithPort(href, servicePort, serviceShortName, forceEncode, overrideNoEncode) {
	const rePort = /\:\d+/;
	href = href.replace(rePort, ":" + servicePort);

	// A typical href contains a second instance of href in IntraMine, eg
	// href="http://192.168.40.8:43129/Viewer/?href=c:/strawberry/c/include/c++/13.2.0/bits/stl_numeric.h&searchItems=accumulate#accumulate"
	// (Don't ask, it's carved in stone at this point.)
	// Pull out the interior hrefProper, encode it, put it back.
	// The href proper runs from '=' to just before either '&' or '"'.
	// This takes care of eg a '+' in the file path.
	const matchResult = href.match(/=[^&"]+/);
	if (matchResult !== null)
		{
		let hrefProper = matchResult[0];
		hrefProper = hrefProper.substring(1);

		let inViewer = false;
		if (typeof viewerShortName !== 'undefined' && shortServerName === viewerShortName)
			{
			// We are in the Viewer.
			inViewer = true;
			}		
		
		if (1 || ((inViewer && !overrideNoEncode) || forceEncode))
			{
			let preAnchor = '';
			let theAnchor = '';
			let postAnchor = '';
			let anchorPosition = hrefProper.indexOf("#");
			if (anchorPosition > 0)
				{
				preAnchor = hrefProper.substring(0, anchorPosition);
				postAnchor = hrefProper.substring(anchorPosition + 1);
				theAnchor = '#';
				}
			else
				{
				preAnchor = hrefProper;
				}
			preAnchor = encodeURIComponent(preAnchor);
			postAnchor = encodeURIComponent(postAnchor);
			href = href.replace(/=[^&"]+/, '=' + preAnchor + theAnchor + postAnchor);
			}
		}
	
	if (serviceShortName === videoShortName)
		{
		// Replace videoShortName with viewerShortName.
		const reName = /videoShortName/;
		href = href.replace(reName, viewerShortName);
		openVideo(href);
		}
	else
		{
		window.open(href, "_blank");
		}
}

async function openVideo(href) {
	const response = await fetch(href); // ignore response
}

// Call back to IntraMine's Viewer
async function openDirectory(href) {

	// Remove file:///, which wrecks the link.
	href = href.replace(/^file\:\/\/\//, '');
	let hrefMatch = /openDirectory\(&quot;(.+?)&quot;/.exec(href);
	if (hrefMatch !== null)
		{
		href = hrefMatch[1];
		}
	
	href = encodeURIComponent(href);
	
	try {
		const port = await fetchPort(mainIP, theMainPort, viewerShortName, errorID);
		if (port !== "")
			{
			openDirectoryWithPort(href, theMainPort, port);
			}
	}
	catch(error) {
		// There was a connection error of some sort
	//		let e1 = document.getElementById(errorID);
	//		e1.innerHTML = 'Connection error while attempting to retrieve port number!';
	}
}

// Call back to Files service, which will open up a new browser tab
// and show an expanded view of the requested directory in href.
// If the Files service is not available,
// call back to Viewer, which will use
// system('start', '', $dirPath);
// to open a view of the directory with Windows File Explorer.
async function openDirectoryWithPort(href, port, viewerPort) {
	let useFilesService = false;

	try {
		const filesPort = await fetchPort(mainIP, port, filesShortName, errorID);
		if (filesPort !== "")
			{
			useFilesService = true;
			let theAction = 'http://' + mainIP + ':' + filesPort + '/' + filesShortName + '/?req=main' + '&directory=' + href;
			
			window.open(theAction, "_blank");
			}
	}
	catch(error) {
		// There was a connection error of some sort
	//		let e1 = document.getElementById(errorID);
	//		e1.innerHTML = 'Connection error while attempting to retrieve port number!';
	}

	if (useFilesService)
		{
		return;
		}
	
	try {
		let theAction = 'http://' + mainIP + ':' + viewerPort + '/' + viewerShortName + '/?req=openDirectory' + '&dir=' + href;

		const response = await fetch(theAction);
		if (response.ok)
			{
			let text = await response.text();
			if (text !== 'OK')
				{
				let e1 = document.getElementById(errorID);
				e1.innerHTML = 'Error, server said ' + text + '!';
				}
			}
		else
			{
			let e1 = document.getElementById(errorID);
			e1.innerHTML = 'Error, server reached but it could not open the directory!';
			}
	}
	catch(error) {
		// Connection error.
	}
}
