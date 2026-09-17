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
		_pending_spread = true
		_pending_spread_index = released_index
		_pending_spread_pos = released_pos


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
## Der Punkt folgt dem Zeiger auf dem Strahl vom Startpunkt aus. Wechselt die
## Zelle dabei die Farbe, endet der Zug mit automatischem Farbwechsel
## (should_switch_automatically).
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

	var moved_distance := board.points[_dragged_index].distance_to(_drag_start)
	if Turns.should_switch_automatically(board, _dragged_index, config, moved_distance):
		var new_color := board.cell_color(_dragged_index)
		drag_tone_ramp_down_requested.emit(_dragged_index)
		drag_tones_stop_requested.emit(_dragged_index)
		_dragging = false
		_dragged_index = -1
		board.active_color = new_color
		_color_switched_automatically = true
		board.clear_drag_visuals()
		return

	drag_volume_requested.emit(_dragged_index)


## Liegt der Zeiger zu nah an einem anderen Punkt?
func _is_too_close() -> bool:
	for i in range(board.points.size()):
		if i == _dragged_index:
			continue
		if board.points[i].distance_to(_cursor) < GameConfig.REPEL_THRESHOLD:
			return true
	return false


## Wie nahe ist die gezogene Zelle an der Uebernahme? Die Ausbreitung kippt
## sie, sobald ihr groesster sichtbarer Nachbar die Gegnerfarbe traegt. Mass
## ist der Flaechen-Vorsprung des groessten Gegners gegenueber dem groessten
## gleichfarbigen Nachbarn: 0 = keine Gefahr, 1 = unmittelbar am Kipp-Punkt.
func _takeover_warning() -> float:
	var opponent := board.drag_opponent_neighbor_area
	var same := board.drag_same_neighbor_area
	var total := opponent + same
	if total <= 0.0:
		return 0.0
	var ratio := opponent / total
	return clampf((ratio - GameConfig.BLINK_WARN_RATIO) / (0.5 - GameConfig.BLINK_WARN_RATIO), 0.0, 1.0)


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
	board.drag_warn = _takeover_warning()


func _hit_point(pos: Vector2) -> int:
	var best := INF
	var hit := -1
	for i in range(board.points.size()):
		var d := board.points[i].distance_to(pos)
		if d < GameConfig.DRAG_RADIUS and d < best:
			best = d
			hit = i
	return hit
