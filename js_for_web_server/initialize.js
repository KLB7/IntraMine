// NOT USED.

function initialize()
	{
	$("#toggleDetails").mouseout(function()
        {
        $("#toggleDetails").css('cursor', 'default');
        });
    $("#toggleDetails").mouseover(function()
        {
        $("#toggleDetails").css('cursor', 'pointer');
        });
    $("#toggleDetails").click(function()
        {
        $("#help").slideToggle("slow");
        });
	}