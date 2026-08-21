// horrible.js: horribleEscape() and horribleUnescape().
// Mainly for use with "tool tips" displayed by tooltip.js#showhint().
// There, hintContents comes from <a onmouseover=showhint(hintContents)..., and has <table>, <div>
// etc elements that won't display properly as-is. So they are "de-natured" or "escaped" in
// gloss.pm#Gloss() at the end with a call to horribleEscape(), replacing eg " with__DQUOTE_REP__
// and restored in tooltip.js#showhint()  by doing the opposite (horribleUnescape())
// just before display.


// Interim hack, replace troublesome characters (in description)
// with placeholders. These are undone when presenting description for
// editing, and also in gloss.pm#Gloss() when applying Gloss to the
// description.
function horribleEscape(text) {
	text = text.replace(/\=/g, '_EQR_');
	text = text.replace(/\"/g, '_DQR_');
	text = text.replace(/\'/g, '_SQR_');
	text = text.replace(/\+/g, '_PSR_');
	text = text.replace(/\%/g, '_PCR_');
	text = text.replace(/\&/g, '_AMR_');
	text = text.replace(/\\t/g, '_TR_');
	text = text.replace(/\\/g, '_BSR_');

	return(text);        
}

// Reverse of horribleEscape just above.
function horribleUnescape(text) {
	text = text.replace(/_EQR_/g, '=');
	text = text.replace(/_DQR_/g, '\"');
	text = text.replace(/_SQR_/g, '\'');
	text = text.replace(/_PSR_/g, '+');
	text = text.replace(/_PCR_/g, '%');
	text = text.replace(/_AMR_/g, '&');
	text = text.replace(/_TR_/g, '\\t');
	text = text.replace(/_BSR_/g, '\\');

	return(text);
}

function putRealQuotes(text) {
	text = text.replace(/\&quot;/g, '\"');

	return(text);
}
