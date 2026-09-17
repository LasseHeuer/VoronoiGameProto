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
	_fill_colors = _cell_fill_colors(count)

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
		shapes[i] = [screen]
		_fill_polygon(screen, Color(_fill_colors[i]))
		if highlight_cells.has(i):
			# Klingende Zelle: farbige Ueberlagerung folgt der Tonlautstaerke.
			var play_color := Color(GameConfig.NOTE_PLAY_COLOR)
			play_color.a = GameConfig.NOTE_PLAY_ALPHA * clampf(float(highlight_cells[i]), 0.0, 1.0)
			_fill_polygon(screen, play_color)

	# 2) Uebernahme-Warnung: die groesste Gegnerzelle blinkt.
	_draw_takeover_blink(shapes)

	# 3) Duenne graue Innenraender zwischen gleichfarbigen Zellen.
	for i in range(count):
		if raws[i] == null:
			continue
		_draw_cell_borders(i, raws[i], line_scale)

	# 4) Durchgehende Frontlinie um jedes Territorium.
	_draw_territory_lines(line_scale)


## Fuellfarbe jeder Zelle: Helligkeit nach Flaechenanteil, dazu ein Anteil der
## groessten Gegnerfarbe an der gemeinsamen Grenze.
func _cell_fill_colors(count: int) -> PackedStringArray:
	var colors := PackedStringArray()
	colors.resize(count)
	var min_max := voronoi.min_max_area()
	var min_area := min_max.x
	var max_area := min_max.y
	if max_area == min_area:
		min_area = 0.0
		max_area = 1.0
	for i in range(count):
		var area := voronoi.area(i)
		var base := board.cell_color(i)
		var norm := 0.0
		if area > 0.01:
			norm = (area - min_area) / (max_area - min_area)
		var my_color := color_for_area(base, norm)

		var enemy_color := ""
		var enemy_area := 0.0
		for nb in voronoi.delaunay().neighbors(i):
			if nb >= count:
				continue
			var nb_base := board.cell_color(nb)
			if nb_base == "" or nb_base == base:
				continue
			var nb_area := voronoi.area(nb)
			if nb_area > enemy_area:
				enemy_area = nb_area
				enemy_color = nb_base
		if enemy_color != "" and area > 0.01:
			var mix := GameConfig.ENEMY_MIX_BASE * (enemy_area / (enemy_area + area))
			mix = minf(mix, GameConfig.ENEMY_MIX_BASE)
			my_color = mix_colors(my_color, enemy_color, mix)
		colors[i] = my_color
	return colors


## Zellfarbe: die kleinste Zelle ist am dunkelsten, die groesste am
## hellsten. Der Farbton der Grundfarbe bleibt, nur die Helligkeit wird
## mit dem Flaechenanteil skaliert.
static func color_for_area(base: String, norm: float) -> String:
	var lum := GameConfig.LUM_MIN + (GameConfig.LUM_MAX - GameConfig.LUM_MIN) * norm
	if base == "":
		return grey_color(lum)
	return mix_color_with_grey(base, lum)


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
		for corner in _territory_corner.get(color, []):
			_fill_fan(corner["vertex"], corner["arc"], team)
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
			if region.size() < 3 or BoardGeometry.signed_polygon_area(region) <= 0.0:
				continue
			var fillet := _fillet_with_cuts(region, config.corner_radius + half)
			var rounded: PackedVector2Array = fillet["path"]
			for inner in Geometry2D.offset_polygon(rounded, -half, Geometry2D.JOIN_MITER):
				if inner.size() >= 3:
					line_paths.append(_to_screen_polygon(_ensure_ccw(inner)))
			for inner in Geometry2D.offset_polygon(rounded, -inset, Geometry2D.JOIN_MITER):
				if inner.size() >= 3:
					clip_paths.append(_to_screen_polygon(_ensure_ccw(inner)))
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


## Vereinigung der Zellflaechen einer Farbe (Brettkoordinaten). Loecher
## entfallen: deren Grenze zeichnet die andere Farbe.
func _merge_cells(color: String) -> Array:
	var pieces: Array = []
	for i in range(board.points.size()):
		if board.cell_color(i) != color:
			continue
		var poly := voronoi.cell_polygon(i)
		if poly.size() >= 3:
			_merge_into(pieces, poly)
	var positive := true
	var largest := -1.0
	for p in pieces:
		var area := BoardGeometry.signed_polygon_area(p)
		if absf(area) > largest:
			largest = absf(area)
			positive = area > 0.0
	var out: Array = []
	for p in pieces:
		var area := BoardGeometry.signed_polygon_area(p)
		if absf(area) > 0.5 and (area > 0.0) == positive:
			out.append(p)
	if out.size() <= 1:
		return out
	# Nur die groesste zusammenhaengende Aussenkontur zeichnen. Kleinere
	# Restpolygone sind Inseln oder Clipper-Artefakte und wuerden als interne
	# Linien innerhalb eines Territoriums erscheinen.
	return [_largest_piece(out)]


## Nimmt eine Zellflaeche in die Liste der Teilflaechen auf: beruehrt sie eine
## vorhandene Flaeche, wird vereinigt (entstehende Loecher entfallen).
func _merge_into(pieces: Array, poly: PackedVector2Array) -> void:
	var current := poly
	var rest: Array = []
	for piece in pieces:
		if current.size() < 3:
			rest.append(piece)
			continue
		var merged := Geometry2D.merge_polygons(piece, current)
		if merged.size() == 1:
			current = merged[0]
		elif _same_winding(merged):
			# Beruehrt sich nicht: getrennte Flaeche bleibt bestehen.
			rest.append(piece)
		else:
			current = _largest_piece(merged)
	rest.append(current)
	pieces.clear()
	pieces.append_array(rest)


static func _same_winding(polys: Array) -> bool:
	var sign_positive := true
	var first := true
	for poly in polys:
		var area := BoardGeometry.signed_polygon_area(poly)
		if absf(area) <= 0.5:
			continue
		if first:
			sign_positive = area > 0.0
			first = false
		elif (area > 0.0) != sign_positive:
			return false
	return true


static func _largest_piece(polys: Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_area := -1.0
	for poly in polys:
		var area := absf(BoardGeometry.signed_polygon_area(poly))
		if area > best_area:
			best_area = area
			best = poly
	return best


## Zellflaeche auf die Fuellgrenze ihres Territoriums beschneiden. So liegen
## die Zellfarben innerhalb der Frontlinie.
func _clip_to_territory(index: int, poly: PackedVector2Array) -> Array:
	var clips: Array = _territory_clip.get(board.cell_color(index), [])
	if clips.is_empty():
		return [poly]
	var out: Array = []
	for clip in clips:
		for part in Geometry2D.clip_polygons(poly, clip):
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


## Uebernahme-Warnung: die groesste Gegnerzelle blinkt.
func _draw_takeover_blink(shapes: Array) -> void:
	if board.drag_blink <= 0.0:
		return
	var index := board.drag_opponent_neighbor
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


## Flaechen-Text zuletzt, damit ihn weder Rahmen noch Punkte ueberdecken.
func _draw_cell_labels() -> void:
	var text_size := _text_size()
	var text_offset := (_font.get_ascent(text_size) - _font.get_descent(text_size)) * 0.5
	for i in range(voronoi.cells.size()):
		var poly := voronoi.cell_polygon(i)
		var area := voronoi.area(i)
		if poly.size() < 3 or area <= 0.01:
			continue
		var centroid := _to_screen(BoardGeometry.polygon_vertex_average(poly))
		var label := str(BoardGeometry.js_round(area / GameConfig.AREA_TEXT_DIVISOR))
		var text_pos := Vector2(centroid.x, centroid.y + text_offset)
		draw_string(_font, text_pos, label, HORIZONTAL_ALIGNMENT_CENTER, 0.0, text_size, Color.BLACK)


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
## Gegner blinkt bei drohender Uebernahme mit der Warnung.
func _draw_drag_lines() -> void:
	var dragged := board.dragged_index
	if dragged < 0 or dragged >= board.points.size():
		return
	var line_scale := view_transform.scale
	var origin := _to_screen(board.points[dragged])
	var my_area := voronoi.area(dragged)

	if board.drag_same_neighbor >= 0 and board.drag_same_neighbor_area > my_area:
		draw_line(origin, _to_screen(board.points[board.drag_same_neighbor]), Color.BLACK, 2.0 * line_scale, true)

	if board.drag_opponent_neighbor >= 0 and board.drag_opponent_neighbor_area > my_area:
		var thickness := 0.5
		if board.drag_same_neighbor_area > 0.0:
			var ratio := board.drag_opponent_neighbor_area / board.drag_same_neighbor_area
			thickness = 0.5 + 2.0 * minf(ratio, 1.0)
		var alpha := 1.0 if board.drag_blink <= 0.0 else 0.3 + 0.7 * clampf(board.drag_blink, 0.0, 1.0)
		draw_line(origin, _to_screen(board.points[board.drag_opponent_neighbor]),
			Color(GameConfig.BLINK_COLOR, alpha), thickness * line_scale, true)


# ------------------------------------------------------------- Farben ------
# 1:1-Port der JS-Farbhelfer (rgbToHsl / hslToRgb / rgbToHex / mixColors),
# inklusive der Math.round-Rundung.

static func hex_to_rgb(hex: String) -> Array:
	return [
		hex.substr(1, 2).hex_to_int(),
		hex.substr(3, 2).hex_to_int(),
		hex.substr(5, 2).hex_to_int(),
	]


static func rgb_to_hex(r: int, g: int, b: int) -> String:
	return "#%02x%02x%02x" % [r, g, b]


static func rgb_to_hsl(r: int, g: int, b: int) -> Array:
	var rf := r / 255.0
	var gf := g / 255.0
	var bf := b / 255.0
	var max_v := maxf(rf, maxf(gf, bf))
	var min_v := minf(rf, minf(gf, bf))
	var h := 0.0
	var s := 0.0
	var l := (max_v + min_v) * 0.5
	if max_v == min_v:
		h = 0.0
		s = 0.0
	else:
		var d := max_v - min_v
		s = d / (2.0 - max_v - min_v) if l > 0.5 else d / (max_v + min_v)
		if max_v == rf:
			h = (gf - bf) / d + (6.0 if gf < bf else 0.0)
		elif max_v == gf:
			h = (bf - rf) / d + 2.0
		else:
			h = (rf - gf) / d + 4.0
		h /= 6.0
	return [h, s, l]


static func hsl_to_rgb(h: float, s: float, l: float) -> Array:
	if s == 0.0:
		var val := BoardGeometry.js_round(l * 255.0)
		return [val, val, val]
	var q := l * (1.0 + s) if l < 0.5 else l + s - l * s
	var p := 2.0 * l - q
	return [
		BoardGeometry.js_round(_hue_to_rgb(p, q, h + 1.0 / 3.0) * 255.0),
		BoardGeometry.js_round(_hue_to_rgb(p, q, h) * 255.0),
		BoardGeometry.js_round(_hue_to_rgb(p, q, h - 1.0 / 3.0) * 255.0),
	]


static func _hue_to_rgb(p: float, q: float, t: float) -> float:
	var tt := t
	if tt < 0.0:
		tt += 1.0
	if tt > 1.0:
		tt -= 1.0
	if tt < 1.0 / 6.0:
		return p + (q - p) * 6.0 * tt
	if tt < 1.0 / 2.0:
		return q
	if tt < 2.0 / 3.0:
		return p + (q - p) * (2.0 / 3.0 - tt) * 6.0
	return p


static func mix_colors(color1: String, color2: String, factor: float) -> String:
	var c1 := hex_to_rgb(color1)
	var c2 := hex_to_rgb(color2)
	return rgb_to_hex(
		BoardGeometry.js_round(c1[0] * (1.0 - factor) + c2[0] * factor),
		BoardGeometry.js_round(c1[1] * (1.0 - factor) + c2[1] * factor),
		BoardGeometry.js_round(c1[2] * (1.0 - factor) + c2[2] * factor)
	)


## Skaliert die Helligkeit der Grundfarbe mit lum (Prozent), Farbton und
## Saettigung bleiben.
static func mix_color_with_grey(hex_color: String, lum: float) -> String:
	var rgb := hex_to_rgb(hex_color)
	var hsl := rgb_to_hsl(rgb[0], rgb[1], rgb[2])
	var luminance: float = hsl[2]
	var new_l := (lum / 100.0) * luminance
	if new_l > 1.0:
		new_l = 1.0
	var mixed := hsl_to_rgb(hsl[0], hsl[1], new_l)
	return rgb_to_hex(mixed[0], mixed[1], mixed[2])


static func grey_color(lum: float) -> String:
	var rgb := hsl_to_rgb(0.0, 0.0, lum / 100.0)
	return rgb_to_hex(rgb[0], rgb[1], rgb[2])
