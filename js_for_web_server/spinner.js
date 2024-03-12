/** spinner.js:
 * showSpinner() shows a spinning pacifier.
 * hideSpinner replaces the pacificier with a "Help" link to the main index.html help file.
 * Include this for every IntraMine server that has an entry in the top nav bar.
 * By default, swarmserver.pm#TopNav() puts the spinning globe in when creating the top nav
 * bar, so call hideSpinner when your page has finished loading.
 * see eg db_example.js#turnOffTheLoadingSpinner().
 */

// Rev May 26 2021, contentsName is now hard-wired to avoid a req=portNumber callback,
// which was a nuisance because it interfered with the round-robin when multiple
// instances of a server were running. Especially with two servers, the port
// number would get stuck due to calling req=portNumber twice.
// contentsName is taken from data/intramine_config.txt "SPECIAL_INDEX_NAME_HTML"
let contentsName = 'contents.html';
let spinnerTimeoutTimer = 0;

function showSpinner() {
	clearTimeout(spinnerTimeoutTimer);
	let spinnerParent = document.getElementById('spinnerParent');
	if (spinnerParent !== null)
		{
		spinnerParent.innerHTML = "<img id='spinner' src='globe.gif' "
									+ "alt='' width='43.3' height='36' />\n";
//	spinnerParent.innerHTML = "<div id='spinnerParent'><img id='spinner' src='globe.gif' " + "alt='' width='43.3' height='36' /></div>\n";
		spinnerTimeoutTimer = setTimeout(hideSpinner, 20000);
		}
	else
		{
		console.log("spinner.js#showSpinner, no parent!");
		}
}

function hideSpinner() {
	// Wait a bit if page hasn't loaded yet.
	// Removed, sometimes it seems "complete" isn't reached for
	// a long time on the Search page, nevertheless the page is usable.
	// In general there are no delays any more that are long enough to need this.
	// if (document.readyState !== "complete")
	// 	{
	// 	spinnerTimeoutTimer = setTimeout(hideSpinner, 100);
	// 	return;
	// 	}
	// clearTimeout(spinnerTimeoutTimer);

	let spinnerParent = document.getElementById('spinnerParent');
	if (spinnerParent !== null)
		{
		spinnerParent.innerHTML = "<a href='./" + contentsName + "' target='_blank'>"
		+ "<img id='spinner' src='question4-44.png' alt='' width='43.3' height='36' /></a>\n";
//		spinnerParent.innerHTML = "<div id='spinnerParent'><a href='./" + contentsName + "' target='_blank'>" + "<img id='spinner' src='question4-44.png' alt='' width='43.3' height='36' /></a></div>\n";
		}
	else
		{
		console.log("spinner.js#hideSpinner, no parent!");
		}
}
