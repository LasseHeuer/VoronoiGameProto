extends GutTest

## Tests fuer die Ausbreitung nach dem Loslassen einer gezogenen Zelle
## (spreadNotes im mouseup der JS-Version).

const POINT_A := Vector2(100.0, 100.0)
const POINT_B := Vector2(200.0, 100.0)
const POINT_C := Vector2(150.0, 200.0)


func _make_input(alternating: bool) -> BoardInput:
	var config := GameConfig.new()
	config.alternating_moves = alternating
	var board := BoardState.new()
	board.points = PackedVector2Array([POINT_A, POINT_B, POINT_C])
	board.reset_colors()
	board.set_cell_color(0, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(1, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(2, GameConfig.COLOR_PLAYER2)
	board.active_color = GameConfig.COLOR_PLAYER1
	var input := BoardInput.new()
	input.setup(board, config)
	input.update_transform(Vector2(GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT))
	add_child_autofree(input)
	return input


func _move_cursor(input: BoardInput, board_pos: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = board_pos
	input._unhandled_input(event)


func test_release_after_drag_starts_cascade_from_dragged_cell() -> void:
	var input := _make_input(false)
	var board: BoardState = input.board
	watch_signals(input)

	input._on_press(POINT_A)
	assert_true(input.is_dragging(), "Drag startet am getroffenen Punkt")

	input._on_release()
	assert_false(input.is_dragging(), "Loslassen beendet den Drag")
	assert_signal_not_emitted(input, "notes_spread_requested")

	input.consume_pending_spread()
	assert_signal_emitted_with_parameters(input, "notes_spread_requested", [0, POINT_A])
	assert_eq(board.dragged_index, -1, "Drag-Linien sind zurueckgesetzt")


func test_release_uses_last_cursor_position() -> void:
	var input := _make_input(false)
	watch_signals(input)

	input._on_press(POINT_A)
	_move_cursor(input, Vector2(300.0, 300.0))
	input._on_release()
	input.consume_pending_spread()

	assert_signal_emitted_with_parameters(input, "notes_spread_requested", [0, Vector2(300.0, 300.0)])


func test_release_without_hit_starts_no_cascade() -> void:
	var input := _make_input(false)
	watch_signals(input)

	input._on_press(Vector2(400.0, 400.0))
	input._on_release()
	input.consume_pending_spread()

	assert_signal_not_emitted(input, "notes_spread_requested")


func test_cascade_runs_only_once() -> void:
	var input := _make_input(false)
	watch_signals(input)

	input._on_press(POINT_A)
	input._on_release()
	input.consume_pending_spread()
	input.consume_pending_spread()

	assert_signal_emit_count(input, "notes_spread_requested", 1, "Ausbreitung wird nur einmal verbraucht")


func test_automatic_color_switch_suppresses_cascade() -> void:
	var input := _make_input(true)
	var board: BoardState = input.board
	watch_signals(input)

	input._on_press(POINT_A)
	assert_true(input.is_dragging(), "Drag startet in der eigenen Farbe")
	# Waehrend des Drags kippt die Farbausbreitung die gezogene Zelle.
	board.set_cell_color(0, GameConfig.COLOR_PLAYER2)
	_move_cursor(input, Vector2(300.0, 300.0))
	input._on_release()

	assert_false(input.is_dragging(), "Der Farbwechsel beendet den Drag")
	assert_eq(board.active_color, GameConfig.COLOR_PLAYER2, "Farbe wechselt auf die gezogene Zelle")
	input.consume_pending_spread()
	assert_signal_not_emitted(input, "notes_spread_requested")


func test_drag_blocked_by_wrong_color_starts_no_cascade() -> void:
	var input := _make_input(true)
	var board: BoardState = input.board
	board.active_color = GameConfig.COLOR_PLAYER2
	watch_signals(input)

	input._on_press(POINT_A)
	assert_false(input.is_dragging(), "Fremde Farbe darf nicht gezogen werden")
	input._on_release()
	input.consume_pending_spread()

	assert_signal_not_emitted(input, "notes_spread_requested")


func _make_plain(input: BoardInput) -> Voronoi:
	return Voronoi.from_points(input.board.points, Rect2(0.0, 0.0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT))


## Zwei Zellen: die linke gehoert dem Gegner, die rechte (groessere) dem
## Spieler - sie wuerde bei der Ausbreitung an den Gegner fallen.
func _make_two_cell_board(prevent_loss: bool) -> Array:
	var config := GameConfig.new()
	config.alternating_moves = false
	config.prevent_loss = prevent_loss
	var board := BoardState.new()
	board.points = PackedVector2Array([Vector2(200.0, 300.0), Vector2(100.0, 300.0)])
	board.dummy_points = PackedVector2Array()
	board.reset_colors()
	board.set_cell_color(0, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(1, GameConfig.COLOR_PLAYER2)
	board.active_color = GameConfig.COLOR_PLAYER1
	var input := BoardInput.new()
	input.setup(board, config)
	input.update_transform(Vector2(GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT))
	add_child_autofree(input)
	return [input, board]


func test_loss_limit_reverts_a_losing_drag() -> void:
	var setup := _make_two_cell_board(true)
	var input: BoardInput = setup[0]
	var board: BoardState = setup[1]
	var rect := Rect2(0.0, 0.0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)
	var start := board.points[0]

	input._on_press(start)
	_move_cursor(input, Vector2(230.0, 300.0))
	input.apply_drag_motion()
	assert_ne(board.points[0], start, "die Bewegung wird zuerst ausgefuehrt")

	var main := Voronoi.from_board(board, rect)
	assert_gt(Territories.lost_cells(CellGeometry.from_voronoi(main), board.color_ids(), GameConfig.COLOR_PROPAGATION_ITERATIONS, GameConfig.COLOR_PLAYER1), 0)

	assert_true(input.apply_loss_limit(main), "die Bewegung wird zurueckgenommen")
	assert_eq(board.points[0], start, "der Punkt steht wieder am Start")


func test_loss_limit_keeps_the_previous_position() -> void:
	var setup := _make_two_cell_board(true)
	var input: BoardInput = setup[0]
	var board: BoardState = setup[1]
	var rect := Rect2(0.0, 0.0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)

	input._on_press(board.points[0])
	_move_cursor(input, Vector2(230.0, 300.0))
	input.apply_drag_motion()
	input.apply_loss_limit(Voronoi.from_board(board, rect))

	# Zweiter Versuch mit stillstehendem Zeiger: nichts passiert.
	var blocked_pos := board.points[0]
	input.apply_drag_motion()
	assert_eq(board.points[0], blocked_pos, "an der Grenze bewegt sich nichts mehr")

	# Weiter ziehen bleibt ebenfalls wirkungslos.
	_move_cursor(input, Vector2(500.0, 300.0))
	input.apply_drag_motion()
	input.apply_loss_limit(Voronoi.from_board(board, rect))
	assert_eq(board.points[0], blocked_pos, "die Grenze bleibt bestehen")


func test_loss_limit_is_inactive_when_switched_off() -> void:
	var setup := _make_two_cell_board(false)
	var input: BoardInput = setup[0]
	var board: BoardState = setup[1]
	var rect := Rect2(0.0, 0.0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)
	var start := board.points[0]

	input._on_press(start)
	_move_cursor(input, Vector2(230.0, 300.0))
	input.apply_drag_motion()
	var moved := board.points[0]

	assert_false(input.apply_loss_limit(Voronoi.from_board(board, rect)))
	assert_eq(board.points[0], moved, "ohne Schutz bleibt die Bewegung stehen")
	assert_ne(board.points[0], start)


func test_drag_visuals_show_the_allowed_territory() -> void:
	var setup := _make_two_cell_board(true)
	var input: BoardInput = setup[0]
	var board: BoardState = setup[1]
	var rect := Rect2(0.0, 0.0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)

	input._on_press(board.points[0])
	_move_cursor(input, Vector2(230.0, 300.0))
	input.apply_drag_motion()
	input.update_drag_visuals(Voronoi.from_board(board, rect))

	assert_true(board.drag_limit_active)
	assert_gte(board.drag_limit_region.size(), 3, "das Territorium ist eine Kontur")
	for i in range(8):
		input.update_drag_visuals(Voronoi.from_board(board, rect))
	assert_gte(board.drag_limit_region.size(), 3)

	input._on_release()
	assert_false(board.drag_limit_active, "nach dem Loslassen verschwindet das Territorium")
	assert_eq(board.drag_limit_region.size(), 0)


func test_drag_visuals_have_no_territory_without_protection() -> void:
	var setup := _make_two_cell_board(false)
	var input: BoardInput = setup[0]
	var board: BoardState = setup[1]
	var rect := Rect2(0.0, 0.0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)

	input._on_press(board.points[0])
	_move_cursor(input, Vector2(230.0, 300.0))
	input.apply_drag_motion()
	input.update_drag_visuals(Voronoi.from_board(board, rect))

	assert_false(board.drag_limit_active)
	assert_eq(board.drag_limit_region.size(), 0)


func test_own_neighbors_are_collected() -> void:
	# Eigene Nachbarzellen werden beim Verlust-Schutz uebersprungen.
	var config := GameConfig.new()
	config.alternating_moves = false
	config.prevent_loss = true
	var board := BoardState.new()
	board.points = PackedVector2Array([
		Vector2(200.0, 290.0), Vector2(280.0, 305.0), Vector2(700.0, 300.0)])
	board.dummy_points = PackedVector2Array()
	board.reset_colors()
	board.set_cell_color(0, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(1, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(2, GameConfig.COLOR_PLAYER2)
	board.active_color = GameConfig.COLOR_PLAYER1
	var input := BoardInput.new()
	input.setup(board, config)
	input.update_transform(Vector2(GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT))
	add_child_autofree(input)
	var rect := Rect2(0.0, 0.0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)

	input._on_press(board.points[0])
	var own := input._own_neighbors(Voronoi.from_board(board, rect))

	assert_eq(own, PackedInt32Array([1]), "nur die eigene Nachbarzelle zaehlt")


## Drei Zellen: links zwei eigene, rechts eine Gegnerzelle.
func _make_three_cell_board() -> Array:
	var config := GameConfig.new()
	config.alternating_moves = false
	config.prevent_loss = true
	var board := BoardState.new()
	board.points = PackedVector2Array([
		Vector2(200.0, 290.0), Vector2(280.0, 305.0), Vector2(700.0, 300.0)])
	board.dummy_points = PackedVector2Array()
	board.reset_colors()
	board.set_cell_color(0, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(1, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(2, GameConfig.COLOR_PLAYER2)
	board.active_color = GameConfig.COLOR_PLAYER1
	var input := BoardInput.new()
	input.setup(board, config)
	input.update_transform(Vector2(GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT))
	add_child_autofree(input)
	return [input, board]


## Das Ziehen wird vor der Grenze des Territoriums immer staerker gebremst:
## der Punkt bleibt hinter dem Zeiger, bleibt im Territorium und springt nicht.
func test_drag_is_braked_smoothly_towards_the_territory_edge() -> void:
	var setup := _make_three_cell_board()
	var input: BoardInput = setup[0]
	var board: BoardState = setup[1]
	var rect := Rect2(0.0, 0.0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)
	var start := board.points[0]

	input._on_press(start)
	input.update_drag_visuals(Voronoi.from_board(board, rect))
	assert_true(input.limit.is_ready(), "das Territorium steht fest")
	var allowed := input.limit._allowed_distance(start, Vector2(1.0, 0.0))
	assert_gt(allowed, 0.0, "in dieser Richtung ist Platz")

	var previous := 0.0
	var ratios: Array = []
	for factor in [0.5, 1.0, 2.0, 4.0]:
		_move_cursor(input, start + Vector2(allowed * float(factor), 0.0))
		input.apply_drag_motion()
		var position := board.points[0]
		var distance := position.distance_to(start)
		assert_gt(distance, previous, "die Bewegung laeuft nur nach vorne")
		assert_lte(distance, allowed * float(factor) + 0.001, "der Punkt bleibt hinter dem Zeiger")
		if is_equal_approx(float(factor), 1.0):
			assert_true(BoardGeometry.point_in_polygon(position, input.limit.outline()),
				"der gebremste Punkt bleibt im Territorium")
		ratios.append(distance / (allowed * float(factor)))
		previous = distance

	assert_gt(ratios[0], ratios[1], "die Bremse setzt ein")
	assert_gt(ratios[1], ratios[2], "die Bremse nimmt zu")
	assert_gt(ratios[2], ratios[3], "die Bremse nimmt weiter zu")
	assert_lte(previous, allowed + 0.001, "die Grenze wird nie erreicht")
	assert_almost_eq(previous, allowed, DragLimit.STOP_MARGIN + 2.0,
		"kurz vor der Grenze steht der Punkt an der Grenze")


func test_hover_reports_the_cell_under_the_cursor() -> void:
	var input := _make_input(false)
	var plain := _make_plain(input)
	watch_signals(input)

	_move_cursor(input, POINT_A)
	input.update_hover(plain)

	assert_signal_emitted_with_parameters(input, "hover_cell_changed", [0])


func test_hover_ignores_moves_within_the_same_cell() -> void:
	var input := _make_input(false)
	var plain := _make_plain(input)
	watch_signals(input)

	_move_cursor(input, POINT_A)
	input.update_hover(plain)
	_move_cursor(input, Vector2(108.0, 100.0))
	input.update_hover(plain)

	assert_signal_emit_count(input, "hover_cell_changed", 1, "gleiche Zelle meldet nichts")


func test_hover_reports_each_cell_change() -> void:
	var input := _make_input(false)
	var plain := _make_plain(input)
	watch_signals(input)

	_move_cursor(input, POINT_A)
	input.update_hover(plain)
	_move_cursor(input, Vector2(192.0, 100.0))
	input.update_hover(plain)

	assert_signal_emit_count(input, "hover_cell_changed", 2, "Zellwechsel meldet erneut")


func test_hover_is_silent_while_dragging() -> void:
	var input := _make_input(false)
	var plain := _make_plain(input)
	watch_signals(input)

	input._on_press(POINT_A)
	_move_cursor(input, Vector2(300.0, 300.0))
	input.update_hover(plain)

	assert_signal_not_emitted(input, "hover_cell_changed")


func test_hover_marks_the_cell_in_the_board_state() -> void:
	var input := _make_input(false)
	var board: BoardState = input.board
	var plain := _make_plain(input)

	_move_cursor(input, POINT_A)
	input.update_hover(plain)
	assert_eq(board.hovered_index, 0, "die Zelle unter dem Zeiger ist markiert")

	_move_cursor(input, Vector2(950.0, 500.0))
	input.update_hover(plain)
	assert_eq(board.hovered_index, -1, "ausserhalb des Bretts ist nichts markiert")
