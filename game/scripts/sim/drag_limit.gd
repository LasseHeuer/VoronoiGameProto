class_name DragLimit
extends RefCounted

## Territorium, in dem Zellen der aktiven Farbe stehen duerfen.
##
## Grundflaeche ist die komplette eigene Farbflaeche. Aussen wird sie um das
## Gebiet erweitert, in dem die Farbe noch keine Zelle verliert - also der
## Bereich, in den man gefahrlos hineinziehen kann. Das Ergebnis ist eine
## geschlossene Kontur (eine Flaeche, keine Ringe je Zelle).
##
## Die Kontur gehoert zur Farbe, nicht zur gedrueckten Zelle: die Grundflaeche
## ist die groesste zusammenhaengende Flaeche der Farbe, und gemessen wird mit
## der eigenen Zelle, auf deren Rand der jeweilige Punkt der eigenen Flaeche
## liegt. Damit ist die Anzeige fuer alle Zellen der Farbe dieselbe,
## unabhaengig davon, welche Zelle gedrueckt wurde.
##
## Berechnet wird die Kontur einmal, sobald die Geometrie vorliegt (erster
## update-Aufruf nach begin). Danach passiert nichts mehr: waehrend des
## Ziehens steht die Flaeche fest.
##
## Gemessen wird lokal genaehert: fuer eine Probeposition werden alle Zellen in
## ihrem Umkreis (LOCAL_RADIUS) neu aufgebaut - mit den verschobenen Punkten,
## also auch mit den Nachbarschaften, die durch die Bewegung entstehen. Zellen
## weiter aussen behalten ihre Werte aus dem Aufbau. Ein kompletter
## Voronoi-Aufbau je Probe kostet rund 4 ms und waere fuer eine sofortige
## Berechnung zu teuer.

## Wachstumsschritt beim Suchen der Grenze.
const STEP := 6.0
## Aufloesung der Grenze.
const MIN_STEP := 8.0
## Hoechstzahl der Proben je Messpunkt.
const MAX_PROBES := 5
## Startwert der Suche beim ersten Messpunkt.
const FIRST_GROWTH := 32.0
## Weiteste Erweiterung ueber die eigene Flaeche hinaus.
const MAX_GROWTH := 100.0
## Abstand, in dem eigene Randkanten abgetastet werden.
const EDGE_SAMPLE_STEP := 24.0
## So viele Konturpunkte liegen zwischen zwei Messungen. Die Zwischenwerte
## werden linear aus den Nachbarn ergaenzt: das Wachstum aendert sich entlang
## der Kontur nur langsam, und die Rechnung wird dadurch deutlich kuerzer.
const MEASURE_STRIDE := 3
## Schwelle fuer sichtbare Nachbarn, wie im Voronoi.
const VISIBLE_MIN_EDGE := 5.0
const VISIBLE_LINE_TOLERANCE := 0.01
## Umkreis um die Probeposition, in dem die Zellen neu gerechnet werden. Muss
## groesser sein als MAX_GROWTH: die Zelle an der Probeposition wird von allen
## Punkten in diesem Umkreis begrenzt; fehlende Punkte wuerden ihre Flaeche zu
## gross machen.
const LOCAL_RADIUS := 170.0
## Sicherheitsabstand, der von jedem Messwert abgezogen wird. Die lokale
## Naeherung kann die Grenze um wenige Pixel ueberschrezen; die angezeigte
## Flaeche bleibt dadurch innerhalb des erlaubten Bereichs.
const SAFETY_MARGIN := 8.0
## Band vor der Grenze, in dem die Bewegung weich abgebremst wird (Brettpixel).
const SOFT_BAND := 45.0
## Das Band ist hoechstens so ein grosser Anteil der erlaubten Entfernung.
const SOFT_BAND_RATIO := 0.6
## Winkelbereich (rad), ueber den die erlaubte Entfernung geglaettet wird.
const DIRECTION_WINDOW := 0.12
## Stuetzstellen dieses Winkelbereichs.
const DIRECTION_SAMPLES := 5
## Zusaetzlicher Abstand vor der Grenze, den die Bremse einhaelt. Die lokale
## Naeherung kann die Grenze um wenige Pixel ueberschaetzen; der Abstand haelt
## die Bewegung innerhalb der Kontur.
const STOP_MARGIN := 12.0
## Anzahl der Richtungsbereiche der gemerkten Wand.
const WALL_SECTORS := 72

var board: BoardState

var _points := PackedVector2Array()
var _ids := PackedByteArray()
var _rect := Rect2()
var _delaunay: Delaunay
## Zellindizes der eigenen Farbe in Nachbarschaftsreihenfolge.
var _own_indices := PackedInt32Array()
## Eckpunkte der eigenen Flaeche.
var _own_outline := PackedVector2Array()
## Wachstum je Ecke und die daraus gebaute Kontur.
var _growth := PackedFloat32Array()
var _outline := PackedVector2Array()
var _normals := PackedVector2Array()
## Flaechen und sichtbare Nachbarn des Aufbaus; je Probe wird die Liste
## kopiert und nur die betroffenen Zellen ersetzt.
var _base_areas := PackedFloat32Array()
var _base_neighbors: Array = []
## Gemerkte Grenzen je Richtungsbereich (siehe note_blocked).
var _wall := {}
var _index := -1
var _color := ""
var _iterations := 0
var _active := false
var _ready := false


func setup(p_board: BoardState) -> void:
	board = p_board


func is_active() -> bool:
	return _active


## Wahre, wenn die Kontur berechnet ist.
func is_ready() -> bool:
	return _active and _ready


## Zelle, mit der der Drag begonnen wurde (nur fuer Anzeige und Tests).
func index() -> int:
	return _index


## Startet ein neues Territorium fuer die Farbe der gedrueckten Zelle.
func begin(cell_index: int) -> void:
	_active = cell_index >= 0
	_ready = false
	_index = cell_index
	_color = board.cell_color(cell_index) if _active else ""
	_own_indices = PackedInt32Array()
	_own_outline = PackedVector2Array()
	_growth = PackedFloat32Array()
	_outline = PackedVector2Array()
	_normals = PackedVector2Array()
	_wall.clear()


func clear() -> void:
	_active = false
	_ready = false
	_index = -1
	_own_indices = PackedInt32Array()
	_own_outline = PackedVector2Array()
	_growth = PackedFloat32Array()
	_outline = PackedVector2Array()
	_normals = PackedVector2Array()
	_wall.clear()


## Eckpunkte der Kontur in Brettkoordinaten.
func outline() -> PackedVector2Array:
	return _outline


## Gemessene Erweiterung je Ecke (0 = Ecke der eigenen Flaeche).
func growth() -> PackedFloat32Array:
	return _growth


## Entfernung, die die gezogene Zelle in Richtung des Zeigers einnimmt.
##
## Innerhalb der Kontur folgt sie dem Zeiger genau; vor der Grenze wird sie
## zunehmend abgebremst und naehert sich der Kontur nur noch an (unsichtbare
## Wand). Der Wert ist stetig und monoton, springt also nicht. Ohne Kontur
## (noch nicht berechnet oder Startpunkt ausserhalb) bleibt der Abstand wie er
## ist.
func braked_distance(origin: Vector2, cursor: Vector2) -> float:
	var offset := cursor - origin
	var distance := offset.length()
	if distance <= 0.001 or not _ready or _outline.size() < 3:
		return distance
	if not BoardGeometry.point_in_polygon(origin, _outline):
		return distance
	var direction := offset / distance
	var allowed := _allowed_distance(origin, direction)
	var wall := _wall_distance(direction)
	if wall >= 0.0 and (allowed <= 0.0 or wall < allowed):
		allowed = wall
	if allowed <= 0.0:
		return distance
	# Etwas vor der Grenze stehen bleiben: die Messung ist eine Naeherung.
	var usable := maxf(allowed - STOP_MARGIN, allowed * 0.35)
	return soft_wall(distance, usable, minf(SOFT_BAND, usable * SOFT_BAND_RATIO))


## Merkt sich, dass die Bewegung in dieser Richtung blockiert wurde: die Bremse
## stoppt dort kuenftig frueher. Dadurch wiederholt sich ein Blockieren in
## derselben Richtung nicht.
func note_blocked(origin: Vector2, blocked: Vector2) -> void:
	var offset := blocked - origin
	if offset.length() <= 0.001:
		return
	var sector := _sector_of(offset.angle())
	var distance := maxf(offset.length() - MIN_STEP, 0.0)
	if not _wall.has(sector) or distance < float(_wall[sector]):
		_wall[sector] = distance


## Gemerkte Grenze in dieser Richtung; -1, wenn keine bekannt ist.
func _wall_distance(direction: Vector2) -> float:
	var sector := _sector_of(direction.angle())
	var best := -1.0
	for offset in [-1, 0, 1]:
		var index := posmod(sector + offset, WALL_SECTORS)
		if not _wall.has(index):
			continue
		var value := float(_wall[index])
		if best < 0.0 or value < best:
			best = value
	return best


func _sector_of(angle: float) -> int:
	return int(floor(fposmod(angle, TAU) / TAU * float(WALL_SECTORS))) % WALL_SECTORS


## Weiche Wand: bis zum Beginn des Bands folgt der Wert genau, danach naehert
## er sich der Grenze an, ohne sie zu erreichen. Anschluss und Steigung sind
## stetig, damit die Bewegung nicht springt.
static func soft_wall(distance: float, limit: float, band: float) -> float:
	if limit <= 0.0:
		return distance
	if distance <= limit - band:
		return distance
	var span := clampf(band, 0.0, limit)
	if span <= 0.0:
		return minf(distance, limit)
	var start := limit - span
	return limit - span * exp(-(distance - start) / span)


## Erlaubte Entfernung vom Startpunkt in dieser Richtung: dort verlaesst der
## Strahl die Kontur. Ueber einen kleinen Winkelbereich wird der kleinste Wert
## genommen, damit einspringende Ecken die Bewegung nicht springen lassen.
func _allowed_distance(origin: Vector2, direction: Vector2) -> float:
	var allowed := -1.0
	var last := float(maxi(DIRECTION_SAMPLES - 1, 1))
	for i in range(maxi(DIRECTION_SAMPLES, 1)):
		var angle := DIRECTION_WINDOW * (float(i) / last - 0.5)
		var value := _ray_exit_distance(origin, direction.rotated(angle))
		if value < 0.0:
			continue
		if allowed < 0.0 or value < allowed:
			allowed = value
	return allowed


## Entfernung bis zum Verlassen der Kontur entlang `direction`; -1, wenn der
## Strahl die Kontur nicht trifft.
func _ray_exit_distance(origin: Vector2, direction: Vector2) -> float:
	var best := -1.0
	var count := _outline.size()
	for i in range(count):
		var a := _outline[i]
		var edge := _outline[(i + 1) % count] - a
		var denom := direction.cross(edge)
		if absf(denom) < 1e-9:
			continue
		var diff := a - origin
		var t := diff.cross(edge) / denom
		var u := diff.cross(direction) / denom
		if t < 0.0 or u < -1e-6 or u > 1.0 + 1e-6:
			continue
		if best < 0.0 or t < best:
			best = t
	return best


## Baut die Kontur beim ersten Aufruf vollstaendig auf. Weitere Aufrufe
## waehrend desselben Drags aendern nichts mehr.
func update(voronoi: Voronoi, iterations: int) -> void:
	if not _active or _ready or voronoi == null or _index < 0:
		return
	_iterations = iterations
	_delaunay = voronoi.delaunay()
	_points = voronoi.points
	_rect = voronoi.rect
	_ids = board.color_ids()
	if _index >= voronoi.real_count:
		_active = false
		return
	_build_own_area(voronoi)
	if _growth.size() < 3:
		_ready = true
		return
	_refresh_base(voronoi)
	_measure_all()
	_ready = true


## Flaechen und Nachbarn aus dem Voronoi holen (einmal je Kontur).
func _refresh_base(voronoi: Voronoi) -> void:
	_base_areas.resize(voronoi.real_count)
	_base_neighbors.resize(voronoi.real_count)
	for i in range(voronoi.real_count):
		_base_areas[i] = voronoi.area(i)
		_base_neighbors[i] = voronoi.visible_neighbors_of(i)


## Eigene Flaechen als eine Kontur: alle Zellpolygone der eigenen Farbe
## werden verschmolzen und die groesste Teilflaeche genommen.
func _build_own_area(voronoi: Voronoi) -> void:
	_own_indices = _adjacent_own_cells(voronoi)
	_own_outline = PackedVector2Array()
	if _own_indices.is_empty():
		_growth = PackedFloat32Array()
		_outline = PackedVector2Array()
		return
	# Zelle fuer Zelle in Nachbarschaftsreihenfolge verschmelzen: so muss nie
	# eine ganze Polygonschar gleichzeitig vereinigt werden.
	var merged := PackedVector2Array()
	for index in _own_indices:
		var poly := voronoi.cell_polygon(index)
		if poly.size() < 3:
			continue
		if merged.size() < 3:
			merged = poly
			continue
		merged = BoardGeometry.largest_polygon(Geometry2D.merge_polygons(merged, poly))
	_own_outline = merged
	if _own_outline.size() < 3:
		_own_outline = voronoi.cell_polygon(_own_indices[0])
	_own_outline = _resample(BoardGeometry.simplify_polygon(_own_outline))
	_normals = _outward_normals(_own_outline)
	_growth = PackedFloat32Array()
	_growth.resize(_own_outline.size())
	_build_outline()


## Eigene Zellen in Nachbarschaftsreihenfolge, beginnend bei der groessten.
## So beruehrt jede naechste Zelle die bisherige Flaeche. Inseln der eigenen
## Farbe bleiben aussen vor.
func _adjacent_own_cells(voronoi: Voronoi) -> PackedInt32Array:
	var largest := -1
	var largest_area := -1.0
	for i in range(mini(voronoi.real_count, board.cell_colors.size())):
		if board.cell_color(i) != _color:
			continue
		if voronoi.area(i) > largest_area:
			largest_area = voronoi.area(i)
			largest = i
	var order := PackedInt32Array()
	if largest < 0:
		return order
	var seen := {largest: true}
	order.append(largest)
	var queue := PackedInt32Array([largest])
	while queue.size() > 0:
		var current := queue[0]
		queue.remove_at(0)
		for nb in _delaunay.neighbors(current):
			if nb >= voronoi.real_count or seen.has(nb):
				continue
			if board.cell_color(nb) != _color:
				continue
			seen[nb] = true
			order.append(nb)
			queue.append(nb)
	return order


## Teilt lange Kanten auf, damit die Grenze ueberall gemessen wird (nicht nur
## an den Ecken der eigenen Flaeche).
func _resample(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count := poly.size()
	for i in range(count):
		var a := poly[i]
		var b := poly[(i + 1) % count]
		out.append(a)
		var parts := int(floor(a.distance_to(b) / EDGE_SAMPLE_STEP))
		for k in range(1, parts):
			out.append(a.lerp(b, float(k) / float(parts)))
	return out


## Aussenrichtung je Ecke: Senkrechte zur Verbindung der Nachbarecken, jeweils
## vom Flaechenmittelpunkt weg.
func _outward_normals(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count := poly.size()
	if count == 0:
		return out
	var center := Vector2.ZERO
	for p in poly:
		center += p
	center /= float(count)
	out.resize(count)
	for i in range(count):
		var prev := poly[(i - 1 + count) % count]
		var next := poly[(i + 1) % count]
		var direction := next - prev
		var normal := Vector2(direction.y, -direction.x)
		if normal.length_squared() < 1e-9:
			normal = poly[i] - center
		normal = normal.normalized()
		if normal.dot(poly[i] - center) < 0.0:
			normal = -normal
		out[i] = normal
	return out


## Misst das Wachstum an jedem Messpunkt der Kontur; die Punkte dazwischen
## bekommen den linear interpolierten Wert und werden danach abgesichert.
func _measure_all() -> void:
	var count := _growth.size()
	var indices := PackedInt32Array()
	var i := 0
	while i < count:
		indices.append(i)
		i += MEASURE_STRIDE
	var guess := FIRST_GROWTH
	for vertex in indices:
		_growth[vertex] = maxf(_measure_growth(vertex, guess) - SAFETY_MARGIN, 0.0)
		guess = _growth[vertex]
	var measured := indices.size()
	for k in range(measured):
		var a: int = indices[k]
		var b: int = indices[(k + 1) % measured]
		var span := (b - a + count) % count
		if span <= 1:
			continue
		for step in range(1, span):
			var t := float(step) / float(span)
			_growth[(a + step) % count] = lerpf(_growth[a], _growth[b], t)
	# Zwischen den Messpunkten kann der interpolierte Wert zu weit aussen
	# liegen; solche Stellen werden auf die sichere Entfernung zurueckgenommen.
	for vertex in range(count):
		if vertex % MEASURE_STRIDE == 0:
			continue
		_confirm_growth(vertex)
	_build_outline()


## Verkleinert einen interpolierten Wert, bis die Position sicher ist.
func _confirm_growth(vertex: int) -> void:
	var value := _growth[vertex]
	if value <= 0.0:
		return
	var from := _own_outline[vertex]
	var normal := _normals[vertex]
	var mover := _nearest_own_cell(from)
	if _safe(from, normal, value, mover):
		return
	var good := 0.0
	var bad := value
	var probes := 1
	while bad - good > MIN_STEP and probes < MAX_PROBES:
		var mid := (good + bad) * 0.5
		probes += 1
		if _safe(from, normal, mid, mover):
			good = mid
		else:
			bad = mid
	_growth[vertex] = good


## Groesste Entfernung vom Rand, in der die naechstgelegene eigene Zelle noch
## stehen darf. Bewegt wird immer die eigene Zelle, auf deren Rand der Punkt
## liegt: bei einem Punkt auf der eigenen Grenze ist das die naechste Zelle.
## Die Suche startet beim Wert des vorigen Messpunkts: die Grenze aendert sich
## nur langsam, dadurch genuegen wenige Proben. Nach MAX_PROBES wird
## abgebrochen; das Ergebnis ist dann etwas kleiner als erlaubt.
func _measure_growth(vertex: int, guess: float) -> float:
	var from := _own_outline[vertex]
	var normal := _normals[vertex]
	var mover := _nearest_own_cell(from)
	var good := 0.0
	var bad := MAX_GROWTH
	var probes := 0
	var probe := clampf(guess, STEP, MAX_GROWTH)
	if _safe(from, normal, probe, mover):
		probes += 1
		good = probe
		while good < MAX_GROWTH and probes < MAX_PROBES:
			probe = minf(good * 1.5 + STEP, MAX_GROWTH)
			probes += 1
			if not _safe(from, normal, probe, mover):
				bad = probe
				break
			good = probe
		if good >= MAX_GROWTH:
			return MAX_GROWTH
	else:
		probes += 1
		bad = probe
		while bad > MIN_STEP and probes < MAX_PROBES:
			probe = maxf(bad * 0.5, MIN_STEP)
			probes += 1
			if _safe(from, normal, probe, mover):
				good = probe
				break
			if probe <= MIN_STEP:
				return 0.0
			bad = probe
	while bad - good > MIN_STEP and probes < MAX_PROBES:
		var mid := (good + bad) * 0.5
		probes += 1
		if _safe(from, normal, mid, mover):
			good = mid
		else:
			bad = mid
	return good


func _safe(from: Vector2, normal: Vector2, distance: float, mover: int) -> bool:
	return _safe_at(from + normal * distance, mover)


## Verliert die eigene Farbe an dieser Stelle eine Zelle? Bewegt wird die
## uebergebene eigene Zelle - die Anzeige gilt damit fuer alle Zellen der
## Farbe. Eigene Nachbarzellen der bewegten Zelle zaehlen nicht mit, genau wie
## beim Verlust-Schutz.
func _safe_at(candidate: Vector2, moved: int) -> bool:
	var color_id := BoardState.color_id(_color)
	if color_id == 0 or moved < 0:
		return false
	var ignored := _own_neighbors_of(moved)
	var after := Territories.propagate_ids(_geometry_at(moved, candidate), _ids.duplicate(), _iterations)
	for i in range(mini(_ids.size(), after.size())):
		if _ids[i] != color_id or after[i] == color_id:
			continue
		if ignored.has(i):
			continue
		return false
	return true


## Eigene Zelle, deren Mittelpunkt der Position am naechsten liegt.
func _nearest_own_cell(candidate: Vector2) -> int:
	var best := -1
	var best_distance := INF
	for i in _own_indices:
		if i >= _points.size():
			continue
		var d := _points[i].distance_squared_to(candidate)
		if d < best_distance:
			best_distance = d
			best = i
	return best


## Eigene, sichtbare Nachbarn einer Zelle.
func _own_neighbors_of(cell: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if cell < 0 or cell >= _base_neighbors.size():
		return out
	for nb in _base_neighbors[cell]:
		if nb < board.cell_colors.size() and board.cell_color(nb) == _color:
			out.append(nb)
	return out


func _build_outline() -> void:
	_outline = PackedVector2Array()
	if _growth.size() != _own_outline.size():
		return
	_outline.resize(_own_outline.size())
	for i in range(_own_outline.size()):
		_outline[i] = _own_outline[i] + _normals[i] * _growth[i]


## Geometrie der Probeposition: alle Zellen im Umkreis der Position werden aus
## den Punkten neu aufgebaut (inklusive neuer Nachbarschaften, die durch die
## Bewegung entstehen), alle weiter entfernten bleiben wie im letzten Aufbau.
func _geometry_at(moved: int, candidate: Vector2) -> CellGeometry:
	var geometry := CellGeometry.new()
	geometry.areas = _base_areas.duplicate()
	geometry.neighbors = _base_neighbors.duplicate()
	var local := _local_cells(moved, candidate)
	if local.size() < 3:
		return geometry
	var local_index := {}
	var local_points := PackedVector2Array()
	for i in local:
		local_index[i] = local_points.size()
		local_points.append(candidate if i == moved else _points[i])
	var local_delaunay := Delaunay.build(local_points)
	# Nur die bewegte Zelle und ihre Nachbarn aendern ihre Flaeche: die
	# Voronoi-Flaeche aller anderen Zellen bleibt gleich.
	for i in _patched_cells(moved, local, local_index, local_delaunay):
		var candidates := _candidate_neighbors(i, local, local_index, local_delaunay)
		var poly := _local_polygon(i, candidate, moved, candidates)
		geometry.areas[i] = BoardGeometry.polygon_area(poly)
		geometry.neighbors[i] = _visible_neighbors(poly, i, candidate, moved, candidates)
	return geometry


## Zellen, deren Flaeche sich durch die Bewegung aendert: die bewegte Zelle
## und ihre Nachbarn, vorher und an der Probeposition.
func _patched_cells(moved: int, local: PackedInt32Array, local_index: Dictionary, local_delaunay: Delaunay) -> PackedInt32Array:
	var out := PackedInt32Array()
	var seen := {}
	for nb in _delaunay.neighbors(moved):
		if nb >= 0 and nb < _base_areas.size() and not seen.has(nb):
			seen[nb] = true
			out.append(nb)
	var offset: int = local_index[moved]
	for index in local_delaunay.neighbors(offset):
		if index < 0 or index >= local.size():
			continue
		var nb: int = local[index]
		if nb != moved and not seen.has(nb):
			seen[nb] = true
			out.append(nb)
	if not seen.has(moved) and moved >= 0 and moved < _base_areas.size():
		out.append(moved)
	return out


## Zellen, die fuer die Probeposition neu gerechnet werden: alle Punkte im
## Umkreis der Position sowie die bewegte Zelle und ihre bisherigen Nachbarn.
func _local_cells(moved: int, candidate: Vector2) -> PackedInt32Array:
	var out := PackedInt32Array()
	var seen := {}
	for i in range(_base_areas.size()):
		if _points[i].distance_to(candidate) <= LOCAL_RADIUS:
			seen[i] = true
			out.append(i)
	if moved >= 0 and moved < _base_areas.size() and not seen.has(moved):
		seen[moved] = true
		out.append(moved)
	for nb in _delaunay.neighbors(moved):
		if nb >= 0 and nb < _base_areas.size() and not seen.has(nb):
			seen[nb] = true
			out.append(nb)
	return out


## Nachbarzellen einer lokalen Zelle: die bisherigen Nachbarn und die Nachbarn
## aus der lokalen Triangulation.
func _candidate_neighbors(index: int, local: PackedInt32Array, local_index: Dictionary, local_delaunay: Delaunay) -> PackedInt32Array:
	var out := PackedInt32Array()
	var seen := {}
	for nb in _delaunay.neighbors(index):
		if nb >= 0 and nb < _base_areas.size() and not seen.has(nb):
			seen[nb] = true
			out.append(nb)
	var local_position: int = local_index[index]
	for offset in local_delaunay.neighbors(local_position):
		if offset < 0 or offset >= local.size():
			continue
		var nb: int = local[offset]
		if nb != index and not seen.has(nb):
			seen[nb] = true
			out.append(nb)
	return out


## Zellpolygon von `index`, wenn die bewegte Zelle an `candidate` steht:
## Schnitt des Bretts mit den Mittelsenkrechten zu allen Nachbarn (wie
## _halfplane_polygon im Voronoi).
func _local_polygon(index: int, candidate: Vector2, moved: int, candidates: PackedInt32Array) -> PackedVector2Array:
	var own := _position(index, candidate, moved)
	var poly := PackedVector2Array([
		_rect.position,
		Vector2(_rect.end.x, _rect.position.y),
		_rect.end,
		Vector2(_rect.position.x, _rect.end.y),
	])
	for j in candidates:
		var other := _position(j, candidate, moved)
		var diff := other - own
		if diff.length_squared() < 1e-12:
			poly = BoardGeometry.clip_half_plane(poly, Vector2(-1.0, 0.0), -own.x)
		else:
			var mid := (own + other) * 0.5
			poly = BoardGeometry.clip_half_plane(poly, diff, diff.dot(mid))
		if poly.size() < 3:
			return PackedVector2Array()
	return poly


## Sichtbare Nachbarn der Zelle an der Probeposition (nur echte Zellen).
func _visible_neighbors(poly: PackedVector2Array, index: int, candidate: Vector2, moved: int, candidates: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	if poly.size() < 3:
		return out
	var own := _position(index, candidate, moved)
	for j in candidates:
		if j >= _base_areas.size():
			continue
		if _visible_edge_length(poly, own, _position(j, candidate, moved)) >= VISIBLE_MIN_EDGE:
			out.append(j)
	return out


func _position(index: int, candidate: Vector2, moved := -1) -> Vector2:
	return candidate if index == moved else _points[index]


## Laenge der gemeinsamen Kante zweier Zellen wie im Voronoi (doppelter
## Umfang des Schnitts), damit die Sichtbarkeitsschwelle dieselbe ist.
func _visible_edge_length(poly: PackedVector2Array, a: Vector2, b: Vector2) -> float:
	var diff := b - a
	var length := diff.length()
	if length < 1e-6:
		return 0.0
	var mid := (a + b) * 0.5
	var normal := diff / length
	var total := 0.0
	var count := poly.size()
	for i in range(count):
		var p1 := poly[i]
		var p2 := poly[(i + 1) % count]
		if absf(normal.dot(p1 - mid)) <= VISIBLE_LINE_TOLERANCE and absf(normal.dot(p2 - mid)) <= VISIBLE_LINE_TOLERANCE:
			total += p1.distance_to(p2)
	return 2.0 * total
