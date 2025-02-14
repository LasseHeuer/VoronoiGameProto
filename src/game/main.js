/*
  Entry point of the game. Connect ui-elements to the engine.
*/


function start() {
	console.log("Starting Voronoi Game Prototype!")
	const canvas = document.getElementById("voronoiCanvas");
	const game = new Game(canvas);
	game.start();
}
