extends GutTest

## Tests fuer app/config.gd, app/settings_store.gd und die Farbhelfer
## von core/board.gd.

func test_schema_keys_exist_in_config() -> void:
	var config := GameConfig.new()
	for entry in GameConfig.SLIDERS:
		var key: String = entry["key"]
		var value: Variant = config.get(key)
		assert_ne(typeof(value), TYPE_NIL, "Slider-Key '%s' hat eine Eigenschaft" % key)
		assert_between(float(value), float(entry["min"]), float(entry["max"]),
			"Default von '%s' liegt im erlaubten Bereich" % key)
	for entry in GameConfig.TOGGLES:
		var key: String = entry["key"]
		assert_ne(typeof(config.get(key)), TYPE_NIL, "Toggle-Key '%s' hat eine Eigenschaft" % key)
		assert_eq(typeof(config.get(key)), TYPE_BOOL)


func test_defaults_cover_the_whole_schema() -> void:
	for entry in GameConfig.SLIDERS:
		assert_true(GameConfig.DEFAULTS.has(entry["key"]), entry["key"])
	for entry in GameConfig.TOGGLES:
		assert_true(GameConfig.DEFAULTS.has(entry["key"]), entry["key"])
	for entry in GameConfig.CHOICES:
		assert_true(GameConfig.DEFAULTS.has(entry["key"]), entry["key"])
	for entry in GameConfig.COLORS:
		assert_true(GameConfig.DEFAULTS.has(entry["key"]), entry["key"])


func test_defaults_match_the_reference_values() -> void:
	var config := GameConfig.new()
	assert_eq(config.waveform, "triangle")
	assert_almost_eq(config.attack, 0.05, 0.0001)
	assert_almost_eq(config.decay, 0.2, 0.0001)
	assert_almost_eq(config.sustain, 0.2, 0.0001)
	assert_almost_eq(config.release, 0.1, 0.0001)
	assert_almost_eq(config.cutoff, 500.0, 0.0001)
	assert_almost_eq(config.drag_tone_volume, 0.2, 0.0001)
	assert_almost_eq(config.drag_neighbor_factor, 0.25, 0.0001)
	assert_almost_eq(config.freq_threshold, 0.2, 0.0001)
	assert_almost_eq(config.spread_time, 0.6, 0.0001)
	assert_eq(config.spread_depth, 2)
	assert_eq(config.cell_count, 16)
	assert_almost_eq(config.influence_start_strength, 100.0, 0.0001)
	assert_almost_eq(config.push_factor, 0.2, 0.0001)
	assert_almost_eq(config.push_radius, 40.0, 0.0001)
	assert_almost_eq(config.border_margin, 50.0, 0.0001)
	assert_almost_eq(config.weight_influence, 1.0, 0.0001)
	assert_almost_eq(config.point_radius, 8.0, 0.0001)
	assert_true(config.alternating_moves)
	assert_true(config.dummy_points)


func test_cell_numbers_are_hidden_by_default() -> void:
	var config := GameConfig.new()
	assert_false(config.show_cell_numbers, "die Flaechenzahlen starten ausgeblendet")
	assert_true(GameConfig.DEFAULTS.has("show_cell_numbers"))


func test_loss_step_default() -> void:
	var config := GameConfig.new()
	assert_almost_eq(config.loss_step_ms, 25.0, 0.0001, "Verlust-Schritt startet bei 25 ms")
	assert_true(GameConfig.DEFAULTS.has("loss_step_ms"))


func test_reset_to_defaults() -> void:
	var config := GameConfig.new()
	config.attack = 2.5
	config.cell_count = 99
	config.dummy_points = false
	config.reset_to_defaults()
	assert_almost_eq(config.attack, 0.05, 0.0001)
	assert_eq(config.cell_count, 16)
	assert_true(config.dummy_points)


func test_every_waveform_default_is_available() -> void:
	var config := GameConfig.new()
	assert_true(GameConfig.WAVEFORMS.has(config.waveform))
	assert_eq(GameConfig.WAVEFORMS.size(), 4)


func test_spread_time_mapping() -> void:
	var config := GameConfig.new()
	config.spread_time = 0.6
	assert_almost_eq(config.spread_time_ms(), 50.0 * pow(20.0, 0.6), 0.001)
	assert_almost_eq(config.spread_time_sec(), config.spread_time_ms() / 1000.0, 0.0001)
	config.spread_time = 0.0
	assert_almost_eq(config.spread_time_ms(), 50.0, 0.001)


func test_settings_store_keys_match_the_schema() -> void:
	var keys := SettingsStore.schema_keys()
	for entry in GameConfig.SLIDERS:
		assert_true(keys.has(entry["key"]), entry["key"])
	for entry in GameConfig.TOGGLES:
		assert_true(keys.has(entry["key"]), entry["key"])
	for entry in GameConfig.CHOICES:
		assert_true(keys.has(entry["key"]), entry["key"])
	for entry in GameConfig.COLORS:
		assert_true(keys.has(entry["key"]), entry["key"])
	assert_true(keys.has("waveform"))
	assert_eq(keys.size(), GameConfig.SLIDERS.size() + GameConfig.TOGGLES.size()
		+ GameConfig.CHOICES.size() + GameConfig.COLORS.size())


func test_board_state_color_helpers() -> void:
	var board := BoardState.new()
	board.points = PackedVector2Array([Vector2(1, 1), Vector2(2, 2), Vector2(3, 3)])
	board.dummy_points = PackedVector2Array([Vector2(-10, -10)])
	board.reset_colors()
	assert_eq(board.cell_colors.size(), 3)
	assert_false(board.has_color(0))

	board.set_cell_color(0, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(1, GameConfig.COLOR_PLAYER2)
	assert_eq(BoardState.color_id(board.cell_color(0)), 1)
	assert_eq(BoardState.color_id(board.cell_color(1)), 2)
	assert_eq(BoardState.color_id(board.cell_color(2)), 0)
	assert_eq(BoardState.color_for_id(1), GameConfig.COLOR_PLAYER1)
	assert_eq(BoardState.color_for_id(2), GameConfig.COLOR_PLAYER2)
	assert_eq(BoardState.color_for_id(0), "")

	var ids := board.color_ids()
	assert_eq(ids, PackedByteArray([1, 2, 0]))
	ids[0] = 2
	board.apply_color_ids(ids)
	assert_eq(board.cell_color(0), GameConfig.COLOR_PLAYER2)
	assert_eq(BoardState.opponent_color(GameConfig.COLOR_PLAYER1), GameConfig.COLOR_PLAYER2)
	assert_eq(BoardState.opponent_color(GameConfig.COLOR_PLAYER2), GameConfig.COLOR_PLAYER1)


func test_board_state_all_points_respects_the_dummy_switch() -> void:
	var board := BoardState.new()
	board.points = PackedVector2Array([Vector2(1, 1), Vector2(2, 2)])
	board.dummy_points = PackedVector2Array([Vector2(-10, -10)])
	board.use_dummy_points = true
	assert_eq(board.all_points().size(), 3)
	board.use_dummy_points = false
	assert_eq(board.all_points().size(), 2)


func test_stamina_end_phase_allows_multiple_moves() -> void:
	var config := GameConfig.new()
	var board := BoardState.new()
	board.reset_stamina(config)
	board.stamina_player1 = 0.0
	board.stamina_player2 = 10.0
	board.active_color = GameConfig.COLOR_PLAYER1

	board.complete_move(GameConfig.COLOR_PLAYER1, config)
	assert_eq(board.active_color, GameConfig.COLOR_PLAYER2)
	assert_false(board.game_over)
	assert_eq(board.final_move_color, GameConfig.COLOR_PLAYER2)

	board.stamina_player2 = 5.0
	board.complete_move(GameConfig.COLOR_PLAYER2, config)
	assert_false(board.game_over)
	assert_eq(board.active_color, GameConfig.COLOR_PLAYER2)

	board.stamina_player2 = 0.0
	board.complete_move(GameConfig.COLOR_PLAYER2, config)
	assert_true(board.game_over)


func test_remaining_color_reports_the_last_surviving_player() -> void:
	var board := BoardState.new()
	board.points = PackedVector2Array([Vector2.ZERO, Vector2.ONE, Vector2(2.0, 2.0)])
	board.reset_colors()
	assert_eq(board.remaining_color(), "", "ohne Farben gibt es keinen Sieger")
	board.set_cell_color(0, GameConfig.COLOR_PLAYER1)
	assert_eq(board.remaining_color(), GameConfig.COLOR_PLAYER1)
	board.set_cell_color(1, GameConfig.COLOR_PLAYER2)
	assert_eq(board.remaining_color(), "", "solange beide Farben liegen, laeuft das Spiel")
	board.set_cell_color(1, GameConfig.COLOR_PLAYER1)
	board.set_cell_color(2, GameConfig.COLOR_PLAYER1)
	assert_eq(board.remaining_color(), GameConfig.COLOR_PLAYER1, "nur noch Rot: Rot gewinnt")


func test_settings_panel_builds_rows_and_writes_back_to_config() -> void:
	var config := GameConfig.new()
	var panel: SettingsPanel = load("res://scenes/SettingsPanel.tscn").instantiate()
	add_child_autofree(panel)
	panel.setup(config)

	var changed: Array = []
	panel.value_changed.connect(func(key: String, _value: Variant): changed.append(key))

	# Jede Gruppe bekommt einen Abschnittstitel, dazu alle Auswahlfelder,
	# Farbwaehler, Regler und Schalter aus dem Schema.
	assert_eq(panel._rows.get_children().size(),
		GameConfig.SETTING_GROUPS.size() + GameConfig.CHOICES.size()
		+ GameConfig.COLORS.size() + GameConfig.SLIDERS.size() + GameConfig.TOGGLES.size())
	assert_eq(panel._controls.size(),
		GameConfig.CHOICES.size() + GameConfig.COLORS.size()
		+ GameConfig.SLIDERS.size() + GameConfig.TOGGLES.size())

	var expected_changes := 0
	for entry in GameConfig.SLIDERS:
		var key: String = entry["key"]
		var slider: HSlider = panel._controls[key]
		if not is_equal_approx(float(config.get(key)), float(entry["max"])):
			expected_changes += 1
		assert_almost_eq(slider.min_value, float(entry["min"]), 0.0001)
		assert_almost_eq(slider.max_value, float(entry["max"]), 0.0001)
		slider.value = slider.max_value
		var stored: Variant = config.get(key)
		if entry.get("is_int", false):
			assert_eq(int(stored), int(entry["max"]), key)
		else:
			assert_almost_eq(float(stored), float(entry["max"]), 0.0001, key)
	assert_eq(changed.size(), expected_changes, "jede tatsaechliche Aenderung meldet sich")


func test_settings_panel_choice_dropdowns_write_back_to_config() -> void:
	var config := GameConfig.new()
	var panel: SettingsPanel = load("res://scenes/SettingsPanel.tscn").instantiate()
	add_child_autofree(panel)
	panel.setup(config)

	for entry in GameConfig.CHOICES:
		var key: String = entry["key"]
		var values: Array = entry["values"]
		var option: OptionButton = panel._controls[key]
		assert_eq(option.item_count, values.size(), key)
		assert_eq(option.selected, values.find(config.get(key)), key)
		var other := (option.selected + 1) % values.size()
		option.item_selected.emit(other)
		assert_eq(config.get(key), values[other], key)


func test_settings_panel_color_picker_writes_back_to_config() -> void:
	var config := GameConfig.new()
	var panel: SettingsPanel = load("res://scenes/SettingsPanel.tscn").instantiate()
	add_child_autofree(panel)
	panel.setup(config)

	for entry in GameConfig.COLORS:
		var key: String = entry["key"]
		var picker: ColorPickerButton = panel._controls[key]
		assert_eq(picker.color, Color(String(config.get(key))), key)
		picker.color_changed.emit(Color("#123456"))
		assert_eq(config.get(key), "#123456", key)


func test_settings_panel_toggles_and_restart_button() -> void:
	var config := GameConfig.new()
	var panel: SettingsPanel = load("res://scenes/SettingsPanel.tscn").instantiate()
	add_child_autofree(panel)
	panel.setup(config)

	var requested := []
	panel.restart_requested.connect(func(): requested.append(true))
	panel.hide_requested.connect(func(): requested.append("hide"))

	for entry in GameConfig.TOGGLES:
		var key: String = entry["key"]
		var check: CheckBox = panel._controls[key]
		check.button_pressed = not check.button_pressed
		assert_eq(bool(config.get(key)), check.button_pressed, key)

	var restart_button: Button = panel.get_node("Margin/Layout/RestartButton")
	restart_button.pressed.emit()
	assert_eq(requested.size(), 1)

	var close_button: Button = panel.get_node("Margin/Layout/Header/CloseButton")
	close_button.pressed.emit()
	assert_eq(requested.size(), 2)


func test_settings_panel_spans_the_full_window_height() -> void:
	var panel: SettingsPanel = load("res://scenes/SettingsPanel.tscn").instantiate()
	add_child_autofree(panel)
	assert_eq(panel.anchor_top, 0.0)
	assert_eq(panel.anchor_bottom, 1.0, "das Menue geht ueber die ganze Hoehe")


func test_settings_panel_sections_start_collapsed_and_toggle() -> void:
	var config := GameConfig.new()
	var panel: SettingsPanel = load("res://scenes/SettingsPanel.tscn").instantiate()
	add_child_autofree(panel)
	panel.setup(config)

	for group in GameConfig.SETTING_GROUPS:
		var rows: Array = panel._rows_by_group.get(group, [])
		assert_false(rows.is_empty(), "Rubrik '%s' hat Zeilen" % group)
		for row in rows:
			assert_false(row.visible, "Rubrik '%s' startet eingeklappt" % group)
		panel._toggle_section(group)
		var shown := 0
		for row in rows:
			if row.visible:
				shown += 1
		assert_eq(shown, rows.size(), "Rubrik '%s' nach dem Ausklappen" % group)


func test_settings_panel_draws_its_section_headers() -> void:
	var config := GameConfig.new()
	var panel: SettingsPanel = load("res://scenes/SettingsPanel.tscn").instantiate()
	add_child_autofree(panel)
	panel.setup(config)
	panel.visible = true
	panel.queue_redraw()
	await wait_process_frames(2)
	assert_true(true, "die Rubrik-Knoepfe zeichnen ohne Fehler")


func test_settings_panel_fine_step_is_a_tenth() -> void:
	var panel: SettingsPanel = load("res://scenes/SettingsPanel.tscn").instantiate()
	add_child_autofree(panel)
	assert_almost_eq(panel._fine_step(0.01), 0.001, 0.000001)
	assert_almost_eq(panel._fine_step(1.0), 0.1, 0.000001)


## Das Zahlenfeld ist direkt editierbar: Klick waehlt den Wert aus, Enter oder
## Fokusverlust uebernehmen die Eingabe und begrenzen sie auf den Bereich.
func test_settings_panel_value_field_is_editable() -> void:
	var config := GameConfig.new()
	var panel: SettingsPanel = load("res://scenes/SettingsPanel.tscn").instantiate()
	add_child_autofree(panel)
	panel.setup(config)

	var field: LineEdit = panel._value_fields["attack"]
	var slider: HSlider = panel._controls["attack"]
	assert_true(field.select_all_on_focus, "ein Klick waehlt den Wert aus")

	field.text = "1.75"
	field.text_submitted.emit(field.text)
	assert_almost_eq(config.attack, 1.75, 0.0001, "die Eingabe wird uebernommen")
	assert_almost_eq(slider.value, 1.75, 0.0001, "der Regler folgt der Eingabe")

	field.text = "999"
	field.focus_exited.emit()
	assert_almost_eq(config.attack, slider.max_value, 0.0001, "zu grosse Werte werden begrenzt")

	field.text = "abc"
	field.text_submitted.emit(field.text)
	assert_almost_eq(config.attack, slider.max_value, 0.0001, "ungueltiger Text aendert nichts")


## Die Halbton-Rasterweite laesst sich bis 40 einstellen.
func test_halftone_raster_can_be_set_higher() -> void:
	for entry in GameConfig.SLIDERS:
		if entry["key"] == "halftone_pattern_scaling":
			assert_almost_eq(float(entry["max"]), 40.0, 0.0001, "Rasterweite bis 40")
			return
	assert_true(false, "Rasterweite-Slider vorhanden")


func test_settings_panel_settings_snapshot_lists_current_values() -> void:
	var config := GameConfig.new()
	var panel: SettingsPanel = load("res://scenes/SettingsPanel.tscn").instantiate()
	add_child_autofree(panel)
	panel.setup(config)
	config.attack = 1.25
	config.dummy_points = false
	config.waveform = "square"
	var snapshot: String = panel._settings_snapshot()
	assert_true(snapshot.contains("\"attack\": 1.25"), snapshot)
	assert_true(snapshot.contains("\"dummy_points\": false"), snapshot)
	assert_true(snapshot.contains("\"waveform\": \"square\""), snapshot)
	assert_true(snapshot.contains("\"halftone_cyan_ink\": 1.0"), snapshot)


func test_settings_panel_has_a_copy_button() -> void:
	var config := GameConfig.new()
	var panel: SettingsPanel = load("res://scenes/SettingsPanel.tscn").instantiate()
	add_child_autofree(panel)
	panel.setup(config)
	var button: Button = panel.get_node("Margin/Layout/CopyButton")
	assert_not_null(button)
	assert_false(button.tooltip_text.is_empty())
	button.pressed.emit()
	assert_true(true, "das Kopieren laeuft ohne Fehler")
