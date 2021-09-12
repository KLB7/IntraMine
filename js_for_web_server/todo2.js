/* todo2.js
 * original @author Shaumik "Dada" Daityari
 * @copyright December 2013
 * (Modified for use in IntraMine. Does not require jQuery.)
 * There is just one ToDo list, for all users. On any change, the todo data is written out
 * and display is refreshed. This isn't bulletproof, two saves in the same few
 * milliseconds by different users might cause a version conflict and loss of an item,
 * in particular an unsaved item. But on any
 * save, all open views everywhere of the ToDo list are immediately refreshed.
 * see todoGetPutData.js and todoFlash.js for the details on that.
 */

// data.items: an array of ToDo items.
// In each item:
//  id : unique int for each item, 0..up
//  code: string, "1" "2" or"3" indicating column for item
//  title: title of item
//  date: yyyy/mm/dd due date
//  description: text of Description field, as entered
//  html: Description after Gloss conversion of Description
// (html is displayed in ToDo columns, description is typed in Add/Edit a Task)

// For each data.items[i] item there is a corresponding HTML div displayed.
// Items are displayed down a column in order by ascending id.
// Globally, id values run from 1 up without gaps. But the id values in
// a column can have gaps.
// id values are re-assigned before saving, by cleanAndSort().

let data = {};
let o = {};
//let drake = {};

let defaults = {
		todoTask: "todo-task",
		todoHeader: "task-header",
		todoDate: "task-date",
		todoDescription: "task-description",
		taskId: "task-",
		formId: "todo-form",
		dataAttribute: "data",
		deleteDiv: "delete-div"
	};
let codes = {
		"1" : "pending",
		"2" : "inProgress",
		"3" : "completed"
	};

function todoNew(rawData, fullInit, options) {
	todoInitOptions();
	
	if (options != undefined)
		{
		if( options.todoTask != undefined ) o.todoTask = options.todoTask;
		if( options.todoHeader != undefined ) o.todoHeader = options.todoHeader;
		if( options.todoDate != undefined ) o.todoDate = options.todoDate;
		if( options.todoDescription != undefined ) o.todoDescription = options.todoDescription;
		if( options.taskId != undefined ) o.taskId = options.taskId;
		if( options.formId != undefined ) o.formId = options.formId;
		if( options.dataAttribute != undefined ) o.dataAttribute = options.dataAttribute;
		if( options.deleteDiv != undefined ) o.deleteDiv = options.deleteDiv;
		}
	
	if (fullInit)
		{
		let options = {};
		options.format = 'yyyy/mm/dd';
		options.autohide = true;
		let dateHolder = document.getElementById("datepicker");
		let datePicker = new Datepicker(dateHolder, options);

		dragula([
			document.getElementById(codes[1]),		// "pending"
			document.getElementById(codes[2]),		// "inProgress"
			document.getElementById(codes[3]), 		// "completed"
			document.getElementById(o.deleteDiv),
			document.getElementById(o.formId)
			])
		  .on('drop', function (el, target, source, sibling) {
			document.getElementById(o.deleteDiv).style.display = "none";
			todoOnDrop(el, target, source, sibling);
			})
		  .on('cancel', function (el, ontainer, source) {
			document.getElementById(o.deleteDiv).style.display = "none";
			})
		  .on('drag', function (el, source) {
			document.getElementById(o.deleteDiv).style.display = "block";
			});
		}
	else
		{
		removeAllChildrenOfTaskHolders();
		}

	todoReload(rawData);
}

function todoInitOptions() {
	o.todoTask = "todo-task";
	o.todoHeader = "task-header";
	o.todoDate = "task-date";
	o.todoDescription = "task-description";
	o.taskId = "task-";
	o.formId = "todo-form";
	o.dataAttribute = "data";
	o.deleteDiv = "delete-div";
}

function todoReload(rawData) {
	data = JSON.parse(rawData);
	data.items = cleanAndSort(data.items, 'id', 1);

	for (let i = 0; i < data.items.length; ++i)
		{
		generateElement(data.items[i]);
		}
	
	overdueCount = getOverDueCount(data);
	
	let message = "todochanged " + overdueCount;
	setOverdueCount(message);
	
	let today = new Date();
	let el = document.getElementById('pending');
	colorByDaysToOverdue(el, today, '#FDEDEC'); // light red
	el = document.getElementById('inProgress');
	colorByDaysToOverdue(el, today, '#FEF9E7'); // light yellow
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

// "el was dropped into target before a sibling element, and originally came from source"
// Dragula has taken care of the HTML elements, but we want
// data.items[] to reflect the corresponding positions
// or remove an item if it was dropped on the trash.
function todoOnDrop(el, target, source, sibling) {
	
	let id = el.getAttribute('data'); // 'data' attribute is the JSON element id
	let codeName = target.getAttribute("id"); // "pending" etc
	
	// Add/Edit
	if (codeName === o.formId)
		{
		todoEditItem(el, target, source, sibling);
		}
	// Delete.
	else if (codeName === o.deleteDiv)
		{
		todoDeleteItem(el, target, source, sibling);
		}
	else // A move, within or between columns
		{
		todoResequenceItem(el, target, source, sibling);
		}
}

// Put el values in Add/Edit form,
// Remove el,
// delete corresponding item from data.
// Note set [4] value to code representing original column.
function todoEditItem(el, target, source, sibling) {
	let id = parseInt(el.getAttribute('data'), 10);
	let elements = document.getElementById(o.formId).elements;
	
	let movedItem = null;
	
	for (let i = 0; i < data.items.length; ++i)
		{
		if (data.items[i].id === id)
			{
			movedItem = data.items[i];
			break;
			}
		}
	
	elements.item(0).value = movedItem.title;
	elements.item(1).value = horribleUnescape(movedItem.description);
	elements.item(2).value = movedItem.date;
	elements.item(4).value = movedItem.code;
	
	todoDeleteItem(el, target, source, sibling);
}

// Delete data.items[] corresponding to HTML element.
// (dropped in trash or onto Add/Edit.)
function todoDeleteItem(el, target, source, sibling) {
	let id = parseInt(el.getAttribute('data'), 10);

	for (let i = 0; i < data.items.length; ++i)
		{
		if (data.items[i].id === id)
			{
			delete data.items[i];
			break;
			}
		}
		
	el.parentNode.removeChild(el);
	
	data.items = cleanAndSort(data.items, 'id', 1);
	putData(data);
}

// Find movedItem = data.items[] corresponding to the dropped HTML element's "data" attr.
// Get id of sibling(HTML element following new position of el).
// Boost all id's >= sibling id by one.
// Set id of movedItem to old sibling id.
// Set code of movedItem to column's code.
// Clean up and save (which will trigger a reload).
function todoResequenceItem(el, target, source, sibling) {
	let id = parseInt(el.getAttribute('data'), 10);
	let movedItem = null;
	
	for (let i = 0; i < data.items.length; ++i)
		{
		if (data.items[i].id === id)
			{
			movedItem = data.items[i];
			break;
			}
		}
	
	let codeName = target.getAttribute("id"); // "pending" etc
	let newCodeIdx = '';
	for (let i = 1; i <= 3; ++i)
		{
		if (codes[i] === codeName)
			{
			newCodeIdx = i;
			break;
			}
		}
	
	let newCode = '' + newCodeIdx;
	movedItem.code = newCode;
	
	let siblingId = siblingIdToBoost(el, sibling);
	boostItemIds(siblingId);
	movedItem.id = siblingId;
	data.items = cleanAndSort(data.items, 'id', 1);
	putData(data);
}

function siblingIdToBoost(el, sibling) {
	let siblingId = 9999;

	if (sibling === null)
		{
		// Get id of sibling before and add one.
		sibling = el.previousSibling;
		if (sibling !== null && typeof(sibling.getAttribute) === typeof(Function))
			{
			siblingId = sibling.getAttribute('data') + 1;
			}
		// else only item in column, just use a big number (9999)
		}
	else
		{
		siblingId = sibling.getAttribute('data');
		}

	return(siblingId);
}

function boostItemIds(minimumID) {
	let arr = data.items;
	for (i = 0; i < arr.length; ++i)
		{
		let item = arr[i];
		let oldID = item.id;
		if (oldID >= minimumID)
			{
			item.id = oldID + 1;
			}
		}
}

function todoAddNewItem() {
	let elements = document.getElementById(o.formId).elements;
	let id = 9999; // Deliberately higher than any existing id, to avoid conflict.
	let title = elements.item(0).value;
	let description = horribleEscape(elements.item(1).value);
	let date = elements.item(2).value;
	let idx = elements.item(4).value;
	let index = '' + idx;
	
	if (!title)
		{
		let errorElem = document.getElementById("loadError");
        errorElem.innerHTML = "New item must have a title!";
		return;
        }
	
	let tempData =
		{
		id : id,
		code: index,
		title: title,
		date: date,
		description: description
        };

	// Save to local disk.
	data.items[id] = tempData;
	//localStorage.setItem("todoData", JSON.stringify(data));
	data.items = cleanAndSort(data.items, 'id', 1);
	putData(data);
	
	// Reset Form
	elements.item(0).value = "";
	elements.item(1).value = "";
	elements.item(2).value = "";
	elements.item(4).value = "1";

	// Reload
	getToDoData();
	}

function generateElement(params) {
	let parent = document.getElementById(codes[params.code]);
	if (parent === undefined || parent === null)
		{
		//console.log("ERRROR no parent for " + codes[params.code]);
		return;
		}
	
	let newElement = document.createElement("div");
	newElement = parent.appendChild(newElement);
	addClass(newElement, o.todoTask);
	newElement.id = o.taskId + params.id;
	newElement.setAttribute("data", params.id);
	
	parent = newElement;
	newElement = document.createElement("div");
	newElement = parent.appendChild(newElement);
	addClass(newElement, o.todoHeader);
	newElement.innerHTML = params.title;
	
	newElement = document.createElement("div");
	newElement = parent.appendChild(newElement);
	addClass(newElement, o.todoDate);
	newElement.innerHTML = params.date;
	
	newElement = document.createElement("div");
	newElement = parent.appendChild(newElement);
	addClass(newElement, o.todoDescription);
	newElement.innerHTML = horribleUnescape(decodeURIComponent(params.html));
}

function cleanAndSort(objArray, prop, direction){
	if (arguments.length<2) throw new Error("ARRAY, AND OBJECT PROPERTY MINIMUM ARGUMENTS, OPTIONAL DIRECTION");
	if (!Array.isArray(objArray)) throw new Error("FIRST ARGUMENT NOT AN ARRAY");
	let clone = objArray.slice(0);
	// Remove nulls.
	clone = clone.filter(function(el){return(el != null);});
	// sort
	const direct = arguments.length > 2 ? arguments[2] : 1; //Default to ascending
	clone.sort(function(a,b){
		if (a !== null && b !== null)
			{
			a = a[prop];
			b = b[prop];
			return ( (a < b) ? -1*direct : ((a > b) ? 1*direct : 0) );
			}
		return(0);
	});
	// Reassign id's to be 0..length-1, same as array index. This removes duplicates
	// and fills in missing id's.
	for (let i = 0; i < clone.length; ++i)
		{
		clone[i].id = i;
		}
	return clone;
}

function removeAllChildrenOfTaskHolders() {

	for (let idx in codes)
		{
		let theID = codes[idx];
		//theID = theID.substring(1); wot???
		let parent = document.getElementById(theID);
		if (parent !== null)
			{
			// Delete all div children (avoid deleting H3 header).
			while (parent.lastChild && parent.lastChild.nodeName === "DIV")
				{
				parent.removeChild(parent.lastChild);
				}
			}
		}
	 }

// Interim hack, replace troublesome characters (in description)
// with placeholders. These are undone when presenting description for
// editing, and also in gloss.pm#Gloss() when applying Gloss to the
// description.
function horribleEscape(text) {
	text = text.replace(/\=/g, '__EQUALSIGN_REP__');
	text = text.replace(/\"/g, '__DQUOTE_REP__');
	text = text.replace(/\'/g, '__ONEQUOTE_REP__');
	text = text.replace(/\+/g, '__PLUSSIGN_REP__');
	text = text.replace(/\%/g, '__PERCENTSIGN_REP__');
	text = text.replace(/\&/g, '__AMPERSANDSIGN_REP__');
	text = text.replace(/\\t/g, '__TABERINO__');
	text = text.replace(/\\/g, '__BSINO__');

	return(text);        
}

// Reverse of horribleEscape just above.
function horribleUnescape(text) {
	text = text.replace(/__EQUALSIGN_REP__/g, '=');
	text = text.replace(/__DQUOTE_REP__/g, '\"');
	text = text.replace(/__ONEQUOTE_REP__/g, '\'');
	text = text.replace(/__PLUSSIGN_REP__/g, '+');
	text = text.replace(/__PERCENTSIGN_REP__/g, '%');
	text = text.replace(/__AMPERSANDSIGN_REP__/g, '&');
	text = text.replace(/__TABERINO__/g, '\\t');
	text = text.replace(/__BSINO__/g, '\\');


	return(text);
}
