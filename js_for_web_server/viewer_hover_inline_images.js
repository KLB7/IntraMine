// viewer_hover_inline_images.js: toggle between showing images
// as hover tooltips or inline.
// Only for .txt files. When the #inlineImages button is clicked, we do a reload().
// The state is remembered in localStorage.

// Hover / Inline Button clicked, set localStorage for
// 'inlineImages' and reload.
function toggleImagesButton() {
	let buttonElem = document.getElementById("inlineImages");
	if (buttonElem === null)
		{
		return;
		}
	let shouldInline = shouldInlineImages();
	shouldInline = !shouldInline;
	let imageKey = thePath + '?' + 'inlineImages';
	localStorage.setItem(imageKey, shouldInline);
	
	window.location.reload();
}

// Button hover / inline state is kept in localStorage.
function shouldInlineImages() {
	let imageKey = thePath + '?' + 'inlineImages';
	let shouldInline = localStorage.getItem(imageKey);
	if (shouldInline === 'true' || shouldInline === true)
		{
		shouldInline = true;
		}
	else
		{
		shouldInline = false;
		}

	return(shouldInline);
	}

// Call during load, or when the Hover / Inline button is clicked.
function setImagesButtonText() {
	let buttonElem = document.getElementById("inlineImages");
	if (buttonElem === null)
		{
		return;
		}
	let imageKey = thePath + '?' + 'inlineImages';
	let shouldInline = shouldInlineImages();
	let buttonText = (shouldInline) ? 'Hover Images' : 'Inline Images';
	buttonElem.value = buttonText;
}
