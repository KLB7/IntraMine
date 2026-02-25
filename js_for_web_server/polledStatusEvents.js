// polledStatusEvents.js

// Use HTTP short polling to ask Status back end for a list of 
// port numbers corresponding to services showing activity of any sort.
async function pollForActivitities() {
	try {
		let theAction = 'http://' + theHost + ':' + thePort + '/?req=serviceactivitylist';
		const response = await fetch(theAction);
		if (response.ok)
			{
			let text = await response.text();
			if (text !== ' ')
				{
				const portList = text.split(",");
				for (const port of portList)
					{
					flashOneServerAFewTimes(port);
					}
				}
			}
		else
			{
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(errorID);
			e1.innerHTML = '<p>Error, activity request failed!</p>';
			}
	}
	catch(error) {
		// There was a connection error of some sort
		let e1 = document.getElementById(errorID);
		e1.innerHTML = '<p>Activity request connection error!</p>';
	}
}


// Ask Status service back end for any port numbers for service activities.
// This needs to be frequent (once per second or so) to show in "real time".
let statusPollingID = setInterval(pollForActivitities, 1000);
