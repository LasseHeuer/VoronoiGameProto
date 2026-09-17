extends GutTest

## Tests fuer sim/color_steps.gd: Farbwechsel laufen nacheinander.

const RECT := Rect2(0.0, 0.0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)


## Vier Zellen in einer Reihe: aussen Gegnerfarbe, innen Spielerfarbe.
## Die beiden inneren Zellen wechseln nacheinander die Farbe.
func _board_with_two_changes() -> Array:
	var board := BoardState.new()
	board.points = PackedVector2Array([
		Vector2(60.0, 290.0), Vector2(180.0, 310.0),
		Vector2(350.0, 300.0), Vector2(780.0, 305.0)])
	board.dummy_points = PackedVector2Array()
	board.reset_colors()
	board.set_cell_color(0, GameConfig.COLOR_PLAYER2)
	board.set_cell_color(1, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(2, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(3, GameConfig.COLOR_PLAYER2)
	board.active_color = GameConfig.COLOR_PLAYER1
	return [board, Voronoi.from_board(board, RECT)]


func _color_setup_of(board: BoardState) -> BoardState:
	var copy := BoardState.new()
	copy.points = board.points
	copy.reset_colors()
	copy.set_cell_color(0, GameConfig.COLOR_PLAYER2)
	copy.set_cell_color(1, GameConfig.COLOR_PLAYER1)
	copy.set_cell_color(2, GameConfig.COLOR_PLAYER1)
	copy.set_cell_color(3, GameConfig.COLOR_PLAYER2)
	return copy


func _changed_cells(before: PackedStringArray, after: PackedStringArray) -> int:
	var changed := 0
	for i in range(before.size()):
		if before[i] != after[i]:
			changed += 1
	return changed


func test_first_step_runs_immediately() -> void:
	var setup := _board_with_two_changes()
	var board: BoardState = setup[0]
	var main: Voronoi = setup[1]
	var steps := ColorSteps.new()
	var before := board.cell_colors.duplicate()

	assert_ne(steps.advance(1000.0, 25.0, board, main, GameConfig.COLOR_PROPAGATION_ITERATIONS), -1,
		"ein eigener Verlust wird gemeldet")
	assert_eq(_changed_cells(before, board.cell_colors), 1, "genau ein Wechsel laeuft sofort")
	assert_true(steps.is_idle(), "die naechste Entscheidung wird aus dem aktuellen Brett berechnet")


## Wechselt eine Gegnerzelle die Farbe, ist das kein eigener Verlust.
func test_a_gained_cell_is_not_reported_as_a_loss() -> void:
	var setup := _board_with_two_changes()
	var board: BoardState = setup[0]
	var main: Voronoi = setup[1]
	var steps := ColorSteps.new()
	board.active_color = GameConfig.COLOR_PLAYER2
	var before := board.cell_colors.duplicate()

	assert_eq(steps.advance(1000.0, 25.0, board, main, GameConfig.COLOR_PROPAGATION_ITERATIONS), -1,
		"kein eigener Verlust")
	assert_eq(_changed_cells(before, board.cell_colors), 1, "trotzdem wird gewechselt")


func test_steps_wait_for_the_interval() -> void:
	var setup := _board_with_two_changes()
	var board: BoardState = setup[0]
	var main: Voronoi = setup[1]
	var steps := ColorSteps.new()

	steps.advance(1000.0, 25.0, board, main, GameConfig.COLOR_PROPAGATION_ITERATIONS)
	var after_first := board.cell_colors.duplicate()

	steps.advance(1010.0, 25.0, board, main, GameConfig.COLOR_PROPAGATION_ITERATIONS)
	assert_eq(board.cell_colors, after_first, "vor Ablauf des Intervalls passiert nichts")
	assert_false(steps.is_idle(), "der naechste Wechsel wartet noch auf das Intervall")

	steps.advance(1030.0, 25.0, board, main, GameConfig.COLOR_PROPAGATION_ITERATIONS)
	assert_true(steps.is_idle(), "nach Ablauf des Intervalls ist alles angewendet")


func test_long_pause_does_not_dump_all_steps() -> void:
	var setup := _board_with_two_changes()
	var board: BoardState = setup[0]
	var main: Voronoi = setup[1]
	var steps := ColorSteps.new()

	steps.advance(1000.0, 25.0, board, main, GameConfig.COLOR_PROPAGATION_ITERATIONS)
	var after_first := board.cell_colors.duplicate()

	steps.advance(5000.0, 25.0, board, main, GameConfig.COLOR_PROPAGATION_ITERATIONS)
	assert_eq(_changed_cells(after_first, board.cell_colors), 1,
		"ein Zeitsprung wendet nur einen Wechsel an")

	steps.advance(5020.0, 25.0, board, main, GameConfig.COLOR_PROPAGATION_ITERATIONS)
	assert_eq(_changed_cells(after_first, board.cell_colors), 1,
		"vor Ablauf des Intervalls passiert nichts")


func test_stepwise_result_matches_the_full_spread() -> void:
	var setup := _board_with_two_changes()
	var board: BoardState = setup[0]
	var main: Voronoi = setup[1]
	var steps := ColorSteps.new()

	var now := 1000.0
	for i in range(10):
		steps.advance(now, 25.0, board, main, GameConfig.COLOR_PROPAGATION_ITERATIONS)
		now += 25.0
	assert_true(steps.is_idle())

	var expected := _color_setup_of(board)
	Territories.update_colors_by_largest_neighbor(expected, main, GameConfig.COLOR_PROPAGATION_ITERATIONS)

	assert_eq(board.cell_colors, expected.cell_colors, "schrittweise kommt dasselbe heraus")


func test_clear_stops_pending_steps() -> void:
	var setup := _board_with_two_changes()
	var board: BoardState = setup[0]
	var main: Voronoi = setup[1]
	var steps := ColorSteps.new()

	steps.advance(1000.0, 25.0, board, main, GameConfig.COLOR_PROPAGATION_ITERATIONS)
	assert_true(steps.is_idle(), "der naechste Wechsel wird spaeter neu berechnet")

	steps.clear()

	assert_true(steps.is_idle(), "clear() verwirft die geplanten Wechsel")
