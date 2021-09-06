// todoFlash.js: use WebSockets to flash the Nav bar when ToDo page changes.

// Add triggers and callbacks for "todochanged" and "todoflash".
// (see websockets.js#addCallback()).

// This is called in response to the custom 'wsinit' event,  which is
// listened for at the bottom here. See websockets.js for the
// definitions of 'wsinit' and addCallback().
// The function name should be unique to avoid collisions.
function registerToDoCallbacks() {
	addCallback("todoflash", flashNavBar);
	// getToDoData() is only defined for the ToDo server.
	if(typeof getToDoData === "function")
		{
		addCallback("todochanged", handleToDoChanged);
		}
	else
		{
		addCallback("todochanged", setOverdueCount);
		}
}

// Briefly change appearance of ToDo in the navigation bar.
function flashNavBar() {
	let navbar = document.getElementById("nav");
	if (navbar === null)
		{
		return;
		}
	
	// Find the ToDo anchor in the navigation bar.
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
        flashIt(todoElem);
        }
}

function flashIt(todoElem) {
 
    toggleFlash(todoElem, true);
    setTimeout(function() {
        toggleFlash(todoElem, false);
        }, 2000);
}

function toggleFlash(todoElem, flashOn) {
    if (flashOn)
        {
        addClass(todoElem, 'flashOn');
        }
    else
        {
        removeClass(todoElem, 'flashOn');
        }
}

// Called by ToDo page to both update overdue count and get the ToDo data.
function handleToDoChanged(message) {
	setOverdueCount(message);
	getToDoData();
}

function setOverdueCount(message) {
	// We expect a number at the end of the message - the ToDo overdue count.
	let overdueNumMatch = /(\d+)/.exec(message);
	if (overdueNumMatch !== null)
		{
		let count = parseInt(overdueNumMatch[1], 10);
		showToDoCountInNav(count);
		}
	else
		{
		// TEST ONLY
		//console.log("ERRO in setOverdueCount, no count supplied!");
		showToDoCountInNav(0);
		}
}

// Set "ToDo" nav item's overdue count, if it has changed.
function showToDoCountInNav(count) {
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
		let newText = newNavText(text, count);
		todoElem.textContent = newText;
		}
}

// Make up new "ToDo" nav item text with correct count.
function newNavText(text, count) {
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

window.addEventListener('wsinit', function (e) { registerToDoCallbacks(); }, false);