extends GutTest

## Tests fuer sim/scoring.gd.

const RECT := Rect2(0.0, 0.0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)


func _board_and_voronoi() -> Array:
	# Zelle 0: 90000 px2 (x <= 150), Zelle 1: 450000 px2
	var board := BoardState.new()
	board.points = PackedVector2Array([Vector2(100.0, 300.0), Vector2(200.0, 300.0)])
	board.dummy_points = PackedVector2Array()
	board.reset_colors()
	return [board, Voronoi.from_points(board.points, RECT)]


func test_only_the_idle_player_scores() -> void:
	var setup := _board_and_voronoi()
	var board: BoardState = setup[0]
	var voronoi: Voronoi = setup[1]
	board.set_cell_color(0, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(1, GameConfig.COLOR_PLAYER2)

	board.active_color = GameConfig.COLOR_PLAYER1
	Scoring.update_scores(board, voronoi, 1.0)
	assert_eq(board.score_p1, 0.0, "Spieler 1 ist am Zug und sammelt nicht")
	assert_gt(board.score_p2, 0.0, "Spieler 2 sammelt, weil er nicht am Zug ist")

	var expected := 360.0
	assert_almost_eq(board.score_p2, expected, 0.01)


func test_leading_player_does_not_score_when_behind_player_is_active() -> void:
	var setup := _board_and_voronoi()
	var board: BoardState = setup[0]
	var voronoi: Voronoi = setup[1]
	board.set_cell_color(0, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(1, GameConfig.COLOR_PLAYER2)
	board.active_color = GameConfig.COLOR_PLAYER2
	Scoring.update_scores(board, voronoi, 1.0)
	assert_eq(board.score_p1, 0.0, "der zurueckliegende Spieler bekommt nichts")
	assert_eq(board.score_p2, 0.0, "der führende Spieler ist am Zug")


func test_scores_are_rounded_per_tick() -> void:
	var setup := _board_and_voronoi()
	var board: BoardState = setup[0]
	var voronoi: Voronoi = setup[1]
	board.set_cell_color(0, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(1, GameConfig.COLOR_PLAYER2)
	board.active_color = GameConfig.COLOR_PLAYER1
	Scoring.update_scores(board, voronoi, 1.0 / 60.0)
	assert_eq(board.score_p2, 6.0, "360000 * (1/60) / 1000 = 6")


func test_bar_ratios() -> void:
	var board := BoardState.new()
	board.score_p1 = 3.0
	board.score_p2 = 1.0
	var ratios := Scoring.bar_ratios(board)
	assert_almost_eq(ratios.x, 75.0, 0.001)
	assert_almost_eq(ratios.y, 25.0, 0.001)


func test_bar_ratios_without_points() -> void:
	var board := BoardState.new()
	var ratios := Scoring.bar_ratios(board)
	assert_eq(ratios, Vector2.ZERO)


func test_uncolored_cells_do_not_count() -> void:
	var setup := _board_and_voronoi()
	var board: BoardState = setup[0]
	var voronoi: Voronoi = setup[1]
	board.active_color = GameConfig.COLOR_PLAYER1
	Scoring.update_scores(board, voronoi, 1.0)
	assert_eq(board.score_p1, 0.0)
	assert_eq(board.score_p2, 0.0)
