extends Button

## Neustart-Knopf: zeichnet einen kreisfoermigen Pfeil ohne Bilddatei.

const COLOR := Color("#e8e8e8")
const COLOR_HOVER := Color("#ffffff")
const COLOR_PRESSED := Color("#ffd34d")


func _ready() -> void:
	text = ""
	if tooltip_text.is_empty():
		tooltip_text = "Neustart"
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)


func _draw() -> void:
	var radius := minf(size.x, size.y) * 0.5 - 4.0
	if radius <= 2.0:
		return
	var center := size * 0.5
	var color := COLOR
	if is_pressed():
		color = COLOR_PRESSED
	elif is_hovered():
		color = COLOR_HOVER
	var start := -PI * 0.82
	var end := PI * 0.9
	draw_arc(center, radius * 0.72, start, end, 28, color, 2.5, true)
	var tip := center + Vector2(cos(end), sin(end)) * radius * 0.72
	var tangent_angle := end + PI * 0.5
	var tangent := Vector2(cos(tangent_angle), sin(tangent_angle))
	var side := Vector2(cos(end), sin(end))
	var arrow := PackedVector2Array([
		tip + tangent * 4.0,
		tip - tangent * 4.0,
		tip + side * 5.0,
	])
	draw_colored_polygon(arrow, color)
