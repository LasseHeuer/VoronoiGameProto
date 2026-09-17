extends GutTest

## Tests fuer sim/cell_geometry.gd: Geometrie der Farbausbreitung.

const RECT := Rect2(0.0, 0.0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)


func _board() -> BoardState:
	var board := BoardState.new()
	board.points = PackedVector2Array([
		Vector2(200.0, 290.0), Vector2(360.0, 305.0), Vector2(570.0, 300.0)])
	board.dummy_points = PackedVector2Array()
	board.reset_colors()
	board.set_cell_color(0, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(1, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(2, GameConfig.COLOR_PLAYER2)
	return board


func test_from_voronoi_takes_areas_and_neighbors() -> void:
	var board := _board()
	var voronoi := Voronoi.from_board(board, RECT)
	var geometry := CellGeometry.from_voronoi(voronoi)

	assert_eq(geometry.count(), voronoi.real_count)
	for i in range(voronoi.real_count):
		assert_almost_eq(geometry.areas[i], voronoi.area(i), 0.0001)
		assert_eq(geometry.neighbors[i], voronoi.visible_neighbors_of(i))


func test_from_voronoi_ignores_dummy_points() -> void:
	var board := _board()
	var dummy_count := Territories.generate_dummy_points().size()
	board.dummy_points = Territories.generate_dummy_points()
	var voronoi := Voronoi.from_board(board, RECT)
	var geometry := CellGeometry.from_voronoi(voronoi)

	assert_eq(geometry.count(), board.points.size(), "Dummies zaehlen nicht als Zellen")
	assert_eq(voronoi.points.size(), board.points.size() + dummy_count, "das Voronoi kennt sie aber")


func test_from_voronoi_keeps_the_areas() -> void:
	var board := _board()
	var voronoi := Voronoi.from_board(board, RECT)
	var geometry := CellGeometry.from_voronoi(voronoi)
	var areas := geometry.areas.duplicate()
	areas[0] = 123.0

	var patched := CellGeometry.new()
	patched.areas = areas
	patched.neighbors = geometry.neighbors

	assert_almost_eq(patched.areas[0], 123.0, 0.0001)
	assert_almost_eq(geometry.areas[0], voronoi.area(0), 0.0001, "das Original bleibt unveraendert")
	assert_eq(patched.neighbors, geometry.neighbors)
	assert_eq(patched.count(), geometry.count())
