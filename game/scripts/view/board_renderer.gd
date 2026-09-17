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
	_draw_drag_limit()
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
	_fill_colors = _cell_fill_colors(count)
	for i in range(count):
		var poly := voronoi.cell_polygon(i)
		var area := voronoi.area(i)
		if poly.size() < 3 or area <= 0.01:
			continue
		var screen_poly := _to_screen_polygon(poly)
		draw_colored_polygon(screen_poly, Color(_fill_colors[i]))
		if highlight_cells.has(i):
			# Klingende Zelle: gelb ueberlegt, so hell wie ihr Ton gerade laut ist.
			var play_color := Color(GameConfig.NOTE_PLAY_COLOR)
			play_color.a = GameConfig.NOTE_PLAY_ALPHA * clampf(float(highlight_cells[i]), 0.0, 1.0)
			draw_colored_polygon(screen_poly, play_color)
		_draw_cell_frame(i, screen_poly, line_scale)


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


## Rahmen einer Zelle: duenne Linie zu gleichfarbigen Nachbarn, dicke
## Frontlinie zu andersfarbigen Nachbarn und zum Brettrand.
##
## An der Frontlinie werden die Zellen abgerundet: an jeder konvexen Ecke, an
## der zwei Frontkanten zusammentreffen, wird die Ecke durch einen Bogen
## ersetzt (Radius aus der Konfiguration). Die dabei abgeschnittene Flaeche
## wird mit den Farben der angrenzenden Zellen gefuellt, damit keine Luecke
## und keine Spitze entsteht.
func _draw_cell_frame(index: int, poly: PackedVector2Array, line_scale: float) -> void:
	var count := poly.size()
	var my_color := board.cell_color(index)
	var neighbors := voronoi.edge_neighbors(index)
	var is_front: Array = []
	is_front.resize(count)
	for k in range(count):
		var nb: int = neighbors[k] if k < neighbors.size() else -1
		is_front[k] = nb < 0 or board.cell_color(nb) != my_color

	var corners := _front_corners(poly, is_front, neighbors, config.corner_radius * line_scale)
	if not corners.is_empty():
		_draw_corner_patches(index, poly, corners)

	for k in range(count):
		var next := (k + 1) % count
		if not is_front[k]:
			draw_line(poly[k], poly[next], Color(GameConfig.FRAME_COLOR),
				GameConfig.SAME_COLOR_FRAME_WIDTH * line_scale, true)
			continue
		var start := poly[k]
		var end := poly[next]
		var length := maxf(start.distance_to(end), 0.0001)
		var trim_a: float = corners[k]["trim"] if corners.has(k) else 0.0
		var trim_b: float = corners[next]["trim"] if corners.has(next) else 0.0
		var a := start.lerp(end, trim_a / length) if trim_a > 0.0 else start
		var b := end.lerp(start, trim_b / length) if trim_b > 0.0 else end
		if a.distance_to(b) > 0.01:
			draw_line(a, b, Color(GameConfig.FRONT_FRAME_COLOR), GameConfig.FRONT_FRAME_WIDTH * line_scale, true)

	var front_color := Color(GameConfig.FRONT_FRAME_COLOR)
	var front_width := GameConfig.FRONT_FRAME_WIDTH * line_scale
	for corner in corners.values():
		var arc: PackedVector2Array = corner["arc"]
		for i in range(arc.size() - 1):
			draw_line(arc[i], arc[i + 1], front_color, front_width, true)
	for k in range(count):
		if corners.has(k):
			continue
		if not is_front[k] and not is_front[(k - 1 + count) % count]:
			continue
		draw_circle(poly[k], front_width * 0.5, front_color, true, -1.0, true)


## Ecken der Frontlinie, die abgerundet werden: Schluessel ist der Eckindex,
## Wert enthaelt Bogen, Stutzweite und die beiden Nachbarzellen. Abgerundet
## werden nur konvexe Ecken mit zwei Frontkanten.
func _front_corners(poly: PackedVector2Array, is_front: Array, neighbors: PackedInt32Array, radius: float) -> Dictionary:
	var out := {}
	var count := poly.size()
	if radius <= 0.01 or count < 3:
		return out
	var ccw := BoardGeometry.signed_polygon_area(poly) > 0.0
	for k in range(count):
		var prev := (k - 1 + count) % count
		if not is_front[k] or not is_front[prev]:
			continue
		var v := poly[k]
		var to_prev := poly[prev] - v
		var to_next := poly[(k + 1) % count] - v
		var len_prev := to_prev.length()
		var len_next := to_next.length()
		if len_prev < 1e-3 or len_next < 1e-3:
			continue
		var cross := to_prev.cross(to_next)
		var convex := (cross < 0.0) == ccw
		if not convex or absf(cross) < 1e-6:
			continue
		var trim := minf(radius, minf(len_prev, len_next) * 0.45)
		if trim <= 0.01:
			continue
		var p_prev := v + to_prev / len_prev * trim
		var p_next := v + to_next / len_next * trim
		var steps := clampi(int(ceil(absf(to_prev.angle_to(to_next)) / (PI / 12.0))), 3, 12)
		var arc := PackedVector2Array()
		for s in range(steps + 1):
			arc.append(_quadratic(p_prev, v, p_next, float(s) / float(steps)))
		out[k] = {
			"arc": arc,
			"trim": trim,
			"prev_neighbor": int(neighbors[prev]) if prev < neighbors.size() else -1,
			"next_neighbor": int(neighbors[k]) if k < neighbors.size() else -1,
		}
	return out


## Fuellt die abgeschnittene Ecke mit den Farben der beiden Nachbarzellen,
## geteilt an der Winkelhalbierenden: so bleibt die Grenze zwischen beiden
## Farben dort, wo sie ohne Abrundung auch waere.
func _draw_corner_patches(index: int, poly: PackedVector2Array, corners: Dictionary) -> void:
	var own_fill: String = _fill_colors[index] if index < _fill_colors.size() else GameConfig.FRAME_COLOR
	for k in corners:
		var corner: Dictionary = corners[k]
		var arc: PackedVector2Array = corner["arc"]
		if arc.size() < 3:
			continue
		var v := poly[k]
		var mid := int(arc.size() / 2)
		var first := PackedVector2Array([v])
		for i in range(mid + 1):
			first.append(arc[i])
		var second := PackedVector2Array([v, arc[mid]])
		for i in range(mid + 1, arc.size() - 1):
			second.append(arc[i])
		second.append(arc[arc.size() - 1])
		_fill_patch(first, _neighbor_fill(corner["prev_neighbor"], own_fill))
		_fill_patch(second, _neighbor_fill(corner["next_neighbor"], own_fill))


## Fuellt eine kleine Flaeche; entartete Reste werden ausgelassen.
func _fill_patch(points: PackedVector2Array, color: String) -> void:
	if points.size() < 3 or BoardGeometry.polygon_area(points) < 0.5:
		return
	draw_colored_polygon(points, Color(color))

## Fuellfarbe einer Nachbarzelle; ohne Nachbar (Brettrand) die eigene Farbe.
func _neighbor_fill(neighbor: int, fallback: String) -> String:
	if neighbor >= 0 and neighbor < _fill_colors.size():
		return _fill_colors[neighbor]
	return fallback


static func _quadratic(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return a * u * u + b * 2.0 * u * t + c * t * t


## Weisse Umrandung der Zelle unter dem Mauszeiger, in der Dicke der normalen
## Zellgrenze. Sie liegt ueber allen Zellrahmen.
func _draw_hover_outline() -> void:
	var index := board.hovered_index
	if index < 0 or index >= voronoi.cells.size():
		return
	var poly := voronoi.cell_polygon(index)
	if poly.size() < 3:
		return
	var screen := _to_screen_polygon(poly)
	var count := screen.size()
	for i in range(count):
		draw_line(screen[i], screen[(i + 1) % count], Color(GameConfig.POINT_HOVER_COLOR),
			GameConfig.SAME_COLOR_FRAME_WIDTH * view_transform.scale, true)


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
		draw_line(origin, _to_screen(board.points[board.drag_opponent_neighbor]), Color.WHITE, thickness * line_scale, true)


## Territorium der erlaubten Bewegung beim Verlust-Schutz: gelb gestrichelte
## Kontur mit schwach gefuellter Flaeche rund um die gezogene Zelle.
func _draw_drag_limit() -> void:
	if not board.drag_limit_active or board.drag_limit_region.size() < 3:
		return
	var line_scale := view_transform.scale
	var region := BoardGeometry.smooth_closed_polygon(
		board.drag_limit_region, GameConfig.DRAG_LIMIT_SMOOTH_ROUNDS)
	var screen := _to_screen_polygon(region)
	draw_colored_polygon(screen, Color(GameConfig.DRAG_LIMIT_FILL_COLOR))
	var outline := Color(GameConfig.DRAG_LIMIT_COLOR)
	var count := screen.size()
	for i in range(count):
		draw_dashed_line(screen[i], screen[(i + 1) % count], outline,
			GameConfig.DRAG_LIMIT_WIDTH * line_scale, GameConfig.DRAG_LIMIT_DASH * line_scale, true, true)


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