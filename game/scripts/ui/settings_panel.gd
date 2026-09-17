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
const SECTION_COLOR := Color("#7f8896")
const CLOSE_COLOR := Color("#c9cfda")
const LABEL_WIDTH := 160.0
const SLIDER_WIDTH := 130.0
const VALUE_WIDTH := 44.0

@onready var _rows: VBoxContainer = $Margin/Layout/Scroll/Rows
@onready var _hide_button: Button = $Margin/Layout/Header/CloseButton
@onready var _restart_button: Button = $Margin/Layout/RestartButton

var _config: GameConfig
## Bedienelement je Schema-Key.
var _controls := {}
var _rows_by_key := {}


func _ready() -> void:
	_style()


func setup(config: GameConfig) -> void:
	_config = config
	_hide_button.pressed.connect(func(): hide_requested.emit())
	_restart_button.pressed.connect(func(): restart_requested.emit())
	for group in GameConfig.SETTING_GROUPS:
		var entries := _entries_for(group)
		var with_waveform: bool = group == GameConfig.WAVEFORM_GROUP
		if entries.is_empty() and not with_waveform:
			continue
		_rows.add_child(_make_section(group))
		if with_waveform:
			_build_waveform_row()
		for entry in entries:
			if entry.has("min"):
				_build_slider(entry)
			else:
				_build_toggle(entry)
	_update_conditional_visibility()


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


func _build_waveform_row() -> void:
	var row := _make_row("Wave")
	var option := OptionButton.new()
	for waveform in GameConfig.WAVEFORMS:
		option.add_item(waveform)
	option.selected = maxi(0, GameConfig.WAVEFORMS.find(_config.waveform))
	option.item_selected.connect(func(index: int):
		_config.waveform = GameConfig.WAVEFORMS[index]
		value_changed.emit("waveform", GameConfig.WAVEFORMS[index]))
	row.add_child(option)
	_controls["waveform"] = option


func _build_slider(entry: Dictionary) -> void:
	var key: String = entry["key"]
	var is_int: bool = entry.get("is_int", false)
	var row := _make_row(entry["label"])
	var slider := HSlider.new()
	slider.min_value = entry["min"]
	slider.max_value = entry["max"]
	slider.step = entry["step"]
	slider.custom_minimum_size = Vector2(SLIDER_WIDTH, 0.0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value = float(_config.get(key))
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(VALUE_WIDTH, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.text = _format_value(slider.value, is_int)
	slider.value_changed.connect(func(value: float):
		var new_value: Variant = int(round(value)) if is_int else value
		_config.set(key, new_value)
		value_label.text = _format_value(value, is_int)
		value_changed.emit(key, new_value))
	row.add_child(slider)
	row.add_child(value_label)
	_controls[key] = slider


func _build_toggle(entry: Dictionary) -> void:
	var key: String = entry["key"]
	var row := _make_row(entry["label"])
	_rows_by_key[key] = row
	var check := CheckBox.new()
	check.button_pressed = bool(_config.get(key))
	check.toggled.connect(func(pressed: bool):
		_config.set(key, pressed)
		if key == "show_flow" and not pressed:
			_config.show_all_flows = false
			var all_flows: CheckBox = _controls.get("show_all_flows")
			if all_flows != null:
				all_flows.button_pressed = false
			_update_conditional_visibility()
		value_changed.emit(key, pressed))
	row.add_child(check)
	_controls[key] = check


func _update_conditional_visibility() -> void:
	if not _rows_by_key.has("show_all_flows") or _config == null:
		return
	_rows_by_key["show_all_flows"].visible = bool(_config.show_flow)


func _make_row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0.0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	_rows.add_child(row)
	return row


func _make_section(title: String) -> Label:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", SECTION_COLOR)
	label.custom_minimum_size = Vector2(0.0, 26.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return label


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


func _format_value(value: float, is_int: bool) -> String:
	return str(int(round(value))) if is_int else "%.2f" % value
