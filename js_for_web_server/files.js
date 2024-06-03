/**
 * files.js: for intramine_filetree.pl. Uses jqueryFileTree.js to display two file browser
 * lists. All files that IntraMine can handle have Viewer links, and most also have Editor links.
 * Images are displayed in-window if the cursor pauses over them, elsewhere called "hover" images.
 * For that, see intramine_filetree.pl#GetDirsAndFiles().
 */

window.addEventListener("load", doResize);
window.addEventListener("resize", doResize);

let onMobile = false; // Set below, true if we have touch events.
if (typeof window.ontouchstart !== 'undefined')
	{
	onMobile = true;
	}

// Using an app for editing isn't possible on an iPad.
if (onMobile)
	{
	useAppForEditing = false;
	}

// Ask jqueryFileTree.js to cook up two file trees. Called at the bottom of this file.
function startFileTreeUp() {
	$('#scrollDriveListLeft').fileTree({
		root : 'C:/',
		script : 'http://' + theHost + ':' + thePort + '/',
		expandSpeed : 200,
		collapseSpeed : 200,
		multiFolder : true,
		pacifierID : 'spinner',
		remote : weAreRemote,
		allowEdit : allowEditing,
		useApp : useAppForEditing,
		mobile : onMobile
	}, function(el, file) {
		openTheFile(el, file);
	}, function(dir) {
		dummyCollapse(dir);
	}, function() {
		doResize();
	});

	$('#scrollDriveListRight').fileTree({
		root : 'C:/',
		script : 'http://' + theHost + ':' + thePort + '/',
		expandSpeed : 200,
		collapseSpeed : 200,
		multiFolder : true,
		pacifierID : 'spinner',
		remote : weAreRemote,
		allowEdit : allowEditing,
		useApp : useAppForEditing,
		mobile : onMobile
	}, function(el, file) {
		openTheFile(el, file);
	}, function(dir) {
		dummyCollapse(dir);
	}, function() {
		doResize();
	});

	if (typeof initialDirectoryPath !== 'undefined')
		{
		if (initialDirectoryPath !== '')
			{
			showDirectory(initialDirectoryPath);
			}
		}

	initNewFileDialog();
}

// Link clicked, respond by opening the file in IntraMine's Viewer or an editor, depending
// on which link for a file was clicked. The "edit" link is associated with an edit icon
// image, currently a tiny pencil.
function openTheFile(el, file) {
	let errM = document.getElementById(errorID);
	errM.innerHTML = '&nbsp;';

	// For some reason File Tree tacks a '/' on at end of file name.
	let trimmedFile = file.replace(/\/$/, '');
	trimmedFile = encodeURIComponent(trimmedFile);

	let sFieldType = el.toUpperCase();
	if (sFieldType === "IMG") // local or remote, **edit** pencil icon (not an "image")
		{
		if (useAppForEditing && !onMobile)
			{
			editWithPreferredApp(trimmedFile);
			}
		else // Use IntraMine's Editor service
			{
			editWithIntraMine(trimmedFile);
//			let url =
//			'http://' + theHost + ':' + theMainPort + '/' + editorShortName + '/?href=' + trimmedFile
//					+ '&rddm=' + String(getRandomInt(1, 65000));
//			window.open(url, "_blank");
			}
		}
	else
		// Viewer anchor, read only
		{
		let isVideo = false;
		const reVIDEO = /VIDEO$/;
		if (reVIDEO.test(trimmedFile))
			{
			isVideo = true;
			trimmedFile = trimmedFile.replace(reVIDEO, '');
			}

		let url =
		'http://' + theHost + ':' + theMainPort + '/' + viewerShortName + '/?href='
			+ trimmedFile + '&rddm=' + String(getRandomInt(1, 65000));
		
		if (isVideo)
			{
			openView(url, videoShortName);
			}
		else
			{
			window.open(url, "_blank");
			}
		}
}

async function openVideo(href) {
	const response = await fetch(href); // ignore response
}

function dummyCollapse(dir) {

}

// Re-init the tree display if a drive is selected using the drive dropdown at top of window.
function driveChanged(tree_id, value) {
	showSpinner();
	let e1 = document.getElementById(tree_id);
	e1.innerHTML = '';
	$('#' + tree_id).fileTree({
		root : value,
		script : 'http://' + theHost + ':' + thePort + '/',
		expandSpeed : 200,
		collapseSpeed : 200,
		multiFolder : true,
		pacifierID : 'spinner',
		remote : weAreRemote,
		allowEdit : allowEditing,
		useApp : useAppForEditing,
		mobile : onMobile
	}, function(el, file) {
		openTheFile(el, file);
	}, function(dir) {
		dummyCollapse(dir);
	}, function() {
		doResize();
	});
}

function doResize() {
	let el = document.getElementById(contentID);

	let pos = getPosition(el);
	let windowHeight = window.innerHeight;
	let elHeight = windowHeight - pos.y;
	el.style.height = elHeight - 20 + "px";

	let windowWidth = window.innerWidth;
	el.style.width = windowWidth - 4 + "px";
	
	// Temp, try adjusting fileTreeLeft and fileTreeRight height as well.
	el = document.getElementById('fileTreeLeft');
	pos = getPosition(el);
	elHeight = windowHeight - pos.y;
	el.style.height = elHeight - 20 + "px";

	el = document.getElementById('fileTreeRight');
	pos = getPosition(el);
	elHeight = windowHeight - pos.y;
	el.style.height = elHeight - 20 + "px";

	// Hide the spinner, and replace it with the help question mark.
	hideSpinner();
}

// This is for the "Open" button at the top of the window. If the associated text in
// the pathFieldElement looks like a full path, ask the Viewer to open it. For such a
// direct request, we can just ask the Main server to redirect to any running Viewer.
// Otherwise, for a presumed partial path, we would like to first ask the Viewer to provide
// a speculative full path for what was typed, and then open that full path in the Viewer.
// Which is what OpenAutoLink() does.
function openUserPath(oFormElement) {
	if (!oFormElement.action)
		{
		return;
		}
	let pathFieldElement = document.getElementById("openfile");
	let path = pathFieldElement.value;
	path = path.replace(/\\/g, "/");

	let fullPathMatch = /[a-zA-Z]\:\//.exec(path);
	if (fullPathMatch != null)
		{
		// href='http://192.168.1.132:81/Viewer/?href=c:/perlprogs/mine/images_for_web_server/ser
		// ver-128x128 60.png'
//		let url =
//				'http://' + theHost + ':' + theMainPort + '/Viewer/?href='
//						+ encodeURIComponent(path) + '&rddm=' + String(getRandomInt(1, 65000));
		let url =
		'http://' + theHost + ':' + theMainPort + '/' + viewerShortName + '/?href='
				+ encodeURIComponent(path) + '&rddm=' + String(getRandomInt(1, 65000));
		window.open(url, "_blank");
		}
	else
		{
		openAutoLink(path);
		}
}

// Request Linker port from main at theMainPort, then call Linker directly using
// the right port to get a fullPath, then get port for Viewer and ask Viewer to open the path.
async function  openAutoLink(path) {
	let errM = document.getElementById(errorID);
	errM.innerHTML = '&nbsp;';
	showSpinner();

	try {
		const linkerPort = await fetchPort(theHost, theMainPort, linkerShortName, errorID);
		if (linkerPort !== "")
			{
			hideSpinner();
			//openAutoLinkWithPort(path, linkerPort);
			const fullPath = await getFullPath(path, linkerPort);
			if (fullPath !== "")
				{
				const viewerPort = await fetchPort(theHost, theMainPort, viewerShortName, errorID);
				if (viewerPort !== "")
					{
					openFullPathWithViewerPort(fullPath, viewerPort);
					}
				}
			else {
				let e1 = document.getElementById(errorID);
				e1.innerHTML = 'No path found for ' + path;
				}
			}
		else
			{
			hideSpinner();
			}
	}
	catch(error) {
		let e1 = document.getElementById(errorID);
		e1.innerHTML = 'Connection error while attempting to open file!';
		hideSpinner();
	}
}

// Ask Linker to supply full path for partial path.
async function getFullPath(path, linkerPort) {
	let fullPath = "";

	try {
		let theAction = 'http://' + theHost + ':' + linkerPort + '/' + linkerShortName +
		'/?req=autolink&partialpath=' + encodeURIComponent(path);
		const response = await fetch(theAction);
		if (response.ok)
			{
			const thePath = await response.text();
			if (thePath !== 'nope')
				{
				fullPath = thePath;
				}
			}
		else
			{
			// We reached our target server, but it returned an error
			let e1 = document.getElementById(errorID);
			e1.innerHTML = 'Error, server reached but no full path found for ' + path + '!';
			}
	}
	catch(error) {
		// There was a connection error of some sort
		let e1 = document.getElementById(errorID);
		e1.innerHTML = 'Connection error: ' + error + '!';
	}

	return(fullPath);
}

function openFullPathWithViewerPort(fullPath, viewerPort) {
	let url =
	'http://' + theHost + ':' + viewerPort + '/' + viewerShortName + '/?href='
			+ encodeURIComponent(fullPath) + '&rddm='
			+ String(getRandomInt(1, 65000));
	let didit = window.open(url, "_blank");
	if (didit === null)
		{
		if (typeof window.ontouchstart !== 'undefined')
			{
			alert("Please turn off your browser's pop-up blocker, with"
					+ " Settings->Safari->Block Pop-ups or equivalent. If you're using"
					+ "Chrome, you can instead select 'Always show' at the bottom"
					+ "of this window.");
			}
		}
	}

// Shrink/expand the file tree on the right. Initially it is shrunk, most of the time
// only one tree is wanted. Probably.
function toggleRightListWidth() {
	let rightTree = document.getElementById('fileTreeRight');
	if (rightTree === null)
		{
		return;
		}
	let rightWidthStr = window.getComputedStyle(rightTree, null).getPropertyValue('width');
	let rightWidth = parseInt(rightWidthStr, 10);
	let treeContainer = document.getElementById('scrollAdjustedHeight');
	let treeWidthStr = window.getComputedStyle(treeContainer, null).getPropertyValue('width');
	let treeContainerWidth = parseInt(treeWidthStr, 10);
	let currentRightWidthPC = 100 * rightWidth / treeContainerWidth;
	
	if (currentRightWidthPC < 40) // right tree is shrunk down
		{
		document.getElementById('fileTreeRight').style.width = "48%";
		document.getElementById('fileTreeLeft').style.width = "48%";
		}
	else // both trees have equal width
		{
		document.getElementById('fileTreeRight').style.width = "28%";
		document.getElementById('fileTreeLeft').style.width = "70%";
		}
	}

function currentSortOrder() {
	let sortElem = document.getElementById( "sort_1" );
	return( sortElem.options[ sortElem.selectedIndex ].value );
	}

// See intramine_filetree.pl#FileTreePage() for the "onchange" that calls this.
// When sort changes, re-sort all open directory listings.
// This is done by simulated clicks, to collapse/expand the listings.
// A top-level listing requires two clicks, to collapse and the re-expand
// with the new sort order.
// A nested listing in a subdirectory is collapsed when its parent directory
// is collapsed, so a nested listing just needs one click to expand it again.
const reSortExpandedDirectoriesOnSortChange = async (relQuery, depth) => {
	let leftList = document.getElementById("scrollDriveListLeft");
	let rightList = document.getElementById("scrollDriveListRight");
	let leftTop = leftList.scrollTop;
	let rightTop = rightList.scrollTop;
	let fileLists = [leftList, rightList];
	let openRels1 = [];
	let nestingLevel1 = [];
	let openRels2 = [];
	let nestingLevel2 = [];

	// Get the anchor 'rel' and directory depth for all expanded directories.
	for (let lIndex = 0; lIndex < 2; ++lIndex)
		{
		let dirList = fileLists[lIndex].getElementsByClassName('directory');
		for (let i = 0; i < dirList.length; ++i)
			{
			let dir = dirList[i];
			if (hasClass(dir, 'expanded'))
				{
				// Get the anchor inside, first child of the dir.
				let anchor = dir.firstChild;
				if (anchor !== null)
					{
					let rel = anchor.attributes.rel.value;
					let level = depthForDir(dir);
					if (lIndex == 0)
						{
						openRels1.push(rel);
						nestingLevel1.push(level);
						}
					else
						{
						openRels2.push(rel);
						nestingLevel2.push(level);
						}
					}
				}
			}
		}

	for (let lIndex = 0; lIndex < 2; ++lIndex)
		{
		let openRels = (lIndex == 0) ? openRels1: openRels2;
		let nestingLevel = (lIndex == 0) ? nestingLevel1: nestingLevel2;
		for (let i = 0; i < openRels.length; ++i)
			{
			let relval = openRels[i];
			let depth = nestingLevel[i];
			let relQuery = '[rel=' + '"' + relval + '"]';
	
			let ank = fileLists[lIndex].querySelectorAll(relQuery)[0];
			let ankAntiBreakCount = 0;
			while (typeof ank === 'undefined' && ++ankAntiBreakCount < 40)
				{
				await delay(100);
				ank = fileLists[lIndex].querySelectorAll(relQuery)[0];
				}
	
			
			if (ank !== null)
				{
				// Click at least once on all dirs that want expansion.
				// Click a second time on top level dirs (depth 0).
				directoryExpansionFinished = false;

				ank.click();

				let antiBreakCount = 0;
				while (!directoryExpansionFinished && ++antiBreakCount < 20)
					{
					await delay(100);
					}
				directoryExpansionFinished = false;
				if (antiBreakCount >= 20)
					{
					console.log("Directory expansion is taking too long, giving up.");
					break;
					}
			
				if (depth == 0)
					{
					directoryExpansionFinished = false;
					ank.click();
					let antiBreakCount = 0;
					while (!directoryExpansionFinished && ++antiBreakCount < 20)
						{
						await delay(100);
						}
					directoryExpansionFinished = false;
					if (antiBreakCount >= 20)
						{
						console.log("Directory expansion is taking too long, giving up.");
						break;
						}
					}
				}
			}
		}

	leftList.scrollTop = leftTop;
	rightList.scrollTop = rightTop;
	}

function depthForDir(dir) {
	let depth = 0;
	while (dir)
		{
		dir = dir.parentNode;

		if (dir !== null && hasClass(dir, 'expanded'))
			{
			++depth;
			}
		}

	return(depth);
	}

// After starting up, expand left directory list to show
// the contents of the directory path in dirPath. This is done
// by simulating clicks on the directory names as we drill down.
// Typical URL:
// http://192.168.40.8:43130/Files/?req=main&directory=file:///C:/perlprogs/intramine/test/
async function showDirectory(dirPath) {
	// Decode: this goes with
	// $initialDirectory = uri_encode($initialDirectory);
	// near bottom of intramine_filetree.pl#FileTreePage().
	dirPath = decodeURIComponent(dirPath);

	let leftList = document.getElementById("scrollDriveListLeft");
	let openRels = [];
	let lastSlashIndex = dirPath.lastIndexOf("/");
	let dirPathLength = dirPath.length;
	if (lastSlashIndex === dirPathLength - 1)
		{
		dirPath = dirPath.substring(0, lastSlashIndex);
		}
	let spuriousFilesIndex = dirPath.indexOf("file:///");
	if (spuriousFilesIndex === 0)
		{
		dirPath = dirPath.substring(8); // 8 == length of file:///
		}
	const dirPathParts = dirPath.split("/");
	let progressivelyDeeperPath = '';

	for (let j = 0; j < dirPathParts.length; ++j)
		{
		progressivelyDeeperPath += dirPathParts[j] + "/";
		openRels.push(progressivelyDeeperPath);
		}
	
	// Handle drive first.
	driveChanged('scrollDriveListLeft', openRels[0]);
	let theDrive = openRels[0];
	theDrive = theDrive.substring(0, theDrive.length - 1);
	let eid = document.getElementById('driveselector_1');
	eid.value = openRels[0];

	await delay(500);

	for (let i = 1; i < openRels.length; ++i)
		{
		let relval = openRels[i];
		let relQuery = '[rel=' + '"' + relval + '"]';
		
		
		let ank = leftList.querySelectorAll(relQuery)[0];
		let ankAntiBreakCount = 0;
		while (typeof ank === 'undefined' && ++ankAntiBreakCount < 40)
			{
			await delay(100);
			ank = leftList.querySelectorAll(relQuery)[0];
			}

		if (typeof ank !== 'undefined')
			{
			directoryExpansionFinished = false;

			ank.click();

			let antiBreakCount = 0;
			while (!directoryExpansionFinished && ++antiBreakCount < 60)
				{
				await delay(100);
				}
			directoryExpansionFinished = false;
			if (antiBreakCount >= 20)
				{
				console.log("Directory expansion is taking too long, giving up.");
				break;
				}
		
			if (i == openRels.length - 1)
				{
				scrollFolderIntoView(leftList, ank);
				}
			}
		else
			{
			console.log("Error, could not open " + relval);
			break;
			}
		}
}

// Scroll the left list of folders so that the folder associated
// with element "ank" is scrolled into view.
// From
// https://stackoverflow.com/questions/635706/how-to-scroll-to-an-element-inside-a-div
// with a little fine tuning since leftList is not at the top of the page.
function scrollFolderIntoView(leftList, ank) {
	let topPos = ank.offsetTop;
	let listTop = getPosition(leftList);
	let newTop = topPos - listTop.y;
	if (newTop >= 0)
		{
		leftList.scrollTop = newTop;
		}
	else
		{
		leftList.scrollTop = topPos;
		}
}

function setSelectBoxByText(id, etxt) {
	let eid = document.getElementById(id);
     for (var i = 0; i < eid.options.length; ++i) {
        if (eid.options[i].text === etxt) {
			eid.options[i].selected = true;
			}
		}
}


const delay = ms => new Promise(res => setTimeout(res, ms));

window.addEventListener("load", startFileTreeUp);
