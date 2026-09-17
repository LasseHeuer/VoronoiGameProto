class_name Synth
extends Node

## Schmale Audio-Schnittstelle: Noten planen/starten, Drag-Toene, Farbwechsel-
## Rampdown und Highlights. Die Implementierung nutzt Sample-Voices
## (WaveformBank + VoicePool); ein spaeteres DSP-Modul kann hinter
## derselben Schnittstelle eingesetzt werden.
##
## Zeitbasis ist eine eigene Uhr (Time.get_ticks_usec), wie im Original die
## audioCtx.currentTime. Noten werden mit (start, freq, wave) eingeplant und
## beim Erreichen gestartet; Highlights laufen auf derselben Uhr.

var config: GameConfig
var board: BoardState

var _pool: VoicePool
var _streams := {}
var _scheduled: Array = []
## Laufende Noten je Zelle: Zeitfenster und Huellkurve.
var _highlights := {}
## Zellen, deren Ton gerade klingt: Zellenindex -> Deckkraft (0..1).
var _active_highlights := {}
var _drag_tones := {}
var _last_hover_at := -INF


func setup(p_config: GameConfig, p_board: BoardState) -> void:
	config = p_config
	board = p_board
	AudioSetup.ensure_layout(config)
	_streams = WaveformBank.build_all()
	_pool = VoicePool.new()
	_pool.name = "VoicePool"
	add_child(_pool)
	_pool.setup(config, _streams)


func now() -> float:
	return float(Time.get_ticks_usec()) / 1000000.0


## Zellen, deren Ton gerade klingt, mit der Deckkraft fuer die gelbe
## Ueberlagerung (folgt der Huellkurve des Tons, siehe _envelope_alpha).
func active_highlight_cells() -> Dictionary:
	return _active_highlights


## Frequenz aus der Zellflaeche (getCellFrequency / scheduleNoteForCell).
## Flaeche kommt aus dem Voronoi OHNE Dummy-Punkte - wie im Original.
func cell_frequency(plain: Voronoi, cell: int) -> float:
	if cell < 0 or cell >= plain.cells.size():
		return GameConfig.FALLBACK_FREQ
	var area := plain.area(cell)
	var ratio := clampf(area / GameConfig.BOARD_AREA, 0.0, 1.0)
	var threshold := config.freq_threshold
	if threshold <= 0.0:
		return GameConfig.FREQ_LOW
	if ratio <= threshold:
		return GameConfig.FREQ_HIGH - (GameConfig.FREQ_HIGH - GameConfig.FREQ_LOW) * (ratio / threshold)
	return GameConfig.FREQ_LOW


## Ausbreitung beim Klick: BFS ueber die Delaunay-Nachbarn des Hauptgraphen,
## Noten nur fuer Zellen mit der Startfarbe, Versatz je Tiefe und Distanz.
func spread_notes(main: Voronoi, plain: Voronoi, start_cell: int, from_pos: Vector2) -> void:
	if start_cell < 0 or start_cell >= board.points.size():
		return
	var starting_color := board.cell_color(start_cell)
	var max_depth := config.spread_depth
	var spread_sec := config.spread_time_sec()
	var network := main.delaunay()

	var queue: Array = [[start_cell, 1]]
	var visited := {start_cell: true}
	var levels := []

	while not queue.is_empty():
		var node: Array = queue.pop_front()
		var index: int = node[0]
		var depth: int = node[1]
		if depth > max_depth:
			continue
		var dist := board.points[index].distance_to(from_pos)
		if depth >= levels.size():
			levels.resize(depth + 1)
		if levels[depth] == null:
			levels[depth] = []
		levels[depth].append({"index": index, "dist": dist})
		if depth < max_depth:
			for nb in network.neighbors(index):
				if nb < main.real_count and not visited.has(nb):
					visited[nb] = true
					queue.append([nb, depth + 1])

	var base_time := now()
	for depth in range(1, max_depth + 1):
		if depth >= levels.size() or levels[depth] == null:
			continue
		var entries: Array = levels[depth]
		entries.sort_custom(func(a, b): return a["dist"] < b["dist"])
		for entry in entries:
			if board.cell_color(entry["index"]) != starting_color:
				continue
			var offset := base_time + float(depth - 1) * spread_sec + float(entry["dist"]) * GameConfig.NOTE_DISTANCE_FACTOR
			schedule_note(entry["index"], cell_frequency(plain, entry["index"]), offset)


func schedule_note(cell: int, freq: float, start_time: float, volume := 1.0, highlight := true) -> void:
	_scheduled.append({
		"start": start_time,
		"cell": cell,
		"freq": freq,
		"wave": config.waveform,
		"volume": volume,
	})
	if not highlight:
		return
	_highlights[cell] = {
		"start": start_time,
		"attack": config.attack,
		"decay": config.decay,
		"sustain": config.sustain,
		"hold_end": start_time + GameConfig.NOTE_DURATION,
		"release": config.release,
		"volume": volume,
		"end": start_time + GameConfig.NOTE_DURATION + config.release + GameConfig.NOTE_TAIL,
	}


## Deckkraft der gelben Ueberlagerung zur Zeit t: dieselbe Huellkurve wie die
## Note (Attack, Decay auf Sustain, danach linear auf 0). Vor dem Start und
## nach dem Ende ist sie 0.
static func _envelope_alpha(entry: Dictionary, t: float) -> float:
	var start := float(entry["start"])
	var attack := float(entry["attack"])
	var decay := float(entry["decay"])
	var sustain := float(entry["sustain"])
	var hold_end := float(entry["hold_end"])
	var release := float(entry["release"])
	var volume := float(entry["volume"])
	var end := hold_end + release
	if t < start or t >= end or volume <= 0.0:
		return 0.0
	if t < start + attack:
		return _ramp(0.0, volume, t - start, attack)
	if t < start + attack + decay:
		return _ramp(volume, sustain * volume, t - start - attack, decay)
	return _ramp(sustain * volume, 0.0, t - (start + attack + decay), end - (start + attack + decay))


static func _ramp(from_value: float, to_value: float, elapsed: float, span: float) -> float:
	if span <= 0.0:
		return to_value
	return lerpf(from_value, to_value, clampf(elapsed / span, 0.0, 1.0))


## Leiser Ton beim Ueberfahren einer Zelle (Windspiel): nur mit
## Mindestabstand und ohne Hervorhebung, damit die Flaeche ruhig bleibt.
func hover_note(cell: int, plain: Voronoi) -> void:
	if cell < 0 or plain == null:
		return
	var t := now()
	if t - _last_hover_at < GameConfig.HOVER_COOLDOWN_SEC:
		return
	_last_hover_at = t
	schedule_note(cell, cell_frequency(plain, cell), t, GameConfig.HOVER_VOLUME, false)


## Drag-Dauertoene: BFS-Tiefe 2, Startzelle mit voller Lautstaerke,
## groesster Nachbar mit halber.
func update_drag_tones(plain: Voronoi, start_cell: int) -> void:
	if start_cell < 0 or start_cell >= board.points.size():
		return
	var visited := {start_cell: true}
	var queue: Array = [[start_cell, 1]]
	var largest_cell := start_cell
	var largest_area := 0.0
	var network := plain.delaunay()

	while not queue.is_empty():
		var node: Array = queue.pop_front()
		var index: int = node[0]
		var depth: int = node[1]
		var area := plain.area(index)
		if area > largest_area:
			largest_area = area
			largest_cell = index
		if depth < GameConfig.DRAG_BFS_DEPTH:
			for nb in network.neighbors(index):
				if not visited.has(nb):
					visited[nb] = true
					queue.append([nb, depth + 1])

	_apply_drag_tone(start_cell, GameConfig.DRAG_START_VOLUME, plain)
	_apply_drag_tone(largest_cell, GameConfig.DRAG_NEIGHBOR_VOLUME, plain)

	for cell in _drag_tones.keys().duplicate():
		if not visited.has(cell):
			stop_drag_tone(cell)


func stop_drag_tones(except_cell: int = -1) -> void:
	for cell in _drag_tones.keys().duplicate():
		if cell == except_cell:
			continue
		stop_drag_tone(cell)


func stop_drag_tone(cell: int) -> void:
	var voice: VoicePool.Voice = _drag_tones.get(cell)
	if voice == null:
		return
	_pool.stop_drag_tone(voice, config.release, now())
	_drag_tones.erase(cell)


func ramp_down_drag_tone(cell: int) -> void:
	var voice: VoicePool.Voice = _drag_tones.get(cell)
	if voice == null:
		return
	_pool.ramp_down_drag_tone(voice, now())
	_drag_tones.erase(cell)


func stop_all() -> void:
	if _pool == null:
		return
	_pool.stop_all()
	_drag_tones.clear()
	_scheduled.clear()
	_highlights.clear()
	_active_highlights.clear()


## Pro Frame aufrufen: faellige Noten starten, Huellkurven fortschreiben.
func process() -> void:
	if _pool == null:
		return
	var t := now()
	if not _scheduled.is_empty():
		var remaining: Array = []
		for entry in _scheduled:
			if t >= float(entry["start"]):
				_pool.start_note(_pool.stream_for(entry["wave"]), float(entry["freq"]), config, t, float(entry["volume"]))
			else:
				remaining.append(entry)
		_scheduled = remaining
	_pool.advance(t)
	_update_highlights(t)


## Zellen, deren Ton gerade klingt, mit der aktuellen Deckkraft. Noch nicht
## gestartete Noten sind nicht dabei: die Zellen werden also nacheinander gelb.
func _update_highlights(t: float) -> void:
	_active_highlights.clear()
	for cell in _highlights.keys().duplicate():
		var entry: Dictionary = _highlights[cell]
		if t > float(entry["end"]):
			_highlights.erase(cell)
			continue
		var alpha := _envelope_alpha(entry, t)
		if alpha > 0.0:
			_active_highlights[cell] = alpha


func _apply_drag_tone(cell: int, volume_factor: float, plain: Voronoi) -> void:
	if cell < 0:
		return
	var freq := cell_frequency(plain, cell)
	var voice := _pool.apply_drag_tone(cell, _pool.stream_for(config.waveform), freq, config.drag_tone_volume * volume_factor, now())
	_drag_tones[cell] = voice
