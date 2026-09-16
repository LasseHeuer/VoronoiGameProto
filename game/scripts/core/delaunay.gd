class_name Delaunay
extends RefCounted

## Delaunay-Triangulation als eigenes Kernmodul.
##
## Die Triangulation selbst kommt aus Geometry2D.triangulate_delaunay()
## (Engine-Bordmittel, kein Fremd-Addon). Dieses Modul baut daraus die
## Nachbarschaft und die Dreiecksfächer auf, die d3-delaunay als
## delaunay.neighbors(i) bzw. fuer die Zellpolygone bereitstellt.
##
## Abweichung zur Planformulierung ("delaunator-Port"): Statt den
## JS-Algorithmus Zeile fuer Zeile zu uebersetzen, wird die Engine-
## Triangulation genutzt. Das Ergebnis ist dieselbe Delaunay-Topologie,
## aber robust, in C++ und damit fuer den 60-Hz-Tick geeignet. Die
## Nachbarschaftslisten sind deterministisch aufsteigend sortiert.
##
## Hinweis: Bei kokreisförmigen Punkten ist die Delaunay-Triangulation
## nicht eindeutig. Die Zellpolygone sind davon unabhaengig (die
## Voronoi-Zerlegung ist eindeutig), die Nachbarschaftslisten koennen aber
## um redundante Kanten abweichen.

var points: PackedVector2Array
var triangles := PackedInt32Array()
var halfedges := PackedInt32Array()

var _inedges := PackedInt32Array()
var _neighbors: Array = []


static func build(pts: PackedVector2Array) -> Delaunay:
	var d := Delaunay.new()
	d.points = pts
	d._build()
	return d


func point_count() -> int:
	return points.size()


func neighbors(index: int) -> PackedInt32Array:
	if index < 0 or index >= _neighbors.size():
		return PackedInt32Array()
	return _neighbors[index]


## Dreiecke um einen Punkt in Rotationsreihenfolge. Leer, wenn der Faecher
## offen ist - das ist bei Randpunkten der Fall (unbeschraenkte Zelle) und
## bei Triangulationen, die durch deckungsgleiche Punkte eine Luecke haben.
func triangles_around(index: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if index < 0 or index >= _inedges.size():
		return out
	var start := _inedges[index]
	if start < 0:
		return out
	var edge := start
	while true:
		@warning_ignore("integer_division")
		var triangle := edge / 3
		out.append(triangle)
		var opposite := halfedges[edge]
		if opposite < 0:
			out.clear()
			return out
		edge = _previous_slot(opposite)
		if edge == start:
			return out
	return out


## Nachster Punkt zu (x, y). Entspricht delaunay.find(x, y).
func find(x: float, y: float) -> int:
	var best := -1
	var best_dist := INF
	for i in range(points.size()):
		var d := points[i].distance_squared_to(Vector2(x, y))
		if d < best_dist:
			best_dist = d
			best = i
	return best


static func _next_slot(edge: int) -> int:
	var base := edge - edge % 3
	return base + (edge % 3 + 1) % 3


static func _previous_slot(edge: int) -> int:
	var base := edge - edge % 3
	return base + (edge % 3 + 2) % 3


func _build() -> void:
	var n := points.size()
	_neighbors = []
	halfedges = PackedInt32Array()
	_inedges = PackedInt32Array()
	for i in range(n):
		_neighbors.append(PackedInt32Array())
	_inedges.resize(n)
	_inedges.fill(-1)
	if n < 2:
		return

	if n == 2:
		_neighbors[0] = PackedInt32Array([1])
		_neighbors[1] = PackedInt32Array([0])
		return

	var raw := Geometry2D.triangulate_delaunay(points)
	var tri := PackedInt32Array()
	var i := 0
	while i + 2 < raw.size():
		var a := raw[i]
		var b := raw[i + 1]
		var c := raw[i + 2]
		i += 3
		if a == b or b == c or a == c:
			continue
		var twice_area := (points[b] - points[a]).cross(points[c] - points[a])
		if absf(twice_area) < 1e-12:
			continue
		if twice_area < 0.0:
			var swap := b
			b = c
			c = swap
		tri.append(a)
		tri.append(b)
		tri.append(c)
	triangles = tri

	_build_halfedges()
	_build_neighbors()


func _build_halfedges() -> void:
	var n := points.size()
	var count := triangles.size()
	halfedges = PackedInt32Array()
	halfedges.resize(count)
	halfedges.fill(-1)
	if count == 0:
		return
	var map := {}
	for e in range(count):
		map[triangles[e] * n + triangles[_next_slot(e)]] = e
	for e in range(count):
		var from_v := triangles[e]
		var to_v := triangles[_next_slot(e)]
		var opposite: int = map.get(to_v * n + from_v, -1)
		halfedges[e] = opposite
		_inedges[to_v] = e


func _build_neighbors() -> void:
	var n := points.size()
	var sets: Array = []
	for k in range(n):
		sets.append({})
	var count := triangles.size()
	var t := 0
	while t < count:
		for k in range(3):
			var a := triangles[t + k]
			var b := triangles[t + (k + 1) % 3]
			sets[a][b] = true
			sets[b][a] = true
		t += 3
	for k in range(n):
		var keys: Array = sets[k].keys()
		keys.sort()
		_neighbors[k] = PackedInt32Array(keys)
