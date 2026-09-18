class_name SettingsPanel
extends PanelContainer

## Baut die Bedienelemente aus dem Schema in GameConfig, gruppiert nach
## SETTING_GROUPS. Enthalten sind nur die wirksamen Parameter.
##
## Das Menue liegt als schmale Spalte ueber die ganze Fensterhoehe; die
## Gestaltung (dunkle Flaeche, runde Kante, Abschnittstitel) kommt aus diesem
## Skript, damit die Szene schlank bleibt.

signal value_changed(key: String, value: Variant)
signal restart_requested
signal hide_requested

## Hintergrund und Kante des Menues.
const PANEL_COLOR := Color("#14171cf2")
const PANEL_BORDER := Color("#39404a")
const TITLE_COLOR := Color("#f2f4f8")
const CLOSE_COLOR := Color("#c9cfda")
const LABEL_WIDTH := 130.0
const SLIDER_WIDTH := 104.0
const VALUE_WIDTH := 38.0
const ROW_FONT_SIZE := 12
const ROW_HEIGHT := 18.0

## Rubrik-Knopf: zeichnet links ein Dreieck und daneben den Titel, ohne
## Bilddatei. Das Dreieck zeigt nach rechts (eingeklappt) oder unten (offen).
class SectionHeaderButton extends Button:
	const COLOR := Color("#7f8896")
	const FONT_SIZE := 12
	const ICON_LEFT := 4.0
	const ICON_WIDTH := 14.0

	var title := ""
	var expanded := false

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		text = ""
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func set_expanded(value: bool) -> void:
		expanded = value
		queue_redraw()

	func _draw() -> void:
		var color := COLOR
		if is_hovered():
			color = color.lightened(0.3)
		var center := Vector2(ICON_LEFT + ICON_WIDTH * 0.5, size.y * 0.5)
		var r := 4.0
		var points: PackedVector2Array
		if expanded:
			points = PackedVector2Array([
				center + Vector2(-r, -r * 0.55),
				center + Vector2(r, -r * 0.55),
				center + Vector2(0.0, r * 0.8)])
		else:
			points = PackedVector2Array([
				center + Vector2(-r * 0.55, -r),
				center + Vector2(r * 0.8, 0.0),
				center + Vector2(-r * 0.55, r)])
		draw_colored_polygon(points, color)

		var font: Font = ThemeDB.fallback_font
		if font == null:
			return
		var baseline := (size.y - font.get_height(FONT_SIZE)) * 0.5 + font.get_ascent(FONT_SIZE)
		draw_string(font, Vector2(ICON_LEFT + ICON_WIDTH + 4.0, baseline), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE, color)

@onready var _rows: VBoxContainer = $Margin/Layout/Scroll/Rows
@onready var _hide_button: Button = $Margin/Layout/Header/CloseButton
@onready var _copy_button: Button = $Margin/Layout/CopyButton
@onready var _restart_button: Button = $Margin/Layout/RestartButton

var _config: GameConfig
## Bedienelement je Schema-Key.
var _controls := {}
var _rows_by_key := {}
## Zeilen je Rubrik und ihr Ein-/Ausklappzustand.
var _rows_by_group := {}
var _section_expanded := {}
var _section_headers := {}
var _current_group := ""


func _ready() -> void:
	_style()


func setup(config: GameConfig) -> void:
	_config = config
	_hide_button.pressed.connect(func(): hide_requested.emit())
	_copy_button.pressed.connect(_copy_settings)
	_restart_button.pressed.connect(func(): restart_requested.emit())
	for group in GameConfig.SETTING_GROUPS:
		var choices := _choices_for(group)
		var entries := _entries_for(group)
		if choices.is_empty() and entries.is_empty():
			continue
		_current_group = group
		_section_expanded[group] = false
		_rows.add_child(_make_section(group))
		for entry in choices:
			_build_choice(entry)
		for entry in entries:
			if entry.has("min"):
				_build_slider(entry)
			else:
				_build_toggle(entry)
	_apply_visibility()


## Alle Auswahlfelder einer Gruppe.
func _choices_for(group: String) -> Array:
	var out: Array = []
	for entry in GameConfig.CHOICES:
		if String(entry.get("group", "")) == group:
			out.append(entry)
	return out


## Alle Schema-Eintraege einer Gruppe, Slider vor Schaltern.
func _entries_for(group: String) -> Array:
	var out: Array = []
	for entry in GameConfig.SLIDERS:
		if String(entry.get("group", "")) == group:
			out.append(entry)
	for entry in GameConfig.TOGGLES:
		if String(entry.get("group", "")) == group:
			out.append(entry)
	return out


func _build_choice(entry: Dictionary) -> void:
	var key: String = entry["key"]
	var values: Array = entry["values"]
	var labels: Array = entry.get("labels", values)
	var row := _make_row(entry["label"])
	var option := OptionButton.new()
	for label in labels:
		option.add_item(String(label))
	option.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	option.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	option.selected = maxi(0, values.find(_config.get(key)))
	option.item_selected.connect(func(index: int):
		var value: Variant = values[index]
		_config.set(key, value)
		value_changed.emit(key, value))
	row.add_child(option)
	_controls[key] = option


func _build_slider(entry: Dictionary) -> void:
	var key: String = entry["key"]
	var is_int: bool = entry.get("is_int", false)
	var base_step: float = entry["step"]
	var row := _make_row(entry["label"])
	var slider := HSlider.new()
	slider.min_value = entry["min"]
	slider.max_value = entry["max"]
	slider.step = base_step
	slider.custom_minimum_size = Vector2(SLIDER_WIDTH, ROW_HEIGHT)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value = float(_config.get(key))
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(VALUE_WIDTH, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	value_label.text = _format_value(slider.value, is_int, base_step)
	slider.value_changed.connect(func(value: float):
		var new_value: Variant = int(round(value)) if is_int else value
		_config.set(key, new_value)
		value_label.text = _format_value(value, is_int, slider.step)
		value_changed.emit(key, new_value))
	# Rechtsklick setzt den Regler auf den Werkswert zurueck. Mit gedrueckter
	# Umschalttaste wird der Schritt zehnmal feiner, damit sich kleine Werte
	# genau einstellen lassen.
	slider.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_RIGHT:
			slider.value = float(GameConfig.DEFAULTS.get(key, slider.value))
			slider.accept_event()
			return
		if is_int:
			return
		if event is InputEventMouseButton and not event.pressed:
			slider.step = base_step
		elif event is InputEventWithModifiers:
			slider.step = _fine_step(base_step) if event.shift_pressed else base_step
		value_label.text = _format_value(slider.value, is_int, slider.step))
	row.add_child(slider)
	row.add_child(value_label)
	_controls[key] = slider


func _build_toggle(entry: Dictionary) -> void:
	var key: String = entry["key"]
	var row := _make_row(entry["label"])
	_rows_by_key[key] = row
	var check := CheckBox.new()
	check.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	check.button_pressed = bool(_config.get(key))
	check.toggled.connect(func(pressed: bool):
		_config.set(key, pressed)
		if key == "show_flow":
			if not pressed:
				_config.show_all_flows = false
				var all_flows: CheckBox = _controls.get("show_all_flows")
				if all_flows != null:
					all_flows.button_pressed = false
			_apply_visibility()
		value_changed.emit(key, pressed))
	row.add_child(check)
	_controls[key] = check


## Klappt eine Rubrik ein oder aus und zeigt bzw. verbirgt ihre Zeilen.
func _toggle_section(group: String) -> void:
	var expanded: bool = not bool(_section_expanded.get(group, false))
	_section_expanded[group] = expanded
	var header: SectionHeaderButton = _section_headers.get(group)
	if header != null:
		header.set_expanded(expanded)
	_apply_visibility()


## Sichtbarkeit aller Zeilen: nur in ausgeklappten Rubriken, die Sonderzeile
## "Flows fuer alle Zellen" zusaetzlich nur bei aktivem "Flow anzeigen".
func _apply_visibility() -> void:
	for group in _rows_by_group:
		var expanded: bool = bool(_section_expanded.get(group, false))
		for row in _rows_by_group[group]:
			row.visible = expanded
	if _rows_by_key.has("show_all_flows") and _config != null:
		var all_flows: Control = _rows_by_key["show_all_flows"]
		all_flows.visible = all_flows.visible and bool(_config.show_flow)


func _make_row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0.0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	row.add_child(label)
	_rows.add_child(row)
	if not _rows_by_group.has(_current_group):
		_rows_by_group[_current_group] = []
	_rows_by_group[_current_group].append(row)
	return row


func _make_section(title: String) -> SectionHeaderButton:
	var button := SectionHeaderButton.new()
	button.title = title
	button.set_expanded(false)
	button.custom_minimum_size = Vector2(0.0, 22.0)
	button.pressed.connect(func(): _toggle_section(title))
	_section_headers[title] = button
	return button


func _style() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL_COLOR
	panel.corner_radius_top_right = 16
	panel.corner_radius_bottom_right = 16
	panel.border_width_right = 1
	panel.border_color = PANEL_BORDER
	add_theme_stylebox_override("panel", panel)

	var title: Label = $Margin/Layout/Header/Title
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", TITLE_COLOR)

	_hide_button.flat = true
	_hide_button.add_theme_font_size_override("font_size", 20)
	_hide_button.add_theme_color_override("font_color", CLOSE_COLOR)


## Schrittweite, solange die Umschalttaste gedrueckt ist.
func _fine_step(base_step: float) -> float:
	return maxf(base_step / 10.0, 0.001)


func _format_value(value: float, is_int: bool, step: float = 0.01) -> String:
	if is_int:
		return str(int(round(value)))
	if step >= 0.01:
		return "%.2f" % value
	if step >= 0.001:
		return "%.3f" % value
	return "%.4f" % value


## Alle Einstellungen als Code-Zeilen, wie sie im DEFAULTS-Woerterbuch von
## GameConfig stehen. So lassen sich die aktuellen Werte direkt uebernehmen.
func _settings_snapshot() -> String:
	var lines := PackedStringArray()
	for key in GameConfig.DEFAULTS:
		lines.append("\t\"%s\": %s," % [key, _format_setting(_config.get(key))])
	return "\n".join(lines)


func _format_setting(value: Variant) -> String:
	match typeof(value):
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_STRING:
			return "\"%s\"" % value
		TYPE_INT:
			return str(value)
		TYPE_FLOAT:
			return _format_float(value)
	return str(value)


## Fliesskommazahl mit mindestens einer Nachkommastelle und ohne ueberfluessige
## Nullen, damit sie als GDScript-Wert lesbar bleibt.
func _format_float(value: float) -> String:
	var text := String.num(value, 4)
	while text.ends_with("0"):
		text = text.substr(0, text.length() - 1)
	if text.ends_with("."):
		text += "0"
	return text


func _copy_settings() -> void:
	if _config == null:
		return
	DisplayServer.clipboard_set(_settings_snapshot())
