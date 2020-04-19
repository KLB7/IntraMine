// wordAtInsertionPt.js
// See https://stackoverflow.com/questions/2444430/how-to-get-a-word-under-cursor-using-javascript 
// soln by Drakes https://stackoverflow.com/users/1938889/drakes
// (Modified from the original.)
// In IntraMine, getFullWord() is called by viewerStart.js#expandSelectionToWordIfPossible(),
// the goal being to select a whole word with one click when in a non-Editable view of a file.

// Get the full word the cursor is over regardless of span breaks
function getFullWord(event) {
let i, begin, end, range, textNode, offset;

// Internet Explorer
if (document.body.createTextRange) {
   try {
	 range = document.body.createTextRange();
	 range.moveToPoint(event.clientX, event.clientY);
	 range.select();
	 range = getTextRangeBoundaryPosition(range, true);
  
	 textNode = range.node;
	 offset = range.offset;
   } catch(e) {
   return(document.createRange()); // Sigh, IE
   }
}

// Firefox, Safari
// REF: https://developer.mozilla.org/en-US/docs/Web/API/Document/caretPositionFromPoint
else if (document.caretPositionFromPoint) {
  range = document.caretPositionFromPoint(event.clientX, event.clientY);
  if (range !== null)
	  {
	  textNode = range.offsetNode;
	  offset = range.offset;
	  }
  else
	  {
	  return(document.createRange());
	  }

  // Chrome
  // REF: https://developer.mozilla.org/en-US/docs/Web/API/document/caretRangeFromPoint
} else if (document.caretRangeFromPoint) {
  range = document.caretRangeFromPoint(event.clientX, event.clientY);
  if (range !== null)
	  {
	  textNode = range.startContainer;
	  offset = range.startOffset;
	  }
  else
	  {
	  return(document.createRange());
	  }
}

// Only act on text nodes
if (!textNode || textNode.nodeType !== Node.TEXT_NODE) {
	return(document.createRange());
}

let data = textNode.textContent;

// Sometimes the offset can be at the 'length' of the data.
// It might be a bug with this 'experimental' feature - 
// compensate for this below
if (offset >= data.length) {
  offset = data.length - 1;
}

// Scan behind the current character until whitespace or punct is found, or beginning
i = begin = end = offset;
// Don't scan behind if we're at the end of a line and last char is not a word char.
let blockedAtLineEnd = ( offset === data.length - 1 && isW(data[offset]) );
if (!blockedAtLineEnd)
	{
	while ( previousCharIsAWordChar(data, i - 1) ) {
	  //while (i > 0 && !isW(data[i - 1])) {
	  i--;
	  }
	}
begin = i;

// Scan ahead of the current character until whitespace or punct is found, or end
// unless char at offset is not a word char.
i = offset;
let offsetIsWordChar = nextCharIsAWordChar(data, offset);
if (nextCharIsAWordChar(data, i))
	{
	while ( nextCharIsAWordChar(data, i + 1) ) {
	//while (i < data.length - 1 && !isW(data[i + 1])) {
	  i++;
	}
	}
end = i;

// This is our temporary word
let word = data.substring(begin, end + 1);

// If at a node boundary, cross over and see what 
// the next word is and check if this should be added to our temp word
if (end === data.length - 1 || begin === 0) {

  let nextNode = getNextNode(textNode);
  let prevNode = getPrevNode(textNode);

  // Get the next node text
  if (end == data.length - 1 && nextNode) {
  let nextText = nextNode.textContent;

	// Add the letters from the next text block until a whitespace or punct, or end
	i = 0;
	while ( nextCharIsAWordChar(nextText, i) ) {
	  word += nextText[i++];
	}

  } else if (begin === 0 && prevNode) {
	// Get the previous node text
  let prevText = prevNode.textContent;

	// Add the letters from the next text block until a whitespace or punct, or end
	i = prevText.length - 1;
	while ( previousCharIsAWordChar(prevText, i) ) {
	  word = prevText[i--] + word;
	}
  }
}

// Sometimes a bad last char is tacked on?
if (word.length)
	{
	word = remove_linebreaks(word);
//	if (isW(word[ word.length - 1]))
//		{
//		word = word.substring(0, word.length - 1);
//		}
	}

// Return the word, and its start and end offsets. Kill selection of '.' or other non-word
// if click happened past end of line and the line ends in non-word char such as '.'.
if (blockedAtLineEnd)
	{
	word = '';
	begin = end;
	}
else
	{
	if (offsetIsWordChar)
		{
		++end;
		}
	}

let obj = {
		theWord: word,
		theBegin: begin,
		theEnd: end
		};

return(obj);

//return word;
} // getFullWord()


// Helper functions

function remove_linebreaks(str ) { 
return str.replace( /[\r\n]+/gm, "" ); 
} 

// Looking in the forward direction, either char is not white or punctuation,
// or it is an apostrophe or hyphen and the following char is not white or punctuation.
function nextCharIsAWordChar(theText, i) {
	let result = ( i < theText.length 
		&& (!isW(theText[i])
		  || ((theText[i] === "'" || theText[i] === "-") && (i+1) < theText.length && !isW(theText[i+1])))
		  );
	return(result);
	}

// Looking in reverse, either char is not white or punctuation,
// or it is an apostrophe or hyphen and the previous char is not white or punctuation.
function previousCharIsAWordChar(theText, i) {
	let result = ( i >= 0 
		&& (!isW(theText[i])
		  || ((theText[i] === "'" || theText[i] === "-") && i > 0 && !isW(theText[i-1])))
		  );
	return(result);
	}


// Barrier nodes are BR, DIV, P, PRE, TD, TR, ... 
function isBarrierNode(node) {
return node ? /^(BR|DIV|P|PRE|TD|TR|TABLE)$/i.test(node.nodeName) : true;
}

// Try to find the next adjacent node
function getNextNode(node) {
let n = null;
// Does this node have a sibling?
if (node.nextSibling) {
n = node.nextSibling;

// Doe this node's container have a sibling?
} else if (node.parentNode && node.parentNode.nextSibling) {
n = node.parentNode.nextSibling;
}
return isBarrierNode(n) ? null : n;
}

// Try to find the prev adjacent node
function getPrevNode(node) {
var n = null;

// Does this node have a sibling?
if (node.previousSibling) {
n = node.previousSibling;

// Doe this node's container have a sibling?
} else if (node.parentNode && node.parentNode.previousSibling) {
n = node.parentNode.previousSibling;
}
return isBarrierNode(n) ? null : n;
}

// REF: http://stackoverflow.com/questions/3127369/how-to-get-selected-textnode-in-contenteditable-div-in-ie
function getChildIndex(node) {
var i = 0;
while( (node = node.previousSibling) ) {
i++;
}
return i;
}

// All this code just to make this work with IE, OTL
// REF: http://stackoverflow.com/questions/3127369/how-to-get-selected-textnode-in-contenteditable-div-in-ie
function getTextRangeBoundaryPosition(textRange, isStart) {
var workingRange = textRange.duplicate();
workingRange.collapse(isStart);
var containerElement = workingRange.parentElement();
var workingNode = document.createElement("span");
var comparison, workingComparisonType = isStart ?
"StartToStart" : "StartToEnd";

var boundaryPosition, boundaryNode;

// Move the working range through the container's children, starting at
// the end and working backwards, until the working range reaches or goes
// past the boundary we're interested in
do {
containerElement.insertBefore(workingNode, workingNode.previousSibling);
workingRange.moveToElementText(workingNode);
} while ( (comparison = workingRange.compareEndPoints(
workingComparisonType, textRange)) > 0 && workingNode.previousSibling);

// We've now reached or gone past the boundary of the text range we're
// interested in so have identified the node we want
boundaryNode = workingNode.nextSibling;
if (comparison == -1 && boundaryNode) {
// This must be a data node (text, comment, cdata) since we've overshot.
// The working range is collapsed at the start of the node containing
// the text range's boundary, so we move the end of the working range
// to the boundary point and measure the length of its text to get
// the boundary's offset within the node
workingRange.setEndPoint(isStart ? "EndToStart" : "EndToEnd", textRange);

boundaryPosition = {
  node: boundaryNode,
  offset: workingRange.text.length
};
} else {
// We've hit the boundary exactly, so this must be an element
boundaryPosition = {
  node: containerElement,
  offset: getChildIndex(workingNode)
};
}

// Clean up
workingNode.parentNode.removeChild(workingNode);

return boundaryPosition;
}
