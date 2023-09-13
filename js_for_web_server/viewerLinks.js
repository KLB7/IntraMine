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

	try {
		const port = await fetchPort(theHost, theMainPort, editorShortName, errorID);
		if (port !== "")
			{
			hideSpinner();
			let properHref = href.replace(/^file\:\/\/\//, '');
			let url = 'http://' + theHost + ':' + port + '/' + editorShortName + '/?href=' + properHref + '&rddm=' + String(getRandomInt(1, 65000));

			window.open(url, "_blank");
			}
	}
	catch(error) {
		let e1 = document.getElementById(errorID);
		e1.innerHTML = 'Connection error while attempting to open file!';
		hideSpinner();
	}
}

// Viewer links. Get a good port, do a window.open().
// openView() calls are put in by eg intramine_linker.pl#GetTextFileRep().
async function openView(href) {
	try {
		const port = await fetchPort(mainIP, theMainPort, viewerShortName, errorID);
		if (port !== "")
			{
			openViewWithPort(href, theMainPort, port);
			}
	}
	catch(error) {
		// There was a connection error of some sort
	//		let e1 = document.getElementById(errorID);
	//		e1.innerHTML = 'Connection error while attempting to retrieve port number!';
	}
}

// Open a view of a file, using the Viewer (intramine_file_viewer_cm.pl).
function openViewWithPort(href, port, viewerPort) {
	let rePort = new RegExp(port);
	href = href.replace(rePort, viewerPort);
	window.open(href, "_blank");
}

// Call back to IntraMine's Viewer
async function openDirectory(href) {
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
			// TEST ONLY
			console.log("Dir: |" + href + "|");
			
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
