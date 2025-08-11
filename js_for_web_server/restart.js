// restart.js: detect that our service has restarted after stopping, respond
// by reloading our page.
// Show red in the nav bar if IntraMine isn't up (see main.css nav li > a.noIntraMine).

let serviceIsUp = true;
let isRunningAction = '';				// Check service is up
let noIntraMineClass = 'noIntraMine'; 	// main.css

// "sleep" for ms milliseconds.
function sleepMs(ms)
	{
	return new Promise(resolve => setTimeout(resolve, ms));
	}

// Loop, checking if our service is running and handling stop/start.
// We require having main port, host, service name and service port.
async function checkForRestartPeriodically()
	{
	if ((typeof theMainPort !== 'undefined') && (typeof theHost !== 'undefined') && (typeof shortServerName !== 'undefined') && (typeof ourSSListeningPort !== 'undefined'))
		{
		// Action to ask Main if our service is running: returns "yes", "no", error.
		isRunningAction = 'http://' + theHost + ':' + theMainPort + '/?req=running&shortname=' + shortServerName;
		}
	else
		{
		return;
		}
	
	await sleepMs(5000); // 5 seconds, things are just starting so be patient.

	while (true)
		{
		try
			{
			await sleepMs(5000); // 5 seconds
			await checkAndHandleRestart();
			}
		catch(error)
			{
			; // ignore any errors
			}
		}
	}

// Ask Main if our service is running. Expect "yes" if it's up,
// "no" if Main is running but our service is not up yet,
// or an error if Main isn't running either.
// Turn the nav bar red if response isn't "yes".
// On "yes", reload if our service was previously down.
async function checkAndHandleRestart()
	{
	try
		{
		// Check that our service is running, regardless of port.
		const runningResponse = await fetch(isRunningAction);
		if (runningResponse.ok)
			{
			let isRunning = await runningResponse.text();
			if (isRunning === "yes")
				{
				handleRestartIfNeeded();
				}
			else
				{
				// Either service is slow to start or
				// it won't be started - we'll try again in 5 seconds.
				console.clear();
				showOurServiceIsDown();
				}
			}
		else
			{
			console.clear();
			showOurServiceIsDown();
			}
		}
	catch(error)
		{
		// There was a connection error of some sort
		console.clear();
		showOurServiceIsDown();
		}

	}

// Reload our window, if our backend service was down and came back.
// Ask for a port number for our service (port numbers can change
// if IntraMine is restarted) first.
// If our port number has changed, update window.location.href
// (which triggers a reload). Otherwise just call reload().
async function handleRestartIfNeeded()
	{
	if (serviceIsUp)
		{
		return;
		}
	
	// Get current service port, in case it changed.
	const port = await fetchPort(theHost, theMainPort, shortServerName, errorID);
	if (port !== "")
		{
		if (port !== ourSSListeningPort)
			{
			// Change port and reload
			// http://192.168.40.8:43131/Editor/?href=...
			let oldHref = window.location.href;
			let newHref = oldHref.replace(/:\d+/, ":" + port);
			window.location.href = newHref; // triggers reload
			}
		else // Just do a reload.
			{
			window.location.reload();
			}
		} 		// port retrieved
	else 		//   - no idea what went wrong.
		{
		console.clear();
		showOurServiceIsDown();
		}
	}

// Put some red in the nav bar. There's no need to remove it,
// since the page will be reloaded if and when our service comes back.
// Note it might never come back if it was removed from data/serverlist.txt.
function showOurServiceIsDown()
	{
	if (!serviceIsUp)
		{
		return;
		}
	
	serviceIsUp = false;
	let navbar = document.getElementById("nav");
	if (navbar === null)
		{
		return;
		}
	
	let aTags = navbar.getElementsByTagName("a");
	for (let i = 0; i < aTags.length; i++)
		{
		addClass(aTags[i], noIntraMineClass);
		}
	}

window.addEventListener("load", checkForRestartPeriodically);
