class_name HalftoneOverlay
extends ColorRect

## Bildschirmweiter Halbtonraster-Effekt.
##
## Das Rechteck liegt ueber dem Spiel, aber unter dem Einstellungsmenue.
## Dadurch wird alles ausser den Einstellungen gerastert. Die Werte kommen aus
## GameConfig und werden ohne Neustart uebernommen.

const SHADER_PATH := "res://shaders/halftone.gdshader"

## Config-Key -> Uniform-Name des Shaders.
const PARAMS := {
	"halftone_dot_size": "u_dot_size",
	"halftone_angle": "u_angle",
	"halftone_gain": "u_gain",
	"halftone_contrast": "u_contrast",
	"halftone_softness": "u_softness",
	"halftone_separation": "u_separation",
	"halftone_paper": "u_paper",
	"halftone_amount": "u_amount",
}

var _material: ShaderMaterial
var _config: GameConfig


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_material()


func setup(config: GameConfig) -> void:
	_config = config
	apply()


## Uebertraegt alle Effektwerte in den Shader und blendet den Effekt ein oder
## aus. Wird bei jeder Aenderung eines Halbton-Reglers aufgerufen.
func apply() -> void:
	_ensure_material()
	if _config == null or _material == null:
		return
	visible = _config.halftone_enabled
	for key in PARAMS:
		_material.set_shader_parameter(PARAMS[key], float(_config.get(key)))


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
