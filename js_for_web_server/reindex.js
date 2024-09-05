// reindex.js: Add/remove folders from index list,
// fire off a re-index which is handled by intramine_reindex.pl#Reindex().

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

// Position and resize scrollAdjustedHeight (holding progress messages).
function xdoResize() {
	let dirTableHolder = document.getElementById(dirtable);
	if (dirTableHolder === null)
		{
		console.log("Error, cannot find div id " + dirtable);
		return;
		}
	let pos = getPosition(dirTableHolder);
	let rect = dirTableHolder.getBoundingClientRect();
	let holderHeight = rect.height;
	let windowHeight = window.innerHeight;
	let elHeight = windowHeight - pos.y - holderHeight - 16;
	let newHeightPC = (elHeight / windowHeight) * 100;
	let el = document.getElementById("scrollAdjustedHeight");
	el.style.height = newHeightPC + "%";
	el.style.width = window.innerWidth - 4 + "px";



	// let buttonHolder = document.getElementById("top_buttons");
	// if (buttonHolder === null)
	// 	{
	// 	console.log("Error, cannot find div id 'top_buttons'!");
	// 	return;
	// 	}
	// let pos = getPosition(buttonHolder);
	// let rect = buttonHolder.getBoundingClientRect();
	// let holderHeight = rect.height;
	
	// let windowHeight = window.innerHeight;
	// let elHeight = windowHeight - pos.y - holderHeight - 16;
	// let newHeightPC = (elHeight / windowHeight) * 100;
	// let el = document.getElementById("scrollAdjustedHeight");
	// el.style.height = newHeightPC + "%";
	// el.style.width = window.innerWidth - 4 + "px";
}

function doResize() {
	let el = document.getElementById(cmdOutputContainerDiv);

	let pos = getPosition(el);
	let windowHeight = window.innerHeight;
	let elHeight = windowHeight - pos.y - 10;
	let newHeightPC = (elHeight / windowHeight) * 100;
	el.style.height = newHeightPC + "%";

	let windowWidth = window.innerWidth;
	el.style.width = windowWidth - 4 + "px";
}

// function addReindexHandler() {
// 	let el = document.getElementById("reindexButton");
// 	if (el !== null)
// 		{
// 		el.addEventListener('click', reindex, false);
// 		}
// }

ready(doResize);
ready(hideSpinner);
//ready(addReindexHandler);
window.addEventListener("resize", doResize);
