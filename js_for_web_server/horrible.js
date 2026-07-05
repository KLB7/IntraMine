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
	text = text.replace(/\=/g, '__EQUALSIGN_REP__');
	text = text.replace(/\"/g, '__DQUOTE_REP__');
	text = text.replace(/\'/g, '__ONEQUOTE_REP__');
	text = text.replace(/\+/g, '__PLUSSIGN_REP__');
	text = text.replace(/\%/g, '__PERCENTSIGN_REP__');
	text = text.replace(/\&/g, '__AMPERSANDSIGN_REP__');
	text = text.replace(/\\t/g, '__TABERINO__');
	text = text.replace(/\\/g, '__BSINO__');

	return(text);        
}

// Reverse of horribleEscape just above.
function horribleUnescape(text) {
	text = text.replace(/__EQUALSIGN_REP__/g, '=');
	text = text.replace(/__DQUOTE_REP__/g, '\"');
	text = text.replace(/__ONEQUOTE_REP__/g, '\'');
	text = text.replace(/__PLUSSIGN_REP__/g, '+');
	text = text.replace(/__PERCENTSIGN_REP__/g, '%');
	text = text.replace(/__AMPERSANDSIGN_REP__/g, '&');
	text = text.replace(/__TABERINO__/g, '\\t');
	text = text.replace(/__BSINO__/g, '\\');


	return(text);
}
