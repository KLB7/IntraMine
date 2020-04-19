/* intramine_config.js
Retrieve a configuration value from any running IntraMine swarmserver
(for back end see swarmserver.pm#ConfigValue())
*/

// Ensure mainIP, theMainPort, and shortServerName are set. The easiest way is to call
// swarmserver.pm#PutPortsAndShortnameAtEndOfBody(\$theBody); on the HTML for a page.
// See intramine_db_example.pl#OurPage() around l. 245 for an example of that.
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