extends GutTest

## Tests fuer view/board_transform.gd und die Farbhelfer aus
## view/board_renderer.gd (1:1-Port der JS-Farbfunktionen).

func test_transform_letterboxes_wide_window() -> void:
	var transform := BoardTransform.for_viewport(Vector2(1800.0, 600.0))
	assert_almost_eq(transform.scale, 1.0, 0.0001)
	assert_almost_eq(transform.offset.x, 450.0, 0.0001)
	assert_almost_eq(transform.offset.y, 0.0, 0.0001)


func test_transform_letterboxes_tall_window() -> void:
	var transform := BoardTransform.for_viewport(Vector2(900.0, 1200.0))
	assert_almost_eq(transform.scale, 1.0, 0.0001)
	assert_almost_eq(transform.offset.x, 0.0, 0.0001)
	assert_almost_eq(transform.offset.y, 300.0, 0.0001)


func test_transform_scales_small_window() -> void:
	var transform := BoardTransform.for_viewport(Vector2(500.0, 350.0))
	assert_almost_eq(transform.scale, 500.0 / 900.0, 0.0001)
	assert_almost_eq(transform.offset.x, 0.0, 0.0001)
	assert_almost_eq(transform.offset.y, (350.0 - 600.0 * transform.scale) * 0.5, 0.0001)


func test_transform_round_trip() -> void:
	var transform := BoardTransform.for_viewport(Vector2(1024.0, 768.0))
	var board_point := Vector2(123.0, 456.0)
	var screen_point := transform.to_screen(board_point)
	var back := transform.to_board(screen_point)
	assert_almost_eq(back.x, board_point.x, 0.0001)
	assert_almost_eq(back.y, board_point.y, 0.0001)


func test_hex_rgb_round_trip() -> void:
	var rgb := BoardRenderer.hex_to_rgb("#FF8BA7")
	assert_eq(rgb, [255, 139, 167])
	assert_eq(BoardRenderer.rgb_to_hex(255, 139, 167), "#ff8ba7")


func test_grey_color_matches_css_hsl() -> void:
	assert_eq(BoardRenderer.grey_color(0.0), "#000000")
	assert_eq(BoardRenderer.grey_color(20.0), "#333333")
	assert_eq(BoardRenderer.grey_color(80.0), "#cccccc")
	assert_eq(BoardRenderer.grey_color(100.0), "#ffffff")


func test_mix_colors_endpoints_and_middle() -> void:
	assert_eq(BoardRenderer.mix_colors("#000000", "#ffffff", 0.0), "#000000")
	assert_eq(BoardRenderer.mix_colors("#000000", "#ffffff", 1.0), "#ffffff")
	assert_eq(BoardRenderer.mix_colors("#000000", "#ffffff", 0.5), "#808080")
	assert_eq(BoardRenderer.mix_colors("#FF8BA7", "#FF8BA7", 0.4), "#ff8ba7")


func test_mix_color_with_grey_keeps_hue_for_white() -> void:
	# Weiss hat keine Saettigung, das Ergebnis ist also das reine Grau.
	assert_eq(BoardRenderer.mix_color_with_grey("#ffffff", 20.0), BoardRenderer.grey_color(20.0))


func test_mix_color_with_grey_darkens_saturated_color() -> void:
	var mixed := BoardRenderer.mix_color_with_grey(GameConfig.COLOR_PLAYER1, 20.0)
	var rgb := BoardRenderer.hex_to_rgb(mixed)
	assert_eq(mixed.length(), 7)
	assert_lt(rgb[0], 255, "Rotanteil wird dunkler")
	assert_gt(rgb[0] + rgb[1] + rgb[2], 0, "Farbe bleibt sichtbar")


func test_score_hud_shows_numbers_and_bar_widths() -> void:
	var board := BoardState.new()
	board.score_p1 = 3.0
	board.score_p2 = 1.0
	var hud: ScoreHud = load("res://scenes/ScoreHud.tscn").instantiate()
	add_child_autofree(hud)
	hud.update_scores(board)

	var label: Label = hud.get_node("ScoreLabel")
	assert_eq(label.text, "Player1: 3 Player2: 1")
	var bar1: ColorRect = hud.get_node("BarBackground/Bar1")
	var bar2: ColorRect = hud.get_node("BarBackground/Bar2")
	assert_almost_eq(bar1.size.x, ScoreHud.BAR_WIDTH * 0.75, 0.01)
	assert_almost_eq(bar2.size.x, ScoreHud.BAR_WIDTH * 0.25, 0.01)
	assert_almost_eq(bar2.position.x, bar1.size.x, 0.01, "zweiter Balken schliesst an")


func test_score_hud_without_points_has_empty_bars() -> void:
	var board := BoardState.new()
	var hud: ScoreHud = load("res://scenes/ScoreHud.tscn").instantiate()
	add_child_autofree(hud)
	hud.update_scores(board)
	var bar1: ColorRect = hud.get_node("BarBackground/Bar1")
	var bar2: ColorRect = hud.get_node("BarBackground/Bar2")
	assert_eq(bar1.size.x, 0.0)
	assert_eq(bar2.size.x, 0.0)
	var label: Label = hud.get_node("ScoreLabel")
	assert_eq(label.text, "Player1: 0 Player2: 0")
