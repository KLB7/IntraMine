/**
 * db_example.js: Manage a small form that adds a fruit with rating to the dbeg.db database
 * and displays it. And a little housekeeping to manage the loading spinner, and resizing.
 * This is included on the web page by intramine_db_example.pl#OurPage().
 * The form:
 * Fruit:____________  Rating:______________  Add/Update.
 * The API is somewhat RESTful:
 * GET  http://n.n.n.n:81/DBX/fruit/ will return the whole fruit db, and
 * POST http://n.n.n.n:81/DBX/fruit/fruitname/fruitrating/ will add or update a fruit with rating.
 * DELETE is also supported.
 */

// Some JS to manage scrollbars and the loading spinner.

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

function doResize() {
	let el = document.getElementById("scrollAdjustedHeight");
	let pos = getPosition(el);
	let windowHeight = window.innerHeight;
	el.style.height = ((windowHeight - pos.y - 10) / windowHeight) * 100 + "%";
	el.style.width = window.innerWidth - 4 + "px";
}

// Top Nav includes a gif that's animated while the page is loading.
// Turn it off when page has loaded.
function turnOffTheLoadingSpinner() {
	hideSpinner();
}

// User clicks the Add/Update button: call back to the db_example service with eg
// POST http://n.n.n.n:81/DBX/fruit/fruitname/fruitrating/,
// where the %RequestAction HandleFruitRequest() will add the fruit to our little db table
// (or update an existing entry).
// If things go well, we call refreshFruitDisplay() to get and refresh the HTML table
// displaying all the fruit entries.
function addFruitSubmit(oFormElement) {
	let fruitname = document.getElementById("fruitnametext").value;
	let fruitrating = document.getElementById("fruitratingtext").value;
	
	let request = new XMLHttpRequest();
	
	request.onload = function() {
		if (request.status >= 200 && request.status < 400)
			{
			// Success!
			refreshFruitDisplay();
			}
		else
			{
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(errorID);
			e1.innerHTML = '<p>Error, server reached but it returned an error adding fruit!</p>';
			}
	};

	request.onerror = function() {
		// There was a connection error of some sort
		let e1 = document.getElementById(errorID);
		e1.innerHTML = '<p>Connection error while adding fruit!</p>';
	};

	// http://n.n.n.n:81/DBX/fruit/apple/3/
	let theAction = 'http://' + theHost + ':' + thePort + '/' + shortServerName + '/'
				+ apiName + '/' + fruitname + '/' + fruitrating + '/';
	
	request.open('POST', theAction, true);
	request.setRequestHeader("Content-Type", "text/plain;charset=UTF-8");
	request.send('');
}

// Call intramine_db_example.pl#GetHTMLforDbContents() via
// GET  http://n.n.n.n:81/DBX/fruit/,
// after addFruitSubmit() above successfully adds a fruit with rating.
function refreshFruitDisplay() {
	let request = new XMLHttpRequest();
	request.onload = function() {
	if (request.status >= 200 && request.status < 400)
		{
		// Success!
		let fruitTableElement = document.getElementById(fruitTableId);
		fruitTableElement.innerHTML = request.responseText;
		addDeleteButtons();
		}
	else
		{
		// We reached our target server, but it returned an error
		let e1 = document.getElementById(errorID);
		e1.innerHTML = '<p>Error, server reached but it returned an error updating fruit display!</p>';
		}
	};

	request.onerror = function() {
		// There was a connection error of some sort
		let e1 = document.getElementById(errorID);
		e1.innerHTML = '<p>Connection error while updating fruit display!</p>';
	};
	
	let theAction = 'http://' + theHost + ':' + thePort + '/' + shortServerName + '/'
					+ apiName + '/';
	
	request.open('GET', theAction, true);
	request.setRequestHeader("Content-Type", "text/plain;charset=UTF-8");
	request.send();
}

function addDeleteButtons() {
	let fruitDiv = document.getElementById(fruitTableId);
	if (fruitDiv === null)
		{
		return;
		}
	let fruitTable = fruitDiv.firstChild;
	
	for (let i = 1, row; row = fruitTable.rows[i]; ++i)
		{
		let lastColIndex = row.cells.length - 1;
		let delHolder = row.cells[lastColIndex];
		let fruitname = row.cells[0].innerHTML;
		
		let deleteButton = 
		"<button type='button' class='delButtonHolder' onclick='deleteOneFruit(\"" + fruitname
				+ "\"); return false;'" + ">Delete</button>";
		delHolder.innerHTML = deleteButton;
		}
}

function deleteOneFruit(fruitname) {
	let request = new XMLHttpRequest();
	
	request.onload = function() {
	if (request.status >= 200 && request.status < 400)
		{
		refreshFruitDisplay();
		}
	else
		{
		// We reached our target server, but it returned an error
		let e1 = document.getElementById(errorID);
		e1.innerHTML = '<p>Error, server reached but it returned an error updating fruit display!</p>';
		}
	};

	request.onerror = function() {
		// There was a connection error of some sort
		let e1 = document.getElementById(errorID);
		e1.innerHTML = '<p>Connection error while updating fruit display!</p>';
	};
	

	let theAction = 'http://' + theHost + ':' + thePort + '/' + shortServerName + '/'
	+ apiName + '/' + fruitname + '/';
	
	request.open('DELETE', theAction, true);
	request.setRequestHeader("Content-Type", "text/plain;charset=UTF-8");
	request.send('');
}

ready(doResize);
ready(turnOffTheLoadingSpinner);
window.addEventListener("resize", doResize);

// Show initial db contents in the fruit table.
ready(refreshFruitDisplay);
