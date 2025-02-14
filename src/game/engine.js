const BORDERPOINTSPACING = 50;  // distance between invisible border points
const BORDERPOINTOFFSET = 30;   // offset away from canvas


class Game {
	constructor (canvas) {
		this.ctx = canvas.getContext("2d");
		this.width = canvas.width;
		this.height = canvas.height;
		this.config = config;
		this.borderPoints = generateBorderPoints(this.width, this.height, BORDERPOINTSPACING, BORDERPOINTOFFSET);
		this.initGameState();
		console.log("New Game started!");
	}

	initGameState() {
		let newPoints = symmetricLevel(
			this.config.numCells,
			this.width,
			this.height,
			this.config.boundaryMargin,
			this.config.spreadFactor);
		let points = []
		for (let point in newPoints) {
			points.push(new Point(point[0], point[1]));
		}
		this.gameState = new GameState(points)
	}

	start() {
		
	}
}
