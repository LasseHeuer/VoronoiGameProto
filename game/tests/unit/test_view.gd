extends GutTest

## Tests fuer view/board_transform.gd und die Farbstufen aus
## view/board_renderer.gd.

func test_transform_letterboxes_wide_window() -> void:
	var transform := BoardTransform.for_viewport(Vector2(1800.0, 600.0))
	assert_almost_eq(transform.scale, 0.8, 0.0001)
	assert_almost_eq(transform.offset.x, 540.0, 0.0001)
	assert_almost_eq(transform.offset.y, 50.0, 0.0001)


func test_transform_letterboxes_tall_window() -> void:
	var transform := BoardTransform.for_viewport(Vector2(900.0, 1200.0))
	assert_almost_eq(transform.scale, 800.0 / 900.0, 0.0001)
	assert_almost_eq(transform.offset.x, 50.0, 0.0001)
	assert_almost_eq(transform.offset.y, 323.3333, 0.0001)


func test_transform_scales_small_window() -> void:
	var transform := BoardTransform.for_viewport(Vector2(500.0, 350.0))
	assert_almost_eq(transform.scale, 230.0 / 600.0, 0.0001)
	assert_almost_eq(transform.offset.x, 77.5, 0.0001)
	assert_almost_eq(transform.offset.y, 50.0, 0.0001)


func test_transform_round_trip() -> void:
	var transform := BoardTransform.for_viewport(Vector2(1024.0, 768.0))
	var board_point := Vector2(123.0, 456.0)
	var screen_point := transform.to_screen(board_point)
	var back := transform.to_board(screen_point)
	assert_almost_eq(back.x, board_point.x, 0.0001)
	assert_almost_eq(back.y, board_point.y, 0.0001)


func test_color_landmarks_are_interpolated() -> void:
	var palette := GameConfig.PLAYER1_STEP_COLORS
	assert_eq(BoardRenderer._interpolate_landmarks(palette, 0.0), "#" + Color(palette[0]).to_html(false))
	assert_eq(BoardRenderer._interpolate_landmarks(palette, 0.5), "#" + Color(palette[1]).to_html(false))
	assert_eq(BoardRenderer._interpolate_landmarks(palette, 1.0), "#" + Color(palette[2]).to_html(false))
	assert_ne(BoardRenderer._interpolate_landmarks(palette, 0.25), palette[0],
		"zwischen den Landmarken entsteht ein fliessender Farbwert")


## Die Zellgroesse wird kontinuierlich auf die Spielerpalette abgebildet; die
## einzige Zelle des Gegners bleibt an dessen erster Landmarke.
func test_cell_colors_use_the_player_palette() -> void:
	var board := BoardState.new()
	board.points = PackedVector2Array([
		Vector2(120.0, 150.0), Vector2(160.0, 450.0), Vector2(300.0, 300.0),
		Vector2(780.0, 300.0)])
	board.dummy_points = PackedVector2Array()
	board.reset_colors()
	board.set_cell_color(0, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(1, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(2, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(3, GameConfig.COLOR_PLAYER2)
	var voronoi := Voronoi.from_points(board.points, Rect2(0.0, 0.0, 900.0, 600.0))
	var renderer := BoardRenderer.new()
	add_child_autofree(renderer)
	renderer.set_board_state(board, GameConfig.new(), voronoi)

	var colors := renderer._cell_step_colors(board.points.size())
	var used := {}
	for i in range(3):
		used[colors[i]] = true
	assert_gte(used.size(), 2, "unterschiedliche Zellgroessen ergeben unterschiedliche Farben")
	assert_eq(colors[3], "#" + Color(GameConfig.PLAYER2_STEP_COLORS[0]).to_html(false),
		"die einzige Zelle des Gegners ist dessen erste Landmarke")


## Quadrat, bei dem die ersten beiden Kanten Frontkanten sind: die Ecke
## zwischen ihnen zeigt nach aussen und wird abgerundet.
func _square_with_front_corner() -> Array:
	var poly := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(100.0, 0.0), Vector2(100.0, 100.0), Vector2(0.0, 100.0)])
	var neighbors := PackedInt32Array([9, 9, 8, 8])
	var is_front := [true, true, false, false]
	return [poly, neighbors, is_front]


func test_cell_corners_round_every_convex_corner() -> void:
	var setup := _square_with_front_corner()
	var renderer := BoardRenderer.new()
	add_child_autofree(renderer)

	var poly: PackedVector2Array = setup[0]
	var corners := renderer._cell_corners(poly, setup[2], renderer._inward_normals(poly), 12.0, 0.0)
	assert_eq(corners.size(), 4, "alle konvexen Ecken werden abgerundet")
	assert_true(corners.has(1))
	var corner: Dictionary = corners[1]
	assert_almost_eq(float(corner["trim"]), 12.0, 0.0001)
	var arc: PackedVector2Array = corner["arc"]
	assert_gte(arc.size(), 4, "der Bogen ist aufgeloest")
	assert_almost_eq(arc[0].distance_to(Vector2(88.0, 0.0)), 0.0, 0.0001, "Bogen beginnt auf der Kante")
	assert_almost_eq(arc[arc.size() - 1].distance_to(Vector2(100.0, 12.0)), 0.0, 0.0001, "Bogen endet auf der Kante")
	assert_lt(arc[arc.size() / 2].distance_to(Vector2(100.0, 0.0)), 12.0, "der Bogen liegt in der Ecke")


## Die Innenraender werden nur an Ecken abgerundet, an denen beide Kanten zu
## gleichfarbigen Nachbarn zeigen.
func test_border_corners_require_two_same_color_edges() -> void:
	var setup := _square_with_front_corner()
	var renderer := BoardRenderer.new()
	add_child_autofree(renderer)
	var poly: PackedVector2Array = setup[0]
	var is_same := [false, false, true, true]
	var normals := renderer._inward_normals(poly)

	var corners := renderer._cell_corners(poly, is_same, normals, 12.0, 0.0, true)
	assert_eq(corners.size(), 1, "nur die Ecke zwischen zwei Innenraendern")
	assert_true(corners.has(3))

	var all_corners := renderer._cell_corners(poly, is_same, normals, 12.0, 0.0)
	assert_eq(all_corners.size(), 4, "ohne Einschraenkung alle konvexen Ecken")


func test_edge_start_uses_the_trimmed_corner() -> void:
	var poly := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(100.0, 0.0), Vector2(100.0, 100.0), Vector2(0.0, 100.0)])
	var is_front := [true, true, true, true]
	var renderer := BoardRenderer.new()
	add_child_autofree(renderer)
	var normals := renderer._inward_normals(poly)
	var zero := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var corners := renderer._cell_corners(poly, is_front, normals, 12.0, 0.0)

	var start := renderer._edge_start(poly, 0, corners, zero)
	var finish := renderer._edge_end(poly, 0, corners, zero)
	assert_almost_eq(start.distance_to(Vector2(12.0, 0.0)), 0.0, 0.0001, "Kante beginnt am Bogen")
	assert_almost_eq(finish.distance_to(Vector2(88.0, 0.0)), 0.0, 0.0001, "Kante endet am Bogen")


func test_cell_corner_radius_zero_keeps_the_sharp_corner() -> void:
	var setup := _square_with_front_corner()
	var renderer := BoardRenderer.new()
	add_child_autofree(renderer)

	assert_eq(renderer._cell_corners(
		setup[0], setup[2], renderer._inward_normals(setup[0]), 0.0, 0.0).size(), 0)


func test_concave_corner_is_not_rounded() -> void:
	# Flaeche mit einer nach innen zeigenden Ecke (Index 3): auch wenn dort
	# zwei Frontkanten zusammentreffen, wird nicht abgerundet.
	var poly := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(100.0, 0.0), Vector2(100.0, 100.0),
		Vector2(50.0, 40.0), Vector2(0.0, 100.0)])
	var is_front := [true, true, true, true, true]
	var renderer := BoardRenderer.new()
	add_child_autofree(renderer)

	var corners := renderer._cell_corners(poly, is_front, renderer._inward_normals(poly), 10.0, 0.0)
	assert_eq(corners.size(), 4, "nur die konvexen Ecken werden abgerundet")
	assert_false(corners.has(3), "die einspringende Ecke bleibt spitz")
	assert_true(corners.has(1))


## Die Hover-Umrandung bekommt dieselben runden Ecken wie die Zellgrenzen.
func test_rounded_outline_rounds_the_corners() -> void:
	var renderer := BoardRenderer.new()
	add_child_autofree(renderer)
	var poly := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(100.0, 0.0), Vector2(100.0, 100.0), Vector2(0.0, 100.0)])

	assert_eq(renderer._rounded_outline(poly, 0.0).size(), 4, "ohne Radius bleibt das Polygon")

	var rounded := renderer._rounded_outline(poly, 12.0)
	assert_gt(rounded.size(), 4, "mit Radius kommen Bogenpunkte dazu")
	for point in rounded:
		assert_true(point.x >= -0.001 and point.x <= 100.001
			and point.y >= -0.001 and point.y <= 100.001, "der Pfad bleibt im Polygon")


func test_cell_fill_colors_cover_every_cell() -> void:
	var board := BoardState.new()
	board.points = PackedVector2Array([Vector2(300.0, 300.0), Vector2(600.0, 300.0)])
	board.dummy_points = PackedVector2Array()
	board.reset_colors()
	board.set_cell_color(0, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(1, GameConfig.COLOR_PLAYER2)
	var voronoi := Voronoi.from_points(board.points, Rect2(0.0, 0.0, 900.0, 600.0))
	var renderer := BoardRenderer.new()
	add_child_autofree(renderer)
	renderer.set_board_state(board, GameConfig.new(), voronoi)

	var colors := renderer._cell_fill_colors(voronoi.cells.size())
	assert_eq(colors.size(), 2)
	for color in colors:
		assert_eq(color.length(), 7)
		assert_true(color.begins_with("#"))
	assert_ne(colors[0], colors[1], "die beiden Farben bleiben unterscheidbar")


## Zeichnet ein Brett mit Frontlinien, Abrundung, Schatten, Hover und
## Blink-Warnung: der Durchlauf darf keine Fehler erzeugen (z. B. ungueltige
## Polygone in den abgerundeten Ecken).
func test_drawing_a_full_frame_runs_without_errors() -> void:
	var config := GameConfig.new()
	config.corner_radius = 14.0
	config.show_flow = true
	var board := BoardState.new()
	board.points = PackedVector2Array([
		Vector2(200.0, 300.0), Vector2(450.0, 200.0),
		Vector2(430.0, 430.0), Vector2(700.0, 300.0)])
	board.dummy_points = PackedVector2Array()
	board.reset_colors()
	board.set_cell_color(0, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(1, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(2, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(3, GameConfig.COLOR_PLAYER2)
	board.hovered_index = 1
	board.dragged_index = 0
	board.drag_same_neighbor = 1
	board.drag_same_neighbor_area = 100.0
	board.drag_opponent_neighbor = 3
	board.drag_opponent_neighbor_area = 400.0
	board.drag_warn = 0.8
	board.drag_blink = 0.7
	var voronoi := Voronoi.from_board(board, Rect2(0.0, 0.0, 900.0, 600.0))
	var renderer := BoardRenderer.new()
	add_child_autofree(renderer)
	renderer.set_board_state(board, config, voronoi)
	renderer.highlight_cells = {0: 0.5, 3: 1.0}

	renderer.queue_redraw()
	await wait_process_frames(3)
	config.show_all_flows = true
	renderer.queue_redraw()
	await wait_process_frames(3)

	assert_true(true, "das Zeichnen laeuft ohne Fehler durch")


## Die Vereinigung zweier gleichfarbiger Nachbarzellen ergibt eine Flaeche.
func test_merge_cells_unions_adjacent_cells() -> void:
	var setup := _two_cell_territory()
	var renderer: BoardRenderer = setup[0]
	var voronoi: Voronoi = setup[2]

	var regions := renderer._merge_cells(GameConfig.COLOR_PLAYER1)
	assert_eq(regions.size(), 1, "die beiden Zellen verschmelzen zu einer Flaeche")
	var area := absf(BoardGeometry.signed_polygon_area(regions[0]))
	var expected := voronoi.area(0) + voronoi.area(1)
	assert_almost_eq(area, expected, 0.5, "die Flaeche ist die Summe der Zellen")


## Die Frontlinie liegt vollstaendig innerhalb der eigenen Flaeche.
func test_territory_line_stays_inside_the_region() -> void:
	var setup := _two_cell_territory()
	var renderer: BoardRenderer = setup[0]

	renderer._ensure_territories(1.0)
	var regions := renderer._merge_cells(GameConfig.COLOR_PLAYER1)
	var paths: Array = renderer._territory_line.get(GameConfig.COLOR_PLAYER1, [])
	assert_eq(paths.size(), 1, "eine geschlossene Kontur")
	var inside := 0
	for point in paths[0]:
		if BoardGeometry.point_in_polygon(point, regions[0]):
			inside += 1
	assert_eq(inside, paths[0].size(), "jeder Punkt der Linie liegt im Territorium")


## Die Zellfuellung wird auf die innere Kante der Frontlinie beschnitten.
func test_fill_is_clipped_to_the_territory_inner_edge() -> void:
	var setup := _two_cell_territory()
	var renderer: BoardRenderer = setup[0]
	var voronoi: Voronoi = setup[2]

	renderer._ensure_territories(1.0)
	var raw := voronoi.cell_polygon(0)
	var parts := renderer._clip_to_territory(0, raw)
	var clipped := 0.0
	for part in parts:
		clipped += absf(BoardGeometry.signed_polygon_area(part))
	assert_gt(clipped, 0.0, "es bleibt eine Flaeche uebrig")
	assert_lt(clipped, absf(BoardGeometry.signed_polygon_area(raw)) + 0.001,
		"die Flaeche wird an der Linie beschnitten")


## Bei Dummy-Punkten am Rand darf die Kontur keine scharfen Knicke zeigen:
## die Frontlinie folgt den abgerundeten Zellen.
func test_territory_outline_has_no_sharp_corners() -> void:
	var setup := _dummy_border_territory()
	var renderer: BoardRenderer = setup[0]
	renderer._ensure_territories(1.0)
	for color in [GameConfig.COLOR_PLAYER1, GameConfig.COLOR_PLAYER2]:
		for path in renderer._territory_line.get(color, []):
			assert_lt(_max_turn(path), deg_to_rad(50.0),
				"die Kontur von %s hat keine scharfen Knicke" % color)


## Die Zellfuellung ist an der Territoriumsgrenze gerundet: der Eckpunkt der
## Zelle wird dort abgeschnitten und ragt nicht mehr als Zipfel heraus.
func test_cell_fill_is_rounded_at_the_territory_border() -> void:
	var setup := _dummy_border_territory()
	var renderer: BoardRenderer = setup[0]
	var board: BoardState = setup[1]
	var voronoi: Voronoi = setup[2]

	var rounded := 0
	for i in range(board.points.size()):
		var screen := renderer._to_screen_polygon(voronoi.cell_polygon(i))
		if screen.size() < 3:
			continue
		var filled := renderer._fill_outline(i, screen, 1.0)
		var my_color := board.cell_color(i)
		var neighbors := voronoi.edge_neighbors(i)
		var count := screen.size()
		for k in range(count):
			var prev := (k - 1 + count) % count
			var nb_prev: int = neighbors[prev] if prev < neighbors.size() else -1
			var nb_next: int = neighbors[k] if k < neighbors.size() else -1
			var front_prev := nb_prev < 0 or board.cell_color(nb_prev) != my_color
			var front_next := nb_next < 0 or board.cell_color(nb_next) != my_color
			if not (front_prev or front_next):
				continue
			if not _path_contains(filled, screen[k]):
				rounded += 1
	assert_gt(rounded, 0, "mindestens eine Front-Ecke ist gerundet")


func test_cell_fill_stays_inside_the_rounded_frame() -> void:
	var setup := _two_cell_territory()
	var renderer: BoardRenderer = setup[0]
	var voronoi: Voronoi = setup[2]
	var raw := renderer._to_screen_polygon(voronoi.cell_polygon(0))
	var filled := renderer._fill_outline(0, raw, 1.0)

	assert_lt(absf(BoardGeometry.signed_polygon_area(filled)),
		absf(BoardGeometry.signed_polygon_area(raw)),
		"die Zellfarbe bleibt innerhalb des Zellrahmens")
	for point in raw:
		assert_false(_path_contains(filled, point),
			"kein Roh-Eckpunkt ragt in die Zellfuellung")


## Groesste Richtungsaenderung entlang eines geschlossenen Pfads.
func _max_turn(path: PackedVector2Array) -> float:
	var count := path.size()
	if count < 3:
		return 0.0
	var worst := 0.0
	for i in range(count):
		var previous := path[(i - 1 + count) % count]
		var here := path[i]
		var following := path[(i + 1) % count]
		var incoming := here - previous
		var outgoing := following - here
		if incoming.length_squared() < 1e-9 or outgoing.length_squared() < 1e-9:
			continue
		worst = maxf(worst, absf(incoming.angle_to(outgoing)))
	return worst


static func _path_contains(path: PackedVector2Array, point: Vector2) -> bool:
	for candidate in path:
		if candidate.distance_squared_to(point) < 0.01:
			return true
	return false


## Vier echte Zellen mit Dummy-Punkten am Rand und grossem Eckenradius.
func _dummy_border_territory() -> Array:
	var board := BoardState.new()
	board.points = PackedVector2Array([
		Vector2(280.0, 200.0), Vector2(280.0, 400.0),
		Vector2(620.0, 200.0), Vector2(620.0, 400.0)])
	board.dummy_points = Territories.generate_dummy_points()
	board.use_dummy_points = true
	board.reset_colors()
	board.set_cell_color(0, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(1, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(2, GameConfig.COLOR_PLAYER2)
	board.set_cell_color(3, GameConfig.COLOR_PLAYER2)
	var voronoi := Voronoi.from_board(board, Rect2(0.0, 0.0, 900.0, 600.0))
	var config := GameConfig.new()
	config.corner_radius = 24.0
	var renderer := BoardRenderer.new()
	add_child_autofree(renderer)
	renderer.set_board_state(board, config, voronoi)
	renderer.view_transform = BoardTransform.for_viewport(Vector2(900.0, 600.0))
	return [renderer, board, voronoi]


## Zwei Zellen nebeneinander, beide in Spielerfarbe, mit einem
## Gegnerpunkt ausserhalb.
func _two_cell_territory() -> Array:
	var board := BoardState.new()
	board.points = PackedVector2Array([
		Vector2(200.0, 250.0), Vector2(450.0, 320.0), Vector2(780.0, 260.0)])
	board.dummy_points = PackedVector2Array()
	board.reset_colors()
	board.set_cell_color(0, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(1, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(2, GameConfig.COLOR_PLAYER2)
	var voronoi := Voronoi.from_board(board, Rect2(0.0, 0.0, 900.0, 600.0))
	var renderer := BoardRenderer.new()
	add_child_autofree(renderer)
	renderer.set_board_state(board, GameConfig.new(), voronoi)
	renderer.view_transform = BoardTransform.for_viewport(Vector2(900.0, 600.0))
	return [renderer, board, voronoi]
