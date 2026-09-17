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
var _edge_neighbors := {}
var _circumcenters := PackedVector2Array()


static func build(delaunay: Delaunay, bounds: Rect2, min_edge := 5.0, real_count := -1, with_visible_neighbors := true, previous: Voronoi = null, changed_indices := PackedInt32Array()) -> Voronoi:
	var v := Voronoi.new()
	v._delaunay = delaunay
	v.points = delaunay.points
	v.rect = bounds
	v.real_count = real_count if real_count >= 0 else delaunay.points.size()
	if previous != null and (previous.real_count != v.real_count \
		or previous.points.size() != v.points.size()):
		previous = null
	if previous != null and previous.real_count == v.real_count \
		and previous.points == v.points and changed_indices.is_empty():
		return previous
	var affected := v._affected_indices(previous, changed_indices)
	v._build_cells(previous, affected)
	if previous != null:
		# Kanten-Nachbarschaften weit entfernter Zellen bleiben gueltig und
		# werden uebernommen; nur bewegte Zellen berechnen sie neu.
		v._edge_neighbors = previous._edge_neighbors.duplicate()
		for index in affected:
			v._edge_neighbors.erase(index)
	if with_visible_neighbors:
		v._build_visible_neighbors(min_edge, previous, affected)
	else:
		v.visible_neighbors = []
		for i in range(v.real_count):
			v.visible_neighbors.append(PackedInt32Array())
	return v


## Voronoi inklusive Dummy-Punkten (entspricht updateDelaunayAndVoronoi()).
static func from_board(board: BoardState, bounds: Rect2, min_edge := 5.0, with_visible_neighbors := true, previous: Voronoi = null, changed_indices := PackedInt32Array()) -> Voronoi:
	return build(Delaunay.build(board.all_points()), bounds, min_edge, board.points.size(), with_visible_neighbors, previous, changed_indices)


## Voronoi nur aus den echten Punkten (entspricht d3.Delaunay.from(points)).
## Die sichtbaren Nachbarn werden hier nicht gebraucht.
static func from_points(pts: PackedVector2Array, bounds: Rect2, previous: Voronoi = null, changed_indices := PackedInt32Array()) -> Voronoi:
	return build(Delaunay.build(pts), bounds, 5.0, pts.size(), false, previous, changed_indices)


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


## Fuer jede Kante der Zelle die Zelle jenseits der Kante, oder -1 am
## Brettrand bzw. zu einem Dummy-Punkt. Eine Kante gehoert genau dann zu
## einem Nachbarn, wenn beide Endpunkte auf der Mittelsenkrechten liegen
## (gleiche Toleranz wie bei der Kantenmessung). Nur der Mittelpunkt zu
## pruefen wuerde bei kokreisförmigen Punkten auch Nachbarn treffen, die die
## Zelle nur in einer Ecke beruehren. Wird pro Zelle einmal berechnet.
func edge_neighbors(index: int) -> PackedInt32Array:
	if _edge_neighbors.has(index):
		var cached: PackedInt32Array = _edge_neighbors[index]
		return cached
	if index < 0 or index >= real_count:
		return PackedInt32Array()
	var poly := cell_polygon(index)
	var out := PackedInt32Array()
	out.resize(poly.size())
	for k in range(poly.size()):
		var p1 := poly[k]
		var p2 := poly[(k + 1) % poly.size()]
		var best := -1
		var best_distance := INF
		for j in _delaunay.neighbors(index):
			if j >= real_count:
				continue
			var diff := points[j] - points[index]
			if diff.length_squared() < 1e-12:
				continue
			var normal := diff / diff.length()
			var mid := (points[index] + points[j]) * 0.5
			var distance := maxf(absf(normal.dot(p1 - mid)), absf(normal.dot(p2 - mid)))
			if distance <= LINETOL and distance < best_distance:
				best_distance = distance
				best = j
		out[k] = best
	_edge_neighbors[index] = out
	return out


func _build_cells(previous: Voronoi = null, affected := {}) -> void:
	if previous != null and previous.cells.size() == real_count:
		cells = previous.cells.duplicate()
		areas = previous.areas.duplicate()
	else:
		cells = []
		areas = PackedFloat32Array()
		areas.resize(real_count)
	_circumcenters.resize(_delaunay.triangles.size() / 3)
	var required_triangles := {}
	if previous != null:
		for index in affected:
			for triangle in _delaunay.triangles_around(index):
				required_triangles[triangle] = true
	for triangle_index in range(_circumcenters.size()):
		if previous != null and not required_triangles.has(triangle_index):
			continue
		var base := triangle_index * 3
		_circumcenters[triangle_index] = BoardGeometry.circumcenter(
			points[_delaunay.triangles[base]],
			points[_delaunay.triangles[base + 1]],
			points[_delaunay.triangles[base + 2]])
	for i in range(real_count):
		if previous != null and not affected.has(i):
			continue
		if _delaunay.neighbors(i).is_empty():
			# Deckungsgleicher Punkt (doppelte Dummy-Ecken der gespiegelten
			# Erzeugung): d3-delaunay liefert dafuer keine Zelle.
			if previous == null:
				cells.append(PackedVector2Array())
			else:
				cells[i] = PackedVector2Array()
			areas[i] = 0.0
			continue
		var poly := _fan_polygon(i)
		if poly.size() < 3 or not BoardGeometry.is_convex(poly):
			# Randzelle oder entartete Umkreiskonstruktion: exakt schneiden
			poly = _halfplane_polygon(i)
		poly = BoardGeometry.simplify_polygon(poly)
		if previous == null:
			cells.append(poly)
		else:
			cells[i] = poly
		areas[i] = BoardGeometry.polygon_area(poly)


## Nur die bewegten Zellen und ihre direkten Delaunay-Nachbarn muessen neu
## geschnitten werden. Das genuegt, weil sich die Zellform einer Zelle nur aus
## den Umkreismittelpunkten der Dreiecke ergibt, die sie mit ihren Nachbarn
## bildet: bewegt sich ein Punkt, aendern sich nur die Faecheradien dieser
## lokalen Dreiecke. Beide Triangulationen (alt und neu) werden betrachtet,
## damit auch Zellen aktualisiert werden, deren Nachbarschaft gerade wechselt.
func _affected_indices(previous: Voronoi, changed_indices: PackedInt32Array) -> Dictionary:
	var affected := {}
	for index in changed_indices:
		if index < 0 or index >= real_count:
			continue
		affected[index] = true
		for neighbor in _delaunay.neighbors(index):
			affected[neighbor] = true
		if previous == null:
			continue
		for neighbor in previous.delaunay().neighbors(index):
			affected[neighbor] = true
	if previous == null or changed_indices.is_empty() \
		or changed_indices.size() * 4 > real_count:
		# Kein Vorgaenger oder sehr viele bewegte Punkte: die lokale Annahme
		# waere unsicher, deshalb wird einmal vollstaendig gerechnet.
		affected.clear()
		for index in range(real_count):
			affected[index] = true
	return affected


## Zellpolygon eines inneren Punktes: die Umkreismittelpunkte der
## Dreiecke rund um den Punkt, in Rotationsreihenfolge. Das ist dieselbe
## Konstruktion, die d3-delaunay verwendet, und braucht kein Clipping
## gegen die Nachbar-Halbebenen.
func _fan_polygon(index: int) -> PackedVector2Array:
	var fan := _delaunay.triangles_around(index)
	var out := PackedVector2Array()
	out.resize(fan.size())
	for k in range(fan.size()):
		out[k] = _circumcenters[fan[k]]
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


func _build_visible_neighbors(min_edge: float, previous: Voronoi = null, affected := {}) -> void:
	if previous != null and previous.visible_neighbors.size() == real_count:
		visible_neighbors = previous.visible_neighbors.duplicate()
	else:
		visible_neighbors = []
		for i in range(real_count):
			visible_neighbors.append(PackedInt32Array())
		for i in range(real_count):
			affected[i] = true
	for i in affected:
		if i < 0 or i >= real_count:
			continue
		var out := PackedInt32Array()
		for j in _delaunay.neighbors(i):
			if j >= real_count:
				continue
			if visible_common_edge_length(i, j) >= min_edge:
				out.append(j)
		visible_neighbors[i] = out
