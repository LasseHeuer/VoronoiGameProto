extends GutTest

## Tests fuer view/halftone_overlay.gd und das Halbton-Schema in GameConfig.

func test_shader_loads() -> void:
	var shader := load(HalftoneOverlay.SHADER_PATH)
	assert_not_null(shader, "der Halbton-Shader ist ladbar")
	assert_true(shader is Shader)


func test_every_shader_parameter_has_a_slider() -> void:
	var slider_keys := {}
	for entry in GameConfig.SLIDERS:
		slider_keys[entry["key"]] = true
	for key in HalftoneOverlay.PARAMS:
		assert_true(slider_keys.has(key), "Slider fuer '%s' vorhanden" % key)


func test_halftone_keys_exist_in_config_and_defaults() -> void:
	var config := GameConfig.new()
	for key in HalftoneOverlay.PARAMS:
		assert_ne(typeof(config.get(key)), TYPE_NIL, "Config-Key '%s'" % key)
		assert_true(GameConfig.DEFAULTS.has(key), "Default fuer '%s'" % key)
	assert_true(GameConfig.TOGGLES.any(func(entry): return entry["key"] == "halftone_enabled"))
	assert_true(GameConfig.SETTING_GROUPS.has("Halbton"))


func test_overlay_maps_config_to_shader_uniforms() -> void:
	var config := GameConfig.new()
	config.halftone_dot_size = 9.0
	config.halftone_angle = 33.0
	config.halftone_amount = 0.5
	var overlay := HalftoneOverlay.new()
	add_child_autofree(overlay)
	overlay.setup(config)

	assert_not_null(overlay.material, "das Overlay baut sein Material selbst")
	var material: ShaderMaterial = overlay.material
	assert_almost_eq(float(material.get_shader_parameter("u_dot_size")), 9.0, 0.0001)
	assert_almost_eq(float(material.get_shader_parameter("u_angle")), 33.0, 0.0001)
	assert_almost_eq(float(material.get_shader_parameter("u_amount")), 0.5, 0.0001)
	assert_true(overlay.visible, "standardmaessig ist der Effekt eingeschaltet")


func test_overlay_updates_live_and_hides_when_disabled() -> void:
	var config := GameConfig.new()
	var overlay := HalftoneOverlay.new()
	add_child_autofree(overlay)
	overlay.setup(config)
	var material: ShaderMaterial = overlay.material

	config.halftone_dot_size = 3.0
	overlay.apply()
	assert_almost_eq(float(material.get_shader_parameter("u_dot_size")), 3.0, 0.0001)

	config.halftone_enabled = false
	overlay.apply()
	assert_false(overlay.visible, "abgeschaltet wird nichts gerastert")
