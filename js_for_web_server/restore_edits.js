// restore_edits.js: for when an edited file is closed without saving
// and later re-opened (or the view is refreshed).
// Applies to IntraMine's built-in Editor only.
// Save edits to localStorage, as diffs from the last saved version.
// Clear localStorage on a Save.
// On load, if there are diffs in localStorage, restore them,
// with a message up top mentioning Undo will remove them
// (for the message, see editor.js#adviseUserEditsWereRestored()).

let dmp; 			// diff match patch, see diff_match_patch_uncompressed.js
let savedText = ''; // Last saved version, for comparison against current text.
let diffKey = '';	// For localStorage saving of text diffs.
let lazySetDiffs = JD.debounce(setDiffs, 2000);

// Called by editor.js#loadFileIntoCodeMirror().
function startDiffer() {
	dmp = new diff_match_patch();
	diffKey = thePath + '?' + 'latestDiffs';
}

// Save a copy of the original text, for comparison against current text.
function setSavedText(text) {
	savedText = text;
}

// Return most recently saved version of text.
function getSavedText() {
	return(savedText);
}

function clearSavedDiffs() {
	localStorage.setItem(diffKey, '');
}

// Call after setSavedText().
// Returns text with restored edits or '' if no edits.
function textWithEditsRestored() {
	let retrievedDiffText = localStorage.getItem(diffKey);
	if (retrievedDiffText === null || retrievedDiffText === '')
		{
		return('');
		}
	
	let retrievedDiffs = dmp.patch_fromText(retrievedDiffText);
	let text = dmp.patch_apply(retrievedDiffs, savedText)[0];
	
	return(text);
}

function setDiffs(newText) {
	clearSavedDiffs();
	let diff = dmp.patch_make(savedText, newText);
	const textDiff = dmp.patch_toText(diff);
	localStorage.setItem(diffKey, textDiff);
}

