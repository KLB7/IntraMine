/**
 * debounce.js: //debounce() is (ultimately) from http://underscorejs.org/#debounce.
 */

let JD = {};

JD.debounce = function(func, wait, immediate) {
	let timeout;
	return function() {
		let context = this, args = arguments;
		let later = function() {
			timeout = null;
			if (!immediate)
				{
				func.apply(context, args);
				}
		};
		let callNow = immediate && !timeout;
		clearTimeout(timeout);
		timeout = setTimeout(later, wait || 200);
		if (callNow)
			{
			func.apply(context, args);
			}
	};
};
