/** tablesort.js: add sort to all tables, really .txt files only.
 * Darn it, DOM is blown away by link addition, this doesn't work.
 */

const getCellValue = (tr, idx) => tr.children[idx].innerText || tr.children[idx].textContent;

const comparer = (idx, asc) => (a, b) => ((v1, v2) => 
    v1 !== '' && v2 !== '' && !isNaN(v1) && !isNaN(v2) ? v1 - v2 : v1.toString().localeCompare(v2)
    )(getCellValue(asc ? a : b, idx), getCellValue(asc ? b : a, idx));


//function addTableSorting() {
//
//document.querySelectorAll('th').forEach(th => th.addEventListener('click', (() => {
//const table = th.closest('table');
//const tbody = table.querySelector('tbody');
//Array.from(tbody.querySelectorAll('tr'))
//  .sort(comparer(Array.from(th.parentNode.children).indexOf(th), this.asc = !this.asc))
//  .forEach(tr => tbody.appendChild(tr) );
//})));
//
//}

function addTableSorting() {

document.querySelectorAll('th').forEach(function(th) {
console.log("Adding click");
th.addEventListener('click', (() => {
const table = th.closest('table');
const tbody = table.querySelector('tbody');
Array.from(tbody.querySelectorAll('tr'))
  .sort(comparer(Array.from(th.parentNode.children).indexOf(th), this.asc = !this.asc))
  .forEach(tr => tbody.appendChild(tr) );
}))
});

}

window.addEventListener("load", addTableSorting);