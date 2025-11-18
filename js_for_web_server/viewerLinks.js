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
	href = href.replace(/^file\:\/\/\//, '');
	// Trim off searchItems etc
	let ampPos = href.indexOf("&");
	if (ampPos < 0)
		{
		ampPos = href.indexOf("#");
		}
	let trailer = '';
	if (ampPos > 0)
		{
		trailer = href.substring(ampPos);
		href =  href.substring(0, ampPos);
		}

	href = encodeURI(href);
	href = href.replace(/\+/g, "%2B");
	
	try {
		let theAction = 'http://' + mainIP + ':' + openerPort + '/' + openerShortName + '/?req=open&clientipaddress=' + clientIPAddress + '&file=' + href;
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
	// Remove file:///, which wrecks the link.
	href = href.replace(/^file\:\/\/\//, '');
	href = href.replace(/^file:/, '');

	// Trim off searchItems etc
	let ampPos = href.indexOf("&");
	if (ampPos < 0)
		{
		ampPos = href.indexOf("#");
		}
	let trailer = '';
	if (ampPos > 0)
		{
		trailer = href.substring(ampPos);
		href =  href.substring(0, ampPos);
		}

	href = encodeURI(href);
	href = href.replace(/\+/g, "%2B");

	// Encode the trailer.
	//console.log("Edit Raw trailer: |" + trailer + "|");
	trailer = trailer.replace(/\&/g, "____AMPER____");
	trailer = trailer.replace(/\?/g, "____QUEST____");
	trailer = trailer.replace(/\=/g, "____EQAL____");
	trailer = trailer.replace(/\+/g, "____PLUSS____");
	trailer = trailer.replace(/\#/g, "____ANK____");
	trailer = trailer.replace(/\%/g, "____PCTT____");
	trailer = encodeURIComponent(trailer);
	trailer = trailer.replace(/____AMPER____/g, "&");
	trailer = trailer.replace(/____QUEST____/g, "?");
	trailer = trailer.replace(/____EQAL____/g, "=");
	trailer = trailer.replace(/____PLUSS____/g, "+");
	trailer = trailer.replace(/____ANK____/g, "#");
	trailer = trailer.replace(/____PCTT____/g, "%");
	//console.log("Edit Enc trailer: |" + trailer + "|");


	// Put back the trailer
	href = href + trailer;

		try {
			const port = await fetchPort(theHost, theMainPort, editorShortName, errorID);
			if (port !== "")
				{
				hideSpinner();
				let url = 'http://' + theHost + ':' + port + '/' + editorShortName + '/?href=' +
				href;

				// TEST ONLY
				//console.log("url: |" + url + "|");

				window.open(url, "_blank");
				}
			else
				{
				// Trouble getting Editor port number.
				hideSpinner();
				let e1 = document.getElementById(errorID);
				e1.innerHTML = 'Error, could not retrieve port number for the Editor!';
				}
		}
		catch(error) {
			hideSpinner();
			// There was a connection error of some sort
		//		let e1 = document.getElementById(errorID);
		//		e1.innerHTML = 'Connection error while attempting to retrieve port number!';
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

	// Remove file:///, which wrecks the link.
	href = href.replace(/^file\:\/\/\//, '');
	href = href.replace(/^file:/, '');

	// Trim off searchItems etc
	let ampPos = href.indexOf("&");
	if (ampPos < 0)
		{
		ampPos = href.indexOf("#");
		}
	let trailer = '';
	if (ampPos > 0)
		{
		trailer = href.substring(ampPos);
		href =  href.substring(0, ampPos);
		}

	href = href.replace(/\+/g, "%2B");

	// Encode the trailer.
	//console.log("Viewer Raw trailer: |" + trailer + "|");
	trailer = trailer.replace(/\&/g, "____AMPER____");
	trailer = trailer.replace(/\?/g, "____QUEST____");
	trailer = trailer.replace(/\=/g, "____EQAL____");
	trailer = trailer.replace(/\+/g, "____PLUSS____");
	trailer = trailer.replace(/\#/g, "____ANK____");
	trailer = trailer.replace(/\%/g, "____PCTT____");
	trailer = encodeURIComponent(trailer);
	trailer = trailer.replace(/____AMPER____/g, "&");
	trailer = trailer.replace(/____QUEST____/g, "?");
	trailer = trailer.replace(/____EQAL____/g, "=");
	trailer = trailer.replace(/____PLUSS____/g, "+");
	trailer = trailer.replace(/____ANK____/g, "#");
	trailer = trailer.replace(/____PCTT____/g, "%");
	//console.log("Viewer Enc trailer: |" + trailer + "|");

	// Put back the trailer
	href = href + trailer;

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
