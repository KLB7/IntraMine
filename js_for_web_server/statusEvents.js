/** statusEvents.js: use WebSockets to flash "LEDs" on the Status page.See also status.js.
 */

// This is called in response to the custom 'wsinit' event, see also websockets.js.
// The function name should be unique to avoid collisions.
function registerActivityCallback() {
	addCallback("activity", showActivity);
	// Nope, doesn't work here: wsSendMessage("SUBSCRIBE__TS_activity_TE_");
	setTimeout(subscribeToActivity, 1000);
}

function subscribeToActivity() {
	wsSendMessage("SUBSCRIBE__TS_activity_TE_hello");
}


window.addEventListener('wsinit', function (e) { registerActivityCallback(); }, false);
