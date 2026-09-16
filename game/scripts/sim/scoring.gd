class_name Scoring
extends RefCounted

## Flaechen-Scoring pro Spieler (updateScores aus src/core.js).
##
## Punkte sammelt immer der Spieler, der gerade NICHT am Zug ist.
## Die Rundung pro Tick wird bewusst beibehalten (Paritaet).

static func update_scores(board: BoardState, voronoi: Voronoi, delta_seconds: float) -> void:
	var area_p1 := 0.0
	var area_p2 := 0.0
	var count_p1 := 0
	var count_p2 := 0
	for i in range(voronoi.cells.size()):
		var color := board.cell_color(i)
		if color == GameConfig.COLOR_PLAYER1:
			area_p1 += voronoi.area(i)
			count_p1 += 1
		elif color == GameConfig.COLOR_PLAYER2:
			area_p2 += voronoi.area(i)
			count_p2 += 1

	var inc_p1 := 0.0
	var inc_p2 := 0.0
	if area_p1 > area_p2:
		inc_p1 = (area_p1 - area_p2) * count_p1
		inc_p2 = (area_p2 - (area_p1 / 2.0)) * count_p2
	else:
		inc_p2 = (area_p2 - area_p1) * count_p2
		inc_p1 = (area_p1 - (area_p2 / 2.0)) * count_p1
	inc_p1 = maxf(0.0, inc_p1)
	inc_p2 = maxf(0.0, inc_p2)

	var scale := delta_seconds / 1000.0
	if board.active_color == GameConfig.COLOR_PLAYER1:
		board.score_p2 += inc_p2 * scale
	elif board.active_color == GameConfig.COLOR_PLAYER2:
		board.score_p1 += inc_p1 * scale

	board.score_p1 = float(BoardGeometry.js_round(board.score_p1))
	board.score_p2 = float(BoardGeometry.js_round(board.score_p2))


## Anteile der beiden Balken in Prozent (updateScoreBars).
static func bar_ratios(board: BoardState) -> Vector2:
	var total := board.score_p1 + board.score_p2
	if total <= 0.0:
		return Vector2.ZERO
	return Vector2(board.score_p1 / total * 100.0, board.score_p2 / total * 100.0)
