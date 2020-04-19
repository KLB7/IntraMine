/** spinner.js:
 * showSpinner() shows a spinning pacifier.
 * hideSpinner replaces the pacificier with a "Help" link to the main index.html help file.
 * Include this for every IntraMine server that has an entry in the top nav bar.
 * By default, swarmserver.pm#TopNav() puts the spinning globe in when creating the top nav
 * bar, so call hideSpinner when your page has finished loading.
 * see eg db_example.js#turnOffTheLoadingSpinner().
 */

// contentsName is taken from data/intramine_config.txt "SPECIAL_INDEX_NAME_HTML"
let contentsName = '';
let spinnerTimeoutTimer = 0;

function showSpinner() {
	clearTimeout(spinnerTimeoutTimer);
	let spinnerParent = document.getElementById('spinnerParent');
	if (spinnerParent !== null)
		{
		spinnerParent.innerHTML = "<div id='spinnerParent'><img id='spinner' src='globe.gif' "
									+ "alt='' width='43.3' height='36' /></div>\n";
		spinnerTimeoutTimer = setTimeout(hideSpinner, 20000);
		}
}

function hideSpinner() {
	// Wait a bit if page hasn't loaded yet.
	if (contentsName === '')
		{
		spinnerTimeoutTimer = setTimeout(hideSpinner, 100);
		return;
		}
	clearTimeout(spinnerTimeoutTimer);
	let spinnerParent = document.getElementById('spinnerParent');
	if (spinnerParent !== null)
		{
		spinnerParent.innerHTML = "<div id='spinnerParent'><a href='./" + contentsName + "' target='_blank'>"
		+ "<img id='spinner' src='question4-44.png' alt='' width='43.3' height='36' /></a></div>\n";
		}
}

// Callback to set contentsName after page has loaded.
function setContentsName(value) {
	contentsName = value;
}

window.addEventListener("load", function() {setConfigValue("SPECIAL_INDEX_NAME_HTML", setContentsName);});