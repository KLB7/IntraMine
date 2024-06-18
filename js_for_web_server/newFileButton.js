// newFileButton.js: for the "New..." button on the Files page,
// especially the directory/filename picker.

function showNewFile(newFilePath) {
	editOpen(newFilePath);
}

function makeNewFile() {
	showNewFilePicker();
}


let el = document.getElementById("new-button");
if (el !== null)
	{
	el.addEventListener('click', makeNewFile, false);
	}

function initNewFileDialog() {
	let driveSelector = document.getElementById('driveselector_3');
	if (driveSelector !== null)
		{
		let driveSelected = driveSelector.value;
		selectTheDirectory(null, driveSelected);
		}

	$('#scrollDriveListNew').fileTree({
		root : 'C:/',
		script : 'http://' + theHost + ':' + thePort + '/',
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
		doNewFilePickerResize();
	});
	
	document.getElementById("dirpickerMainContainer").addEventListener('keydown', dirKey);

}

function driveChangedNew(tree_id, value) {
	let e1 = document.getElementById(tree_id);
	e1.innerHTML = '';
	selectTheDirectory(e1, value);

	$('#' + tree_id).fileTree({
		root : value,
		script : 'http://' + theHost + ':' + thePort + '/',
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
		doNewFilePickerResize();
	});
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

function showNewFilePicker() {
	doNewFilePickerResize();
	
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
		requestNewFile(newFilePath);
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
function doNewFilePickerResize() {

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

async function requestNewFile(newFilePath) {

	let theAction = 'http://' + mainIP + ':' + ourSSListeningPort + '/' + shortServerName + '/?req=new&path=' + encodeURIComponent(newFilePath);

	try {
		
		const response = await fetch(theAction);
		if (response.ok)
			{
			let text = await response.text();
			if (text === 'ok')
				{
				showNewFile(encodeURIComponent(newFilePath));
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
				else if (text === 'exists')
					{
					alert("Sorry, file already exists and IntraMine will not overwrite.");
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
		alert("WHOOPS, could not create new file due to connection error.");
	}
}