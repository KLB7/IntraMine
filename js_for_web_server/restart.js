// restart.js: detect that IntraMine has restarted, respond
// by calling websockets.js#wsInit() and refreshing the top navigation bar.
// Show red in the nav bar if IntraMine isn't up (see main.css nav li > a.noIntraMine).

let sessionStart = '';
let intramineIsUp = true;
let theSSAction = '';
let noIntraMineClass = 'noIntraMine'; // main.css

// "sleep" for ms milliseconds.
function sleepMs(ms)
	{
	return new Promise(resolve => setTimeout(resolve, ms));
	}

async function checkForRestartPeriodically()
	{
	if ((typeof theMainPort !== 'undefined') && (typeof theHost !== 'undefined'))
		{
		theSSAction = 'http://' + theHost + ':' + theMainPort + '/?req=sessionStart';
		}
	if (theSSAction === '')
		{
		return;
		}
	
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

// Ask Main service for its session start date time stamp.
// If it changes, we want to re-establish WebSockets comm
// and redo the nav bar (in case services have changed).
// If no good response is received, that probably means
// Main is restarting, so ignore.
async function checkAndHandleRestart()
	{
	try {
		const response = await fetch(theSSAction);
		if (response.ok)
			{
			let text = await response.text();
			handleRestartIfNeeded(text);
			}
		else
			{
			// We reached our target server, but it returned an error
			showIntraMineIsDown();
			}
		}
	catch(error)
		{
		// There was a connection error of some sort
		showIntraMineIsDown();
		}
	}

// Re-establish WebSockets communication.
async function handleRestartIfNeeded(latestSessionStart)
	{
	if (sessionStart !== '' && sessionStart !== latestSessionStart)
		{
		wsInit();
		// Try navbar a few times, sometimes things are slow.
		let numRetries = 5;
		for (let tryCount = 0; tryCount < 5; ++tryCount)
			{
			let didIt = refreshNavBar();
			if (didIt == true)
				{
				break;
				}
			await sleepMs(1000); // 1 second
			}
		
		}
	sessionStart = latestSessionStart;
	}

function showIntraMineIsDown()
	{
	if (!intramineIsUp)
		{
		return;
		}
	
	intramineIsUp = false;
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

// Request a new navbar from our service.
// Return false if should retry, true if we're done.
async function refreshNavBar()
	{
	if (intramineIsUp)
		{
		return(true);
		}
	intramineIsUp = true;
	let navbar = document.getElementById("nav");
	if (navbar === null)
		{
		return(true);
		}

	if ((typeof ourSSListeningPort === 'undefined') || (typeof theHost === 'undefined'))
		{
		return(true);
		}
	
	try
		{
		let theAction = 'http://' + theHost + ':' + ourSSListeningPort + '/?req=navbar';
		const response = await fetch(theAction);
		if (response.ok)
			{
			let text = await response.text();
			navbar.innerHTML = text;
			return(false);
			}
		else
			{
			// We reached our target server, but it returned an error
			//console.log("We reached our target server, but it returned an error.");
			return(true);
			}		
		}
	catch(error)
		{
		//console.log("Try failed.");
		return(true);
		}
	}

window.addEventListener("load", checkForRestartPeriodically);
