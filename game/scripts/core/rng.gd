class_name DeterministicRng
extends RefCounted

## Duenne Huelle um RandomNumberGenerator, damit Punktgenerierung mit
## festem Seed reproduzierbar ist (Tests, manueller Vergleich mit der
## JS-Version). Seed 0 bedeutet "zufaellig".

var _rng := RandomNumberGenerator.new()

func _init(seed_value: int = 0) -> void:
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value

func next_float() -> float:
	return _rng.randf()
