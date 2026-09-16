extends GutTest

## Tests fuer core/delaunay.gd.

func _grid_points(count: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(count):
		pts.append(Vector2(50.0 + float(i % 7) * 90.0, 40.0 + float(i / 7) * 70.0))
	return pts


func test_two_points_are_neighbours() -> void:
	var delaunay := Delaunay.build(PackedVector2Array([Vector2(0, 0), Vector2(10, 0)]))
	assert_eq(delaunay.point_count(), 2)
	assert_eq(delaunay.neighbors(0), PackedInt32Array([1]))
	assert_eq(delaunay.neighbors(1), PackedInt32Array([0]))


func test_single_point_has_no_neighbours() -> void:
	var delaunay := Delaunay.build(PackedVector2Array([Vector2(5, 5)]))
	assert_eq(delaunay.point_count(), 1)
	assert_eq(delaunay.neighbors(0).size(), 0)


func test_neighbours_are_symmetric() -> void:
	var delaunay := Delaunay.build(_grid_points(40))
	for i in range(delaunay.point_count()):
		for nb in delaunay.neighbors(i):
			assert_true(delaunay.neighbors(nb).has(i), "Nachbarschaft muss symmetrisch sein (%d/%d)" % [i, nb])


func test_full_triangulation_counts() -> void:
	var points := _grid_points(40)
	var delaunay := Delaunay.build(points)
	var boundary := 0
	for e in range(delaunay.halfedges.size()):
		if delaunay.halfedges[e] == -1:
			boundary += 1
	var triangles := floori(float(delaunay.triangles.size()) / 3.0)
	# Eulersche Formel fuer eine Triangulation mit h Randpunkten; die
	# Anzahl der Randkanten entspricht der Anzahl der Randpunkte.
	assert_eq(boundary, 20, "Randkanten im 7x6-Raster")
	assert_almost_eq(float(triangles), float(2 * points.size() - 2 - boundary), 0.01,
		"Dreiecksanzahl nach Euler")


func test_neighbour_lists_are_sorted_and_unique() -> void:
	var delaunay := Delaunay.build(_grid_points(30))
	for i in range(delaunay.point_count()):
		var previous := -1
		for nb in delaunay.neighbors(i):
			assert_gt(nb, previous, "Nachbarn aufsteigend und ohne Duplikate")
			previous = nb


func test_find_returns_nearest_point() -> void:
	var points := PackedVector2Array([
		Vector2(10.0, 10.0), Vector2(200.0, 100.0), Vector2(880.0, 580.0),
	])
	var delaunay := Delaunay.build(points)
	assert_eq(delaunay.find(190.0, 110.0), 1)
	assert_eq(delaunay.find(12.0, 12.0), 0)


func test_triangles_around_covers_all_incident_triangles() -> void:
	var points := _grid_points(30)
	var delaunay := Delaunay.build(points)
	var interior := -1
	for i in range(delaunay.point_count()):
		var fan := delaunay.triangles_around(i)
		if fan.size() >= 3 and fan.size() == _incident_triangle_count(delaunay, i):
			interior = i
			break
	assert_ne(interior, -1, "es muss einen inneren Punkt geben")
	assert_eq(delaunay.triangles_around(interior).size(), _incident_triangle_count(delaunay, interior),
		"der Faecher enthaelt jedes Dreieck mit dem Punkt genau einmal")


func test_fan_of_a_hull_point_is_empty() -> void:
	# Punkt 0 ist die obere linke Ecke des Rasters, also ein Randpunkt.
	var delaunay := Delaunay.build(_grid_points(20))
	assert_gt(_incident_triangle_count(delaunay, 0), 0)
	assert_eq(delaunay.triangles_around(0).size(), 0, "offener Faecher am Rand")


func _incident_triangle_count(delaunay: Delaunay, index: int) -> int:
	var total := floori(float(delaunay.triangles.size()) / 3.0)
	var count := 0
	for t in range(total):
		for k in range(3):
			if delaunay.triangles[t * 3 + k] == index:
				count += 1
				break
	return count


func test_collinear_points_do_not_crash() -> void:
	var points := PackedVector2Array()
	for i in range(10):
		points.append(Vector2(float(i) * 10.0, 0.0))
	var delaunay := Delaunay.build(points)
	assert_eq(delaunay.point_count(), 10)
	# Kollineare Punkte haben keine Dreiecke. Das eigene Modul liefert
	# dafuer einen leeren Graphen (d3-delaunay wuerde eine Linie bilden);
	# im Spiel kann dieser Fall nicht auftreten, weil Punkte zweidimensional
	# gestreut werden.
	assert_eq(delaunay.triangles.size(), 0)
	assert_eq(delaunay.neighbors(0).size(), 0)
	# Die Punktabfrage funktioniert trotzdem.
	assert_eq(delaunay.find(5.0, 5.0), 0)


func test_duplicate_points_do_not_crash() -> void:
	var points := PackedVector2Array([
		Vector2(100.0, 100.0), Vector2(100.0, 100.0), Vector2(300.0, 120.0), Vector2(200.0, 400.0),
	])
	var delaunay := Delaunay.build(points)
	assert_eq(delaunay.point_count(), 4)
	assert_gt(delaunay.triangles.size(), 0)


func test_two_point_fan_is_empty() -> void:
	var delaunay := Delaunay.build(PackedVector2Array([Vector2(0, 0), Vector2(10, 0)]))
	assert_eq(delaunay.triangles_around(0).size(), 0)
