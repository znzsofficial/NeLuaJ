'use strict';
const output = document.getElementById('count');
const increment = document.getElementById('increment');
const reset = document.getElementById('reset');
let count = 0;
function render() {
  output.textContent = String(count);
  reset.disabled = count === 0;
  increment.disabled = count >= 9999;
}
increment.addEventListener('click', function () {
  if (count < 9999) count += 1;
  render();
});
reset.addEventListener('click', function () {
  count = 0;
  render();
});
render();
