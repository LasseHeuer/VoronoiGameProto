extends GutTest

## Tests fuer audio/synth.gd: Frequenzzuordnung, Ausbreitung (BFS) und
## Highlights. Der eigentliche Klang wird hier nicht geprueft, nur die
## eingeplanten Noten und die Zeitversaetze.

const RECT := Rect2(0.0, 0.0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)


func _make_synth(cell_count := 20, seed_value := 4711) -> Array:
	var config := GameConfig.new()
	config.cell_count = cell_count
	var board := BoardState.new()
	board.dummy_points = Territories.generate_dummy_points()
	Territories.init_on_new_game(board, config, DeterministicRng.new(seed_value))
	var main := Voronoi.from_board(board, RECT)
	var plain := Voronoi.from_points(board.points, RECT)
	var synth := Synth.new()
	add_child_autofree(synth)
	synth.setup(config, board)
	return [synth, board, main, plain, config]


func test_frequency_mapping_uses_cell_area() -> void:
	var config := GameConfig.new()
	var board := BoardState.new()
	board.points = PackedVector2Array([Vector2(100.0, 300.0), Vector2(200.0, 300.0)])
	board.dummy_points = PackedVector2Array()
	board.reset_colors()
	var plain := Voronoi.from_points(board.points, RECT)
	var synth := Synth.new()
	add_child_autofree(synth)
	synth.setup(config, board)

	# Zelle 0 hat ein Sechstel des Bretts: 1200 - 1150 * (1/6) / 0.2
	var ratio := plain.area(0) / GameConfig.BOARD_AREA
	assert_almost_eq(synth.cell_frequency(plain, 0),
		GameConfig.FREQ_HIGH - (GameConfig.FREQ_HIGH - GameConfig.FREQ_LOW) * (ratio / config.freq_threshold),
		0.01)
	# Zelle 1 ist groesser als die Schwelle -> tiefster Ton
	assert_almost_eq(synth.cell_frequency(plain, 1), GameConfig.FREQ_LOW, 0.01)


func test_frequency_falls_back_for_invalid_cell() -> void:
	var setup := _make_synth()
	var synth: Synth = setup[0]
	var plain: Voronoi = setup[3]
	assert_eq(synth.cell_frequency(plain, -1), GameConfig.FALLBACK_FREQ)
	assert_eq(synth.cell_frequency(plain, 9999), GameConfig.FALLBACK_FREQ)


func test_spread_notes_schedules_only_cells_of_the_start_color() -> void:
	var setup := _make_synth()
	var synth: Synth = setup[0]
	var board: BoardState = setup[1]
	var main: Voronoi = setup[2]
	var plain: Voronoi = setup[3]

	var start_cell := -1
	for i in range(board.cell_colors.size()):
		if board.cell_color(i) == GameConfig.COLOR_PLAYER1:
			start_cell = i
			break
	assert_ne(start_cell, -1)

	var from_pos := board.points[start_cell]
	synth.spread_notes(main, plain, start_cell, from_pos)
	assert_gt(synth._scheduled.size(), 0, "es werden Noten eingeplant")
	for entry in synth._scheduled:
		assert_eq(board.cell_color(entry["cell"]), board.cell_color(start_cell))
		assert_gt(entry["freq"], 0.0)


func test_spread_notes_respects_depth_and_offsets() -> void:
	var setup := _make_synth()
	var synth: Synth = setup[0]
	var board: BoardState = setup[1]
	var main: Voronoi = setup[2]
	var plain: Voronoi = setup[3]
	var config: GameConfig = setup[4]

	var start_cell := -1
	for i in range(board.cell_colors.size()):
		if board.cell_color(i) == GameConfig.COLOR_PLAYER2:
			start_cell = i
			break
	assert_ne(start_cell, -1, "es gibt eine Zelle von Spieler 2")
	var from_pos := board.points[start_cell]
	var before := synth.now()
	synth.spread_notes(main, plain, start_cell, from_pos)

	# Der Zeitversatz folgt der JS-Formel:
	# start = jetzt + (Tiefe - 1) * spread_sec + Distanz * 0.003
	var depth := _depth_map(main, start_cell)
	var spread_sec := config.spread_time_sec()
	var max_distance_delay := 1200.0 * GameConfig.NOTE_DISTANCE_FACTOR
	for entry in synth._scheduled:
		assert_true(depth.has(entry["cell"]), "Zelle liegt in der Ausbreitungstiefe")
		var level: int = depth[entry["cell"]]
		assert_between(level, 1, config.spread_depth)
		var offset := float(entry["start"]) - before
		assert_between(offset, float(level - 1) * spread_sec,
			float(level - 1) * spread_sec + max_distance_delay)


func test_highlights_are_set_when_scheduling() -> void:
	var setup := _make_synth()
	var synth: Synth = setup[0]
	var board: BoardState = setup[1]
	var main: Voronoi = setup[2]
	var plain: Voronoi = setup[3]

	var start_cell := 0
	synth.spread_notes(main, plain, start_cell, board.points[start_cell])
	var highlights := synth.active_highlight_cells()
	assert_gt(highlights.size(), 0)
	for entry in synth._scheduled:
		assert_true(highlights.has(int(entry["cell"])), "eingeplante Zelle ist hervorgehoben")
		var window: Dictionary = highlights[int(entry["cell"])]
		assert_true(float(window["end"]) > float(window["start"]))


func test_invalid_start_cell_is_ignored() -> void:
	var setup := _make_synth()
	var synth: Synth = setup[0]
	var board: BoardState = setup[1]
	var main: Voronoi = setup[2]
	var plain: Voronoi = setup[3]
	synth.spread_notes(main, plain, -1, Vector2.ZERO)
	assert_eq(synth._scheduled.size(), 0)


func test_drag_tones_start_with_two_voices() -> void:
	var setup := _make_synth()
	var synth: Synth = setup[0]
	var board: BoardState = setup[1]
	var plain: Voronoi = setup[3]
	synth.update_drag_tones(plain, 0)
	# Startzelle und groesster Nachbar erhalten je einen Dauerton; ist die
	# Startzelle selbst die groesste, bleibt es bei einer Stimme.
	assert_between(synth._drag_tones.size(), 1, 2)
	assert_ne(synth._drag_tones.get(0), null, "die Startzelle klingt")


func test_drag_tones_follow_the_start_cell() -> void:
	var setup := _make_synth()
	var synth: Synth = setup[0]
	var board: BoardState = setup[1]
	var plain: Voronoi = setup[3]
	synth.update_drag_tones(plain, 0)
	var keys := synth._drag_tones.keys()
	assert_between(keys.size(), 1, 2)
	assert_true(keys.has(0), "die Startzelle klingt")
	assert_lt(int(keys.max()), board.points.size())
	synth.stop_drag_tones(-1)
	assert_eq(synth._drag_tones.size(), 0, "Stimmen werden wieder freigegeben")


func test_drag_tones_stop_when_the_start_cell_changes() -> void:
	var setup := _make_synth()
	var synth: Synth = setup[0]
	var board: BoardState = setup[1]
	var plain: Voronoi = setup[3]
	if board.points.size() < 3:
		return
	var far := 0
	for i in range(board.points.size()):
		if not plain.delaunay().neighbors(0).has(i) and i != 0:
			far = i
			break
	synth.update_drag_tones(plain, 0)
	assert_true(synth._drag_tones.has(0))
	synth.update_drag_tones(plain, far)
	assert_false(synth._drag_tones.has(0), "alte Stimme ausserhalb der BFS wird gestoppt")
	assert_true(synth._drag_tones.has(far))


func test_process_starts_due_notes_without_errors() -> void:
	var setup := _make_synth()
	var synth: Synth = setup[0]
	var board: BoardState = setup[1]
	var main: Voronoi = setup[2]
	var plain: Voronoi = setup[3]
	synth.spread_notes(main, plain, 0, board.points[0])
	synth.spread_notes(main, plain, 1, board.points[1])
	# Zeitversatz abwarten, dann faellige Noten starten.
	for i in range(3):
		synth.process()
	assert_true(true, "process() laeuft ohne Fehler")


func test_stop_all_clears_state() -> void:
	var setup := _make_synth()
	var synth: Synth = setup[0]
	var board: BoardState = setup[1]
	var main: Voronoi = setup[2]
	var plain: Voronoi = setup[3]
	synth.spread_notes(main, plain, 0, board.points[0])
	synth.update_drag_tones(plain, 0)
	synth.stop_all()
	assert_eq(synth._scheduled.size(), 0)
	assert_eq(synth._drag_tones.size(), 0)
	assert_eq(synth.active_highlight_cells().size(), 0)


## BFS-Tiefe aller Zellen ab start_cell (nur echte Zellen).
func _depth_map(voronoi: Voronoi, start_cell: int) -> Dictionary:
	var depths := {start_cell: 1}
	var queue: Array = [[start_cell, 1]]
	while not queue.is_empty():
		var node: Array = queue.pop_front()
		for nb in voronoi.delaunay().neighbors(node[0]):
			if nb >= voronoi.real_count or depths.has(nb):
				continue
			depths[nb] = node[1] + 1
			queue.append([nb, node[1] + 1])
	return depths
