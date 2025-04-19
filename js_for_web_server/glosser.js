// glosser.js: 
// respond to "NEWGLOSSMESSAGE" by appending the supplied message
// to the text area (#theTextWithoutJumpList), and resize.

let directoryCache;

// Call fn when ready.
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

function registerGlosserCallbacks() {
	// Sent by intramine_glosser.pl#ShowFeedback().
	addCallback("NEWGLOSSMESSAGE", refreshGlosserDisplay);
	// Xable the Generate button.
	addCallback("ENABLEGLOSSERGENERATE", enableGenerateButton);
	addCallback("DISABLEGLOSSERGENERATE", disableGenerateButton);
}

function enableGenerateButton() {
	let gb = document.getElementById('convert_button');
	if (gb !== null)
		{
		gb.disabled = false;
		}
}

function disableGenerateButton() {
	let gb = document.getElementById('convert_button');
	if (gb !== null)
		{
		gb.disabled = true;
		}
}

// Adjust the feedback container to fill the bottom of the window.
function doResize() {
	let el = document.getElementById(cmdOutputContainerDiv);

	let pos = getPosition(el);
	let windowHeight = window.innerHeight;
	let elHeight = windowHeight - pos.y - 10;
	let newHeightPC = (elHeight / windowHeight) * 100;
	el.style.height = newHeightPC + "%";

	let windowWidth = window.innerWidth;
	el.style.width = windowWidth - 4 + "px";
}

// Handle WebSockets message "NEWGLOSSMESSAGE".
// as sent by intramine_glosser.pl via gloss_to_html.pm.
async function refreshGlosserDisplay(message) {
	message = message.replace(/NEWGLOSSMESSAGE\:?/, '');
	let e1 = document.getElementById('theTextWithoutJumpList');
	e1.innerHTML += message;
	doResize();
	// Scroll last line into view.
	e1.scrollTop = e1.scrollHeight;
}

// Call back to intramine_glossary.pl with req=convert
async function runConversion() {
	//showSpinner();

	let baseAction = 'http://' + theHost + ':' + thePort + '/?req=convert';
	// Gather dir/file, inline, hoverGIF

	let dirvalElement = document.getElementById("searchdirectory");
	let dirValue = encodeURIComponent(dirvalElement.value);
	let args = '&file_or_dir=' + dirValue;

	let inline = document.querySelector('input[name="inline"]:checked');
	let valInline = (inline === null) ? "no" : inline.value;
	args += '&inline=' + valInline;
	let hoverGIFs = document.querySelector('input[name="hoverGIFs"]:checked');
	let valHoverGIFs = (hoverGIFs === null) ? "no" : hoverGIFs.value;
	args += '&hover_gifs=' + valHoverGIFs;

	try {
		let theAction = baseAction + args;
		const response = await fetch(theAction);
		if (response.ok)
			{
			let resp = await response.text();
			let e1 = document.getElementById('theTextWithoutJumpList');
			if (resp == "Ok")
				{
				e1.innerHTML = '<p>STARTING</p>';
				e1.innerHTML += '<p>Inline images: ' + valInline + '</p>';
				e1.innerHTML += '<p>Always hover GIFs: ' + valHoverGIFs + '</p>';
				directoryCache.set(dirValue, dirValue);
				rebuildDirList();
				saveDirCache();
				rememberCheckBoxes();
				wsSendMessage('DISABLEGLOSSERGENERATE');
				}
			else
				{
				e1.innerHTML = '<p>' + resp + '</p>';
				}
			}
		else
			{
			let e1 = document.getElementById('theTextWithoutJumpList');
			e1.innerHTML += '<strong>Error, server reached but it ran into trouble!</strong><br>';
			doResize();
			// Scroll last line into view.
			e1.scrollTop = e1.scrollHeight;
			//hideSpinner();
			}
		}
	catch(error) {
		// There was a connection error of some sort
		let e1 = document.getElementById('theTextWithoutJumpList');
		e1.innerHTML += '<strong>Connection error while attempting to monitor output!</strong><br>';
		doResize();
		// Scroll last line into view.
		e1.scrollTop = e1.scrollHeight;
		//hideSpinner();
		}
}

function finishDirPickerSetup() {
	initDirectoryDialog();

	directoryCache = new LRUCache(10);
	loadDirCache();
	rebuildDirList();
}

function rebuildDirList() {
	let dirListElem = document.getElementById("dirlist");
	typeof (dirListElem !== 'undefined')
		{
		dirListElem.innerHTML = '';
		dirInnerHTML = '';
		
		// We need to reverse the keys in directoryCache.cache
		// to show the most recently used first.
		let keysArr = Array.from(directoryCache.cache.keys() );
		for (let key of keysArr.reverse()) {
			//console.log(key);
			let dirValue = decodeURIComponent(key);
			let dirChild = "<option value='" + dirValue + "'>";
			dirInnerHTML += dirChild;
			}
		
		if (dirInnerHTML !== '')
			{
			dirListElem.innerHTML = dirInnerHTML;
			}
		}
}

function saveDirCache() {
	let keysArr = Array.from(directoryCache.cache.keys() );
	let dirString = '';
	for (let key of keysArr.reverse()) {
		if (dirString === '')
			{
			dirString = key;
			}
		else
			{
			dirString += '|' + key;
			}
		}
	
	if (dirString !== '')
		{
		localStorage.setItem("dirCacheGlosser", dirString);
		}
	}

function loadDirCache() {
	if (!localStorage.getItem("dirCacheGlosser")) {
		return;
		}
		
	let dirString = localStorage.getItem("dirCacheGlosser");
	const keysArr = dirString.split("|");
	for (let key of keysArr) {
		directoryCache.cache.set(key, key);
		}
	}

// Adjust the heights of all the parts of the Search form directory picker.
function doDirectoryPickerResize() {

	// Set simple elements to a fixed height.
	// Note padding is included in height, margin is not
	let dirDialogTitleElement = document.getElementById("directoryPickerTitle");
	let dirDialogTitleElementHeight = 26;
	dirDialogTitleElement.style.height = dirDialogTitleElementHeight + "px";
	// total height 4 + 26 = 30px
	let dirDialogTitleElementTotalHeight = 30;
	
	let driveSelectorElem1 = document.getElementById("driveselector_1");
	let driveSelectorHeight = 24;
	driveSelectorElem1.style.height = driveSelectorHeight + "px"; // total height 24px
	let pickerDisplayElem = document.getElementById("pickerDisplayDiv");
	let pickerDisplayElemHeight = 24;
	pickerDisplayElem.style.height = pickerDisplayElemHeight + "px"; // total height 24 + 2 = 26px
	let pickerDisplayElemTotalHeight = 26;
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
	let driveLeftElement = document.getElementById("fileTreeLeft");
	driveLeftElement.style.height = scrollAdjustedHeight + "px";
	// scrollDriveListLeft: driveLeftElement less driveSelectorHeight
	let scrollDriveLeftElement = document.getElementById("scrollDriveListLeft");
	let scrollDriveLeftHeight = scrollAdjustedHeight - driveSelectorHeight;
	scrollDriveLeftElement.style.height = scrollDriveLeftHeight + "px";
}

function showDirectoryPicker() {
	doDirectoryPickerResize();
	
	let picker = document.getElementById("dirpickerMainContainer");
	if (picker !== null)
		{
		picker.style.display = 'block';
		// Poor choice: this pops open the drive dropdown on iPad: document.getElementById("driveselector_1").focus();
		// We need the focus so that Enter/Escape keys will work right from the start.
		document.getElementById("dirOkButton").focus();
		}
}

function hideDirectoryPicker() {
	let picker = document.getElementById("dirpickerMainContainer");
	if (picker !== null)
		{
		picker.style.display = 'none';
		}
}

// On "OK" in the dir picker: set directory in the "Directory" text box.
function setDirectoryFromPicker() {
	let displayedDir = document.getElementById('searchdirectory');
	if (displayedDir !== null)
		{
		document.getElementById('searchdirectory').value = document.getElementById('pickerDisplayedDirectory').innerHTML;
		}
	hideDirectoryPicker();
	setFocusToDirectoryBox();
}

function setFocusToDirectoryBox() {
	document.getElementById("searchdirectory").focus();
	}

// The directory picker for Search is a variant of the picker used in intramine_filetree.pl,
//  Clicking on a directory both selects it and expands (or collapses) it.
function initDirectoryDialog() {
	let driveSelector = document.getElementById('driveselector_1');
	if (driveSelector !== null)
		{
		let driveSelected = driveSelector.value;
		selectTheDirectory(null, driveSelected);
		}

	$('#scrollDriveListLeft').fileTree({
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
		doDirectoryPickerResize();
	});
	
	document.getElementById("dirpickerMainContainer").addEventListener('keydown', dirKey);
}

function driveChanged(tree_id, value) {
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
		doDirectoryPickerResize();
	});
}

// Remember pick, and show it in "pickerDisplayedDirectory".
function selectTheDirectory(el, file) {
	if (file.length === 0)
		{
		return;
		}
	
	let fileMarkerPos = file.indexOf("__FILE__");
	if (fileMarkerPos > 0)
		{
		file = file.substring(0, fileMarkerPos);
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
		hideDirectoryPicker();
		e.preventDefault();
		}
	else if (code === "Enter")
		{
		setDirectoryFromPicker();
		e.preventDefault();
		}
}


// Fixed sort order for the directory picker.
function currentSortOrder() {
	return("name_ascending");
}

function rememberCheckBoxes() {
	let inline = document.querySelector('input[name="inline"]:checked');
	let valInline = (inline === null) ? "no" : "yes";
	let hoverGIFs = document.querySelector('input[name="hoverGIFs"]:checked');
	let valHoverGIFs = (hoverGIFs === null) ? "no" : "yes";
	localStorage.setItem("inlineImagesGlosser", valInline);
	localStorage.setItem("hoverGIFsGlosser", valHoverGIFs);
}

// Set Inline images and Always hover GIFs checkboxes.
function restoreCheckBoxes() {
	if (!localStorage.getItem("inlineImagesGlosser"))
		{
		return;
		}
	if (!localStorage.getItem("hoverGIFsGlosser"))
		{
		return;
		}
			
	let valInline = localStorage.getItem("inlineImagesGlosser");
	if (valInline === "yes")
		{
		document.getElementById("inlineCheck").checked = true;
		}
	else
		{
			document.getElementById("inlineCheck").checked = false;
		}
	let valHoverGIFs = localStorage.getItem("hoverGIFsGlosser");
	if (valHoverGIFs === "yes")
		{
		document.getElementById("hoverGIFsCheck").checked = true;
		}
	else
		{
		document.getElementById("hoverGIFsCheck").checked = false;
		}
}

ready(finishDirPickerSetup);
ready(restoreCheckBoxes);
ready(doResize);
ready(hideSpinner);
window.addEventListener("resize", doResize);
window.addEventListener("resize", doDirectoryPickerResize);

window.addEventListener('wsinit', function (e) { registerGlosserCallbacks(); }, false);