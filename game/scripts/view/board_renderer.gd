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
## Schrift fuer die Sieger-Anzeige (Rubik Spray Paint).
var _result_font: Font
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
	_result_font = load("res://assets/RubikSprayPaint-Regular.ttf")
	if _result_font == null:
		_result_font = _font


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
	_draw_stamina_bar(rect1, ratio1, GameConfig.COLOR_PLAYER1, false)
	_draw_stamina_bar(rect2, ratio2, GameConfig.COLOR_PLAYER2, true)


func _draw_stamina_bar(rect: Rect2, ratio: float, color: String, from_right: bool) -> void:
	_draw_rounded_rect(rect, Color(color, 0.2), 4.0)
	if ratio > 0.0:
		var fill_width := rect.size.x * ratio
		var fill_x := rect.position.x
		if from_right:
			fill_x = rect.position.x + rect.size.x - fill_width
		_draw_rounded_rect(Rect2(Vector2(fill_x, rect.position.y), Vector2(fill_width, rect.size.y)), Color(color), 4.0)


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
	var text := "unentschieden"
	var background := Color(GameConfig.BACKGROUND_COLOR)
	if board.winner_color == GameConfig.COLOR_PLAYER1:
		text = "rot hat gewonnen"
		background = Color(GameConfig.COLOR_PLAYER1)
	elif board.winner_color == GameConfig.COLOR_PLAYER2:
		text = "blau hat gewonnen"
		background = Color(GameConfig.COLOR_PLAYER2)
	_draw_result_popup(viewport_size * 0.5, text, background)


func _draw_result_popup(center: Vector2, label: String, background: Color) -> void:
	var text_size := 48
	var font := _result_font
	var text_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, text_size).x
	var size := Vector2(text_width + text_size * 1.4, text_size * 1.9)
	_draw_rounded_rect(Rect2(center - size * 0.5, size), background, 18.0)
	var text_offset := (font.get_ascent(text_size) - font.get_descent(text_size)) * 0.5
	draw_string(font, Vector2(center.x - text_width * 0.5, center.y + text_offset), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, text_size, Color.BLACK)


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


## Flows zuletzt, damit sie weder Rahmen noch Punkte ueberdecken. Die Linien
## liegen auf den Mittelpunkten der gemeinsamen Zellgrenzen und laufen als
## weiche Kurve durch diese Punkte. Linien und Zellwert gibt es nur fuer die
## Hover-/Drag-Zelle; "Flows fuer alle Zellen" blendet zusaetzlich an jeder
## Grenze den vererbten Wert ein.
func _draw_flows() -> void:
	if voronoi.real_count <= 0:
		return
	var geometry := CellGeometry.from_voronoi(voronoi, true)
	var ids := board.color_ids()
	var roots := Influence.resolve_roots(geometry, ids, board.influence_roots())
	var flows := {
		1: Influence.flow(geometry, roots[0]),
		2: Influence.flow(geometry, roots[1]),
	}
	var text_size := _text_size()
	var text_offset := (_font.get_ascent(text_size) - _font.get_descent(text_size)) * 0.5
	var point_radius := config.point_radius * view_transform.scale
	var focus := board.dragged_index if board.dragged_index >= 0 else board.hovered_index
	if focus >= 0 and focus < voronoi.real_count:
		_draw_focus_flow(focus, geometry, ids, roots, flows)
		_draw_focus_value(focus, geometry, ids, roots, flows, text_size, text_offset, point_radius)
	if config.show_all_flows:
		_draw_inherited_labels(geometry, ids, flows, text_size, text_offset, point_radius)


## Flow-Linien der Hover-/Drag-Zelle: eigener Weg zur eigenen groessten Zelle
## und, bei einer gegnerischen Front, der Weg der Gegenseite.
func _draw_focus_flow(focus: int, geometry: CellGeometry, ids: PackedByteArray,
		roots: PackedInt32Array, flows: Dictionary) -> void:
	var own_id := int(ids[focus]) if focus < ids.size() else 0
	if own_id == 0:
		return
	var routes := {}
	var own_root: int = roots[own_id - 1]
	if own_root >= 0:
		var chain := _chain_to_root(flows[own_id]["parents"], own_root, focus)
		if chain.size() >= 2:
			routes[_route_key(chain)] = {"cells": chain, "color": own_id}
	if _has_enemy_front(geometry, ids, focus):
		var enemy_id := 2 if own_id == 1 else 1
		var enemy_root: int = roots[enemy_id - 1]
		if enemy_root >= 0:
			var enemy_chain := _enemy_chain(geometry, ids, flows[enemy_id], enemy_root, focus, enemy_id)
			if enemy_chain.size() >= 2:
				routes[_route_key(enemy_chain)] = {"cells": enemy_chain, "color": enemy_id}
	_draw_flow_routes(routes, maxf(1.5, 2.0 * view_transform.scale))


## Wert der Hover-/Drag-Zelle: eigene Staerke plus gegnerischer Druck.
func _draw_focus_value(focus: int, geometry: CellGeometry, ids: PackedByteArray,
		roots: PackedInt32Array, flows: Dictionary, text_size: int, text_offset: float,
		point_radius: float) -> void:
	var own_id := int(ids[focus]) if focus < ids.size() else 0
	if own_id == 0:
		return
	var own_strengths: PackedFloat32Array = flows[own_id]["strengths"]
	var value := own_strengths[focus] * (-1.0 if own_id == 2 else 1.0)
	if _has_enemy_front(geometry, ids, focus):
		var enemy_id := 2 if own_id == 1 else 1
		var enemy_strengths: PackedFloat32Array = flows[enemy_id]["strengths"]
		value += enemy_strengths[focus] * (-1.0 if enemy_id == 2 else 1.0)
	var poly := voronoi.cell_polygon(focus)
	if poly.size() < 3:
		return
	var center := _to_screen(BoardGeometry.polygon_centroid(poly))
	center = _move_label_away_from_point(center, _to_screen(board.points[focus]),
		point_radius + text_size * 0.9)
	_draw_centered_label_text(center, str(BoardGeometry.js_round(value)),
		text_size, text_offset, Color.BLACK)


## "Flows fuer alle Zellen": an jeder Grenze steht der Wert, den die Zelle von
## ihrer Elternzelle geerbt hat. Das gilt fuer alle Zellen, nicht nur fuer die
## Hover-Zelle.
func _draw_inherited_labels(geometry: CellGeometry, ids: PackedByteArray, flows: Dictionary,
		text_size: int, text_offset: float, point_radius: float) -> void:
	for i in range(mini(geometry.count(), ids.size())):
		var id := int(ids[i])
		if id == 0:
			continue
		var flow: Dictionary = flows[id]
		var parents: PackedInt32Array = flow["parents"]
		var strengths: PackedFloat32Array = flow["strengths"]
		var parent := parents[i]
		if parent < 0 or strengths[i] <= 0.0:
			continue
		var scaled := BoardGeometry.js_round(strengths[i] * (-1.0 if id == 2 else 1.0))
		if scaled == 0:
			continue
		var label := ("+" if scaled > 0 else "") + str(scaled)
		_draw_inherited_label(i, parent, label, text_size, text_offset, point_radius)


## Vererbter Wert an der gemeinsamen Grenze, leicht zur Kindzelle versetzt.
func _draw_inherited_label(child: int, parent: int, label: String, text_size: int,
		text_offset: float, point_radius: float) -> void:
	var midpoint := _to_screen(_boundary_midpoint(child, parent))
	var toward_child := _to_screen(board.points[child]) - midpoint
	if toward_child.length_squared() < 0.0001:
		toward_child = Vector2.UP
	else:
		toward_child = toward_child.normalized()
	var position := midpoint + toward_child * maxf(4.0, text_size * 0.6)
	position = _move_label_away_from_point(position, _to_screen(board.points[child]),
		point_radius + text_size * 0.9)
	_draw_centered_label_text(position, label, text_size, text_offset, Color.BLACK)


## Weg Wurzel -> node ueber die Elternkette. Leer, wenn die Kette die Wurzel
## nicht erreicht.
func _chain_to_root(parents: PackedInt32Array, root: int, node: int) -> PackedInt32Array:
	var chain: Array = []
	var current := node
	var guard := 0
	while current >= 0 and current < parents.size() and guard <= parents.size():
		chain.append(current)
		if current == root:
			break
		current = parents[current]
		guard += 1
	if chain.is_empty() or int(chain[chain.size() - 1]) != root:
		return PackedInt32Array()
	chain.reverse()
	return PackedInt32Array(chain)


## Gegnerischer Weg. Die erste Zelle nach dem Fokus ist ein tatsaechlich
## angrenzender Gegner; erst danach folgt dessen Elternkette zur gegnerischen
## Wurzel. So laeuft der gegnerische Flow nicht ueber gleichfarbige Zellen.
func _enemy_chain(geometry: CellGeometry, ids: PackedByteArray, enemy_flow: Dictionary,
		enemy_root: int, focus: int, enemy_id: int) -> PackedInt32Array:
	var strengths: PackedFloat32Array = enemy_flow["strengths"]
	var best := -1
	var best_value := -1.0
	for neighbor in geometry.neighbors[focus]:
		if neighbor < 0 or neighbor >= ids.size() or int(ids[neighbor]) != enemy_id:
			continue
		var value := strengths[neighbor] if neighbor < strengths.size() else 0.0
		if value > best_value:
			best_value = value
			best = neighbor
	if best < 0:
		return PackedInt32Array()
	var chain := _chain_to_root(enemy_flow["parents"], enemy_root, best)
	if chain.is_empty():
		return PackedInt32Array()
	var out := chain.duplicate()
	out.append(focus)
	return out


func _route_key(cells: PackedInt32Array) -> String:
	var key := ""
	for cell in cells:
		key += str(cell) + ","
	return key


## Grenzt die Zelle an einen andersfarbigen Spieler?
func _has_enemy_front(geometry: CellGeometry, ids: PackedByteArray, cell: int) -> bool:
	if cell < 0 or cell >= ids.size() or ids[cell] == 0:
		return false
	for neighbor in geometry.neighbors[cell]:
		if neighbor >= 0 and neighbor < ids.size() and ids[neighbor] != 0 \
			and ids[neighbor] != ids[cell]:
			return true
	return false


func _draw_flow_routes(routes: Dictionary, width: float) -> void:
	for route in routes.values():
		var cells: PackedInt32Array = route["cells"]
		var color := Color(GameConfig.COLOR_PLAYER1, 0.8) if int(route["color"]) == 1 \
			else Color(GameConfig.COLOR_PLAYER2, 0.8)
		var points := _flow_route_points(cells)
		if points.size() < 2:
			continue
		draw_polyline(_to_screen_polygon(_smooth_flow_path(points)), color, width, true)


## Grenzmittelpunkte entlang einer Zellfolge (Brettkoordinaten).
func _flow_route_points(cells: PackedInt32Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for k in range(cells.size() - 1):
		points.append(_boundary_midpoint(cells[k], cells[k + 1]))
	return points


## Mittelpunkt der gemeinsamen Grenze zweier Zellen.
func _boundary_midpoint(first: int, second: int) -> Vector2:
	var poly := voronoi.cell_polygon(first)
	if poly.size() >= 3:
		var neighbors := voronoi.edge_neighbors(first)
		for k in range(poly.size()):
			if k < neighbors.size() and int(neighbors[k]) == second:
				return (poly[k] + poly[(k + 1) % poly.size()]) * 0.5
	return (board.points[first] + board.points[second]) * 0.5


## Weicher Verlauf durch die Grenzmittelpunkte (Catmull-Rom). So entsteht ein
## runder Flow statt eines Zickzacks.
func _smooth_flow_path(points: PackedVector2Array) -> PackedVector2Array:
	var count := points.size()
	if count < 3:
		return points
	var out := PackedVector2Array()
	var steps := 10
	for i in range(count - 1):
		var p0 := points[maxi(i - 1, 0)]
		var p1 := points[i]
		var p2 := points[i + 1]
		var p3 := points[mini(i + 2, count - 1)]
		for s in range(steps):
			out.append(_catmull_rom(p0, p1, p2, p3, float(s) / float(steps)))
	out.append(points[count - 1])
	return out


static func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (2.0 * p1 + (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


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


## Staerkeueberschuss je Zelle: rot positiv, blau negativ (+100/-100 an den
## Wurzelzellen). Ein Wert nahe null bedeutet, dass der Einfluss beider Spieler
## fast gleich gross ist und die Zelle bald kippt.
func _cell_influence_values(geometry: CellGeometry, ids: PackedByteArray) -> PackedFloat32Array:
	var count := geometry.count()
	var values := PackedFloat32Array()
	values.resize(count)
	values.fill(0.0)
	if count == 0:
		return values
	var roots := Influence.resolve_roots(geometry, ids, board.influence_roots())
	var red_influence: PackedFloat32Array = Influence.flow(geometry, roots[0])["strengths"]
	var blue_influence: PackedFloat32Array = Influence.flow(geometry, roots[1])["strengths"]
	for i in range(count):
		values[i] = clampf(red_influence[i] - blue_influence[i],
			-GameConfig.INFLUENCE_START_STRENGTH, GameConfig.INFLUENCE_START_STRENGTH)
	return values


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
