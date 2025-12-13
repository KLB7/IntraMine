// showDiffDetails.js: show git diff HEAD detailed changes
// around a line, on click in the "cmGitDiffGutter" erm gutter.

function addDiffClickHandler(editor) {
    editor.on("gutterClick", async function(cm, n) {
    var clickedLineNumber = n + 1;
    //console.log("Clicked line number:", clickedLineNumber);
    
    try {
		const port = await fetchPort(mainIP, theMainPort, linkerShortName, '');
		if (port !== "")
			{
            showDiffsWithPort(clickedLineNumber, port);
			}
	}
	catch(error) {
		return;
	}
    });
}

async function showNonCMDiffDetails(elem) {
    // Get line number.
    let lineNum = lineNumberForFirstTD(elem);
    if (lineNum === 0)
        {
        return;
        }

        try {
            const port = await fetchPort(mainIP, theMainPort, linkerShortName, '');
            if (port !== "")
                {
                showDiffsWithPort(lineNum, port);
                }
        }
        catch(error) {
            return;
        }
}

function lineNumberForFirstTD(elem) {
    let elemN = elem.getAttribute('n'); // eg "58 |"
    let lineNum = parseInt(elemN, 10);
    //console.log("lineNum: |" + lineNum + "|");
    return(lineNum);
}

async function showDiffsWithPort(clickedLineNumber, port) {
    let theAction = 'http://' + mainIP + ':' + port + '/?req=specificgitdiffs&first=' + clickedLineNumber + '&last=0' + '&path=' + encodeURIComponent(thePath);

     try {
		const response = await fetch(theAction);
		if (response.ok)
			{
			let text = await response.text();
			if (text !== '' && text !== ' ')
				{
				if (text !== 'nope')
					{
					text = text.replace(/%2B/g, "+");
                    text = decodeURIComponent(text);
					//text = text.replace(/__IMSPC__/g, " ");
                    let diffPopupElement = document.getElementById('uniqueDiffSpecificsOverlay');
                    if (diffPopupElement !== null)
                        {
                        let diffActualContentElement = document.getElementById('theActualDiffs');
                        if (diffActualContentElement !== null)
                            {
                            diffActualContentElement.innerHTML = text;
                            // TODO set top of popup.
                            diffPopupElement.style.display = 'flex';
                            setPopupDetails();
                            }
                        }
                    
					// Show the definition links via tooltip.js#showhint().
					//showhint(hintContent, event.target, event, '500px', false); 
					}
				}
			else
				{
				// TEST ONLY
				//console.log("text is empty.");
				}
			}
		else
			{
			// We reached our target server, but it returned an error
			// TEST ONLY
			//console.log("We reached our target server, but it returned an error");
			return;
			}
	}
	catch(error) {
		// TEST ONLY
		//console.log("Try failed.");

		return;
	}
}

function setPopupDetails() {
    //console.log("TOP of setPopupDetails");

    let diffContentElement = document.getElementById("diffContentId");
    if (diffContentElement === null)
        {
        //console.log("NO diffContentId!");
        return;
        }
    const tabl = document.getElementById("thisisthetablefordiffdetails");
    if (tabl === null)
        {
        //console.log("NO thisisthetablefordiffdetails!");
        return;
        }

     const totalRowCount = tabl.rows.length;
    let originalRowCount = totalRowCount;
    let newRowCount = totalRowCount;

    //console.log("Original row count: |" + totalRowCount + "|");
 
    // Adjust totalRowCount for long lines.
    for (let i = 0; i < tabl.rows.length; ++i)
        {
        //console.log("Row " + i);
        let row = tabl.rows[i];
        let lineCell = row.cells[1]; // The line of text
        let lineCellText = lineCell.textContent;
        let lineLength = lineCellText.length;
        //console.log("Initial line length: |" + lineLength + "|");
        lineLength = lineLength - 76;
        while (lineLength > 76)
            {
            ++newRowCount;
            lineLength = lineLength - 76;
            }
        }

    let rowHeight = newRowCount * 23 + 60;

    // TEST ONLY
    //console.log("original |" + originalRowCount + " vs total |" + newRowCount + "|");

    let windowHeight = (window.innerHeight - 100) * 0.8; // 80% by default
    //console.log("rowHeight: |" + rowHeight + "|");
    //console.log("window.innerHeight: |" + window.innerHeight + "|");
    if (rowHeight < windowHeight)
        {
        let newHeightPC = (rowHeight / window.innerHeight) * 100;
        diffContentElement.style.height = newHeightPC + "%";
        }

    const btn = document.getElementById("closeDiffsButtonId");
    if (btn)
        {
        btn.scrollIntoView();
        }
    // const targetRow = tabl.rows[0];
    // if (targetRow)
    //     {
    //     targetRow.scrollIntoView(); 
    //     }

}

function closeDiffPopup() {
	document.getElementById('uniqueDiffSpecificsOverlay').style.display = 'none';
}
