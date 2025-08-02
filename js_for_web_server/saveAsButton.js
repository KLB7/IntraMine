// saveAsButton.js: for the "Save As..." button in IntraMine's Editor,
// especially the directory/filename picker.

function initSaveAsDialog() {
	let driveSelector = document.getElementById('driveselector_3');
	if (driveSelector !== null)
		{
		let driveSelected = driveSelector.value;
		selectTheDirectory(null, driveSelected);
		}

	// TEST ONLY
	//console.log("initSaveAsDialog called.")

	$('#scrollDriveListNew').fileTree({
		root : 'C:/',
		script : 'http://' + theHost + ':' + ourServerPort + '/',
		expandSpeed : 200,
		collapseSpeed : 200,
		multiFolder : true,
		selectDirectories: true
		//pacifierID : 'spinner',
		//remote : weAreRemote,
		//mobile : onMobile
	}, function(el, file) {
		selectTheDirectory(el, file);
	}, function(dir) {
		selectCollapsedDirectory(dir);
	}, function() {
		doSaveAsPickerResize();
	});
	
	document.getElementById("dirpickerMainContainer").addEventListener('keydown', dirKey);

}

function driveChangedNew(tree_id, value) {
	let e1 = document.getElementById(tree_id);
	e1.innerHTML = '';
	selectTheDirectory(e1, value);

	$('#' + tree_id).fileTree({
		root : value,
		script : 'http://' + theHost + ':' + ourServerPort + '/',
		expandSpeed : 200,
		collapseSpeed : 200,
		multiFolder : true,
		selectDirectories: true
		//pacifierID : 'spinner',
		//remote : weAreRemote
	}, function(el, file) {
		selectTheDirectory(el, file);
	}, function(dir) {
		selectCollapsedDirectory(dir);
	}, function() {
		doSaveAsPickerResize();
	});
}

function currentSortOrder() {
	return("name_ascending");
	}

function selectTheDirectory(el, file) {
	// Remember pick, and show it in "pickerDisplayedDirectory".
	// Trim any file name first, though.
	if (file.length === 0)
		{
		return;
		}
	
	let fileMarkerPos = file.indexOf("__FILE__");
	if (fileMarkerPos > 0)
		{
		file = file.substring(0, fileMarkerPos);
		let slashPos = file.lastIndexOf("/");
		if (slashPos < 0)
			{
			slashPos = file.lastIndexOf("\\");
			}
		if (slashPos > 0)
			{
			file = file.substring(0, slashPos + 1);
			}
		}
	
	document.getElementById('pickerDisplayedDirectory').innerHTML = file;
}

function selectCollapsedDirectory(dir) {
	if (dir.length === 0)
		{
		return;
		}
	
	document.getElementById('pickerDisplayedDirectory').innerHTML = dir;
}

// Handle Escape and Enter keys when directory picker is visible.
function dirKey(e) {
	let code = e.code;
	if (code === "Escape")
		{
		hideNewFilePicker();
		document.getElementById('newFullPathField').value = '';
		e.preventDefault();
		}
	else if (code === "Enter")
		{
		setFullPathFromPicker();
		e.preventDefault();
		}
}

function showSaveAsFilePicker() {
	doSaveAsPickerResize();
	
	let picker = document.getElementById("dirpickerMainContainer");
	if (picker !== null)
		{
		picker.style.display = 'block';
		document.getElementById('newFullPathField').value = '';
		// We need the focus so that Enter/Escape keys will work right from the start.
		document.getElementById("dirOkButton").focus();
		}
}

// On "OK" in the dir picker: set dir and file name.
function setFullPathFromPicker() {
	document.getElementById('newFullPathField').value = document.getElementById('pickerDisplayedDirectory').innerHTML + document.getElementById('newFileName').value;
	hideNewFilePicker();

	let newFilePath = document.getElementById('newFullPathField').value;

	if (newFilePath !== '')
		{
		saveFileAs(newFilePath);
		}
}

function hideNewFilePicker() {
	let picker = document.getElementById("dirpickerMainContainer");
	if (picker !== null)
		{
		picker.style.display = 'none';
		}
}

// Adjust the heights of all the parts of the Search form directory picker.
function doSaveAsPickerResize() {

	// Set simple elements to a fixed height.
	// Note padding is included in height, margin is not
	let dirDialogTitleElement = document.getElementById("directoryPickerTitle");
	let dirDialogTitleElementHeight = 26;
	dirDialogTitleElement.style.height = dirDialogTitleElementHeight + "px";
	// total height 4 + 26 = 30px
	let dirDialogTitleElementTotalHeight = 30;
	
	let driveSelectorElem1 = document.getElementById("driveselector_3");
	let driveSelectorHeight = 24;
	driveSelectorElem1.style.height = driveSelectorHeight + "px"; // total height 24px
	let pickerDisplayElem = document.getElementById("pickerDisplayDiv");
	let pickerDisplayElemHeight = 24;
	pickerDisplayElem.style.height = pickerDisplayElemHeight + "px"; // total height 24 + 2 = 26px


	let newFileNameElem = document.getElementById("newFileDiv");
	let newFileElemHeight = 24;
	newFileNameElem.style.height = newFileElemHeight + "px";
	let pickerDisplayElemTotalHeight = pickerDisplayElemHeight + newFileElemHeight;

	// Buttons Ok/Cancel
	let buttonHeight = 24;
	let okButton = document.getElementById("dirOkButton");
	okButton.style.height = buttonHeight + "px"; // total height 24px
	let cancelButton = document.getElementById("dirCancelButton");
	cancelButton.style.height = buttonHeight + "px"; // total height 24px
	let buttonHolderHeight = buttonHeight + 14; // There's an extra 8 there, not sure why....
	
	// Overall "dialog" div: set to half of window height.
	let dialogHeight = window.innerHeight / 2;
	let dialogHeightPC = (dialogHeight/window.innerHeight)*100;
	let mainPickerElement = document.getElementById("dirpickerMainContainer");
	mainPickerElement.style.height = dialogHeightPC + "%";
	// dirpicker: what's left after taking out title and dir display and buttons
	let dirpickerHeight = dialogHeight - dirDialogTitleElementTotalHeight - buttonHolderHeight;
	//let dirpickerHeight = dialogHeight - dirDialogTitleElementTotalHeight - pickerDisplayElemHeight - buttonHolderHeight;
	let pickerElement = document.getElementById("dirpicker");
	pickerElement.style.height = dirpickerHeight + "px";
	// scrollAdjustedHeightDirPicker: pickerElement minus pickerDisplayElem
	let scrollAdjustedHeight = dirpickerHeight - pickerDisplayElemTotalHeight;
	let el = document.getElementById("scrollAdjustedHeightDirPicker");
	el.style.height = scrollAdjustedHeight + "px";
	// fileTreeLeft: same as scrollAdjusted
	let driveLeftElement = document.getElementById("fileTreeNew");
	driveLeftElement.style.height = scrollAdjustedHeight + "px";
	// scrollDriveListNew: driveLeftElement less driveSelectorHeight
	let scrollDriveLeftElement = document.getElementById("scrollDriveListNew");
	let scrollDriveLeftHeight = scrollAdjustedHeight - driveSelectorHeight;
	scrollDriveLeftElement.style.height = scrollDriveLeftHeight + "px";
	
}

async function saveFileAs(newFilePath) {

	let theAction = 'http://' + mainIP + ':' + ourSSListeningPort + '/' + shortServerName + '/?req=oktosaveas&path=' + encodeURIComponent(newFilePath);

	try {
		
		const response = await fetch(theAction);
		if (response.ok)
			{
			let text = await response.text();
			if (    text === 'ok'
				|| (text=== 'exists'
					&& window.confirm(newFilePath + ' already exists. Replace it?')) )
				{
				finallyDoTheSaveAs(newFilePath);
				}
			else
				{
				if (text === 'nopath')
					{
					alert("Error, no file path was provided.");
					}
				else if (text === 'badname')
					{
					alert("Error, that is a bad file name.");
					}
				else if (text === 'badchar')
					{
					alert("Error, there are one or more bad characters in the file name.");
					}
				else if (text === 'noname')
					{
					alert("Please provide a file name.");
					}
				else if (text === 'error')
					{
					alert("File system error, could not create the file.");
					}
				}
			}
		else
			{
			alert("WHOOPS, server reached but it could not handle the request.");
			}
	}
	catch(error) {
		alert("WHOOPS, could not save as due to connection error.");
	}
}

// Based on editor.js#saveFile().
async function finallyDoTheSaveAs(path) {
	// TEST ONLY
	console.log("finallyDoTheSaveAs for path |" + path + "|");
	//return;

	let originalPath = path;
	showSpinner();
	let contents = myCodeMirror.doc.getValue();
	let originalContents = contents;
	// '%' needs encoding in contents, to survive the encodeURIComponent() below.
	contents = contents.replace(/%/g, "%25");
	// And the same for path.
	path = path.replace(/%/g, "%25");
	path = encodeURIComponent(path);
	contents = encodeURIComponent(contents);
	contents = encodeURIComponent(contents); // sic

	try {
		let theAction = 'http://' + mainIP + ':' + ourServerPort + '/';

		const response = await fetch(theAction, {
			method: 'POST',
			headers: {
			'Content-Type': 'application/x-www-form-urlencoded',
		  },
		  body: 'req=saveas&file=' + path + '&contents='
		  + contents
		});
		if (response.ok)
			{
			let resp = await response.text();
			if (resp !== 'OK')
				{
				let e1 = document.getElementById("editor_error");
				e1.innerHTML = '<p>Error, server said ' + resp + '!</p>';
				hideSpinner();
				}
			else
				{
				// Reload.
				// Example full href:
				// http://192.168.40.8:43131/Editor/?href=C:/perlprogs/IntraMine/docs/IntraMine%20July%2021%202025.txt#497
				let oldHref = window.location.href;
				let newHref = oldHref.replace(/\/\?href=([^#]+)/, "/?href=" + path);

				sleepABit(500);

				window.location.href = newHref;
				}
			}
		else
			{
			// We reached our target server, but it returned an error
			// TODO make this less offensive.
			let e1 = document.getElementById("editor_error");
			e1.innerHTML = '<p>Error, server reached but it could not save the file!</p>';
			hideSpinner();
			}
	}
	catch(error) {
		// There was a connection error of some sort
		// TODO make this less vague.
		let e1 = document.getElementById("editor_error");
		e1.innerHTML = '<p>Connection error while attempting to save file!</p>';
		hideSpinner();
	}
}

// Ctrl+Alt+S or Ctrl+Shift+S to Save As.
window.addEventListener('keydown', function(e){		
	if ((e.altKey || e.shiftKey) && e.ctrlKey && e.key === 's')
		{
		saveFileAsWithPicker();
		e.preventDefault();
		}
  })
