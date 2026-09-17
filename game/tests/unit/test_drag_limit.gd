extends GutTest

## Tests fuer sim/drag_limit.gd: Territorium der gezogenen Zelle.

const RECT := Rect2(0.0, 0.0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)
## Zelle, die gezogen wird (Spieler 1).
const DRAGGED := 1
const OWN_COLOR := GameConfig.COLOR_PLAYER1


## Vier Zellen in einer Reihe: links Spieler 1, rechts Spieler 2. Die
## Ausbreitung ist stabil, kippt aber, sobald die gezogene Zelle weit nach
## links wandert (dort waechst die Gegnerzelle).
func _setup() -> Array:
	var board := BoardState.new()
	board.points = PackedVector2Array([
		Vector2(200.0, 290.0), Vector2(360.0, 305.0),
		Vector2(570.0, 300.0), Vector2(745.0, 310.0)])
	board.dummy_points = PackedVector2Array()
	board.reset_colors()
	board.set_cell_color(0, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(1, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(2, GameConfig.COLOR_PLAYER2)
	board.set_cell_color(3, GameConfig.COLOR_PLAYER2)
	var limit := DragLimit.new()
	limit.setup(board)
	return [limit, board, Voronoi.from_board(board, RECT)]


func _build(limit: DragLimit, main: Voronoi, cell := DRAGGED) -> void:
	limit.begin(cell)
	limit.update(main, GameConfig.COLOR_PROPAGATION_ITERATIONS)


## Farbe einer Zelle, wenn ihr Punkt an `position` steht (genau gerechnet
## ueber ein frisches Voronoi).
func _color_at(board: BoardState, cell: int, position: Vector2) -> String:
	var moved := BoardState.new()
	moved.points = board.points
	moved.points[cell] = position
	moved.dummy_points = board.dummy_points
	moved.use_dummy_points = board.use_dummy_points
	moved.cell_colors = board.cell_colors
	var voronoi := Voronoi.from_board(moved, RECT)
	var ids := Territories.propagate_ids(CellGeometry.from_voronoi(voronoi), moved.color_ids(),
		GameConfig.COLOR_PROPAGATION_ITERATIONS)
	return BoardState.color_for_id(ids[cell])


## Eigene Zelle, deren Mittelpunkt `position` am naechsten liegt.
func _nearest_own_cell(board: BoardState, position: Vector2) -> int:
	var best := -1
	var best_distance := INF
	for i in range(board.points.size()):
		if board.cell_color(i) != OWN_COLOR:
			continue
		var d := board.points[i].distance_to(position)
		if d < best_distance:
			best_distance = d
			best = i
	return best


func test_outline_is_ready_after_one_update() -> void:
	var setup := _setup()
	var limit: DragLimit = setup[0]
	var main: Voronoi = setup[2]

	_build(limit, main)

	assert_true(limit.is_active())
	assert_true(limit.is_ready())
	assert_gte(limit.outline().size(), 3, "eine geschlossene Kontur")


## Die Kontur gehoert zur Farbe: sie haengt nicht davon ab, welche Zelle der
## Farbe gedrueckt wurde.
func test_outline_is_the_same_for_every_cell_of_the_color() -> void:
	var setup := _setup()
	var limit: DragLimit = setup[0]
	var main: Voronoi = setup[2]

	_build(limit, main)
	var first := limit.outline()
	limit.begin(0)
	limit.update(main, GameConfig.COLOR_PROPAGATION_ITERATIONS)
	assert_eq(limit.outline(), first, "Zelle 0 zeigt dasselbe Territorium wie Zelle 1")


func test_outline_does_not_change_during_the_drag() -> void:
	var setup := _setup()
	var limit: DragLimit = setup[0]
	var board: BoardState = setup[1]
	var main: Voronoi = setup[2]

	_build(limit, main)
	var outline := limit.outline()
	# Die Lage aendert sich waehrend des Ziehens (hier stark): die Kontur
	# bleibt trotzdem stehen.
	var points := board.points
	points[DRAGGED] = Vector2(260.0, 300.0)
	board.points = points
	limit.update(Voronoi.from_board(board, RECT), GameConfig.COLOR_PROPAGATION_ITERATIONS)
	assert_eq(limit.outline(), outline, "die Kontur wird nicht neu gerechnet")


func test_outline_contains_all_own_cells() -> void:
	var setup := _setup()
	var limit: DragLimit = setup[0]
	var board: BoardState = setup[1]
	var main: Voronoi = setup[2]

	_build(limit, main)
	var outline := limit.outline()
	for i in range(board.points.size()):
		if board.cell_color(i) != OWN_COLOR:
			continue
		var center := BoardGeometry.polygon_vertex_average(main.cell_polygon(i))
		assert_true(BoardGeometry.point_in_polygon(center, outline),
			"Zelle %d liegt im Territorium" % i)


func test_outline_is_larger_than_the_own_area() -> void:
	var setup := _setup()
	var limit: DragLimit = setup[0]
	var board: BoardState = setup[1]
	var main: Voronoi = setup[2]

	_build(limit, main)
	var own_area := 0.0
	for i in range(board.points.size()):
		if board.cell_color(i) == OWN_COLOR:
			own_area += main.area(i)

	assert_gt(BoardGeometry.polygon_area(limit.outline()), own_area,
		"das Territorium reicht ueber die eigene Flaeche hinaus")


func test_outline_stops_before_the_cell_flips() -> void:
	# Auf einem realistischen Brett: die Kontur ist eine lokale Naeherung, der
	# weitaus groesste Teil des Randes muss aber sicher sein (die genaue
	# Pruefung des Verlust-Schutzes laeuft im Spiel mit dem echten Voronoi).
	var setup := _real_setup()
	var limit: DragLimit = setup[0]
	var board: BoardState = setup[1]
	var main: Voronoi = setup[2]

	_build(limit, main, setup[3])
	var outline := limit.outline()
	var growth := limit.growth()
	var grown := 0
	var safe := 0
	for i in range(outline.size()):
		if growth[i] <= 0.0:
			continue
		grown += 1
		var cell := _nearest_own_cell(board, outline[i])
		if _color_at(board, cell, outline[i]) == OWN_COLOR:
			safe += 1
	assert_gt(grown, 0, "das Territorium waechst ueber die eigene Flaeche hinaus")
	assert_gte(safe, int(ceil(float(grown) * 0.8)),
		"mindestens 80%% der Randpunkte sind sicher (%d von %d)" % [safe, grown])


## Realistisches Brett mit 20 Zellen (beide Farben zusammenhaengend).
func _real_setup() -> Array:
	var config := GameConfig.new()
	config.cell_count = 20
	var board := BoardState.new()
	board.dummy_points = Territories.generate_dummy_points()
	Territories.init_on_new_game(board, config, DeterministicRng.new(4711))
	var limit := DragLimit.new()
	limit.setup(board)
	var own := -1
	var count := 0
	for i in range(board.points.size()):
		if board.cell_color(i) != GameConfig.COLOR_PLAYER1:
			continue
		count += 1
		own = i
	return [limit, board, Voronoi.from_board(board, RECT), own]


func test_clear_removes_the_outline() -> void:
	var setup := _setup()
	var limit: DragLimit = setup[0]
	var main: Voronoi = setup[2]

	_build(limit, main)
	limit.clear()

	assert_false(limit.is_active())
	assert_eq(limit.outline().size(), 0)
	assert_eq(limit.index(), -1)


func test_update_without_drag_does_nothing() -> void:
	var setup := _setup()
	var limit: DragLimit = setup[0]
	var main: Voronoi = setup[2]

	limit.clear()
	limit.update(main, GameConfig.COLOR_PROPAGATION_ITERATIONS)

	assert_false(limit.is_active())
	assert_eq(limit.outline().size(), 0)


func test_outline_follows_the_own_color_of_the_dragged_cell() -> void:
	# Wird die Gegnerzelle gezogen, ist deren Flaeche die Grundflaeche.
	var setup := _setup()
	var limit: DragLimit = setup[0]
	var board: BoardState = setup[1]
	var main: Voronoi = setup[2]

	limit.begin(2)
	limit.update(main, GameConfig.COLOR_PROPAGATION_ITERATIONS)
	assert_true(limit.is_ready())
	assert_true(BoardGeometry.point_in_polygon(
		BoardGeometry.polygon_vertex_average(main.cell_polygon(3)), limit.outline()),
		"auch die zweite Gegnerzelle liegt im Territorium")
	assert_false(BoardGeometry.point_in_polygon(
		BoardGeometry.polygon_vertex_average(main.cell_polygon(0)), limit.outline()),
		"die eigene Zelle liegt nicht darin")


# --------------------------------------------------- weiche Bremse ---------

func test_soft_wall_follows_the_cursor_until_the_band() -> void:
	assert_almost_eq(DragLimit.soft_wall(20.0, 100.0, 30.0), 20.0, 0.0001)
	assert_almost_eq(DragLimit.soft_wall(70.0, 100.0, 30.0), 70.0, 0.0001, "Beginn des Bands")
	assert_almost_eq(DragLimit.soft_wall(70.5, 100.0, 30.0), 70.5, 0.05,
		"am Beginn des Bands wird kaum gebremst (stetiger Anschluss)")


func test_soft_wall_approaches_the_limit_without_crossing_it() -> void:
	var previous := 0.0
	for distance in [70.0, 80.0, 90.0, 100.0, 130.0, 200.0]:
		var value := DragLimit.soft_wall(distance, 100.0, 30.0)
		assert_lt(value, 100.0, "die Grenze wird nicht erreicht")
		assert_lte(value, distance, "hinter dem Band wird gebremst")
		assert_gte(value, previous, "der Wert waechst monoton")
		previous = value
	# Sehr weit hinter der Grenze liegt der Wert praktisch an der Grenze.
	assert_almost_eq(DragLimit.soft_wall(5000.0, 100.0, 30.0), 100.0, 0.5)


func test_soft_wall_without_a_limit_keeps_the_distance() -> void:
	assert_almost_eq(DragLimit.soft_wall(50.0, 0.0, 20.0), 50.0, 0.0001)


func test_braked_distance_follows_inside_and_stops_at_the_edge() -> void:
	var setup := _real_setup()
	var limit: DragLimit = setup[0]
	var board: BoardState = setup[1]
	var main: Voronoi = setup[2]
	var origin: Vector2 = board.points[setup[3]]
	var direction := Vector2(1.0, 0.0)

	_build(limit, main, setup[3])
	assert_true(limit.is_ready())
	var allowed := limit._allowed_distance(origin, direction)
	assert_gt(allowed, 0.0, "in dieser Richtung ist Platz")

	# Vor dem Band folgt die Zelle dem Zeiger genau.
	var near := minf(10.0, allowed * 0.2)
	assert_almost_eq(limit.braked_distance(origin, origin + direction * near), near, 0.0001)

	# Weit hinaus waechst der Wert monoton, bleibt aber vor der Konturgrenze.
	var previous := near
	for factor in [1.5, 3.0, 10.0]:
		var cursor := origin + direction * (allowed * float(factor))
		var value := limit.braked_distance(origin, cursor)
		assert_gt(value, previous, "die Bewegung laeuft weiter")
		assert_lt(value, allowed, "die Konturgrenze wird nicht erreicht")
		assert_true(BoardGeometry.point_in_polygon(origin + direction * (value - 0.5), limit.outline()),
			"der gebremste Punkt bleibt im Territorium")
		previous = value


func test_braked_distance_without_a_contour_keeps_the_distance() -> void:
	var setup := _real_setup()
	var limit: DragLimit = setup[0]
	var board: BoardState = setup[1]
	var origin: Vector2 = board.points[setup[3]]

	# Ohne vorherigen update-Aufruf gibt es keine Kontur.
	assert_almost_eq(limit.braked_distance(origin, origin + Vector2(200.0, 0.0)), 200.0, 0.0001)


## Wird eine Richtung blockiert, bremst die Kontur dort kuenftig frueher.
func test_blocked_direction_is_remembered() -> void:
	var setup := _real_setup()
	var limit: DragLimit = setup[0]
	var board: BoardState = setup[1]
	var main: Voronoi = setup[2]
	var origin: Vector2 = board.points[setup[3]]
	var direction := Vector2(1.0, 0.0)

	_build(limit, main, setup[3])
	var far := origin + direction * 900.0
	var before := limit.braked_distance(origin, far)
	assert_gt(before, 30.0)

	limit.note_blocked(origin, origin + direction * (before - 30.0))
	var after := limit.braked_distance(origin, far)

	assert_lt(after, before, "in dieser Richtung wird frueher gestoppt")
	assert_lt(after, before - 20.0, "die Bremse haelt den gelernten Abstand ein")


func test_clear_forgets_the_learned_wall() -> void:
	var setup := _real_setup()
	var limit: DragLimit = setup[0]
	var board: BoardState = setup[1]
	var main: Voronoi = setup[2]
	var origin: Vector2 = board.points[setup[3]]
	var direction := Vector2(1.0, 0.0)

	_build(limit, main, setup[3])
	var far := origin + direction * 900.0
	var before := limit.braked_distance(origin, far)
	limit.note_blocked(origin, origin + direction * 20.0)
	limit.clear()
	_build(limit, main, setup[3])

	assert_almost_eq(limit.braked_distance(origin, far), before, 0.0001,
		"nach dem Loeschen gilt wieder die Kontur")
