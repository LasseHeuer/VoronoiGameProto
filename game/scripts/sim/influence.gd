class_name Influence
extends RefCounted

## Kraftverteilung der Zellen.
##
## Nur die groesste Zelle je Spieler (die Wurzel) traegt einen eigenen
## Groessenwert: die Tonmenge x, rot positiv und blau negativ. x gilt fuer die
## groesste Zelle des Bretts; eine kleinere Wurzel traegt entsprechend weniger
## (x mal ihre Flaeche geteilt durch die groesste Flaeche). Alle anderen
## Zellen bekommen ausschliesslich die Summe der Flusswerte, die von den
## groesseren Nachbarn ankommen. Von jeder Zelle fliesst ihr Wert an die
## naechstkleineren Nachbarn, aufgeteilt nach der gemeinsamen Kantenlaenge
## (Richtung immer groesser -> kleiner).
##
## Der Wert ist also die vorzeichenbehaftete Summe der Zufluesse: zwei rote
## Nachbarn mit +20 und +30 und ein blauer mit -40 ergeben +10. Reine Logik auf
## CellGeometry, keine Node-Abhaengigkeit.

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


## Bevorzugt die gespeicherte Wurzelzelle nur, solange sie noch zur jeweiligen
## Farbe gehoert und genauso gross ist wie die groesste gefaerbte Zelle. Waechst
## im Spiel eine andere Zelle zur groessten ihrer Farbe heran, wandert die Wurzel
## mit: nur so traegt die groesste Zelle immer den Groessenwert und gibt ihn
## weiter. Der Groessenvergleich laeuft ueber die gerundeten Stufen, damit
## gleich grosse Zellen die Wurzel nicht jeden Tick hin und her springen lassen.
static func resolve_roots(geometry: CellGeometry, ids: PackedByteArray,
		preferred: PackedInt32Array) -> PackedInt32Array:
	var best := roots(geometry, ids)
	var keys := _area_keys(geometry)
	for slot in range(2):
		var candidate := preferred[slot] if slot < preferred.size() else -1
		if candidate >= 0 and candidate < geometry.count() and candidate < ids.size() \
			and int(ids[candidate]) == slot + 1 \
			and best[slot] >= 0 and keys[candidate] >= keys[best[slot]]:
			best[slot] = candidate
	return best


## Gesamtes Kraftfeld: `values` (vorzeichenbehafteter Zellwert) und `edges`
## (Fliessmenge je Kante groesser -> kleiner, Schluessel `i * count + j`).
##
## Die beiden Wurzeln starten mit ihrem Groessenwert (+x mal Flaechenanteil
## fuer Rot, negativ fuer Blau). Weitergegeben wird der angezeigte Zellwert,
## also der Groessenwert plus der bei der Zelle ankommende gegnerische Fluss.
## Zieht der Gegner etwas ab, fliesst entsprechend weniger weiter. Alle Zellen
## geben so den bei ihnen angekommenen Fluss weiter; der Zufluss wird dort
## summiert.
static func distribute(geometry: CellGeometry, ids: PackedByteArray,
		preferred := PackedInt32Array(),
		start_strength := GameConfig.INFLUENCE_START_STRENGTH) -> Dictionary:
	var count := geometry.count()
	var values := PackedFloat32Array()
	values.resize(count)
	values.fill(0.0)
	var edges := {}
	if count == 0:
		return {"values": values, "edges": edges}
	var resolved := resolve_roots(geometry, ids, preferred)
	var keys := _area_keys(geometry)
	# Eigener Groessenwert je Wurzelzelle: der Startwert des Zellwerts. Der
	# gegnerische Zufluss kommt beim Verteilen hinzu und zaehlt mit.
	var own := PackedFloat32Array()
	own.resize(count)
	own.fill(0.0)
	if resolved[0] >= 0 and resolved[0] < count:
		own[resolved[0]] += _root_strength(keys, resolved[0], start_strength)
	if resolved[1] >= 0 and resolved[1] < count:
		own[resolved[1]] -= _root_strength(keys, resolved[1], start_strength)
	for i in range(count):
		values[i] += own[i]
	for i in _order_by_keys(keys):
		# Jede Zelle gibt ihren angezeigten (Netto-)Zellwert weiter. Er ist zu
		# diesem Zeitpunkt vollstaendig, weil nur groessere Nachbarn Zufluss
		# liefern und diese bereits verarbeitet sind. Eine Wurzel mit
		# gegnerischem Abzug gibt damit nur noch ihren tatsaechlichen Wert
		# weiter, nicht ihren urspruenglichen Groessenwert.
		var out_value := values[i]
		# Graue Zellen gelten als verloren: sie gehoeren keinem Spieler mehr und
		# vererben deshalb nichts an kleinere Nachbarn.
		if is_neutral(out_value):
			continue
		var total_edge := 0.0
		for neighbor in geometry.neighbors[i]:
			if _is_smaller(keys, neighbor, i):
				total_edge += _edge_length(geometry, i, neighbor)
		if total_edge <= 0.0:
			continue
		for neighbor in geometry.neighbors[i]:
			if not _is_smaller(keys, neighbor, i):
				continue
			var share := out_value * _edge_length(geometry, i, neighbor) / total_edge
			if is_zero_approx(share):
				continue
			values[neighbor] += share
			edges[i * count + neighbor] = share
	return {"values": values, "edges": edges}


## Vorzeichenbehafteter Zellwert (Summe der Zufluesse): rot positiv, blau
## negativ. Zellen ohne Zufluss sind 0.
static func cell_values(geometry: CellGeometry, ids: PackedByteArray,
		preferred := PackedInt32Array(),
		start_strength := GameConfig.INFLUENCE_START_STRENGTH) -> PackedFloat32Array:
	var values: PackedFloat32Array = distribute(geometry, ids, preferred, start_strength)["values"]
	return values


## Zellwert unter der Neutral-Schwelle: die Zelle gilt als grau und zaehlt nicht
## zum Territorium.
static func is_neutral(value: float) -> bool:
	return absf(value) < GameConfig.NEUTRAL_VALUE_THRESHOLD


## Besitzer je Zelle aus dem Vorzeichen des Zellwerts: positiv = Spieler 1,
## negativ = Spieler 2. Graue Zellen (unter der Neutral-Schwelle) gehoeren
## keinem Spieler mehr und bekommen die Kennung 0.
static func owner_ids(geometry: CellGeometry, ids: PackedByteArray,
		preferred := PackedInt32Array(),
		start_strength := GameConfig.INFLUENCE_START_STRENGTH) -> PackedByteArray:
	var count := geometry.count()
	var owners := PackedByteArray()
	owners.resize(count)
	owners.fill(0)
	if count == 0:
		return owners
	var values := cell_values(geometry, ids, preferred, start_strength)
	for i in range(count):
		if is_neutral(values[i]):
			owners[i] = 0
		elif values[i] > 0.0:
			owners[i] = 1
		else:
			owners[i] = 2
	return owners


## Groessenordnung je Zelle. Die Flaeche wird relativ zur groessten Flaeche auf
## 1000 Stufen gerundet: so sind gespiegelte Zellen (deren Flaechen sich nur um
## Rundungsrauschen unterscheiden) exakt gleich gross und der Fluss bleibt
## spiegelsymmetrisch.
static func _area_keys(geometry: CellGeometry) -> PackedInt32Array:
	var count := geometry.count()
	var keys := PackedInt32Array()
	keys.resize(count)
	var max_area := 0.0
	for area in geometry.areas:
		max_area = maxf(max_area, float(area))
	if max_area <= 0.0:
		keys.fill(0)
		return keys
	for i in range(count):
		keys[i] = int(round(float(geometry.areas[i]) / max_area * 1000.0))
	return keys


## Groessenstufen je Zelle (oeffentlich fuer die Anzeige): die Flaeche relativ
## zur groessten Flaeche, auf 1000 Stufen gerundet - dieselbe Ordnung, die
## `distribute` fuer die Fliessrichtung verwendet.
static func size_keys(geometry: CellGeometry) -> PackedInt32Array:
	return _area_keys(geometry)


## Eigener Groessenwert einer Wurzelzelle: die Tonmenge x mal ihrer Flaeche
## relativ zur groessten Zelle des Bretts (gerundete Groessenstufe, damit
## gespiegelte Wurzeln denselben Wert tragen).
static func _root_strength(keys: PackedInt32Array, cell: int, start_strength: float) -> float:
	if cell < 0 or cell >= keys.size():
		return 0.0
	return start_strength * float(keys[cell]) / 1000.0


## Ist `neighbor` nach der gerundeten Groesse kleiner als `cell`?
static func _is_smaller(keys: PackedInt32Array, neighbor: int, cell: int) -> bool:
	return neighbor >= 0 and neighbor < keys.size() and keys[neighbor] < keys[cell]


## Oeffentliche Fliessrichtung: ist `neighbor` nach der gerundeten Groesse
## kleiner als `cell`? Damit zeichnet die Anzeige genau die Kanten, die auch
## einen Flusswert tragen koennen.
static func is_smaller(keys: PackedInt32Array, neighbor: int, cell: int) -> bool:
	return _is_smaller(keys, neighbor, cell)


## Gemeinsame Kantenlaenge zweier Zellen (0, wenn keine Kante existiert).
static func _edge_length(geometry: CellGeometry, first: int, second: int) -> float:
	if first < 0 or first >= geometry.edge_lengths.size():
		return 0.0
	return maxf(0.0, float(geometry.edge_lengths[first].get(second, 0.0)))


## Indizes absteigend nach Groesse, bei Gleichstand nach Index.
static func _order_by_keys(keys: PackedInt32Array) -> Array:
	var order: Array = []
	order.resize(keys.size())
	for i in range(keys.size()):
		order[i] = i
	order.sort_custom(func(a, b):
		if keys[a] == keys[b]:
			return a < b
		return keys[a] > keys[b])
	return order
