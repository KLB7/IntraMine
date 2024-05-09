// spellcheck.js: handle enable/disable spell checker, get status.

let spellCheckIsInitialized = false;
let shouldDoSpellCheck = false;
let haveSpellCheckButton = false;

// See cmAutoLinks.js#requestLinkMarkupWithPort().
function shouldSpellCheck() {
	if (!spellCheckIsInitialized)
		{
		initializeSpellCheck();
		}
	
	return(shouldDoSpellCheck);
}

// See editor.js#loadFileIntoCodeMirror().
function initializeSpellCheck() {
	spellCheckIsInitialized = true;
	let buttonElem = document.getElementById("spellcheck-button");
	if (buttonElem === null)
		{
		return;
		}

	haveSpellCheckButton = true;

	let checkKey = thePath + 'spellcheck';
	let checking = localStorage.getItem(checkKey);
	if (checking === 'true' || checking === true)
		{
		checking = true;
		}
	else
		{
		checking = false;
		}

	shouldDoSpellCheck = checking;
	
	setSpellcheckButtonText();
}

// See editor.js at bottom for
// addClickHandler("spellcheck-button", toggleSpellCheck);
function toggleSpellCheck(e) {
	if (!haveSpellCheckButton)
		{
		return; // Admittedly redundand
		}
	let checkKey = thePath + 'spellcheck';
	let checking = localStorage.getItem(checkKey);
	if (checking === 'true' || checking === true)
		{
		checking = true;
		}
	else
		{
		checking = false;
		}

	checking = !checking;
	localStorage.setItem(checkKey, checking);

	shouldDoSpellCheck = checking;
	
	setSpellcheckButtonText();

	clearAndAddAutoLinks();
}

// Toggle text between "Check" and "Checking", also
// adjust appearance to make "Checking" stand out a bit.
function setSpellcheckButtonText() {
	let buttonElem = document.getElementById("spellcheck-button");
	if (buttonElem === null)
		{
		return;
		}
	let buttonText = (shouldDoSpellCheck) ? 'Checking' : 'Check';
	buttonElem.value = buttonText;

	if (shouldDoSpellCheck)
		{
		addClass(buttonElem, "buttonIsOn");
		}
	else
		{
		removeClass(buttonElem, "buttonIsOn");
		}
}


