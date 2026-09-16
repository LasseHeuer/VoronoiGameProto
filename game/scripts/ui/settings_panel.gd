class_name SettingsPanel
extends PanelContainer

## Baut die Bedienelemente aus dem Schema in GameConfig.
## Enthalten sind nur die wirksamen Parameter.

signal value_changed(key: String, value: Variant)
signal restart_requested
signal hide_requested

@onready var _rows: VBoxContainer = $Margin/Layout/Scroll/Rows
@onready var _hide_button: Button = $Margin/Layout/HideButton

var _config: GameConfig


func setup(config: GameConfig) -> void:
	_config = config
	_hide_button.pressed.connect(func(): hide_requested.emit())
	_build_waveform_row()
	_build_sliders()
	_build_toggles()
	_build_restart_row()


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


func _build_sliders() -> void:
	for entry in GameConfig.SLIDERS:
		var key: String = entry["key"]
		var is_int: bool = entry.get("is_int", false)
		var row := _make_row(entry["label"])
		var slider := HSlider.new()
		slider.min_value = entry["min"]
		slider.max_value = entry["max"]
		slider.step = entry["step"]
		slider.custom_minimum_size = Vector2(150.0, 0.0)
		slider.value = float(_config.get(key))
		var value_label := Label.new()
		value_label.custom_minimum_size = Vector2(46.0, 0.0)
		value_label.text = _format_value(slider.value, is_int)
		slider.value_changed.connect(func(value: float):
			var new_value: Variant = int(round(value)) if is_int else value
			_config.set(key, new_value)
			value_label.text = _format_value(value, is_int)
			value_changed.emit(key, new_value))
		row.add_child(slider)
		row.add_child(value_label)


func _build_toggles() -> void:
	for entry in GameConfig.TOGGLES:
		var key: String = entry["key"]
		var row := _make_row(entry["label"])
		var check := CheckBox.new()
		check.button_pressed = bool(_config.get(key))
		check.toggled.connect(func(pressed: bool):
			_config.set(key, pressed)
			value_changed.emit(key, pressed))
		row.add_child(check)


func _build_restart_row() -> void:
	var row := HBoxContainer.new()
	var button := Button.new()
	button.text = "Neustart"
	button.pressed.connect(func(): restart_requested.emit())
	row.add_child(button)
	_rows.add_child(row)


func _make_row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(170.0, 0.0)
	row.add_child(label)
	_rows.add_child(row)
	return row


func _format_value(value: float, is_int: bool) -> String:
	return str(int(round(value))) if is_int else "%.2f" % value
