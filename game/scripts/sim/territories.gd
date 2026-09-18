class_name Territories
extends RefCounted

## Punktgenerierung, Startterritorien und Farbausbreitung.
##
## Reine Logik auf BoardState + Voronoi, keine Node-Abhaengigkeit.
## Ergebnis- und Reihenfolge-Paritaet zur JS-Version aus src/core.js.

## Gleichstand bleibt stabil; ein positiver Nettovorsprung reicht fuer den
## Farbwechsel aus.
const COLOR_SWITCH_MARGIN_RATIO := 0.0

## Erzeugt 2 * cell_count Punkte: links zufaellig, rechts gespiegelt
## (generateRandomButMirroredPoints). Die Verdopplung ist gewollt und
## wurde aus der JS-Version uebernommen.
static func generate_points(config: GameConfig, rng: DeterministicRng) -> PackedVector2Array:
	var num := config.cell_count
	var w := GameConfig.BOARD_WIDTH
	var h := GameConfig.BOARD_HEIGHT
	var margin := GameConfig.POINT_MARGIN
	var spread := GameConfig.POINT_SPREAD_FACTOR
	var half_w := w * 0.5
	var arr := PackedVector2Array()
	arr.resize(num * 2)
	var exponent := 1.0 - spread
	for i in range(num):
		var rx := pow(rng.next_float(), exponent)
		var ry := pow(rng.next_float(), exponent)
		var x := margin + rx * (half_w - 2.0 * margin)
		var y := margin + ry * (h - 2.0 * margin)
		arr[i * 2] = Vector2(x, y)
		arr[i * 2 + 1] = Vector2(w - x, y)
	return arr


static func generate_dummy_points(border_margin := GameConfig.DUMMY_MARGIN) -> PackedVector2Array:
	var w := GameConfig.BOARD_WIDTH
	var h := GameConfig.BOARD_HEIGHT
	var spacing := GameConfig.DUMMY_SPACING
	var margin := maxf(float(border_margin), GameConfig.DUMMY_MARGIN)
	var pts := PackedVector2Array()
	var x := -margin
	while x <= w + margin:
		pts.append(Vector2(x, -margin))
		pts.append(Vector2(x, h + margin))
		x += spacing
	var y := -margin
	while y <= h + margin:
		pts.append(Vector2(-margin, y))
		pts.append(Vector2(w + margin, y))
		y += spacing
	return pts


## Startaufstellung fuer ein neues Spiel: so lange neu wuerfeln und
## entspannen, bis beide Farbflaechen innerhalb der Toleranz liegen
## (initColorTerritoriesOnNewGame).
static func init_on_new_game(board: BoardState, config: GameConfig, rng: DeterministicRng) -> void:
	var tolerance := GameConfig.BALANCE_TOLERANCE_RATIO * GameConfig.BOARD_AREA
	var balanced := false
	var iteration_count := 0
	var main: Voronoi = null

	while not balanced and iteration_count < GameConfig.NEW_GAME_MAX_ITERATIONS:
		board.points = generate_points(config, rng)
		board.velocities = PackedVector2Array()
		board.velocities.resize(board.points.size())
		board.velocities.fill(Vector2.ZERO)

		var relax_times := GameConfig.RELAX_ITERATIONS_MANY if config.cell_count > GameConfig.RELAX_MANY_THRESHOLD else GameConfig.RELAX_ITERATIONS_FEW
		for i in range(relax_times):
			Relaxation.push_points_no_weight(board, config)
			Relaxation.clamp_to_canvas(board, config)

		main = Voronoi.from_board(board, Rect2(0, 0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT))
		init_color_territories(board, config, main)
		update_colors_by_largest_neighbor(board, main, GameConfig.COLOR_PROPAGATION_ITERATIONS, 0.0)
		main = Voronoi.from_board(board, Rect2(0, 0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT))

		var area1 := total_area_for_color(board, main, GameConfig.COLOR_PLAYER1)
		var area2 := total_area_for_color(board, main, GameConfig.COLOR_PLAYER2)
		if absf(area1 - area2) <= tolerance:
			balanced = true
		iteration_count += 1

	if not balanced:
		push_warning("Farbterritorien nicht ausgeglichen nach %d Iterationen." % iteration_count)


## Setzt die beiden Seed-Zellen auf getrennten Brettseiten: Spieler 1 beginnt
## links, Spieler 2 rechts. Innerhalb der Seite werden moeglichst grosse und
## nicht benachbarte Zellen verwendet (initColorTerritories).
## Seed-Auswahl und Flaechen kommen aus dem Voronoi OHNE Dummy-Punkte,
## die Ausbreitung aus `main` (mit Dummy-Punkten) - wie im Original.
static func init_color_territories(board: BoardState, config: GameConfig, main: Voronoi) -> void:
	var plain := Voronoi.from_points(board.points, Rect2(0, 0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT))
	var areas := PackedFloat32Array()
	areas.resize(plain.real_count)
	for i in range(plain.real_count):
		areas[i] = plain.area(i)

	if plain.real_count < 2:
		return

	var order := _order_by_area_desc(areas)
	var left_order: Array = []
	var right_order: Array = []
	for candidate in order:
		if plain.points[candidate].x <= GameConfig.BOARD_WIDTH * 0.5:
			left_order.append(candidate)
		else:
			right_order.append(candidate)
	var big1: int = left_order[0] if not left_order.is_empty() else order[0]
	var neighbors_of_big1 := {}
	for nb in plain.delaunay().neighbors(big1):
		neighbors_of_big1[nb] = true
	var big2 := -1
	for candidate in right_order:
		if not neighbors_of_big1.has(candidate):
			big2 = candidate
			break
	if big2 < 0 and not right_order.is_empty():
		big2 = right_order[0]
	if big2 < 0:
		for candidate in order:
			if candidate != big1 and not neighbors_of_big1.has(candidate):
				big2 = candidate
				break
	if big2 < 0:
		big2 = order[1]

	board.reset_colors()
	board.set_cell_color(big1, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(big2, GameConfig.COLOR_PLAYER2)
	board.influence_root1 = big1
	board.influence_root2 = big2
	if board.active_color == "":
		board.active_color = GameConfig.COLOR_PLAYER1

	var tolerance := GameConfig.BALANCE_TOLERANCE_RATIO * GameConfig.BOARD_AREA
	var iter := 0
	var area1 := 0.0
	var area2 := 0.0
	while true:
		update_colors_by_largest_neighbor(board, main, GameConfig.COLOR_PROPAGATION_ITERATIONS, 0.0)
		area1 = total_area_for_color(board, main, GameConfig.COLOR_PLAYER1)
		area2 = total_area_for_color(board, main, GameConfig.COLOR_PLAYER2)
		iter += 1
		if absf(area1 - area2) <= tolerance or iter >= GameConfig.INIT_MAX_ITERATIONS:
			break


## Stellt sicher, dass die beiden Spieler gleich viele Zellen besitzen. Bei
## einer ungeraden Zellzahl beginnt Spieler 1 mit genau einer Zelle Vorsprung.
## Die Kandidaten werden nach der kleinsten Flaechenabweichung gewaehlt, damit
## die bereits ausgeglichene Startflaeche moeglichst wenig veraendert wird.
static func balance_color_counts(board: BoardState, voronoi: Voronoi) -> void:
	var total := board.points.size()
	var target1 := ceili(total * 0.5)
	var indices1: Array = []
	var indices2: Array = []
	var uncolored: Array = []
	for i in range(total):
		match board.cell_color(i):
			GameConfig.COLOR_PLAYER1:
				indices1.append(i)
			GameConfig.COLOR_PLAYER2:
				indices2.append(i)
			_:
				uncolored.append(i)

	for index in uncolored:
		if indices1.size() < target1:
			board.set_cell_color(index, GameConfig.COLOR_PLAYER1)
			indices1.append(index)
		else:
			board.set_cell_color(index, GameConfig.COLOR_PLAYER2)
			indices2.append(index)

	while indices1.size() > target1:
		var move1 := _best_recolor_candidate(indices1, board, voronoi, true)
		indices1.erase(move1)
		indices2.append(move1)
		board.set_cell_color(move1, GameConfig.COLOR_PLAYER2)
	while indices1.size() < target1:
		var move2 := _best_recolor_candidate(indices2, board, voronoi, false)
		indices2.erase(move2)
		indices1.append(move2)
		board.set_cell_color(move2, GameConfig.COLOR_PLAYER1)


static func _best_recolor_candidate(indices: Array, board: BoardState, voronoi: Voronoi,
		from_player1: bool) -> int:
	var best := int(indices[0])
	var best_cost := INF
	var area_diff := 0.0
	for i in range(voronoi.real_count):
		if board.cell_color(i) == GameConfig.COLOR_PLAYER1:
			area_diff += voronoi.area(i)
		elif board.cell_color(i) == GameConfig.COLOR_PLAYER2:
			area_diff -= voronoi.area(i)
	for index in indices:
		var area := voronoi.area(index)
		var cost := absf(area_diff - 2.0 * area)
		if cost < best_cost or (is_equal_approx(cost, best_cost) and index < best):
			best = index
			best_cost = cost
	return best


## Farbausbreitung: jede Zelle wird von der Staerke der beiden Wurzelzellen
## erreicht. Es gewinnt der Spieler mit der groesseren Staerke; Zellen, zu denen
## keine Staerke gelangt, bleiben neutral und grau.
static func update_colors_by_largest_neighbor(board: BoardState, voronoi: Voronoi, iterations: int,
		switch_margin_ratio := COLOR_SWITCH_MARGIN_RATIO) -> void:
	board.apply_color_ids(propagate_ids(CellGeometry.from_voronoi(voronoi, true), board.color_ids(),
		iterations, switch_margin_ratio, board.influence_roots()))


## Farbschluessel nach der Ausbreitung. `ids` wird dabei veraendert.
static func propagate_ids(geometry: CellGeometry, ids: PackedByteArray, iterations: int,
		switch_margin_ratio := COLOR_SWITCH_MARGIN_RATIO,
		roots := PackedInt32Array()) -> PackedByteArray:
	for step in color_change_steps(geometry, ids, iterations, switch_margin_ratio, roots):
		ids[step["cell"]] = step["color"]
	return ids


## Einzelne Farbwechsel der Ausbreitung in der Reihenfolge, in der sie
## passieren (Zelle, neue Farbe). `ids` bleibt unveraendert; die Liste eignet
## sich zum schrittweisen Anwenden.
##
## Zielbesitzer ist die per Grenze weitergegebene Staerke bis 0: der staerkere
## Spieler gewinnt, Zellen ohne Staerke werden neutral (0 = grau). Die
## Reihenfolge folgt der Zellgroesse, damit grosse Zellen zuerst kippen.
static func color_change_steps(geometry: CellGeometry, ids: PackedByteArray, iterations: int,
		switch_margin_ratio := COLOR_SWITCH_MARGIN_RATIO,
		roots := PackedInt32Array()) -> Array:
	var n := mini(geometry.count(), ids.size())
	if n == 0 or iterations <= 0:
		return []
	var target := Influence.owner_ids(geometry, ids, roots)
	var steps: Array = []
	for i in _order_by_area_desc(geometry.areas):
		if i >= n:
			continue
		if int(target[i]) != int(ids[i]):
			steps.append({"cell": i, "color": int(target[i])})
	return steps


## Rohwert des relativen Einflusses. Entscheidend ist, wie viel groesser der
## Nachbar ist; dieser Groessenueberschuss wird mit der Laenge der gemeinsamen
## Zellgrenze gewichtet.
static func relative_neighbor_raw_value(geometry: CellGeometry, ids: PackedByteArray,
		cell_index: int, neighbor_index: int) -> float:
	if cell_index < 0 or cell_index >= geometry.count() \
		or neighbor_index < 0 or neighbor_index >= geometry.count() \
		or neighbor_index >= ids.size() or cell_index >= ids.size():
		return 0.0
	var delta := geometry.areas[neighbor_index] - geometry.areas[cell_index]
	if delta <= 0.0 or ids[neighbor_index] == 0:
		return 0.0
	var edge_length := 1.0
	if cell_index < geometry.edge_lengths.size():
		var lengths: Dictionary = geometry.edge_lengths[cell_index]
		edge_length = float(lengths.get(neighbor_index, 0.0))
	if edge_length <= 0.0:
		return 0.0
	var weighted_delta := delta * edge_length
	if ids[neighbor_index] == ids[cell_index]:
		return weighted_delta
	return -weighted_delta


## Global skalierter Einfluss eines Nachbarn. Der groesste gewichtete Wert des
## gesamten Spielfelds entspricht 100; alle anderen Werte bleiben proportional.
## Der Groessenueberschuss bleibt mit der gemeinsamen Zellgrenze gewichtet.
static func relative_neighbor_value(geometry: CellGeometry, ids: PackedByteArray,
		cell_index: int, neighbor_index: int) -> float:
	var raw := relative_neighbor_raw_value(geometry, ids, cell_index, neighbor_index)
	if is_zero_approx(raw) or cell_index < 0 or cell_index >= geometry.neighbors.size():
		return 0.0
	var largest_raw := geometry.max_weighted_area_delta()
	if largest_raw <= 0.0:
		return 0.0
	return raw / largest_raw * 100.0


## Summe aller relativen Nachbareinfluesse einer Zelle.
static func relative_neighbor_total(geometry: CellGeometry, ids: PackedByteArray,
		cell_index: int) -> float:
	var total := 0.0
	if cell_index < 0 or cell_index >= geometry.neighbors.size():
		return total
	for neighbor_index in geometry.neighbors[cell_index]:
		total += relative_neighbor_value(geometry, ids, cell_index, neighbor_index)
	return total


## Groesster sichtbarer Nachbar mit der Zielfarbe
## (getLargestNeighborByColor).
static func largest_neighbor_by_color(board: BoardState, voronoi: Voronoi, cell_idx: int, target_color: String) -> Dictionary:
	var result := {"cell_id": -1, "max_area": 0.0}
	for nb in voronoi.delaunay().neighbors(cell_idx):
		if nb >= voronoi.real_count:
			continue
		if board.cell_color(nb) != target_color:
			continue
		var a := voronoi.area(nb)
		if a > result["max_area"]:
			result["max_area"] = a
			result["cell_id"] = nb
	return result


static func total_area_for_color(board: BoardState, voronoi: Voronoi, color: String) -> float:
	var total := 0.0
	for i in range(voronoi.cells.size()):
		if board.cell_color(i) == color:
			total += voronoi.area(i)
	return total


## Indizes absteigend nach Flaeche, bei Gleichstand nach Index
## (JS-Sortierung ist stabil).
static func _order_by_area_desc(areas: PackedFloat32Array) -> Array:
	var order: Array = []
	order.resize(areas.size())
	for i in range(areas.size()):
		order[i] = i
	order.sort_custom(func(a, b):
		if areas[a] == areas[b]:
			return a < b
		return areas[a] > areas[b])
	return order
