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
var _highlights := {}
var _drag_tones := {}


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


func active_highlight_cells() -> Dictionary:
	return _highlights


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


func schedule_note(cell: int, freq: float, start_time: float) -> void:
	_scheduled.append({"start": start_time, "cell": cell, "freq": freq, "wave": config.waveform})
	var stop_time := start_time + GameConfig.NOTE_DURATION + config.release + GameConfig.NOTE_TAIL
	_highlights[cell] = {"start": start_time, "end": stop_time}


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


## Pro Frame aufrufen: faellige Noten starten, Huellkurven fortschreiben.
func process() -> void:
	if _pool == null:
		return
	var t := now()
	if not _scheduled.is_empty():
		var remaining: Array = []
		for entry in _scheduled:
			if t >= float(entry["start"]):
				_pool.start_note(_pool.stream_for(entry["wave"]), float(entry["freq"]), config, t)
			else:
				remaining.append(entry)
		_scheduled = remaining
	_pool.advance(t)
	for cell in _highlights.keys().duplicate():
		if t > float(_highlights[cell]["end"]):
			_highlights.erase(cell)


func _apply_drag_tone(cell: int, volume_factor: float, plain: Voronoi) -> void:
	if cell < 0:
		return
	var freq := cell_frequency(plain, cell)
	var voice := _pool.apply_drag_tone(cell, _pool.stream_for(config.waveform), freq, config.drag_tone_volume * volume_factor, now())
	_drag_tones[cell] = voice
