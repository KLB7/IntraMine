// topnav.js: show/hide service names in IntraMine's top navigation bar
// in response to WebSockets messages.

function registerTopNavCallbacks() {
	addCallback("Nav:", showHideServiceName);
}

// Show or hide a service called shortName in the top navigation bar.
function showHideServiceName(message) {
	let navbar = document.getElementById("nav");
	if (navbar === null)
		{
		return;
		}

	let fieldsArr = message.split(":");
	let shortName = fieldsArr[1]; // Skip "Nav:"
	let showHide = fieldsArr[2];
	let show = (showHide.indexOf("show") == 0) ? true : false;
	let liTags = navbar.getElementsByTagName("li");
    let searchText = shortName;
	let nameElem = null;
	for (let i = 0; i < liTags.length; i++)
        {
		if (liTags[i].textContent.indexOf(searchText) == 0)
            {
			nameElem = liTags[i];
            break;
            }
        }
	if (nameElem !== null)
		{
		if (show)
			{
			// TEST ONLY
			//console.log("Showing " + shortName);
			removeClass(nameElem, "navHidden");
			}
		else // hide
			{
			// TEST ONLY
			//console.log("HIDING " + shortName);
			addClass(nameElem, "navHidden");
			}
		}	
}

window.addEventListener('wsinit', function (e) { registerTopNavCallbacks(); }, false);