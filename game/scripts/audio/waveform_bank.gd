class_name WaveformBank
extends RefCounted

## Erzeugt loopfaehige Grundwellenformen als AudioStreamWAV.
##
## Eine Periode mit PERIOD_SAMPLES Samples ergibt die exakte
## Grundfrequenz BASE_FREQ; die Tonhoehe wird spaeter ueber pitch_scale
## eingestellt (wie die frequency eines Web-Audio-Oszillators).
##
## Bandbegrenzung: nur Harmonische bis MAX_HARMONICS, damit auch die
## hoechste Tonhoehe (1200 Hz) nicht aliast. Die Wellenformen werden auf
## Spitzenwert 1.0 normalisiert, passend zum Web-Audio-Oszillator.

const SAMPLE_RATE := 44100
const PERIOD_SAMPLES := 100
const BASE_FREQ := 441.0
const MAX_HARMONICS := 18


static func build_all() -> Dictionary:
	var streams := {}
	for waveform in GameConfig.WAVEFORMS:
		streams[waveform] = build(waveform)
	return streams


static func build(waveform: String) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(PERIOD_SAMPLES)
	var peak := 0.0
	for i in range(PERIOD_SAMPLES):
		var value := _sample(waveform, float(i) / float(PERIOD_SAMPLES))
		samples[i] = value
		peak = maxf(peak, absf(value))
	if peak <= 0.0:
		peak = 1.0

	var data := PackedByteArray()
	data.resize(PERIOD_SAMPLES * 2)
	for i in range(PERIOD_SAMPLES):
		var normalized := clampf(samples[i] / peak, -1.0, 1.0)
		data.encode_s16(i * 2, int(round(normalized * 32767.0)))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = PERIOD_SAMPLES
	return stream


static func _sample(waveform: String, phase: float) -> float:
	match waveform:
		"sine":
			return sin(TAU * phase)
		"square":
			var value := 0.0
			var k := 1
			while k <= MAX_HARMONICS:
				value += sin(TAU * k * phase) / float(k)
				k += 2
			return value * 4.0 / PI
		"triangle":
			var value := 0.0
			var k := 1
			var sign := 1.0
			while k <= MAX_HARMONICS:
				value += sign * sin(TAU * k * phase) / float(k * k)
				sign = -sign
				k += 2
			return value * 8.0 / (PI * PI)
		"sawtooth":
			var value := 0.0
			for k in range(1, MAX_HARMONICS + 1):
				value += sin(TAU * k * phase) / float(k)
			return value * 2.0 / PI
	return sin(TAU * phase)
