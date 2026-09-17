class_name GearButton
extends Button

## Einstellungs-Knopf: zeichnet nur ein Zahnrad, ohne Bilddatei.

const TEETH := 8
## Verhaeltnis von Ringinnerem zu Aussenradius.
const RING_RATIO := 0.62
const COLOR := Color("#e8e8e8")
const COLOR_HOVER := Color("#ffffff")
const COLOR_PRESSED := Color("#ffd34d")


func _ready() -> void:
	text = ""
	if tooltip_text.is_empty():
		tooltip_text = "Einstellungen"
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)


func _draw() -> void:
	var radius := minf(size.x, size.y) * 0.5 - 3.0
	if radius <= 2.0:
		return
	var center := size * 0.5
	var color := COLOR
	if is_pressed():
		color = COLOR_PRESSED
	elif is_hovered():
		color = COLOR_HOVER

	var ring_outer := radius
	var ring_inner := radius * RING_RATIO
	draw_arc(center, (ring_outer + ring_inner) * 0.5, 0.0, TAU, 40, color, ring_outer - ring_inner, true)

	var tooth_length := radius * 0.32
	var tooth_width := (TAU * ring_outer) / float(TEETH) * 0.42
	for i in range(TEETH):
		var angle := TAU * float(i) / float(TEETH)
		draw_set_transform(center, angle, Vector2.ONE)
		draw_rect(Rect2(ring_outer - 1.0, -tooth_width * 0.5, tooth_length, tooth_width), color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
