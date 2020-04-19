/*!
 * Run a callback function after scrolling has stopped
 * (c) 2017 Chris Ferdinandi, MIT License, https://gomakethings.com
 * @param  {Function} callback The function to run after scrolling
 */
 // (modified to accept an element to listen on, and 200 msec delay.)
var scrollStop = function (elem, callback) {

	// Make sure a valid callback was provided
	if (!callback || typeof callback !== 'function') return;

	// Setup scrolling variable
	var isScrolling;

	// Listen for scroll events
	elem.addEventListener('scroll', function (event) {

		// Clear our timeout throughout the scroll
		elem.clearTimeout(isScrolling);

		// Set a timeout to run after scrolling ends
		isScrolling = setTimeout(function() {

			// Run the callback
			callback();

		}, 200);

	}, false);

};