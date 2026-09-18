class_name SettingsStore
extends RefCounted

## Speichert und laedt alle einstellbaren Werte aus GameConfig
## nach user://settings.cfg.

const PATH := "user://settings.cfg"
const SECTION := "settings"

## Alle Keys des Config-Schemas (Slider, Toggles, Auswahlfelder).
static func schema_keys() -> PackedStringArray:
	var keys := PackedStringArray()
	for entry in GameConfig.SLIDERS:
		keys.append(entry["key"])
	for entry in GameConfig.TOGGLES:
		keys.append(entry["key"])
	for entry in GameConfig.CHOICES:
		keys.append(entry["key"])
	return keys

static func save(config: GameConfig) -> void:
	var cfg := ConfigFile.new()
	for key in schema_keys():
		cfg.set_value(SECTION, key, config.get(key))
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("Einstellungen konnten nicht gespeichert werden: %s" % PATH)

static func load_into(config: GameConfig) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key in schema_keys():
		if not cfg.has_section_key(SECTION, key):
			continue
		var value = cfg.get_value(SECTION, key)
		var current = config.get(key)
		if typeof(current) == TYPE_INT:
			config.set(key, int(value))
		elif typeof(current) == TYPE_FLOAT:
			config.set(key, float(value))
		elif typeof(current) == TYPE_BOOL:
			config.set(key, bool(value))
		elif typeof(current) == TYPE_STRING:
			config.set(key, String(value))
