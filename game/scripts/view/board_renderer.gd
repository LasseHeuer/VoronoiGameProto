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
var _cache_empty_color := ""
var _cache_strength := -1.0
## Gerundete Zellfuellungen (Fensterkoordinaten), einmal je Geometrie.
var _fill_outlines: Array = []
var _cache_fill_voronoi: Voronoi = null
var _cache_fill_colors := PackedStringArray()
var _cache_fill_scale := -1.0
var _cache_fill_offset := Vector2.ZERO
var _cache_fill_radius := -1.0
var _cache_fill_gap := -1.0
var _cache_fill_empty_color := ""
var _cache_fill_strength := -1.0
var _signed_values := PackedFloat32Array()
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
	_draw_stamina_bars()
	if config.show_flow:
		_draw_flows()
	if config.show_all_cell_numbers:
		_draw_all_cell_values()
	elif config.show_cell_numbers:
		_draw_cell_labels()
	# Punkte liegen ueber Pfeilen und Texten, das Popup darueber.
	_draw_points()
	if board.game_over:
		_draw_game_result()


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
	# Zuerst die Zellwerte und Fuellfarben: die Frontlinien brauchen die
	# Neutral-Erkennung aus denselben Werten.
	_ensure_fill_outlines(line_scale)
	_ensure_territories(line_scale)

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

	# 2) Uebernahme-Warnung: nur die gezogene, gefaehrdete Zelle blinkt.
	_draw_takeover_blink(shapes)

	# 3) Durchgehende Frontlinie um jedes Territorium.
	_draw_territory_lines(line_scale)


## Fuellfarbe jeder Zelle: kontinuierlicher Verlauf durch die drei definierten
## Farbstufen des jeweiligen Spielers. Zellen ohne Spielerfarbe oder mit zu
## geringem Zellwert werden im einstellbaren Neutralgrau gezeichnet.
func _cell_fill_colors(count: int) -> PackedStringArray:
	var colors := PackedStringArray()
	colors.resize(count)
	var step_colors := _cell_step_colors(count)
	for i in range(count):
		if _is_neutral(i):
			colors[i] = config.cell_empty_color
		else:
			colors[i] = step_colors[i] if step_colors[i] != "" else config.cell_empty_color
	return colors


## Farbverlauf je Zelle: die groesste Zelle bekommt Landmarke 1. Alle weiteren
## Zellen werden zwischen Landmarke 2 (zweitgroesste) und 3 (kleinste) im
## RGB-Raum fliessend interpoliert. Neutrale Zellen zaehlen nicht mit.
func _cell_step_colors(count: int) -> PackedStringArray:
	var out := PackedStringArray()
	out.resize(count)
	for player in [GameConfig.COLOR_PLAYER1, GameConfig.COLOR_PLAYER2]:
		var palette: Array = GameConfig.step_colors_for(player)
		var indices: Array = []
		for i in range(count):
			if board.cell_color(i) == player and not _is_neutral(i):
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
	_cache_empty_color = config.cell_empty_color
	_cache_strength = config.influence_start_strength


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
		and is_equal_approx(config.cell_gap, _cache_fill_gap) \
		and config.cell_empty_color == _cache_fill_empty_color \
		and is_equal_approx(config.influence_start_strength, _cache_fill_strength):
		return
	var count := voronoi.cells.size()
	var geometry := CellGeometry.from_voronoi(voronoi, true)
	_signed_values = Influence.cell_values(geometry, board.color_ids(),
		board.influence_roots(), config.influence_start_strength)
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
	_cache_fill_empty_color = config.cell_empty_color
	_cache_fill_strength = config.influence_start_strength


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
		and is_equal_approx(config.corner_radius, _cache_radius) \
		and config.cell_empty_color == _cache_empty_color \
		and is_equal_approx(config.influence_start_strength, _cache_strength)


## Aussenkonturen der Zellflaechen einer Farbe (Brettkoordinaten).
## Gleichfarbige Kanten werden von Anfang an entfernt. Dadurch entstehen keine
## inneren Restpfade oder Sackgassen durch fehlerhafte Polygon-Vereinigungen.
## Neutrale (graue) Zellen zaehlen nicht zum Territorium: die Frontlinie laeuft
## nur um die tatsaechlich in Spielerfarbe gezeichneten Zellen.
func _merge_cells(color: String) -> Array:
	var boundary_segments: Array = []
	for i in range(board.points.size()):
		if board.cell_color(i) != color or _is_neutral(i):
			continue
		var poly := voronoi.cell_polygon(i)
		if poly.size() < 3:
			continue
		poly = _ensure_ccw(poly)
		var neighbors := voronoi.edge_neighbors(i)
		for k in range(poly.size()):
			var nb: int = neighbors[k] if k < neighbors.size() else -1
			if nb >= 0 and board.cell_color(nb) == color and not _is_neutral(nb):
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


## Uebernahme-Warnung: nur die gezogene Zelle blinkt, wenn ein Farbverlust
## droht. Kleine Zellwerte loesen kein Blinken mehr aus.
func _draw_takeover_blink(shapes: Array) -> void:
	if board.drag_blink <= 0.0:
		return
	var index := board.dragged_index
	if index < 0 or index >= shapes.size() or shapes[index] == null:
		return
	var color := Color(GameConfig.BLINK_COLOR, GameConfig.BLINK_ALPHA * board.drag_blink)
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


## Kraftfeld: an jeder Grenze zeigt ein Pfeil in der Spielerfarbe der groesseren
## Zelle zur kleineren; auf dem Pfeil steht die Fliessmenge dieser Kante in
## Weiss. Die Richtung wird - wie im Kraftfeld - ueber die gerundeten
## Groessenstufen bestimmt. Kanten ohne Fluss (Fliessmenge 0) werden weder als
## Pfeil noch als Zahl angezeigt.
func _draw_flows() -> void:
	if voronoi.real_count <= 0:
		return
	var geometry := CellGeometry.from_voronoi(voronoi, true)
	var count := geometry.count()
	var field := Influence.distribute(geometry, board.color_ids(), board.influence_roots(),
		config.influence_start_strength)
	var edges: Dictionary = field["edges"]
	var keys := Influence.size_keys(geometry)
	# Groesster Fluss des Feldes als Bezug: grosse Werte bekommen breite, lange
	# Pfeile, kleine Werte kurze, schmale Pfeile.
	var max_magnitude := 0.0
	for value in edges.values():
		max_magnitude = maxf(max_magnitude, absf(float(value)))
	if max_magnitude <= 0.0:
		return
	var max_width := maxf(0.5, config.flow_arrow_width) * view_transform.scale
	var max_length := maxf(2.0, config.flow_arrow_length) * view_transform.scale
	var text_size := maxi(1, int(round(config.flow_label_size * view_transform.scale)))
	var text_offset := (_font.get_ascent(text_size) - _font.get_descent(text_size)) * 0.5
	for i in range(count):
		if voronoi.cell_polygon(i).size() < 3:
			continue
		var arrow_color := _flow_arrow_color(i)
		for neighbor in geometry.neighbors[i]:
			if neighbor < 0 or neighbor >= count:
				continue
			if not Influence.is_smaller(keys, neighbor, i):
				continue
			var share := float(edges.get(i * count + neighbor, 0.0))
			if is_zero_approx(share):
				# Nichts vererbt: kein Pfeil und keine Zahl.
				continue
			var midpoint := _boundary_midpoint(i, neighbor)
			if not midpoint.is_finite():
				continue
			var direction := board.points[neighbor] - board.points[i]
			if direction.length_squared() < 0.0001:
				continue
			direction = direction.normalized()
			var weight := clampf(absf(share) / max_magnitude, 0.0, 1.0)
			var scale_factor := lerpf(0.3, 1.0, weight)
			var center := _to_screen(midpoint)
			_draw_arrow(center, direction, max_width * scale_factor,
				max_length * scale_factor, arrow_color)
			_draw_edge_flow_label(center, share, text_size, text_offset)


## Pfeilfarbe: die Spielerfarbe der Zelle, von der der Fluss ausgeht. Neutrale
## Zellen (ohne Farbe) bekommen den neutralen Grauton.
func _flow_arrow_color(cell: int) -> Color:
	var color := board.cell_color(cell)
	if color == "":
		return Color(config.cell_empty_color)
	return Color(color)


## Pfeil mit Schaft und gefuelltem Dreieckskopf, zentriert auf `center`.
func _draw_arrow(center: Vector2, direction: Vector2, width: float, length: float,
		color: Color) -> void:
	var tip := center + direction * length * 0.5
	var tail := center - direction * length * 0.5
	var head := clampf(length * 0.45, width * 2.0, length * 0.7)
	var base := tip - direction * head
	var side := direction.orthogonal() * (head * 0.42)
	draw_line(tail, base, color, width, true)
	draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), color)


## Fliessmenge an der Kante, mittig auf dem Pfeil in weisser Schrift.
func _draw_edge_flow_label(center: Vector2, value: float, text_size: int,
		text_offset: float) -> void:
	var label := str(BoardGeometry.js_round(value))
	var text_width := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, text_size).x
	var position := Vector2(center.x - text_width * 0.5, center.y + text_offset)
	draw_string(_font, position, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, text_size,
		Color(1.0, 1.0, 1.0))


## Mittelpunkt der gemeinsamen Grenze zweier Zellen (INF, wenn keine Kante).
func _boundary_midpoint(first: int, second: int) -> Vector2:
	var poly := voronoi.cell_polygon(first)
	if poly.size() >= 3:
		var neighbors := voronoi.edge_neighbors(first)
		for k in range(poly.size()):
			if k < neighbors.size() and int(neighbors[k]) == second:
				return (poly[k] + poly[(k + 1) % poly.size()]) * 0.5
	return Vector2.INF


## Zellwerte der Hover-/Drag-Zelle und ihrer Nachbarn.
func _draw_cell_labels() -> void:
	var text_size := _text_size()
	var text_offset := (_font.get_ascent(text_size) - _font.get_descent(text_size)) * 0.5
	var point_radius := config.point_radius * view_transform.scale
	var focus := board.dragged_index if board.dragged_index >= 0 else board.hovered_index
	if focus < 0 or focus >= voronoi.real_count:
		return
	var geometry := CellGeometry.from_voronoi(voronoi, true)
	var values := _cell_values(geometry)
	var focus_poly := voronoi.cell_polygon(focus)
	if focus_poly.size() >= 3 and focus < values.size() and not is_zero_approx(values[focus]):
		_draw_value_label(focus, values[focus], focus_poly, text_size, text_offset, point_radius)
	for neighbor in geometry.neighbors[focus]:
		if neighbor < 0 or neighbor >= values.size() or is_zero_approx(values[neighbor]):
			continue
		var poly := voronoi.cell_polygon(neighbor)
		if poly.size() < 3:
			continue
		_draw_neighbor_value_label(focus, neighbor, values[neighbor], poly, text_size, text_offset, point_radius)


## Zeigt fuer jede echte Zelle ihren Flusswert (rot positiv, blau negativ).
func _draw_all_cell_values() -> void:
	if voronoi.real_count <= 0:
		return
	var geometry := CellGeometry.from_voronoi(voronoi, true)
	var values := _cell_values(geometry)
	var text_size := _text_size()
	var text_offset := (_font.get_ascent(text_size) - _font.get_descent(text_size)) * 0.5
	var point_radius := config.point_radius * view_transform.scale
	for i in range(mini(voronoi.real_count, values.size())):
		if is_zero_approx(values[i]):
			continue
		var poly := voronoi.cell_polygon(i)
		if poly.size() < 3:
			continue
		var center := _to_screen(BoardGeometry.polygon_centroid(poly))
		center = _move_label_away_from_point(center, _to_screen(board.points[i]),
			point_radius + text_size * 0.9)
		_draw_centered_label_text(center, str(BoardGeometry.js_round(values[i])), text_size,
			text_offset, Color.BLACK)


## Vorzeichenbehafteter Flusswert je Zelle aus dem aktuellen Brett und der
## eingestellten Tonmenge x.
func _cell_values(geometry: CellGeometry) -> PackedFloat32Array:
	return Influence.cell_values(geometry, board.color_ids(), board.influence_roots(),
		config.influence_start_strength)


## Neutrale Zelle: ohne Spielerfarbe oder mit einem Zellwert unter der
## Neutral-Schwelle. Sie wird grau gezeichnet und bekommt keine Frontlinie.
func _is_neutral(index: int) -> bool:
	if index < 0 or index >= board.points.size():
		return false
	if board.cell_color(index) == "":
		return true
	if index >= _signed_values.size():
		return false
	return Influence.is_neutral(_signed_values[index])


func _draw_value_label(index: int, value: float, poly: PackedVector2Array,
		text_size: int, text_offset: float, point_radius: float) -> void:
	var centroid := _to_screen(BoardGeometry.polygon_centroid(poly))
	var point := _to_screen(board.points[index])
	centroid = _move_label_away_from_point(centroid, point, point_radius + text_size * 0.9)
	_draw_centered_label_text(centroid, str(BoardGeometry.js_round(value)),
		text_size, text_offset, Color.BLACK)


## Wert einer Nachbarzelle an der gemeinsamen Grenze, leicht zur Zelle versetzt.
func _draw_neighbor_value_label(focus: int, neighbor: int, value: float,
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
	_draw_rounded_label(position, str(BoardGeometry.js_round(value)), text_size, text_offset,
		Color.WHITE, Color(board.cell_color(neighbor)))


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
