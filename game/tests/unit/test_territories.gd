extends GutTest

## Tests fuer sim/territories.gd und die Zugregeln aus sim/turns.gd.

func _config(cell_count := 20) -> GameConfig:
	var config := GameConfig.new()
	config.cell_count = cell_count
	return config


func test_generate_points_is_mirrored_and_doubled() -> void:
	var config := _config(20)
	var points := Territories.generate_points(config, DeterministicRng.new(9))
	assert_eq(points.size(), 40, "num Zellen ergeben 2 * num Punkte")
	for i in range(0, points.size(), 2):
		var left := points[i]
		var right := points[i + 1]
		assert_almost_eq(left.y, right.y, 0.0001)
		assert_almost_eq(left.x + right.x, GameConfig.BOARD_WIDTH, 0.0001)
		assert_true(left.x <= GameConfig.BOARD_WIDTH * 0.5 - 30.0 + 0.01)
		assert_true(right.x >= GameConfig.BOARD_WIDTH * 0.5 + 30.0 - 0.01)


func test_generate_points_stays_inside_the_margins() -> void:
	var config := _config(100)
	var points := Territories.generate_points(config, DeterministicRng.new(3))
	assert_eq(points.size(), 200)
	for p in points:
		assert_between(p.x, GameConfig.POINT_MARGIN - 0.01, GameConfig.BOARD_WIDTH - GameConfig.POINT_MARGIN + 0.01)
		assert_between(p.y, GameConfig.POINT_MARGIN - 0.01, GameConfig.BOARD_HEIGHT - GameConfig.POINT_MARGIN + 0.01)


func test_generate_points_is_reproducible() -> void:
	var config := _config(20)
	var a := Territories.generate_points(config, DeterministicRng.new(1234))
	var b := Territories.generate_points(config, DeterministicRng.new(1234))
	assert_eq(a, b)


func test_dummy_points_sit_outside_the_board() -> void:
	var dummies := Territories.generate_dummy_points()
	assert_eq(dummies.size(), 72)
	for p in dummies:
		var outside := p.x < 0.0 or p.x > GameConfig.BOARD_WIDTH or p.y < 0.0 or p.y > GameConfig.BOARD_HEIGHT
		assert_true(outside, "Dummy-Punkt %s liegt ausserhalb" % p)
	assert_eq(Territories.generate_dummy_points()[0].y, -GameConfig.DUMMY_MARGIN,
		"Dummy-Rand liegt ausserhalb des Spielpunkt-Rands")


func test_new_game_creates_two_colored_seeds() -> void:
	var config := _config(20)
	var board := BoardState.new()
	board.dummy_points = Territories.generate_dummy_points()
	Territories.init_on_new_game(board, config, DeterministicRng.new(20250116))

	var count_p1 := 0
	var count_p2 := 0
	for i in range(board.cell_colors.size()):
		if board.cell_color(i) == GameConfig.COLOR_PLAYER1:
			count_p1 += 1
		elif board.cell_color(i) == GameConfig.COLOR_PLAYER2:
			count_p2 += 1
	assert_gt(count_p1, 0, "Spieler 1 besitzt mindestens eine Zelle")
	assert_gt(count_p2, 0, "Spieler 2 besitzt mindestens eine Zelle")
	assert_eq(board.active_color, GameConfig.COLOR_PLAYER1, "Spieler 1 beginnt")
	for i in range(board.points.size()):
		assert_between(board.points[i].x, GameConfig.POINT_MARGIN - 0.01,
			GameConfig.BOARD_WIDTH - GameConfig.POINT_MARGIN + 0.01)
		assert_between(board.points[i].y, GameConfig.POINT_MARGIN - 0.01,
			GameConfig.BOARD_HEIGHT - GameConfig.POINT_MARGIN + 0.01)


func test_new_game_is_reproducible() -> void:
	var config := _config(20)
	var first := BoardState.new()
	first.dummy_points = Territories.generate_dummy_points()
	Territories.init_on_new_game(first, config, DeterministicRng.new(4242))
	var second := BoardState.new()
	second.dummy_points = Territories.generate_dummy_points()
	Territories.init_on_new_game(second, config, DeterministicRng.new(4242))
	assert_eq(first.points, second.points)
	assert_eq(first.cell_colors, second.cell_colors)


func test_new_game_balances_color_areas() -> void:
	var config := _config(20)
	var board := BoardState.new()
	board.dummy_points = Territories.generate_dummy_points()
	Territories.init_on_new_game(board, config, DeterministicRng.new(777))
	var rect := Rect2(0, 0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)
	var main := Voronoi.from_board(board, rect)
	var area1 := Territories.total_area_for_color(board, main, GameConfig.COLOR_PLAYER1)
	var area2 := Territories.total_area_for_color(board, main, GameConfig.COLOR_PLAYER2)
	var tolerance := GameConfig.BALANCE_TOLERANCE_RATIO * GameConfig.BOARD_AREA
	assert_lt(absf(area1 - area2), tolerance, "Flaechen sind innerhalb der Toleranz")


## Die Startaufstellung ist gespiegelt: die Punkte werden paarweise erzeugt,
## also sind Zelle i und ihr Spiegel i+1 flaechengleich und tragen
## entgegengesetzte Farben (neutrale Zellen bleiben auf beiden Seiten neutral).
func test_new_game_colors_are_mirrored() -> void:
	var config := _config(20)
	var board := BoardState.new()
	board.dummy_points = Territories.generate_dummy_points()
	Territories.init_on_new_game(board, config, DeterministicRng.new(20250116))
	var rect := Rect2(0, 0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)
	var main := Voronoi.from_board(board, rect)
	assert_eq(board.influence_root2, Territories._mirror_index(board.influence_root1),
		"die Wurzelzellen sind Spiegel")
	for i in range(0, board.points.size(), 2):
		assert_almost_eq(board.points[i].x + board.points[i + 1].x, GameConfig.BOARD_WIDTH, 0.01,
			"Punktpaar %d ist gespiegelt" % i)
		assert_almost_eq(main.area(i), main.area(i + 1), 1.0,
			"Flaechenpaar %d ist gespiegelt" % i)
		var left := BoardState.color_id(board.cell_color(i))
		var right := BoardState.color_id(board.cell_color(i + 1))
		assert_eq(left, _opponent_id(right),
			"Zelle %d und ihr Spiegel haben Gegenfarben" % i)


static func _opponent_id(id: int) -> int:
	return 3 - id if id != 0 else 0


func test_small_point_move_does_not_flip_the_whole_board() -> void:
	var config := _config(20)
	var board := BoardState.new()
	board.dummy_points = Territories.generate_dummy_points()
	Territories.init_on_new_game(board, config, DeterministicRng.new(20250116))
	var before := board.color_ids()
	var moved := board.points
	moved[0] += Vector2(1.0, 0.0)
	board.points = moved
	var main := Voronoi.from_board(board,
		Rect2(0.0, 0.0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT))
	var steps := Territories.color_change_steps(CellGeometry.from_voronoi(main), before,
		GameConfig.COLOR_PROPAGATION_ITERATIONS)
	var changed := {}
	for step in steps:
		changed[int(step["cell"])] = true
	assert_lt(changed.size(), board.points.size() - 1,
		"eine kleine Bewegung darf keine globale Farb-Kaskade ausloesen")


func test_color_count_balancing_handles_non_mirrored_setup() -> void:
	var board := BoardState.new()
	board.points = PackedVector2Array([
		Vector2(120.0, 120.0), Vector2(300.0, 180.0), Vector2(520.0, 140.0),
		Vector2(700.0, 300.0), Vector2(420.0, 470.0)])
	board.reset_colors()
	for i in range(4):
		board.set_cell_color(i, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(4, GameConfig.COLOR_PLAYER2)
	var voronoi := Voronoi.from_points(board.points,
		Rect2(0.0, 0.0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT))
	Territories.balance_color_counts(board, voronoi)

	var count1 := 0
	var count2 := 0
	for color in board.cell_colors:
		count1 += 1 if color == GameConfig.COLOR_PLAYER1 else 0
		count2 += 1 if color == GameConfig.COLOR_PLAYER2 else 0
	assert_eq(count1, 3, "Spieler 1 bekommt bei ungerader Zellzahl die mittlere Anzahl")
	assert_eq(count2, 2, "Spieler 2 bekommt bei ungerader Zellzahl die mittlere Anzahl")


func test_colors_spread_over_visible_neighbours() -> void:
	var config := _config(20)
	var board := BoardState.new()
	board.dummy_points = Territories.generate_dummy_points()
	board.points = Territories.generate_points(config, DeterministicRng.new(8))
	board.reset_colors()
	board.set_cell_color(0, GameConfig.COLOR_PLAYER1)
	var rect := Rect2(0, 0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)
	var main := Voronoi.from_board(board, rect)
	Territories.update_colors_by_largest_neighbor(board, main, GameConfig.COLOR_PROPAGATION_ITERATIONS)
	var colored := 0
	for i in range(board.cell_colors.size()):
		if board.cell_color(i) != "":
			colored += 1
	assert_gt(colored, 1, "die Farbe breitet sich auf Nachbarzellen aus")


func test_change_steps_reproduce_the_spread_result() -> void:
	var config := _config(30)
	var board := BoardState.new()
	board.dummy_points = Territories.generate_dummy_points()
	board.points = Territories.generate_points(config, DeterministicRng.new(21))
	board.reset_colors()
	board.set_cell_color(0, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(1, GameConfig.COLOR_PLAYER2)
	var rect := Rect2(0, 0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)
	var main := Voronoi.from_board(board, rect)
	var ids := board.color_ids()
	var geometry := CellGeometry.from_voronoi(main)

	var steps := Territories.color_change_steps(geometry, ids, GameConfig.COLOR_PROPAGATION_ITERATIONS)
	assert_gt(steps.size(), 0, "es gibt Farbwechsel")
	assert_eq(board.color_ids(), ids, "die Rechnung laesst den Zustand unveraendert")

	var after := Territories.propagate_ids(geometry, board.color_ids(), GameConfig.COLOR_PROPAGATION_ITERATIONS)
	for i in range(steps.size()):
		assert_true(steps[i].has("cell") and steps[i].has("color"))

	board.apply_color_ids(after)
	assert_eq(board.color_ids(), after)
	# Nach dem Anwenden ist die Ausbreitung fertig: kein weiterer Wechsel.
	assert_eq(Territories.color_change_steps(geometry, board.color_ids(), GameConfig.COLOR_PROPAGATION_ITERATIONS).size(), 0)


func test_largest_neighbor_by_color() -> void:
	var config := _config(20)
	var board := BoardState.new()
	board.dummy_points = Territories.generate_dummy_points()
	board.points = Territories.generate_points(config, DeterministicRng.new(11))
	board.reset_colors()
	var rect := Rect2(0, 0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)
	var main := Voronoi.from_board(board, rect)
	board.set_cell_color(1, GameConfig.COLOR_PLAYER2)
	var found := Territories.largest_neighbor_by_color(board, main, 0, GameConfig.COLOR_PLAYER2)
	if main.delaunay().neighbors(0).has(1):
		assert_eq(found["cell_id"], 1)
		assert_gt(found["max_area"], 0.0)
	else:
		assert_eq(found["cell_id"], -1)


## Nur die Wurzel traegt einen Groessenwert (die Tonmenge x); alle anderen
## Zellen bekommen ausschliesslich den Fluss, der bei ihnen ankommt.
func test_only_root_carries_the_size_value() -> void:
	var geometry := CellGeometry.new()
	geometry.areas = PackedFloat32Array([400.0, 200.0, 100.0])
	geometry.neighbors = [PackedInt32Array([1]), PackedInt32Array([0, 2]), PackedInt32Array([1])]
	geometry.edge_lengths = [{1: 1.0}, {0: 1.0, 2: 1.0}, {1: 1.0}]
	var values := Influence.cell_values(geometry, PackedByteArray([1, 0, 0]),
		PackedInt32Array([0, -1]), 100.0)
	assert_almost_eq(values[0], 100.0, 0.001, "nur die Wurzel traegt x")
	assert_almost_eq(values[1], 100.0, 0.001, "die naechste Zelle bekommt den Fluss")
	assert_almost_eq(values[2], 100.0, 0.001, "der Fluss laeuft weiter")


## Der Fluss teilt sich nach der gemeinsamen Kantenlaenge auf die kleineren
## Nachbarn auf.
func test_flow_splits_by_edge_length() -> void:
	var geometry := CellGeometry.new()
	geometry.areas = PackedFloat32Array([400.0, 300.0, 200.0])
	geometry.neighbors = [PackedInt32Array([1, 2]), PackedInt32Array([0]), PackedInt32Array([0])]
	geometry.edge_lengths = [{1: 3.0, 2: 1.0}, {0: 3.0}, {0: 1.0}]
	var values := Influence.cell_values(geometry, PackedByteArray([1, 0, 0]),
		PackedInt32Array([0, -1]), 100.0)
	assert_almost_eq(values[1], 75.0, 0.001, "laengere Kante bekommt mehr")
	assert_almost_eq(values[2], 25.0, 0.001, "kuerzere Kante bekommt weniger")


## Der Zufluss laeuft nur bergab: groessere Nachbarn werden nie erreicht.
func test_flow_only_reaches_smaller_neighbors() -> void:
	var geometry := CellGeometry.new()
	geometry.areas = PackedFloat32Array([400.0, 300.0, 200.0, 100.0])
	geometry.neighbors = [PackedInt32Array([1]), PackedInt32Array([0, 2]),
		PackedInt32Array([1, 3]), PackedInt32Array([2])]
	geometry.edge_lengths = [{1: 1.0}, {0: 1.0, 2: 1.0}, {1: 1.0, 3: 1.0}, {2: 1.0}]
	var values := Influence.cell_values(geometry, PackedByteArray([0, 0, 1, 0]),
		PackedInt32Array([2, -1]), 100.0)
	assert_eq(values[0], 0.0, "eine groessere Zelle wird nicht erreicht")
	assert_eq(values[1], 0.0, "eine groessere Zelle wird nicht erreicht")
	assert_gt(values[3], 0.0, "kleinere Nachbarn werden erreicht")


## Der Zellwert ist die vorzeichenbehaftete Summe der ankommenden Flusswerte:
## zwei rote Nachbarn mit +20 und +30 und ein blauer mit -40 ergeben +10.
## Beide Wurzeln sind gleich gross (groesste Zellen des Bretts) und tragen
## daher den vollen Wert +100 bzw. -100.
func test_cell_value_is_the_signed_sum_of_inflows() -> void:
	var geometry := CellGeometry.new()
	geometry.areas = PackedFloat32Array([4000.0, 3000.0, 2000.0, 1000.0, 4000.0, 1000.0, 100.0])
	geometry.neighbors = [
		PackedInt32Array([1, 2, 3]),
		PackedInt32Array([0, 6]),
		PackedInt32Array([0, 6]),
		PackedInt32Array([0]),
		PackedInt32Array([6, 5]),
		PackedInt32Array([4]),
		PackedInt32Array([1, 2, 4])]
	geometry.edge_lengths = [
		{1: 2.0, 2: 3.0, 3: 5.0},
		{0: 2.0, 6: 1.0},
		{0: 3.0, 6: 1.0},
		{0: 5.0},
		{6: 2.0, 5: 3.0},
		{4: 3.0},
		{1: 1.0, 2: 1.0, 4: 2.0}]
	var ids := PackedByteArray([1, 0, 0, 0, 2, 0, 0])
	var values := Influence.cell_values(geometry, ids, PackedInt32Array([0, 4]), 100.0)
	assert_almost_eq(values[1], 20.0, 0.001, "erster roter Zufluss")
	assert_almost_eq(values[2], 30.0, 0.001, "zweiter roter Zufluss")
	assert_almost_eq(values[6], 10.0, 0.001, "20 + 30 - 40 = 10")


## Eine Zelle gehoert dem Spieler, dessen Zufluss an der Zelle ueberwiegt.
func test_owner_ids_follows_downhill_reachability() -> void:
	var geometry := CellGeometry.new()
	geometry.areas = PackedFloat32Array([400.0, 300.0, 100.0, 350.0])
	geometry.neighbors = [PackedInt32Array([1]), PackedInt32Array([0, 2]),
		PackedInt32Array([1, 3]), PackedInt32Array([2])]
	geometry.edge_lengths = [{1: 1.0}, {0: 1.0, 2: 1.0}, {1: 1.0, 3: 1.0}, {2: 1.0}]
	var ids := PackedByteArray([1, 0, 0, 2])
	var values := Influence.cell_values(geometry, ids, PackedInt32Array([0, 3]), 100.0)
	assert_gt(values[0], 0.0, "die rote Wurzel ist positiv")
	assert_gt(values[1], 0.0, "Zelle 1 ist rot")
	assert_lt(values[3], 0.0, "die blaue Wurzel ist negativ")

	var owners := Influence.owner_ids(geometry, ids, PackedInt32Array([0, 3]), 100.0)
	assert_eq(owners[0], 1)
	assert_eq(owners[1], 1, "nur Rot erreicht Zelle 1")
	assert_eq(owners[3], 2, "nur Blau erreicht Zelle 3")


## Die Wurzel traegt x mal ihren Flaechenanteil an der groessten Zelle. Eine
## kleinere blaue Wurzel hat daher einen kleineren eigenen Wert und kann vom
## groesseren roten Zufluss ueberholt werden.
func test_smaller_root_can_be_overtaken_by_flow() -> void:
	var geometry := CellGeometry.new()
	geometry.areas = PackedFloat32Array([4000.0, 3000.0, 2000.0])
	geometry.neighbors = [PackedInt32Array([1, 2]), PackedInt32Array([0, 2]),
		PackedInt32Array([0, 1])]
	geometry.edge_lengths = [{1: 1.0, 2: 1.0}, {0: 1.0, 2: 1.0}, {0: 1.0, 1: 1.0}]
	var ids := PackedByteArray([1, 0, 2])
	var values := Influence.cell_values(geometry, ids, PackedInt32Array([0, 2]), 100.0)
	assert_almost_eq(values[0], 100.0, 0.001, "die groesste Zelle traegt x")
	assert_gt(values[2], 0.0, "der rote Zufluss ueberholt die kleinere blaue Wurzel")

	var owners := Influence.owner_ids(geometry, ids, PackedInt32Array([0, 2]), 100.0)
	assert_eq(owners[2], 1, "die kleinere blaue Wurzel faellt an Rot")


## Eine Wurzel gibt ihren angezeigten (Netto-)Zellwert weiter: zieht
## gegnerischer Zufluss den Groessenwert auf 0, fliesst nichts mehr weiter.
func test_root_passes_its_net_value_when_opposed() -> void:
	var geometry := CellGeometry.new()
	geometry.areas = PackedFloat32Array([4000.0, 3000.0, 2000.0, 1000.0])
	geometry.neighbors = [PackedInt32Array([1, 2]), PackedInt32Array([0, 3]),
		PackedInt32Array([0, 3]), PackedInt32Array([1, 2])]
	geometry.edge_lengths = [{1: 1.0, 2: 1.0}, {0: 1.0, 3: 1.0},
		{0: 1.0, 3: 1.0}, {1: 1.0, 2: 1.0}]
	var ids := PackedByteArray([1, 0, 2, 0])
	var field := Influence.distribute(geometry, ids, PackedInt32Array([0, 2]), 100.0)
	var values: PackedFloat32Array = field["values"]
	var edges: Dictionary = field["edges"]
	assert_almost_eq(values[2], 0.0, 0.001, "der gegnerische Zufluss gleicht die blaue Wurzel aus")
	assert_true(is_zero_approx(float(edges.get(2 * geometry.count() + 3, 0.0))),
		"eine ausgeglichene Wurzel gibt nichts weiter")


## Eine uebernommene Wurzel gibt ihren verbleibenden Restwert weiter, nicht
## ihren urspruenglichen Groessenwert: die blaue Wurzel traegt -75, der rote
## Zufluss hebt sie auf -25, und genau -25 fliesst weiter.
func test_root_passes_the_reduced_net_value() -> void:
	var geometry := CellGeometry.new()
	geometry.areas = PackedFloat32Array([4000.0, 3500.0, 3000.0, 500.0])
	geometry.neighbors = [PackedInt32Array([1, 2]), PackedInt32Array([0]),
		PackedInt32Array([0, 3]), PackedInt32Array([2])]
	geometry.edge_lengths = [{1: 1.0, 2: 1.0}, {0: 1.0}, {0: 1.0, 3: 1.0}, {2: 1.0}]
	var ids := PackedByteArray([1, 0, 2, 0])
	var field := Influence.distribute(geometry, ids, PackedInt32Array([0, 2]), 100.0)
	var values: PackedFloat32Array = field["values"]
	var edges: Dictionary = field["edges"]
	assert_almost_eq(values[2], -25.0, 0.001, "Groessenwert -75 plus roter Zufluss +50")
	assert_almost_eq(float(edges.get(2 * geometry.count() + 3, 0.0)), -25.0, 0.001,
		"die Wurzel gibt ihren Restwert weiter")


## Die Wurzel folgt der groessten Zelle ihrer Farbe: waechst im Spiel eine
## andere Zelle heran, traegt sie den Groessenwert und gibt ihn weiter, statt
## dass die groesste Zelle ohne Wert bleibt.
func test_root_follows_the_largest_cell_of_its_color() -> void:
	var geometry := CellGeometry.new()
	geometry.areas = PackedFloat32Array([3000.0, 4000.0, 2000.0])
	geometry.neighbors = [PackedInt32Array([1, 2]), PackedInt32Array([0, 2]),
		PackedInt32Array([0, 1])]
	geometry.edge_lengths = [{1: 1.0, 2: 1.0}, {0: 1.0, 2: 1.0}, {0: 1.0, 1: 1.0}]
	var ids := PackedByteArray([1, 1, 2])
	# Zelle 0 ist die gespeicherte rote Wurzel, Zelle 1 ist aber groesser.
	var resolved := Influence.resolve_roots(geometry, ids, PackedInt32Array([0, 2]))
	assert_eq(resolved[0], 1, "die groessere rote Zelle wird zur Wurzel")

	var values := Influence.cell_values(geometry, ids, PackedInt32Array([0, 2]), 100.0)
	assert_almost_eq(values[1], 100.0, 0.001, "die neue Wurzel traegt den Groessenwert")


## Graue Zellen vererben nichts an kleinere Nachbarn: sie gelten als verloren.
func test_neutral_cells_do_not_pass_values_on() -> void:
	var geometry := CellGeometry.new()
	geometry.areas = PackedFloat32Array([4000.0, 1000.0, 100.0])
	geometry.neighbors = [PackedInt32Array([1]), PackedInt32Array([0, 2]),
		PackedInt32Array([1])]
	geometry.edge_lengths = [{1: 1.0}, {0: 1.0, 2: 1.0}, {1: 1.0}]
	var ids := PackedByteArray([1, 0, 0])
	var values := Influence.cell_values(geometry, ids, PackedInt32Array([0, -1]), 9.0)

	assert_true(Influence.is_neutral(values[0]), "die Wurzel liegt unter der Schwelle")
	assert_eq(values[1], 0.0, "die graue Zelle vererbt nichts")
	assert_eq(values[2], 0.0, "auch kleineren Zellen wird nichts vererbt")


## Graue Zellen gehoeren keinem Spieler mehr.
func test_owner_ids_marks_neutral_cells_as_unowned() -> void:
	var geometry := CellGeometry.new()
	geometry.areas = PackedFloat32Array([4000.0, 1000.0])
	geometry.neighbors = [PackedInt32Array([1]), PackedInt32Array([0])]
	geometry.edge_lengths = [{1: 1.0}, {0: 1.0}]
	var ids := PackedByteArray([1, 0])

	var owners := Influence.owner_ids(geometry, ids, PackedInt32Array([0, -1]), 9.0)
	assert_eq(owners[0], 0, "die graue Wurzel gehoert keinem Spieler")
	assert_eq(owners[1], 0, "die graue Folgezelle gehoert keinem Spieler")

	owners = Influence.owner_ids(geometry, ids, PackedInt32Array([0, -1]), 100.0)
	assert_eq(owners[0], 1, "starke Zellen behalten ihren Besitzer")
	assert_eq(owners[1], 1, "der Fluss reicht weiter")


## Bei der Flaechenwertung zaehlen graue Zellen fuer keinen Spieler.
func test_total_area_ignores_neutral_cells() -> void:
	var board := BoardState.new()
	board.points = PackedVector2Array([Vector2(200.0, 300.0), Vector2(700.0, 300.0)])
	board.dummy_points = PackedVector2Array()
	board.reset_colors()
	board.set_cell_color(0, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(1, GameConfig.COLOR_PLAYER2)
	var rect := Rect2(0.0, 0.0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)
	var main := Voronoi.from_board(board, rect)

	board.influence_start_strength = 100.0
	assert_gt(Territories.total_area_for_color(board, main, GameConfig.COLOR_PLAYER1), 0.0,
		"starke Zellen zaehlen")

	board.influence_start_strength = 1.0
	assert_eq(Territories.total_area_for_color(board, main, GameConfig.COLOR_PLAYER1), 0.0,
		"graue Zellen zaehlen nicht")


func test_turns_drag_permission_follows_active_color() -> void:
	var config := _config(4)
	var board := BoardState.new()
	board.points = PackedVector2Array([Vector2(100, 100), Vector2(200, 200)])
	board.reset_colors()
	board.active_color = GameConfig.COLOR_PLAYER1
	board.set_cell_color(0, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(1, GameConfig.COLOR_PLAYER2)
	assert_true(Turns.can_start_drag(board, 0, config))
	assert_false(Turns.can_start_drag(board, 1, config))

	config.alternating_moves = false
	assert_true(Turns.can_start_drag(board, 1, config))


func test_turns_automatic_switch_only_after_movement() -> void:
	var config := _config(4)
	var board := BoardState.new()
	board.points = PackedVector2Array([Vector2(100, 100), Vector2(200, 200)])
	board.reset_colors()
	board.active_color = GameConfig.COLOR_PLAYER1
	board.set_cell_color(0, GameConfig.COLOR_PLAYER2)
	assert_false(Turns.should_switch_automatically(board, 0, config, 0.0))
	assert_false(Turns.should_switch_automatically(board, 0, config, GameConfig.MOVE_THRESHOLD))
	assert_true(Turns.should_switch_automatically(board, 0, config, 5.0))

	config.alternating_moves = false
	assert_false(Turns.should_switch_automatically(board, 0, config, 5.0))


func test_turns_toggle() -> void:
	assert_eq(Turns.toggled_color(GameConfig.COLOR_PLAYER1), GameConfig.COLOR_PLAYER2)
	assert_eq(Turns.toggled_color(GameConfig.COLOR_PLAYER2), GameConfig.COLOR_PLAYER1)
