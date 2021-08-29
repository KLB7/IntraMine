/** statusEvents.js: use WebSockets to flash "LEDs" on the Status page.See also status.js.
 */

// This is called in response to the custom 'wsinit' event, see also websockets.js.
// The function name should be unique to avoid collisions.
function registerActivityCallback() {
	addCallback("activity", showActivity);
}


window.addEventListener('wsinit', function (e) { registerActivityCallback(); }, false);
