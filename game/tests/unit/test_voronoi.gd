extends GutTest

## Tests fuer core/voronoi.gd.

const RECT := Rect2(0.0, 0.0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)


func _make_board(cell_count: int, seed_value: int) -> BoardState:
	var config := GameConfig.new()
	config.cell_count = cell_count
	var rng := DeterministicRng.new(seed_value)
	var board := BoardState.new()
	board.points = Territories.generate_points(config, rng)
	board.dummy_points = Territories.generate_dummy_points()
	board.reset_colors()
	return board


func test_cells_are_convex_and_contain_their_point() -> void:
	for cell_count in [2, 5, 20, 50, 100]:
		var board := _make_board(cell_count, 500 + cell_count)
		var main := Voronoi.from_board(board, RECT)
		assert_eq(main.cells.size(), board.points.size())
		for i in range(main.cells.size()):
			var poly := main.cell_polygon(i)
			assert_true(poly.size() >= 3, "Zelle %d hat ein Polygon" % i)
			assert_true(BoardGeometry.is_convex(poly), "Zelle %d ist konvex" % i)
			assert_almost_eq(BoardGeometry.polygon_area(poly), main.area(i), 0.01,
				"Flaechenwert passt zum Polygon (Zelle %d)" % i)
			assert_true(BoardGeometry.point_in_polygon(board.points[i], poly),
				"Zelle %d enthaelt ihren eigenen Punkt" % i)


func test_cells_stay_inside_the_board() -> void:
	var board := _make_board(40, 77)
	var main := Voronoi.from_board(board, RECT)
	for i in range(main.cells.size()):
		for p in main.cell_polygon(i):
			assert_between(p.x, -0.01, GameConfig.BOARD_WIDTH + 0.01)
			assert_between(p.y, -0.01, GameConfig.BOARD_HEIGHT + 0.01)


func test_all_cells_cover_the_board() -> void:
	for seed_value in [4711, 99, 3]:
		var board := _make_board(20, seed_value)
		var delaunay := Delaunay.build(board.all_points())
		var all_count := board.all_points().size()
		var voronoi := Voronoi.build(delaunay, RECT, 5.0, all_count, true)
		var total := 0.0
		for i in range(voronoi.cells.size()):
			total += voronoi.area(i)
		assert_almost_eq(total, GameConfig.BOARD_AREA, 1.0,
			"Zellen kacheln das Brett (Seed %d)" % seed_value)


func test_real_cells_cover_less_than_the_board_with_dummies() -> void:
	# Die Dummy-Punkte ausserhalb des Bretts besitzen den Randstreifen.
	var board := _make_board(20, 4711)
	var main := Voronoi.from_board(board, RECT)
	var total := Territories.total_area_for_color(board, main, GameConfig.COLOR_PLAYER1)
	total += Territories.total_area_for_color(board, main, GameConfig.COLOR_PLAYER2)
	assert_lt(total, GameConfig.BOARD_AREA)


func test_areas_without_dummies_are_positive() -> void:
	var board := _make_board(30, 1234)
	var plain := Voronoi.from_points(board.points, RECT)
	assert_eq(plain.cells.size(), board.points.size())
	for i in range(plain.cells.size()):
		assert_gt(plain.area(i), 0.0, "Randzellen werden auf das Brett beschnitten")


func test_visible_neighbours_are_symmetric_and_shared() -> void:
	var board := _make_board(30, 313)
	var main := Voronoi.from_board(board, RECT)
	for i in range(main.cells.size()):
		for nb in main.visible_neighbors_of(i):
			assert_true(main.visible_neighbors_of(nb).has(i),
				"sichtbare Nachbarschaft ist symmetrisch (%d/%d)" % [i, nb])
			var length := main.visible_common_edge_length(i, nb)
			assert_true(length >= 5.0, "gemeinsame Kante liegt ueber der Schwelle")


func test_shared_edge_of_touching_cells_is_measured() -> void:
	var board := BoardState.new()
	board.points = PackedVector2Array([Vector2(450.0, 200.0), Vector2(450.0, 400.0)])
	board.dummy_points = PackedVector2Array()
	board.reset_colors()
	var voronoi := Voronoi.from_board(board, RECT)
	assert_eq(voronoi.visible_neighbors_of(0), PackedInt32Array([1]))
	# Gemeinsame Kante ist die volle Brettbreite; die JS-Formel liefert
	# den doppelten Umfang der entarteten Schnittflaeche.
	assert_almost_eq(voronoi.visible_common_edge_length(0, 1), 1800.0, 0.5)


func test_edge_neighbors_are_symmetric() -> void:
	var board := _make_board(30, 313)
	var main := Voronoi.from_board(board, RECT)
	for i in range(main.cells.size()):
		var poly := main.cell_polygon(i)
		var neighbors := main.edge_neighbors(i)
		assert_eq(neighbors.size(), poly.size(), "je Kante eine Nachbarangabe")
		for k in range(neighbors.size()):
			var nb := neighbors[k]
			if nb < 0:
				continue
			assert_ne(nb, i, "eine Zelle ist nicht ihr eigener Nachbar")
			assert_lt(nb, main.real_count, "Nachbarn sind echte Zellen, keine Dummy-Punkte")
			var shared_length := main.visible_common_edge_length(i, nb)
			assert_gt(shared_length, 0.0, "die gemeinsame Kante hat eine Laenge (%d/%d)" % [i, nb])
			assert_true(main.edge_neighbors(nb).has(i),
				"die Zuordnung ist symmetrisch (%d/%d)" % [i, nb])


func test_board_border_edges_have_no_neighbor() -> void:
	var board := _make_board(12, 909)
	var main := Voronoi.from_board(board, RECT)
	for i in range(main.cells.size()):
		var poly := main.cell_polygon(i)
		var neighbors := main.edge_neighbors(i)
		for k in range(poly.size()):
			if not (_on_board_border(poly[k]) and _on_board_border(poly[(k + 1) % poly.size()])):
				continue
			assert_lt(neighbors[k], 0,
				"Brettrandkante hat keinen Nachbarn (Zelle %d, Kante %d)" % [i, k])


func _on_board_border(point: Vector2) -> bool:
	return absf(point.x - RECT.position.x) < 0.1 or absf(point.x - RECT.end.x) < 0.1 \
		or absf(point.y - RECT.position.y) < 0.1 or absf(point.y - RECT.end.y) < 0.1


func test_fan_construction_matches_halfplane_construction() -> void:
	var board := _make_board(25, 2024)
	var main := Voronoi.from_board(board, RECT)
	for i in range(board.points.size()):
		var halfplane: PackedVector2Array = main._halfplane_polygon(i)
		assert_almost_eq(BoardGeometry.polygon_area(halfplane), main.area(i), 0.5,
			"Fan- und Halbebenen-Konstruktion stimmen ueberein (Zelle %d)" % i)


func test_min_max_area() -> void:
	var board := _make_board(20, 55)
	var main := Voronoi.from_board(board, RECT)
	var min_max := main.min_max_area()
	assert_gt(min_max.x, 0.0)
	assert_gt(min_max.y, min_max.x)


func test_incremental_build_matches_full_rebuild() -> void:
	var board := _make_board(30, 2026)
	var previous := Voronoi.from_points(board.points, RECT)
	board.points[0] += Vector2(3.0, 1.0)
	var incremental := Voronoi.from_points(board.points, RECT, previous, PackedInt32Array([0]))
	var full := Voronoi.from_points(board.points, RECT)
	for i in range(board.points.size()):
		assert_almost_eq(incremental.area(i), full.area(i), 0.01,
			"inkrementelle Flaeche stimmt fuer Zelle %d" % i)


func test_cells_stay_valid_during_simulation() -> void:
	# Ueber mehrere Seeds und Ticks muss jede Zelle konvex bleiben und sich
	# triangulieren lassen (Grundlage fuer das Zeichnen).
	for seed_value in [7, 21, 42, 99, 1234]:
		var config := GameConfig.new()
		config.cell_count = 60
		var rng := DeterministicRng.new(seed_value)
		var board := BoardState.new()
		board.dummy_points = Territories.generate_dummy_points()
		Territories.init_on_new_game(board, config, rng)
		for t in range(25):
			var plain := Voronoi.from_points(board.points, RECT)
			var weights := Relaxation.compute_cell_weights(board, plain)
			Relaxation.push_points(board, config, weights)
			Relaxation.update_point_positions(board)
			var main := Voronoi.from_board(board, RECT)
			Relaxation.clamp_to_canvas(board, config)
			Territories.update_colors_by_largest_neighbor(board, main,
				GameConfig.COLOR_PROPAGATION_ITERATIONS)
			for i in range(main.cells.size()):
				var poly := main.cell_polygon(i)
				if poly.size() < 3:
					continue
				assert_true(BoardGeometry.is_convex(poly),
					"Zelle %d konvex (Seed %d, Tick %d)" % [i, seed_value, t])
				assert_false(Geometry2D.triangulate_polygon(poly).is_empty(),
					"Zelle %d triangulierbar (Seed %d, Tick %d)" % [i, seed_value, t])
