/*
  Point in 2d game space. Has coordinate `x`, `y`
  and `player` which is null for border points
  or a string for the player name.
 */
class Point {
	constructor (x, y, player) {
		this.x = x
		this.y = y
		this.player = player
	}
	asList() {
		return [this.x, this.y];
	}
	isColor(color) {
		return this.color == color;
	}
	isBorder() {
		return this.player === null;
	}
}

/*
  generate points along the border of the canvas.
  `offset` offsets the points towards outside the canvas.
 */
function generateBorderPoints(width, height, spacing, offset) {
	let borderPoints = [];
	for (let x = -offset; x <= width + offset; x += spacing) {
		topPoint = new Point(x, -offset, null)
		botPoint = new Point(x, height + offset, null)
		borderPoints.push(topPoint, botPoint);
	}
	for (let y = -offset; y <= height + offset; y += spacing) {
		rightPoint = new Point(width + offset, y, null)
		leftPoint = new Point(-offset, y, null)
		borderPoints.push(leftPoint, rightPoint);
	}
	return borderPoints;
}
