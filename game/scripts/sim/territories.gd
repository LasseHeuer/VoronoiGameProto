class_name Territories
extends RefCounted

## Punktgenerierung, Startterritorien und Farbausbreitung.
##
## Reine Logik auf BoardState + Voronoi, keine Node-Abhaengigkeit.
## Ergebnis- und Reihenfolge-Paritaet zur JS-Version aus src/core.js.

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


static func generate_dummy_points() -> PackedVector2Array:
	var w := GameConfig.BOARD_WIDTH
	var h := GameConfig.BOARD_HEIGHT
	var spacing := GameConfig.DUMMY_SPACING
	var margin := GameConfig.DUMMY_MARGIN
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
		update_colors_by_largest_neighbor(board, main, GameConfig.COLOR_PROPAGATION_ITERATIONS)
		main = Voronoi.from_board(board, Rect2(0, 0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT))

		var area1 := total_area_for_color(board, main, GameConfig.COLOR_PLAYER1)
		var area2 := total_area_for_color(board, main, GameConfig.COLOR_PLAYER2)
		if absf(area1 - area2) <= tolerance:
			balanced = true
		iteration_count += 1

	if not balanced:
		push_warning("Farbterritorien nicht ausgeglichen nach %d Iterationen." % iteration_count)


## Setzt die beiden Seed-Zellen (groesste Zelle + groesste nicht
## benachbarte Zelle) und gleicht die Flaechen aus (initColorTerritories).
## Seed-Auswahl und Flaechen kommen aus dem Voronoi OHNE Dummy-Punkte,
## der Ausgleich aus `main` (mit Dummy-Punkten) - wie im Original.
static func init_color_territories(board: BoardState, config: GameConfig, main: Voronoi) -> void:
	var plain := Voronoi.from_points(board.points, Rect2(0, 0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT))
	var areas := PackedFloat32Array()
	areas.resize(plain.real_count)
	for i in range(plain.real_count):
		areas[i] = plain.area(i)

	if plain.real_count < 2:
		return

	var order := _order_by_area_desc(areas)
	var big1: int = order[0]
	var neighbors_of_big1 := {}
	for nb in plain.delaunay().neighbors(big1):
		neighbors_of_big1[nb] = true
	var big2: int = order[1]
	for k in range(1, order.size()):
		var candidate: int = order[k]
		if not neighbors_of_big1.has(candidate):
			big2 = candidate
			break

	board.reset_colors()
	board.set_cell_color(big1, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(big2, GameConfig.COLOR_PLAYER2)
	if board.active_color == "":
		board.active_color = GameConfig.COLOR_PLAYER1

	var tolerance := GameConfig.BALANCE_TOLERANCE_RATIO * GameConfig.BOARD_AREA
	var iter := 0
	var area1 := 0.0
	var area2 := 0.0
	while true:
		update_colors_by_largest_neighbor(board, main, GameConfig.COLOR_PROPAGATION_ITERATIONS)
		area1 = total_area_for_color(board, main, GameConfig.COLOR_PLAYER1)
		area2 = total_area_for_color(board, main, GameConfig.COLOR_PLAYER2)
		iter += 1
		if absf(area1 - area2) <= tolerance or iter >= GameConfig.INIT_MAX_ITERATIONS:
			break


## Farbausbreitung: jede Zelle uebernimmt die Farbe ihres groessten
## sichtbaren Nachbarn (updateColorsByLargestNeighbor).
static func update_colors_by_largest_neighbor(board: BoardState, voronoi: Voronoi, iterations: int) -> void:
	board.apply_color_ids(propagate_ids(CellGeometry.from_voronoi(voronoi), board.color_ids(), iterations))


## Farbschluessel nach der Ausbreitung. `ids` wird dabei veraendert.
static func propagate_ids(geometry: CellGeometry, ids: PackedByteArray, iterations: int) -> PackedByteArray:
	for step in color_change_steps(geometry, ids, iterations):
		ids[step["cell"]] = step["color"]
	return ids


## Einzelne Farbwechsel der Ausbreitung in der Reihenfolge, in der sie
## passieren (Zelle, neue Farbe). `ids` bleibt unveraendert; die Liste eignet
## sich zum schrittweisen Anwenden.
static func color_change_steps(geometry: CellGeometry, ids: PackedByteArray, iterations: int) -> Array:
	var n := mini(geometry.count(), ids.size())
	if n == 0 or iterations <= 0:
		return []
	# Die Flaechen aendern sich innerhalb der Schleife nicht, also ist die
	# Reihenfolge in jeder Iteration dieselbe (JS sortiert stabil neu).
	var order := _order_by_area_desc(geometry.areas)
	var work := ids.duplicate()
	var steps: Array = []
	var changed := true
	var count := 0
	while changed and count < iterations:
		changed = false
		count += 1
		for i in order:
			if i >= n:
				continue
			var max_area := -1.0
			var max_id := 0
			for nb in geometry.neighbors[i]:
				if nb >= n:
					continue
				var nb_id := work[nb]
				if nb_id == 0:
					continue
				var nb_area := geometry.areas[nb]
				if nb_area > max_area:
					max_area = nb_area
					max_id = nb_id
			if max_id != 0 and work[i] != max_id:
				work[i] = max_id
				steps.append({"cell": i, "color": max_id})
				changed = true
	return steps


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
