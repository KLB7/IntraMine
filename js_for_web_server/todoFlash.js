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
		addCallback("todochanged", getToDoData);
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
    let todoElem;

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

window.addEventListener('wsinit', function (e) { registerToDoCallbacks(); }, false);