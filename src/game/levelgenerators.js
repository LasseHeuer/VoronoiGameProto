/*
  different ways of throwing points at a canvas.
*/

/*
  generate random points.
  num          -- number of points
  w            -- width of canvas
  h            -- height of canvas
  margin       -- distance from border
  spreadFactor -- 
 */
function randomLevel(num, w, h, margin, spreadFactor) {
  const arr = [];
  for (let i = 0; i < num; i++) {
    let rx = Math.random();
    let ry = Math.random();
    rx = Math.pow(rx, 1 - spreadFactor);
    ry = Math.pow(ry, 1 - spreadFactor);
    const x = margin + rx * (w - 2*margin);
    const y = margin + ry * (h - 2*margin);
    arr.push([x, y]);
  }
  return arr;
}

/*
  generate random points with mirror symmetry on center y-axis.
 */
function symmetricLevel(num, w, h, margin, spreadFactor) {
  const arr = [];
  ww = w / 2;
  for (let i = 0; i < num; i++) {
    let rx = Math.random();
    let ry = Math.random();
    rx = Math.pow(rx, 1 - spreadFactor);
    ry = Math.pow(ry, 1 - spreadFactor);
    const x = margin + rx * (ww - 2*margin);
    const y = margin + ry * (h - 2*margin);
    arr.push([x, y]);
    arr.push([w - x, y]);
  }
  return arr;
}
