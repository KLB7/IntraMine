// todoGetPutData.js: used by intramine_todolist.js to:
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
function getToDoData() {
	showSpinner();
	let request = new XMLHttpRequest();
	request.open('get', 'http://' + theHost + ':' + thePort + '/?req=getData', true);

	request.onload = function() {
		if (request.status >= 200 && request.status < 400)
			{
			// Success!
			hideSpinner();

			let theText = decodeURIComponent(request.responseText);
			
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
	};

	request.onerror = function() {
		// There was a connection error of some sort
		let e1 = document.getElementById(theErrorID);
		e1.innerHTML = 'Connection error!';
		hideSpinner();
	};

	request.send();
}

// Periodically retrieve date stamp on todo data file. If time stamp has changed, and our
// masterDateStamp has already been set, reload the todo list data. Always set
// masterDateStamp if sucessful.
// See also intramine_todolist.pl#DataModDate().
function getModificationDateStamp() {
	let request = new XMLHttpRequest();
	request.open('get', 'http://' + theHost + ':' + thePort + '/?req=getModDate', true);

	request.onload = function() {
		if (request.status >= 200 && request.status < 400)
			{
			// Success! Probably.
			let responseTxt = request.responseText;
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
	};

	request.onerror = function() {
		// There was a connection error of some sort
		let e1 = document.getElementById(theErrorID);
		e1.innerHTML = 'Connection error in getModificationDateStamp!';
	};

	request.send();
}

// POST ToDo data with a "data" request, handled by
// intramine_todolist.pl#PutData().
function putData(rawData) {
	showSpinner();
	
	// Send todochanged out to all WebSockets clients.
	// The web clients will flash the ToDo item and show
	// the count of overdue items N, as ToDo [N].
	overdueCount = getOverDueCount(rawData);
	wsSendMessage("todochanged " + overdueCount);
		
	let theData = JSON.stringify(rawData);
	
	let request = new XMLHttpRequest();
	request.open('post', 'http://' + theHost + ':' + thePort + '/', true);

	request.onload = function() {
		if (request.status >= 200 && request.status < 400)
			{
			// Success! Probably.
			hideSpinner();
			
			// Trigger reload, and ToDo flash in the nav bar
			// (see todoFlash.js). Also send an "activity" message.
			wsSendMessage("todoflash");
			wsSendMessage('activity ' + shortServerName + ' ' + ourSSListeningPort);

			let responseTxt = request.responseText;
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
	};

	request.onerror = function() {
		// There was a connection error of some sort
		let e1 = document.getElementById(theErrorID);
		e1.innerHTML = 'Connection error!';
		hideSpinner();
	};

	
	theData = theData.replace(/%/g, "%25");
	theData = encodeURIComponent(theData);
	theData = encodeURIComponent(theData); // sic

	request.send('data=' + theData);
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
	
	let options = {};
	options.format = 'yyyy/mm/dd';
	let dateHolder = document.getElementById("datepicker");
	let datePicker = new Datepicker(dateHolder);
	//let datePicker = new Datepicker(dateHolder, options);
	
	// for the jQuery v1 version: $('#datepicker').datepicker({ dateFormat: 'yy/mm/dd'});
	// was 	$("#datepicker").datepicker();
	//$("#datepicker").datepicker("option", "dateFormat", "yy/mm/dd");
	
	// TEMP out

	//$(".task-container").droppable();
	//$(".todo-task").draggable({
	//	revert : "valid",
	//	revertDuration : 200
	//});
	//todo.init(rawData, true);
	
	
	todoNew(rawData);

	overdueCount = 0;
	observeTasks();

	// Trigger the observer on load.
	let pending = document.getElementById('pending');
	let color = pending.style.color;
	pending.style.color = 'black';
	pending.style.color = color;
	let inprog = document.getElementById('inProgress');
	color = inprog.style.color;
	inprog.style.color = 'black';
	inprog.style.color = color;

	// Periodically (and frequently) check for change to mod date on the data file.
	// Retired in favour of Server-Sent Events, see todoEvents.js.
//	window.setInterval(function() {
//		getModificationDateStamp();
//	}, 1000);
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

// Much ado about turning overdue items red (if not even started)
// or yellow (if started but not done).
function observeTasks() {
	let observer = new MutationObserver(function(mutations) {
		let today = new Date();

		let currentOverdueCount = 0;
		let el = document.getElementById('pending');
		currentOverdueCount += numOverdue(el, today);
		colorByDaysToOverdue(el, today, '#FDEDEC'); // light red
		el = document.getElementById('inProgress');
		colorByDaysToOverdue(el, today, '#FEF9E7'); // light yellow

		if (overdueCount != currentOverdueCount)
			{
			overdueCount = currentOverdueCount;
			signalOverdueChanged();
			resetOverdueInNav(overdueCount);
			}

		doResize();
	});

	let observerConfig = {
		// characterData: true,
		attributes : true,
		childList : true
	};

	let targetNode = document.getElementById('pending');
	observer.observe(targetNode, observerConfig);
	targetNode = document.getElementById('inProgress');
	observer.observe(targetNode, observerConfig);
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

function signalOverdueChanged() {
	let request = new XMLHttpRequest();
	request.open('get', 'http://' + theHost + ':' + theMainPort + '/?signal=todoCount&count='
			+ overdueCount + '&name=PageServers', true);

	request.onload = function() {
		if (request.status >= 200 && request.status < 400)
			{
			// Success!
			}
		else
			{
			// We reached our target server, but it returned an error
			// let e1 = document.getElementById(theErrorID);
			// e1.innerHTML = 'Error, server reached but it returned an error!';
			}
	};

	request.onerror = function() {
		// There was a connection error of some sort
		// let e1 = document.getElementById(theErrorID);
		// e1.innerHTML = 'Connection error!';
	};

	request.send();
}
