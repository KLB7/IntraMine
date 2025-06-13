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
// Aaaand much later, contentsName is no longer used. Never mind.
let contentsName = 'contents.html';
let spinnerTimeoutTimer = 0;

function showSpinner() {
	clearTimeout(spinnerTimeoutTimer);
	let spinnerParent = document.getElementById('spinnerParent');
	if (spinnerParent !== null)
		{
		spinnerParent.innerHTML = "<img id='spinner' src='globe.gif' "
									+ "width='30.0' height='24.0' />\n";
		//document.getElementById("spinner").style.objectPosition = "0 0";
		styleGlobe();
		spinnerTimeoutTimer = setTimeout(hideSpinner, 20000);
		}
	else
		{
		console.log("spinner.js#showSpinner, no parent!");
		}
}

function hideSpinner() {
	let spinnerParent = document.getElementById('spinnerParent');
	if (spinnerParent !== null)
		{
		// The old way. IntraMine handled the link. That mostly worked, but
		// relative links were broken.
		// spinnerParent.innerHTML = "<a href='./" + contentsName + "' target='_blank'>"
		// + "<img id='spinner' src='question4-44.png' width='30.0' height='24.0' /></a>\n";
		// The better way, topnav.js#showHelpContents calls back to Main, which
		// asks the default browser to show the contents.html file directly,
		// and magically the relative links work.
		spinnerParent.innerHTML = "<a href='' onclick='showHelpContents(); return(false);'>"
		+ "<img id='spinner' src='question4-44.png' width='30.0' height='24.0' /></a>\n";

		setTimeout(styleQuestionMark, 50);
		}
	else
		{
		console.log("spinner.js#hideSpinner, no parent!");
		}
}

function styleGlobe() {
	let spinnerParent = document.getElementById('spinnerParent');
	if (spinnerParent === null)
		{
		return;
		}
	let img = document.getElementById('spinner');
	if (img !== null)
		{
		img.style.display="inline-block";
		img.style.objectPosition = "0 0";
		}
}

function styleQuestionMark() {
	let spinnerParent = document.getElementById('spinnerParent');
	if (spinnerParent === null)
		{
		return;
		}
	let img = document.getElementById('spinner');
	if (img !== null)
		{
		img.style.display="inline-block";
		img.style.objectPosition = "0 -4px";
		clearTimeout(spinnerTimeoutTimer);
		spinnerTimeoutTimer = 0;
		}
}