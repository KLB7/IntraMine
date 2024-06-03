// uploader.js: used by intramine_uploader.pl. 
// Note theHost, thePort, and theDefaultUploadDir are set in intramine_uploader.pl#UploadPage().

// Call enableUploader when ready.
function ready(fn) {
	if (document.readyState != 'loading')
		{
		fn();
		}
	else
		{
		document.addEventListener('DOMContentLoaded', fn);
		}
}

function enableUploader() {
	// Init the Ajax form submission
	initFullFormAjaxUpload();
	hideSpinner();
}

ready(enableUploader);

function initFullFormAjaxUpload() {
	let form = document.getElementById('form-id');
	form.onsubmit = function() {
		// FormData receives the whole form
		// See eg https://developer.mozilla.org/en-US/docs/Web/API/FormData
		let formData = new FormData(form);

		// Set action for whole form.
		let action = 'http://' + theHost + ':' + thePort + '/?req=upload';

		uploadTheFile(formData, action);

		// Avoid normal form submission
		return false;
	}
}

function updateChosenFileDisplay(inp) {
	// Display chosen file in file-upload-value.
	let fakepath = inp.value;
	let arrayMatch = /([^\\]+)$/.exec(fakepath);
	let filename = (arrayMatch !== null) ? arrayMatch[1] : '';
	document.getElementById('file-upload-value').innerHTML = filename;
}

function clearStatus() {
	// Clear status message.
	let status = document.getElementById('upload-status');
	status.innerHTML = '&nbsp';

	// Clear the progress indicator.
	let progress = document.getElementById('progress');
	progress.innerHTML = '&nbsp';
}

// Note this has been left as an XMLHttpRequest() rather than using fetch.
function sendXHRequest(formData, uri) {
	// Get an XMLHttpRequest instance
	let xhr = new XMLHttpRequest();

	// Set up events
	xhr.upload.addEventListener('loadstart', onloadstartHandler, false);
	xhr.upload.addEventListener('progress', onprogressHandler, false);
	xhr.upload.addEventListener('load', onloadHandler, false);
	xhr.addEventListener('readystatechange', onreadystatechangeHandler, false);

	// Set up request
	xhr.open('POST', uri, true);

	// Spinner gif is in TopNav()
	showSpinner();

	// Fire!
	xhr.send(formData);
}

// Handle the start of the transmission
function onloadstartHandler(evt) {
	let div = document.getElementById('upload-status');
	div.innerHTML = 'Upload started.';
}

// Handle the end of the transmission
function onloadHandler(evt) {
	let div = document.getElementById('upload-status');
	div.innerHTML = 'File uploaded. Waiting for response.';
}

// Handle the progress
function onprogressHandler(evt) {
	let div = document.getElementById('progress');
	let percent = evt.loaded / evt.total * 100;
	div.innerHTML = 'Progress: ' + percent + '%';
}

// Handle the response from the server
function onreadystatechangeHandler(evt) {
	let status, text, readyState;

	try
		{
		readyState = evt.target.readyState;
		text = evt.target.responseText;
		status = evt.target.status;
		}
	catch (e)
		{
		return;
		}

	if (readyState === XMLHttpRequest.DONE && (status == '200' || status === 0) && text !== '')
		{
		let statusElem = document.getElementById('upload-status');
		statusElem.innerHTML = text;
		// Spinner gif is in swarmserver.pm#TopNav()
		hideSpinner();
		}
}

// Send req=checkFile. If 'OK', or user confirms overwrite,
// upload the file with sendXHRequest().
async function uploadTheFile(formData, uri) {
	// Send an "activity" message.
	wsSendMessage('activity ' + shortServerName + ' ' + ourSSListeningPort);
	
	showSpinner();

	let fileElem = document.getElementById('file-id');
	let fakepath = fileElem.value;
	let arrayMatch = /([^\\]+)$/.exec(fakepath);
	let fileName = (arrayMatch !== null) ? arrayMatch[1] : '';
	let dirElem = document.getElementById('other-field-id');
	let serverDir = dirElem.value;

	if (fileName === "")
		{
		let status = document.getElementById('upload-status');
		status.innerHTML = '<p>Error, missing file name!</p>';
		hideSpinner();
		return;
		}

	try {
		let theAction = 'http://' + theHost + ':' + thePort + '/?req=checkFile&filename='
		+ encodeURIComponent(fileName) + '&directory=' + encodeURIComponent(serverDir);
		const response = await fetch(theAction);
		if (response.ok)
			{
			let text = await response.text();

			if (text.indexOf("OK") === 0)
				{
				sendXHRequest(formData, uri);
				}
			else
				{
				// File exists on server, confirm replacement or cancel.
				if (confirmReplaceFile(serverDir, fileName))
					{
					uri += '&allowOverwrite=1';
					sendXHRequest(formData, uri);
					}
				else
					{
					let status = document.getElementById('upload-status');
					status.innerHTML = '&nbsp;';
					hideSpinner();
					}
				}
			}
		else
			{
			let status = document.getElementById('upload-status');
			status.innerHTML = '<p>Error, server reached but it returned an error!</p>';
			hideSpinner();
			}
	}
	catch(error) {
		// There was a connection error of some sort
		let status = document.getElementById('upload-status');
		status.innerHTML = '<p>Connection error!</p>';
		hideSpinner();
	}
}

// Ask user if file on server should be replaced.
function confirmReplaceFile(serverDir, fileName) {
	if (serverDir == '')
		{
		serverDir = theDefaultUploadDir;
		}
	serverDir = serverDir.replace(/\\/g, '/');
	if (!/\/$/.test(serverDir))
		{
		serverDir += '/';
		}
	return (window.confirm(serverDir + fileName + ' already exists. Replace it?'));
}
