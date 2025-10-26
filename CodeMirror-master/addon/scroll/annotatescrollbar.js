// CodeMirror, copyright (c) by Marijn Haverbeke and others
// Distributed under an MIT license: https://codemirror.net/5/LICENSE

// Added for more precise markers.
//let arrowHeight = 18; // Needed for PC only.

(function(mod) {
  if (typeof exports == "object" && typeof module == "object") // CommonJS
    mod(require("../../lib/codemirror"));
  else if (typeof define == "function" && define.amd) // AMD
    define(["../../lib/codemirror"], mod);
  else // Plain browser env
    mod(CodeMirror);
})(function(CodeMirror) {
  "use strict";

  CodeMirror.defineExtension("annotateScrollbar", function(options) {
    if (typeof options == "string") options = {className: options};
    return new Annotation(this, options);
  });

  CodeMirror.defineOption("scrollButtonHeight", 0);

  function Annotation(cm, options) {
    this.cm = cm;
    this.options = options;
    this.buttonHeight = options.scrollButtonHeight || cm.getOption("scrollButtonHeight");
    this.annotations = [];
    this.doRedraw = this.doUpdate = null;
    this.div = cm.getWrapperElement().appendChild(document.createElement("div"));
    this.div.style.cssText = "position: absolute; right: 0; top: 0; z-index: 7; pointer-events: none";
    this.computeScale();

    function scheduleRedraw(delay) {
      clearTimeout(self.doRedraw);
      self.doRedraw = setTimeout(function() { self.redraw(); }, delay);
    }

    var self = this;
    cm.on("refresh", this.resizeHandler = function() {
      clearTimeout(self.doUpdate);
      self.doUpdate = setTimeout(function() {
        if (self.computeScale()) scheduleRedraw(20);
      }, 100);
    });
    cm.on("markerAdded", this.resizeHandler);
    cm.on("markerCleared", this.resizeHandler);
    if (options.listenForChanges !== false)
      cm.on("changes", this.changeHandler = function() {
        scheduleRedraw(250);
      });
  }

  Annotation.prototype.computeScale = function() {
    var cm = this.cm;
	  
	// REVISION improve accuracy of marker placement by correcting hScale.
  let rect = markerMainElement.getBoundingClientRect();
	let yTop = rect.top;
	let yBottom = rect.bottom;
	let textViewableHeight = yBottom - yTop;
	let viewWidth = rect.right - rect.left;
	let mainScrolllHeight = 0;
	let widthDifference = 0;
	let heightDifference = 0;
	let haveVerticalScroll = false;
	let haveHorizontalScroll = false;

  let scrollEl = cm.getWrapperElement().querySelector('.CodeMirror-scroll');
  mainScrolllHeight = scrollEl.scrollHeight;
  widthDifference = cm.getScrollerElement().offsetWidth - cm.getScrollerElement().clientWidth;
  //widthDifference = cm.getWrapperElement().offsetWidth - cm.getScrollerElement().clientWidth;
  heightDifference = cm.getWrapperElement().offsetHeight - cm.getScrollerElement().clientHeight;
  if (scrollEl.scrollHeight > scrollEl.clientHeight)
    {
    haveVerticalScroll = true;
    }
  if (scrollEl.scrollWidth > scrollEl.clientWidth)
    {
    haveHorizontalScroll = true;
    }
	
	let arrowMultiplier = 2;
	if (typeof window.ontouchstart !== 'undefined')
		{
		arrowHeight = 2;
		}
	else
		{
		if (haveVerticalScroll)
			{
			if (widthDifference > 6.0 && widthDifference < 30.0)
				{
				arrowHeight = widthDifference;
				}
			if (haveHorizontalScroll)
				{
				arrowMultiplier = 3;
				}
			}
		else
			{
			arrowHeight = 0;
			}
		}

	let usableTextHeight = textViewableHeight - arrowMultiplier * arrowHeight;
	
	if (mainScrolllHeight > usableTextHeight)
		{
		let indicatorHeight = usableTextHeight * (textViewableHeight/(mainScrolllHeight));
		indicatorM =
					(usableTextHeight - indicatorHeight) / (mainScrolllHeight - textViewableHeight);
    }

	
    if (indicatorM != this.hScale) {
      this.hScale = indicatorM;
      return true;
    }
  };


  Annotation.prototype.update = function(annotations) {
    this.annotations = annotations;
    this.redraw();
  };

  Annotation.prototype.redraw = function(compute) {
    if (compute !== false) this.computeScale();
    var cm = this.cm, hScale = this.hScale;

    var frag = document.createDocumentFragment(), anns = this.annotations;

    var wrapping = cm.getOption("lineWrapping");
    var singleLineH = wrapping && cm.defaultTextHeight() * 1.5;
    var curLine = null, curLineObj = null;

    function getY(pos, top) {
      if (curLine != pos.line) {
        curLine = pos.line
        curLineObj = cm.getLineHandle(pos.line)
        var visual = cm.getLineHandleVisualStart(curLineObj)
        if (visual != curLineObj) {
          curLine = cm.getLineNumber(visual)
          curLineObj = visual
        }
      }
      if ((curLineObj.widgets && curLineObj.widgets.length) ||
          (wrapping && curLineObj.height > singleLineH))
        return cm.charCoords(pos, "local")[top ? "top" : "bottom"];
      var topY = cm.heightAtLine(curLineObj, "local");
      return topY + (top ? 0 : curLineObj.height);
    }

    var lastLine = cm.lastLine()
 	// HORRIBLE TEMPORARY HACK!
   if (typeof window.ontouchstart !== 'undefined')
    {
    cm.display.barWidth = 17;
    }

  // Adjust top and bottom by arrowHeight.
  // (to allow for the top arrow in the scroll bar).
  let widthDifference = cm.getScrollerElement().offsetWidth - cm.getScrollerElement().clientWidth;
  let arrowHeight = widthDifference;
  if (cm.display.barWidth) for (var i = 0, nextTop; i < anns.length; i++) {
      var ann = anns[i];
      if (ann.to.line > lastLine) continue;
      var top = nextTop || getY(ann.from, true) * hScale; + arrowHeight;
      var bottom = getY(ann.to, false) * hScale; + arrowHeight;
      while (i < anns.length - 1) {
        if (anns[i + 1].to.line > lastLine) break;
        nextTop = getY(anns[i + 1].from, true) * hScale; + arrowHeight;
        if (nextTop > bottom + .9) break;
        ann = anns[++i];
        bottom = getY(ann.to, false) * hScale; + arrowHeight;
      }
      if (bottom == top) continue;
      var height = Math.max(bottom - top, 3);

      var elt = frag.appendChild(document.createElement("div"));
      elt.style.cssText = "position: absolute; right: 0px; width: " + Math.max(cm.display.barWidth - 1, 2) + "px; top: "
        + (top + arrowHeight) + "px; height: " + height + "px";
      elt.className = this.options.className;
      if (ann.id) {
        elt.setAttribute("annotation-id", ann.id);
      }
    }
    this.div.textContent = "";
    this.div.appendChild(frag);
  };

  Annotation.prototype.clear = function() {
    this.cm.off("refresh", this.resizeHandler);
    this.cm.off("markerAdded", this.resizeHandler);
    this.cm.off("markerCleared", this.resizeHandler);
    if (this.changeHandler) this.cm.off("changes", this.changeHandler);
    this.div.parentNode.removeChild(this.div);
  };
});
