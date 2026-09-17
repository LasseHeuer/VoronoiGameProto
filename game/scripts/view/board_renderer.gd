class_name BoardRenderer
extends Node2D

## Zeichnet das Brett: Zellfuellungen, Flaechen-Text, Rahmen, Punkte und
## Drag-Linien. Liest nur BoardState, Voronoi und Config.
##
## Gezeichnet wird direkt in Fensterpixeln (view_transform), nicht ueber die
## Node2D-Skalierung: so werden Linien, Punkte und Text in jeder Fenster-
## groesse in voller Aufloesung gerastert.

var board: BoardState
var config: GameConfig
var voronoi: Voronoi
## Brett -> Fenster (Skalierung und Versatz).
var view_transform := BoardTransform.new()
## Zellen, deren Ton gerade klingt: Zellenindex -> Deckkraft (0..1).
var highlight_cells := {}

var _font: Font
## Fuellfarbe je Zelle (Flaechenanteil und Gegneranteil), einmal je Frame.
var _fill_colors := PackedStringArray()
## Konturen der Territorien (Fensterkoordinaten) je Farbe.
var _territory_line := {}
## Fuellgrenzen der Territorien (Fensterkoordinaten) je Farbe.
var _territory_clip := {}
## Abgeschnittene, mit Teamfarbe gefuellte Eckstuecke je Farbe.
var _territory_corner := {}
var _cache_voronoi: Voronoi = null
var _cache_colors := PackedStringArray()
var _cache_points := PackedVector2Array()
var _cache_scale := -1.0
var _cache_offset := Vector2.ZERO
var _cache_radius := -1.0
## Gerundete Zellfuellungen (Fensterkoordinaten), einmal je Geometrie.
var _fill_outlines: Array = []
var _cache_fill_voronoi: Voronoi = null
var _cache_fill_colors := PackedStringArray()
var _cache_fill_scale := -1.0
var _cache_fill_offset := Vector2.ZERO
var _cache_fill_radius := -1.0
## UV-Platzhalter fuer draw_primitive (3 Punkte je Dreieck).
var _uvs3 := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])


func _ready() -> void:
	_font = ThemeDB.fallback_font


func set_board_state(p_board: BoardState, p_config: GameConfig, p_voronoi: Voronoi) -> void:
	board = p_board
	config = p_config
	voronoi = p_voronoi


func _draw() -> void:
	var board_size := BoardTransform.BOARD_SIZE * view_transform.scale
	draw_rect(Rect2(view_transform.offset, board_size), Color("#b2b2b2"), true)
	if board == null or config == null or voronoi == null:
		return
	_draw_cells()
	_draw_hover_outline()
	_draw_points()
	_draw_drag_lines()
	if config.show_cell_numbers:
		_draw_cell_labels()


func _to_screen(point: Vector2) -> Vector2:
	return point * view_transform.scale + view_transform.offset


func _to_screen_polygon(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(poly.size())
	for i in range(poly.size()):
		out[i] = _to_screen(poly[i])
	return out


func _text_size() -> int:
	return maxi(1, int(round(GameConfig.AREA_TEXT_SIZE * view_transform.scale)))


func _draw_cells() -> void:
	var count := voronoi.cells.size()
	if count == 0:
		return
	var line_scale := view_transform.scale
	_ensure_territories(line_scale)
	_ensure_fill_outlines(line_scale)

	# 1) Zellflaechen: immer das gueltige Voronoi-Polygon fuellen. Die
	#    Territoriums-Grenze liegt darueber; so bleiben keine Zellen grau, wenn
	#    eine komplexe Clipflaeche nicht triangulierbar ist.
	var shapes: Array = []
	var raws: Array = []
	shapes.resize(count)
	raws.resize(count)
	for i in range(count):
		var poly := voronoi.cell_polygon(i)
		if poly.size() < 3 or voronoi.area(i) <= 0.01:
			continue
		var screen := _to_screen_polygon(poly)
		raws[i] = screen
		var filled: PackedVector2Array = _fill_outlines[i]
		if filled.size() < 3:
			filled = screen
		var parts := _clip_to_territory(i, filled)
		if parts.is_empty():
			parts = [filled]
		shapes[i] = parts
		for part in parts:
			_fill_polygon(part, Color(_fill_colors[i]))
		if highlight_cells.has(i):
			# Klingende Zelle: farbige Ueberlagerung folgt der Tonlautstaerke.
			var play_color := Color(GameConfig.NOTE_PLAY_COLOR)
			play_color.a = GameConfig.NOTE_PLAY_ALPHA * clampf(float(highlight_cells[i]), 0.0, 1.0)
			for part in parts:
				_fill_polygon(part, play_color)

	# 2) Uebernahme-Warnung: die groesste Gegnerzelle blinkt.
	_draw_takeover_blink(shapes)

	# 3) Duenne graue Innenraender zwischen gleichfarbigen Zellen.
	for i in range(count):
		if raws[i] == null:
			continue
		_draw_cell_borders(i, raws[i], line_scale)

	# 4) Durchgehende Frontlinie um jedes Territorium.
	_draw_territory_lines(line_scale)


## Fuellfarbe jeder Zelle: kontinuierlicher Verlauf durch die drei definierten
## Farbstufen des jeweiligen Spielers.
func _cell_fill_colors(count: int) -> PackedStringArray:
	var colors := PackedStringArray()
	colors.resize(count)
	var step_colors := _cell_step_colors(count)
	for i in range(count):
		colors[i] = step_colors[i] if step_colors[i] != "" else GameConfig.CELL_EMPTY_COLOR
	return colors


## Farbverlauf je Zelle: die groesste Zelle bekommt Landmarke 1. Alle weiteren
## Zellen werden zwischen Landmarke 2 (zweitgroesste) und 3 (kleinste) im
## RGB-Raum fliessend interpoliert.
func _cell_step_colors(count: int) -> PackedStringArray:
	var out := PackedStringArray()
	out.resize(count)
	for player in [GameConfig.COLOR_PLAYER1, GameConfig.COLOR_PLAYER2]:
		var palette: Array = GameConfig.step_colors_for(player)
		var indices: Array = []
		for i in range(count):
			if board.cell_color(i) == player:
				indices.append(i)
		if indices.is_empty():
			continue
		var min_area := INF
		for index in indices:
			var area := voronoi.area(index)
			min_area = minf(min_area, area)
		indices.sort_custom(func(a, b):
			if voronoi.area(a) == voronoi.area(b):
				return a < b
			return voronoi.area(a) > voronoi.area(b))
		var largest: int = int(indices[0])
		if indices.size() == 1:
			out[largest] = "#" + Color(palette[0]).to_html(false)
			continue
		var second_area := voronoi.area(indices[1])
		for index in indices:
			if index == largest:
				# Landmarke 1 ist ausschliesslich fuer die groesste Zelle.
				out[index] = "#" + Color(palette[0]).to_html(false)
				continue
			var t := 0.0
			if not is_equal_approx(second_area, min_area):
				# Die restlichen Zellen verlaufen nur von Landmarke 2 zu 3.
				t = clampf(inverse_lerp(second_area, min_area, voronoi.area(index)), 0.0, 1.0)
			out[index] = _interpolate_remaining_landmarks(palette, t)
	return out


static func _interpolate_landmarks(palette: Array, t: float) -> String:
	if palette.size() < 3:
		return GameConfig.CELL_EMPTY_COLOR
	var color: Color
	if t <= 0.5:
		color = Color(palette[0]).lerp(Color(palette[1]), t * 2.0)
	else:
		color = Color(palette[1]).lerp(Color(palette[2]), (t - 0.5) * 2.0)
	return "#" + color.to_html(false)


static func _interpolate_remaining_landmarks(palette: Array, t: float) -> String:
	if palette.size() < 3:
		return GameConfig.CELL_EMPTY_COLOR
	var color := Color(palette[1]).lerp(Color(palette[2]), clampf(t, 0.0, 1.0))
	return "#" + color.to_html(false)


## Duenne graue Innenraender einer Zelle: nur auf den Kanten zu einer
## gleichfarbigen Nachbarzelle. Die Frontkanten zeichnet das Territorium.
##
## Abgerundet werden nur Ecken, an denen beide anliegenden Kanten einen
## Innenrand tragen. An der Front endet der Innenrand am Zellrand und wird von
## der dicken Frontlinie ueberdeckt.
func _draw_cell_borders(index: int, poly: PackedVector2Array, line_scale: float) -> void:
	var count := poly.size()
	if count < 3:
		return
	var my_color := board.cell_color(index)
	var neighbors := voronoi.edge_neighbors(index)
	var width := GameConfig.SAME_COLOR_FRAME_WIDTH * line_scale
	var gray := Color(GameConfig.FRAME_COLOR)
	var is_same: Array = []
	is_same.resize(count)
	for k in range(count):
		var nb: int = neighbors[k] if k < neighbors.size() else -1
		is_same[k] = nb >= 0 and board.cell_color(nb) == my_color
	var normals := _inward_normals(poly)
	var zero := PackedVector2Array()
	zero.resize(count)
	var corners := _cell_corners(poly, is_same, normals, config.corner_radius * line_scale, 0.0, true)
	for k in range(count):
		if not is_same[k]:
			continue
		draw_line(_edge_start(poly, k, corners, zero), _edge_end(poly, k, corners, zero), gray, width, true)
	for key in corners:
		var arc: PackedVector2Array = corners[key]["arc"]
		if arc.size() >= 2:
			draw_polyline(arc, gray, width, true)
	# Scharfe Ecken (Radius 0): kleine Fuellpunkte als runde Anschluesse.
	for k in range(count):
		var prev := (k - 1 + count) % count
		if corners.has(k) or not (is_same[prev] and is_same[k]):
			continue
		draw_circle(poly[k], width * 0.5, gray, true)


## Innen liegende Einheitsnormale jeder Kante (zeigt ins Zellinnere).
func _inward_normals(poly: PackedVector2Array) -> PackedVector2Array:
	var count := poly.size()
	var out := PackedVector2Array()
	out.resize(count)
	var ccw := BoardGeometry.signed_polygon_area(poly) > 0.0
	for k in range(count):
		var dir := poly[(k + 1) % count] - poly[k]
		if dir.length_squared() < 1e-12:
			out[k] = Vector2.ZERO
			continue
		dir = dir.normalized()
		var normal := Vector2(-dir.y, dir.x)
		out[k] = normal if ccw else -normal
	return out


## Beginn der Kante k: Ende des Eckbogens oder der Eckpunkt selbst.
func _edge_start(poly: PackedVector2Array, k: int, corners: Dictionary, offsets: PackedVector2Array) -> Vector2:
	if corners.has(k):
		return corners[k]["finish"]
	return poly[k] + offsets[k]


## Ende der Kante k: Beginn des Eckbogens an der naechsten Ecke.
func _edge_end(poly: PackedVector2Array, k: int, corners: Dictionary, offsets: PackedVector2Array) -> Vector2:
	var next := (k + 1) % poly.size()
	if corners.has(next):
		return corners[next]["start"]
	return poly[next] + offsets[k]


## Abgerundete Ecken der Zelle: Schluessel ist der Eckindex. Abgerundet werden
## alle konvexen Ecken (Voronoi-Zellen sind konvex); mit `require_both` nur
## die, an denen beide anliegenden Kanten in `is_front` stehen.
func _cell_corners(poly: PackedVector2Array, is_front: Array, normals: PackedVector2Array, radius: float, offset: float, require_both := false) -> Dictionary:
	var out := {}
	var count := poly.size()
	if radius <= 0.01 or count < 3:
		return out
	var ccw := BoardGeometry.signed_polygon_area(poly) > 0.0
	for k in range(count):
		var prev := (k - 1 + count) % count
		if require_both and not (is_front[prev] and is_front[k]):
			continue
		var v := poly[k]
		var to_prev := poly[prev] - v
		var to_next := poly[(k + 1) % count] - v
		var len_prev := to_prev.length()
		var len_next := to_next.length()
		if len_prev < 1e-3 or len_next < 1e-3:
			continue
		var cross := to_prev.cross(to_next)
		if (cross < 0.0) != ccw or absf(cross) < 1e-6:
			continue
		var trim := minf(radius, minf(len_prev, len_next) * 0.45)
		if trim <= 0.01:
			continue
		var ofs_prev := normals[prev] * offset if is_front[prev] else Vector2.ZERO
		var ofs_next := normals[k] * offset if is_front[k] else Vector2.ZERO
		var start := v + (to_prev / len_prev) * trim + ofs_prev
		var finish := v + (to_next / len_next) * trim + ofs_next
		var control := v
		if is_front[prev] and is_front[k]:
			var denom := 1.0 + normals[prev].dot(normals[k])
			control = v + ((normals[prev] + normals[k]) / denom * offset if denom > 1e-6 else ofs_next)
		elif is_front[prev]:
			control = v + ofs_prev
		elif is_front[k]:
			control = v + ofs_next
		var steps := _arc_steps(trim, to_prev.angle_to(to_next))
		var arc := PackedVector2Array()
		arc.resize(steps + 1)
		for s in range(steps + 1):
			arc[s] = _quadratic(start, control, finish, float(s) / float(steps))
		out[k] = {
			"arc": arc,
			"trim": trim,
			"start": start,
			"finish": finish,
		}
	return out


## Aufloesung eines Eckbogens: mindestens acht Stuetzpunkte, bei grossen
## Radien rund einer je zweiundeinhalb Pixel Bogenlaenge. So sehen die Ecken
## auch bei grossem Radius weich aus.
static func _arc_steps(trim: float, sweep: float) -> int:
	return clampi(int(ceil(trim * absf(sweep) / 2.5)), 8, 28)


# --------------------------------------------------------- Territorium -----

## Durchgehende Frontlinie um jedes Territorium: eine geschlossene Kontur je
## Farbflaeche, um die halbe Linienbreite nach innen versetzt. An den
## Innenecken wird das beim Abrunden abgeschnittene Eckstueck in der Teamfarbe
## gefuellt, damit dort keine Luecke entsteht.
func _draw_territory_lines(line_scale: float) -> void:
	var width := GameConfig.FRONT_FRAME_WIDTH * line_scale
	for color in [GameConfig.COLOR_PLAYER1, GameConfig.COLOR_PLAYER2]:
		var team := Color(color)
		var paths: Array = _territory_line.get(color, [])
		for path in paths:
			if path.size() < 3:
				continue
			var closed: PackedVector2Array = path.duplicate()
			closed.append(path[0])
			draw_polyline(closed, team, width, true)


## Konturen und Fuellgrenzen beider Farben neu berechnen, wenn sich Geometrie,
## Farben, Radius oder Ansicht geaendert haben.
func _ensure_territories(line_scale: float) -> void:
	if _territories_valid(line_scale):
		return
	_territory_line.clear()
	_territory_clip.clear()
	_territory_corner.clear()
	var safe_scale := maxf(line_scale, 0.0001)
	var half := GameConfig.FRONT_FRAME_WIDTH * 0.5 / safe_scale
	var inset := GameConfig.FRONT_FRAME_WIDTH / safe_scale
	for color in [GameConfig.COLOR_PLAYER1, GameConfig.COLOR_PLAYER2]:
		var line_paths: Array = []
		var clip_paths: Array = []
		var corner_paths: Array = []
		for region in _merge_cells(color):
			if region.size() < 3 or absf(BoardGeometry.signed_polygon_area(region)) <= 0.5:
				continue
			region = _ensure_ccw(region)
			var fillet := _fillet_with_cuts(region, config.corner_radius + half)
			var rounded: PackedVector2Array = fillet["path"]
			for inner in Geometry2D.offset_polygon(rounded, -half, Geometry2D.JOIN_ROUND):
				if inner.size() >= 3:
					var smooth_line := _smooth_territory_path(_ensure_ccw(inner))
					line_paths.append(_to_screen_polygon(smooth_line))
			for inner in Geometry2D.offset_polygon(rounded, -inset, Geometry2D.JOIN_ROUND):
				if inner.size() >= 3:
					var smooth_clip := _smooth_territory_path(_ensure_ccw(inner))
					clip_paths.append(_to_screen_polygon(smooth_clip))
			for cut in fillet["cuts"]:
				# Am Brettrand zeigt die Luecke den Hintergrund: dort bleibt
				# die Ecke offen und wirkt dadurch rund.
				if _on_board_border(cut["vertex"]):
					continue
				corner_paths.append({
					"vertex": _to_screen(cut["vertex"]),
					"arc": _to_screen_polygon(cut["arc"]),
				})
		_territory_line[color] = line_paths
		_territory_clip[color] = clip_paths
		_territory_corner[color] = corner_paths
	_cache_voronoi = voronoi
	_cache_colors = board.cell_colors
	_cache_points = board.points
	_cache_scale = view_transform.scale
	_cache_offset = view_transform.offset
	_cache_radius = config.corner_radius


func _smooth_territory_path(path: PackedVector2Array) -> PackedVector2Array:
	if config.corner_radius <= 0.01:
		return path
	# Dummy-Raender erzeugen bei langen Konturen viele kleine Richtungswechsel.
	# Ein zweiter Chaikin-Durchlauf glattet nur diese langen Wege; kurze
	# Territorien behalten die bisherige Geometrie.
	var rounds := 2 if path.size() >= 12 else 1
	return BoardGeometry.smooth_closed_polygon(path, rounds)


## Gerundete Zellfuellungen und Fuellfarben nur dann neu berechnen, wenn sich
## Geometrie, Farben, Radius oder Ansicht geaendert haben. Im Ruhezustand
## entfaellt damit pro Bild die komplette Neuberechnung aller Zellen.
func _ensure_fill_outlines(line_scale: float) -> void:
	if voronoi == _cache_fill_voronoi \
		and board.cell_colors == _cache_fill_colors \
		and is_equal_approx(view_transform.scale, _cache_fill_scale) \
		and view_transform.offset == _cache_fill_offset \
		and is_equal_approx(config.corner_radius, _cache_fill_radius):
		return
	var count := voronoi.cells.size()
	_fill_colors = _cell_fill_colors(count)
	_fill_outlines = []
	_fill_outlines.resize(count)
	for i in range(count):
		var poly := voronoi.cell_polygon(i)
		if poly.size() < 3:
			_fill_outlines[i] = PackedVector2Array()
			continue
		_fill_outlines[i] = _fill_outline(i, _to_screen_polygon(poly), line_scale)
	_cache_fill_voronoi = voronoi
	_cache_fill_colors = board.cell_colors
	_cache_fill_scale = view_transform.scale
	_cache_fill_offset = view_transform.offset
	_cache_fill_radius = config.corner_radius


## Liegt der Punkt auf dem Rand des Bretts?
static func _on_board_border(point: Vector2) -> bool:
	return point.x <= 1.0 or point.y <= 1.0 \
		or point.x >= GameConfig.BOARD_WIDTH - 1.0 \
		or point.y >= GameConfig.BOARD_HEIGHT - 1.0


func _territories_valid(line_scale: float) -> bool:
	if voronoi == null or board == null or voronoi != _cache_voronoi:
		return false
	return board.cell_colors == _cache_colors \
		and board.points == _cache_points \
		and is_equal_approx(line_scale, _cache_scale) \
		and view_transform.offset == _cache_offset \
		and is_equal_approx(config.corner_radius, _cache_radius)


## Aussenkonturen der Zellflaechen einer Farbe (Brettkoordinaten).
## Gleichfarbige Kanten werden von Anfang an entfernt. Dadurch entstehen keine
## inneren Restpfade oder Sackgassen durch fehlerhafte Polygon-Vereinigungen.
func _merge_cells(color: String) -> Array:
	var boundary_segments: Array = []
	for i in range(board.points.size()):
		if board.cell_color(i) != color:
			continue
		var poly := voronoi.cell_polygon(i)
		if poly.size() < 3:
			continue
		poly = _ensure_ccw(poly)
		var neighbors := voronoi.edge_neighbors(i)
		for k in range(poly.size()):
			var nb: int = neighbors[k] if k < neighbors.size() else -1
			if nb >= 0 and board.cell_color(nb) == color:
				continue
			var a := poly[k]
			var b := poly[(k + 1) % poly.size()]
			if a.distance_squared_to(b) > 0.0001:
				boundary_segments.append([a, b])
	return _chain_boundary_segments(boundary_segments)


## Schliesst die gerichteten Randkanten zu vollstaendigen Konturen. Offene
## Ketten werden verworfen; sie koennen deshalb nie als Sackgasse gezeichnet
## werden. Die Quantisierung verbindet Umkreismittelpunkte mit minimalen
## float32-Abweichungen sicher.
func _chain_boundary_segments(segments: Array) -> Array:
	var outgoing := {}
	for segment in segments:
		var a: Vector2 = segment[0]
		var b: Vector2 = segment[1]
		var from_key := _boundary_key(a)
		var to_key := _boundary_key(b)
		if from_key == to_key:
			continue
		if not outgoing.has(from_key):
			outgoing[from_key] = []
		outgoing[from_key].append({"to": to_key, "from": a, "end": b})

	# Ganzzahlige Schluessel statt Text: bei vielen Zellen ist das der
	# groesste Unterschied in der Konturberechnung.
	var paths: Array = []
	var used := {}
	for from_key in outgoing:
		for edge_index in range(outgoing[from_key].size()):
			var edge_id := Vector3i(from_key.x, from_key.y, edge_index)
			if used.has(edge_id):
				continue
			var path := PackedVector2Array()
			var start_key: Vector2i = from_key
			var current_key: Vector2i = from_key
			var previous_direction := Vector2.ZERO
			var closed := false
			while true:
				var choices: Array = outgoing.get(current_key, [])
				var choice_index := -1
				for candidate_index in range(choices.size()):
					var candidate_id := Vector3i(current_key.x, current_key.y, candidate_index)
					if used.has(candidate_id):
						continue
					if choice_index < 0:
						choice_index = candidate_index
						continue
					# An Kreuzungen folgt die Kontur der geringsten Drehung.
					var candidate: Dictionary = choices[candidate_index]
					var selected: Dictionary = choices[choice_index]
					var candidate_turn := _positive_turn(previous_direction,
						candidate["end"] - candidate["from"])
					var selected_turn := _positive_turn(previous_direction,
						selected["end"] - selected["from"])
					if candidate_turn < selected_turn:
						choice_index = candidate_index
				if choice_index < 0:
					break
				var chosen_id := Vector3i(current_key.x, current_key.y, choice_index)
				used[chosen_id] = true
				var chosen: Dictionary = choices[choice_index]
				path.append(chosen["from"])
				previous_direction = chosen["end"] - chosen["from"]
				current_key = chosen["to"]
				if current_key == start_key:
					closed = true
					break
				if path.size() > segments.size():
					break
			if closed:
				path = BoardGeometry.simplify_polygon(path)
				if path.size() >= 3 and absf(BoardGeometry.signed_polygon_area(path)) > 0.5:
					paths.append(path)
	return paths


static func _boundary_key(point: Vector2) -> Vector2i:
	return Vector2i(roundi(point.x * 100.0), roundi(point.y * 100.0))


static func _positive_turn(previous: Vector2, next: Vector2) -> float:
	if previous.length_squared() < 1e-9 or next.length_squared() < 1e-9:
		return 0.0
	var angle := previous.angle_to(next)
	return angle + TAU if angle < 0.0 else angle

## Zellflaeche auf die Fuellgrenze ihres Territoriums beschneiden. So liegen
## die Zellfarben innerhalb der Frontlinie.
func _clip_to_territory(index: int, poly: PackedVector2Array) -> Array:
	var clips: Array = _territory_clip.get(board.cell_color(index), [])
	if clips.is_empty():
		return [poly]
	var out: Array = []
	for clip in clips:
		for part in Geometry2D.intersect_polygons(poly, clip):
			if part.size() >= 3 and absf(BoardGeometry.signed_polygon_area(part)) > 0.5 \
				and not Geometry2D.triangulate_polygon(part).is_empty():
				out.append(part)
	if out.is_empty():
		return [poly]
	return out


## Fuellt ein Polygon als Dreiecksliste. Robuster als draw_colored_polygon:
## beschnittene Flaechen koennen einspringende Ecken haben, die Godot sonst
## nicht triangulieren kann; ein misslungenes Polygon wird einfach ausgelassen.
func _fill_polygon(points: PackedVector2Array, color: Color) -> void:
	if points.size() < 3 or absf(BoardGeometry.signed_polygon_area(points)) <= 0.5:
		return
	var indices := Geometry2D.triangulate_polygon(points)
	if indices.size() < 3:
		return
	var colors := PackedColorArray([color, color, color])
	var triangle := PackedVector2Array()
	triangle.resize(3)
	var i := 0
	while i + 2 < indices.size():
		triangle[0] = points[indices[i]]
		triangle[1] = points[indices[i + 1]]
		triangle[2] = points[indices[i + 2]]
		draw_primitive(triangle, colors, _uvs3)
		i += 3


## Fuellt einen Faecher um `center` (Dreiecke zu den aufeinanderfolgenden
## Punkten von `arc`). Fuer die beim Abrunden abgeschnittenen Eckstuecke.
func _fill_fan(center: Vector2, arc: PackedVector2Array, color: Color) -> void:
	var colors := PackedColorArray([color, color, color])
	for i in range(arc.size() - 1):
		draw_primitive(PackedVector2Array([center, arc[i], arc[i + 1]]), colors, _uvs3)


## Uebernahme-Warnung: die gezogene Zelle blinkt.
func _draw_takeover_blink(shapes: Array) -> void:
	if board.drag_blink <= 0.0:
		return
	var index := board.dragged_index
	if index < 0 or index >= shapes.size() or shapes[index] == null:
		return
	var color := Color(GameConfig.BLINK_COLOR, GameConfig.BLINK_ALPHA * clampf(board.drag_blink, 0.0, 1.0))
	for part in shapes[index]:
		_fill_polygon(part, color)


## Rundet die konvexen Ecken eines geschlossenen Polygons: die Ecke wird durch
## einen Bogen aus Stuetzpunkten ersetzt. Zurueck kommen der gerundete Pfad und
## die abgeschnittenen Eckstuecke (Eckpunkt + Bogen).
func _fillet_with_cuts(poly: PackedVector2Array, radius: float) -> Dictionary:
	var path := PackedVector2Array()
	var cuts: Array = []
	var count := poly.size()
	if radius <= 0.01 or count < 3:
		return {"path": poly, "cuts": cuts}
	var ccw := BoardGeometry.signed_polygon_area(poly) > 0.0
	for k in range(count):
		var v := poly[k]
		var to_prev := poly[(k - 1 + count) % count] - v
		var to_next := poly[(k + 1) % count] - v
		var len_prev := to_prev.length()
		var len_next := to_next.length()
		if len_prev < 1e-3 or len_next < 1e-3:
			path.append(v)
			continue
		var cross := to_prev.cross(to_next)
		if (cross < 0.0) != ccw or absf(cross) < 1e-6:
			path.append(v)
			continue
		var trim := minf(radius, minf(len_prev, len_next) * 0.45)
		if trim <= 0.01:
			path.append(v)
			continue
		var start := v + (to_prev / len_prev) * trim
		var finish := v + (to_next / len_next) * trim
		var steps := _arc_steps(trim, to_prev.angle_to(to_next))
		var arc := PackedVector2Array()
		arc.resize(steps + 1)
		for s in range(steps + 1):
			arc[s] = _quadratic(start, v, finish, float(s) / float(steps))
		path.append_array(arc)
		cuts.append({"vertex": v, "arc": arc})
	return {"path": path, "cuts": cuts}


## Dreht ein Polygon auf die positive Windung, damit die Clipper-Aufrufe
## Flaechen und keine Loecher sehen.
static func _ensure_ccw(poly: PackedVector2Array) -> PackedVector2Array:
	if BoardGeometry.signed_polygon_area(poly) >= 0.0:
		return poly
	var out := PackedVector2Array()
	out.resize(poly.size())
	for i in range(poly.size()):
		out[i] = poly[poly.size() - 1 - i]
	return out


static func _quadratic(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return a * u * u + b * 2.0 * u * t + c * t * t


## Weisse Umrandung der Zelle unter dem Mauszeiger: gerundet wie die
## Zellgrenzen, in der Dicke der duennen Linie. Sie liegt ueber allen Rahmen.
func _draw_hover_outline() -> void:
	var index := board.hovered_index
	if index < 0 or index >= voronoi.cells.size():
		return
	var poly := voronoi.cell_polygon(index)
	if poly.size() < 3:
		return
	var path := _rounded_outline(_to_screen_polygon(poly),
		config.corner_radius * view_transform.scale)
	if path.size() < 3:
		return
	path.append(path[0])
	draw_polyline(path, Color(GameConfig.POINT_HOVER_COLOR),
		GameConfig.SAME_COLOR_FRAME_WIDTH * view_transform.scale, true)


## Gerundeter geschlossener Pfad eines Polygons: gerade Kanten mit
## abgerundeten konvexen Ecken (ohne Versatz, fuer die Hover-Umrandung).
func _rounded_outline(poly: PackedVector2Array, radius: float) -> PackedVector2Array:
	var count := poly.size()
	var is_front: Array = []
	is_front.resize(count)
	for k in range(count):
		is_front[k] = false
	var corners := _cell_corners(poly, is_front, _inward_normals(poly), radius, 0.0)
	var path := PackedVector2Array()
	for k in range(count):
		if corners.has(k):
			var arc: PackedVector2Array = corners[k]["arc"]
			path.append_array(arc)
		else:
			path.append(poly[k])
	return path


## Zellfuellung (Fensterkoordinaten) mit Abstand zu allen Zellrahmen.
## Dadurch bleibt die graue Rahmen- bzw. Hintergrundfarbe zwischen benachbarten
## Zellen sichtbar. Die Territoriumsfront wird danach zusaetzlich geclippt.
func _fill_outline(index: int, screen_poly: PackedVector2Array, line_scale: float) -> PackedVector2Array:
	var count := screen_poly.size()
	var radius := config.corner_radius * line_scale
	if count < 3:
		return screen_poly
	var path := _rounded_outline(screen_poly, radius) if radius > 0.01 else screen_poly
	var gap := GameConfig.SAME_COLOR_FRAME_WIDTH * line_scale * 0.5
	if gap <= 0.01:
		return path
	var join := Geometry2D.JOIN_ROUND if radius > 0.01 else Geometry2D.JOIN_MITER
	var inset := Geometry2D.offset_polygon(path, -gap, join)
	if inset.is_empty():
		return path
	return BoardGeometry.largest_polygon(inset)


## Relative Einflusswerte zuletzt, damit sie weder Rahmen noch Punkte ueberdecken.
func _draw_cell_labels() -> void:
	var text_size := _text_size()
	var text_offset := (_font.get_ascent(text_size) - _font.get_descent(text_size)) * 0.5
	var point_radius := GameConfig.POINT_RADIUS * view_transform.scale
	var focus := board.dragged_index if board.dragged_index >= 0 else board.hovered_index
	if focus < 0 or focus >= voronoi.real_count:
		return
	var geometry := CellGeometry.from_voronoi(voronoi, true)
	var ids := board.color_ids()
	var focus_poly := voronoi.cell_polygon(focus)
	if focus_poly.size() >= 3:
		var total := Territories.relative_neighbor_total(geometry, ids, focus)
		_draw_relative_label(focus, total, focus_poly, text_size, text_offset, point_radius)
	for neighbor in geometry.neighbors[focus]:
		var value := Territories.relative_neighbor_value(geometry, ids, focus, neighbor)
		if is_zero_approx(value):
			continue
		var poly := voronoi.cell_polygon(neighbor)
		if poly.size() < 3:
			continue
		_draw_neighbor_relative_label(focus, neighbor, value, poly, text_size, text_offset, point_radius)


func _draw_relative_label(index: int, value: float, poly: PackedVector2Array,
		text_size: int, text_offset: float, point_radius: float) -> void:
	var centroid := _to_screen(BoardGeometry.polygon_centroid(poly))
	var point := _to_screen(board.points[index])
	var min_distance := point_radius + text_size * 0.55
	if centroid.distance_to(point) < min_distance:
		centroid.y += min_distance - centroid.distance_to(point) + text_size * 0.35
	var scaled := BoardGeometry.js_round(value)
	if scaled == 0:
		return
	var label := ("+" if scaled > 0 else "") + str(scaled)
	_draw_centered_label_text(centroid, label, text_size, text_offset, Color.BLACK)


## Zeichnet den Wert einer groesseren Nachbarzelle direkt an ihrer gemeinsamen
## Grenze. Der kleine Versatz zeigt auf die Seite der groesseren Zelle.
func _draw_neighbor_relative_label(focus: int, neighbor: int, value: float,
		poly: PackedVector2Array, text_size: int, text_offset: float, point_radius: float) -> void:
	var edge := _shared_edge(focus, neighbor)
	if edge.size() < 2:
		return
	var start: Vector2 = edge[0]
	var end: Vector2 = edge[1]
	var midpoint := (_to_screen(start) + _to_screen(end)) * 0.5
	var toward_neighbor := _to_screen(board.points[neighbor]) - midpoint
	if toward_neighbor.length_squared() < 0.0001:
		toward_neighbor = Vector2.UP
	else:
		toward_neighbor = toward_neighbor.normalized()
	var position := midpoint + toward_neighbor * maxf(4.0, text_size * 0.6)
	var scaled := BoardGeometry.js_round(value)
	if scaled == 0:
		return
	var label := ("+" if scaled > 0 else "") + str(scaled)
	_draw_rounded_label(position, label, text_size, text_offset, Color.WHITE,
		Color(board.cell_color(neighbor)))


func _draw_centered_label_text(center: Vector2, label: String, text_size: int,
		text_offset: float, color: Color) -> void:
	var text_width := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, text_size).x
	draw_string(_font, Vector2(center.x - text_width * 0.5, center.y + text_offset), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, text_size, color)


func _draw_rounded_label(center: Vector2, label: String, text_size: int,
		text_offset: float, background: Color, text_color: Color) -> void:
	var text_width := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, text_size).x
	var size := Vector2(text_width + text_size * 1.1, text_size * 1.7)
	var style := StyleBoxFlat.new()
	style.bg_color = background
	var radius := int(round(text_size * 0.35))
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.corner_detail = 4
	style.anti_aliasing = true
	style.anti_aliasing_size = 1.0
	draw_style_box(style, Rect2(center - size * 0.5, size))
	_draw_centered_label_text(center, label, text_size, text_offset, text_color)


## Liefert die laengste gemeinsame Kante zweier Voronoi-Zellen.
func _shared_edge(first: int, second: int) -> PackedVector2Array:
	var poly := voronoi.cell_polygon(first)
	var neighbors := voronoi.edge_neighbors(first)
	var best := PackedVector2Array()
	var best_length := 0.0
	for k in range(poly.size()):
		var neighbor := neighbors[k] if k < neighbors.size() else -1
		if neighbor != second:
			continue
		var start := poly[k]
		var end := poly[(k + 1) % poly.size()]
		var length := start.distance_to(end)
		if length > best_length:
			best_length = length
			best = PackedVector2Array([start, end])
	var threshold := config.boundary_label_threshold if config != null else 0.0
	if best_length < threshold:
		return PackedVector2Array()
	return best


func _draw_points() -> void:
	var radius := GameConfig.POINT_RADIUS * view_transform.scale
	for i in range(board.points.size()):
		var color := Color.BLACK
		if i == board.hovered_index:
			color = Color(GameConfig.POINT_HOVER_COLOR)
		elif config.alternating_moves and board.cell_color(i) != board.active_color:
			color = Color(0.5, 0.5, 0.5)
		draw_circle(_to_screen(board.points[i]), radius, color, true, -1.0, true)


## Linien zum groessten gleichen bzw. gegnerischen Nachbarn. Die Linie zum
## Gegner bleibt bei der Warnung konstant sichtbar.
func _draw_drag_lines() -> void:
	var dragged := board.dragged_index
	if dragged < 0 or dragged >= board.points.size():
		return
	var line_scale := view_transform.scale
	var origin := _to_screen(board.points[dragged])
	var my_area := voronoi.area(dragged)

	if board.drag_same_neighbor >= 0 and board.drag_same_neighbor_area > my_area:
		draw_line(origin, _to_screen(board.points[board.drag_same_neighbor]), Color.BLACK, 2.0 * line_scale, true)

	# Die groesste angrenzende Gegnerzelle wird immer verbunden. Die Linie
	# dient als Orientierung und blinkt nicht mehr mit der Warnung.
	if board.drag_opponent_neighbor >= 0:
		var thickness := 0.5
		if board.drag_same_neighbor_area > 0.0:
			var ratio := board.drag_opponent_neighbor_area / board.drag_same_neighbor_area
			thickness = 0.5 + 2.0 * minf(ratio, 1.0)
		draw_line(origin, _to_screen(board.points[board.drag_opponent_neighbor]),
			Color(GameConfig.BLINK_COLOR), thickness * line_scale, true)
