// jQuery File Tree Plugin
//
// Version 1.01
//
// Cory S.N. LaViska
// A Beautiful Site (http://abeautifulsite.net/)
// 24 March 2008
//
// Visit http://abeautifulsite.net/notebook.php?article=58 for more information
//
// Usage: $('.fileTreeDemo').fileTree( options, callback )
//
// Options:  root           - root folder to display; default = /
//           script         - location of the serverside AJAX file to use; default = jqueryFileTree.php
//           folderEvent    - event to trigger expand/collapse; default = click
//           expandSpeed    - default = 500 (ms); use -1 for no animation
//           collapseSpeed  - default = 500 (ms); use -1 for no animation
//           expandEasing   - easing function to use on expand (optional)
//           collapseEasing - easing function to use on collapse (optional)
//           multiFolder    - whether or not to limit the browser to one subfolder at a time
//           loadMessage    - Message to display while initial tree loads (can be HTML)
//
// History:
//
// 1.01 - updated to work with foreign characters in directory/file names (12 April 2008)
// 1.00 - released (24 March 2008)
//
// TERMS OF USE
// 
// This plugin is dual-licensed under the GNU General Public License and the MIT License and
// is copyright 2008 A Beautiful Site, LLC. 
//
// Lightly modifed from the original 2019, to include remote, mobile, and selectDirectories.
// And the memorable "h" function has been renamed to "action". I might have also added the
// "resizeUs", a couple of years ago, sorry I forget.
if(jQuery) (function($){
	
	$.extend($.fn, {
		fileTree: function(o, action, collapseAction, resizeUs) {
			// Defaults
			if( !o ) var o = {};
			if( o.root == undefined ) o.root = '/';
			if( o.script == undefined ) o.script = 'jqueryFileTree.php';
			if( o.folderEvent == undefined ) o.folderEvent = 'click';
			if( o.expandSpeed == undefined ) o.expandSpeed= 500;
			if( o.collapseSpeed == undefined ) o.collapseSpeed= 500;
			if( o.expandEasing == undefined ) o.expandEasing = null;
			if( o.collapseEasing == undefined ) o.collapseEasing = null;
			if( o.multiFolder == undefined ) o.multiFolder = true;
			if( o.loadMessage == undefined ) o.loadMessage = 'Loading...';
			if( o.pacifierID == undefined ) o.pacifierID = 'spinner';
			if( o.remote == undefined ) o.remote = true;
			if( o.allowEdit == undefined ) o.allowEdit = false;
			if( o.useApp == undefined ) o.useApp = true;
			if( o.mobile == undefined ) o.mobile = false;
			if( o.selectDirectories == undefined ) o.selectDirectories = false;
			
			$(this).each( function() {
				
				function showTree(c, t) {
					document.getElementById(o.pacifierID).style.display = '';
					$(c).addClass('wait');
					$(".jqueryFileTree.start").remove();
					
					let sortOrder = currentSortOrder(); // files.js#currentSortOrder().
					
					// get also works.
					//$.get(o.script + '/?dir=' + t, function(data) {					
					$.post(o.script, { dir: t, rmt: o.remote, edt: o.allowEdit, app: o.useApp, mobile: o.mobile, sort: sortOrder }, function(data) {
//					$.post(o.script, { dir: t, rmt: o.remote, edt: o.allowEdit, app: o.useApp, mobile: o.mobile }, function(data) {
						$(c).find('.start').html('');
						$(c).removeClass('wait').append(data);
						document.getElementById(o.pacifierID).style.display = 'none';
						if( o.root == t ) $(c).find('UL:hidden').show(); else $(c).find('UL:hidden').slideDown({ duration: o.expandSpeed, easing: o.expandEasing });
						bindTree(c);
						resizeUs();
					});
				}
				
				function bindTree(t) {
					$(t).find('LI A, LI IMG').bind(o.folderEvent, function() {
						if( $(this).parent().hasClass('directory') ) {
							if( $(this).parent().hasClass('collapsed') ) {
								// Expand
								if( !o.multiFolder ) {
									$(this).parent().parent().find('UL').slideUp({ duration: o.collapseSpeed, easing: o.collapseEasing });
									$(this).parent().parent().find('LI.directory').removeClass('expanded').addClass('collapsed');
								}
								$(this).parent().find('UL').remove(); // cleanup
								showTree( $(this).parent(), escape($(this).attr('rel').match( /.*\// )) );
								$(this).parent().removeClass('collapsed').addClass('expanded');
								
								if (o.selectDirectories)
									{
									action($(this)[0].nodeName, $(this).attr('rel'));
									}
							} else {
								// Collapse
								$(this).parent().find('UL').slideUp({ duration: o.collapseSpeed, easing: o.collapseEasing });
								$(this).parent().removeClass('expanded').addClass('collapsed');
								collapseAction($(this).attr('rel'));
							}
						} else {
						if (o.selectDirectories)
							{
							action($(this)[0].nodeName, $(this).attr('rel') + '__FILE__');
							}
						else
							{
							action($(this)[0].nodeName, $(this).attr('rel'));
							}
							//h($(this).attr('rel'));
						}
						return false;
					});
					// Prevent A from triggering the # on non-click events
					if( o.folderEvent.toLowerCase != 'click' ) $(t).find('LI A').bind('click', function() { return false; });
				}
				// Loading message
				$(this).html('<ul class="jqueryFileTree start"><li class="wait">' + o.loadMessage + '<li></ul>');
				// Get the initial file list
				showTree( $(this), escape(o.root) );
			});
		}
	});
	
})(jQuery);