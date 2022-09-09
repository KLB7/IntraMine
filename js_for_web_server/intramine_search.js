/**
 * intramine_search.js: for intramine_search.pl.
 * Load the Search dialog, manage resize, language selection, sorting,
 * submit search request and show results.
 */
	
window.addEventListener("load", doResize);
//window.addEventListener("load", doDirectoryPickerResize);
window.addEventListener("resize", doResize);
window.addEventListener("resize", doDirectoryPickerResize);

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

function setFocusToTextBox() {
	document.getElementById("searchtext").focus();
}

function setFocusToDirectoryBox() {
document.getElementById("searchdirectory").focus();
}

function blurTextBox() {
	document.getElementById("searchtext").blur();
}

// Call loader when ready.
function ready(fn) {
  if (document.readyState != 'loading'){
	fn();
  } else {
	document.addEventListener('DOMContentLoaded', fn);
  }
}

// Load and set page content.
// Mainly a search form. See intramine_search.pl#SearchForm().
async function loadPageContent() {
	showSpinner();
	try {
		let theAction = 'http://' + theHost + ':' + thePort + '/?req=frm';
		const response = await fetch(theAction);
		if (response.ok)
			{
			let text = await response.text();
			let e1 = document.getElementById('searchform');
			e1.innerHTML = text;
			selectAllOrNone(true);
			setFocusToTextBox();
			addFormClickListener();
			initDirectoryDialog();
			hideSpinner();
			}
		else
			{
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(errorID);
			e1.innerHTML = '<p>Error, server reached but it returned an error!</p>';
			hideSpinner();
			}
	}
	catch(error) {
		// There was a connection error of some sort
		let e1 = document.getElementById(errorID);
		e1.innerHTML = '<p>Connection error!</p>';
		hideSpinner();
	}
}

ready(loadPageContent);

// Send "req=results" with all search form fields back to Search (intramine_search.pl).
// The "req=results" request action calls intramine_search.pl#SearchResults().
// The oReq.responseText response holds all the hits from the search (with links).
// For the call, see intramine_search.pl#SearchForm().
async function searchSubmit(oFormElement) {
	if (!oFormElement.action) { return; }
	
	// Send an "activity" message.
	wsSendMessage('activity ' + shortServerName + ' ' + ourSSListeningPort);
	
	let findThis = '';
	e1 = document.getElementById('headingAboveContents');
	e1.innerHTML = "&nbsp;";
	showSpinner();

	let oField, sFieldType = "";
	let remoteValue = (weAreRemote)? '1': '0';
	let allowEditValue = (allowEditing)? '1': '0';
	let useAppValue = (useAppForEditing)? '1': '0';
	let sSearch = "&req=results&remote=" + remoteValue
		+ "&allowEdit=" + allowEditValue + "&useApp=" + useAppValue;

	for (let nItem = 0; nItem < oFormElement.elements.length; nItem++)
		{
		oField = oFormElement.elements[nItem];
		if (!oField.hasAttribute("name")) { continue; }
		sFieldType = oField.nodeName.toUpperCase() === "INPUT" ? oField.getAttribute("type").toUpperCase() : "TEXT";
		if ((sFieldType !== "RADIO" && sFieldType !== "CHECKBOX") || oField.checked)
			{
			if (oField.name === 'findthis')
				{
				sSearch += "&" + encodeURIComponent(oField.name) + "=" + encodeURIComponent(oField.value);
				findThis = oField.value;
				}
			else
				{
				// sSearch += "&" + escape(oField.name) + "=" + escape(oField.value);
				sSearch += "&" + encodeURIComponent(oField.name) + "=" + encodeURIComponent(oField.value);
				}
			}
		}

	// Pick up any directory. And if subdirs wanted.
	let dirvalElement = document.getElementById("searchdirectory");
	let dirValue = encodeURIComponent(dirvalElement.value);
	if (dirValue === "")
		{
		dirValue = 'ALL';
		}
	sSearch += "&directory=" + dirValue;

	// And tack on whether languages or extensions have been selected.
	let val = document.querySelector('input[name="langExt"]:checked').value;
	sSearch += "&extFilter=" + val;

	try {
		let theAction = oFormElement.action + sSearch;
		blurTextBox(); // Remove the darned suggestions select dropdown that sometimes stays up.
		const response = await fetch(theAction);
		if (response.ok)
			{
			let resp = await response.text();
			// Pull elapsed time from beginning of response.
			let elapsed = '';
			let firstSpanMatch = /^(<span>[^<]+<\/span>)/.exec(resp);
			if (firstSpanMatch !== null)
				{
				elapsed = firstSpanMatch[1];
				resp = resp.replace(/^<span>[^<]+<\/span>/, '');
				}
			let e1 = document.getElementById('scrollAdjustedHeight');
			e1.innerHTML = resp;
			e1 = document.getElementById('headingAboveContents');
			e1.innerHTML = "Results for: <strong>" + findThis + "</strong>" + elapsed + "<hr>";
			hideSpinner();
			setFocusToTextBox();
			
			// Reset the random number in action, to force response even when
			// form fields are unchanged. (Not sure this is needed, really.)
			let oldAction = String(oFormElement.action);
			let newAction = oldAction.replace(/rddm=\d+$/, 'rddm=' + String(getRandomInt(1, 65000)));
			oFormElement.action = newAction;
			
			// Reset height of search results after content change.
			doResize();
			
			// Apply preferred current sort order.
			let sorter = document.getElementById("sortBy");
			let selectedValue = sorter.value;
			if (selectedValue !== 'Score')
				{
				sortSearchResults(sorter);
				}
			}
		else
			{
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(errorID);
			e1.innerHTML = '<p>Error, server reached but it returned an error while searching!</p>';
			hideSpinner();
			setFocusToTextBox();
			}
	}
	catch(error) {
		// There was a connection error of some sort
		let e1 = document.getElementById(errorID);
		e1.innerHTML = '<p>Connection error while searching!</p>';
		hideSpinner();
		setFocusToTextBox();		
	}
}

// Swap Language dropdown with Extensions dropdown when the radio buttons for those are clicked.
function swapLangExt() {
	let val = document.querySelector('input[name="langExt"]:checked').value;

	let itemList = document.getElementById(val);
	let dropDownContainer = document.getElementById("checkboxes");
	dropDownContainer.innerHTML = itemList.innerHTML;

	selectAllOrNone(true);

	let languagesBeingDone = true;
	if (val.indexOf("language") < 0)
		{
		languagesBeingDone = false;
		}

	let multiSummaryElement = document.getElementById("multiLanguageSummary");
	if (multiSummaryElement !== null)
		{
		if (languagesBeingDone)
			{
			multiSummaryElement.textContent = '(all languages are selected)';
			}
		else
			{
			multiSummaryElement.textContent = '(all extensions are selected)';
			}
		}

}

// elasticsearcher.pm#FormatHitResults() inserts calls to this, to open a file
// in the Viewer (intramine_file_viewer_cm.pl).
function viewerOpenAnchor(href) {
	let properHref = href.replace(/^file\:\/\/\//, '');
	
// Argument-based 'href=path' approach:
	let url = 'http://' + theHost + ':' + theMainPort + '/' + viewerShortName + '/?href=' +
				properHref + '&rddm=' + String(getRandomInt(1, 65000));
	
	// A more RESTful 'Viewer/file/path/' approach
//	let url = 'http://' + theHost + ':' + theMainPort + '/' + viewerShortName + '/file/' +
//				properHref + '&rddm=' + String(getRandomInt(1, 65000));

	window.open(url, "_blank");
	}

// For the Search form, handlers for the "All" and "None" language thingies.
function selectAllOrNone(checkEm) {
	let oFormElement = document.forms[0]; // document.getElementById(formID);

	let checks = document.getElementById("checkboxes");
	let checksChildren = checks.children;

	for (let i = 0; i < checksChildren.length; ++i)
		{
		let checkItem = (typeof (checksChildren[i].children[0]) !== 'undefined') ? checksChildren[i].children[0]: null;
		if (checkItem === null) { continue; }
		if (!checkItem.hasAttribute("name")) { continue; }
		let sFieldType = checkItem.nodeName.toUpperCase() === "INPUT" ? checkItem.getAttribute("type").toUpperCase() : "TEXT";
		if (sFieldType === "CHECKBOX" && checkItem.name !== 'matchexact' && checkItem.name !== 'subdirs')
			{
			if (checkEm)
				{
				checkItem.checked = 'checked';
				}
			else
				{
				checkItem.checked = '';
				}
			}
		}


	return;
	}

// Update the main content holder's height and width, so scrolling works properly etc.
function doResize() {
	let el = document.getElementById("scrollAdjustedHeight");
	
	let pos = getPosition(el);
	let windowHeight = window.innerHeight;
	let elHeight = windowHeight - pos.y - 10;
	let newHeightPC = (elHeight/windowHeight)*100;
	el.style.height = newHeightPC + "%";
	
	let windowWidth = window.innerWidth;
	el.style.width = windowWidth - 4 + "px";
	
	// Hide the spinner, and replace it with the help question mark.
	hideSpinner();
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

// Search results are in table cells. Within each cell, the (first) <p> contains the hitsummary.
// Within that, spans for all items of interest when sorting are:
// span class='resultAnchors' (two anchors, text of first anchor has file name proper)
// span class='resultTime' (date 'at' time, time in 24 hour format)
// span class='resultSize' (number followed by B/KB/MB/GB)
// span class='resultScore'
function sortSearchResults(sortElem) {
	let selectedValue = sortElem.value;
	quickSortResults('elasticSearchResultsTable', selectedValue);
}

// Sort search results by Score, Name, Date, Size, Extension, with a quick sort.
// See quicksort.js#quickSort() for the sorter.
function quickSortResults(tableID, sortBy) {
	let table = document.getElementById("elasticSearchResultsTable");
	if (table === null)
		{
		return;
		}
	let rows = table.rows;
	let rowsParent = table.tBodies[0];
	let originalNumRows = rows.length;
	let tableIndexes = [];
	let sortedTableIndexes = [];
	for (let i = 0; i < rows.length; ++i)
		{
		tableIndexes.push(i);
		}
	
	if (sortBy === 'Score')
		{
		sortedTableIndexes = quickSortByScores(rows, tableIndexes);
		}
	else if (sortBy === 'Name')
		{
		sortedTableIndexes = quickSortByFileNamesInAnchors(rows, tableIndexes);
		}
	else if (sortBy === 'Date')
		{
		sortedTableIndexes = quickSortByFileDateTimes(rows, tableIndexes);
		}
	else if (sortBy === 'Size')
		{
		sortedTableIndexes = quickSortByFileSizes(rows, tableIndexes);
		}
	else if (sortBy === 'Extension')
		{
		sortedTableIndexes = quickSortByFileExtensionsInAnchors(rows, tableIndexes);
		}
	putRowsInOrder();
	
	// Nodes are dynamic, re-ordering the rows in a table is a bit like wrestling
	// a jellyfish. Below is a hard-won solution.
	function putRowsInOrder() {
		for (let i = 0; i < originalNumRows; ++i)
			{
			let newRow = rows[sortedTableIndexes[i]].cloneNode(true);
			rowsParent.appendChild(newRow);
			}
		for (let i = 0; i < originalNumRows; ++i)
			{
			let nodeGoingOut = table.rows[0];
			rowsParent.removeChild(nodeGoingOut);
			}
		}
	} // quickSortResults()

// Sort by score descending.
function quickSortByScores(rows, tableIndexes) {
	function scoreComp(a, b) {
		let result = 0;
		let first = rows[tableIndexes[a]].getElementsByClassName('resultScore')[0];
		let second = rows[tableIndexes[b]].getElementsByClassName('resultScore')[0];
		if (typeof first !== 'undefined' && typeof second !== 'undefined')
			{
			let firstScore = parseFloat(first.innerText);
			let secondScore = parseFloat(second.innerText);
			if (firstScore > secondScore)
				{
				result = -1;
				}
			if (firstScore < secondScore)
				{
				result = 1;
				}
			}
		
		return(result);
		}
	
	let sortedTableIndexes = quickSort(tableIndexes, scoreComp); // quicksort.js
	return(sortedTableIndexes);
	}

// Sort by file name ascending a-z.
function quickSortByFileNamesInAnchors(rows, tableIndexes) {
	function fileNameComp(a, b) {
		let result = 0;
		let first = rows[tableIndexes[a]].getElementsByClassName('resultAnchors')[0];
		let second = rows[tableIndexes[b]].getElementsByClassName('resultAnchors')[0];
		if (typeof first !== 'undefined' && typeof second !== 'undefined')
			{
			let firstAnchorList = first.getElementsByTagName('a');
			let secondAnchorList = second.getElementsByTagName('a');
			if (firstAnchorList.length && secondAnchorList.length)
				{
				let firstAnchor = firstAnchorList[0];
				let secondAnchor = secondAnchorList[0];
				let firstFileName = firstAnchor.innerText;
				let secondFileName = secondAnchor.innerText;
				if (firstFileName < secondFileName)
					{
					result = -1;
					}
				if (firstFileName > secondFileName)
					{
					result = 1;
					}
				}
			}
		return(result);
		}
	
	let sortedTableIndexes = quickSort(tableIndexes, fileNameComp); // quicksort.js
	return(sortedTableIndexes);
	}

// Newest first (note [a] and [b] are reversed in first, second).
function quickSortByFileDateTimes(rows, tableIndexes) {
	function dateTimeComp(a, b) {
		let result = 0;
		let first = rows[tableIndexes[b]].getElementsByClassName('resultTime')[0];
		let second = rows[tableIndexes[a]].getElementsByClassName('resultTime')[0];
		if (typeof first !== 'undefined' && typeof second !== 'undefined')
			{
			// <span class="resultTime">2016-06-07 at 08:53</span>
			let firstText = first.innerText;
			let secondText = second.innerText;
			let firstDTMatch = /^([0-9-]+)\sat\s([0-9:]+)$/.exec(firstText);
			let secondDTMatch = /^([0-9-]+)\sat\s([0-9:]+)$/.exec(secondText);
			if (firstDTMatch !== null && secondDTMatch != null)
				{
				let firstDate = firstDTMatch[1];
				let firstTime = firstDTMatch[2];
				let secondDate = secondDTMatch[1];
				let secondTime = secondDTMatch[2];
				let firstYMDMatch = /^(\d\d\d\d).(\d\d).(\d\d)$/.exec(firstDate);
				let secondYMDMatch = /^(\d\d\d\d).(\d\d).(\d\d)$/.exec(secondDate);
				if (firstYMDMatch !== null && secondYMDMatch != null)
					{
					let firstYr = parseInt(firstYMDMatch[1], 10);
					let firstMn = parseInt(firstYMDMatch[2], 10);
					let firstDay = parseInt(firstYMDMatch[3], 10);
					let secondYr = parseInt(secondYMDMatch[1], 10);
					let secondMn = parseInt(secondYMDMatch[2], 10);
					let secondDay = parseInt(secondYMDMatch[3], 10);
					if (secondYr > firstYr)
						{
						result = -1;
						}
					else if (firstYr === secondYr && secondMn > firstMn)
						{
						result = -1;
						}
					else if (firstYr === secondYr && firstMn === secondMn && secondDay > firstDay)
						{
						result = -1;
						}
					else if (firstYr === secondYr && firstMn === secondMn && firstDay === secondDay)
						{
						let firstTimeMatch = /^(\d+)\:(\d+)$/.exec(firstTime);
						let secondTimeMatch = /^(\d+)\:(\d+)$/.exec(secondTime);
						if (firstTimeMatch !== null && secondTimeMatch != null)
							{
							let firstHour = firstTimeMatch[1];
							let firstMin = firstTimeMatch[2];
							let secondHour = secondTimeMatch[1];
							let secondMin = secondTimeMatch[2];
							if (secondHour > firstHour)
								{
								result = -1;
								}
							else if (firstHour === secondHour && secondMin > firstMin)
								{
								result = -1;
								}
							}
						}
					}
				}
			}
		
		return(result);
		}
	let sortedTableIndexes = quickSort(tableIndexes, dateTimeComp); // quicksort.js
	return(sortedTableIndexes);
	}

// Smallest first (somewhat arbitrary). For largest first, reverse [a] and [b]
// in first and second.
function quickSortByFileSizes(rows, tableIndexes) {
	function fileSizeComp(a,b) {
		let result = 0;
		let first = rows[tableIndexes[a]].getElementsByClassName('resultSize')[0];
		let second = rows[tableIndexes[b]].getElementsByClassName('resultSize')[0];
		if (typeof first !== 'undefined' && typeof second !== 'undefined')
			{
			let firstText = first.innerText;
			let secondText = second.innerText;
			let firstSizeMatch = /^([0-9.]+)\s+(\w+)$/.exec(firstText);
			let secondSizeMatch = /^([0-9.]+)\s+(\w+)$/.exec(secondText);
			if (firstSizeMatch !== null && secondSizeMatch != null)
				{
				let firstNum = parseFloat(firstSizeMatch[1]);
				let firstUnits = firstSizeMatch[2];
				let secondNum = parseFloat(secondSizeMatch[1]);
				let secondUnits = secondSizeMatch[2];
				if (firstUnits === 'KB')
					{
					firstNum *= 1000;
					}
				else if (firstUnits === 'MB')
					{
					firstNum *= 1000000;
					}
				else if (firstUnits === 'GB')
					{
					firstNum *= 1000000000;
					}
				if (secondUnits === 'KB')
					{
					secondNum *= 1000;
					}
				else if (secondUnits === 'MB')
					{
					secondNum *= 1000000;
					}
				else if (secondUnits === 'GB')
					{
					secondNum *= 1000000000;
					}
				
				if (firstNum < secondNum)
					{
					result = -1;
					}
				if (firstNum > secondNum)
					{
					result = 1;
					}
				}
			}
		return(result);
		}
	let sortedTableIndexes = quickSort(tableIndexes, fileSizeComp); // quicksort.js
	return(sortedTableIndexes);
	}

// Sort by extension, and within each extension by file name. Ascending a-z for both parts.
function quickSortByFileExtensionsInAnchors(rows, tableIndexes) {
	function fileExtensionComp(a, b) {
		let result = 0;
		let first =  rows[tableIndexes[a]].getElementsByClassName('resultAnchors')[0];
		let second =  rows[tableIndexes[b]].getElementsByClassName('resultAnchors')[0];
		if (typeof first !== 'undefined' && typeof second !== 'undefined')
			{
			let firstAnchorList = first.getElementsByTagName('a');
			let secondAnchorList = second.getElementsByTagName('a');
			if (firstAnchorList.length && secondAnchorList.length)
				{
				let firstAnchor = firstAnchorList[0];
				let secondAnchor = secondAnchorList[0];
				let firstFileName = firstAnchor.innerText;
				let secondFileName = secondAnchor.innerText;
				let firstExtMatch = /\.(\w+)$/.exec(firstFileName);
				let secondExtMatch = /\.(\w+)$/.exec(secondFileName);
				if (firstExtMatch !== null && secondExtMatch != null)
					{
					let firstExt = firstExtMatch[1];
					let secondExt = secondExtMatch[1];
					if (firstExt < secondExt || (firstExt === secondExt && firstFileName < secondFileName))
						{
						result = -1;
						}
					}
				}
			}
		
		return(result);
		}
	let sortedTableIndexes = quickSort(tableIndexes, fileExtensionComp); // quicksort.js
	return(sortedTableIndexes);
	}

// A dropdown menu with check boxes.
let languageDropdownExpanded = false;

// Show/hide the language dropdown.
function showCheckboxes() {
  let checkboxes = document.getElementById("checkboxes");
  if (!languageDropdownExpanded) {
    checkboxes.style.display = "block";
    checkboxes.style.height = "400px";
    languageDropdownExpanded = true;
    let summaryElement = document.getElementById("languageSummary");
	if (summaryElement !== null)
		{
		summaryElement.textContent = '';
		}
   } else {
    checkboxes.style.display = "none";
    checkboxes.style.height = "20px";
    languageDropdownExpanded = false;
    updateLanguageSummary();
  }
}

// A brief summary below the Language dropdown shows which languages have been selected.
// Or which extensions have been selected.
// Up to 4 specific languages are shown, above that it says "etc".
// And of course if all are selected the summary reads "all are selected".
function updateLanguageSummary() {
	let summary = '';
	let firstLanguage = '';
	let secondLanguage = '';
	let thirdLanguage = '';
	let numLanguagesSelected = 0;
	let numLanguages = 0;
	
	let oFormElement = document.forms[0]; // document.getElementById(formID);

	// Get languages, and whether all are selected.
	let checkElement = document.getElementById("checkboxes");
	let inputs = checkElement.getElementsByTagName("INPUT");
	for (let i = 0; i < inputs.length; ++i)
		{
		let theInput = inputs[i];
		if (theInput.checked && theInput.name !== 'matchexact' && theInput.name !== 'subdirs')
			{
			++numLanguagesSelected;
			if (firstLanguage === '')
				{
				firstLanguage = theInput.name.substr(4);
				}
			else if (secondLanguage === '')
				{
				secondLanguage = theInput.name.substr(4);
				}
			else if (thirdLanguage === '')
				{
				thirdLanguage = theInput.name.substr(4);
				}
			}
		++numLanguages;
		}

	let val = document.querySelector('input[name="langExt"]:checked').value;
	let languagesBeingDone = true;
	if (val.indexOf("language") < 0)
		{
		languagesBeingDone = false;
		}
	
	if (numLanguagesSelected === 0)
		{
		if (languagesBeingDone)
			{
				summary = '(no languages are selected)';
			}
		else
			{
				summary = '(no extensions are selected)';
			}
		
		}
	else if (numLanguagesSelected === numLanguages)
		{
		if (languagesBeingDone)
			{
			summary = '(all languages are selected)';
			}
		else
			{
			summary = '(all extensions are selected)';
			}
		}
	else
		{
		let lans = firstLanguage;
		if (secondLanguage !== '')
			{
			lans += ', ' + secondLanguage;
			if (thirdLanguage !== '')
				{
				lans += ', ' + thirdLanguage;
				}
			}
		if (numLanguagesSelected >= 4)
			{
			lans += ' etc';
			}
		summary = '(' + lans + ' selected)';
		}
	
	let summaryElement = document.getElementById("languageSummary");
	if (summaryElement !== null)
		{
		summaryElement.textContent = summary;
		}

	let multiSummaryElement = document.getElementById("multiLanguageSummary");
	if (multiSummaryElement !== null)
		{
		multiSummaryElement.textContent = summary;
		}
	}

function addFormClickListener() {
	let formDivEelement = document.getElementById("searchform");
	formDivEelement.addEventListener("mouseup", formMouseUp);
	}

// Handle clicks in form, collapse Language dropdown if it's expanded and click was elsewhere.
function formMouseUp(evt) {
	if (!languageDropdownExpanded)
		{
		return;
		}
	let target = evt.target;
	let mouseX = evt.clientX;
	let mouseY = evt.clientY;
	
	let languageDiv = document.getElementById("languageDropdown");
	let rect = languageDiv.getBoundingClientRect();
	let clickInRect = (mouseX >= rect.left && mouseX <= rect.right && mouseY >= rect.top && mouseY <= rect.bottom);
	if (!clickInRect)
		{
		showCheckboxes(); // ie collapse the dropdown
		}
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

// The directory picker for Search is a variant of the picker used in intramine_filetree.pl,
// for Search we just want to select a directory rather than open a file. So there are no
// file links here, and clicking a file just selects its enclosing directory. Clicking on
// a directory both selects it and expands (or collapses) it.
function initDirectoryDialog() {
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

