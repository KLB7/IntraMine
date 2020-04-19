// days.js: days between dates, holidays. Used in: intramine_daysserver.pl.
// This uses jQuery for the date picker.

// Set up the two calendars for date picking, and click handling. This is called on "load", see
// intramine_daysserver.pl#DaysPage().
function startCustomDateJS() {
	let today = new Date();
	let tem = today.getDay();
	while (today.isHoliday() || tem == 0 || tem == 6)
		{
		today = new Date(today.setDate(today.getDate() + 1));
		tem = today.getDay();
		}

	let yr = today.getFullYear();
	let mn = today.getMonth() + 1;
	let dy = today.getDate();
	g_globalObject1 = new JsDatePick({
		useMode : 1,
		isStripped : true,
		target : "calendar1",
		cellColorScheme : "armygreen",
		weekStartDay : 0
	});
	g_globalObject1.setOnSelectedDelegate(function() {
		let obj1 = g_globalObject1.getSelectedDay();
		let obj2 = g_globalObject2.getSelectedDay();
		let dateStr1 =
				obj1.year + "/" + ('0' + obj1.month).slice(-2) + "/" + ('0' + obj1.day).slice(-2);
		let dateStr2 =
				obj2.year + "/" + ('0' + obj2.month).slice(-2) + "/" + ('0' + obj2.day).slice(-2);
		let elapsedDays = elapsedDaysBetweenDates(obj1, obj2);
		let elapsedCalendarDays = elapsedCalendarDaysBetweenDates(obj1, obj2);
		$('[name=elapsed]').val(elapsedDays.toString());
		$('#startdate').text("Start Date " + dateStr1);
		$('#enddate').text("End Date " + dateStr2);
		$('#cal_elapsed').text(elapsedCalendarDays.toString());
	});
	g_globalObject1.setSelectedDay({
		year : yr,
		month : mn,
		day : dy
	});
	g_globalObject2 = new JsDatePick({
		useMode : 1,
		isStripped : true,
		target : "calendar2",
		cellColorScheme : "armygreen",
		weekStartDay : 0
	});
	g_globalObject2.setOnSelectedDelegate(function() {
		let obj1 = g_globalObject1.getSelectedDay();
		let obj2 = g_globalObject2.getSelectedDay();
		let dateStr1 =
				obj1.year + "/" + ('0' + obj1.month).slice(-2) + "/" + ('0' + obj1.day).slice(-2);
		let dateStr2 =
				obj2.year + "/" + ('0' + obj2.month).slice(-2) + "/" + ('0' + obj2.day).slice(-2);
		let elapsedDays = elapsedDaysBetweenDates(obj1, obj2);
		let elapsedCalendarDays = elapsedCalendarDaysBetweenDates(obj1, obj2);
		$('[name=elapsed]').val(elapsedDays.toString());
		$('#startdate').text("Start Date " + dateStr1);
		$('#enddate').text("End Date " + dateStr2);
		$('#cal_elapsed').text(elapsedCalendarDays.toString());
	});
	g_globalObject2.setSelectedDay({
		year : yr,
		month : mn,
		day : dy
	});
	
	$('[name=elapsed]').val("1");
	$('#cal_elapsed').text("1");

	let obj1 = g_globalObject1.getSelectedDay();
	let dateStr1 =
			obj1.year + "/" + ('0' + obj1.month).slice(-2) + "/" + ('0' + obj1.day).slice(-2);
	$('#startdate').text("Start Date " + dateStr1);
	$('#enddate').text("End Date " + dateStr1);

	$('#daysform').submit(function() {
		let numBusinessDays = $('[name=elapsed]').val();
		setEndDay(numBusinessDays);
		return false;
	});

	$('[name=elapsed]').bind('keyup', function(e) {
		let numBusinessDays = $('[name=elapsed]').val();
		setEndDay(numBusinessDays);
	});
	$('[name=elapsed]').click(function() {
		this.select();
	});
}

// 2010 - 2030. These are for Ontario Canada.
Date.prototype.isHoliday = function() {
	let A = [ this.getFullYear(), this.getMonth() + 1, this.getDate() ];
	let hol = {
		'NewYear2000' : [ 2000, 01, 03 ],
		'FamilyDay2000' : [ 2000, 02, 21 ],
		'GoodFriday2000' : [ 2000, 04, 21 ],
		'EasterMonday2000' : [ 2000, 04, 24 ],
		'VictoriaDay2000' : [ 2000, 05, 22 ],
		'CanadaDay2000' : [ 2000, 07, 03 ],
		'Civic2000' : [ 2000, 08, 07 ],
		'LabourDay2000' : [ 2000, 09, 04 ],
		'ThanksgivingDay2000' : [ 2000, 10, 09 ],
		'RemembranceDay2000' : [ 2000, 11, 13 ],
		'Christmas2000' : [ 2000, 12, 25 ],
		'BoxingDay2000' : [ 2000, 12, 26 ],
		'NewYear2001' : [ 2001, 01, 01 ],
		'FamilyDay2001' : [ 2001, 02, 19 ],
		'GoodFriday2001' : [ 2001, 04, 13 ],
		'EasterMonday2001' : [ 2001, 04, 16 ],
		'VictoriaDay2001' : [ 2001, 05, 21 ],
		'CanadaDay2001' : [ 2001, 07, 02 ],
		'Civic2001' : [ 2001, 08, 06 ],
		'LabourDay2001' : [ 2001, 09, 03 ],
		'ThanksgivingDay2001' : [ 2001, 10, 08 ],
		'RemembranceDay2001' : [ 2001, 11, 12 ],
		'Christmas2001' : [ 2001, 12, 25 ],
		'BoxingDay2001' : [ 2001, 12, 26 ],
		'NewYear2002' : [ 2002, 01, 01 ],
		'FamilyDay2002' : [ 2002, 02, 18 ],
		'GoodFriday2002' : [ 2002, 03, 29 ],
		'EasterMonday2002' : [ 2002, 04, 01 ],
		'VictoriaDay2002' : [ 2002, 05, 20 ],
		'CanadaDay2002' : [ 2002, 07, 01 ],
		'Civic2002' : [ 2002, 08, 05 ],
		'LabourDay2002' : [ 2002, 09, 02 ],
		'ThanksgivingDay2002' : [ 2002, 10, 14 ],
		'RemembranceDay2002' : [ 2002, 11, 11 ],
		'Christmas2002' : [ 2002, 12, 25 ],
		'BoxingDay2002' : [ 2002, 12, 26 ],
		'NewYear2003' : [ 2003, 01, 01 ],
		'FamilyDay2003' : [ 2003, 02, 17 ],
		'GoodFriday2003' : [ 2003, 04, 18 ],
		'EasterMonday2003' : [ 2003, 04, 21 ],
		'VictoriaDay2003' : [ 2003, 05, 19 ],
		'CanadaDay2003' : [ 2003, 07, 01 ],
		'Civic2003' : [ 2003, 08, 04 ],
		'LabourDay2003' : [ 2003, 09, 01 ],
		'ThanksgivingDay2003' : [ 2003, 10, 13 ],
		'RemembranceDay2003' : [ 2003, 11, 11 ],
		'Christmas2003' : [ 2003, 12, 25 ],
		'BoxingDay2003' : [ 2003, 12, 26 ],
		'NewYear2004' : [ 2004, 01, 01 ],
		'FamilyDay2004' : [ 2004, 02, 16 ],
		'GoodFriday2004' : [ 2004, 04, 09 ],
		'EasterMonday2004' : [ 2004, 04, 12 ],
		'VictoriaDay2004' : [ 2004, 05, 24 ],
		'CanadaDay2004' : [ 2004, 07, 01 ],
		'Civic2004' : [ 2004, 08, 02 ],
		'LabourDay2004' : [ 2004, 09, 06 ],
		'ThanksgivingDay2004' : [ 2004, 10, 11 ],
		'RemembranceDay2004' : [ 2004, 11, 11 ],
		'Christmas2004' : [ 2004, 12, 24 ],
		'BoxingDay2004' : [ 2004, 12, 27 ],
		'NewYear2005' : [ 2005, 01, 03 ],
		'FamilyDay2005' : [ 2005, 02, 21 ],
		'GoodFriday2005' : [ 2005, 03, 25 ],
		'EasterMonday2005' : [ 2005, 03, 28 ],
		'VictoriaDay2005' : [ 2005, 05, 23 ],
		'CanadaDay2005' : [ 2005, 07, 01 ],
		'Civic2005' : [ 2005, 08, 01 ],
		'LabourDay2005' : [ 2005, 09, 05 ],
		'ThanksgivingDay2005' : [ 2005, 10, 10 ],
		'RemembranceDay2005' : [ 2005, 11, 11 ],
		'Christmas2005' : [ 2005, 12, 23 ],
		'BoxingDay2005' : [ 2005, 12, 26 ],
		'NewYear2006' : [ 2006, 01, 02 ],
		'FamilyDay2006' : [ 2006, 02, 20 ],
		'GoodFriday2006' : [ 2006, 04, 14 ],
		'EasterMonday2006' : [ 2006, 04, 17 ],
		'VictoriaDay2006' : [ 2006, 05, 22 ],
		'CanadaDay2006' : [ 2006, 07, 03 ],
		'Civic2006' : [ 2006, 08, 07 ],
		'LabourDay2006' : [ 2006, 09, 04 ],
		'ThanksgivingDay2006' : [ 2006, 10, 09 ],
		'RemembranceDay2006' : [ 2006, 11, 13 ],
		'Christmas2006' : [ 2006, 12, 25 ],
		'BoxingDay2006' : [ 2006, 12, 26 ],
		'NewYear2007' : [ 2007, 01, 01 ],
		'FamilyDay2007' : [ 2007, 02, 19 ],
		'GoodFriday2007' : [ 2007, 04, 06 ],
		'EasterMonday2007' : [ 2007, 04, 09 ],
		'VictoriaDay2007' : [ 2007, 05, 21 ],
		'CanadaDay2007' : [ 2007, 07, 02 ],
		'Civic2007' : [ 2007, 08, 06 ],
		'LabourDay2007' : [ 2007, 09, 03 ],
		'ThanksgivingDay2007' : [ 2007, 10, 08 ],
		'RemembranceDay2007' : [ 2007, 11, 12 ],
		'Christmas2007' : [ 2007, 12, 25 ],
		'BoxingDay2007' : [ 2007, 12, 26 ],
		'NewYear2008' : [ 2008, 01, 01 ],
		'FamilyDay2008' : [ 2008, 02, 18 ],
		'GoodFriday2008' : [ 2008, 03, 21 ],
		'EasterMonday2008' : [ 2008, 03, 24 ],
		'VictoriaDay2008' : [ 2008, 05, 19 ],
		'CanadaDay2008' : [ 2008, 07, 01 ],
		'Civic2008' : [ 2008, 08, 04 ],
		'LabourDay2008' : [ 2008, 09, 01 ],
		'ThanksgivingDay2008' : [ 2008, 10, 13 ],
		'RemembranceDay2008' : [ 2008, 11, 11 ],
		'Christmas2008' : [ 2008, 12, 25 ],
		'BoxingDay2008' : [ 2008, 12, 26 ],
		'NewYear2009' : [ 2009, 01, 01 ],
		'FamilyDay2009' : [ 2009, 02, 16 ],
		'GoodFriday2009' : [ 2009, 04, 10 ],
		'EasterMonday2009' : [ 2009, 04, 13 ],
		'VictoriaDay2009' : [ 2009, 05, 18 ],
		'CanadaDay2009' : [ 2009, 07, 01 ],
		'Civic2009' : [ 2009, 08, 03 ],
		'LabourDay2009' : [ 2009, 09, 07 ],
		'ThanksgivingDay2009' : [ 2009, 10, 12 ],
		'RemembranceDay2009' : [ 2009, 11, 11 ],
		'Christmas2009' : [ 2009, 12, 25 ],
		'BoxingDay2009' : [ 2009, 12, 28 ],
		'NewYear2010' : [ 2010, 01, 01 ],
		'FamilyDay2010' : [ 2010, 02, 15 ],
		'GoodFriday2010' : [ 2010, 04, 02 ],
		'EasterMonday2010' : [ 2010, 04, 05 ],
		'VictoriaDay2010' : [ 2010, 05, 24 ],
		'CanadaDay2010' : [ 2010, 07, 01 ],
		'Civic2010' : [ 2010, 08, 02 ],
		'LabourDay2010' : [ 2010, 09, 06 ],
		'ThanksgivingDay2010' : [ 2010, 10, 11 ],
		'RemembranceDay2010' : [ 2010, 11, 11 ],
		'Christmas2010' : [ 2010, 12, 24 ],
		'BoxingDay2010' : [ 2010, 12, 27 ],
		'NewYear2011' : [ 2011, 01, 03 ],
		'FamilyDay2011' : [ 2011, 02, 21 ],
		'GoodFriday2011' : [ 2011, 04, 22 ],
		'EasterMonday2011' : [ 2011, 04, 25 ],
		'VictoriaDay2011' : [ 2011, 05, 23 ],
		'CanadaDay2011' : [ 2011, 07, 01 ],
		'Civic2011' : [ 2011, 08, 01 ],
		'LabourDay2011' : [ 2011, 09, 05 ],
		'ThanksgivingDay2011' : [ 2011, 10, 10 ],
		'RemembranceDay2011' : [ 2011, 11, 11 ],
		'Christmas2011' : [ 2011, 12, 23 ],
		'BoxingDay2011' : [ 2011, 12, 26 ],
		'NewYear2012' : [ 2012, 01, 02 ],
		'FamilyDay2012' : [ 2012, 02, 20 ],
		'GoodFriday2012' : [ 2012, 04, 06 ],
		'EasterMonday2012' : [ 2012, 04, 09 ],
		'VictoriaDay2012' : [ 2012, 05, 21 ],
		'CanadaDay2012' : [ 2012, 07, 02 ],
		'Civic2012' : [ 2012, 08, 06 ],
		'LabourDay2012' : [ 2012, 09, 03 ],
		'ThanksgivingDay2012' : [ 2012, 10, 08 ],
		'RemembranceDay2012' : [ 2012, 11, 12 ],
		'Christmas2012' : [ 2012, 12, 25 ],
		'BoxingDay2012' : [ 2012, 12, 26 ],
		'NewYear2013' : [ 2013, 01, 01 ],
		'FamilyDay2013' : [ 2013, 02, 18 ],
		'GoodFriday2013' : [ 2013, 03, 29 ],
		'EasterMonday2013' : [ 2013, 04, 01 ],
		'VictoriaDay2013' : [ 2013, 05, 20 ],
		'CanadaDay2013' : [ 2013, 07, 01 ],
		'Civic2013' : [ 2013, 08, 05 ],
		'LabourDay2013' : [ 2013, 09, 02 ],
		'ThanksgivingDay2013' : [ 2013, 10, 14 ],
		'RemembranceDay2013' : [ 2013, 11, 11 ],
		'Christmas2013' : [ 2013, 12, 25 ],
		'BoxingDay2013' : [ 2013, 12, 26 ],
		'NewYear2014' : [ 2014, 01, 01 ],
		'FamilyDay2014' : [ 2014, 02, 17 ],
		'GoodFriday2014' : [ 2014, 04, 18 ],
		'EasterMonday2014' : [ 2014, 04, 21 ],
		'VictoriaDay2014' : [ 2014, 05, 19 ],
		'CanadaDay2014' : [ 2014, 07, 01 ],
		'Civic2014' : [ 2014, 08, 04 ],
		'LabourDay2014' : [ 2014, 09, 01 ],
		'ThanksgivingDay2014' : [ 2014, 10, 13 ],
		'RemembranceDay2014' : [ 2014, 11, 11 ],
		'Christmas2014' : [ 2014, 12, 25 ],
		'BoxingDay2014' : [ 2014, 12, 26 ],
		'NewYear2015' : [ 2015, 01, 01 ],
		'FamilyDay2015' : [ 2015, 02, 16 ],
		'GoodFriday2015' : [ 2015, 04, 03 ],
		'EasterMonday2015' : [ 2015, 04, 06 ],
		'VictoriaDay2015' : [ 2015, 05, 18 ],
		'CanadaDay2015' : [ 2015, 07, 01 ],
		'Civic2015' : [ 2015, 08, 03 ],
		'LabourDay2015' : [ 2015, 09, 07 ],
		'ThanksgivingDay2015' : [ 2015, 10, 12 ],
		'RemembranceDay2015' : [ 2015, 11, 11 ],
		'Christmas2015' : [ 2015, 12, 25 ],
		'BoxingDay2015' : [ 2015, 12, 28 ],
		'NewYear2016' : [ 2016, 01, 01 ],
		'FamilyDay2016' : [ 2016, 02, 15 ],
		'GoodFriday2016' : [ 2016, 03, 25 ],
		'EasterMonday2016' : [ 2016, 03, 28 ],
		'VictoriaDay2016' : [ 2016, 05, 23 ],
		'CanadaDay2016' : [ 2016, 07, 01 ],
		'Civic2016' : [ 2016, 08, 01 ],
		'LabourDay2016' : [ 2016, 09, 05 ],
		'ThanksgivingDay2016' : [ 2016, 10, 10 ],
		'RemembranceDay2016' : [ 2016, 11, 11 ],
		'Christmas2016' : [ 2016, 12, 23 ],
		'BoxingDay2016' : [ 2016, 12, 26 ],
		'NewYear2017' : [ 2017, 01, 02 ],
		'FamilyDay2017' : [ 2017, 02, 20 ],
		'GoodFriday2017' : [ 2017, 04, 14 ],
		'EasterMonday2017' : [ 2017, 04, 17 ],
		'VictoriaDay2017' : [ 2017, 05, 22 ],
		'CanadaDay2017' : [ 2017, 07, 03 ],
		'Civic2017' : [ 2017, 08, 07 ],
		'LabourDay2017' : [ 2017, 09, 04 ],
		'ThanksgivingDay2017' : [ 2017, 10, 09 ],
		'RemembranceDay2017' : [ 2017, 11, 13 ],
		'Christmas2017' : [ 2017, 12, 25 ],
		'BoxingDay2017' : [ 2017, 12, 26 ],
		'NewYear2018' : [ 2018, 01, 01 ],
		'FamilyDay2018' : [ 2018, 02, 19 ],
		'GoodFriday2018' : [ 2018, 03, 30 ],
		'EasterMonday2018' : [ 2018, 04, 02 ],
		'VictoriaDay2018' : [ 2018, 05, 21 ],
		'CanadaDay2018' : [ 2018, 07, 02 ],
		'Civic2018' : [ 2018, 08, 06 ],
		'LabourDay2018' : [ 2018, 09, 03 ],
		'ThanksgivingDay2018' : [ 2018, 10, 08 ],
		'RemembranceDay2018' : [ 2018, 11, 12 ],
		'Christmas2018' : [ 2018, 12, 25 ],
		'BoxingDay2018' : [ 2018, 12, 26 ],
		'NewYear2019' : [ 2019, 01, 01 ],
		'FamilyDay2019' : [ 2019, 02, 18 ],
		'GoodFriday2019' : [ 2019, 04, 19 ],
		'EasterMonday2019' : [ 2019, 04, 22 ],
		'VictoriaDay2019' : [ 2019, 05, 20 ],
		'CanadaDay2019' : [ 2019, 07, 01 ],
		'Civic2019' : [ 2019, 08, 05 ],
		'LabourDay2019' : [ 2019, 09, 02 ],
		'ThanksgivingDay2019' : [ 2019, 10, 14 ],
		'RemembranceDay2019' : [ 2019, 11, 11 ],
		'Christmas2019' : [ 2019, 12, 25 ],
		'BoxingDay2019' : [ 2019, 12, 26 ],
		'NewYear2020' : [ 2020, 01, 01 ],
		'FamilyDay2020' : [ 2020, 02, 17 ],
		'GoodFriday2020' : [ 2020, 04, 10 ],
		'EasterMonday2020' : [ 2020, 04, 13 ],
		'VictoriaDay2020' : [ 2020, 05, 18 ],
		'CanadaDay2020' : [ 2020, 07, 01 ],
		'Civic2020' : [ 2020, 08, 03 ],
		'LabourDay2020' : [ 2020, 09, 07 ],
		'ThanksgivingDay2020' : [ 2020, 10, 12 ],
		'RemembranceDay2020' : [ 2020, 11, 11 ],
		'Christmas2020' : [ 2020, 12, 25 ],
		'BoxingDay2020' : [ 2020, 12, 28 ],
		'NewYear2021' : [ 2021, 01, 01 ],
		'FamilyDay2021' : [ 2021, 02, 15 ],
		'GoodFriday2021' : [ 2021, 04, 02 ],
		'EasterMonday2021' : [ 2021, 04, 05 ],
		'VictoriaDay2021' : [ 2021, 05, 24 ],
		'CanadaDay2021' : [ 2021, 07, 01 ],
		'Civic2021' : [ 2021, 08, 02 ],
		'LabourDay2021' : [ 2021, 09, 06 ],
		'ThanksgivingDay2021' : [ 2021, 10, 11 ],
		'RemembranceDay2021' : [ 2021, 11, 11 ],
		'Christmas2021' : [ 2021, 12, 24 ],
		'BoxingDay2021' : [ 2021, 12, 27 ],
		'NewYear2022' : [ 2022, 01, 03 ],
		'FamilyDay2022' : [ 2022, 02, 21 ],
		'GoodFriday2022' : [ 2022, 04, 15 ],
		'EasterMonday2022' : [ 2022, 04, 18 ],
		'VictoriaDay2022' : [ 2022, 05, 23 ],
		'CanadaDay2022' : [ 2022, 07, 01 ],
		'Civic2022' : [ 2022, 08, 01 ],
		'LabourDay2022' : [ 2022, 09, 05 ],
		'ThanksgivingDay2022' : [ 2022, 10, 10 ],
		'RemembranceDay2022' : [ 2022, 11, 11 ],
		'Christmas2022' : [ 2022, 12, 23 ],
		'BoxingDay2022' : [ 2022, 12, 26 ],
		'NewYear2023' : [ 2023, 01, 02 ],
		'FamilyDay2023' : [ 2023, 02, 20 ],
		'GoodFriday2023' : [ 2023, 04, 07 ],
		'EasterMonday2023' : [ 2023, 04, 10 ],
		'VictoriaDay2023' : [ 2023, 05, 22 ],
		'CanadaDay2023' : [ 2023, 07, 03 ],
		'Civic2023' : [ 2023, 08, 07 ],
		'LabourDay2023' : [ 2023, 09, 04 ],
		'ThanksgivingDay2023' : [ 2023, 10, 09 ],
		'RemembranceDay2023' : [ 2023, 11, 13 ],
		'Christmas2023' : [ 2023, 12, 25 ],
		'BoxingDay2023' : [ 2023, 12, 26 ],
		'NewYear2024' : [ 2024, 01, 01 ],
		'FamilyDay2024' : [ 2024, 02, 19 ],
		'GoodFriday2024' : [ 2024, 03, 29 ],
		'EasterMonday2024' : [ 2024, 04, 01 ],
		'VictoriaDay2024' : [ 2024, 05, 20 ],
		'CanadaDay2024' : [ 2024, 07, 01 ],
		'Civic2024' : [ 2024, 08, 05 ],
		'LabourDay2024' : [ 2024, 09, 02 ],
		'ThanksgivingDay2024' : [ 2024, 10, 14 ],
		'RemembranceDay2024' : [ 2024, 11, 11 ],
		'Christmas2024' : [ 2024, 12, 25 ],
		'BoxingDay2024' : [ 2024, 12, 26 ],
		'NewYear2025' : [ 2025, 01, 01 ],
		'FamilyDay2025' : [ 2025, 02, 17 ],
		'GoodFriday2025' : [ 2025, 04, 18 ],
		'EasterMonday2025' : [ 2025, 04, 21 ],
		'VictoriaDay2025' : [ 2025, 05, 19 ],
		'CanadaDay2025' : [ 2025, 07, 01 ],
		'Civic2025' : [ 2025, 08, 04 ],
		'LabourDay2025' : [ 2025, 09, 01 ],
		'ThanksgivingDay2025' : [ 2025, 10, 13 ],
		'RemembranceDay2025' : [ 2025, 11, 11 ],
		'Christmas2025' : [ 2025, 12, 25 ],
		'BoxingDay2025' : [ 2025, 12, 26 ],
		'NewYear2026' : [ 2026, 01, 01 ],
		'FamilyDay2026' : [ 2026, 02, 16 ],
		'GoodFriday2026' : [ 2026, 04, 03 ],
		'EasterMonday2026' : [ 2026, 04, 06 ],
		'VictoriaDay2026' : [ 2026, 05, 18 ],
		'CanadaDay2026' : [ 2026, 07, 01 ],
		'Civic2026' : [ 2026, 08, 03 ],
		'LabourDay2026' : [ 2026, 09, 07 ],
		'ThanksgivingDay2026' : [ 2026, 10, 12 ],
		'RemembranceDay2026' : [ 2026, 11, 11 ],
		'Christmas2026' : [ 2026, 12, 25 ],
		'BoxingDay2026' : [ 2026, 12, 28 ],
		'NewYear2027' : [ 2027, 01, 01 ],
		'FamilyDay2027' : [ 2027, 02, 15 ],
		'GoodFriday2027' : [ 2027, 03, 26 ],
		'EasterMonday2027' : [ 2027, 03, 29 ],
		'VictoriaDay2027' : [ 2027, 05, 24 ],
		'CanadaDay2027' : [ 2027, 07, 01 ],
		'Civic2027' : [ 2027, 08, 02 ],
		'LabourDay2027' : [ 2027, 09, 06 ],
		'ThanksgivingDay2027' : [ 2027, 10, 11 ],
		'RemembranceDay2027' : [ 2027, 11, 11 ],
		'Christmas2027' : [ 2027, 12, 24 ],
		'BoxingDay2027' : [ 2027, 12, 27 ],
		'NewYear2028' : [ 2028, 01, 03 ],
		'FamilyDay2028' : [ 2028, 02, 21 ],
		'GoodFriday2028' : [ 2028, 04, 14 ],
		'EasterMonday2028' : [ 2028, 04, 17 ],
		'VictoriaDay2028' : [ 2028, 05, 22 ],
		'CanadaDay2028' : [ 2028, 07, 03 ],
		'Civic2028' : [ 2028, 08, 07 ],
		'LabourDay2028' : [ 2028, 09, 04 ],
		'ThanksgivingDay2028' : [ 2028, 10, 09 ],
		'RemembranceDay2028' : [ 2028, 11, 13 ],
		'Christmas2028' : [ 2028, 12, 25 ],
		'BoxingDay2028' : [ 2028, 12, 26 ],
		'NewYear2029' : [ 2029, 01, 01 ],
		'FamilyDay2029' : [ 2029, 02, 19 ],
		'GoodFriday2029' : [ 2029, 03, 30 ],
		'EasterMonday2029' : [ 2029, 04, 02 ],
		'VictoriaDay2029' : [ 2029, 05, 21 ],
		'CanadaDay2029' : [ 2029, 07, 02 ],
		'Civic2029' : [ 2029, 08, 06 ],
		'LabourDay2029' : [ 2029, 09, 03 ],
		'ThanksgivingDay2029' : [ 2029, 10, 08 ],
		'RemembranceDay2029' : [ 2029, 11, 12 ],
		'Christmas2029' : [ 2029, 12, 25 ],
		'BoxingDay2029' : [ 2029, 12, 26 ],
		'NewYear2030' : [ 2030, 01, 01 ],
		'FamilyDay2030' : [ 2030, 02, 18 ],
		'GoodFriday2030' : [ 2030, 04, 19 ],
		'EasterMonday2030' : [ 2030, 04, 22 ],
		'VictoriaDay2030' : [ 2030, 05, 20 ],
		'CanadaDay2030' : [ 2030, 07, 01 ],
		'Civic2030' : [ 2030, 08, 05 ],
		'LabourDay2030' : [ 2030, 09, 02 ],
		'ThanksgivingDay2030' : [ 2030, 10, 14 ],
		'RemembranceDay2030' : [ 2030, 11, 11 ],
		'Christmas2030' : [ 2030, 12, 25 ],
		'BoxingDay2030' : [ 2030, 12, 26 ]
	};
	let tem;
	for ( let p in hol)
		{
		tem = hol[p];
		if (A[0] == tem[0] && A[1] == tem[1] && A[2] == tem[2])
			return true;
		}
	return false;
}

function elapsedDaysBetweenDates(obj1, obj2) {
	let startdate = new Date(obj1.year, obj1.month - 1, obj1.day);
	let enddate = new Date(obj2.year, obj2.month - 1, obj2.day);
	if (startdate > enddate)
		{
		let temp = startdate;
		startdate = enddate;
		enddate = temp;
		}
	let daysElap = businessDaysBetween(startdate, enddate);
	return daysElap;
}

function elapsedCalendarDaysBetweenDates(obj1, obj2) {
	let startdate = new Date(obj1.year, obj1.month - 1, obj1.day);
	let enddate = new Date(obj2.year, obj2.month - 1, obj2.day);
	if (startdate > enddate)
		{
		let temp = startdate;
		startdate = enddate;
		enddate = temp;
		}
	let daysElap = calendarDaysBetween(startdate, enddate);
	return daysElap;
}

function calendarDaysBetween(startdate, enddate) {
	let count = 0;
	while (startdate <= enddate)
		{
		++count;
		startdate = new Date(startdate.setDate(startdate.getDate() + 1));
		}
	return count;
}

function businessDaysBetween(startdate, enddate) {
	let tem = startdate.getDay();
	while (startdate.isHoliday() || tem == 0 || tem == 6)
		{
		startdate = new Date(startdate.setDate(startdate.getDate() + 1));
		tem = startdate.getDay();
		}
	tem = enddate.getDay();
	while (enddate.isHoliday() || tem == 0 || tem == 6)
		{
		enddate = new Date(enddate.setDate(enddate.getDate() + 1));
		tem = enddate.getDay();
		}
	let count = 0;
	while (startdate <= enddate)
		{
		tem = startdate.getDay();
		if (!startdate.isHoliday() && tem != 0 && tem != 6)
			{
			++count;
			}
		startdate = new Date(startdate.setDate(startdate.getDate() + 1));
		}
	return count;
}

function setEndDay(numBusinessDays) {
	let obj1 = g_globalObject1.getSelectedDay();
	let newEnddate = new Date(obj1.year, obj1.month - 1, obj1.day);
	let count = 1;
	while (count < numBusinessDays)
		{
		newEnddate = new Date(newEnddate.setDate(newEnddate.getDate() + 1));
		let tem = newEnddate.getDay();
		if (!newEnddate.isHoliday() && tem != 0 && tem != 6)
			{
			++count;
			}
		}
	let yr = newEnddate.getFullYear();
	let mn = newEnddate.getMonth() + 1;
	let dy = newEnddate.getDate();
	g_globalObject2.setSelectedDay({
		year : yr,
		month : mn,
		day : dy
	});
	let obj2 = g_globalObject2.getSelectedDay();
	let dateStr2 =
			obj2.year + "/" + ('0' + obj2.month).slice(-2) + "/" + ('0' + obj2.day).slice(-2);
	$('#enddate').text("End Date " + dateStr2);
	let elapsedCalendarDays = elapsedCalendarDaysBetweenDates(obj1, obj2);
	$('#cal_elapsed').text(elapsedCalendarDays.toString());
}
