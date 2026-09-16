class_name AudioSetup
extends RefCounted

## Bus-Layout: alle Stimmen laufen ueber den Bus "Synth" (globaler
## Lowpass mit dem Cutoff-Regler) und danach ueber "Master", auf dem der
## Limiter als Kompressor sitzt.
##
## Gegenstueck zum Web-Audio-Aufbau aus src/core.js: pro Note wurde dort
## ein eigener Biquad-Filter gesetzt - da der Cutoff global ist, ist ein
## Bus-Filter verhaltensgleich.

const BUS_SYNTH := "Synth"

const LIMITER_THRESHOLD_DB := -8.0
const LIMITER_RATIO := 20.0
const LIMITER_ATTACK_US := 3000.0
const LIMITER_RELEASE_MS := 200.0


static func ensure_layout(config: GameConfig) -> void:
	var master := AudioServer.get_bus_index("Master")
	if master >= 0:
		_ensure_limiter(master)

	var synth := AudioServer.get_bus_index(BUS_SYNTH)
	if synth < 0:
		synth = AudioServer.bus_count
		AudioServer.add_bus(synth)
		AudioServer.set_bus_name(synth, BUS_SYNTH)
		AudioServer.set_bus_send(synth, "Master")
	_ensure_lowpass(synth, config.cutoff)


static func apply_cutoff(config: GameConfig) -> void:
	var synth := AudioServer.get_bus_index(BUS_SYNTH)
	if synth < 0:
		return
	for i in range(AudioServer.get_bus_effect_count(synth)):
		var effect := AudioServer.get_bus_effect(synth, i)
		if effect is AudioEffectLowPassFilter:
			(effect as AudioEffectLowPassFilter).cutoff_hz = config.cutoff
			return


static func _ensure_lowpass(bus: int, cutoff: float) -> void:
	for i in range(AudioServer.get_bus_effect_count(bus)):
		var existing := AudioServer.get_bus_effect(bus, i)
		if existing is AudioEffectLowPassFilter:
			(existing as AudioEffectLowPassFilter).cutoff_hz = cutoff
			return
	var filter := AudioEffectLowPassFilter.new()
	filter.cutoff_hz = cutoff
	AudioServer.add_bus_effect(bus, filter)


static func _ensure_limiter(bus: int) -> void:
	for i in range(AudioServer.get_bus_effect_count(bus)):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectCompressor:
			return
	var compressor := AudioEffectCompressor.new()
	compressor.threshold = LIMITER_THRESHOLD_DB
	compressor.ratio = LIMITER_RATIO
	compressor.attack_us = LIMITER_ATTACK_US
	compressor.release_ms = LIMITER_RELEASE_MS
	AudioServer.add_bus_effect(bus, compressor)
