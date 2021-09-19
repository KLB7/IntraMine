// chatFlash.js:

function registerChatCallbacks() {
	// addToDisplayedMessageList() is only defined for the Chat server.
	if(typeof addToDisplayedMessageList === "function")
		{
		addCallback("Chat:", newChatMessage);
		}
	else
		{
		addCallback("Chat:", flashChatinNavBar);
		}
}

function newChatMessage(message) {
	breakUpAndAddToDisplayedMessageList(message);
	flashChatinNavBar();
}

function flashChatinNavBar() {
	let navbar = document.getElementById("nav");
	if (navbar === null)
		{
		return;
		}
	
	// Find the ToDo anchor in the navigation bar.
    let aTags = navbar.getElementsByTagName("a");
    let searchText = "Chat";
    let chatElem = null;

    for (let i = 0; i < aTags.length; i++)
        {
		if (aTags[i].textContent.indexOf(searchText) == 0)
            {
            chatElem = aTags[i];
            break;
            }
        }
        
    if (chatElem !== null)
        {
        flashChat(chatElem);
        }	
}

function flashChat(chatElem) {
	setIntervalX(toggleChat, chatElem, 200, 10);
}

function setIntervalX(callback, arg, delay, repetitions) {
    var x = 0;
    var intervalID = window.setInterval(function () {

       callback(arg);

       if (++x === repetitions) {
           window.clearInterval(intervalID);
       }
    }, delay);
}

function toggleChat(chatElem) {
	if (hasClass(chatElem, 'flashOn'))
		{
		removeClass(chatElem, 'flashOn');
		}
	else
		{
		addClass(chatElem, 'flashOn');
		}
}

window.addEventListener('wsinit', function (e) { registerChatCallbacks(); }, false);