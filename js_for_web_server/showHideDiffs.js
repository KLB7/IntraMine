// showHideDiffs.js: Show diffs / Hide diffs button, and maintenance for it.

let diffsButtonShown = false;
let haveDiffs = true; 	// Requires setting after load
let showingDiffs = true; 		// Default is to show the diffs.
let diffsButtonId = "togglediffs";

function disableDiffsButton() {
	let diffButton = document.getElementById("togglediffs");
	if (diffButton === null)
		{
		return;
		}

	diffButton.disabled = true;
}

function toggleDiffs() {
	if (!haveDiffs)
		{
		return;
		}

	if (showingDiffs)
		{
		hideDiffs();
		showingDiffs = false;
		}
	else
		{
		showDiffs();
		showingDiffs = true;
		}
}

function showDiffs() {
	document.getElementById("togglediffs").value = "Hide diffs";
	const elements = document.querySelectorAll('.' + diffScrollMarkerClass);
	if (elements.length > 0)
		{
		elements.forEach((element) => {
			element.style.visibility = 'visible';
		});
		}
}

function hideDiffs() {
	document.getElementById("togglediffs").value = "Show diffs";
	const elements = document.querySelectorAll('.' + diffScrollMarkerClass);
	if (elements.length > 0)
		{
		elements.forEach((element) => {
			element.style.visibility = 'hidden';
		});
		}
}

function maintainShowHideDiffs() {
	let diffButton = document.getElementById("togglediffs");
	if (diffButton === null)
		{
		return;
		}
		
	haveDiffs = false;

	//let numDiffArrayEntries = textDiffChangedLines.length;
	const elements = document.querySelectorAll('.' + diffScrollMarkerClass);
	if (elements.length > 0)
		{
		haveDiffs = true;
		}
	
	if (haveDiffs && showingDiffs)
		{
		elements.forEach((element) => {
			element.style.visibility = 'visible';
		});
		}
	else if (haveDiffs && !showingDiffs)
		{
		elements.forEach((element) => {
			element.style.visibility = 'hidden';
		});
		}

	if (haveDiffs)
		{
		diffButton.disabled = false;
		}
	else
		{
		diffButton.disabled = true;
		}
}