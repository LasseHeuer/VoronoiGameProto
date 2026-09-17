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
	assert_eq(dummies.size(), 72)
	for p in dummies:
		var outside := p.x < 0.0 or p.x > GameConfig.BOARD_WIDTH or p.y < 0.0 or p.y > GameConfig.BOARD_HEIGHT
		assert_true(outside, "Dummy-Punkt %s liegt ausserhalb" % p)
	assert_eq(Territories.generate_dummy_points()[0].y, -GameConfig.DUMMY_MARGIN,
		"Dummy-Rand liegt ausserhalb des Spielpunkt-Rands")


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
	for i in range(board.points.size()):
		assert_between(board.points[i].x, GameConfig.POINT_MARGIN - 0.01,
			GameConfig.BOARD_WIDTH - GameConfig.POINT_MARGIN + 0.01)
		assert_between(board.points[i].y, GameConfig.POINT_MARGIN - 0.01,
			GameConfig.BOARD_HEIGHT - GameConfig.POINT_MARGIN + 0.01)


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


func test_small_point_move_does_not_flip_the_whole_board() -> void:
	var config := _config(20)
	var board := BoardState.new()
	board.dummy_points = Territories.generate_dummy_points()
	Territories.init_on_new_game(board, config, DeterministicRng.new(20250116))
	var before := board.color_ids()
	var moved := board.points
	moved[0] += Vector2(1.0, 0.0)
	board.points = moved
	var main := Voronoi.from_board(board,
		Rect2(0.0, 0.0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT))
	var steps := Territories.color_change_steps(CellGeometry.from_voronoi(main), before,
		GameConfig.COLOR_PROPAGATION_ITERATIONS)
	var changed := {}
	for step in steps:
		changed[int(step["cell"])] = true
	assert_lt(changed.size(), board.points.size() - 1,
		"eine kleine Bewegung darf keine globale Farb-Kaskade ausloesen")


func test_color_count_balancing_handles_non_mirrored_setup() -> void:
	var board := BoardState.new()
	board.points = PackedVector2Array([
		Vector2(120.0, 120.0), Vector2(300.0, 180.0), Vector2(520.0, 140.0),
		Vector2(700.0, 300.0), Vector2(420.0, 470.0)])
	board.reset_colors()
	for i in range(4):
		board.set_cell_color(i, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(4, GameConfig.COLOR_PLAYER2)
	var voronoi := Voronoi.from_points(board.points,
		Rect2(0.0, 0.0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT))
	Territories.balance_color_counts(board, voronoi)

	var count1 := 0
	var count2 := 0
	for color in board.cell_colors:
		count1 += 1 if color == GameConfig.COLOR_PLAYER1 else 0
		count2 += 1 if color == GameConfig.COLOR_PLAYER2 else 0
	assert_eq(count1, 3, "Spieler 1 bekommt bei ungerader Zellzahl die mittlere Anzahl")
	assert_eq(count2, 2, "Spieler 2 bekommt bei ungerader Zellzahl die mittlere Anzahl")


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


func test_change_steps_reproduce_the_spread_result() -> void:
	var config := _config(30)
	var board := BoardState.new()
	board.dummy_points = Territories.generate_dummy_points()
	board.points = Territories.generate_points(config, DeterministicRng.new(21))
	board.reset_colors()
	board.set_cell_color(0, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(1, GameConfig.COLOR_PLAYER2)
	var rect := Rect2(0, 0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)
	var main := Voronoi.from_board(board, rect)
	var ids := board.color_ids()
	var geometry := CellGeometry.from_voronoi(main)

	var steps := Territories.color_change_steps(geometry, ids, GameConfig.COLOR_PROPAGATION_ITERATIONS)
	assert_gt(steps.size(), 0, "es gibt Farbwechsel")
	assert_eq(board.color_ids(), ids, "die Rechnung laesst den Zustand unveraendert")

	var after := Territories.propagate_ids(geometry, board.color_ids(), GameConfig.COLOR_PROPAGATION_ITERATIONS)
	for i in range(steps.size()):
		assert_true(steps[i].has("cell") and steps[i].has("color"))

	board.apply_color_ids(after)
	assert_eq(board.color_ids(), after)
	# Nach dem Anwenden ist die Ausbreitung fertig: kein weiterer Wechsel.
	assert_eq(Territories.color_change_steps(geometry, board.color_ids(), GameConfig.COLOR_PROPAGATION_ITERATIONS).size(), 0)


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


func test_relative_influence_sums_larger_support_and_enemy_pressure() -> void:
	var geometry := CellGeometry.new()
	geometry.areas = PackedFloat32Array([100.0, 125.0, 200.0, 80.0])
	geometry.neighbors = [PackedInt32Array([1, 2, 3]), PackedInt32Array(),
		PackedInt32Array(), PackedInt32Array()]
	geometry.edge_lengths = [{1: 2.0, 2: 3.0, 3: 4.0}, {}, {}, {}]
	var ids := PackedByteArray([1, 1, 2, 2])

	assert_almost_eq(Territories.relative_neighbor_raw_value(geometry, ids, 0, 1), 50.0, 0.001)
	assert_almost_eq(Territories.relative_neighbor_raw_value(geometry, ids, 0, 2), -300.0, 0.001)
	assert_almost_eq(Territories.relative_neighbor_value(geometry, ids, 0, 1), 16.6667, 0.001)
	assert_almost_eq(Territories.relative_neighbor_value(geometry, ids, 0, 2), -100.0, 0.001)
	assert_almost_eq(Territories.relative_neighbor_value(geometry, ids, 0, 3), 0.0, 0.001,
		"kleinere Nachbarn liefern keinen Einfluss")
	assert_almost_eq(Territories.relative_neighbor_total(geometry, ids, 0), -83.3333, 0.001)


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
