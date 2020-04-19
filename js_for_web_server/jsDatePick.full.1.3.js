/*
	Copyright 2009 Itamar Arjuan
	jsDatePick is distributed under the terms of the GNU General Public License.
*/
/*
	Configuration settings documentation:
	
	useMode (Integer) – Possible values are 1 and 2 as follows:
		1 – The calendar's HTML will be directly appended to the field supplied by target
		2 – The calendar will appear as a popup when the field with the id supplied in target is clicked.
	
	target (String) – The id of the field to attach the calendar to , usually a text input field when using useMode 2.
	
	isStripped (Boolean) – When set to true the calendar appears without the visual design - usually used with useMode 1
	
	selectedDate (Object) – When supplied , this object tells the calendar to open up with this date selected already.
	
	yearsRange (Array) – When supplied , this array sets the limits for the years enabled in the calendar.
	
	limitToToday (Boolean) – Enables you to limit the possible picking days to today's date.
	
	cellColorScheme (String) – Enables you to swap the colors of the date's cells from a wide range of colors.
		Available color schemes: torqoise,purple,pink,orange,peppermint,aqua,armygreen,bananasplit,beige,
		deepblue,greenish,lightgreen,  ocean_blue <-default
	
	dateFormat (String) - Enables you to easily switch the date format without any hassle at all! 
		Should you not supply anything this field will default to: "%m-%d-%Y"
		
		Possible values to use in the date format:
		
		%d - Day of the month, 2 digits with leading zeros
		%j - Day of the month without leading zeros
		
		%m - Numeric representation of a month, with leading zeros
		%M - A short textual representation of a month, three letters
		%n - Numeric representation of a month, without leading zeros
		%F - A full textual representation of a month, such as January or March
		
		%Y - A full numeric representation of a year, 4 digits
		%y - A two digit representation of a year
		
		You can of course put whatever divider you want between them.
		
	weekStartDay (Integer) : Enables you to change the day that the week starts on.
		Possible values 0 (Sunday) through 6 (Saturday)
		Default value is 1 (Monday)
		
	Note: We have implemented a way to change the image path of the img folder should you decide you want to move it somewhere else.
	Please read through the instructions on how to carefully accomplish that just in the next comment!
	
	Thanks for using my calendar !
	Itamar :-)
	
	itamar.arjuan@gmail.com
	
*/
// The language array - change these values to your language to better fit your needs!
g_l = [];
g_l["MONTHS"] = ["January","February","March","April","May","June","July","August","September","October","November","December"];
g_l["DAYS_3"] = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"];
g_l["MONTH_FWD"] = "Move a month forward";
g_l["MONTH_BCK"] = "Move a month backward";
g_l["YEAR_FWD"] = "Move a year forward";
g_l["YEAR_BCK"] = "Move a year backward";
g_l["CLOSE"] = "Close the calendar";
g_l["ERROR_2"] = g_l["ERROR_1"] = "Date object invalid!";
g_l["ERROR_4"] = g_l["ERROR_3"] = "Target invalid";

/* Changing the image path: WARNING! */
/*
	The image path can be changed easily , however a few important
	safety steps must take place!
	
	CSS as a rule-of-thumb is always looking for relative image paths to where the CSS
	file resides. Meaning , if we place the css document of JsDatePick somewhere else
	Since some of the elements inside the CSS have  background:url(img/someimage.png);
	
	The system will try to look for a file under the same folder where the CSS file is.
	So pay careful attention when moving the CSS file somewhere else as the images folder
	must be relative to it. If you want to put the CSS document somewhere else and the images somewhere
	else - you HAVE to look and replace each background:url(img/someimage.png); to the new path you desire.
	
	That way you ensure risk free operation of images.
	For any further questions or support about this issue - please consider the feedback form
	at javascriptcalendar.org
	Thank you!
*/

// 2010 - 2016 only for the moment.
Date.prototype.isCalendarWkndOrHoliday=function(){
	var tem = this.getDay();
	if (tem == 0 || tem == 6)
		{
		return true;
		}
	var A=[this.getFullYear(), this.getMonth()+1,this.getDate()];
	var hol={
		'NewYear2000':[2000,01,03],
		'FamilyDay2000':[2000,02,21],
		'GoodFriday2000':[2000,04,21],
		'EasterMonday2000':[2000,04,24],
		'VictoriaDay2000':[2000,05,22],
		'CanadaDay2000':[2000,07,03],
		'Civic2000':[2000,08,07],
		'LabourDay2000':[2000,09,04],
		'ThanksgivingDay2000':[2000,10,09],
		'RemembranceDay2000':[2000,11,13],
		'Christmas2000':[2000,12,25],
		'BoxingDay2000':[2000,12,26],
		'NewYear2001':[2001,01,01],
		'FamilyDay2001':[2001,02,19],
		'GoodFriday2001':[2001,04,13],
		'EasterMonday2001':[2001,04,16],
		'VictoriaDay2001':[2001,05,21],
		'CanadaDay2001':[2001,07,02],
		'Civic2001':[2001,08,06],
		'LabourDay2001':[2001,09,03],
		'ThanksgivingDay2001':[2001,10,08],
		'RemembranceDay2001':[2001,11,12],
		'Christmas2001':[2001,12,25],
		'BoxingDay2001':[2001,12,26],
		'NewYear2002':[2002,01,01],
		'FamilyDay2002':[2002,02,18],
		'GoodFriday2002':[2002,03,29],
		'EasterMonday2002':[2002,04,01],
		'VictoriaDay2002':[2002,05,20],
		'CanadaDay2002':[2002,07,01],
		'Civic2002':[2002,08,05],
		'LabourDay2002':[2002,09,02],
		'ThanksgivingDay2002':[2002,10,14],
		'RemembranceDay2002':[2002,11,11],
		'Christmas2002':[2002,12,25],
		'BoxingDay2002':[2002,12,26],
		'NewYear2003':[2003,01,01],
		'FamilyDay2003':[2003,02,17],
		'GoodFriday2003':[2003,04,18],
		'EasterMonday2003':[2003,04,21],
		'VictoriaDay2003':[2003,05,19],
		'CanadaDay2003':[2003,07,01],
		'Civic2003':[2003,08,04],
		'LabourDay2003':[2003,09,01],
		'ThanksgivingDay2003':[2003,10,13],
		'RemembranceDay2003':[2003,11,11],
		'Christmas2003':[2003,12,25],
		'BoxingDay2003':[2003,12,26],
		'NewYear2004':[2004,01,01],
		'FamilyDay2004':[2004,02,16],
		'GoodFriday2004':[2004,04,09],
		'EasterMonday2004':[2004,04,12],
		'VictoriaDay2004':[2004,05,24],
		'CanadaDay2004':[2004,07,01],
		'Civic2004':[2004,08,02],
		'LabourDay2004':[2004,09,06],
		'ThanksgivingDay2004':[2004,10,11],
		'RemembranceDay2004':[2004,11,11],
		'Christmas2004':[2004,12,24],
		'BoxingDay2004':[2004,12,27],
		'NewYear2005':[2005,01,03],
		'FamilyDay2005':[2005,02,21],
		'GoodFriday2005':[2005,03,25],
		'EasterMonday2005':[2005,03,28],
		'VictoriaDay2005':[2005,05,23],
		'CanadaDay2005':[2005,07,01],
		'Civic2005':[2005,08,01],
		'LabourDay2005':[2005,09,05],
		'ThanksgivingDay2005':[2005,10,10],
		'RemembranceDay2005':[2005,11,11],
		'Christmas2005':[2005,12,23],
		'BoxingDay2005':[2005,12,26],
		'NewYear2006':[2006,01,02],
		'FamilyDay2006':[2006,02,20],
		'GoodFriday2006':[2006,04,14],
		'EasterMonday2006':[2006,04,17],
		'VictoriaDay2006':[2006,05,22],
		'CanadaDay2006':[2006,07,03],
		'Civic2006':[2006,08,07],
		'LabourDay2006':[2006,09,04],
		'ThanksgivingDay2006':[2006,10,09],
		'RemembranceDay2006':[2006,11,13],
		'Christmas2006':[2006,12,25],
		'BoxingDay2006':[2006,12,26],
		'NewYear2007':[2007,01,01],
		'FamilyDay2007':[2007,02,19],
		'GoodFriday2007':[2007,04,06],
		'EasterMonday2007':[2007,04,09],
		'VictoriaDay2007':[2007,05,21],
		'CanadaDay2007':[2007,07,02],
		'Civic2007':[2007,08,06],
		'LabourDay2007':[2007,09,03],
		'ThanksgivingDay2007':[2007,10,08],
		'RemembranceDay2007':[2007,11,12],
		'Christmas2007':[2007,12,25],
		'BoxingDay2007':[2007,12,26],
		'NewYear2008':[2008,01,01],
		'FamilyDay2008':[2008,02,18],
		'GoodFriday2008':[2008,03,21],
		'EasterMonday2008':[2008,03,24],
		'VictoriaDay2008':[2008,05,19],
		'CanadaDay2008':[2008,07,01],
		'Civic2008':[2008,08,04],
		'LabourDay2008':[2008,09,01],
		'ThanksgivingDay2008':[2008,10,13],
		'RemembranceDay2008':[2008,11,11],
		'Christmas2008':[2008,12,25],
		'BoxingDay2008':[2008,12,26],
		'NewYear2009':[2009,01,01],
		'FamilyDay2009':[2009,02,16],
		'GoodFriday2009':[2009,04,10],
		'EasterMonday2009':[2009,04,13],
		'VictoriaDay2009':[2009,05,18],
		'CanadaDay2009':[2009,07,01],
		'Civic2009':[2009,08,03],
		'LabourDay2009':[2009,09,07],
		'ThanksgivingDay2009':[2009,10,12],
		'RemembranceDay2009':[2009,11,11],
		'Christmas2009':[2009,12,25],
		'BoxingDay2009':[2009,12,28],
		'NewYear2010':[2010,01,01],
		'FamilyDay2010':[2010,02,15],
		'GoodFriday2010':[2010,04,02],
		'EasterMonday2010':[2010,04,05],
		'VictoriaDay2010':[2010,05,24],
		'CanadaDay2010':[2010,07,01],
		'Civic2010':[2010,08,02],
		'LabourDay2010':[2010,09,06],
		'ThanksgivingDay2010':[2010,10,11],
		'RemembranceDay2010':[2010,11,11],
		'Christmas2010':[2010,12,24],
		'BoxingDay2010':[2010,12,27],
		'NewYear2011':[2011,01,03],
		'FamilyDay2011':[2011,02,21],
		'GoodFriday2011':[2011,04,22],
		'EasterMonday2011':[2011,04,25],
		'VictoriaDay2011':[2011,05,23],
		'CanadaDay2011':[2011,07,01],
		'Civic2011':[2011,08,01],
		'LabourDay2011':[2011,09,05],
		'ThanksgivingDay2011':[2011,10,10],
		'RemembranceDay2011':[2011,11,11],
		'Christmas2011':[2011,12,23],
		'BoxingDay2011':[2011,12,26],
		'NewYear2012':[2012,01,02],
		'FamilyDay2012':[2012,02,20],
		'GoodFriday2012':[2012,04,06],
		'EasterMonday2012':[2012,04,09],
		'VictoriaDay2012':[2012,05,21],
		'CanadaDay2012':[2012,07,02],
		'Civic2012':[2012,08,06],
		'LabourDay2012':[2012,09,03],
		'ThanksgivingDay2012':[2012,10,08],
		'RemembranceDay2012':[2012,11,12],
		'Christmas2012':[2012,12,25],
		'BoxingDay2012':[2012,12,26],
		'NewYear2013':[2013,01,01],
		'FamilyDay2013':[2013,02,18],
		'GoodFriday2013':[2013,03,29],
		'EasterMonday2013':[2013,04,01],
		'VictoriaDay2013':[2013,05,20],
		'CanadaDay2013':[2013,07,01],
		'Civic2013':[2013,08,05],
		'LabourDay2013':[2013,09,02],
		'ThanksgivingDay2013':[2013,10,14],
		'RemembranceDay2013':[2013,11,11],
		'Christmas2013':[2013,12,25],
		'BoxingDay2013':[2013,12,26],
		'NewYear2014':[2014,01,01],
		'FamilyDay2014':[2014,02,17],
		'GoodFriday2014':[2014,04,18],
		'EasterMonday2014':[2014,04,21],
		'VictoriaDay2014':[2014,05,19],
		'CanadaDay2014':[2014,07,01],
		'Civic2014':[2014,08,04],
		'LabourDay2014':[2014,09,01],
		'ThanksgivingDay2014':[2014,10,13],
		'RemembranceDay2014':[2014,11,11],
		'Christmas2014':[2014,12,25],
		'BoxingDay2014':[2014,12,26],
		'NewYear2015':[2015,01,01],
		'FamilyDay2015':[2015,02,16],
		'GoodFriday2015':[2015,04,03],
		'EasterMonday2015':[2015,04,06],
		'VictoriaDay2015':[2015,05,18],
		'CanadaDay2015':[2015,07,01],
		'Civic2015':[2015,08,03],
		'LabourDay2015':[2015,09,07],
		'ThanksgivingDay2015':[2015,10,12],
		'RemembranceDay2015':[2015,11,11],
		'Christmas2015':[2015,12,25],
		'BoxingDay2015':[2015,12,28],
		'NewYear2016':[2016,01,01],
		'FamilyDay2016':[2016,02,15],
		'GoodFriday2016':[2016,03,25],
		'EasterMonday2016':[2016,03,28],
		'VictoriaDay2016':[2016,05,23],
		'CanadaDay2016':[2016,07,01],
		'Civic2016':[2016,08,01],
		'LabourDay2016':[2016,09,05],
		'ThanksgivingDay2016':[2016,10,10],
		'RemembranceDay2016':[2016,11,11],
		'Christmas2016':[2016,12,23],
		'BoxingDay2016':[2016,12,26],
		'NewYear2017':[2017,01,02],
		'FamilyDay2017':[2017,02,20],
		'GoodFriday2017':[2017,04,14],
		'EasterMonday2017':[2017,04,17],
		'VictoriaDay2017':[2017,05,22],
		'CanadaDay2017':[2017,07,03],
		'Civic2017':[2017,08,07],
		'LabourDay2017':[2017,09,04],
		'ThanksgivingDay2017':[2017,10,09],
		'RemembranceDay2017':[2017,11,13],
		'Christmas2017':[2017,12,25],
		'BoxingDay2017':[2017,12,26],
		'NewYear2018':[2018,01,01],
		'FamilyDay2018':[2018,02,19],
		'GoodFriday2018':[2018,03,30],
		'EasterMonday2018':[2018,04,02],
		'VictoriaDay2018':[2018,05,21],
		'CanadaDay2018':[2018,07,02],
		'Civic2018':[2018,08,06],
		'LabourDay2018':[2018,09,03],
		'ThanksgivingDay2018':[2018,10,08],
		'RemembranceDay2018':[2018,11,12],
		'Christmas2018':[2018,12,25],
		'BoxingDay2018':[2018,12,26],
		'NewYear2019':[2019,01,01],
		'FamilyDay2019':[2019,02,18],
		'GoodFriday2019':[2019,04,19],
		'EasterMonday2019':[2019,04,22],
		'VictoriaDay2019':[2019,05,20],
		'CanadaDay2019':[2019,07,01],
		'Civic2019':[2019,08,05],
		'LabourDay2019':[2019,09,02],
		'ThanksgivingDay2019':[2019,10,14],
		'RemembranceDay2019':[2019,11,11],
		'Christmas2019':[2019,12,25],
		'BoxingDay2019':[2019,12,26],
		'NewYear2020':[2020,01,01],
		'FamilyDay2020':[2020,02,17],
		'GoodFriday2020':[2020,04,10],
		'EasterMonday2020':[2020,04,13],
		'VictoriaDay2020':[2020,05,18],
		'CanadaDay2020':[2020,07,01],
		'Civic2020':[2020,08,03],
		'LabourDay2020':[2020,09,07],
		'ThanksgivingDay2020':[2020,10,12],
		'RemembranceDay2020':[2020,11,11],
		'Christmas2020':[2020,12,25],
		'BoxingDay2020':[2020,12,28],
		'NewYear2021':[2021,01,01],
		'FamilyDay2021':[2021,02,15],
		'GoodFriday2021':[2021,04,02],
		'EasterMonday2021':[2021,04,05],
		'VictoriaDay2021':[2021,05,24],
		'CanadaDay2021':[2021,07,01],
		'Civic2021':[2021,08,02],
		'LabourDay2021':[2021,09,06],
		'ThanksgivingDay2021':[2021,10,11],
		'RemembranceDay2021':[2021,11,11],
		'Christmas2021':[2021,12,24],
		'BoxingDay2021':[2021,12,27],
		'NewYear2022':[2022,01,03],
		'FamilyDay2022':[2022,02,21],
		'GoodFriday2022':[2022,04,15],
		'EasterMonday2022':[2022,04,18],
		'VictoriaDay2022':[2022,05,23],
		'CanadaDay2022':[2022,07,01],
		'Civic2022':[2022,08,01],
		'LabourDay2022':[2022,09,05],
		'ThanksgivingDay2022':[2022,10,10],
		'RemembranceDay2022':[2022,11,11],
		'Christmas2022':[2022,12,23],
		'BoxingDay2022':[2022,12,26],
		'NewYear2023':[2023,01,02],
		'FamilyDay2023':[2023,02,20],
		'GoodFriday2023':[2023,04,07],
		'EasterMonday2023':[2023,04,10],
		'VictoriaDay2023':[2023,05,22],
		'CanadaDay2023':[2023,07,03],
		'Civic2023':[2023,08,07],
		'LabourDay2023':[2023,09,04],
		'ThanksgivingDay2023':[2023,10,09],
		'RemembranceDay2023':[2023,11,13],
		'Christmas2023':[2023,12,25],
		'BoxingDay2023':[2023,12,26],
		'NewYear2024':[2024,01,01],
		'FamilyDay2024':[2024,02,19],
		'GoodFriday2024':[2024,03,29],
		'EasterMonday2024':[2024,04,01],
		'VictoriaDay2024':[2024,05,20],
		'CanadaDay2024':[2024,07,01],
		'Civic2024':[2024,08,05],
		'LabourDay2024':[2024,09,02],
		'ThanksgivingDay2024':[2024,10,14],
		'RemembranceDay2024':[2024,11,11],
		'Christmas2024':[2024,12,25],
		'BoxingDay2024':[2024,12,26],
		'NewYear2025':[2025,01,01],
		'FamilyDay2025':[2025,02,17],
		'GoodFriday2025':[2025,04,18],
		'EasterMonday2025':[2025,04,21],
		'VictoriaDay2025':[2025,05,19],
		'CanadaDay2025':[2025,07,01],
		'Civic2025':[2025,08,04],
		'LabourDay2025':[2025,09,01],
		'ThanksgivingDay2025':[2025,10,13],
		'RemembranceDay2025':[2025,11,11],
		'Christmas2025':[2025,12,25],
		'BoxingDay2025':[2025,12,26],
		'NewYear2026':[2026,01,01],
		'FamilyDay2026':[2026,02,16],
		'GoodFriday2026':[2026,04,03],
		'EasterMonday2026':[2026,04,06],
		'VictoriaDay2026':[2026,05,18],
		'CanadaDay2026':[2026,07,01],
		'Civic2026':[2026,08,03],
		'LabourDay2026':[2026,09,07],
		'ThanksgivingDay2026':[2026,10,12],
		'RemembranceDay2026':[2026,11,11],
		'Christmas2026':[2026,12,25],
		'BoxingDay2026':[2026,12,28],
		'NewYear2027':[2027,01,01],
		'FamilyDay2027':[2027,02,15],
		'GoodFriday2027':[2027,03,26],
		'EasterMonday2027':[2027,03,29],
		'VictoriaDay2027':[2027,05,24],
		'CanadaDay2027':[2027,07,01],
		'Civic2027':[2027,08,02],
		'LabourDay2027':[2027,09,06],
		'ThanksgivingDay2027':[2027,10,11],
		'RemembranceDay2027':[2027,11,11],
		'Christmas2027':[2027,12,24],
		'BoxingDay2027':[2027,12,27],
		'NewYear2028':[2028,01,03],
		'FamilyDay2028':[2028,02,21],
		'GoodFriday2028':[2028,04,14],
		'EasterMonday2028':[2028,04,17],
		'VictoriaDay2028':[2028,05,22],
		'CanadaDay2028':[2028,07,03],
		'Civic2028':[2028,08,07],
		'LabourDay2028':[2028,09,04],
		'ThanksgivingDay2028':[2028,10,09],
		'RemembranceDay2028':[2028,11,13],
		'Christmas2028':[2028,12,25],
		'BoxingDay2028':[2028,12,26],
		'NewYear2029':[2029,01,01],
		'FamilyDay2029':[2029,02,19],
		'GoodFriday2029':[2029,03,30],
		'EasterMonday2029':[2029,04,02],
		'VictoriaDay2029':[2029,05,21],
		'CanadaDay2029':[2029,07,02],
		'Civic2029':[2029,08,06],
		'LabourDay2029':[2029,09,03],
		'ThanksgivingDay2029':[2029,10,08],
		'RemembranceDay2029':[2029,11,12],
		'Christmas2029':[2029,12,25],
		'BoxingDay2029':[2029,12,26],
		'NewYear2030':[2030,01,01],
		'FamilyDay2030':[2030,02,18],
		'GoodFriday2030':[2030,04,19],
		'EasterMonday2030':[2030,04,22],
		'VictoriaDay2030':[2030,05,20],
		'CanadaDay2030':[2030,07,01],
		'Civic2030':[2030,08,05],
		'LabourDay2030':[2030,09,02],
		'ThanksgivingDay2030':[2030,10,14],
		'RemembranceDay2030':[2030,11,11],
		'Christmas2030':[2030,12,25],
		'BoxingDay2030':[2030,12,26]
		};
	var tem;
	for(var p in hol)
		{
		tem= hol[p];
		if(A[0]==tem[0] && A[1]==tem[1] && A[2]==tem[2]) return true;
		}
	return false;
	}

g_jsDatePickImagePath = "";
g_jsDatePickDirectionality = "ltr";

g_arrayOfUsedJsDatePickCalsGlobalNumbers = [];
g_arrayOfUsedJsDatePickCals = [];
g_currentDateObject = {};
g_currentDateObject.dateObject = new Date();

g_currentDateObject.day = g_currentDateObject.dateObject.getDate();
g_currentDateObject.month = g_currentDateObject.dateObject.getMonth() + 1;
g_currentDateObject.year = g_currentDateObject.dateObject.getFullYear();

JsgetElem = function(id){ return document.getElementById(id); };

String.prototype.trim = function() {
	return this.replace(/^\s+|\s+$/g,"");
};
String.prototype.ltrim = function() {
	return this.replace(/^\s+/,"");
};
String.prototype.rtrim = function() {
	return this.replace(/\s+$/,"");
};
String.prototype.strpad=function(){
	return (!isNaN(this) && this.toString().length==1)?"0"+this:this;
};

JsDatePick = function(configurationObject){
	if (document.all){
		this.isie = true;
		this.iever = JsDatePick.getInternetExplorerVersion();
	} else {
		this.isie = false;
	}
	
	this.oConfiguration = {};
	this.oCurrentDay = g_currentDateObject;
	this.monthsTextualRepresentation = g_l["MONTHS"];
	
	this.lastPostedDay = null;
	
	this.initialZIndex = 2;
	
	this.globalNumber = this.getUnUsedGlobalNumber();
	g_arrayOfUsedJsDatePickCals[this.globalNumber] = this;
	
	this.setConfiguration(configurationObject);
	this.makeCalendar();
};

JsDatePick.getCalInstanceById=function(id){ return g_arrayOfUsedJsDatePickCals[parseInt(id,10)]; };

JsDatePick.getInternetExplorerVersion=function(){
	var rv = -1, ua, re;
	if (navigator.appName == 'Microsoft Internet Explorer'){
		ua = navigator.userAgent;
		re = new RegExp("MSIE ([0-9]{1,}[\.0-9]{0,})");
		if (re.exec(ua) != null){
		  rv = parseFloat( RegExp.$1 );
		}
		return rv;
	}
};

JsDatePick.prototype.setC = function(obj, aClassName){
	if (this.isie && this.iever > 7){
		obj.setAttribute("class", aClassName);
	} else {
		obj.className = aClassName;
	}
};

JsDatePick.prototype.getUnUsedGlobalNumber = function(){
	
	var aNum = Math.floor(Math.random()*1000);
	
	while ( ! this.isUnique_GlobalNumber(aNum) ){
		aNum = Math.floor(Math.random()*1000);
	}
	
	return aNum;
};

JsDatePick.prototype.isUnique_GlobalNumber = function(aNum){
	var i;
	for (i=0; i<g_arrayOfUsedJsDatePickCalsGlobalNumbers.length; i++){
		if (g_arrayOfUsedJsDatePickCalsGlobalNumbers[i] == aNum){
			return false;
		}
	}
	return true;
};

JsDatePick.prototype.addOnSelectedDelegate = function(aDelegatedFunction){
	if (typeof(aDelegatedFunction) == "function"){
		this.addonSelectedDelegate = aDelegatedFunction;
	}
	return false;
};

JsDatePick.prototype.setOnSelectedDelegate = function(aDelegatedFunction){
	if (typeof(aDelegatedFunction) == "function"){
		this.onSelectedDelegate = aDelegatedFunction;
		return true;
	}
	return false;
};

JsDatePick.prototype.executeOnSelectedDelegateIfExists = function(){
	if (typeof(this.onSelectedDelegate) == "function"){
		this.onSelectedDelegate();
	}
	if (typeof(this.addonSelectedDelegate) == "function"){
		this.addonSelectedDelegate();
	}
};

JsDatePick.prototype.setRepopulationDelegate = function(aDelegatedFunction){
	if (typeof(aDelegatedFunction) == "function"){
		this.repopulationDelegate = aDelegatedFunction;
		return true;
	}
	return false;
};

JsDatePick.prototype.setConfiguration = function(aConf){
	this.oConfiguration.isStripped 		= (aConf["isStripped"] != null) ? aConf["isStripped"] : false;
	this.oConfiguration.useMode    		= (aConf["useMode"] != null) ? aConf["useMode"] : 1;
	this.oConfiguration.selectedDate   	= (aConf["selectedDate"] != null) ? aConf["selectedDate"] : null;
	this.oConfiguration.target			= (aConf["target"] != null) ? aConf["target"] : null;
	this.oConfiguration.yearsRange		= (aConf["yearsRange"] != null) ? aConf["yearsRange"] : [1971,2100];
	this.oConfiguration.limitToToday	= (aConf["limitToToday"] != null) ? aConf["limitToToday"] : false;
	this.oConfiguration.field			= (aConf["field"] != null) ? aConf["field"] : false;
	this.oConfiguration.cellColorScheme = (aConf["cellColorScheme"] != null) ? aConf["cellColorScheme"] : "ocean_blue";
	this.oConfiguration.dateFormat		= (aConf["dateFormat"] != null) ? aConf["dateFormat"] : "%m-%d-%Y";
	this.oConfiguration.imgPath			= (g_jsDatePickImagePath.length != null) ? g_jsDatePickImagePath : "";
	this.oConfiguration.weekStartDay   	= (aConf["weekStartDay"] != null) ? aConf["weekStartDay"] : 1;
	
	this.selectedDayObject = {};
	this.flag_DayMarkedBeforeRepopulation = false;
	this.flag_aDayWasSelected = false;
	this.lastMarkedDayObject = null;
	
	if (!this.oConfiguration.selectedDate){
		this.currentYear 	= this.oCurrentDay.year;
		this.currentMonth	= this.oCurrentDay.month;
		this.currentDay		= this.oCurrentDay.day;
	}
};

JsDatePick.prototype.resizeCalendar = function(){
	this.leftWallStrechedElement.style.height = "0px";
	this.rightWallStrechedElement.style.height = "0px";
	
	var totalHeight = this.JsDatePickBox.offsetHeight, newStrechedHeight = totalHeight-16;	
	
	if (newStrechedHeight < 0){
		return;
	}
	
	this.leftWallStrechedElement.style.height = newStrechedHeight+"px";
	this.rightWallStrechedElement.style.height = newStrechedHeight+"px";
	return true;
};

JsDatePick.prototype.closeCalendar = function(){
	this.JsDatePickBox.style.display = "none";
	document.onclick = function(){};
};

JsDatePick.prototype.populateFieldWithSelectedDate = function(){
	JsgetElem(this.oConfiguration.target).value = this.getSelectedDayFormatted();
	if (this.lastPickedDateObject){
		delete(this.lastPickedDateObject);
	}
	this.lastPickedDateObject = {};
	this.lastPickedDateObject.day = this.selectedDayObject.day;
	this.lastPickedDateObject.month = this.selectedDayObject.month;
	this.lastPickedDateObject.year = this.selectedDayObject.year;
	
	this.closeCalendar();
};

JsDatePick.prototype.makeCalendar = function(){
	var d = document, JsDatePickBox, clearfix, closeButton,leftWall,rightWall,topWall,bottomWall,topCorner,bottomCorner,wall,inputElement,aSpan,aFunc;
	
	JsDatePickBox = d.createElement("div");
	clearfix		= d.createElement("div");
	closeButton		= d.createElement("div");
	
	this.setC(JsDatePickBox, "JsDatePickBox");
	this.setC(clearfix, "clearfix");
	this.setC(closeButton, "jsDatePickCloseButton");
	closeButton.setAttribute("globalNumber",this.globalNumber);
	
	closeButton.onmouseover = function(){
		var gRef = JsDatePick.getCalInstanceById(this.getAttribute("globalNumber"));
		gRef.setTooltipText(g_l["CLOSE"]);
		gRef.setC(this, "jsDatePickCloseButtonOver");
	};
	
	closeButton.onmouseout = function(){
		var gRef = JsDatePick.getCalInstanceById(this.getAttribute("globalNumber"));
		gRef.setTooltipText('');
		gRef.setC(this, "jsDatePickCloseButton");
	};
	
	closeButton.onmousedown = function(){
		var gRef = JsDatePick.getCalInstanceById(this.getAttribute("globalNumber"));
		gRef.setTooltipText(g_l["CLOSE"]);
		gRef.setC(this, "jsDatePickCloseButtonDown");
	};
	
	closeButton.onmouseup = function(){
		var gRef = JsDatePick.getCalInstanceById(this.getAttribute("globalNumber"));
		gRef.setTooltipText('');
		gRef.setC(this, "jsDatePickCloseButton");
		gRef.closeCalendar();
	};
	
	this.JsDatePickBox = JsDatePickBox;
	
	leftWall  	= d.createElement("div");
	rightWall 	= d.createElement("div");
	topWall		= d.createElement("div");
	bottomWall	= d.createElement("div");
	
	this.setC(topWall, "topWall");
	this.setC(bottomWall, "bottomWall");
	
	if (this.isie && this.iever == 6){
		bottomWall.style.bottom = "-2px";
	}
	
	topCorner	 = d.createElement("div");
	bottomCorner = d.createElement("div");
	wall		 = d.createElement("div");
	
	this.setC(topCorner, "leftTopCorner");
	this.setC(bottomCorner, "leftBottomCorner");
	this.setC(wall, "leftWall");
	
	this.leftWallStrechedElement = wall;
	this.leftWall  = leftWall;
	this.rightWall = rightWall;
	
	leftWall.appendChild(topCorner);
	leftWall.appendChild(wall);
	leftWall.appendChild(bottomCorner);
	
	topCorner	 = d.createElement("div");
	bottomCorner = d.createElement("div");
	wall		 = d.createElement("div");
	
	this.setC(topCorner, "rightTopCorner");
	this.setC(bottomCorner, "rightBottomCorner");
	this.setC(wall, "rightWall");
	
	this.rightWallStrechedElement = wall;
	
	rightWall.appendChild(topCorner);
	rightWall.appendChild(wall);
	rightWall.appendChild(bottomCorner);
	
	if (this.oConfiguration.isStripped){
		this.setC(leftWall, "hiddenBoxLeftWall");
		this.setC(rightWall, "hiddenBoxRightWall");				
	} else {
		this.setC(leftWall, "boxLeftWall");
		this.setC(rightWall, "boxRightWall");
	}
	
	JsDatePickBox.appendChild(leftWall);
	JsDatePickBox.appendChild(this.getDOMCalendarStripped());
	JsDatePickBox.appendChild(rightWall);
	JsDatePickBox.appendChild(clearfix);
	
	if (!this.oConfiguration.isStripped){
		JsDatePickBox.appendChild(closeButton);
		JsDatePickBox.appendChild(topWall);
		JsDatePickBox.appendChild(bottomWall);
	}
	
	if (this.oConfiguration.useMode == 2){
		if (this.oConfiguration.target != false){
			if (typeof(JsgetElem(this.oConfiguration.target)) != null){
				inputElement = JsgetElem(this.oConfiguration.target);
		
				aSpan = document.createElement("span");
				inputElement.parentNode.replaceChild(aSpan,inputElement);
				aSpan.appendChild(inputElement);
		
				inputElement.setAttribute("globalNumber",this.globalNumber);
				inputElement.onclick = function(){ JsDatePick.getCalInstanceById(this.getAttribute("globalNumber")).showCalendar(); };
				inputElement.onfocus = function(){ JsDatePick.getCalInstanceById(this.getAttribute("globalNumber")).showCalendar(); };
				
				aSpan.style.position = "relative";
				this.initialZIndex++;
				
				JsDatePickBox.style.zIndex = this.initialZIndex.toString();
				JsDatePickBox.style.position = "absolute";
				JsDatePickBox.style.top = "18px";
				JsDatePickBox.style.left = "0px";
				JsDatePickBox.style.display = "none";
				aSpan.appendChild(JsDatePickBox);
				
				aFunc = new Function("g_arrayOfUsedJsDatePickCals["+this.globalNumber+"].populateFieldWithSelectedDate();");
				
				this.setOnSelectedDelegate(aFunc);
			} else {
				alert(g_l["ERROR_3"]);
			}
		}
	} else {
		if (this.oConfiguration.target != null){
			JsgetElem(this.oConfiguration.target).appendChild(JsDatePickBox);
			JsgetElem(this.oConfiguration.target).style.position = "relative";
			JsDatePickBox.style.position = "absolute";
			JsDatePickBox.style.top = "0px";
			JsDatePickBox.style.left = "0px";
			this.resizeCalendar();
			this.executePopulationDelegateIfExists();
		} else {
			alert(g_l["ERROR_4"]);
		}
	}
};

JsDatePick.prototype.determineFieldDate = function(){
	var aField,divider,dateMold,array,array2,i,dI,yI,mI,tflag=false,fflag=false;
	
	if (this.lastPickedDateObject){
		this.setSelectedDay({
			year:parseInt(this.lastPickedDateObject.year),
			month:parseInt(this.lastPickedDateObject.month,10),
			day:parseInt(this.lastPickedDateObject.day,10)
		});
	} else {
		aField = JsgetElem(this.oConfiguration.target);
		
		if (aField.value.trim().length == 0){
			this.unsetSelection();
			
			if (typeof(this.oConfiguration.selectedDate) == "object" && this.oConfiguration.selectedDate){
				this.setSelectedDay({
					year:parseInt(this.oConfiguration.selectedDate.year),
					month:parseInt(this.oConfiguration.selectedDate.month,10),
					day:parseInt(this.oConfiguration.selectedDate.day,10)
				});
			}
			
		} else {
			if (aField.value.trim().length > 5){
				divider = this.senseDivider(this.oConfiguration.dateFormat);
				dateMold = this.oConfiguration.dateFormat;
				array 	= aField.value.trim().split(divider);
				array2 	= dateMold.trim().split(divider);
				i=dI=yI=mI=0;
				
				for (i=0; i<array2.length; i++){
					switch (array2[i]){
						case "%d": case "%j": dI = i; break;
						case "%m": case "%n": mI = i; break;
						case "%M": mI = i; tflag=true; break;
						case "%F": mI = i; fflag=true; break;
						case "%Y": case "%y": yI = i;
					}
				}
				
				if (tflag){
					for (i=0; i<12; i++){
						if (g_l["MONTHS"][i].substr(0,3).toUpperCase() == array[mI].toUpperCase()){
							mI = i+1; break;
						}
					}
				} else if (fflag){
					for (i=0; i<12; i++){
						if (g_l["MONTHS"][i].toLowerCase() == array[mI].toLowerCase()){
							mI = i+1; break;
						}
					}
				} else {
					mI = parseInt(array[mI],10);
				}
				
				this.setSelectedDay({
					year:parseInt(array[yI],10),
					month:mI,
					day:parseInt(array[dI],10)
				});
			} else {
				this.unsetSelection();
				return;
			}
		}
	}
};

JsDatePick.prototype.senseDivider=function(aStr){return aStr.replace("%d","").replace("%j","").replace("%m","").replace("%M","").replace("%n","").replace("%F","").replace("%Y","").replace("%y","").substr(0,1);};

JsDatePick.prototype.showCalendar = function(){
	if (this.JsDatePickBox.style.display == "none"){
		this.determineFieldDate();
		this.JsDatePickBox.style.display = "block";
		this.resizeCalendar();
		this.executePopulationDelegateIfExists();
		this.JsDatePickBox.onmouseover = function(){
			document.onclick = function(){};
		};
		
		this.JsDatePickBox.setAttribute("globalCalNumber", this.globalNumber);		
		this.JsDatePickBox.onmouseout = function(){
			document.onclick = new Function("g_arrayOfUsedJsDatePickCals["+this.getAttribute("globalCalNumber")+"].closeCalendar();");
		};
		
	} else {
		return;
	}
};

JsDatePick.prototype.isAvailable = function(y, m, d){
	if (y > this.oCurrentDay.year){
		return false;
	}
	
	if (m > this.oCurrentDay.month && y == this.oCurrentDay.year){
		return false;
	}
	
	if (d > this.oCurrentDay.day && m == this.oCurrentDay.month && y == this.oCurrentDay.year ){
		return false;
	}
	
	return true;
};

JsDatePick.prototype.getDOMCalendarStripped = function(){
	var d = document,boxMain,boxMainInner,clearfix,boxMainCellsContainer,tooltip,weekDaysRow,clearfix2;
	
	boxMain = d.createElement("div");
	if (this.oConfiguration.isStripped){
		this.setC(boxMain, "boxMainStripped");
	} else {
		this.setC(boxMain, "boxMain");
	}
	
	this.boxMain = boxMain;
	
	boxMainInner 			= d.createElement("div");
	clearfix	 			= d.createElement("div");
	boxMainCellsContainer 	= d.createElement("div");
	tooltip					= d.createElement("div");
	weekDaysRow				= d.createElement("div");
	clearfix2				= d.createElement("div");
	
	this.setC(clearfix, "clearfix");
	this.setC(clearfix2, "clearfix");
	this.setC(boxMainInner, "boxMainInner");
	this.setC(boxMainCellsContainer, "boxMainCellsContainer");
	this.setC(tooltip, "tooltip");
	this.setC(weekDaysRow, "weekDaysRow");
	
	this.tooltip = tooltip;
	
	boxMain.appendChild(boxMainInner);
	
	this.controlsBar = this.getDOMControlBar();
	this.makeDOMWeekDays(weekDaysRow);
	
	boxMainInner.appendChild(this.controlsBar);
	boxMainInner.appendChild(clearfix);
	boxMainInner.appendChild(tooltip);
	boxMainInner.appendChild(weekDaysRow);
	boxMainInner.appendChild(boxMainCellsContainer);
	boxMainInner.appendChild(clearfix2);
	
	this.boxMainCellsContainer = boxMainCellsContainer;
	this.populateMainBox(boxMainCellsContainer);
	
	return boxMain;
};

JsDatePick.prototype.makeDOMWeekDays = function(aWeekDaysRow){
	var i=0,d = document,weekDaysArray = g_l["DAYS_3"],textNode,weekDay;	
	
	for (i=this.oConfiguration.weekStartDay; i<7; i++){
		weekDay 	= d.createElement("div");
		textNode 	= d.createTextNode(weekDaysArray[i]);
		this.setC(weekDay, "weekDay");
		
		weekDay.appendChild(textNode);
		aWeekDaysRow.appendChild(weekDay);
	}
	
	if (this.oConfiguration.weekStartDay > 0){
		for (i=0; i<this.oConfiguration.weekStartDay; i++){
			weekDay 	= d.createElement("div");
			textNode 	= d.createTextNode(weekDaysArray[i]);
			this.setC(weekDay, "weekDay");
			
			weekDay.appendChild(textNode);
			aWeekDaysRow.appendChild(weekDay);
		}
	}
	weekDay.style.marginRight = "0px";
};

JsDatePick.prototype.repopulateMainBox = function(){
	while (this.boxMainCellsContainer.firstChild){
		this.boxMainCellsContainer.removeChild(this.boxMainCellsContainer.firstChild);
	}
	
	this.populateMainBox(this.boxMainCellsContainer);
	this.resizeCalendar();
	this.executePopulationDelegateIfExists();
};

JsDatePick.prototype.executePopulationDelegateIfExists = function(){
	if (typeof(this.repopulationDelegate) == "function"){
		this.repopulationDelegate();
	}
};

JsDatePick.prototype.populateMainBox = function(aMainBox){
	var d = document,aDayDiv,aTextNode,columnNumber = 1,disabledDayFlag = false,cmpMonth = this.currentMonth-1,oDay,iStamp,skipDays,i,currentColorScheme;
	
	oDay = new Date(this.currentYear, cmpMonth, 1,1,0,0);
	iStamp = oDay.getTime();
	
	this.flag_DayMarkedBeforeRepopulation = false;
	this.setControlBarText(this.monthsTextualRepresentation[cmpMonth] + ", " + this.currentYear);
	
	skipDays = parseInt(oDay.getDay())-this.oConfiguration.weekStartDay;
	if (skipDays < 0){
		skipDays = skipDays + 7;
	}
	
	i=0;
	for (i=0; i<skipDays; i++){
		aDayDiv = d.createElement("div");
		this.setC(aDayDiv, "skipDay");
		aMainBox.appendChild(aDayDiv);
		if (columnNumber == 7){
			columnNumber = 1;
		} else {
			columnNumber++;
		}
	}
	
	while (oDay.getMonth() == cmpMonth){
		disabledDayFlag = false;
		aDayDiv 	= d.createElement("div");
		
		if (this.lastPostedDay){
			if (this.lastPostedDay == oDay.getDate()){
				aTextNode	= parseInt(this.lastPostedDay,10)+1;
			} else {
				aTextNode	= d.createTextNode(oDay.getDate());
			}
		} else {
			aTextNode	= d.createTextNode(oDay.getDate());
		}
		
		aDayDiv.appendChild(aTextNode);
		aMainBox.appendChild(aDayDiv);
		
		aDayDiv.setAttribute("globalNumber",this.globalNumber);
		
		if (columnNumber == 7){
			if (g_jsDatePickDirectionality == "ltr"){
				aDayDiv.style.marginRight = "0px";
			} else {
				aDayDiv.style.marginLeft = "0px";
			}
		}
		
		if (this.isToday(oDay)){
			aDayDiv.setAttribute("isToday",1);
		}
		
		if (this.oConfiguration.limitToToday){
			if ( ! this.isAvailable(this.currentYear, this.currentMonth, parseInt(oDay.getDate()) ) ){
				disabledDayFlag = true;
				aDayDiv.setAttribute("isJsDatePickDisabled",1);
			}
		}

		//var thisdate = new Date(this.currentYear, this.currentMonth - 1, d);
		if (oDay.isCalendarWkndOrHoliday())
			{
			disabledDayFlag = true;
			aDayDiv.setAttribute("isJsDatePickDisabled",1);
			}

		aDayDiv.onmouseover = function(){
			var gRef = JsDatePick.getCalInstanceById(this.getAttribute("globalNumber")),currentColorScheme;
			currentColorScheme = gRef.getCurrentColorScheme();
			
			if (parseInt(this.getAttribute("isSelected")) == 1){
				return;
			}
			if (parseInt(this.getAttribute("isJsDatePickDisabled")) == 1){
				return;
			}
			if (parseInt(this.getAttribute("isToday")) == 1){
				gRef.setC(this, "dayOverToday");
				this.style.background = "url(" + gRef.oConfiguration.imgPath + currentColorScheme + "_dayOver.gif) left top no-repeat";
			} else {
				gRef.setC(this, "dayOver");
				this.style.background = "url(" + gRef.oConfiguration.imgPath + currentColorScheme + "_dayOver.gif) left top no-repeat";
			}
		};
		
		aDayDiv.onmouseout = function(){
			var gRef = JsDatePick.getCalInstanceById(this.getAttribute("globalNumber")),currentColorScheme;
			currentColorScheme = gRef.getCurrentColorScheme();
			
			if (parseInt(this.getAttribute("isSelected")) == 1){
				return;
			}
			if (parseInt(this.getAttribute("isJsDatePickDisabled")) == 1){
				return;
			}
			if (parseInt(this.getAttribute("isToday")) == 1){
				gRef.setC(this, "dayNormalToday");
				this.style.background = "url(" + gRef.oConfiguration.imgPath + currentColorScheme + "_dayNormal.gif) left top no-repeat";
			} else {
				gRef.setC(this, "dayNormal");
				this.style.background = "url(" + gRef.oConfiguration.imgPath + currentColorScheme + "_dayNormal.gif) left top no-repeat";
			}
		};
		
		aDayDiv.onmousedown = function(){
			var gRef = JsDatePick.getCalInstanceById(this.getAttribute("globalNumber")),currentColorScheme;
			currentColorScheme = gRef.getCurrentColorScheme();
			
			if (parseInt(this.getAttribute("isSelected")) == 1){
				return;
			}
			if (parseInt(this.getAttribute("isJsDatePickDisabled")) == 1){
				return;
			}
			if (parseInt(this.getAttribute("isToday")) == 1){
				gRef.setC(this, "dayDownToday");
				this.style.background = "url(" + gRef.oConfiguration.imgPath + currentColorScheme + "_dayDown.gif) left top no-repeat";
			} else {
				gRef.setC(this, "dayDown");
				this.style.background = "url(" + gRef.oConfiguration.imgPath + currentColorScheme + "_dayDown.gif) left top no-repeat";
			}
		};
		
		aDayDiv.onmouseup = function(){
			var gRef = JsDatePick.getCalInstanceById(this.getAttribute("globalNumber")),currentColorScheme;
			currentColorScheme = gRef.getCurrentColorScheme();
			
			if (parseInt(this.getAttribute("isJsDatePickDisabled")) == 1){
				return;
			}
			if (parseInt(this.getAttribute("isToday")) == 1){
				gRef.setC(this, "dayNormalToday");
				this.style.background = "url(" + gRef.oConfiguration.imgPath + currentColorScheme + "_dayNormal.gif) left top no-repeat";
			} else {
				gRef.setC(this, "dayNormal");
				this.style.background = "url(" + gRef.oConfiguration.imgPath + currentColorScheme + "_dayNormal.gif) left top no-repeat";
			}
			
			gRef.setDaySelection(this);
			gRef.executeOnSelectedDelegateIfExists();
		};
	
		if (this.isSelectedDay(oDay.getDate())){
			aDayDiv.setAttribute("isSelected",1);
			this.flag_DayMarkedBeforeRepopulation = true;
			this.lastMarkedDayObject = aDayDiv;
			
			if (parseInt(aDayDiv.getAttribute("isToday")) == 1){
				this.setC(aDayDiv, "dayDownToday");
				aDayDiv.style.background = "url(" + this.oConfiguration.imgPath + this.oConfiguration.cellColorScheme + "_dayDown.gif) left top no-repeat";
			} else {
				this.setC(aDayDiv, "dayDown");
				aDayDiv.style.background = "url(" + this.oConfiguration.imgPath + this.oConfiguration.cellColorScheme + "_dayDown.gif) left top no-repeat";
			}	
			
		} else {
			currentColorScheme = this.getCurrentColorScheme();
			
			if (parseInt(aDayDiv.getAttribute("isToday")) == 1){
				if (disabledDayFlag){
					this.setC(aDayDiv, "dayDisabled");
					aDayDiv.style.background = "url(" + this.oConfiguration.imgPath + this.oConfiguration.cellColorScheme + "_dayNormal.gif) left top no-repeat";
				} else {
					this.setC(aDayDiv, "dayNormalToday");
					aDayDiv.style.background = "url(" + this.oConfiguration.imgPath + this.oConfiguration.cellColorScheme + "_dayNormal.gif) left top no-repeat";
				}
			} else {
				if (disabledDayFlag){
					this.setC(aDayDiv, "dayDisabled");
					aDayDiv.style.background = "url(" + this.oConfiguration.imgPath + this.oConfiguration.cellColorScheme + "_dayNormal.gif) left top no-repeat";
				} else {
					this.setC(aDayDiv, "dayNormal");
					aDayDiv.style.background = "url(" + this.oConfiguration.imgPath + this.oConfiguration.cellColorScheme + "_dayNormal.gif) left top no-repeat";
				}
			}
		}
		
		if (columnNumber == 7){
			columnNumber = 1;
		} else {
			columnNumber++;
		}
		iStamp += 86400000;
		oDay.setTime(iStamp);
	}
	
	this.lastPostedDay = null;
	
	return aMainBox;
};

JsDatePick.prototype.unsetSelection = function(){
	this.flag_aDayWasSelected = false;
	this.selectedDayObject = {};
	this.repopulateMainBox();
};

JsDatePick.prototype.setSelectedDay = function(dateObject){
	this.flag_aDayWasSelected = true;
	
	this.selectedDayObject.day = parseInt(dateObject.day,10);
	this.selectedDayObject.month = parseInt(dateObject.month,10);
	this.selectedDayObject.year = parseInt(dateObject.year);
	
	this.currentMonth 	= dateObject.month;
	this.currentYear	= dateObject.year;
	
	this.repopulateMainBox();
};

JsDatePick.prototype.isSelectedDay = function(aDate){
	if (this.flag_aDayWasSelected){
		if (parseInt(aDate) == this.selectedDayObject.day &&
			this.currentMonth == this.selectedDayObject.month &&
			this.currentYear == this.selectedDayObject.year){
			return true;
		} else {
			return false;
		}
	}
	return false;
};

JsDatePick.prototype.getSelectedDay = function(){
	if (this.flag_aDayWasSelected){
		return this.selectedDayObject;
	} else {
		return false;
	}
};

JsDatePick.prototype.getSelectedDayFormatted = function(){
	if (this.flag_aDayWasSelected){
		
		var dateStr = this.oConfiguration.dateFormat;
		
		dateStr = dateStr.replace("%d", this.selectedDayObject.day.toString().strpad());
		dateStr = dateStr.replace("%j", this.selectedDayObject.day);
		
		dateStr = dateStr.replace("%m", this.selectedDayObject.month.toString().strpad());
		dateStr = dateStr.replace("%M", g_l["MONTHS"][this.selectedDayObject.month-1].substr(0,3).toUpperCase());
		dateStr = dateStr.replace("%n", this.selectedDayObject.month);
		dateStr = dateStr.replace("%F", g_l["MONTHS"][this.selectedDayObject.month-1]);
		
		dateStr = dateStr.replace("%Y", this.selectedDayObject.year);
		dateStr = dateStr.replace("%y", this.selectedDayObject.year.toString().substr(2,2));
		
		return dateStr;
	} else {
		return false;
	}
};

JsDatePick.prototype.setDaySelection = function(anElement){
	var currentColorScheme = this.getCurrentColorScheme();
	
	if  (this.flag_DayMarkedBeforeRepopulation){
		/* Un mark last selected day */
		this.lastMarkedDayObject.setAttribute("isSelected",0);
		
		if (parseInt(this.lastMarkedDayObject.getAttribute("isToday")) == 1){
			this.setC(this.lastMarkedDayObject, "dayNormalToday");
			this.lastMarkedDayObject.style.background = "url(" + this.oConfiguration.imgPath + currentColorScheme + "_dayNormal.gif) left top no-repeat";
		} else {
			this.setC(this.lastMarkedDayObject, "dayNormal");
			this.lastMarkedDayObject.style.background = "url(" + this.oConfiguration.imgPath + currentColorScheme + "_dayNormal.gif) left top no-repeat";
		}
	}
	
	this.flag_aDayWasSelected = true;
	this.selectedDayObject.year  = this.currentYear;
	this.selectedDayObject.month = this.currentMonth;
	this.selectedDayObject.day   = parseInt(anElement.innerHTML);
	
	this.flag_DayMarkedBeforeRepopulation = true;
	this.lastMarkedDayObject = anElement;
	
	anElement.setAttribute("isSelected",1);
	
	if (parseInt(anElement.getAttribute("isToday")) == 1){
		this.setC(anElement, "dayDownToday");
		anElement.style.background = "url(" + this.oConfiguration.imgPath + currentColorScheme + "_dayDown.gif) left top no-repeat";
	} else {
		this.setC(anElement, "dayDown");
		anElement.style.background = "url(" + this.oConfiguration.imgPath + currentColorScheme + "_dayDown.gif) left top no-repeat";
	}
};

JsDatePick.prototype.isToday = function(aDateObject){
	var cmpMonth = this.oCurrentDay.month-1;
	if (aDateObject.getDate() == this.oCurrentDay.day &&
		aDateObject.getMonth() == cmpMonth &&
		aDateObject.getFullYear() == this.oCurrentDay.year){
		return true;
	}
	return false;
};

JsDatePick.prototype.setControlBarText = function(aText){
	var aTextNode = document.createTextNode(aText);
	
	while (this.controlsBarTextCell.firstChild){
		this.controlsBarTextCell.removeChild(this.controlsBarTextCell.firstChild);
	}
	
	this.controlsBarTextCell.appendChild(aTextNode);
};

JsDatePick.prototype.setTooltipText = function(aText){
	while (this.tooltip.firstChild){
		this.tooltip.removeChild(this.tooltip.firstChild);
	}
	
	var aTextNode = document.createTextNode(aText);
	this.tooltip.appendChild(aTextNode);
};

JsDatePick.prototype.moveForwardOneYear = function(){
	var desiredYear = this.currentYear + 1;
	if (desiredYear < parseInt(this.oConfiguration.yearsRange[1])){
		this.currentYear++;
		this.repopulateMainBox();
		return true;
	} else {
		return false;
	}
};

JsDatePick.prototype.moveBackOneYear = function(){
	var desiredYear = this.currentYear - 1;
	
	if (desiredYear > parseInt(this.oConfiguration.yearsRange[0])){
		this.currentYear--;
		this.repopulateMainBox();
		return true;
	} else {
		return false;
	}
};

JsDatePick.prototype.moveForwardOneMonth = function(){
	
	if (this.currentMonth < 12){
		this.currentMonth++;
	} else {
		if (this.moveForwardOneYear()){
			this.currentMonth = 1;
		} else {
			this.currentMonth = 12;
		}
	}
	
	this.repopulateMainBox();
};

JsDatePick.prototype.moveBackOneMonth = function(){
	
	if (this.currentMonth > 1){
		this.currentMonth--;
	} else {
		if (this.moveBackOneYear()){
			this.currentMonth = 12;
		} else {
			this.currentMonth = 1;
		}
	}
	
	this.repopulateMainBox();
};

JsDatePick.prototype.getCurrentColorScheme = function(){
	return this.oConfiguration.cellColorScheme;
};

JsDatePick.prototype.getDOMControlBar = function(){
	var d = document, controlsBar,monthForwardButton,monthBackwardButton,yearForwardButton,yearBackwardButton,controlsBarText;
	
	controlsBar 			= d.createElement("div");
	monthForwardButton		= d.createElement("div");
	monthBackwardButton		= d.createElement("div");
	yearForwardButton		= d.createElement("div");
	yearBackwardButton		= d.createElement("div");
	controlsBarText			= d.createElement("div");
	
	this.setC(controlsBar, "controlsBar");
	this.setC(monthForwardButton, "monthForwardButton");
	this.setC(monthBackwardButton, "monthBackwardButton");
	this.setC(yearForwardButton, "yearForwardButton");
	this.setC(yearBackwardButton, "yearBackwardButton");
	this.setC(controlsBarText, "controlsBarText");
		
	controlsBar.setAttribute("globalNumber",this.globalNumber);
	monthForwardButton.setAttribute("globalNumber",this.globalNumber);
	monthBackwardButton.setAttribute("globalNumber",this.globalNumber);
	yearBackwardButton.setAttribute("globalNumber",this.globalNumber);
	yearForwardButton.setAttribute("globalNumber",this.globalNumber);
	
	this.controlsBarTextCell = controlsBarText;
	
	controlsBar.appendChild(monthForwardButton);
	controlsBar.appendChild(monthBackwardButton);
	controlsBar.appendChild(yearForwardButton);
	controlsBar.appendChild(yearBackwardButton);
	controlsBar.appendChild(controlsBarText);
	
	monthForwardButton.onmouseover = function(){
		var	gRef,parentElement;
		if (parseInt(this.getAttribute("isJsDatePickDisabled")) == 1){
			return;
		}
		parentElement = this.parentNode;
		while (parentElement.className != "controlsBar"){
			parentElement = parentElement.parentNode;
		}
		gRef = JsDatePick.getCalInstanceById(this.getAttribute("globalNumber"));
		gRef.setTooltipText(g_l["MONTH_FWD"]);
		gRef.setC(this, "monthForwardButtonOver");
	};
	
	monthForwardButton.onmouseout = function(){
		var parentElement,gRef;
		if (parseInt(this.getAttribute("isJsDatePickDisabled")) == 1){
			return;
		}
		parentElement = this.parentNode;
		while (parentElement.className != "controlsBar"){
			parentElement = parentElement.parentNode;
		}
		gRef = JsDatePick.getCalInstanceById(this.getAttribute("globalNumber"));
		gRef.setTooltipText('');
		gRef.setC(this, "monthForwardButton");
	};
	
	monthForwardButton.onmousedown = function(){
		var gRef,parentElement;
		if (parseInt(this.getAttribute("isJsDatePickDisabled")) == 1){
			return;
		}
		parentElement = this.parentNode;
		while (parentElement.className != "controlsBar"){
			parentElement = parentElement.parentNode;
		}		
		gRef = JsDatePick.getCalInstanceById(this.getAttribute("globalNumber"));
		gRef.setTooltipText(g_l["MONTH_FWD"]);
		gRef.setC(this, "monthForwardButtonDown");
	};
	
	monthForwardButton.onmouseup = function(){
		var parentElement,gRef;
		if (parseInt(this.getAttribute("isJsDatePickDisabled")) == 1){
			return;
		}
		parentElement = this.parentNode;
		while (parentElement.className != "controlsBar"){
			parentElement = parentElement.parentNode;
		}
		gRef = JsDatePick.getCalInstanceById(this.getAttribute("globalNumber"));
		gRef.setTooltipText(g_l["MONTH_FWD"]);
		gRef.setC(this, "monthForwardButton");
		gRef.moveForwardOneMonth();
	};
	
	/* Month backward button event handlers */
	
	monthBackwardButton.onmouseover = function(){
		var parentElement,gRef;
		if (parseInt(this.getAttribute("isJsDatePickDisabled")) == 1){
			return;
		}
		parentElement = this.parentNode;
		while (parentElement.className != "controlsBar"){
			parentElement = parentElement.parentNode;
		}
		gRef = JsDatePick.getCalInstanceById(this.getAttribute("globalNumber"));
		gRef.setTooltipText(g_l["MONTH_BCK"]);
		gRef.setC(this, "monthBackwardButtonOver");
	};
	
	monthBackwardButton.onmouseout = function(){
		var parentElement,gRef;
		if (parseInt(this.getAttribute("isJsDatePickDisabled")) == 1){
			return;
		}
		parentElement = this.parentNode;
		while (parentElement.className != "controlsBar"){
			parentElement = parentElement.parentNode;
		}
		gRef = JsDatePick.getCalInstanceById(this.getAttribute("globalNumber"));
		gRef.setTooltipText('');
		gRef.setC(this, "monthBackwardButton");
	};
	
	monthBackwardButton.onmousedown = function(){
		var parentElement,gRef;
		if (parseInt(this.getAttribute("isJsDatePickDisabled")) == 1){
			return;
		}
		parentElement = this.parentNode;
		while (parentElement.className != "controlsBar"){
			parentElement = parentElement.parentNode;
		}
		gRef = JsDatePick.getCalInstanceById(this.getAttribute("globalNumber"));
		gRef.setTooltipText(g_l["MONTH_BCK"]);
		gRef.setC(this, "monthBackwardButtonDown");
	};
	
	monthBackwardButton.onmouseup = function(){
		var parentElement,gRef;
		if (parseInt(this.getAttribute("isJsDatePickDisabled")) == 1){
			return;
		}
		parentElement = this.parentNode;
		while (parentElement.className != "controlsBar"){
			parentElement = parentElement.parentNode;
		}
		gRef = JsDatePick.getCalInstanceById(this.getAttribute("globalNumber"));
		gRef.setTooltipText(g_l["MONTH_BCK"]);
		gRef.setC(this, "monthBackwardButton");
		gRef.moveBackOneMonth();
	};
	
	/* Year forward button */
	
	yearForwardButton.onmouseover = function(){
		var parentElement,gRef;
		if (parseInt(this.getAttribute("isJsDatePickDisabled")) == 1){
			return;
		}
		parentElement = this.parentNode;		
		while (parentElement.className != "controlsBar"){
			parentElement = parentElement.parentNode;
		}
		gRef = JsDatePick.getCalInstanceById(this.getAttribute("globalNumber"));
		gRef.setTooltipText(g_l["YEAR_FWD"]);
		gRef.setC(this, "yearForwardButtonOver");
	};
	
	yearForwardButton.onmouseout = function(){
		var parentElement,gRef;
		if (parseInt(this.getAttribute("isJsDatePickDisabled")) == 1){
			return;			
		}
		parentElement = this.parentNode;
		while (parentElement.className != "controlsBar"){
			parentElement = parentElement.parentNode;
		}
		gRef = JsDatePick.getCalInstanceById(this.getAttribute("globalNumber"));
		gRef.setTooltipText('');
		gRef.setC(this, "yearForwardButton");
	};
	
	yearForwardButton.onmousedown = function(){
		var parentElement,gRef;
		if (parseInt(this.getAttribute("isJsDatePickDisabled")) == 1){
			return;
		}
		parentElement = this.parentNode;
		while (parentElement.className != "controlsBar"){
			parentElement = parentElement.parentNode;
		}
		gRef = JsDatePick.getCalInstanceById(this.getAttribute("globalNumber"));
		gRef.setTooltipText(g_l["YEAR_FWD"]);
		gRef.setC(this, "yearForwardButtonDown");
	};
	
	yearForwardButton.onmouseup = function(){
		var parentElement,gRef;
		if (parseInt(this.getAttribute("isJsDatePickDisabled")) == 1){
			return;
		}
		parentElement = this.parentNode;
		while (parentElement.className != "controlsBar"){
			parentElement = parentElement.parentNode;
		}
		gRef = JsDatePick.getCalInstanceById(this.getAttribute("globalNumber"));
		gRef.setTooltipText(g_l["YEAR_FWD"]);
		gRef.setC(this, "yearForwardButton");
		gRef.moveForwardOneYear();
	};
	
	/* Year backward button */
	
	yearBackwardButton.onmouseover = function(){
		var parentElement,gRef;
		if (parseInt(this.getAttribute("isJsDatePickDisabled")) == 1){
			return;
		}
		parentElement = this.parentNode;
		while (parentElement.className != "controlsBar"){
			parentElement = parentElement.parentNode;
		}
		gRef = JsDatePick.getCalInstanceById(this.getAttribute("globalNumber"));
		gRef.setTooltipText(g_l["YEAR_BCK"]);
		gRef.setC(this, "yearBackwardButtonOver");
	};
	
	yearBackwardButton.onmouseout = function(){
		var parentElement,gRef;
		if (parseInt(this.getAttribute("isJsDatePickDisabled")) == 1){
			return;
		}		
		parentElement = this.parentNode;
		while (parentElement.className != "controlsBar"){
			parentElement = parentElement.parentNode;
		}
		gRef = JsDatePick.getCalInstanceById(this.getAttribute("globalNumber"));
		gRef.setTooltipText('');
		gRef.setC(this, "yearBackwardButton");
	};
	
	yearBackwardButton.onmousedown = function(){
		var parentElement,gRef;
		if (parseInt(this.getAttribute("isJsDatePickDisabled")) == 1){
			return;
		}
		parentElement = this.parentNode;
		while (parentElement.className != "controlsBar"){
			parentElement = parentElement.parentNode;
		}
		gRef = JsDatePick.getCalInstanceById(this.getAttribute("globalNumber"));
		gRef.setTooltipText(g_l["YEAR_BCK"]);
		gRef.setC(this, "yearBackwardButtonDown");
	};
	
	yearBackwardButton.onmouseup = function(){
		var parentElement,gRef;
		if (parseInt(this.getAttribute("isJsDatePickDisabled")) == 1){
			return;
		}
		parentElement = this.parentNode;
		while (parentElement.className != "controlsBar"){
			parentElement = parentElement.parentNode;
		}		
		gRef = JsDatePick.getCalInstanceById(this.getAttribute("globalNumber"));
		gRef.setTooltipText(g_l["YEAR_BCK"]);
		gRef.setC(this, "yearBackwardButton");
		gRef.moveBackOneYear();
	};
	
	return controlsBar;
};