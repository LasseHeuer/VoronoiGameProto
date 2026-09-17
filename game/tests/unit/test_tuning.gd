extends GutTest

## Tests fuer audio/tuning.gd: Runden auf die naechste Note und die
## Erweiterbarkeit auf andere Temperaturen.


func test_default_is_12_step_equal_temperament_with_a432() -> void:
	var tuning := Tuning.default_tuning()
	assert_eq(tuning.reference_freq, 432.0, "Referenzton ist A4 = 432 Hz")
	assert_eq(tuning.ratios.size(), 12, "zwoelf Schritte pro Oktave")


func test_nearest_keeps_a_reference_note() -> void:
	var tuning := Tuning.default_tuning()
	assert_almost_eq(tuning.nearest(432.0), 432.0, 0.001)
	assert_almost_eq(tuning.nearest(216.0), 216.0, 0.001, "eine Oktave tiefer")
	assert_almost_eq(tuning.nearest(864.0), 864.0, 0.001, "eine Oktave hoeher")


func test_nearest_rounds_to_the_closest_semitone() -> void:
	var tuning := Tuning.default_tuning()
	# 0.4 Halbtoene ueber A liegt naeher an A, 0.6 naeher am naechsten Halbton.
	assert_almost_eq(tuning.nearest(432.0 * pow(2.0, 0.4 / 12.0)), 432.0, 0.001)
	var above := 432.0 * pow(2.0, 0.6 / 12.0)
	assert_almost_eq(tuning.nearest(above), 432.0 * pow(2.0, 1.0 / 12.0), 0.001)


func test_nearest_is_stable_for_already_snapped_notes() -> void:
	var tuning := Tuning.default_tuning()
	var snapped := tuning.nearest(700.0)
	assert_almost_eq(tuning.nearest(snapped), snapped, 0.001)


func test_nearest_ignores_invalid_input() -> void:
	var tuning := Tuning.default_tuning()
	assert_eq(tuning.nearest(0.0), 0.0)
	assert_eq(tuning.nearest(-5.0), -5.0)


func test_other_equal_temperaments_can_be_created() -> void:
	var tuning := Tuning.equal_temperament(19, 432.0, "19-TET A432")
	assert_eq(tuning.ratios.size(), 19, "19 Schritte pro Oktave")
	assert_almost_eq(tuning.nearest(432.0 * pow(2.0, 0.4 / 19.0)), 432.0, 0.001)
	assert_almost_eq(tuning.nearest(432.0 * pow(2.0, 0.6 / 19.0)),
		432.0 * pow(2.0, 1.0 / 19.0), 0.001)


func test_custom_ratios_support_other_systems() -> void:
	# Beispiel reine Stimmung: Referenz, grosse Terz und Quinte.
	var ratios := PackedFloat64Array([1.0, 5.0 / 4.0, 3.0 / 2.0])
	var tuning := Tuning.new("just", 432.0, ratios)
	assert_almost_eq(tuning.nearest(432.0 * 1.5), 432.0 * 1.5, 0.001, "reine Quinte bleibt erhalten")
	assert_almost_eq(tuning.nearest(432.0 * 1.25), 432.0 * 1.25, 0.001, "reine grosse Terz bleibt erhalten")
