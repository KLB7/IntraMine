// reportActivity.js
async function reportActivity() {
	try {
		let theAction = 'http://' + theHost + ':' + theMainPort + '/?signal=activity&activeservice='
		+ shortServerName + '&name=Status&port=' + ourSSListeningPort;
		const response = await fetch(theAction);
		if (response.ok)
			{
			// Success!
			//console.log("SUCCESS");
			}
		// else no big deal.
	}
	catch(error) {
		console.log("reportActivity ERROR! |" + error + "|");
	}
}
