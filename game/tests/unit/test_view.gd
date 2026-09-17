extends GutTest

## Tests fuer view/board_transform.gd und die Farbhelfer aus
## view/board_renderer.gd (1:1-Port der JS-Farbfunktionen).

func test_transform_letterboxes_wide_window() -> void:
	var transform := BoardTransform.for_viewport(Vector2(1800.0, 600.0))
	assert_almost_eq(transform.scale, 1.0, 0.0001)
	assert_almost_eq(transform.offset.x, 450.0, 0.0001)
	assert_almost_eq(transform.offset.y, 0.0, 0.0001)


func test_transform_letterboxes_tall_window() -> void:
	var transform := BoardTransform.for_viewport(Vector2(900.0, 1200.0))
	assert_almost_eq(transform.scale, 1.0, 0.0001)
	assert_almost_eq(transform.offset.x, 0.0, 0.0001)
	assert_almost_eq(transform.offset.y, 300.0, 0.0001)


func test_transform_scales_small_window() -> void:
	var transform := BoardTransform.for_viewport(Vector2(500.0, 350.0))
	assert_almost_eq(transform.scale, 500.0 / 900.0, 0.0001)
	assert_almost_eq(transform.offset.x, 0.0, 0.0001)
	assert_almost_eq(transform.offset.y, (350.0 - 600.0 * transform.scale) * 0.5, 0.0001)


func test_transform_round_trip() -> void:
	var transform := BoardTransform.for_viewport(Vector2(1024.0, 768.0))
	var board_point := Vector2(123.0, 456.0)
	var screen_point := transform.to_screen(board_point)
	var back := transform.to_board(screen_point)
	assert_almost_eq(back.x, board_point.x, 0.0001)
	assert_almost_eq(back.y, board_point.y, 0.0001)


func test_hex_rgb_round_trip() -> void:
	var rgb := BoardRenderer.hex_to_rgb("#FF8BA7")
	assert_eq(rgb, [255, 139, 167])
	assert_eq(BoardRenderer.rgb_to_hex(255, 139, 167), "#ff8ba7")


func test_grey_color_matches_css_hsl() -> void:
	assert_eq(BoardRenderer.grey_color(0.0), "#000000")
	assert_eq(BoardRenderer.grey_color(20.0), "#333333")
	assert_eq(BoardRenderer.grey_color(80.0), "#cccccc")
	assert_eq(BoardRenderer.grey_color(100.0), "#ffffff")


func test_mix_colors_endpoints_and_middle() -> void:
	assert_eq(BoardRenderer.mix_colors("#000000", "#ffffff", 0.0), "#000000")
	assert_eq(BoardRenderer.mix_colors("#000000", "#ffffff", 1.0), "#ffffff")
	assert_eq(BoardRenderer.mix_colors("#000000", "#ffffff", 0.5), "#808080")
	assert_eq(BoardRenderer.mix_colors("#FF8BA7", "#FF8BA7", 0.4), "#ff8ba7")


func test_mix_color_with_grey_keeps_hue_for_white() -> void:
	# Weiss hat keine Saettigung, das Ergebnis ist also das reine Grau.
	assert_eq(BoardRenderer.mix_color_with_grey("#ffffff", 20.0), BoardRenderer.grey_color(20.0))


func test_mix_color_with_grey_darkens_saturated_color() -> void:
	var mixed := BoardRenderer.mix_color_with_grey(GameConfig.COLOR_PLAYER1, 20.0)
	var rgb := BoardRenderer.hex_to_rgb(mixed)
	assert_eq(mixed.length(), 7)
	assert_lt(rgb[0], 255, "Rotanteil wird dunkler")
	assert_gt(rgb[0] + rgb[1] + rgb[2], 0, "Farbe bleibt sichtbar")


func test_cell_color_gets_lighter_with_the_cell_area() -> void:
	var small := _hsl_of(BoardRenderer.color_for_area(GameConfig.COLOR_PLAYER1, 0.0))
	var large := _hsl_of(BoardRenderer.color_for_area(GameConfig.COLOR_PLAYER1, 1.0))
	assert_lt(small[2], large[2], "die kleinste Zelle ist dunkler als die groesste")
	assert_almost_eq(small[0], large[0], 0.01, "Farbton bleibt gleich")
	assert_almost_eq(small[1], large[1], 0.01, "Saettigung bleibt gleich")

	var middle := _hsl_of(BoardRenderer.color_for_area(GameConfig.COLOR_PLAYER1, 0.5))
	assert_between(middle[2], small[2], large[2], "dazwischen liegt die Helligkeit dazwischen")


func test_cell_color_without_base_color_is_grey() -> void:
	var middle_lum := (GameConfig.LUM_MIN + GameConfig.LUM_MAX) * 0.5
	assert_eq(BoardRenderer.color_for_area("", 0.5), BoardRenderer.grey_color(middle_lum))


func _hsl_of(hex_color: String) -> Array:
	var rgb := BoardRenderer.hex_to_rgb(hex_color)
	return BoardRenderer.rgb_to_hsl(rgb[0], rgb[1], rgb[2])


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
