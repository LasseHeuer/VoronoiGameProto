extends GutTest

## Tests fuer sim/territories.gd und die Zugregeln aus sim/turns.gd.

func _config(cell_count := 20) -> GameConfig:
	var config := GameConfig.new()
	config.cell_count = cell_count
	return config


func test_generate_points_is_mirrored_and_doubled() -> void:
	var config := _config(20)
	var points := Territories.generate_points(config, DeterministicRng.new(9))
	assert_eq(points.size(), 40, "num Zellen ergeben 2 * num Punkte")
	for i in range(0, points.size(), 2):
		var left := points[i]
		var right := points[i + 1]
		assert_almost_eq(left.y, right.y, 0.0001)
		assert_almost_eq(left.x + right.x, GameConfig.BOARD_WIDTH, 0.0001)
		assert_true(left.x <= GameConfig.BOARD_WIDTH * 0.5 - 30.0 + 0.01)
		assert_true(right.x >= GameConfig.BOARD_WIDTH * 0.5 + 30.0 - 0.01)


func test_generate_points_stays_inside_the_margins() -> void:
	var config := _config(100)
	var points := Territories.generate_points(config, DeterministicRng.new(3))
	assert_eq(points.size(), 200)
	for p in points:
		assert_between(p.x, GameConfig.POINT_MARGIN - 0.01, GameConfig.BOARD_WIDTH - GameConfig.POINT_MARGIN + 0.01)
		assert_between(p.y, GameConfig.POINT_MARGIN - 0.01, GameConfig.BOARD_HEIGHT - GameConfig.POINT_MARGIN + 0.01)


func test_generate_points_is_reproducible() -> void:
	var config := _config(20)
	var a := Territories.generate_points(config, DeterministicRng.new(1234))
	var b := Territories.generate_points(config, DeterministicRng.new(1234))
	assert_eq(a, b)


func test_dummy_points_sit_outside_the_board() -> void:
	var dummies := Territories.generate_dummy_points()
	assert_eq(dummies.size(), 68)
	for p in dummies:
		var outside := p.x < 0.0 or p.x > GameConfig.BOARD_WIDTH or p.y < 0.0 or p.y > GameConfig.BOARD_HEIGHT
		assert_true(outside, "Dummy-Punkt %s liegt ausserhalb" % p)


func test_new_game_creates_two_colored_seeds() -> void:
	var config := _config(20)
	var board := BoardState.new()
	board.dummy_points = Territories.generate_dummy_points()
	Territories.init_on_new_game(board, config, DeterministicRng.new(20250116))

	var count_p1 := 0
	var count_p2 := 0
	for i in range(board.cell_colors.size()):
		if board.cell_color(i) == GameConfig.COLOR_PLAYER1:
			count_p1 += 1
		elif board.cell_color(i) == GameConfig.COLOR_PLAYER2:
			count_p2 += 1
	assert_gt(count_p1, 0, "Spieler 1 besitzt mindestens eine Zelle")
	assert_gt(count_p2, 0, "Spieler 2 besitzt mindestens eine Zelle")
	assert_eq(board.active_color, GameConfig.COLOR_PLAYER1, "Spieler 1 beginnt")


func test_new_game_is_reproducible() -> void:
	var config := _config(20)
	var first := BoardState.new()
	first.dummy_points = Territories.generate_dummy_points()
	Territories.init_on_new_game(first, config, DeterministicRng.new(4242))
	var second := BoardState.new()
	second.dummy_points = Territories.generate_dummy_points()
	Territories.init_on_new_game(second, config, DeterministicRng.new(4242))
	assert_eq(first.points, second.points)
	assert_eq(first.cell_colors, second.cell_colors)


func test_new_game_balances_color_areas() -> void:
	var config := _config(20)
	var board := BoardState.new()
	board.dummy_points = Territories.generate_dummy_points()
	Territories.init_on_new_game(board, config, DeterministicRng.new(777))
	var rect := Rect2(0, 0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)
	var main := Voronoi.from_board(board, rect)
	var area1 := Territories.total_area_for_color(board, main, GameConfig.COLOR_PLAYER1)
	var area2 := Territories.total_area_for_color(board, main, GameConfig.COLOR_PLAYER2)
	var tolerance := GameConfig.BALANCE_TOLERANCE_RATIO * GameConfig.BOARD_AREA
	assert_lt(absf(area1 - area2), tolerance, "Flaechen sind innerhalb der Toleranz")


func test_colors_spread_over_visible_neighbours() -> void:
	var config := _config(20)
	var board := BoardState.new()
	board.dummy_points = Territories.generate_dummy_points()
	board.points = Territories.generate_points(config, DeterministicRng.new(8))
	board.reset_colors()
	board.set_cell_color(0, GameConfig.COLOR_PLAYER1)
	var rect := Rect2(0, 0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)
	var main := Voronoi.from_board(board, rect)
	Territories.update_colors_by_largest_neighbor(board, main, GameConfig.COLOR_PROPAGATION_ITERATIONS)
	var colored := 0
	for i in range(board.cell_colors.size()):
		if board.cell_color(i) != "":
			colored += 1
	assert_gt(colored, 1, "die Farbe breitet sich auf Nachbarzellen aus")


func test_largest_neighbor_by_color() -> void:
	var config := _config(20)
	var board := BoardState.new()
	board.dummy_points = Territories.generate_dummy_points()
	board.points = Territories.generate_points(config, DeterministicRng.new(11))
	board.reset_colors()
	var rect := Rect2(0, 0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)
	var main := Voronoi.from_board(board, rect)
	board.set_cell_color(1, GameConfig.COLOR_PLAYER2)
	var found := Territories.largest_neighbor_by_color(board, main, 0, GameConfig.COLOR_PLAYER2)
	if main.delaunay().neighbors(0).has(1):
		assert_eq(found["cell_id"], 1)
		assert_gt(found["max_area"], 0.0)
	else:
		assert_eq(found["cell_id"], -1)


func test_turns_drag_permission_follows_active_color() -> void:
	var config := _config(4)
	var board := BoardState.new()
	board.points = PackedVector2Array([Vector2(100, 100), Vector2(200, 200)])
	board.reset_colors()
	board.active_color = GameConfig.COLOR_PLAYER1
	board.set_cell_color(0, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(1, GameConfig.COLOR_PLAYER2)
	assert_true(Turns.can_start_drag(board, 0, config))
	assert_false(Turns.can_start_drag(board, 1, config))

	config.alternating_moves = false
	assert_true(Turns.can_start_drag(board, 1, config))


func test_turns_automatic_switch_only_after_movement() -> void:
	var config := _config(4)
	var board := BoardState.new()
	board.points = PackedVector2Array([Vector2(100, 100), Vector2(200, 200)])
	board.reset_colors()
	board.active_color = GameConfig.COLOR_PLAYER1
	board.set_cell_color(0, GameConfig.COLOR_PLAYER2)
	assert_false(Turns.should_switch_automatically(board, 0, config, 0.0))
	assert_false(Turns.should_switch_automatically(board, 0, config, GameConfig.MOVE_THRESHOLD))
	assert_true(Turns.should_switch_automatically(board, 0, config, 5.0))

	config.alternating_moves = false
	assert_false(Turns.should_switch_automatically(board, 0, config, 5.0))


func test_turns_toggle() -> void:
	assert_eq(Turns.toggled_color(GameConfig.COLOR_PLAYER1), GameConfig.COLOR_PLAYER2)
	assert_eq(Turns.toggled_color(GameConfig.COLOR_PLAYER2), GameConfig.COLOR_PLAYER1)
