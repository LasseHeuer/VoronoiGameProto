class_name BoardRenderer
extends Node2D

## Zeichnet das Brett: Zellfuellungen, Flaechen-Text, Rahmen und Punkte.
## Liest nur BoardState, Voronoi und Config.
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
var _cache_fill_gap := -1.0
var _influence_values := PackedFloat32Array()
## UV-Platzhalter fuer draw_primitive (3 Punkte je Dreieck).
var _uvs3 := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])


func _ready() -> void:
	_font = ThemeDB.fallback_font


func set_board_state(p_board: BoardState, p_config: GameConfig, p_voronoi: Voronoi) -> void:
	board = p_board
	config = p_config
	voronoi = p_voronoi


func _draw() -> void:
	var viewport_size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(GameConfig.BACKGROUND_COLOR), true)
	var board_size := BoardTransform.BOARD_SIZE * view_transform.scale
	draw_rect(Rect2(view_transform.offset, board_size), Color(GameConfig.BACKGROUND_COLOR), true)
	if board == null or config == null or voronoi == null:
		return
	_draw_cells()
	_draw_points()
	_draw_stamina_bars()
	if board.game_over:
		_draw_game_result()
	if config.show_flow:
		_draw_flows()
	elif config.show_all_cell_numbers:
		_draw_all_cell_ratios()
	elif config.show_cell_numbers:
		_draw_cell_labels()


func _to_screen(point: Vector2) -> Vector2:
	return point * view_transform.scale + view_transform.offset


func _to_screen_polygon(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(poly.size())
	for i in range(poly.size()):
		out[i] = _to_screen(poly[i])
	return out


func _draw_stamina_bars() -> void:
	if not config.alternating_moves:
		return
	var viewport_size := get_viewport_rect().size
	var margin := 18.0
	var gap := 20.0
	var bar_width := minf(240.0, maxf(100.0, (viewport_size.x - margin * 2.0 - gap) * 0.5))
	var bar_height := 20.0
	var y := viewport_size.y - margin - bar_height
	var max_stamina := maxf(config.stamina, 1.0)
	var ratio1 := clampf(board.stamina_player1 / max_stamina, 0.0, 1.0)
	var ratio2 := clampf(board.stamina_player2 / max_stamina, 0.0, 1.0)
	var rect1 := Rect2(margin, y, bar_width, bar_height)
	var rect2 := Rect2(viewport_size.x - margin - bar_width, y, bar_width, bar_height)
	_draw_stamina_bar(rect1, ratio1, GameConfig.COLOR_PLAYER1)
	_draw_stamina_bar(rect2, ratio2, GameConfig.COLOR_PLAYER2)


func _draw_stamina_bar(rect: Rect2, ratio: float, color: String) -> void:
	_draw_rounded_rect(rect, Color(color, 0.2), 4.0)
	if ratio > 0.0:
		_draw_rounded_rect(Rect2(rect.position, Vector2(rect.size.x * ratio, rect.size.y)), Color(color), 4.0)


func _draw_rounded_rect(rect: Rect2, color: Color, radius: float) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	var corner := int(round(radius))
	style.corner_radius_top_left = corner
	style.corner_radius_top_right = corner
	style.corner_radius_bottom_left = corner
	style.corner_radius_bottom_right = corner
	style.corner_detail = 4
	style.anti_aliasing = true
	style.anti_aliasing_size = 1.0
	draw_style_box(style, rect)


func _draw_game_result() -> void:
	var viewport_size := get_viewport_rect().size
	var text := "Unentschieden"
	if board.winner_color == GameConfig.COLOR_PLAYER1:
		text = "Spieler 1 gewinnt"
	elif board.winner_color == GameConfig.COLOR_PLAYER2:
		text = "Spieler 2 gewinnt"
	var center := Vector2(viewport_size.x * 0.5, 28.0)
	_draw_rounded_label(center, "Spiel beendet: " + text, 18, 6.0,
		Color("#14171ce8"), Color.WHITE)


func _text_size() -> int:
	return maxi(1, int(round(GameConfig.AREA_TEXT_SIZE * view_transform.scale)))


func _draw_cells() -> void:
	var count := voronoi.cells.size()
	if count == 0:
		return
	var line_scale := view_transform.scale
	_ensure_territories(line_scale)
	_ensure_fill_outlines(line_scale)
	var influence_values := _influence_values

	# 1) Zellflaechen: immer das gueltige Voronoi-Polygon fuellen. Die
	#    Territoriums-Grenze liegt darueber; so bleiben keine Zellen grau, wenn
	#    eine komplexe Clipflaeche nicht triangulierbar ist.
	var shapes: Array = []
	shapes.resize(count)
	for i in range(count):
		var poly := voronoi.cell_polygon(i)
		if poly.size() < 3 or voronoi.area(i) <= 0.01:
			continue
		var screen := _to_screen_polygon(poly)
		var filled: PackedVector2Array = _fill_outlines[i]
		if filled.size() < 3:
			filled = screen
		# Die Zellfuellung bleibt die vollstaendig gerundete Zellform. Die
		# Territoriumskontur wird separat darueber gezeichnet und beschneidet
		# die Flaeche nicht, damit keine eckigen Schnittkanten entstehen.
		var parts := [filled]
		shapes[i] = parts
		for part in parts:
			_fill_polygon(part, Color(_fill_colors[i]))
		if i == board.hovered_index or i == board.dragged_index:
			var focus_color := Color(_fill_colors[i]).lerp(Color.WHITE, 0.2)
			for part in parts:
				_fill_polygon(part, focus_color)
		if highlight_cells.has(i):
			# Klingende Zelle: farbige Ueberlagerung folgt der Tonlautstaerke.
			var play_color := Color(GameConfig.NOTE_PLAY_COLOR)
			play_color.a = GameConfig.NOTE_PLAY_ALPHA * clampf(float(highlight_cells[i]), 0.0, 1.0)
			for part in parts:
				_fill_polygon(part, play_color)

	# 2) Uebernahme-Warnung: Zellen nahe dem Umsprung blinken.
	_draw_takeover_blink(shapes, influence_values)

	# 3) Durchgehende Frontlinie um jedes Territorium.
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
					# Die geglaettete Linie liegt auf beiden Seiten um die halbe
					# Rahmenbreite versetzt direkt an der gemeinsamen Grenze.
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
		and is_equal_approx(config.corner_radius, _cache_fill_radius) \
		and is_equal_approx(config.cell_gap, _cache_fill_gap):
		return
	var count := voronoi.cells.size()
	_influence_values = _cell_influence_values(
		CellGeometry.from_voronoi(voronoi, true), board.color_ids())
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
	_cache_fill_gap = config.cell_gap


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


## Uebernahme-Warnung: Zellen mit nahezu ausgeglichenem Einfluss blinken.
func _draw_takeover_blink(shapes: Array, influence_values: PackedFloat32Array) -> void:
	var threshold := GameConfig.BLINK_VALUE_THRESHOLD
	var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 1000.0 * TAU / GameConfig.BLINK_SLOW_SEC)
	for index in range(shapes.size()):
		if shapes[index] == null or index >= influence_values.size():
			continue
		var value := absf(float(influence_values[index]))
		var near_switch := value <= threshold
		var is_drag_warning := index == board.dragged_index and board.drag_blink > 0.0
		if not near_switch and not is_drag_warning:
			continue
		var proximity := 1.0 - clampf(value / threshold, 0.0, 1.0)
		var intensity := pulse * proximity
		if is_drag_warning:
			intensity = maxf(intensity, board.drag_blink)
		var color := Color(GameConfig.BLINK_COLOR, GameConfig.BLINK_ALPHA * intensity)
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
	var gap := (GameConfig.SAME_COLOR_FRAME_WIDTH * 0.5 + config.cell_gap) * line_scale
	if gap <= 0.01:
		return path
	var join := Geometry2D.JOIN_ROUND if radius > 0.01 else Geometry2D.JOIN_MITER
	var inset := Geometry2D.offset_polygon(path, -gap, join)
	if inset.is_empty():
		return path
	return BoardGeometry.largest_polygon(inset)


## Flows zuletzt, damit sie weder Rahmen noch Punkte ueberdecken.
func _draw_flows() -> void:
	if voronoi.real_count <= 0:
		return
	var geometry := CellGeometry.from_voronoi(voronoi, true)
	var ids := board.color_ids()
	var roots := _flow_roots(geometry, ids)
	var max_edge := _max_flow_edge(geometry)
	var red_flow := _build_influence_flow(geometry, roots["red"], max_edge)
	var blue_flow := _build_influence_flow(geometry, roots["blue"], max_edge)
	var targets: Array = []
	if config.show_all_flows:
		for i in range(voronoi.real_count):
			targets.append(i)
	else:
		var focus := board.dragged_index if board.dragged_index >= 0 else board.hovered_index
		if focus < 0 or focus >= voronoi.real_count:
			return
		targets.append(focus)

	var red_edges := {}
	var blue_edges := {}
	var label_values := PackedFloat32Array()
	label_values.resize(voronoi.real_count)
	label_values.fill(0.0)
	var label_visible := PackedByteArray()
	label_visible.resize(voronoi.real_count)
	label_visible.fill(0)
	for target in targets:
		var own_id := ids[target] if target < ids.size() else 0
		var own_flow: Dictionary = red_flow if own_id == 1 else blue_flow
		var own_root: int = roots["red"] if own_id == 1 else roots["blue"]
		var own_sign := -1.0 if own_id == 2 else 1.0
		if own_root >= 0:
			_collect_flow_path(target, own_flow, red_edges if own_id == 1 else blue_edges,
				label_values, label_visible, not config.show_all_flows, own_sign)
		if _has_enemy_front(geometry, ids, target):
			var enemy_id := 2 if own_id == 1 else 1
			var enemy_flow: Dictionary = red_flow if enemy_id == 1 else blue_flow
			var enemy_root: int = roots["red"] if enemy_id == 1 else roots["blue"]
			if enemy_root >= 0:
				_collect_flow_path(target, enemy_flow,
					red_edges if enemy_id == 1 else blue_edges, label_values, label_visible,
					not config.show_all_flows, -1.0 if enemy_id == 2 else 1.0)
		if config.show_all_flows:
			var own_strengths: PackedFloat32Array = own_flow["strengths"]
			label_values[target] = own_strengths[target] * own_sign if own_root >= 0 else 0.0
			if _has_enemy_front(geometry, ids, target):
				var enemy_strengths: PackedFloat32Array = red_flow["strengths"] if own_id != 1 else blue_flow["strengths"]
				var enemy_sign := -1.0 if own_id != 1 else 1.0
				label_values[target] += enemy_strengths[target] * enemy_sign
			label_visible[target] = 1

	var line_width := maxf(1.5, 2.0 * view_transform.scale)
	_draw_flow_edges(red_edges, Color(GameConfig.COLOR_PLAYER1, 0.8), line_width)
	_draw_flow_edges(blue_edges, Color(GameConfig.COLOR_PLAYER2, 0.8), line_width)
	var text_size := _text_size()
	var text_offset := (_font.get_ascent(text_size) - _font.get_descent(text_size)) * 0.5
	var point_radius := config.point_radius * view_transform.scale
	for i in range(voronoi.real_count):
		if label_visible[i] == 0:
			continue
		var poly := voronoi.cell_polygon(i)
		if poly.size() < 3:
			continue
		var center := _to_screen(BoardGeometry.polygon_centroid(poly))
		center = _move_label_away_from_point(center, _to_screen(board.points[i]),
			point_radius + text_size * 0.9)
		_draw_centered_label_text(center, str(BoardGeometry.js_round(label_values[i])),
			text_size, text_offset, Color.BLACK)


func _flow_roots(geometry: CellGeometry, ids: PackedByteArray) -> Dictionary:
	var red := -1
	var blue := -1
	for i in range(geometry.count()):
		if i >= ids.size():
			continue
		if ids[i] == 1 and (red < 0 or geometry.areas[i] > geometry.areas[red]):
			red = i
		elif ids[i] == 2 and (blue < 0 or geometry.areas[i] > geometry.areas[blue]):
			blue = i
	return {"red": red, "blue": blue}


func _max_flow_edge(geometry: CellGeometry) -> float:
	var max_edge := 0.0
	for lengths in geometry.edge_lengths:
		for edge in lengths.values():
			max_edge = maxf(max_edge, float(edge))
	return maxf(max_edge, 0.001)


func _has_enemy_front(geometry: CellGeometry, ids: PackedByteArray, cell: int) -> bool:
	if cell < 0 or cell >= ids.size() or ids[cell] == 0:
		return false
	for neighbor in geometry.neighbors[cell]:
		if neighbor >= 0 and neighbor < ids.size() and ids[neighbor] != 0 \
			and ids[neighbor] != ids[cell]:
			return true
	return false


func _collect_flow_path(target: int, flow: Dictionary, edges: Dictionary,
		labels: PackedFloat32Array, visible: PackedByteArray, add_labels: bool, sign: float) -> void:
	var parents: PackedInt32Array = flow["parents"]
	var strengths: PackedFloat32Array = flow["strengths"]
	var current := target
	while current >= 0 and current < parents.size():
		if add_labels:
			labels[current] += maxf(strengths[current], 0.0) * sign
			visible[current] = 1
		var parent := parents[current]
		if parent < 0:
			break
		edges[parent * parents.size() + current] = [parent, current]
		current = parent


func _draw_flow_edges(edges: Dictionary, color: Color, width: float) -> void:
	for edge in edges.values():
		var from: int = edge[0]
		var to: int = edge[1]
		draw_line(_to_screen(board.points[from]), _to_screen(board.points[to]), color, width, true)


## Relative Einflusswerte zuletzt, damit sie weder Rahmen noch Punkte ueberdecken.
func _draw_cell_labels() -> void:
	var text_size := _text_size()
	var text_offset := (_font.get_ascent(text_size) - _font.get_descent(text_size)) * 0.5
	var point_radius := config.point_radius * view_transform.scale
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


## Zeigt fuer jede echte Zelle den aufsummierten gegenseitigen Einfluss ihrer
## Nachbarn. Groessere gleichfarbige Nachbarn wirken positiv, groessere
## gegnerische Nachbarn negativ; gemeinsame Grenzlaengen werden einbezogen.
func _draw_all_cell_ratios() -> void:
	if voronoi.real_count <= 0:
		return
	var geometry := CellGeometry.from_voronoi(voronoi, true)
	var ids := board.color_ids()
	var values := _cell_influence_values(geometry, ids)
	var text_size := _text_size()
	var text_offset := (_font.get_ascent(text_size) - _font.get_descent(text_size)) * 0.5
	var point_radius := config.point_radius * view_transform.scale
	for i in range(voronoi.real_count):
		var poly := voronoi.cell_polygon(i)
		if poly.size() < 3:
			continue
		var center := _to_screen(BoardGeometry.polygon_centroid(poly))
		center = _move_label_away_from_point(center, _to_screen(board.points[i]),
			point_radius + text_size * 0.9)
		_draw_centered_label_text(center, str(BoardGeometry.js_round(values[i])), text_size,
			text_offset, Color.BLACK)


## Die groesste rote und blaue Zelle sind die beiden Referenzpunkte (+100/-100).
## Beide Werte werden ueber bekannte Kanten weitergegeben und gegeneinander
## verrechnet. Dadurch liegen umkaempfte Zellen nahe null.
func _cell_influence_values(geometry: CellGeometry, ids: PackedByteArray) -> PackedFloat32Array:
	var count := geometry.count()
	var values := PackedFloat32Array()
	values.resize(count)
	values.fill(0.0)
	if count == 0:
		return values
	var red_root := -1
	var blue_root := -1
	for i in range(count):
		if i >= ids.size():
			continue
		if ids[i] == 1 and (red_root < 0 or geometry.areas[i] > geometry.areas[red_root]):
			red_root = i
		elif ids[i] == 2 and (blue_root < 0 or geometry.areas[i] > geometry.areas[blue_root]):
			blue_root = i
	var max_edge := 0.0
	for lengths in geometry.edge_lengths:
		for edge in lengths.values():
			max_edge = maxf(max_edge, float(edge))
	max_edge = maxf(max_edge, 0.001)
	var red_influence := _propagate_influence(geometry, red_root, max_edge)
	var blue_influence := _propagate_influence(geometry, blue_root, max_edge)
	for i in range(count):
		var red_value := red_influence[i] if red_influence[i] >= 0.0 else 0.0
		var blue_value := blue_influence[i] if blue_influence[i] >= 0.0 else 0.0
		var combined := clampf(red_value - blue_value, -100.0, 100.0)
		if i < ids.size() and ids[i] == 1:
			values[i] = maxf(0.0, combined)
		elif i < ids.size() and ids[i] == 2:
			values[i] = minf(0.0, combined)
		else:
			values[i] = combined
	if red_root >= 0:
		values[red_root] = 100.0
	if blue_root >= 0:
		values[blue_root] = -100.0
	return values


func _build_influence_flow(geometry: CellGeometry, source: int, max_edge: float) -> Dictionary:
	var count := geometry.count()
	var scores := PackedFloat32Array()
	scores.resize(count)
	scores.fill(-1.0)
	var parents := PackedInt32Array()
	parents.resize(count)
	parents.fill(-1)
	if source < 0 or source >= count:
		return {"strengths": scores, "parents": parents}

	# Berechne die kuerzesten gewichteten Wege statt den Einfluss bei jedem
	# Nachbarn erneut zu multiplizieren. Dadurch bleiben auch entfernte Zellen
	# aussagekraeftig; grosse Zellen senken die Wegkosten zusaetzlich.
	var area_sum := 0.0
	for area in geometry.areas:
		area_sum += maxf(float(area), 0.01)
	var average_area := maxf(area_sum / maxf(float(count), 1.0), 0.01)
	var distances := PackedFloat32Array()
	distances.resize(count)
	distances.fill(INF)
	distances[source] = 0.0
	var queue: Array = [[0.0, source]]
	while not queue.is_empty():
		queue.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
		var node: Array = queue.pop_front()
		var current_distance: float = node[0]
		var current: int = node[1]
		if current_distance > distances[current] + 0.000001:
			continue
		for neighbor in geometry.neighbors[current]:
			if neighbor < 0 or neighbor >= count:
				continue
			var edge := float(geometry.edge_lengths[current].get(neighbor, 0.0))
			if edge <= 0.0:
				continue
			var edge_strength := lerpf(0.75, 1.0, clampf(edge / max_edge, 0.0, 1.0))
			var area_strength := sqrt(maxf(float(geometry.areas[neighbor]), 0.01) / average_area)
			area_strength = clampf(area_strength, 0.75, 1.35)
			var cost := (1.0 / edge_strength) / area_strength
			var candidate := current_distance + cost
			if candidate < distances[neighbor]:
				distances[neighbor] = candidate
				parents[neighbor] = current
				queue.append([candidate, neighbor])

	var max_distance := 0.0
	for distance in distances:
		if distance < INF * 0.5:
			max_distance = maxf(max_distance, float(distance))
	for i in range(count):
		if distances[i] >= INF * 0.5:
			continue
		var normalized := distances[i] / maxf(max_distance, 0.000001)
		scores[i] = lerpf(100.0, 35.0, clampf(normalized, 0.0, 1.0))
	return {"strengths": scores, "parents": parents}


func _propagate_influence(geometry: CellGeometry, source: int, max_edge: float) -> PackedFloat32Array:
	return _build_influence_flow(geometry, source, max_edge)["strengths"]


func _draw_relative_label(index: int, value: float, poly: PackedVector2Array,
		text_size: int, text_offset: float, point_radius: float) -> void:
	var centroid := _to_screen(BoardGeometry.polygon_centroid(poly))
	var point := _to_screen(board.points[index])
	centroid = _move_label_away_from_point(centroid, point, point_radius + text_size * 0.9)
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
	position = _move_label_away_from_point(position, _to_screen(board.points[neighbor]),
		point_radius + text_size * 0.9)
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


func _move_label_away_from_point(center: Vector2, point: Vector2, min_distance: float) -> Vector2:
	var delta := center - point
	if delta.length_squared() >= min_distance * min_distance:
		return center
	var direction := Vector2.UP if delta.length_squared() < 0.0001 else delta.normalized()
	return point + direction * min_distance


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
	var radius := config.point_radius * view_transform.scale
	for i in range(board.points.size()):
		var color := Color.BLACK
		if i == board.hovered_index:
			color = Color(GameConfig.POINT_HOVER_COLOR)
		elif config.alternating_moves and board.cell_color(i) != board.active_color:
			color = Color(0.5, 0.5, 0.5)
		draw_circle(_to_screen(board.points[i]), radius, color, true, -1.0, true)
