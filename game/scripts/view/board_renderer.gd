class_name BoardRenderer
extends Node2D

## Zeichnet das Brett: Zellfuellungen, Flaechen-Text, Rahmen, Punkte und
## Drag-Linien. Liest nur BoardState, Voronoi und Config.

var board: BoardState
var config: GameConfig
var voronoi: Voronoi
## Zellen, deren Ton gerade spielt (Schluessel = Zellenindex).
var highlight_cells := {}

var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font


func set_board_state(p_board: BoardState, p_config: GameConfig, p_voronoi: Voronoi) -> void:
	board = p_board
	config = p_config
	voronoi = p_voronoi


func _draw() -> void:
	draw_rect(Rect2(0, 0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT), Color("#b2b2b2"), true)
	if board == null or config == null or voronoi == null:
		return
	_draw_cells()
	_draw_points()
	_draw_drag_lines()


func _draw_cells() -> void:
	var count := voronoi.cells.size()
	if count == 0:
		return
	var min_max := voronoi.min_max_area()
	var min_area := min_max.x
	var max_area := min_max.y
	if max_area == min_area:
		min_area = 0.0
		max_area = 1.0
	for i in range(count):
		var poly := voronoi.cell_polygon(i)
		var area := voronoi.area(i)
		if poly.size() < 3 or area <= 0.01:
			continue
		var norm := (area - min_area) / (max_area - min_area)
		var lum := GameConfig.LUM_MAX - (GameConfig.LUM_MAX - GameConfig.LUM_MIN) * norm
		var base := board.cell_color(i)
		var my_color := mix_color_with_grey(base, lum) if base != "" else grey_color(lum)

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
		if enemy_color != "":
			var mix := GameConfig.ENEMY_MIX_BASE * (enemy_area / (enemy_area + area))
			mix = minf(mix, GameConfig.ENEMY_MIX_BASE)
			my_color = mix_colors(my_color, enemy_color, mix)

		draw_colored_polygon(poly, Color(my_color))

		var centroid := BoardGeometry.polygon_vertex_average(poly)
		var label := str(BoardGeometry.js_round(area / GameConfig.AREA_TEXT_DIVISOR))
		var ascent := _font.get_ascent(GameConfig.AREA_TEXT_SIZE)
		var descent := _font.get_descent(GameConfig.AREA_TEXT_SIZE)
		var text_pos := Vector2(centroid.x, centroid.y + (ascent - descent) * 0.5)
		draw_string(_font, text_pos, label, HORIZONTAL_ALIGNMENT_CENTER, 0.0, GameConfig.AREA_TEXT_SIZE, Color.BLACK)

		var outline := poly.duplicate()
		outline.append(poly[0])
		if highlight_cells.has(i):
			draw_polyline(outline, Color(GameConfig.HIGHLIGHT_FRAME_COLOR), GameConfig.HIGHLIGHT_FRAME_WIDTH, false)
		else:
			draw_polyline(outline, Color(GameConfig.FRAME_COLOR), GameConfig.FRAME_WIDTH, false)


func _draw_points() -> void:
	for i in range(board.points.size()):
		var color := Color.BLACK
		if config.alternating_moves and board.cell_color(i) != board.active_color:
			color = Color(0.5, 0.5, 0.5)
		draw_circle(board.points[i], GameConfig.POINT_RADIUS, color)


func _draw_drag_lines() -> void:
	var dragged := board.dragged_index
	if dragged < 0 or dragged >= board.points.size():
		return
	var origin := board.points[dragged]
	var my_area := voronoi.area(dragged)

	if board.drag_same_neighbor >= 0 and board.drag_same_neighbor_area > my_area:
		draw_line(origin, board.points[board.drag_same_neighbor], Color.BLACK, 2.0)

	if board.drag_opponent_neighbor >= 0 and board.drag_opponent_neighbor_area > my_area:
		var thickness := 0.5
		if board.drag_same_neighbor_area > 0.0:
			var ratio := board.drag_opponent_neighbor_area / board.drag_same_neighbor_area
			thickness = 0.5 + 2.0 * minf(ratio, 1.0)
		draw_line(origin, board.points[board.drag_opponent_neighbor], Color.WHITE, thickness)


# ------------------------------------------------------------- Farben ------
# 1:1-Port der JS-Farbhelfer (rgbToHsl / hslToRgb / rgbToHex / mixColors /
# mixColorWithGrey), inklusive der Math.round-Rundung.

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


static func grey_color(lum: float) -> String:
	var rgb := hsl_to_rgb(0.0, 0.0, lum / 100.0)
	return rgb_to_hex(rgb[0], rgb[1], rgb[2])


static func mix_color_with_grey(hex_color: String, lum: float) -> String:
	var rgb := hex_to_rgb(hex_color)
	var hsl := rgb_to_hsl(rgb[0], rgb[1], rgb[2])
	var luminance: float = hsl[2]
	var new_l := (lum / 100.0) * luminance
	if new_l > 1.0:
		new_l = 1.0
	var mixed := hsl_to_rgb(hsl[0], hsl[1], new_l)
	return rgb_to_hex(mixed[0], mixed[1], mixed[2])