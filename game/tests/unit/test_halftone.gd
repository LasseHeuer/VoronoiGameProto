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
	assert_true(GameConfig.DEFAULTS.has("halftone_pattern"))
	assert_true(GameConfig.CHOICES.any(func(entry): return entry["key"] == "halftone_pattern"))
	assert_true(GameConfig.TOGGLES.any(func(entry): return entry["key"] == "halftone_enabled"))
	assert_true(GameConfig.SETTING_GROUPS.has("Halbton"))


func test_overlay_maps_config_to_shader_uniforms() -> void:
	var config := GameConfig.new()
	config.halftone_pattern_scaling = 9.0
	config.halftone_cyan_rotation = 33.0
	config.halftone_alpha_threshold = 0.25
	config.halftone_cyan_ink = 0.25
	config.halftone_cyan_noise_strength = 0.75
	config.halftone_magenta_noise_scaling = 11.0
	var overlay := HalftoneOverlay.new()
	add_child_autofree(overlay)
	overlay.setup(config)

	assert_not_null(overlay.material, "das Overlay baut sein Material selbst")
	var material: ShaderMaterial = overlay.material
	assert_almost_eq(float(material.get_shader_parameter("u_pattern_scaling")), 9.0, 0.0001)
	assert_almost_eq(float(material.get_shader_parameter("u_cyan_rotation")), 33.0, 0.0001)
	assert_almost_eq(float(material.get_shader_parameter("u_alpha_threshold")), 0.25, 0.0001)
	assert_almost_eq(float(material.get_shader_parameter("u_cyan_ink")), 0.25, 0.0001)
	assert_almost_eq(float(material.get_shader_parameter("u_cyan_noise_strength")), 0.75, 0.0001)
	assert_almost_eq(float(material.get_shader_parameter("u_magenta_noise_scaling")), 11.0, 0.0001)
	assert_not_null(material.get_shader_parameter("u_pattern"), "das Streumuster ist gesetzt")
	assert_not_null(material.get_shader_parameter("u_noise"), "die Rauschtextur ist gesetzt")
	assert_true(overlay.visible, "standardmaessig ist der Effekt eingeschaltet")


func test_overlay_updates_live_and_hides_when_disabled() -> void:
	var config := GameConfig.new()
	var overlay := HalftoneOverlay.new()
	add_child_autofree(overlay)
	overlay.setup(config)
	var material: ShaderMaterial = overlay.material

	config.halftone_pattern_scaling = 3.0
	overlay.apply()
	assert_almost_eq(float(material.get_shader_parameter("u_pattern_scaling")), 3.0, 0.0001)

	config.halftone_enabled = false
	overlay.apply()
	assert_false(overlay.visible, "abgeschaltet wird nichts gerastert")


func test_pattern_image_is_a_valid_halftone_cell() -> void:
	var image := HalftoneOverlay.build_pattern_image(16)
	assert_eq(image.get_width(), 16)
	assert_eq(image.get_height(), 16)
	var center := image.get_pixel(8, 8)
	var corner := image.get_pixel(0, 0)
	assert_almost_eq(center.r, 0.0, 0.05, "die Zellmitte hat die kleinste Schwelle")
	assert_gt(corner.r, 0.8, "die Zellecke hat die groesste Schwelle")


func test_noise_image_has_four_varied_channels() -> void:
	var image := HalftoneOverlay.build_noise_image(64)
	assert_eq(image.get_width(), 64)
	assert_eq(image.get_height(), 64)
	var min_r := 1.0
	var max_r := 0.0
	for y in 64:
		for x in 64:
			min_r = minf(min_r, image.get_pixel(x, y).r)
			max_r = maxf(max_r, image.get_pixel(x, y).r)
	assert_gt(max_r - min_r, 0.1, "der Rauschkanal variiert")
	var center := image.get_pixel(32, 32)
	assert_ne(center.r, center.g, "C und M streuen unterschiedlich")


func test_asset_pattern_is_loadable() -> void:
	var texture := load(HalftoneOverlay.PATTERN_ASSET_PATH)
	assert_not_null(texture, "die PNG-Musterdatei ist ladbar")
	assert_true(texture is Texture2D)


func test_overlay_switches_between_pattern_sources() -> void:
	var config := GameConfig.new()
	config.halftone_pattern = HalftoneOverlay.PATTERN_SOURCE_ASSET
	var overlay := HalftoneOverlay.new()
	add_child_autofree(overlay)
	overlay.setup(config)
	var material: ShaderMaterial = overlay.material
	var asset_texture = material.get_shader_parameter("u_pattern")

	config.halftone_pattern = HalftoneOverlay.PATTERN_SOURCE_CODE
	overlay.apply()
	var code_texture = material.get_shader_parameter("u_pattern")

	assert_not_null(asset_texture, "das PNG-Muster ist gesetzt")
	assert_not_null(code_texture, "das erzeugte Muster ist gesetzt")
	assert_ne(asset_texture, code_texture, "die beiden Quellen sind verschiedene Texturen")
