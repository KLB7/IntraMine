// popup_image_cache.js: retrieve bin64 images from a Map.
// The Map is created in gloss.pm when loading images for
// glossary popups. The goal is to have just
// one stored instance of each image that's use in a popup
// definition. Images are loaded into the popup definition
// when the popup is shown.

// Given popup hint text containing image placeholders such as '__img__cache__00007',
// replace with bin64 image from imageCache.
function loadCachedImages(text) {

	// If we get here too early before imageCache is defined, just leave.
	if (typeof imageCache === 'undefined')
		{
		return;
		}

	let keyLength = 19; // Length of __img__cache__ plus 5 for the digits
	const imagePositions = [];
	let cacheKeyRegExp = new RegExp('__img__cache__[0-9][0-9][0-9][0-9][0-9]', 'g');
	let match = {};
	while ((match = cacheKeyRegExp.exec(text)) !== null)
		{
		let currentMatchPos = match.index;
		imagePositions.push(currentMatchPos);
		}
		
	// Loop through array in reverse, putting in images.
	for (let i = imagePositions.length - 1; i >= 0; --i)
		{
		let imageKey = text.substr(imagePositions[i], keyLength);
		if (imageCache.has(imageKey))
			{
			let bin64Image = imageCache.get(imageKey);
			text = text.substr(0, imagePositions[i]) + bin64Image + text.substr(imagePositions[i] + keyLength);
			}
		}
		
	return(text);
}
