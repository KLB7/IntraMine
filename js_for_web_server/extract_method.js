// extract_method.js: JS for intramine_EM.pl (Extract Method for Perl).

let src = '';

hideSpinner();


//inputArea.addEventListener('oninput', showParamDialog);

function onPaste() {
    const inputArea = document.querySelector('#textarea_source');
    src = inputArea.value;
    let callDiv = document.getElementById('final_sub_name');
    callDiv.innerHTML = '';
    let methodDiv = document.getElementById('extracted_method');
    methodDiv.innerHTML = '';
    showParamDialog(src);
}

async function showParamDialog(text) {
    showSpinner();
    text = encodeURIComponent(text);
    try {
         let theAction = 'http://' + theHost + ':' + thePort + '/' + shortServerName + '/dialog/?contents=' + text;

        //console.log("Action: |" + theAction + "|");

        // const response = await fetch(theAction, {
        // method: "POST",
        // Body: text
        // });

    const response = await fetch(theAction);

    if (response.ok)
        {
        let textBack = await response.text();
         //let textBack = decodeURIComponent(await response.text());
        //console.log("Paste to Perl returned: |" + textBack + "|");
        let dialogDiv = document.getElementById('dialogDiv');
        dialogDiv.innerHTML = textBack;
        hideSpinner();
        }
    else
        {
        // We reached our target server, but it returned an error
		let e1 = document.getElementById(errorID);
		e1.innerHTML = '<p>Error, server reached but it did not return a useful result.';
        hideSpinner();
        }
    }
    catch(error) {
        // There was a connection error of some sort
	    let e1 = document.getElementById(errorID);
	    e1.innerHTML = 'Connection error! ' + error;
        hideSpinner();
    }

}

async function paramFormSubmit(oFormElement) {
    showSpinner();
    let sendBack = params(oFormElement);
    sendBack += '&contents=' + encodeURIComponent(src);
    try {
		let theAction = oFormElement.action + '&params=' + sendBack;
        const response = await fetch(theAction);

        if (response.ok)
			{
			let textBack = await response.text();
            let lines = textBack.split("\n");
            let exampleCall = lines[0];
            let callDiv = document.getElementById('final_sub_name');
            callDiv.innerHTML = exampleCall;

            if (lines.length >= 3)
                {
                let extractedSub = lines[2];

                for (let i = 3; i < lines.length; ++i)
                    {
                    extractedSub += "\n" + lines[i];
                    }
                let methodArea = document.getElementById('extracted_method');
                let rows = lines.length;
                if (rows > 50)
                    {
                    rows = 50;
                    }
                methodArea.rows = rows;
                methodArea.innerHTML = extractedSub;
            }

            hideSpinner();
            }
        else
            {
            let e1 = document.getElementById(errorID);
            e1.innerHTML = '<p>Error, server reached but it returned an error!</p>';
            hideSpinner();
            }
    }
	catch(error) {
		// There was a connection error of some sort
		let e1 = document.getElementById(errorID);
		e1.innerHTML = 'Connection error! ' + error;
		hideSpinner();
	}
}

function params(oFormElement) {
    let theParams = '';
    let oField, sFieldType = "";

    for (let nItem = 0; nItem < oFormElement.elements.length; nItem++)
        {
        oField = oFormElement.elements[nItem];
        if (!oField.hasAttribute("name")) { continue; }
        sFieldType = oField.nodeName.toUpperCase() === "INPUT" ? oField.getAttribute("type").toUpperCase() : "TEXT";
        if ((sFieldType !== "RADIO" && sFieldType !== "CHECKBOX") || oField.checked)
            {
            // TEST ONLY
            // console.log("Param " + encodeURIComponent('PARAM_' + oField.name) + ", val |" + encodeURIComponent(oField.value) + "|");
            theParams += "&" + encodeURIComponent('PARAM_' + oField.name) + "=" + encodeURIComponent(oField.value);
            }
        }

    return(theParams);
}

function doResize() {
	let el = document.getElementById(contentID); // default 'scrollAdjustedHeight
	let pos = getPosition(el);
	let windowHeight = window.innerHeight;
	el.style.height = ((windowHeight - pos.y - 40) / windowHeight) * 100 + "%";

	let windowWidth = window.innerWidth;
	el.style.width = windowWidth - 4 + "px";
}

window.addEventListener("load", doResize);
window.addEventListener("resize", doResize);
