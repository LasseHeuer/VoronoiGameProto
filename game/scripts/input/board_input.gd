class_name BoardInput
extends Node

## Maus -> Drag/Klick-Intents. Uebersetzt Fensterkoordinaten in
## Brettkoordinaten und fuehrt die Drag-Zustandsmaschine
## (Hit-Test, Zug-Erlaubnis, Slow-Faktor, automatischer Farbwechsel,
## Drag-Linien-Daten und Uebernahme-Warnung).
##
## Klang und Geometrie werden nicht selbst berechnet: das Modul meldet
## Intents per Signal und bekommt die Geometrie einmal pro Tick hereingegeben.

signal notes_spread_requested(cell_index: int, from_pos: Vector2)
signal drag_volume_requested(cell_index: int)
signal drag_tones_stop_requested(except_index: int)
signal drag_tone_ramp_down_requested(cell_index: int)
## Meldet jede Mausaktivitaet, damit die Ruhe-Erkennung aufgeweckt wird.
signal activity
## Zeigt auf eine andere Zelle als zuletzt (fuer die leisen Hover-Toene).
signal hover_cell_changed(cell_index: int)

var board: BoardState
var config: GameConfig

var transform := BoardTransform.new()

var _dragging := false
var _dragged_index := -1
var _drag_start := Vector2.ZERO
var _successful_drag := false
var _color_switched_automatically := false
var _cursor := Vector2.ZERO
var _pending_click := false
var _pending_click_pos := Vector2.ZERO
var _pending_spread := false
var _pending_spread_index := -1
var _pending_spread_pos := Vector2.ZERO
var _hover_dirty := false
var _hover_cell := -1
var _loss_deadline_ms := -1.0
var _loss_active := false


func setup(p_board: BoardState, p_config: GameConfig) -> void:
	board = p_board
	config = p_config


func is_dragging() -> bool:
	return _dragging


func dragged_index() -> int:
	return _dragged_index


func update_transform(viewport_size: Vector2) -> void:
	transform = BoardTransform.for_viewport(viewport_size)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		activity.emit()
		if event.pressed:
			_on_press(event.position)
		else:
			_on_release()
	elif event is InputEventMouseMotion:
		_cursor = transform.to_board(event.position)
		_hover_dirty = true
		if _dragging:
			activity.emit()


func _on_press(screen_pos: Vector2) -> void:
	if board == null or config == null:
		return
	_cursor = transform.to_board(screen_pos)
	var hit := _hit_point(_cursor)
	if hit >= 0:
		if not Turns.can_start_drag(board, hit, config):
			return
		_dragging = true
		_dragged_index = hit
		_successful_drag = false
		_color_switched_automatically = false
		_drag_start = board.points[hit]
		# Der bewegte Punkt bleibt waehrend des Drags als aktive Hover-Zelle
		# sichtbar, auch wenn seit dem Druecken kein neues Mausereignis kommt.
		board.hovered_index = hit
		board.clear_drag_visuals()
		drag_volume_requested.emit(hit)
		return
	_pending_click = true
	_pending_click_pos = _cursor


func _on_release() -> void:
	if _dragging:
		# Letzte Bewegung vor dem Loslassen uebernehmen (im Original passiert
		# das im mousemove). Das kann den automatischen Farbwechsel ausloesen;
		# danach ist kein Drag mehr aktiv und es folgt keine Ausbreitung.
		apply_drag_motion()
	var released_index := _dragged_index
	var released_pos := _cursor
	var lost_without_rescue := _loss_active \
		and board.cell_color(_dragged_index) != board.active_color
	if lost_without_rescue:
		_finish_automatic_switch()
		released_index = -1
	_loss_active = false
	_loss_deadline_ms = -1.0
	_dragging = false
	_dragged_index = -1
	if config != null and config.alternating_moves:
		if _successful_drag and not _color_switched_automatically:
			board.active_color = Turns.toggled_color(board.active_color)
		_color_switched_automatically = false
	drag_tones_stop_requested.emit(-1)
	_successful_drag = false
	if board != null:
		board.clear_drag_visuals()
	if released_index >= 0:
		# Der zuletzt bewegte Punkt bleibt direkt nach dem Loslassen aktiv. So
		# gehen Umrandung und Hover-Ton auch ohne weiteres Mausereignis nicht
		# verloren.
		_hover_cell = released_index
		_hover_dirty = false
		board.hovered_index = released_index
		hover_cell_changed.emit(released_index)
		_pending_spread = true
		_pending_spread_index = released_index
		_pending_spread_pos = released_pos
	else:
		# Bei einem automatischen Farbwechsel kann keine Drag-Zelle uebernommen
		# werden; die Mausposition wird beim naechsten Ereignis neu bestimmt.
		_hover_cell = -1
		_hover_dirty = true


## Zug-Erlaubnis und Klick-Hit-Test brauchen die Geometrie des Ticks.
func has_pending_click() -> bool:
	return _pending_click


func consume_click(click_plain: Voronoi) -> void:
	if not _pending_click:
		return
	_pending_click = false
	if click_plain == null:
		return
	var pos := _pending_click_pos
	var index := click_plain.delaunay().find(pos.x, pos.y)
	if index < 0:
		return
	var poly := click_plain.cell_polygon(index)
	if poly.size() < 3:
		return
	if BoardGeometry.point_in_polygon(pos, poly):
		notes_spread_requested.emit(index, pos)


## Ausbreitung nach dem Loslassen einer gezogenen Zelle (spreadNotes im
## mouseup des Originals). Laeuft bewusst erst im Tick nach der
## Farbausbreitung, damit die Farben zur Endposition der Zelle passen.
func consume_pending_spread() -> void:
	if not _pending_spread:
		return
	_pending_spread = false
	var index := _pending_spread_index
	var pos := _pending_spread_pos
	_pending_spread_index = -1
	if index >= 0:
		notes_spread_requested.emit(index, pos)


## Zelle unter dem Mauszeiger, aber nur wenn sie gewechselt hat (fuer die
## leisen Hover-Toene). Die uebergebene Geometrie stammt aus dem letzten
## Tick: im Ruhezustand aendert sie sich nicht, sonst ist sie maximal einen
## Tick alt. Ein laufender Drag erzeugt keine Hover-Toene.
func update_hover(plain: Voronoi) -> void:
	if not _hover_dirty:
		return
	_hover_dirty = false
	if plain == null or _dragging or _pending_click:
		return
	var index := -1
	var candidate := plain.delaunay().find(_cursor.x, _cursor.y)
	if candidate >= 0:
		var poly := plain.cell_polygon(candidate)
		if poly.size() >= 3 and BoardGeometry.point_in_polygon(_cursor, poly):
			index = candidate
	if index == _hover_cell:
		return
	_hover_cell = index
	board.hovered_index = index
	if index >= 0:
		hover_cell_changed.emit(index)


## Bewegung des gezogenen Punktes (mousemove-Aequivalent), einmal pro Tick.
##
## Der Punkt folgt dem Zeiger auf dem Strahl vom Startpunkt aus. Ein Farbverlust
## wird nach der Farbausbreitung separat ueber die Rettungszeit behandelt.
func apply_drag_motion() -> void:
	if not _dragging or _dragged_index < 0:
		return
	var from := board.points[_dragged_index]
	var offset := _cursor - _drag_start
	var distance := offset.length()
	if distance <= 0.001:
		# Zeiger steht auf dem Startpunkt: Punkt dorthin zuruecknehmen.
		if from != _drag_start:
			var points_home := board.points
			points_home[_dragged_index] = _drag_start
			board.points = points_home
		return
	var direction := offset / distance
	var target := distance
	if _is_too_close():
		# Langsam an das Ziel herantasten statt springen.
		var current := from.distance_to(_drag_start)
		target = current + (target - current) * GameConfig.SLOW_FACTOR
	var points := board.points
	points[_dragged_index] = _drag_start + direction * target
	board.points = points

	if not _successful_drag:
		if board.points[_dragged_index].distance_to(_drag_start) > GameConfig.MOVE_THRESHOLD:
			_successful_drag = true

	Relaxation.clamp_to_canvas(board, config)

	if board.points[_dragged_index].distance_to(from) < 0.001:
		var revert := board.points
		revert[_dragged_index] = from
		board.points = revert

	drag_volume_requested.emit(_dragged_index)


## Meldet den Verlust der gezogenen Zelle und startet deren Rettungszeit.
func notify_drag_cell_lost(cell_index: int) -> void:
	if not config.alternating_moves or not _dragging or cell_index != _dragged_index:
		return
	_loss_active = true
	_loss_deadline_ms = float(Time.get_ticks_msec()) + config.loss_rescue_ms


## Gibt 1 bei Rettung, -1 bei abgelaufener Rettungszeit und 0 sonst zurueck.
func update_drag_rescue(now_ms: float) -> int:
	if not _loss_active or not _dragging or _dragged_index < 0:
		return 0
	if board.cell_color(_dragged_index) == board.active_color:
		_loss_active = false
		_loss_deadline_ms = -1.0
		return 1
	if now_ms < _loss_deadline_ms:
		return 0
	_finish_automatic_switch()
	return -1


func _finish_automatic_switch() -> void:
	if _dragged_index < 0:
		return
	var new_color := board.cell_color(_dragged_index)
	drag_tone_ramp_down_requested.emit(_dragged_index)
	drag_tones_stop_requested.emit(_dragged_index)
	_dragging = false
	_dragged_index = -1
	_loss_active = false
	_loss_deadline_ms = -1.0
	board.active_color = new_color
	_color_switched_automatically = true
	board.clear_drag_visuals()


## Liegt der Zeiger zu nah an einem anderen Punkt?
func _is_too_close() -> bool:
	for i in range(board.points.size()):
		if i == _dragged_index:
			continue
		if board.points[i].distance_to(_cursor) < GameConfig.REPEL_THRESHOLD:
			return true
	return false


## Blinkintensitaet aus dem summierten relativen Einfluss der Drag-Zelle.
func _takeover_warning(main: Voronoi) -> float:
	if main == null:
		return 0.0
	var geometry := CellGeometry.from_voronoi(main, true)
	var ids := board.color_ids()
	var total := 0.0
	var has_opponent_pressure := board.drag_opponent_neighbor >= 0 \
		and board.drag_opponent_neighbor_area > main.area(_dragged_index)
	if _dragged_index >= 0 and _dragged_index < geometry.neighbors.size():
		for neighbor in geometry.neighbors[_dragged_index]:
			var value := Territories.relative_neighbor_value(
				geometry, ids, _dragged_index, neighbor)
			total += value
			if value < 0.0:
				has_opponent_pressure = true
	if not has_opponent_pressure:
		return 0.0
	return clampf((GameConfig.BLINK_WARN_VALUE - total) / GameConfig.BLINK_WARN_VALUE, 0.0, 1.0)


## Linien zum groessten gleichen bzw. gegnerischen Nachbarn und die Warnung
## vor der Uebernahme.
func update_drag_visuals(main: Voronoi) -> void:
	if not _dragging or _dragged_index < 0 or main == null:
		return
	var my_color := board.cell_color(_dragged_index)
	var same := Territories.largest_neighbor_by_color(board, main, _dragged_index, my_color)
	var other := Territories.largest_neighbor_by_color(board, main, _dragged_index, BoardState.opponent_color(my_color))
	board.dragged_index = _dragged_index
	board.drag_same_neighbor = same["cell_id"]
	board.drag_same_neighbor_area = same["max_area"]
	board.drag_opponent_neighbor = other["cell_id"]
	board.drag_opponent_neighbor_area = other["max_area"]
	board.drag_warn = _takeover_warning(main)


func _hit_point(pos: Vector2) -> int:
	var best := INF
	var hit := -1
	for i in range(board.points.size()):
		var d := board.points[i].distance_to(pos)
		if d < GameConfig.DRAG_RADIUS and d < best:
			best = d
			hit = i
	return hit
