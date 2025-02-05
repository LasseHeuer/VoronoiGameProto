
import { symmetricLevel } from './levelgenerators.js'
import { config } from './settings.js'

const BORDERPOINTSPACING = 50;  // distance between invisible border points
CONST BORDERPOINTOFFSET = 30;   // offset away from canvas

class Point {
	constructor (x, y, player) {
		this.x = x
		this.y = y
		this.player = player
	}
	function asList() {
		return [this.x, this.y];
	}
	function isColor(color) {
		return this.color == color;
	}
	function isBorder() {
		return this.player === null;
	}
}

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

/*
  Represents the current state of the game.
  */
class GameState {
	constructor (points) {
		this.points = points
	}
}

export default class Game {
	constructor (canvas) {
		this.ctx = canvas.getContext("2d");
		this.width = canvas.width;
		this.height = canvas.height;
		this.config = config
		this.borderPoints = generateBorderPoints(this.width, this.height, BORDERPOINTSPACING, BORDERPOINTOFFSET)
	}

	function initGameState() {
		let newPoints = symmetricLevel(
			this.config.numCells,
			this.width,
			this.height,
			this.config.boundaryMargin,
			this.config.spreadFactor);
		points = []
		for (let point in newPoints) {
			points.push(new Point(point[0], point[1]))
		}
	}
}
