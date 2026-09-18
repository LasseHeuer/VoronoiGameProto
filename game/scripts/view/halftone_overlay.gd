class_name HalftoneOverlay
extends ColorRect

## Bildschirmweiter CMYK-Halbton-Effekt.
##
## Das Rechteck liegt ueber dem Spiel, aber unter dem Einstellungsmenue.
## Dadurch wird alles ausser den Einstellungen gerastert. Die Werte kommen aus
## GameConfig und werden ohne Neustart uebernommen.
##
## Das Streumuster kommt entweder aus dem Code (beim Start erzeugte Halbtonzelle)
## oder aus einer PNG-Datei; die Quelle waehlt der Regler "Streumuster".

const SHADER_PATH := "res://shaders/halftone.gdshader"
## Musterquelle als PNG-Datei.
const PATTERN_ASSET_PATH := "res://assets/halftone_pattern.png"
const PATTERN_SOURCE_CODE := "code"
const PATTERN_SOURCE_ASSET := "asset"
## Kantenlaenge der im Code erzeugten Halbtonzelle.
const PATTERN_SIZE := 64
## Kantenlaenge und Startwert der im Code erzeugten Rauschtextur. Die vier
## Farbkanaele sind unabhaengig, damit jede Druckfarbe anders streut.
const NOISE_SIZE := 128
const NOISE_SEED := 20250918

## Config-Key -> Uniform-Name des Shaders.
const PARAMS := {
	"halftone_pattern_scaling": "u_pattern_scaling",
	"halftone_sampling_quality": "u_sampling_quality",
	"halftone_cyan_rotation": "u_cyan_rotation",
	"halftone_magenta_rotation": "u_magenta_rotation",
	"halftone_yellow_rotation": "u_yellow_rotation",
	"halftone_black_rotation": "u_black_rotation",
	"halftone_cyan_offset_rotation": "u_cyan_offset_rotation",
	"halftone_magenta_offset_rotation": "u_magenta_offset_rotation",
	"halftone_yellow_offset_rotation": "u_yellow_offset_rotation",
	"halftone_black_offset_rotation": "u_black_offset_rotation",
	"halftone_alpha_threshold": "u_alpha_threshold",
	"halftone_cyan_ink": "u_cyan_ink",
	"halftone_magenta_ink": "u_magenta_ink",
	"halftone_yellow_ink": "u_yellow_ink",
	"halftone_black_ink": "u_black_ink",
	"halftone_cyan_noise_strength": "u_cyan_noise_strength",
	"halftone_magenta_noise_strength": "u_magenta_noise_strength",
	"halftone_yellow_noise_strength": "u_yellow_noise_strength",
	"halftone_black_noise_strength": "u_black_noise_strength",
	"halftone_cyan_noise_scaling": "u_cyan_noise_scaling",
	"halftone_magenta_noise_scaling": "u_magenta_noise_scaling",
	"halftone_yellow_noise_scaling": "u_yellow_noise_scaling",
	"halftone_black_noise_scaling": "u_black_noise_scaling",
}

var _material: ShaderMaterial
var _config: GameConfig
var _generated_pattern: ImageTexture
var _generated_noise: ImageTexture
var _asset_pattern: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_material()


func setup(config: GameConfig) -> void:
	_config = config
	apply()


## Uebertraegt alle Effektwerte in den Shader, waehlt das Streumuster und
## blendet den Effekt ein oder aus. Wird bei jeder Aenderung eines
## Halbton-Reglers aufgerufen.
func apply() -> void:
	_ensure_material()
	if _config == null or _material == null:
		return
	visible = _config.halftone_enabled
	for key in PARAMS:
		_material.set_shader_parameter(PARAMS[key], float(_config.get(key)))
	_material.set_shader_parameter("u_pattern", _pattern_texture())
	_material.set_shader_parameter("u_noise", _noise_texture())


## Halbtonzelle als Bild: die Schwelle waechst mit dem Quadrat des Abstands zur
## Zellmitte. Dadurch ist die Punktflaeche proportional zur Farbdichte.
static func build_pattern_image(size: int) -> Image:
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGB8)
	var center := Vector2(size, size) * 0.5
	var max_distance := center.length()
	for y in size:
		for x in size:
			var distance := Vector2(x + 0.5, y + 0.5).distance_to(center) / max_distance
			var threshold := clampf(distance * distance, 0.0, 1.0)
			image.set_pixel(x, y, Color(threshold, threshold, threshold))
	return image


func _pattern_texture() -> Texture2D:
	if _config != null and _config.halftone_pattern == PATTERN_SOURCE_ASSET:
		if _asset_pattern == null:
			_asset_pattern = load(PATTERN_ASSET_PATH) as Texture2D
			if _asset_pattern == null:
				push_warning("Halbton-Muster konnte nicht geladen werden: %s" % PATTERN_ASSET_PATH)
		if _asset_pattern != null:
			return _asset_pattern
	return _generated_pattern_texture()


func _generated_pattern_texture() -> ImageTexture:
	if _generated_pattern == null:
		_generated_pattern = ImageTexture.create_from_image(build_pattern_image(PATTERN_SIZE))
	return _generated_pattern


## Rauschtextur als Bild: vier unabhaengige, weiche Rauschkanaele fuer C, M, Y
## und K. Der feste Startwert macht das Muster reproduzierbar.
static func build_noise_image(size: int) -> Image:
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var noises: Array[FastNoiseLite] = []
	for i in 4:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		noise.seed = NOISE_SEED + i * 101
		noise.frequency = 0.02
		noises.append(noise)
	for y in size:
		for x in size:
			image.set_pixel(x, y, Color(
				clampf(noises[0].get_noise_2d(x, y) * 0.5 + 0.5, 0.0, 1.0),
				clampf(noises[1].get_noise_2d(x, y) * 0.5 + 0.5, 0.0, 1.0),
				clampf(noises[2].get_noise_2d(x, y) * 0.5 + 0.5, 0.0, 1.0),
				clampf(noises[3].get_noise_2d(x, y) * 0.5 + 0.5, 0.0, 1.0)))
	return image


func _noise_texture() -> ImageTexture:
	if _generated_noise == null:
		_generated_noise = ImageTexture.create_from_image(build_noise_image(NOISE_SIZE))
	return _generated_noise


func _ensure_material() -> void:
	if _material != null:
		return
	var shader := load(SHADER_PATH) as Shader
	if shader == null:
		push_warning("Halbton-Shader konnte nicht geladen werden: %s" % SHADER_PATH)
		return
	_material = ShaderMaterial.new()
	_material.shader = shader
	material = _material
