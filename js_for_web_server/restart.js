// restart.js: detect that our service has stopped/restarted, respond
// by just changing the nav bar to red on stop, and when IntraMine comes back
// restore nav bar color and re-init the WebSockets connection.
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
	
	await sleepMs(5000); // Check every five seconds.

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

// "Restart" our window, if our backend service was down and came back.
// doTheRestart resets WebSockets but does not reload the page.
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
		doTheRestart(port);
		} 		// port retrieved
	else 		//   - no idea what went wrong.
		{
		console.clear();
		showOurServiceIsDown();
		}
	}

// Put some red in the nav bar.
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

async function doTheRestart(port) {
	if (serviceIsUp)
		{
		return;
		}
	
	serviceIsUp = true;
	
	let navbar = document.getElementById("nav");
	if (navbar === null)
		{
		return;
		}
	
	let aTags = navbar.getElementsByTagName("a");
	for (let i = 0; i < aTags.length; i++)
		{
		removeClass(aTags[i], noIntraMineClass);
		}

	// Re-establish WebSockets.
	initializing = true;
	wsIsConnected = 0;
	wsInit();

	// And do a "hard" reload? No, it tends to lock things up, alas.
	//window.location.reload(true);
}

window.addEventListener("load", checkForRestartPeriodically);
