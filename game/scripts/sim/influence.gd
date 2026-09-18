class_name Influence
extends RefCounted

## Staerkeverteilung des Einflusses im Spielfeld.
##
## Von der groessten Zelle eines Spielers fliesst Staerke ueber die gemeinsamen
## Zellgrenzen. Groessere Nachbarzellen und laengere Grenzen geben mehr Staerke
## weiter; unter der Mindeststaerke wird der Wert 0. Eine Zelle mit 0 gehoert
## keinem Spieler und bleibt grau.
##
## Reine Logik auf CellGeometry, keine Node-Abhaengigkeit.

## Wurzelzellen aus den Farben ableiten: je Spieler die groesste gefaerbte Zelle.
static func roots(geometry: CellGeometry, ids: PackedByteArray) -> PackedInt32Array:
	var best := PackedInt32Array([-1, -1])
	for i in range(mini(geometry.count(), ids.size())):
		var id := int(ids[i])
		if id != 1 and id != 2:
			continue
		var slot := id - 1
		if best[slot] < 0 or geometry.areas[i] > geometry.areas[best[slot]]:
			best[slot] = i
	return best


## Bevorzugt die gespeicherten Wurzelzellen, solange sie noch zur jeweiligen
## Farbe gehoeren. Sonst wird die groesste gefaerbte Zelle verwendet.
static func resolve_roots(geometry: CellGeometry, ids: PackedByteArray,
		preferred: PackedInt32Array) -> PackedInt32Array:
	var derived := roots(geometry, ids)
	var out := PackedInt32Array([-1, -1])
	for slot in range(2):
		var candidate := preferred[slot] if slot < preferred.size() else -1
		if candidate >= 0 and candidate < geometry.count() and candidate < ids.size() \
			and int(ids[candidate]) == slot + 1:
			out[slot] = candidate
		else:
			out[slot] = derived[slot]
	return out


## Staerke je Zelle ausgehend von `source`. Rueckgabe enthaelt die Werte
## ("strengths") und je Zelle den Nachbarn, der die meiste Staerke geliefert hat
## ("parents") - daraus entstehen die Flow-Wege.
static func flow(geometry: CellGeometry, source: int) -> Dictionary:
	var count := geometry.count()
	var strengths := PackedFloat32Array()
	strengths.resize(count)
	strengths.fill(0.0)
	var parents := PackedInt32Array()
	parents.resize(count)
	parents.fill(-1)
	if source < 0 or source >= count:
		return {"strengths": strengths, "parents": parents}

	var max_edge := _max_edge(geometry)
	var max_area := _max_area(geometry)
	strengths[source] = GameConfig.INFLUENCE_START_STRENGTH
	var queue: Array = [source]
	while not queue.is_empty():
		# Jeweils die Zelle mit der aktuell hoechsten Staerke zuerst. Weil die
		# Weitergabe die Staerke nie erhoeht, ist das ein stabiler Maximalfluss.
		var best := 0
		for k in range(1, queue.size()):
			if strengths[queue[k]] > strengths[queue[best]]:
				best = k
		var current: int = queue[best]
		queue.remove_at(best)
		for neighbor in geometry.neighbors[current]:
			if neighbor < 0 or neighbor >= count:
				continue
			var edge := float(geometry.edge_lengths[current].get(neighbor, 0.0))
			if edge <= 0.0:
				continue
			var edge_ratio := clampf(edge / max_edge, 0.0, 1.0)
			var area_ratio := clampf(float(geometry.areas[neighbor]) / max_area, 0.0, 1.0)
			var transfer := strengths[current] * GameConfig.INFLUENCE_TRANSFER_RATE \
				* sqrt(edge_ratio * area_ratio)
			if transfer < GameConfig.INFLUENCE_MIN_STRENGTH:
				transfer = 0.0
			if transfer > strengths[neighbor]:
				strengths[neighbor] = transfer
				parents[neighbor] = current
				queue.append(neighbor)
	return {"strengths": strengths, "parents": parents}


## Besitzer je Zelle aus der Staerke beider Spieler: der staerkere Spieler
## gewinnt, bei 0 fuer beide bleibt die Zelle neutral (0).
static func owner_ids(geometry: CellGeometry, ids: PackedByteArray,
		preferred := PackedInt32Array()) -> PackedByteArray:
	var count := geometry.count()
	var owners := PackedByteArray()
	owners.resize(count)
	owners.fill(0)
	if count == 0:
		return owners
	var resolved := resolve_roots(geometry, ids, preferred)
	var red: PackedFloat32Array = flow(geometry, resolved[0])["strengths"]
	var blue: PackedFloat32Array = flow(geometry, resolved[1])["strengths"]
	for i in range(count):
		if red[i] > blue[i]:
			owners[i] = 1
		elif blue[i] > red[i]:
			owners[i] = 2
		else:
			owners[i] = ids[i] if i < ids.size() else 0
	return owners


static func _max_edge(geometry: CellGeometry) -> float:
	var max_edge := 0.0
	for lengths in geometry.edge_lengths:
		for edge in lengths.values():
			max_edge = maxf(max_edge, float(edge))
	return maxf(max_edge, 0.001)


static func _max_area(geometry: CellGeometry) -> float:
	var max_area := 0.0
	for area in geometry.areas:
		max_area = maxf(max_area, float(area))
	return maxf(max_area, 0.001)
