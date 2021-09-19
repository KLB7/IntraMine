// chat.js:

let peerAddress = '';
let messageHeight = 0;
let newestFirst = true;

// "sleep" for ms milliseconds.
function sleepChat(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function sendMessage(oFormElement) {
	let actualMessage = document.getElementById("messageid").value;
	if (actualMessage === '')
		{
		// TODO display error message is empty.
		return;
		}
	actualMessage = actualMessage.replace(/\n/g, '_NL_');
	actualMessage = actualMessage.replace(/\^/g, '_HAT_');

	let name = document.getElementById("nameid").value;
	if (name === '')
		{
		name = peerAddress;
		}
	
	let timestamp = currentDateStamp();
	
	let message = "Chat:^" + name + "^" + peerAddress + "^" + timestamp + "^" + actualMessage;
	saveMessage(message);
	await sleepChat(300);
	wsSendMessage(message);
	resetMessageArea();
}

//Pad given value to the left with "0"
function AddZero(num) {
    return (num >= 0 && num < 10) ? "0" + num : num + "";
}

function currentDateStamp() {
	let now = new Date();
	let strDateTime = [[now.getFullYear(),
        AddZero(now.getMonth() + 1), 
		AddZero(now.getDate())].join("/"), 
        [AddZero(now.getHours()), 
        AddZero(now.getMinutes())].join(":"), 
        now.getHours() >= 12 ? "PM" : "AM"].join(" ");
		
	// TEST ONLY
	//console.log("DT: |" + strDateTime + "|"); //DT: |2021/09/16 17:15 PM|
	
	return strDateTime;
}

function breakUpAndAddToDisplayedMessageList(message) {
	let fieldsArr = message.split("^");
	let name = fieldsArr[1]; // Skip "Chat:"
	let peer = fieldsArr[2];
	let timestamp = fieldsArr[3];
	let actualMessage = fieldsArr[4];
	
	addToDisplayedMessageList(name, peer, timestamp, actualMessage, newestFirst);
}

// Display message.
// "Our" messages have name in black, flush left.
// Messages from "others" have name in colour, indented slightly with a hint of a tint.
function addToDisplayedMessageList(name, peer, timestamp, actualMessage, newFirst) {
	let parent = document.getElementById(messagesID);
	let newElement = document.createElement("div");
	if (newFirst)
		{
		newElement = parent.insertBefore(newElement, parent.firstChild);
		}
	else // add at bottom
		{
		newElement = parent.appendChild(newElement);
		}
	
	addClass(newElement, "bubble");
	
	let nameClass = 'my-name'; // no good, wrong colour: 'name';
	if (peer !== peerAddress)
		{
		addClass(newElement, "other-bubble");
		}
	
	if (name === "(none)")
		{
		name = "(?)";
		}
	
	let bubbleContents = "<div class='text'>";
	bubbleContents += "<p class='" + nameClass + "'>" + name;
	bubbleContents  += "<span class='timestamp'>" + timestamp + "</span>";
	bubbleContents  += "</p>";
	
	// With each line in a <p>, copying a multi-line message
	// doubles the newlines. Using a table row for each message line
	// doesn't do that. Weird.
	let finalMessage = "<div class='message'><table><tr><td>";
	actualMessage = actualMessage.replace(/_NL_/g, "</td></tr><tr><td>");
	
	actualMessage = actualMessage.replace(/_HAT_/g, '^');
	
	finalMessage += actualMessage;
	finalMessage += "</td></tr></table></div>";
	
	bubbleContents += finalMessage;
	bubbleContents += "</div>";
	bubbleContents += "<div class='bubble-arrow'></div>";
		
	newElement.innerHTML = bubbleContents;
	
	// Set background color of bubble according to last three digits of peer address.
	if (peer !== peerAddress)
		{
		let rgbBackColor = colorForPeerAddress(peer);
		// Reduce opacity a bit to avoid bleeding eyes.
		rgbBackColor = rgbBackColor.replace(/\)/, ', 0.2)');
		newElement.style.background = rgbBackColor;
		}
}

function saveMessage(message) {
	showSpinner();
	
	// TEST ONLY
	//console.log("JS saving |" + message + "|");
	
	let request = new XMLHttpRequest();
	request.open('post', 'http://' + theHost + ':' + thePort + '/', true);

		request.onload = function() {
		if (request.status >= 200 && request.status < 400)
			{
			// Success! Probably.
			hideSpinner();
			}
		else
			{
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(errorID);
			e1.innerHTML = 'Error, server reached but it returned an error when trying to save message!';
			hideSpinner();
			}
	};

	request.onerror = function() {
		// There was a connection error of some sort
		let e1 = document.getElementById(errorID);
		e1.innerHTML = 'Connection error! Could not reach server when trying to save message.';
		hideSpinner();
	};

	message = encodeURIComponent(message);
	request.send('data=' + message);
}

// Retrieve our ip address and refresh display.
function getChatStarted() {
	showSpinner();
	let request = new XMLHttpRequest();
	request.open('get', 'http://' + theHost + ':' + thePort + '/?req=peer', true);

	request.onload = function() {
		if (request.status >= 200 && request.status < 400)
			{
			// Success!
			peerAddress = decodeURIComponent(request.responseText);
			messageHeight = document.getElementById("messageid").clientHeight;
			refreshChatDisplay();
			}
		else
			{
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(errorID);
			e1.innerHTML = 'Error, server reached but it returned an error when trying to get peer address!';
			hideSpinner();
			}
	};

	request.onerror = function() {
		// There was a connection error of some sort
		let e1 = document.getElementById(errorID);
		e1.innerHTML = 'Connection error! Could not reach server when trying to get peer address.';
		hideSpinner();
	};

	request.send();
}

function refreshChatDisplay() {
	getMessages();
	hideSpinner();
}

function getMessages() {
	showSpinner();
	let request = new XMLHttpRequest();
	request.open('get', 'http://' + theHost + ':' + thePort + '/?req=getMessages', true);

	request.onload = function() {
		if (request.status >= 200 && request.status < 400)
			{
			// Success!
			hideSpinner();
			
			let theText = decodeURIComponent(request.responseText);
			// No messages? Nothing to do.
			if (theText === '(none)')
				{
				return;
				}

			let myMessageArr = theText.split("_MS_");
			for (let i = 0; i < myMessageArr.length; ++i)
				{
				breakUpAndAddToDisplayedMessageList(myMessageArr[i]);
				}
			}
		else
			{
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(errorID);
			e1.innerHTML = 'Error, server reached but it returned an error when trying to get all messages!';
			hideSpinner();
			}
	};

	request.onerror = function() {
		// There was a connection error of some sort
		let e1 = document.getElementById(errorID);
		e1.innerHTML = 'Connection error! Could not reach server when trying to get all messages.';
		hideSpinner();
	};

	request.send();
}

function autoGrow (oField) {
  if (oField.scrollHeight > oField.clientHeight)
	{
    oField.style.height = oField.scrollHeight + "px";
	}
}

function resetMessageArea() {
	let textMessageArea = document.getElementById("messageid");
	textMessageArea.value = "";
	textMessageArea.style.height = messageHeight + "px";
}

// Adjust main content height to show/hide scroll bars.
function doResize() {
	var el = document.getElementById('scrollAdjustedHeight');
	
	var pos = getPosition(el);
	var windowHeight = window.innerHeight;
	var elHeight = windowHeight - pos.y;
	el.style.height = elHeight - 4 + "px";
	
	var windowWidth = window.innerWidth;
	el.style.width = windowWidth - 4 + "px";
	}

// Show messages in newest-first or oldest-first order.
// Default is newest first.
function toggleNewOld() {
	let val = document.querySelector('input[name="newOld"]:checked').value;
	if (val.indexOf("new") < 0)
		{
		newestFirst = false;
		}
	else
		{
		newestFirst = true;
		}
	
	displayMessagesInOrder();
}

function displayMessagesInOrder() {
	deleteAllDisplayedMessages();
	getMessages();
}

function deleteAllDisplayedMessages() {
	let parent = document.getElementById(messagesID);
	if (parent !== null)
		{
		// Delete all children.
		while (parent.lastChild)
			{
			parent.removeChild(parent.lastChild);
			}
		}
}

// Colour for message, to distinguish different senders slightly.
function colorForPeerAddress(peer) {
	const regex = /\d+\.\d+\.\d+\.(\d+)/;
	const found = peer.match(regex);
	if (found[1])
		{
		return(rgbForInt[found[1]]);
		}
	else
		{
		return("rgb(255, 255, 255)");
		}
	}

// Colors for senders, to help distinguish them.
const rgbForInt = [
"rgb(253, 253, 253)",
"rgb(127, 232, 148)",
"rgb(190, 211, 190)",
"rgb(169, 169, 148)",
"rgb(127, 127, 169)",
"rgb(148, 127, 169)",
"rgb(148, 253, 232)",
"rgb(169, 253, 127)",
"rgb(169, 232, 127)",
"rgb(232, 148, 169)",
"rgb(190, 148, 190)",
"rgb(169, 190, 211)",
"rgb(148, 211, 211)",
"rgb(211, 232, 169)",
"rgb(211, 253, 253)",
"rgb(148, 127, 253)",
"rgb(148, 169, 127)",
"rgb(127, 190, 169)",
"rgb(169, 148, 169)",
"rgb(190, 127, 211)",
"rgb(169, 127, 211)",
"rgb(211, 211, 148)",
"rgb(148, 148, 211)",
"rgb(190, 127, 232)",
"rgb(232, 127, 190)",
"rgb(169, 127, 169)",
"rgb(211, 253, 253)",
"rgb(169, 148, 190)",
"rgb(169, 190, 127)",
"rgb(127, 190, 169)",
"rgb(148, 169, 211)",
"rgb(148, 232, 127)",
"rgb(148, 169, 190)",
"rgb(190, 127, 253)",
"rgb(190, 169, 211)",
"rgb(169, 253, 169)",
"rgb(211, 190, 232)",
"rgb(127, 190, 190)",
"rgb(148, 211, 232)",
"rgb(190, 127, 232)",
"rgb(148, 148, 127)",
"rgb(190, 232, 190)",
"rgb(127, 127, 169)",
"rgb(211, 253, 253)",
"rgb(169, 127, 169)",
"rgb(148, 127, 253)",
"rgb(169, 148, 253)",
"rgb(190, 169, 211)",
"rgb(148, 148, 232)",
"rgb(148, 127, 253)",
"rgb(127, 127, 253)",
"rgb(169, 127, 211)",
"rgb(190, 127, 232)",
"rgb(169, 148, 190)",
"rgb(127, 211, 253)",
"rgb(169, 253, 232)",
"rgb(148, 148, 253)",
"rgb(148, 253, 232)",
"rgb(169, 190, 127)",
"rgb(190, 232, 190)",
"rgb(211, 211, 169)",
"rgb(190, 127, 190)",
"rgb(127, 190, 127)",
"rgb(169, 127, 127)",
"rgb(169, 232, 127)",
"rgb(127, 190, 211)",
"rgb(169, 211, 190)",
"rgb(190, 127, 232)",
"rgb(148, 253, 211)",
"rgb(127, 127, 232)",
"rgb(148, 211, 211)",
"rgb(211, 169, 232)",
"rgb(169, 232, 169)",
"rgb(148, 148, 148)",
"rgb(127, 253, 148)",
"rgb(211, 211, 169)",
"rgb(127, 148, 253)",
"rgb(169, 232, 148)",
"rgb(148, 190, 211)",
"rgb(127, 190, 127)",
"rgb(211, 232, 232)",
"rgb(169, 253, 148)",
"rgb(148, 232, 211)",
"rgb(190, 232, 190)",
"rgb(127, 253, 127)",
"rgb(190, 169, 211)",
"rgb(169, 211, 190)",
"rgb(190, 148, 190)",
"rgb(190, 127, 253)",
"rgb(148, 232, 169)",
"rgb(211, 127, 190)",
"rgb(148, 169, 127)",
"rgb(211, 211, 148)",
"rgb(169, 211, 190)",
"rgb(148, 211, 211)",
"rgb(169, 127, 169)",
"rgb(127, 127, 232)",
"rgb(190, 190, 148)",
"rgb(148, 148, 190)",
"rgb(211, 127, 190)",
"rgb(190, 211, 211)",
"rgb(148, 190, 190)",
"rgb(190, 127, 253)",
"rgb(148, 190, 232)",
"rgb(169, 232, 148)",
"rgb(127, 148, 211)",
"rgb(232, 127, 169)",
"rgb(169, 127, 211)",
"rgb(190, 232, 127)",
"rgb(148, 148, 169)",
"rgb(148, 148, 127)",
"rgb(127, 169, 232)",
"rgb(190, 211, 211)",
"rgb(148, 211, 253)",
"rgb(169, 148, 148)",
"rgb(127, 169, 232)",
"rgb(169, 253, 127)",
"rgb(190, 211, 190)",
"rgb(169, 169, 211)",
"rgb(148, 190, 148)",
"rgb(211, 232, 232)",
"rgb(127, 190, 211)",
"rgb(127, 127, 253)",
"rgb(211, 127, 190)",
"rgb(211, 169, 211)",
"rgb(169, 211, 232)",
"rgb(148, 127, 148)",
"rgb(211, 169, 232)",
"rgb(169, 253, 169)",
"rgb(169, 148, 211)",
"rgb(148, 211, 211)",
"rgb(211, 190, 127)",
"rgb(148, 211, 190)",
"rgb(169, 169, 253)",
"rgb(211, 169, 253)",
"rgb(211, 232, 127)",
"rgb(211, 127, 190)",
"rgb(211, 148, 148)",
"rgb(148, 253, 211)",
"rgb(148, 148, 127)",
"rgb(127, 253, 169)",
"rgb(169, 253, 127)",
"rgb(169, 148, 232)",
"rgb(190, 211, 211)",
"rgb(127, 169, 253)",
"rgb(148, 232, 169)",
"rgb(211, 211, 169)",
"rgb(190, 148, 232)",
"rgb(127, 127, 253)",
"rgb(148, 253, 232)",
"rgb(190, 169, 211)",
"rgb(169, 148, 253)",
"rgb(190, 148, 232)",
"rgb(127, 127, 211)",
"rgb(190, 211, 211)",
"rgb(169, 169, 211)",
"rgb(148, 169, 190)",
"rgb(190, 253, 127)",
"rgb(169, 211, 232)",
"rgb(127, 190, 127)",
"rgb(148, 211, 169)",
"rgb(190, 232, 127)",
"rgb(127, 190, 127)",
"rgb(211, 211, 148)",
"rgb(211, 148, 148)",
"rgb(169, 211, 190)",
"rgb(169, 190, 211)",
"rgb(169, 232, 148)",
"rgb(127, 169, 232)",
"rgb(148, 211, 253)",
"rgb(127, 127, 190)",
"rgb(148, 253, 232)",
"rgb(190, 169, 211)",
"rgb(169, 253, 190)",
"rgb(148, 253, 190)",
"rgb(148, 253, 211)",
"rgb(211, 190, 232)",
"rgb(127, 148, 232)",
"rgb(148, 190, 148)",
"rgb(148, 253, 211)",
"rgb(148, 127, 169)",
"rgb(127, 148, 232)",
"rgb(169, 253, 127)",
"rgb(148, 169, 127)",
"rgb(148, 127, 148)",
"rgb(211, 169, 253)",
"rgb(127, 148, 211)",
"rgb(148, 190, 148)",
"rgb(169, 127, 232)",
"rgb(190, 148, 232)",
"rgb(148, 169, 190)",
"rgb(211, 253, 211)",
"rgb(148, 232, 211)",
"rgb(169, 211, 190)",
"rgb(127, 253, 169)",
"rgb(211, 148, 148)",
"rgb(148, 190, 211)",
"rgb(190, 232, 190)",
"rgb(127, 232, 232)",
"rgb(190, 127, 232)",
"rgb(190, 127, 232)",
"rgb(127, 148, 253)",
"rgb(148, 148, 169)",
"rgb(232, 127, 190)",
"rgb(190, 169, 211)",
"rgb(211, 190, 211)",
"rgb(211, 253, 253)",
"rgb(148, 190, 148)",
"rgb(127, 253, 127)",
"rgb(148, 253, 232)",
"rgb(190, 148, 190)",
"rgb(148, 232, 127)",
"rgb(127, 211, 253)",
"rgb(211, 232, 148)",
"rgb(148, 190, 211)",
"rgb(190, 211, 211)",
"rgb(148, 211, 232)",
"rgb(169, 253, 232)",
"rgb(127, 190, 190)",
"rgb(232, 127, 190)",
"rgb(211, 232, 127)",
"rgb(148, 190, 211)",
"rgb(211, 190, 211)",
"rgb(190, 127, 169)",
"rgb(169, 211, 253)",
"rgb(211, 190, 127)",
"rgb(190, 232, 232)",
"rgb(211, 169, 253)",
"rgb(190, 211, 211)",
"rgb(148, 190, 190)",
"rgb(148, 232, 211)",
"rgb(190, 169, 190)",
"rgb(169, 127, 232)",
"rgb(148, 127, 253)",
"rgb(211, 127, 190)",
"rgb(211, 253, 253)",
"rgb(169, 169, 211)",
"rgb(148, 148, 148)",
"rgb(232, 127, 211)",
"rgb(148, 253, 211)",
"rgb(127, 232, 169)",
"rgb(211, 253, 211)",
"rgb(190, 253, 211)",
"rgb(127, 169, 232)",
"rgb(148, 211, 253)",
"rgb(169, 253, 148)",
"rgb(190, 211, 211)",
"rgb(169, 190, 253)",
"rgb(169, 169, 253)",
"rgb(232, 148, 169)",
"rgb(127, 190, 127)",
"rgb(169, 169, 253)",
"rgb(127, 253, 148)",
"rgb(169, 232, 169)",
"rgb(190, 169, 190)",
"rgb(127, 127, 232)"
];

window.addEventListener("resize", doResize);
window.addEventListener("load", doResize);
window.addEventListener('wsinit', function (e) { getChatStarted(); }, false);