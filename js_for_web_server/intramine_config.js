/* intramine_config.js
Retrieve a configuration value from any running IntraMine swarmserver
(for back end see swarmserver.pm#ConfigValue())

NOTE setConfigValue() is not currently used.
However, fetchPort() is used all over the place.
So this file should now be called something more like "fetchPort.js",
sorry about that.
*/

// "sleep" for ms milliseconds.
function sleepForSomeMilliseconds(ms) {
	return new Promise(resolve => setTimeout(resolve, ms));
}

// Since this file is included in all IntraMine services, fetchPort() is snuck
// in here.
// Return appropriate port number for service named short_name.
// Using the port number avoids cross-origin trouble.
// Eg: const port = await fetchPort(mainIP, mainPort, 'Search', errorID);
async function fetchPort(main_ip, main_port, short_name, errorID) {
	let shortPort = "";
	let tryCounter = 0;
	let maxTries = 10;
	let retry = true;
	
	while (retry)
		{
		try
			{
			let theAction = 'http://' + main_ip + ':' + main_port + '/' + short_name + '/?req=portNumber';
			const response = await fetch(theAction);
			if (response.ok)
				{
				let text = await response.text();
				if (isNaN(text))
					{
					++tryCounter;
					if (tryCounter > maxTries)
						{
						retry = false;
						let e1 = document.getElementById(errorID);
						if (e1 !== null)
							{
							e1.innerHTML = '<p>Error, server reached but it did not return a numeric port for ' + short_name + '!</p>';
							}
						}
					else
						{
						retry = true;
						// Try again, after a brief pause.
						await sleepForSomeMilliseconds(1000);
						}
					}
				else
					{
					// Success!
					retry = false;
					shortPort = text;
					}
				}
			else
				{
				++tryCounter;
				if (tryCounter > maxTries)
					{
					retry = false;
					// We reached our target server, but it returned an error
					let e1 = document.getElementById(errorID);
					if (e1 !== null)
						{
						e1.innerHTML = '<p>Error, server reached but it did not return a port for ' + short_name + '!</p>';
						}
					}
				else
					{
					retry = true;
					// Try again, after a brief pause.
					await sleepForSomeMilliseconds(1000);
					}
				}
			}
		catch(error)
			{
			// There was a connection error of some sort
			++tryCounter;
			if (tryCounter > maxTries)
				{
				retry = false;
				// There was a connection error of some sort
				let e1 = document.getElementById(errorID);
				e1.innerHTML = '<p>Connection error while attempting to get port for ' + short_name + '!: ' + error + '</p>';
				}
			else
				{
				retry = true;
				// Try again, after a brief pause.
				await sleepForSomeMilliseconds(1000);
				}
			}
		} // while retry
	
	return(shortPort);
}

// Rev May 26, this is no longer used since it
// was generating an extra req=portNumber call.
// Ensure mainIP, theMainPort, and shortServerName are set. The easiest way is to call
// swarmserver.pm#PutPortsAndShortnameAtEndOfBody(\$theBody); on the HTML for a page.
// See intramine_db_example.pl#OurPage() around l. 250 for an example of that.
// "callback" should take one argument and set the desired variable, eg
// function setWidgetName(value) {
// 	widgetName = value;
// }
// where 'widgetName' is in a larger scope containing the callback setWidgetName.
// See spinner.js for an example. 
function setConfigValue(configKey, callback) {
	let request = new XMLHttpRequest();	
	let theRequest = 'http://' + mainIP + ':' + theMainPort + '/' + shortServerName + '/?req=portNumber';
	request.open('get', theRequest, true);

	request.onload =
			function() {
				if (request.status >= 200 && request.status < 400)
					{
					// Success?
					let resp = request.responseText;
					if (isNaN(resp))
						{
						console.log('setConfigValue error, expected a number but received ' + resp);
						}
					else
						{
						setConfigValueWithPort(configKey, callback, resp);
						}
					}
				else
					{
					// We reached our target server, but it returned an error
					console.log('setConfigValue error, server reached but it could not handle request for port number!');
					}
			};

	request.onerror = function() {
		// There was a connection error of some sort
		console.log('setConfigValue connection error while attempting to retrieve port number!');
	};

	request.send();
}

// Not used.
function setConfigValueWithPort(configKey, callback, port) {
	let request = new XMLHttpRequest();	
	let theRequest = 'http://' + mainIP + ':' + port + '/' + shortServerName
					+ '/?req=configvalueforjs&key=' + encodeURIComponent(configKey);
	request.open('get', theRequest, true);

	request.onload =
			function() {
				if (request.status >= 200 && request.status < 400)
					{
					// Success?
					let resp = request.responseText;
					callback(resp);
					}
				else
					{
					// We reached our target server, but it returned an error
					console.log('setConfigValueWithPort error, server reached but it could not handle request for port number!');
					}
			};

	request.onerror = function() {
		// There was a connection error of some sort
		console.log('setConfigValueWithPort connection error while attempting to retrieve port number!');
	};

	request.send();
}