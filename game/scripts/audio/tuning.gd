class_name Tuning
extends RefCounted

## Stimmung (Temperament) fuer die Zelltoene.
##
## Bildet eine beliebige Frequenz auf die naechste Note einer Skala ab
## (Naehe ueber das Frequenzverhaeltnis, also im Tonhoehen- und nicht im
## linearen Frequenzabstand). Eine Stimmung besteht aus einer
## Referenzfrequenz und den Verhaeltnissen der Noten innerhalb einer Oktave
## (aufsteigend, Faktor 1.0 = Referenzton). Damit sind gleichstufige
## Temperaturen (12-TET, 19-TET, ...) und spaeter auch andere Systeme wie
## reine Stimmung mit festen Intervallen darstellbar.
##
## Standard ist die 12-stufige gleichstufige Stimmung mit A4 = 432 Hz.

const DEFAULT_DIVISIONS := 12
const DEFAULT_REFERENCE_FREQ := 432.0
## Natuerlicher Logarithmus von 2 (fuer die Oktav-Berechnung).
const LN2 := 0.6931471805599453

var id: String
var reference_freq: float
var ratios: PackedFloat64Array


func _init(p_id: String, p_reference_freq: float, p_ratios: PackedFloat64Array) -> void:
	id = p_id
	reference_freq = p_reference_freq
	ratios = p_ratios


## 12-stufig gleichstufig mit A4 = 432 Hz (Standard).
static func default_tuning() -> Tuning:
	return equal_temperament(DEFAULT_DIVISIONS, DEFAULT_REFERENCE_FREQ, "12-TET A432")


## Gleichstufige Stimmung mit `divisions` gleich grossen Schritten pro Oktave.
static func equal_temperament(divisions: int, reference_freq: float, p_id := "") -> Tuning:
	var p_ratios := PackedFloat64Array()
	for i in range(divisions):
		p_ratios.append(pow(2.0, float(i) / float(divisions)))
	return Tuning.new(p_id, reference_freq, p_ratios)


## Naechste Note zur Frequenz `freq`. Ungueltige Eingaben bleiben unveraendert.
func nearest(freq: float) -> float:
	if freq <= 0.0 or reference_freq <= 0.0 or ratios.is_empty():
		return freq
	var octave := int(floor(log(freq / reference_freq) / LN2))
	var best := freq
	var best_distance := INF
	for o in range(octave - 1, octave + 2):
		var factor := pow(2.0, float(o))
		for ratio in ratios:
			var candidate := reference_freq * ratio * factor
			var distance := absf(log(candidate / freq))
			if distance < best_distance:
				best_distance = distance
				best = candidate
	return best
