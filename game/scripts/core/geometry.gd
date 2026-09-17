class_name BoardGeometry
extends RefCounted

## Reine Geometrie-Helfer. Keine Szene-, Node- oder Engine-Abhaengigkeit.
## Alle Funktionen sind statisch und damit direkt testbar.
##
## Die Algorithmen entsprechen 1:1 den JS-Originalen aus src/core.js
## (Shoelace, Ray-Casting, Sutherland-Hodgman), damit die Ergebnisse
## deckungsgleich bleiben.

const EPS := 1e-9

## Abstand, unter dem zwei Polygonpunkte als derselbe Punkt gelten.
## Umkreismittelpunkte entarteter (kokreisfoermiger) Dreiecke liegen
## rechnerisch bis ca. 3e-4 px auseinander; echte Zellkanten sind
## mindestens im Bereich von Pixeln.
const MERGE_EPSILON := 5e-4
const MERGE_EPSILON_SQ := MERGE_EPSILON * MERGE_EPSILON

## Vorzeichenbehaftete Flaeche (Shoelace).
static func signed_polygon_area(poly: PackedVector2Array) -> float:
	var n := poly.size()
	if n < 3:
		return 0.0
	var acc := 0.0
	for i in range(n):
		var j := (i + 1) % n
		acc += poly[i].x * poly[j].y - poly[j].x * poly[i].y
	return acc * 0.5

## Flaeche wie polygonArea() in core.js (Betrag).
static func polygon_area(poly: PackedVector2Array) -> float:
	return absf(signed_polygon_area(poly))

## Mittelpunkt der Eckpunkte (genau wie computeCentroid() in core.js,
## also KEIN Flaechenschwerpunkt).
static func polygon_vertex_average(poly: PackedVector2Array) -> Vector2:
	if poly.is_empty():
		return Vector2.ZERO
	var acc := Vector2.ZERO
	for p in poly:
		acc += p
	return acc / float(poly.size())

## Ray-Casting wie pointInPolygon() in core.js.
static func point_in_polygon(pt: Vector2, poly: PackedVector2Array) -> bool:
	var inside := false
	var n := poly.size()
	if n < 3:
		return false
	var j := n - 1
	for i in range(n):
		var pi := poly[i]
		var pj := poly[j]
		if (pi.y > pt.y) != (pj.y > pt.y):
			var x_cross := (pj.x - pi.x) * (pt.y - pi.y) / (pj.y - pi.y) + pi.x
			if pt.x < x_cross:
				inside = not inside
		j = i
	return inside

## Schneidet ein Polygon an einem Rechteck (Sutherland-Hodgman).
## Kantenreihenfolge und Innen-Tests wie clipPolygonToRect() in core.js
## (links, rechts, oben, unten).
static func clip_polygon_to_rect(poly: PackedVector2Array, rect: Rect2) -> PackedVector2Array:
	var out := poly
	out = _clip_vertical(out, rect.position.x, true)
	out = _clip_vertical(out, rect.end.x, false)
	out = _clip_horizontal(out, rect.position.y, true)
	out = _clip_horizontal(out, rect.end.y, false)
	return out

static func _clip_vertical(poly: PackedVector2Array, limit: float, keep_greater: bool) -> PackedVector2Array:
	if poly.is_empty():
		return poly
	var out := PackedVector2Array()
	var n := poly.size()
	for i in range(n):
		var cur := poly[i]
		var prev := poly[(i - 1 + n) % n]
		var cur_in := cur.x >= limit if keep_greater else cur.x <= limit
		var prev_in := prev.x >= limit if keep_greater else prev.x <= limit
		if prev_in and cur_in:
			out.append(cur)
		elif prev_in and not cur_in:
			out.append(_intersect_vertical(prev, cur, limit))
		elif not prev_in and cur_in:
			out.append(_intersect_vertical(prev, cur, limit))
			out.append(cur)
	return out

static func _clip_horizontal(poly: PackedVector2Array, limit: float, keep_greater: bool) -> PackedVector2Array:
	if poly.is_empty():
		return poly
	var out := PackedVector2Array()
	var n := poly.size()
	for i in range(n):
		var cur := poly[i]
		var prev := poly[(i - 1 + n) % n]
		var cur_in := cur.y >= limit if keep_greater else cur.y <= limit
		var prev_in := prev.y >= limit if keep_greater else prev.y <= limit
		if prev_in and cur_in:
			out.append(cur)
		elif prev_in and not cur_in:
			out.append(_intersect_horizontal(prev, cur, limit))
		elif not prev_in and cur_in:
			out.append(_intersect_horizontal(prev, cur, limit))
			out.append(cur)
	return out

static func _intersect_vertical(a: Vector2, b: Vector2, x: float) -> Vector2:
	var denom := b.x - a.x
	if absf(denom) < EPS:
		return Vector2(x, a.y)
	var t := (x - a.x) / denom
	return Vector2(x, a.y + t * (b.y - a.y))

static func _intersect_horizontal(a: Vector2, b: Vector2, y: float) -> Vector2:
	var denom := b.y - a.y
	if absf(denom) < EPS:
		return Vector2(a.x, y)
	var t := (y - a.y) / denom
	return Vector2(a.x + t * (b.x - a.x), y)

## Entfernt fast gleiche und kollineare Zwischenpunkte.
##
## Ergebnis ist die minimale Eckpunktfolge des Polygons und damit
## vergleichbar mit den Zellpolygonen aus d3-delaunay. Die Funktion ist
## flaechentreu: entfernte Punkte liegen auf der Strecke ihrer Nachbarn.
static func simplify_polygon(poly: PackedVector2Array, eps := 1e-9) -> PackedVector2Array:
	var count := poly.size()
	if count < 3:
		return poly
	var eps_sq := eps * eps

	var unique := PackedVector2Array()
	unique.resize(count)
	var u := 0
	for i in range(count):
		var p := poly[i]
		if u == 0 or unique[u - 1].distance_squared_to(p) > MERGE_EPSILON_SQ:
			unique[u] = p
			u += 1
	while u >= 2 and unique[0].distance_squared_to(unique[u - 1]) <= MERGE_EPSILON_SQ:
		u -= 1
	if u < 3:
		unique.resize(u)
		return unique

	var out := PackedVector2Array()
	out.resize(u)
	var written := 0
	var prev := unique[u - 1]
	for i in range(u):
		var cur := unique[i]
		var next := unique[(i + 1) % u]
		var d1 := cur - prev
		var d2 := next - cur
		var scale := maxf(1.0, d1.length() * d2.length())
		if absf(d1.cross(d2)) / scale > eps:
			out[written] = cur
			written += 1
		prev = cur
	if written < 3:
		return unique
	out.resize(written)
	return out

## Schneidet ein konvexes Polygon an einer Halbebene dot(n, p) <= d.
static func clip_half_plane(poly: PackedVector2Array, n: Vector2, d: float) -> PackedVector2Array:
	var count := poly.size()
	if count == 0:
		return poly
	var out := PackedVector2Array()
	out.resize(count + 1)
	var written := 0
	var prev := poly[count - 1]
	var prev_val := n.dot(prev) - d
	var prev_in := prev_val <= 0.0
	for i in range(count):
		var cur := poly[i]
		var cur_val := n.dot(cur) - d
		var cur_in := cur_val <= 0.0
		if prev_in != cur_in:
			var denom := prev_val - cur_val
			if absf(denom) < EPS:
				out[written] = prev
			else:
				out[written] = prev + (cur - prev) * (prev_val / denom)
			written += 1
		if cur_in:
			out[written] = cur
			written += 1
		prev = cur
		prev_val = cur_val
		prev_in = cur_in
	out.resize(written)
	return out

## Groesste Flaeche aus einer Liste von Polygonen (z. B. nach dem Verschmelzen
## mehrerer Zellpolygone, wo Randstuecke uebrig bleiben koennen).
static func largest_polygon(polygons: Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_area := 0.0
	for poly in polygons:
		var area := polygon_area(poly)
		if area > best_area:
			best_area = area
			best = poly
	return best


## Rundet ein geschlossenes Polygon (Chaikin): jede Kante wird durch zwei
## Punkte bei einem Viertel und drei Vierteln ersetzt. Die Kontur wird dabei
## leicht kleiner, bleibt aber innerhalb der alten Eckpunkte.
static func smooth_closed_polygon(poly: PackedVector2Array, rounds := 1) -> PackedVector2Array:
	var out := poly
	for round_index in range(maxi(rounds, 0)):
		var count := out.size()
		if count < 3:
			return out
		var smoothed := PackedVector2Array()
		smoothed.resize(count * 2)
		for i in range(count):
			var p := out[i]
			var q := out[(i + 1) % count]
			smoothed[i * 2] = p.lerp(q, 0.25)
			smoothed[i * 2 + 1] = p.lerp(q, 0.75)
		out = smoothed
	return out


## Prueft, ob ein Polygon konvex und nicht entartet ist. Die
## Umkreismittelpunkt-Konstruktion kann bei fast entarteten Dreiecken
## Selbstschnitte erzeugen; solche Faelle werden damit erkannt.
static func is_convex(poly: PackedVector2Array) -> bool:
	var count := poly.size()
	if count < 3:
		return false
	var sign := 0
	for i in range(count):
		var p0 := poly[i]
		var p1 := poly[(i + 1) % count]
		var p2 := poly[(i + 2) % count]
		if not is_finite(p0.x) or not is_finite(p0.y):
			return false
		var cross := (p1 - p0).cross(p2 - p1)
		if absf(cross) <= 1e-6:
			continue
		var current := 1 if cross > 0.0 else -1
		if sign == 0:
			sign = current
		elif sign != current:
			return false
	return true


## Umkreismittelpunkt eines Dreiecks. Fuer entartete Dreiecke wird der
## Schwerpunkt zurueckgegeben (stabiler Ersatzwert).
static func circumcenter(a: Vector2, b: Vector2, c: Vector2) -> Vector2:
	var d := 2.0 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
	if absf(d) < 1e-12:
		return (a + b + c) / 3.0
	var a_sq := a.length_squared()
	var b_sq := b.length_squared()
	var c_sq := c.length_squared()
	return Vector2(
		(a_sq * (b.y - c.y) + b_sq * (c.y - a.y) + c_sq * (a.y - b.y)) / d,
		(a_sq * (c.x - b.x) + b_sq * (a.x - c.x) + c_sq * (b.x - a.x)) / d
	)


## Rundung wie Math.round in JavaScript (halbe Werte Richtung +unendlich).
static func js_round(value: float) -> int:
	return int(floor(value + 0.5))
