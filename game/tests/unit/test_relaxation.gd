extends GutTest

## Tests fuer sim/relaxation.gd.

const RECT := Rect2(0.0, 0.0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)


func _config() -> GameConfig:
	return GameConfig.new()


func _board_with_points(points: PackedVector2Array) -> BoardState:
	var board := BoardState.new()
	board.points = points
	board.dummy_points = PackedVector2Array()
	board.velocities = PackedVector2Array()
	board.velocities.resize(points.size())
	board.velocities.fill(Vector2.ZERO)
	board.reset_colors()
	return board


func test_points_far_apart_are_untouched() -> void:
	var board := _board_with_points(PackedVector2Array([Vector2(100, 100), Vector2(500, 400)]))
	var before := board.points.duplicate()
	var config := _config()
	Relaxation.push_points_no_weight(board, config)
	assert_eq(board.points, before)


func test_two_near_points_are_pushed_apart() -> void:
	var board := _board_with_points(PackedVector2Array([Vector2(100, 300), Vector2(110, 300)]))
	var config := _config()
	Relaxation.push_points_no_weight(board, config)
	var distance := board.points[0].distance_to(board.points[1])
	assert_almost_eq(distance, 16.0, 0.001, "Abstand waechst um den doppelten halben Overlap")
	assert_almost_eq((board.points[0] + board.points[1]).x * 0.5, 105.0, 0.001, "Mittelpunkt bleibt")


func test_weight_influence_one_moves_only_the_lighter_cell() -> void:
	var board := _board_with_points(PackedVector2Array([Vector2(100, 300), Vector2(110, 300)]))
	var config := _config()
	config.weight_influence = 1.0
	var weights := PackedFloat32Array([500.0, 1.0])
	Relaxation.push_points(board, config, weights)
	assert_almost_eq(board.points[0].x, 100.0, 0.001, "schwere Zelle bleibt liegen")
	assert_almost_eq(board.points[1].x, 116.0, 0.001, "leichte Zelle wird um overlap verschoben")


func test_weight_influence_interpolates() -> void:
	var board := _board_with_points(PackedVector2Array([Vector2(100, 300), Vector2(110, 300)]))
	var config := _config()
	config.weight_influence = 0.5
	var weights := PackedFloat32Array([1000.0, 1.0])
	Relaxation.push_points(board, config, weights)
	assert_gt(board.points[1].x - board.points[0].x, 10.0)
	assert_lt(board.points[1].x - board.points[0].x, 16.0)


func test_compute_cell_weights_inherits_within_same_color() -> void:
	var board := _board_with_points(PackedVector2Array([Vector2(100.0, 300.0), Vector2(200.0, 300.0)]))
	var voronoi := Voronoi.from_points(board.points, RECT)
	board.set_cell_color(0, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(1, GameConfig.COLOR_PLAYER1)
	var weights := Relaxation.compute_cell_weights(board, voronoi)
	assert_almost_eq(weights[0], weights[1], 0.01, "gleiche Farbe erbt das groessere Gewicht")
	assert_almost_eq(weights[1], voronoi.area(1), 0.01)


func test_compute_cell_weights_does_not_mix_colors() -> void:
	var board := _board_with_points(PackedVector2Array([Vector2(100.0, 300.0), Vector2(200.0, 300.0)]))
	var voronoi := Voronoi.from_points(board.points, RECT)
	board.set_cell_color(0, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(1, GameConfig.COLOR_PLAYER2)
	var weights := Relaxation.compute_cell_weights(board, voronoi)
	assert_almost_eq(weights[0], voronoi.area(0), 0.01)
	assert_almost_eq(weights[1], voronoi.area(1), 0.01)


func test_compute_cell_weights_ignores_uncolored_cells() -> void:
	var board := _board_with_points(PackedVector2Array([Vector2(100.0, 300.0), Vector2(200.0, 300.0)]))
	var voronoi := Voronoi.from_points(board.points, RECT)
	var weights := Relaxation.compute_cell_weights(board, voronoi)
	assert_almost_eq(weights[0], voronoi.area(0), 0.01)
	assert_almost_eq(weights[1], voronoi.area(1), 0.01)


func test_clamp_to_canvas() -> void:
	var board := _board_with_points(PackedVector2Array([Vector2(-20.0, -10.0), Vector2(950.0, 700.0)]))
	var config := _config()
	Relaxation.clamp_to_canvas(board, config)
	assert_almost_eq(board.points[0].x, config.border_margin, 0.001)
	assert_almost_eq(board.points[0].y, config.border_margin, 0.001)
	assert_almost_eq(board.points[1].x, GameConfig.BOARD_WIDTH - config.border_margin, 0.001)
	assert_almost_eq(board.points[1].y, GameConfig.BOARD_HEIGHT - config.border_margin, 0.001)


func test_update_point_positions_applies_damped_velocity() -> void:
	var board := _board_with_points(PackedVector2Array([Vector2(100.0, 100.0)]))
	board.velocities[0] = Vector2(2.0, 0.0)
	Relaxation.update_point_positions(board)
	# Geschwindigkeit wird zuerst gedaempft (0.9), dann angewendet.
	assert_almost_eq(board.points[0].x, 101.8, 0.001)
	assert_almost_eq(board.velocities[0].x, 1.8, 0.001)
