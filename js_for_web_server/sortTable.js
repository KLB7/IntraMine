/**
 * sortTable.js: sort a table by column contents. From
 * https://stackoverflow.com/questions/14267781/sorting-html-table-with-javascript
 *  See intramine_status.pl#refreshServerStatus() for use in IntraMine.
 */

function sortTable(table_id, sortColumn){
    let tableData = document.getElementById(table_id).getElementsByTagName('tbody').item(0);
    let rowData = tableData.getElementsByTagName('tr');            
    for(let i = 0; i < rowData.length - 1; i++){
        for(let j = 0; j < rowData.length - (i + 1); j++){
        	if(rowData.item(j).getElementsByTagName('td').item(sortColumn).innerHTML > rowData.item(j+1).getElementsByTagName('td').item(sortColumn).innerHTML){
                tableData.insertBefore(rowData.item(j+1),rowData.item(j));
            }
        }
    }
}
