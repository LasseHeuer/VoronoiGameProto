extends GutTest

## Tests fuer core/geometry.gd.

const RECT := Rect2(0.0, 0.0, 900.0, 600.0)


func _square() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(10.0, 0.0), Vector2(10.0, 10.0), Vector2(0.0, 10.0),
	])


func test_polygon_area() -> void:
	assert_almost_eq(BoardGeometry.polygon_area(_square()), 100.0, 0.0001)
	assert_eq(BoardGeometry.polygon_area(PackedVector2Array()), 0.0)
	assert_eq(BoardGeometry.polygon_area(PackedVector2Array([Vector2(0, 0), Vector2(1, 1)])), 0.0)


func test_polygon_area_is_orientation_independent() -> void:
	var clockwise := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.0, 10.0), Vector2(10.0, 10.0), Vector2(10.0, 0.0),
	])
	assert_almost_eq(BoardGeometry.polygon_area(clockwise), 100.0, 0.0001)


func test_polygon_vertex_average() -> void:
	var average := BoardGeometry.polygon_vertex_average(_square())
	assert_almost_eq(average.x, 5.0, 0.0001)
	assert_almost_eq(average.y, 5.0, 0.0001)


func test_polygon_centroid_uses_area_center() -> void:
	var poly := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(4.0, 0.0), Vector2(1.0, 1.0)])
	var centroid := BoardGeometry.polygon_centroid(poly)
	assert_almost_eq(centroid.x, 5.0 / 3.0, 0.0001)
	assert_almost_eq(centroid.y, 1.0 / 3.0, 0.0001)


func test_point_in_polygon() -> void:
	var square := _square()
	assert_true(BoardGeometry.point_in_polygon(Vector2(5.0, 5.0), square))
	assert_false(BoardGeometry.point_in_polygon(Vector2(15.0, 5.0), square))
	assert_false(BoardGeometry.point_in_polygon(Vector2(-1.0, 5.0), square))


func test_clip_polygon_to_rect_keeps_inner_polygon() -> void:
	var square := _square()
	var clipped := BoardGeometry.clip_polygon_to_rect(square, RECT)
	assert_almost_eq(BoardGeometry.polygon_area(clipped), 100.0, 0.0001)


func test_clip_polygon_to_rect_cuts_outer_polygon() -> void:
	var big := PackedVector2Array([
		Vector2(-100.0, -100.0), Vector2(100.0, -100.0), Vector2(100.0, 100.0), Vector2(-100.0, 100.0),
	])
	var clipped := BoardGeometry.clip_polygon_to_rect(big, RECT)
	assert_almost_eq(BoardGeometry.polygon_area(clipped), 10000.0, 0.0001)


func test_clip_half_plane() -> void:
	var square := _square()
	# Behalte x <= 5
	var clipped := BoardGeometry.clip_half_plane(square, Vector2(1.0, 0.0), 5.0)
	assert_almost_eq(BoardGeometry.polygon_area(clipped), 50.0, 0.0001)


func test_simplify_polygon_removes_duplicates_and_collinear_points() -> void:
	var poly := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(5.0, 0.0), Vector2(10.0, 0.0),
		Vector2(10.0, 10.0), Vector2(10.0, 10.0), Vector2(0.0, 10.0),
	])
	var simplified := BoardGeometry.simplify_polygon(poly)
	assert_eq(simplified.size(), 4)
	assert_almost_eq(BoardGeometry.polygon_area(simplified), 100.0, 0.0001)


func test_simplify_polygon_is_area_preserving_with_merge_tolerance() -> void:
	var poly := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(5.0, 0.0), Vector2(10.0, 0.0), Vector2(10.0, 10.0), Vector2(0.0, 10.0),
	])
	assert_almost_eq(BoardGeometry.polygon_area(BoardGeometry.simplify_polygon(poly)), 100.0, 0.0001)


func test_simplify_polygon_merges_nearly_identical_points() -> void:
	var poly := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(10.0, 0.0), Vector2(10.0, 0.0002), Vector2(10.0, 10.0), Vector2(0.0, 10.0),
	])
	var simplified := BoardGeometry.simplify_polygon(poly)
	assert_eq(simplified.size(), 4)


func test_smooth_closed_polygon_rounds_the_corners() -> void:
	var smoothed := BoardGeometry.smooth_closed_polygon(_square(), 1)
	assert_eq(smoothed.size(), 8, "jede Kante wird durch zwei Punkte ersetzt")
	assert_lt(BoardGeometry.polygon_area(smoothed), 100.0, "die Ecken werden abgeschnitten")
	assert_gt(BoardGeometry.polygon_area(smoothed), 50.0, "die Flaeche bleibt weitgehend erhalten")


func test_smooth_closed_polygon_keeps_degenerate_input() -> void:
	assert_eq(BoardGeometry.smooth_closed_polygon(PackedVector2Array(), 1).size(), 0)
	var line := PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 0.0)])
	assert_eq(BoardGeometry.smooth_closed_polygon(line, 2).size(), 2)
	assert_eq(BoardGeometry.smooth_closed_polygon(_square(), 0).size(), 4, "ohne Runden bleibt alles")


func test_largest_polygon_picks_the_biggest_area() -> void:
	var small := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(2.0, 0.0), Vector2(2.0, 2.0), Vector2(0.0, 2.0),
	])
	var large := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(10.0, 0.0), Vector2(10.0, 10.0), Vector2(0.0, 10.0),
	])
	var middle := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(5.0, 0.0), Vector2(5.0, 5.0), Vector2(0.0, 5.0),
	])
	var picked := BoardGeometry.largest_polygon([small, large, middle])
	assert_almost_eq(BoardGeometry.polygon_area(picked), 100.0, 0.0001)
	assert_eq(BoardGeometry.largest_polygon([]).size(), 0)
	assert_eq(BoardGeometry.largest_polygon([PackedVector2Array()]).size(), 0)


func test_is_convex() -> void:
	assert_true(BoardGeometry.is_convex(_square()))
	var concave := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(10.0, 0.0), Vector2(5.0, 5.0), Vector2(10.0, 10.0), Vector2(0.0, 10.0),
	])
	assert_false(BoardGeometry.is_convex(concave))
	assert_false(BoardGeometry.is_convex(PackedVector2Array([Vector2(0, 0), Vector2(1, 1)])))


func test_circumcenter() -> void:
	# Rechtwinkliges Dreieck: Umkreismittelpunkt ist die Mitte der Hypotenuse
	var center := BoardGeometry.circumcenter(Vector2(0.0, 0.0), Vector2(10.0, 0.0), Vector2(0.0, 10.0))
	assert_almost_eq(center.x, 5.0, 0.0001)
	assert_almost_eq(center.y, 5.0, 0.0001)


func test_circumcenter_of_degenerate_triangle_is_finite() -> void:
	var center := BoardGeometry.circumcenter(Vector2(0.0, 0.0), Vector2(5.0, 0.0), Vector2(10.0, 0.0))
	assert_true(is_finite(center.x))
	assert_true(is_finite(center.y))


func test_js_round_matches_javascript() -> void:
	assert_eq(BoardGeometry.js_round(0.5), 1)
	assert_eq(BoardGeometry.js_round(1.5), 2)
	assert_eq(BoardGeometry.js_round(-0.5), 0)
	assert_eq(BoardGeometry.js_round(2.4), 2)
	assert_eq(BoardGeometry.js_round(2.6), 3)
