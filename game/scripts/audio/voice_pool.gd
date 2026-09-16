class_name VoicePool
extends Node

## Pool von AudioStreamPlayern mit linearer Huellkurven-State-Machine.
##
## Die Huellkurve wird als Folge linearer Segmente (start, end, von, nach)
## beschrieben - genau das, was die Web-Audio-Aufrufe
## setValueAtTime/linearRampToValueAtTime im Original bewirken. Wichtig:
## ein linearRampToValueAtTime startet am Ende des vorherigen Ereignisses,
## deshalb laeuft die Note schon waehrend der Haltephase Richtung 0.
##
## Der Lautstaerkewert bleibt linear und wird erst beim Setzen in dB
## umgerechnet (AudioStreamPlayer.volume_db).

const MAX_VOICES := 64
const SILENT_DB := -80.0


class Voice extends RefCounted:
	var player: AudioStreamPlayer
	var cell := -1
	var is_drag_tone := false
	var gain := 0.0
	var freq := 0.0
	var finish_at := INF
	var _gain_segments: Array = []
	var _freq_segments: Array = []

	func clear_segments() -> void:
		_gain_segments.clear()
		_freq_segments.clear()
		finish_at = INF

	func add_gain_segment(start: float, end: float, from_value: float, to_value: float) -> void:
		_gain_segments.append({"start": start, "end": end, "from": from_value, "to": to_value})

	func add_freq_segment(start: float, end: float, from_value: float, to_value: float) -> void:
		_freq_segments.append({"start": start, "end": end, "from": from_value, "to": to_value})

	func advance(now: float) -> void:
		gain = _evaluate(_gain_segments, now, gain)
		freq = _evaluate(_freq_segments, now, freq)

	static func _evaluate(segments: Array, now: float, current: float) -> float:
		while not segments.is_empty():
			var segment: Dictionary = segments[0]
			if now >= segment["end"]:
				current = segment["to"]
				segments.remove_at(0)
				continue
			var span: float = segment["end"] - segment["start"]
			if span <= 0.0:
				return segment["to"]
			var t := clampf((now - segment["start"]) / span, 0.0, 1.0)
			return lerpf(segment["from"], segment["to"], t)
		return current


var _streams := {}
var _bus := ""
var _free: Array = []
var _used: Array = []


func setup(config: GameConfig, streams: Dictionary) -> void:
	_bus = AudioSetup.BUS_SYNTH
	_streams = streams
	AudioSetup.apply_cutoff(config)


func stream_for(waveform: String) -> AudioStreamWAV:
	if _streams.has(waveform):
		return _streams[waveform]
	if _streams.is_empty():
		return null
	return _streams.values()[0]


## Geplanter Ton mit ADSR-Huellkurve (scheduleNoteForCell).
func start_note(stream: AudioStreamWAV, freq: float, config: GameConfig, now: float) -> Voice:
	var voice := _acquire()
	voice.cell = -1
	voice.is_drag_tone = false
	voice.gain = 0.0
	voice.freq = freq
	var attack := config.attack
	var decay := config.decay
	var sustain := config.sustain
	var hold_end := now + GameConfig.NOTE_DURATION
	voice.add_gain_segment(now, now + attack, 0.0, 1.0)
	voice.add_gain_segment(now + attack, now + attack + decay, 1.0, sustain)
	voice.add_gain_segment(now + attack + decay, hold_end + config.release, sustain, 0.0)
	voice.finish_at = hold_end + config.release + GameConfig.NOTE_TAIL
	_play(voice, stream, freq)
	return voice


## Dauerton erzeugen oder aktualisieren (startOrUpdateDragTone).
func apply_drag_tone(cell: int, stream: AudioStreamWAV, freq: float, target: float, now: float) -> Voice:
	var voice := find_drag_tone(cell)
	if voice == null:
		voice = _acquire()
		voice.cell = cell
		voice.is_drag_tone = true
		voice.gain = 0.0
		voice.add_gain_segment(now, now + GameConfig.VOICE_ATTACK_MS / 1000.0, 0.0, target)
		_play(voice, stream, freq)
		return voice

	voice.clear_segments()
	voice.add_gain_segment(now, now + GameConfig.VOICE_SMOOTH_SEC, voice.gain, target)
	_set_frequency(voice, freq)
	return voice


func find_drag_tone(cell: int) -> Voice:
	if cell < 0:
		return null
	for voice in _used:
		if voice.is_drag_tone and voice.cell == cell:
			return voice
	return null


## Sofortiges Beenden eines Dauertons (stopDragTone).
func stop_drag_tone(voice: Voice, release: float, now: float) -> void:
	voice.clear_segments()
	voice.add_gain_segment(now, now + release, voice.gain, 0.0)
	voice.finish_at = now + release + GameConfig.NOTE_TAIL


## Frequenz-Rampdown plus Ausblenden (rampDownAndStopDragTone).
## Der Oszillator stoppt im Original bereits nach 0.4 s.
func ramp_down_drag_tone(voice: Voice, now: float) -> void:
	voice.clear_segments()
	voice.is_drag_tone = false
	voice.add_freq_segment(now, now + GameConfig.RAMP_DOWN_FREQ_SEC, voice.freq, GameConfig.RAMP_DOWN_FREQ_HZ)
	voice.add_gain_segment(now, now + GameConfig.RAMP_DOWN_GAIN_SEC, voice.gain, 0.0)
	voice.finish_at = now + GameConfig.RAMP_DOWN_FREQ_SEC


func stop_all() -> void:
	for voice in _used.duplicate():
		_finish(voice)


## Pro Frame aufrufen: Huellkurven fortschreiben, fertige Stimmen freigeben.
func advance(now: float) -> void:
	for voice in _used.duplicate():
		voice.advance(now)
		_update_volume(voice)
		if now >= voice.finish_at:
			_finish(voice)


func _play(voice: Voice, stream: AudioStreamWAV, freq: float) -> void:
	if stream == null:
		return
	voice.player.stream = stream
	voice.player.pitch_scale = _pitch_for(freq)
	_update_volume(voice)
	voice.player.play()


func _set_frequency(voice: Voice, freq: float) -> void:
	voice.freq = freq
	voice.player.pitch_scale = _pitch_for(freq)


func _update_volume(voice: Voice) -> void:
	voice.player.volume_db = linear_to_db(clampf(voice.gain, 0.0, 1.0)) if voice.gain > 0.0 else SILENT_DB


func _pitch_for(freq: float) -> float:
	return clampf(freq / WaveformBank.BASE_FREQ, 0.01, 4.0)


func _acquire() -> Voice:
	if _used.size() >= MAX_VOICES and not _used.is_empty():
		var stolen: Voice = _used.pop_front()
		_reset(stolen)
		_used.append(stolen)
		return stolen
	if _free.is_empty():
		_create_voice()
	var voice: Voice = _free.pop_back()
	_reset(voice)
	_used.append(voice)
	return voice


func _create_voice() -> void:
	var player := AudioStreamPlayer.new()
	player.bus = _bus
	add_child(player)
	var voice := Voice.new()
	voice.player = player
	_free.append(voice)


func _reset(voice: Voice) -> void:
	voice.player.stop()
	voice.clear_segments()
	voice.gain = 0.0
	voice.player.volume_db = SILENT_DB
	voice.cell = -1
	voice.is_drag_tone = false


func _finish(voice: Voice) -> void:
	_reset(voice)
	_used.erase(voice)
	_free.append(voice)
