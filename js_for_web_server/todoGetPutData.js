// todoGetPutData.js:
// get/put todo items as JSON
// signal the overdue count
// resize elements (to show/hide scrollbar, mainly)
// and start the ToDo list up on "load"

window.addEventListener("load", getDataAndStartToDoList);
window.addEventListener("resize", doResize);

let overdueCount = 0;
let masterDateStamp = '';
let toDoIsStarted = false;
let theErrorID = "loadError";

function getDataAndStartToDoList() {
	getToDoData();
	doResize();
}

// Call back to intramine_todolist.pl with "req=getData". The %RequestAction registered there
// in turn calls intramine_todolist.pl#GetData().
async function getToDoData() {
	showSpinner();

	try {
		let theAction = 'http://' + theHost + ':' + thePort + '/?req=getData';
		const response = await fetch(theAction);
		if (response.ok)
			{
			// Success!
			hideSpinner();

			let text = await response.text();
			let theText = decodeURIComponent(text);
			
			todoNew(theText, !toDoIsStarted);
			toDoIsStarted = true;			
			}
		else
			{
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(theErrorID);
			e1.innerHTML = 'Error, server reached but it returned an error!';
			hideSpinner();
			}
	}
	catch(error) {
		// There was a connection error of some sort
		let e1 = document.getElementById(theErrorID);
		e1.innerHTML = 'Connection error!';
		hideSpinner();
	}
}

// Periodically retrieve date stamp on todo data file. If time stamp has changed, and our
// masterDateStamp has already been set, reload the todo list data. Always set
// masterDateStamp if sucessful.
// See also intramine_todolist.pl#DataModDate().
async function getModificationDateStamp() {
	try {
		let theAction = 'http://' + theHost + ':' + thePort + '/?req=getModDate';
		const response = await fetch(theAction);
		if (response.ok)
			{
			let responseTxt = await response.text();
			let newMasterDateStamp = responseTxt;
			if (masterDateStamp !== newMasterDateStamp)
				{
				if (masterDateStamp !== '')
					{
					getToDoData();
					}
				masterDateStamp = newMasterDateStamp;
				}
			let e1 = document.getElementById(theErrorID);
			e1.innerHTML = '';
			}
		else
			{
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(theErrorID);
			e1.innerHTML = 'Error, server did not return a data modification date!';
			}
	}
	catch(error) {
		// There was a connection error of some sort
		let e1 = document.getElementById(theErrorID);
		e1.innerHTML = 'Connection error in getModificationDateStamp!';
	}
}

// POST ToDo data with a "data" request, handled by
// intramine_todolist.pl#PutData().
async function putData(rawData) {
	showSpinner();

	try {
		let theAction = 'http://' + theHost + ':' + thePort + '/';
		let theData = JSON.stringify(rawData);
		theData = theData.replace(/%/g, "%25");
		theData = encodeURIComponent(theData);
		theData = encodeURIComponent(theData); // sic

		const response = await fetch(theAction, {
			method: 'POST',
			headers: {
			'Content-Type': 'application/json',
		  	},
		  	body: 'data=' + theData,
		  	});
		
		if (response.ok)
		  	{
			// Success! Probably.
			hideSpinner();
			
			// Send todochanged out to all WebSockets clients.
			// The web clients will flash the ToDo item and show
			// the count of overdue items N, as ToDo [N].
			overdueCount = getOverDueCount(rawData);
			wsSendMessage("todochanged " + overdueCount);
			
			// Trigger reload, and ToDo flash in the nav bar
			// (see todoFlash.js). Also publish an "activity" message.
			wsSendMessage("todoflash");
			wsSendMessage('PUBLISH__TS_activity_TE_' + 'activity ' + shortServerName + ' ' + ourSSListeningPort);

			//let responseTxt = request.responseText;
			let responseTxt = await response.text();
			let errorMatch = /^FILE/.exec(responseTxt);
			if (errorMatch === null)
				{
				masterDateStamp = responseTxt;
				}
			else
				{
				let e1 = document.getElementById(theErrorID);
				e1.innerHTML = responseTxt;
				}
		 	}
		else
			{
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(theErrorID);
			e1.innerHTML = 'Error, server reached but it returned an error!';
			hideSpinner();
			}
	}
	catch(error) {
		// There was a connection error of some sort
		let e1 = document.getElementById(theErrorID);
		e1.innerHTML = 'Connection error!';
		hideSpinner();
	}
}

async function archiveOneItem(rawData) {
	try {
		let theAction = 'http://' + theHost + ':' + thePort + '/';
		let theData = JSON.stringify(rawData);
		theData = theData.replace(/%/g, "%25");
		theData = encodeURIComponent(theData);
		theData = encodeURIComponent(theData); // sic

		const response = await fetch(theAction, {
			method: 'POST',
			headers: {
			'Content-Type': 'application/json',
		  	},
		  	body: 'saveToArchive=' + theData,
		  	});
		
		if (response.ok)
		  	{
			// Success! Probably.
		 	}
		else
			{
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(theErrorID);
			e1.innerHTML = 'Archiving error, server reached but it returned an error!';
			}
	}
	catch(error) {
		// There was a connection error of some sort
		let e1 = document.getElementById(theErrorID);
		e1.innerHTML = 'Connection error while archiving!';
	}
}

function getOverDueCount(rawData) {
	let count = 0;
	let objArray = rawData.items;
	if (!Array.isArray(objArray))
		{
		return(count);
		}
	
	let now = new Date();
	let today = YYYYMMDDforDate(now);
	
	for (let i = 0; i < objArray.length; ++i)
		{
		let date = objArray[i].date;
		let code = objArray[i].code;
		if (code === "1" && date != "")
			{
			date = date.replace(/\//g, '');
			let dateNum = parseInt(date, 10);
			if (dateNum <= today)
				{
				++count;
				}
			}
		}
	
	return(count);
}

function YYYYMMDDforDate(date) {
	let day = date.getDate();
	let twoDDay = ("0" + day).slice(-2);
	let month = date.getMonth() + 1;
	let twoDMonth = ("0" + month).slice(-2);
	let year = date.getFullYear();
	
	let result = parseInt("" + year + twoDMonth + twoDDay, 10);
	return(result);
}

// Called after getting the ToDo data, init the ToDo display.
function startToDoList(rawData) {
		
	todoNew(rawData);

	overdueCount = 0;
}

function daysBetween(one, another) {
	let oneDay = 24 * 60 * 60 * 1000; // hours*minutes*seconds*milliseconds
	let twelveHours = 12 * 60 * 60 * 1000; // don't ask me why
	return Math.round((one - another + twelveHours) / oneDay);
}

// Count up the number of items due today or before.
function numOverdue(el, today) {
	let dates = el.getElementsByClassName("task-date");
	let currentOverdueCount = 0;
	for (let i = 0; i < dates.length; i++)
		{
		let dateDiv = dates[i];
		let rawDate = dateDiv.innerHTML;
		let arrayMatch = /^(\d\d\d\d)\/(\d\d)\/(\d\d)/.exec(rawDate);
		if (arrayMatch != null)
			{
			let yyyy = arrayMatch[1];
			let mm = arrayMatch[2];
			let dd = arrayMatch[3];
			let thisDate = new Date(yyyy, mm - 1, dd);
			let numBetween = daysBetween(thisDate, today);
			if (numBetween <= 0)
				{
				++currentOverdueCount;
				}
			}
		}

	return (currentOverdueCount);
}

// Get overdue count in navigation bar, or 0.
function oldNavTextCount(text) {
	let oldCount = 0;
	let firstBracketPos = text.indexOf("[");

	if (firstBracketPos > 0)
		{
		let lastBracketPos = text.indexOf("]");
		if (lastBracketPos > firstBracketPos + 1)
			{
			let countStr = text.substring(firstBracketPos + 1, lastBracketPos);
			oldCount = parseInt(countStr, 10);
			}
		}
		
	return(oldCount);
}

// Make up new "ToDo" nav item text with correct count.
function newNavTextForCount(text, count) {
	let newText = "";
	let firstBracketPos = text.indexOf("[");
	
	if (firstBracketPos > 0)
		{
		let navName = text.substring(0, firstBracketPos);
		if (count > 0)
			{
			newText = navName + "[" + count + "]";
			}
		else
			{
			let navName = text.substring(0, firstBracketPos - 1);
			newText = navName;
			}
		}
	else
		{
		if (count > 0)
			{
			newText = text + " [" + count + "]";
			}
		else // should not happen
			{
				newText = text;
			}
		}
		
	return(newText);
}

// Set "ToDo" nav item's overdue count, if it has changed.
function resetOverdueInNav(count) {
	let navbar = document.getElementById('nav');
	if (navbar === null)
		{
		return;
		}

	let aTags = navbar.getElementsByTagName("a");
    let searchText = "ToDo";
    let todoElem = null;
	
    for (let i = 0; i < aTags.length; i++)
        {
		if (aTags[i].textContent.indexOf(searchText) == 0)
            {
            todoElem = aTags[i];
            break;
            }
        }
	
	if (todoElem !== null)
		{
		let text = todoElem.textContent;
		let oldCount = oldNavTextCount(text);
		if (count !== oldCount)
			{
			let newText = newNavTextForCount(text, count);
			todoElem.textContent = newText;
			}
		}
}


// Put a color on items due today or before.
function colorByDaysToOverdue(el, today, overdueColor) {
	let dates = el.getElementsByClassName("task-date");
	for (let i = 0; i < dates.length; i++)
		{
		let dateDiv = dates[i];
		let rawDate = dateDiv.innerHTML;
		let arrayMatch = /^(\d\d\d\d)\/(\d\d)\/(\d\d)/.exec(rawDate);
		if (arrayMatch != null)
			{
			let yyyy = arrayMatch[1];
			let mm = arrayMatch[2];
			let dd = arrayMatch[3];
			let thisDate = new Date(yyyy, mm - 1, dd);
			let numBetween = daysBetween(thisDate, today);
			if (numBetween <= 0)
				{
				dateDiv.parentNode.style.backgroundColor = overdueColor;
				}
			else
				{
				dateDiv.parentNode.style.backgroundColor = '#EAFAF1'; // light greenish
				}
			}
		else
			{
			dateDiv.parentNode.style.backgroundColor = 'White';
			}
		}
}

// Once upon a time I thought it would be a Bad Idea to allow a vertical scrollbar
// in the ToDo view, since that would encourage having Too Many Items.
// But when the caffeine wore off a bit I realized I ain'tcha momma. So have a scroller
// but try not to need it: this is Kanban.
function doResize() {
	let el = document.getElementById(contentID); // default 'scrollAdjustedHeight
	let pos = getPosition(el);
	let windowHeight = window.innerHeight;
	el.style.height = ((windowHeight - pos.y - 10) / windowHeight) * 100 + "%";

	let windowWidth = window.innerWidth;
	el.style.width = windowWidth - 4 + "px";
}

async function signalOverdueChanged() {
	try {
		let theAction = 'http://' + theHost + ':' + theMainPort + '/?signal=todoCount&count='
		+ overdueCount + '&name=PageServers';
		const response = await fetch(theAction);
		if (response.ok)
			{
			// Success!
			}
		// else no big deal.
	}
	catch(error) {
		// Also no big deal.
	}
}
