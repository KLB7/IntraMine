/**
 * status.js: for intramine_status.pl.
 * Periodically call back to Main to get a server status table,
 * manage Start/Stop/Restart and Add buttons,
 * flash server lights in response to Server-Sent Events (see also statusEvents.js).
 */

window.addEventListener("load", doResize);
window.addEventListener("resize", doResize);

let normalStatusRefreshMsecs = statusRefreshMilliseconds;

// Sort order for page and background tables. Port is column 2.
let pageSortColumn = 2;
let backgroundSortColumn = 2;

function hasClass(el, className) {
	if (el === null || el.nodeName === "#TEXT" || el.nodeName === "#text")
		{
		return false;
		}
	if (el.classList)
		return el.classList.contains(className)
	else
	return(typeof el.className !== 'undefined' && !!el.className.match(new RegExp('(\\s|^)' + className + '(\\s|$)')));
}

function addClass(el, className) {
	if (el !== null)
		{
		if (el.classList)
			el.classList.add(className)
		else if (!hasClass(el, className))
			el.className += " " + className
		}
}

function removeClass(el, className) {
	if (el !== null)
		{
		if (el.classList)
			el.classList.remove(className)
		else if (hasClass(el, className))
			{
			let reg = new RegExp('(\\s|^)' + className + '(\\s|$)')
			el.className = el.className.replace(reg, ' ')
			}
		}
}

function removeAllClasses(el) {
	if (el !== null)
		{
		if (el.classList)
			el.classList = "";
		else
			el.className = "";
		}
}

// Call fn when ready.
function ready(fn) {
	if (document.readyState != 'loading')
		{
		fn();
		}
	else
		{
		document.addEventListener('DOMContentLoaded', fn);
		}
}

// 'req=filestatus' XMLHttpRequest() request to this server invokes
// intramine_status.pl#FileStatusHTML()
// which returns a list of changed files. Followed by a call to
// refreshServerStatus() which grabs a table showing server status
// from the main server. Called every statusRefreshMilliseconds (which is initially set
// in intramine_status.pl#StatusPage()).
function refreshStatus() {
	showSpinner();
	let e1 = document.getElementById(errorID);
	e1.innerHTML = '&nbsp;';
	let request = new XMLHttpRequest();
	request.open('get', 'http://' + theHost + ':' + thePort + '/?req=filestatus', true);

	request.onload = function() {
		if (request.status >= 200 && request.status < 400)
			{
			// Success
			let e1 = document.getElementById(errorID);
			e1.innerHTML = '&nbsp;';
			let resp = request.responseText;
			e1 = document.getElementById(fileContentID);
			e1.innerHTML = resp;
			// Update status of all IntraMine servers.
			refreshServerStatus(true);
			}
		else
			{
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(errorID);
			e1.innerHTML = '<p>Error, status request failed!</p>';
			hideSpinner();
			}
	};

	request.onerror = function() {
		// There was a connection error of some sort
		let e1 = document.getElementById(errorID);
		e1.innerHTML = '<p>Connection error!</p>';
		hideSpinner();
	};

	request.send();
}

// Request update status of all IntraMine servers from main server. And set a Timeout
// to call refreshStatus().
function refreshServerStatus(doItRepeatedly) {
	let e1 = document.getElementById(errorID);
	e1.innerHTML = '&nbsp;';
	let request = new XMLHttpRequest();
	request.open('get', 'http://' + theHost + ':' + theMainPort + '/?req=serverstatus', true);

	request.onload = function() {
		if (request.status >= 200 && request.status < 400)
			{
			// Success
			let e1 = document.getElementById(errorID);
			e1.innerHTML = '&nbsp;';
			let resp = request.responseText;
			e1 = document.getElementById(serverStatusContentID);
			e1.innerHTML = resp;

			// Check more often if any server status is 'STARTING UP'
			if (resp.indexOf('STARTING UP') > 0)
				{
				statusRefreshMilliseconds = 1000;
				}
			else
				{
				statusRefreshMilliseconds = normalStatusRefreshMsecs;
				}

			// Re-sort page and background server tables after refresh.
			sortTable(pageServerTableId, pageSortColumn);
			sortTable(backgroundServerTableId, backgroundSortColumn);

			// Explicit doResize, since neither "load" nor "resize" events are triggered here.
			doResize();
			hideSpinner();

			// Add buttons to stop/start/restart individual servers.
			addStartStopRefreshButtons();

			// Do it all again every now and then (default 30 seconds).
			if (doItRepeatedly)
				{
				setTimeout(function() {
					refreshStatus();
				}, statusRefreshMilliseconds);
				}

			}
		else
			{
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(errorID);
			e1.innerHTML = '<p>Error, server status request failed!</p>';
			hideSpinner();
			}
	};

	request.onerror = function() {
		// There was a connection error of some sort
		let e1 = document.getElementById(errorID);
		e1.innerHTML = '<p>Connection error while contacting main server!</p>';
		hideSpinner();
	};

	request.send();
}

// Add Start/Stop/Restart buttons, to "Page" (non-background) servers.
function addStartStopRefreshButtons() {
	let statusTable = document.getElementById(pageServerTableId);
	if (statusTable === null)
		{
		return;
		}
	
	for (let i = 0, row; row = statusTable.rows[i]; ++i)
		{
		let serverStatus = '';
		let portNumber = '';
		for (let j = 0, col; col = row.cells[j]; ++j)
			{
			for (let k = 0; k < col.children.length; ++k)
				{
				let child = col.children[k];
				let cname = child.nodeName;
				if (cname === 'SPAN')
					{
					if (hasClass(child, statusButtonClass))
						{
						let isUp = (serverStatus === 'UP') ? true : false;
						let isStarting = (serverStatus === 'STARTING UP') ? true : false;
						let isUpOrStarting = (isUp || isStarting);
						let startDisable = (isUpOrStarting) ? ' disabled' : '';
						let stopDisable = (isUp) ? '' : ' disabled';
						let restartDisable = (isUp) ? '' : ' disabled';
						let startButton =
								"<button type='button' onclick='startServer(" + portNumber
										+ "); return false;'" + startDisable + ">Start</button>";
						let stopButton =
								"<button type='button' onclick='stopServer(" + portNumber
										+ "); return false;'" + stopDisable + ">Stop</button>";
						let restartButton =
								"<button type='button' onclick='restartServer(" + portNumber
										+ "); return false;'" + restartDisable
										+ ">Restart</button>";
						child.innerHTML =
								startButton + '&nbsp;' + stopButton + '&nbsp;' + restartButton;
						}
					else if (hasClass(child, portHolderClass)) // port number
						{
						portNumber = col.innerText;
						}
					}
				else if (cname === 'DIV' && hasClass(child, 'divAlignCenter')) // Status cell, comes before buttons cell
					{
					let secondDiv = child.getElementsByTagName('div').item(1);
					serverStatus = secondDiv.innerText;
					serverStatus = serverStatus.replace(/^\W+/, '');
					}
				}
			}
		}
}

function startServer(port) {
	console.log("Start for server " + port + " requested.");
	startStopRestartSubmit('start_one_specific_server', port);
}

function stopServer(port) {
	console.log("Stop for server " + port + " requested.");
	startStopRestartSubmit('stop_one_specific_server', port);
}

function restartServer(port) {
	console.log("Restart for server " + port + " requested.");
	startStopRestartSubmit('restart_one_specific_server', port);
}

function doResize() {
	let el = document.getElementById("scrollAdjustedHeight");

	let pos = getPosition(el);
	let windowHeight = window.innerHeight;
	let elHeight = windowHeight - pos.y - 10;
	let newHeightPC = (elHeight / windowHeight) * 100;
	el.style.height = newHeightPC + "%";

	let windowWidth = window.innerWidth;
	el.style.width = windowWidth - 4 + "px";
}

// Request the little "Add on page server" form and poke it into the "AddServer" element.
function loadAddServerForm() {
	let request = new XMLHttpRequest();
	request.open('get', 'http://' + theHost + ':' + thePort + '/?req=addserverform', true);

	request.onload = function() {
		if (request.status >= 200 && request.status < 400)
			{
			// Success!
			let e1 = document.getElementById('addServer');
			e1.innerHTML = request.responseText;
			}
		else
			{
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(errorID);
			e1.innerHTML = '<p>Error, server reached but could not retrieve Add Server form!</p>';
			}
	};

	request.onerror = function() {
		// There was a connection error of some sort
		let e1 = document.getElementById(errorID);
		e1.innerHTML = '<p>Connection error, could not retrieve Add Server form!</p>';
	};

	request.send();
}

// Ask Main to add a Page server as selected in the "addOne" dropdown in the Add server form.
// req=add_one_specific_server&shortname=selectedValue
function addServerSubmit(oFormElement) {

	if (!oFormElement.action)
		{
		return;
		}
	let adder = document.getElementById("addOne");
	let selectedValue = adder.value;
	let request = new XMLHttpRequest();

	request.onload = function() {
		if (request.status >= 200 && request.status < 400)
			{
			// Success!
			refreshServerStatus(false);
			}
		else
			{
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(errorID);
			e1.innerHTML = '<p>Error, server reached but it returned an error adding server!</p>';
			}
	};

	request.onerror = function() {
		// There was a connection error of some sort
		let e1 = document.getElementById(errorID);
		e1.innerHTML = '<p>Connection error while adding server!</p>';
	};

	let addAction = "&req=add_one_specific_server&shortname=" + selectedValue;
	let theAction = oFormElement.action + addAction;

	request.open('get', theAction, true);
	request.setRequestHeader("Content-Type", "text/plain;charset=UTF-8");
	request.send();
}

// Ask Main to stop/start/restart a Page server.
// ssrText: 'start_one_specific_server', 'stop_one_specific_server', 'restart_one_specific_server'.
function startStopRestartSubmit(ssrText, port) {
	let request = new XMLHttpRequest();
	let action =
			"http://" + theHost + ":" + theMainPort + "/?rddm=1" + "&req=" + ssrText
					+ "&portNumber=" + port;
	request.open('get', action, true);

	request.onload =
			function() {
				if (request.status >= 200 && request.status < 400)
					{
					// Success!
					refreshServerStatus(false);
					}
				else
					{
					// We reached our target server, but it returned an error
					let e1 = document.getElementById(errorID);
					e1.innerHTML =
							'<p>Error, server reached but could not ' + ssrText
									+ ' server on port ' + port + '!</p>';
					}
			};

	request.onerror = function() {
		// There was a connection error of some sort
		let e1 = document.getElementById(errorID);
		e1.innerHTML = '<p>Connection error! Main did not respond.</p>';
	};

	request.send();
}

// Flash an "LED" when there's some IntraMine activity on a port.
// See statusEvents.js#requestSSE().
function showActivity(data) {
	// Break data into name space port.
	let spacePos = data.indexOf(' ');
	if (spacePos < 1)
		{
		return;
		}
	let serverName = data.substring(0, spacePos);
	let port = data.substring(spacePos + 1);
	
	// serverName is not needed at the moment.
	flashOneServerAFewTimes(port);
}

// The "flashing" is done using CSS, see flashingLEDs.css. There's a call to flashOneServer()
// to start flashing, and a call after a brief delay to stop flashing, done by
// changing the class on the "LED".
function flashOneServerAFewTimes(port) {
	flashOneServer(port, true);
	
	setTimeout(function() {
	flashOneServer(port, false);
	}, 2000);
}

// Change "LED" for a port to signal activity. LEDs are done in css, changing the
// class changes the light. There is one LED and row per port on the Status page.
function flashOneServer(port, flashIt) {
	let foundServer = false;
	// Looking for "<span class="portHolder">43124</span>"
	let portHolder = '<span class="portHolder">' + port + '</span>';
	let tableCounter = 0; // There are two tables to check, page and background.
	while (++tableCounter <= 2 && !foundServer)
		{
		let tableId = (tableCounter === 1) ? pageServerTableId: backgroundServerTableId;
		let currentTable = document.getElementById(tableId);
		// If Status page is still loading, currentTable might not have shown up yet.
		if (currentTable === null)
			{
			continue;
			}
		let tableData = currentTable.getElementsByTagName('tbody').item(0);
		let rowData = tableData.getElementsByTagName('tr');

		for(let i = 0; i < rowData.length; i++)
			{
			let rowCellData = rowData.item(i).getElementsByTagName('td');
			if (rowCellData !== null)
				{
				for (let j = 0; j < rowCellData.length; ++j)
					{
					if (rowCellData.item(j).innerHTML === portHolder)
						{
						foundServer = true;
						let nextCell = rowCellData.item(j+1);
						let firstDiv = nextCell.getElementsByTagName('div').item(0);
						firstDiv = firstDiv.getElementsByTagName('div').item(0);
						removeAllClasses(firstDiv);
						if (flashIt)
							{
							addClass(firstDiv, 'led-yellow');
							}
						else
							{
							addClass(firstDiv, 'led-green');
							}
						}
					
					if (foundServer)
						{
						break;
						}
					}
				}

			if (foundServer)
				{
				break;
				}
			}
		}
}

ready(loadAddServerForm);
ready(refreshStatus);
