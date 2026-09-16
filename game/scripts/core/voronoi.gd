class_name Voronoi
extends RefCounted

## Zellpolygone aus einer Delaunay-Triangulation, beschnitten auf das Brett.
##
## d3-delaunay liefert cellPolygon(i) bereits auf das uebergebene Rechteck
## beschnitten. Genau das passiert hier: jede Zelle ist der Schnitt des
## Rechtecks mit allen Mittelsenkrechten-Halbebenen zu den Delaunay-
## Nachbarn. Weil nur echte Delaunay-Nachbarn benoetigt werden, ist das
## Ergebnis identisch zur d3-Zelle - ohne Sonderfall fuer unbeschraenkte
## Randzellen.
##
## Alles wird einmal pro Aufbau berechnet und geteilt (statt wie in der
## JS-Version mehrfach pro Frame).

const MIN_EDGE_EPSILON := 1e-6
## Toleranz fuer "Punkt liegt auf der Mittelsenkrechten". Die Zell-Ecken
## sind Umkreismittelpunkte (float32) und weichen rechnerisch bis ca.
## 2e-3 px von der exakten Mittelsenkrechten ab.
const LINETOL := 0.01

var rect: Rect2
var points: PackedVector2Array
var cells: Array = []
var areas := PackedFloat32Array()
var visible_neighbors: Array = []
## Anzahl der "echten" Zellen. Punkte ab diesem Index sind Dummy-Punkte,
## die nur als Nachbarn fuer die Mittelsenkrechten dienen.
var real_count := 0

var _delaunay: Delaunay
var _edge_lengths := {}


static func build(delaunay: Delaunay, bounds: Rect2, min_edge := 5.0, real_count := -1, with_visible_neighbors := true) -> Voronoi:
	var v := Voronoi.new()
	v._delaunay = delaunay
	v.points = delaunay.points
	v.rect = bounds
	v.real_count = real_count if real_count >= 0 else delaunay.points.size()
	v._build_cells()
	if with_visible_neighbors:
		v._build_visible_neighbors(min_edge)
	else:
		v.visible_neighbors = []
		for i in range(v.real_count):
			v.visible_neighbors.append(PackedInt32Array())
	return v


## Voronoi inklusive Dummy-Punkten (entspricht updateDelaunayAndVoronoi()).
static func from_board(board: BoardState, bounds: Rect2, min_edge := 5.0, with_visible_neighbors := true) -> Voronoi:
	return build(Delaunay.build(board.all_points()), bounds, min_edge, board.points.size(), with_visible_neighbors)


## Voronoi nur aus den echten Punkten (entspricht d3.Delaunay.from(points)).
## Die sichtbaren Nachbarn werden hier nicht gebraucht.
static func from_points(pts: PackedVector2Array, bounds: Rect2) -> Voronoi:
	return build(Delaunay.build(pts), bounds, 5.0, pts.size(), false)


func delaunay() -> Delaunay:
	return _delaunay


func cell_polygon(index: int) -> PackedVector2Array:
	if index < 0 or index >= cells.size():
		return PackedVector2Array()
	return cells[index]


func area(index: int) -> float:
	if index < 0 or index >= areas.size():
		return 0.0
	return areas[index]


func min_max_area() -> Vector2:
	var min_a := INF
	var max_a := -INF
	for i in range(areas.size()):
		var a := areas[i]
		if a < min_a:
			min_a = a
		if a > max_a:
			max_a = a
	return Vector2(min_a, max_a)


## Laenge der gemeinsamen sichtbaren Kante zweier Zellen.
##
## Die JS-Version schneidet beide Zellpolygone und nimmt den Umfang des
## Ergebnisses. Dieser Schnitt ist eine Strecke, sein Umfang also genau
## das Doppelte der Kantenlaenge (nachgeprueft mit dem Original-Algorithmus).
## Deshalb wird hier direkt 2 * Laenge zurueckgegeben - gleiche Schwelle
## (min_edge), gleiches Ergebnis.
##
## Die gemeinsame Kante ist der Teil des Zellrands, der auf der
## Mittelsenkrechten der beiden Punkte liegt. Als "auf der Geraden" gilt
## ein Punkt, dessen Abstand zur Geraden unter LINETOL liegt. Vector2
## rechnet in float32; dieser Toleranzwert ist noetig und ausreichend
## (gegen die d3-Referenz geprueft).
func visible_common_edge_length(a: int, b: int) -> float:
	if a == b:
		return 0.0
	var key := a * points.size() + b if a < b else b * points.size() + a
	if _edge_lengths.has(key):
		return _edge_lengths[key]
	var value := _measure_common_edge_length(a, b)
	_edge_lengths[key] = value
	return value


func visible_neighbors_of(index: int) -> PackedInt32Array:
	if index < 0 or index >= visible_neighbors.size():
		return PackedInt32Array()
	return visible_neighbors[index]


func _build_cells() -> void:
	cells = []
	areas = PackedFloat32Array()
	areas.resize(real_count)
	for i in range(real_count):
		if _delaunay.neighbors(i).is_empty():
			# Deckungsgleicher Punkt (doppelte Dummy-Ecken der gespiegelten
			# Erzeugung): d3-delaunay liefert dafuer keine Zelle.
			cells.append(PackedVector2Array())
			areas[i] = 0.0
			continue
		var poly := _fan_polygon(i)
		if poly.size() < 3 or not BoardGeometry.is_convex(poly):
			# Randzelle oder entartete Umkreiskonstruktion: exakt schneiden
			poly = _halfplane_polygon(i)
		poly = BoardGeometry.simplify_polygon(poly)
		cells.append(poly)
		areas[i] = BoardGeometry.polygon_area(poly)


## Zellpolygon eines inneren Punktes: die Umkreismittelpunkte der
## Dreiecke rund um den Punkt, in Rotationsreihenfolge. Das ist dieselbe
## Konstruktion, die d3-delaunay verwendet, und braucht kein Clipping
## gegen die Nachbar-Halbebenen.
func _fan_polygon(index: int) -> PackedVector2Array:
	var fan := _delaunay.triangles_around(index)
	var out := PackedVector2Array()
	out.resize(fan.size())
	for k in range(fan.size()):
		var base := fan[k] * 3
		out[k] = BoardGeometry.circumcenter(
			points[_delaunay.triangles[base]],
			points[_delaunay.triangles[base + 1]],
			points[_delaunay.triangles[base + 2]])
	return _clip_to_rect_if_needed(out)


## Zellpolygon eines Randpunktes: Schnitt des Rechtecks mit den
## Mittelsenkrechten zu allen Delaunay-Nachbarn (unbeschraenkte Zelle).
func _halfplane_polygon(index: int) -> PackedVector2Array:
	var poly := PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])
	for j in _delaunay.neighbors(index):
		var diff := points[j] - points[index]
		if diff.length_squared() < 1e-12:
			# Doppelter Punkt: deterministische Trennung statt Division durch 0
			poly = BoardGeometry.clip_half_plane(poly, Vector2(-1.0, 0.0), -points[index].x)
		else:
			var mid := (points[index] + points[j]) * 0.5
			poly = BoardGeometry.clip_half_plane(poly, diff, diff.dot(mid))
		if poly.size() < 3:
			break
	return poly


## Nur beschneiden, wenn das Polygon das Brett verlaesst.
func _clip_to_rect_if_needed(poly: PackedVector2Array) -> PackedVector2Array:
	var max_x := rect.position.x
	var max_y := rect.position.y
	var min_x := rect.end.x
	var min_y := rect.end.y
	for p in poly:
		if p.x < min_x:
			min_x = p.x
		if p.x > max_x:
			max_x = p.x
		if p.y < min_y:
			min_y = p.y
		if p.y > max_y:
			max_y = p.y
	if min_x >= rect.position.x and min_y >= rect.position.y and max_x <= rect.end.x and max_y <= rect.end.y:
		return poly
	return BoardGeometry.clip_polygon_to_rect(poly, rect)


func _measure_common_edge_length(a: int, b: int) -> float:
	var poly_a := cell_polygon(a)
	if poly_a.size() < 3:
		return 0.0
	if b < 0 or b >= real_count:
		return 0.0
	var diff := points[b] - points[a]
	var len := diff.length()
	if len < MIN_EDGE_EPSILON:
		return 0.0
	var mid := (points[a] + points[b]) * 0.5
	var normal := diff / len
	var total := 0.0
	var count := poly_a.size()
	for i in range(count):
		var p1 := poly_a[i]
		var p2 := poly_a[(i + 1) % count]
		if absf(normal.dot(p1 - mid)) <= LINETOL and absf(normal.dot(p2 - mid)) <= LINETOL:
			total += p1.distance_to(p2)
	return 2.0 * total


func _build_visible_neighbors(min_edge: float) -> void:
	visible_neighbors = []
	for i in range(real_count):
		var out := PackedInt32Array()
		for j in _delaunay.neighbors(i):
			if j >= real_count:
				continue
			if visible_common_edge_length(i, j) >= min_edge:
				out.append(j)
		visible_neighbors.append(out)
