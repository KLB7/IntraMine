/**
 * viewerLinks.js: handle links in file views. Used in intramine_viewer.pl
 *  for both CodeMirror and non-CodeMirror source and text files.
 *  See eg intramine_file_viewer_cm.pl#GetTextFileRep().
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
function editWithPreferredApp(href) {
	showSpinner();
	let request = new XMLHttpRequest();
//	let theRequest = 'http://' + mainIP + ':' + theMainPort + '/Opener/?req=portNumber';
	let theRequest = 'http://' + mainIP + ':' + theMainPort + '/' + openerShortName + '/?req=portNumber';
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

// Call Opener intramine_open_with.pl to open a file using user's preferred editor
// (as specified in data/intramine_config.txt, "LOCAL_OPENER_APP" etc).
function appEditWithPort(href, openerPort) {
	showSpinner();
	let request = new XMLHttpRequest();
	let properHref = href.replace(/^file\:\/\/\//, '');

	let theRequest = 'http://' + mainIP + ':' + openerPort + '/' + openerShortName + '/?req=open&clientipaddress=' + clientIPAddress + '&file=' + properHref;
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

// Use IntraMine's CodeMirror-based editor (intramine_editor.pl).
function editWithIntraMine(href) {
	showSpinner();
	let request = new XMLHttpRequest();
	let theRequest = 'http://' + theHost + ':' + theMainPort + '/' + editorShortName + '/?req=portNumber';
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
				let url = 'http://' + theHost + ':' + resp + '/' + editorShortName + '/?href=' + properHref + '&rddm=' + String(getRandomInt(1, 65000));
	
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

// Viewer links. Get a good port, do a window.open().
// openView() calls are put in by eg intramine_linker.pl#GetTextFileRep().
function openView(href) {
	let request = new XMLHttpRequest();
	let theRequest = 'http://' + mainIP + ':' + theMainPort + '/' +
						viewerShortName + '/?req=portNumber';
	request.open('get', theRequest, true);
	
	request.onload =
			function() {
				if (request.status >= 200 && request.status < 400)
					{
					// Success?
					let resp = request.responseText;
					if (!isNaN(resp))
						{
						openViewWithPort(href, theMainPort, resp);
						}
					}
			};
	
	request.onerror = function() {
		// There was a connection error of some sort
//		let e1 = document.getElementById(errorID);
//		e1.innerHTML = 'Connection error while attempting to retrieve port number!';
//		hideSpinner();
	};
	
	request.send();
}

// Open a view of a file, using the Viewer (intramine_file_viewer_cm.pl).
function openViewWithPort(href, port, viewerPort) {
	let rePort = new RegExp(port);
	href = href.replace(rePort, viewerPort);
	window.open(href, "_blank");
}