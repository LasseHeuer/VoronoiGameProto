/*
  Represents the current state of the game.
  */
class GameState {
	constructor (points) {
		this.points = points;
		this.hasChanged = true;
		this.update();
	}

	setPoint(idx, point) {
		this.points[idx] = point;
		this.hasChanged = true;
	}

	getPoint(idx) {
		return this.points[idx];
	}

	update() {
		if (!this.hasChanged || this.points.length == 0)
			return;
		this.delauny = d3.Delaunay.from(this.points.reduce((p) => p.toList()));
		this.voronoi = delaunay.voronoi([0, 0, width, height]);
		this.hasChanged = false;
	}
}
