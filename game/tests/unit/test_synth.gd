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
		assert_eq(float(entry["volume"]), 1.0, "Ausbreitungsnoten laufen mit voller Lautstaerke")


func test_hover_note_is_quiet_and_without_highlight() -> void:
	var setup := _make_synth()
	var synth: Synth = setup[0]
	var plain: Voronoi = setup[3]

	synth.hover_note(0, plain)

	assert_eq(synth._scheduled.size(), 1, "ein Hover-Ton wird eingeplant")
	assert_eq(float(synth._scheduled[0]["volume"]), GameConfig.HOVER_VOLUME)
	assert_lt(GameConfig.HOVER_VOLUME, 1.0, "Hover ist leiser als eine normale Note")
	assert_eq(synth.active_highlight_cells().size(), 0, "Hover hebt die Zelle nicht hervor")


func test_hover_notes_keep_a_minimum_distance() -> void:
	var setup := _make_synth()
	var synth: Synth = setup[0]
	var plain: Voronoi = setup[3]

	synth.hover_note(0, plain)
	synth.hover_note(1, plain)

	assert_eq(synth._scheduled.size(), 1, "zu schnelle Zellwechsel werden ausgelassen")


func test_hover_note_ignores_invalid_cell() -> void:
	var setup := _make_synth()
	var synth: Synth = setup[0]
	var plain: Voronoi = setup[3]

	synth.hover_note(-1, plain)

	assert_eq(synth._scheduled.size(), 0)


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


func test_highlight_is_only_active_while_the_note_sounds() -> void:
	# Eine Note, die erst spaeter klingt, darf die Zelle noch nicht faerben.
	var setup := _make_synth()
	var synth: Synth = setup[0]
	var board: BoardState = setup[1]

	synth.schedule_note(0, GameConfig.FALLBACK_FREQ, synth.now() + 10.0)
	synth.process()
	assert_eq(synth.active_highlight_cells().size(), 0, "noch nicht gestartete Noten faerben nicht")

	synth.stop_all()
	synth.schedule_note(0, GameConfig.FALLBACK_FREQ, synth.now() - 0.01)
	synth.process()
	var highlights := synth.active_highlight_cells()
	assert_true(highlights.has(0), "die klingende Zelle ist hervorgehoben")
	assert_gt(float(highlights[0]), 0.0, "die Deckkraft ist groesser als 0")


func test_highlight_alpha_follows_the_volume_envelope() -> void:
	var entry := {
		"start": 10.0,
		"attack": 0.5,
		"decay": 0.5,
		"sustain": 0.4,
		"hold_end": 12.0,
		"release": 1.0,
		"volume": 1.0,
		"end": 13.1,
	}
	assert_eq(Synth._envelope_alpha(entry, 9.0), 0.0, "vor dem Start")
	assert_almost_eq(Synth._envelope_alpha(entry, 10.25), 0.5, 0.0001, "waehrend des Einschwingens")
	assert_almost_eq(Synth._envelope_alpha(entry, 10.5), 1.0, 0.0001, "lauter Peak")
	assert_almost_eq(Synth._envelope_alpha(entry, 10.75), 0.7, 0.0001, "Ausklang auf Sustain")
	assert_almost_eq(Synth._envelope_alpha(entry, 11.0), 0.4, 0.0001, "Haltephase")
	assert_between(Synth._envelope_alpha(entry, 12.5), 0.0, 0.4, "Ausblenden")
	assert_almost_eq(Synth._envelope_alpha(entry, 13.1), 0.0, 0.0001, "nach dem Ende")


func test_highlights_are_set_when_scheduling() -> void:
	var setup := _make_synth()
	var synth: Synth = setup[0]
	var board: BoardState = setup[1]
	var main: Voronoi = setup[2]
	var plain: Voronoi = setup[3]

	var start_cell := 0
	synth.spread_notes(main, plain, start_cell, board.points[start_cell])
	assert_gt(synth._highlights.size(), 0)
	for entry in synth._scheduled:
		var cell := int(entry["cell"])
		assert_true(synth._highlights.has(cell), "eingeplante Zelle hat eine Huellkurve")
		var window: Dictionary = synth._highlights[cell]
		assert_almost_eq(float(window["start"]), float(entry["start"]), 0.0001)
		assert_true(float(window["end"]) > float(window["start"]))
		assert_true(float(window["end"]) > float(window["hold_end"]), "das Ausblenden passt noch hinein")


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
