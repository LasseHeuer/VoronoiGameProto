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


## Die Drag-Daten zeigen auf die groessten Nachbarn je Farbe; die Warnung
## steigt mit dem Flaechen-Vorsprung des Gegners. Nach dem Loslassen ist alles
## zurueckgesetzt.
func test_drag_visuals_report_neighbors_and_warning() -> void:
	var setup := _make_three_cell_board()
	var input: BoardInput = setup[0]
	var board: BoardState = setup[1]
	var rect := Rect2(0.0, 0.0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)

	input._on_press(board.points[0])
	_move_cursor(input, Vector2(240.0, 292.0))
	input.apply_drag_motion()
	input.update_drag_visuals(Voronoi.from_board(board, rect))

	assert_eq(board.dragged_index, 0)
	assert_eq(board.drag_same_neighbor, 1, "gleichfarbiger Nachbar erkannt")
	assert_eq(board.drag_opponent_neighbor, 2, "Gegner erkannt")
	assert_true(board.drag_warn > 0.0 and board.drag_warn <= 1.0,
		"der grosse Gegner loest eine Warnung aus")

	input._on_release()
	assert_eq(board.dragged_index, -1, "nach dem Loslassen sind die Daten weg")
	assert_eq(board.drag_warn, 0.0)
	assert_eq(board.drag_blink, 0.0)


## Ohne Gegner in Reichweite gibt es keine Warnung.
func test_drag_warning_stays_zero_without_an_opponent() -> void:
	var setup := _make_three_cell_board()
	var input: BoardInput = setup[0]
	var board: BoardState = setup[1]
	var rect := Rect2(0.0, 0.0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)
	board.set_cell_color(2, GameConfig.COLOR_PLAYER1)

	input._on_press(board.points[0])
	_move_cursor(input, Vector2(240.0, 292.0))
	input.apply_drag_motion()
	input.update_drag_visuals(Voronoi.from_board(board, rect))

	assert_eq(board.drag_warn, 0.0, "ohne Gegner keine Warnung")


## Drei Zellen: links zwei eigene, rechts eine Gegnerzelle.
func _make_three_cell_board() -> Array:
	var config := GameConfig.new()
	config.alternating_moves = false
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


## Der gezogene Punkt folgt dem Zeiger ungebremst. Den Schutz uebernimmt der
## Verlust-Schutz, der eine verlustbringende Bewegung zuruecknimmt.
func test_drag_follows_the_cursor_without_braking() -> void:
	var setup := _make_three_cell_board()
	var input: BoardInput = setup[0]
	var board: BoardState = setup[1]
	var start := board.points[0]

	input._on_press(start)
	var target := start + Vector2(-130.0, 0.0)
	_move_cursor(input, target)
	input.apply_drag_motion()

	assert_almost_eq(board.points[0].distance_to(start), 130.0, 0.001,
		"die Bewegung wird nicht gebremst")
	assert_almost_eq(board.points[0].distance_to(target), 0.0, 0.001,
		"der Punkt steht genau beim Zeiger")


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
