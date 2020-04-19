/*
 * @author Shaumik "Dada" Daityari
 * @copyright December 2013
 * (Modified for use in IntraMine. Requires jQuery.)
 * There is just one ToDo list, for all users. On any change, the todo data is written out
 * and display is refreshed. This isn't bulletproof, two saves in the same few
 * milliseconds by different users might cause a version conflict and loss of an item. But on any
 * save, all open views everywhere of the ToDo list are immediately refreshed.
 * see todoGetPutData.js for the details on that.
 */

var todo = todo || {};
	
(function(todo, $) {
		
	let data = {};
	
	let defaults = {
            todoTask: "todo-task",
            todoHeader: "task-header",
            todoDate: "task-date",
            todoDescription: "task-description",
            taskId: "task-",
            formId: "todo-form",
            dataAttribute: "data",
            deleteDiv: "delete-div"
        }, codes = {
            "1" : "#pending",
            "2" : "#inProgress",
            "3" : "#completed"
        };

    todo.init = function (rawData, fullInit, options) {

		data = JSON.parse(rawData);
		data.items = cleanAndSort(data.items, 'id', 1);
		
		removeAllChildrenOfTaskHolders();

        options = options || {};
        options = $.extend({}, defaults, options);

        $.each(data.items, function (index, params) {
            generateElement(params);
        });

        /*generateElement({
            id: "123",
            code: "1",
            title: "asd",
            date: "22/12/2013",
            description: "Blah Blah"
        });*/

        /*removeElement({
            id: "123",
            code: "1",
            title: "asd",
            date: "22/12/2013",
            description: "Blah Blah"
        });*/

        if (fullInit)
        	{
            // Adding drop function to each category of task
            $.each(codes, function (index, value) {
                $(value).droppable({
                    drop: function (event, ui) {
                    	let element = ui.helper,
                                css_id = element.attr("id"),
                                id = css_id.replace(options.taskId, ""),
                                object = data.items[id];
                            
                             	let insertBeforeElement = elementToInsertBefore(index, ui);
                             	let insertBeforeID = 99999;
                             	if (insertBeforeElement !== null)
                             		{
                             		let beforeId = insertBeforeElement.getAttribute("id"); // "task-2"
                             		let idMatch = /(\d+)/.exec(beforeId);
        							if (idMatch !== null)
        								{
        								insertBeforeID = idMatch[1];
        								}
                             		}
                             	object.code = index;
                             	delete data.items[id];
                                data.items = data.items.filter(function(el){return(el != null);});
                             	insertDataItem(object, insertBeforeID);
                             	data.items = cleanAndSort(data.items, 'id', 1);
                             	putData(JSON.stringify(data));

                                // Hide Delete Area
                                $("#" + defaults.deleteDiv).hide();
                                
                                // Force a full reload. Oddly, flicker is minimal, yay.
                                $("." + defaults.todoTask).remove();
                                getToDoData();
                                
                        },
                        hoverClass: "drop-hover"
                })
             });

            // Adding drop function to delete div
            $("#" + options.deleteDiv).droppable({
                drop: function(event, ui) {
                	let element = ui.helper,
                        css_id = element.attr("id"),
                        id = css_id.replace(options.taskId, ""),
                        object = data.items[id];

                    // Removing old element
                    //removeElement(object);

                    // Updating local storage
                    delete data.items[id];
                    data.items = data.items.filter(function(el){return(el != null);});
                    data.items = cleanAndSort(data.items, 'id', 1);
                    putData(JSON.stringify(data));
    				
                    // Hiding Delete Area
                    $("#" + defaults.deleteDiv).hide();
                    // Force a full reload. Oddly, flicker is minimal, yay.
                    $("." + defaults.todoTask).remove();
                    getToDoData();
                },
                hoverClass: "drop-hover"
            })
            
            // Add drop to Add/Edit a Task
            $("#" + options.formId).droppable({
            	drop:  function(event, ui) {
            		let element = ui.helper,
                    css_id = element.attr("id"),
                    id = css_id.replace(options.taskId, ""),
                    object = data.items[id],
                    index = object.code;
            		let inputs = $("#" + defaults.formId + " :input");
            		
            		// Set input values from object.
            		inputs[0].value = object.title;
            		inputs[1].value = object.description;
            		inputs[2].value = object.date;
            		// 3 is the save button
            		inputs[4].value = index;
           		
            		removeElement(object);
            		delete data.items[id];
            		data.items = data.items.filter(function(el){return(el != null);});
            		data.items = cleanAndSort(data.items, 'id', 1);
            		putData(JSON.stringify(data));
            		$("#" + defaults.deleteDiv).hide();
            		getToDoData();
            	},
            	hoverClass: "drop-hover"
            })
        }
    };

    // Add Task
    let generateElement = function(params){
    	let parent = $(codes[params.code]),
            wrapper;

        if (!parent) {
            return;
        }

        wrapper = $("<div />", {
            "class" : defaults.todoTask,
            "id" : defaults.taskId + params.id,
            "data" : params.id
        }).appendTo(parent);

        $("<div />", {
            "class" : defaults.todoHeader,
            "text": params.title
        }).appendTo(wrapper);

        $("<div />", {
            "class" : defaults.todoDate,
            "text": params.date
        }).appendTo(wrapper);

        $("<div />", {
            "class" : defaults.todoDescription,
            "text": params.description
        }).appendTo(wrapper);

	    wrapper.draggable({
            start: function() {
                $("#" + defaults.deleteDiv).show();
            },
            stop: function() {
                $("#" + defaults.deleteDiv).hide();
            },
	        revert: "invalid",
	        revertDuration : 200
        });

    };

    // Remove task
    let removeElement = function (params) {
    	if (params)
    		{
            $("#" + defaults.taskId + params.id).remove();
            //getToDoData();
            }
    	else
    		{
    		// Something wrong, desperately try to re-init.
    		$("." + defaults.todoTask).remove();
    		getToDoData();
    		}
    };

    todo.add = function() {
    	let inputs = $("#" + defaults.formId + " :input"),
            errorMessage = "Title cannot be empty",
            id, title, description, date, tempData, index;

        if (inputs.length !== 5) {
        	generateDialog("todo.js#todo.add() OOOPs inputs.length is , " + inputs.length);
            return;
        }

        title = inputs[0].value;
        description = inputs[1].value; //.replace(/\n/g, '<br\\/>');
        
        date = inputs[2].value;
        index = inputs[4].value;

        if (!title) {
            generateDialog(errorMessage);
            return;
        }

        //id = new Date().getTime();
        id = data.items.length;

        tempData = {
            id : id,
            code: index,
            title: title,
            date: date,
            description: description
        };

        // Save to local disk.
        data.items[id] = tempData;
        //localStorage.setItem("todoData", JSON.stringify(data));
        data.items = cleanAndSort(data.items, 'id', 1);
        putData(JSON.stringify(data));
		
        // Generate Todo Element
        generateElement(tempData);

        // Reset Form
        inputs[0].value = "";
        inputs[1].value = "";
        inputs[2].value = "";
        inputs[4].value = "1";
    };

    let generateDialog = function (message) {
    	let responseId = "response-dialog",
            title = "Ahem",
            responseDialog = $("#" + responseId),
            buttonOptions;

        if (!responseDialog.length) {
            responseDialog = $("<div />", {
                    title: title,
                    id: responseId
            }).appendTo($("body"));
        }

        responseDialog.html(message);

        buttonOptions = {
            "Ok" : function () {
                responseDialog.dialog("close");
            }
        };

	    responseDialog.dialog({
            autoOpen: true,
            width: 400,
            modal: true,
            closeOnEscape: true,
            buttons: buttonOptions
        });
    };

    // NOT UPDATED, not needed.
//    todo.clear = function () {
//        data = {};
//        //localStorage.setItem("todoData", JSON.stringify(data));
//		  putData(JSON.stringify(data));
//        $("." + defaults.todoTask).remove();
//    };

    function cleanAndSort(objArray, prop, direction){
        if (arguments.length<2) throw new Error("ARRAY, AND OBJECT PROPERTY MINIMUM ARGUMENTS, OPTIONAL DIRECTION");
        if (!Array.isArray(objArray)) throw new Error("FIRST ARGUMENT NOT AN ARRAY");
        let clone = objArray.slice(0);
        // Remove nulls.
        clone = clone.filter(function(el){return(el != null);});
        // sort
        const direct = arguments.length>2 ? arguments[2] : 1; //Default to ascending
        clone.sort(function(a,b){
        	if (a !== null && b !== null)
        		{
                a = a[prop];
                b = b[prop];
                return ( (a < b) ? -1*direct : ((a > b) ? 1*direct : 0) );
        		}
        	return(0);
        });
        // Reassign id's to be 0..length-1, same as array index. This removes duplicates
        // and fills in missing id's.
        for (i = 0; i < clone.length; ++i)
        	{
        	clone[i].id = i;
        	}
        return clone;
    }
    
    function  elementToInsertBefore(index, ui)
    	{
    	let elemInsBefore = null;
		let droppedOffTop = ui.offset.top;
		let draggedID = ui.helper.attr("id");
		let parentId = codes[index];
		parentId = parentId.substring(1);
		let dropParent = document.getElementById(parentId); //$(codes[index]);
		let children = dropParent.children;
		
		for (let i = 0; i < children.length; ++i)
			{
			let item = children[i];
			let nname = item.nodeName;
			if (nname === "DIV")
				{
				let rect = item.getBoundingClientRect();
				let itemTop = rect.top;
				if (droppedOffTop < itemTop)
					{
					// Avoid comparing dragged item against itself. Penalty for not
					// doing so: thirty minutes of head scratching.
					let itemID = item.getAttribute("id");
					if (draggedID !== itemID)
						{
						elemInsBefore = item;
						break;
						}
					}
				}
			}
		
		return(elemInsBefore);
		}

    // This should be followed by cleanAndSort() to restore array item id values to be the same as
    // position in array. Item id values are used as HTML element "id" entries, so here when
    // inserting a new data item we just ensure the id values are different and in the correct order.
    function insertDataItem(object, insertBeforeID) {
    	let newCode = object.code;
    	let arr = data.items;
    	let oldCatHighestCode = 0;
    	for (i = 0; i < arr.length; ++i)
			{
			let item = arr[i];
			let oldID = item.id;
			let oldCode = item.code;
			if (oldCode === newCode && oldCatHighestCode < oldCode)
				{
				oldCatHighestCode = oldCode;
				}
			}
    	++oldCatHighestCode;
    	
    	let insBeforeSeen = false;
    	for (i = 0; i < arr.length; ++i)
    		{
    		let item = arr[i];
    		let oldCode = item.code;
    		if (oldCode === newCode) // in same category
    			{
    			if (arr[i].id >= insertBeforeID)
    				{
    				arr[i].id = arr[i].id + 1;
    				}
    			}
    		else // in a different category
    			{
    			arr[i].id = arr[i].id + oldCatHighestCode;
    			}
    		}
    	
    	// Append object to array (with new id).
    	object.id = insertBeforeID;
    	data.items[arr.length] = object;
    	}

//	let parentId = codes[index];
//	parentId = parentId.substring(1);

   function removeAllChildrenOfTaskHolders() {
	   for (let idx in codes)
		   {
		   let theID = codes[idx];
		   theID = theID.substring(1);
		   let parent = document.getElementById(theID);
		   if (parent !== null)
			   {
			   // Delete all div children (avoid deleting H3 header).
			   while (parent.lastChild && parent.lastChild.nodeName === "DIV")
			   		{
				   parent.removeChild(parent.lastChild);
			   		}
			   }
		   }
   		}
})(todo, jQuery);