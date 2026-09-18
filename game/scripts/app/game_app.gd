extends Node

## Verdrahtung aller Module und Takt des Spiels.
##
## Simulation laeuft fest mit 60 Hz in _physics_process (bewusste
## Entscheidung gegenueber dem requestAnimationFrame des Originals), die
## Darstellung und das Audio pro Frame in _process.
##
## Reihenfolge pro Tick folgt animate() aus src/core.js:
## Abstandskraefte -> Geschwindigkeiten -> Geometrie -> Clamping ->
## Farbausbreitung. Zusaetzlich: Hover-Toene, die Tonkaskade nach dem
## Loslassen und der Pitch-Down bei einem Zellverlust.

const BOARD_RECT := Rect2(0, 0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)

@onready var board_view: BoardRenderer = $BoardView
@onready var board_input: BoardInput = $BoardInput
@onready var audio: Synth = $Audio
@onready var settings_panel: SettingsPanel = $SettingsPanel
@onready var halftone_overlay: HalftoneOverlay = $HalftoneOverlay
@onready var show_settings_button: Button = $ShowSettingsButton
@onready var restart_button: Button = $RestartButton

var config: GameConfig
var board: BoardState
var rng: DeterministicRng
var voronoi_main: Voronoi
var voronoi_plain: Voronoi
## Offene Farbwechsel, wenn Verluste schrittweise laufen sollen.
var _color_steps := ColorSteps.new()

## Ruhe-Erkennung: haben sich Punkte und Farben im letzten Tick exakt nicht
## geaendert, ist der komplette Rechenweg deterministisch derselbe. Dann
## werden Geometrie, Kraefte und Farbausbreitung uebersprungen; nur die
## Wertung laeuft weiter (wie im Original, das Flaechen pro Frame zaehlt).
var _resting := false
var _last_points := PackedVector2Array()
var _last_colors := PackedStringArray()
## Phase des Blink-Pulses der Uebernahme-Warnung (0..1).
var _blink_phase := 0.0
var _was_dragging := false


func _ready() -> void:
	config = GameConfig.new()
	SettingsStore.load_into(config)
	config.cell_count = clampi(config.cell_count, 2, 16)
	config.cell_gap = clampf(config.cell_gap, 0.0, 4.0)
	board = BoardState.new()
	board.dummy_points = Territories.generate_dummy_points(config.border_margin)
	board.use_dummy_points = config.dummy_points
	rng = DeterministicRng.new(config.random_seed)

	board_view.set_board_state(board, config, null)
	board_input.setup(board, config)
	audio.setup(config, board)
	settings_panel.setup(config)
	halftone_overlay.setup(config)

	settings_panel.value_changed.connect(_on_setting_changed)
	settings_panel.restart_requested.connect(restart)
	settings_panel.hide_requested.connect(_hide_settings)
	show_settings_button.pressed.connect(_show_settings)
	restart_button.pressed.connect(restart)

	board_input.notes_spread_requested.connect(_on_notes_spread_requested)
	board_input.hover_cell_changed.connect(_on_hover_cell_changed)
	board_input.drag_volume_requested.connect(_on_drag_volume_requested)
	board_input.drag_tones_stop_requested.connect(_on_drag_tones_stop_requested)
	board_input.drag_tone_ramp_down_requested.connect(_on_drag_tone_ramp_down_requested)
	board_input.activity.connect(wake)

	restart()


func restart() -> void:
	audio.stop_all()
	_color_steps.clear()
	board.active_color = ""
	board.clear_drag_visuals()
	_was_dragging = false
	board.dummy_points = Territories.generate_dummy_points(config.border_margin)
	board.use_dummy_points = config.dummy_points
	board.reset_stamina(config)
	Territories.init_on_new_game(board, config, rng)
	voronoi_plain = Voronoi.from_points(board.points, BOARD_RECT)
	voronoi_main = Voronoi.from_board(board, BOARD_RECT)
	board_view.voronoi = voronoi_main
	_update_game_result()
	wake()


## Erzwingt im naechsten Tick den vollen Rechenweg.
func wake() -> void:
	_resting = false


func _physics_process(_delta: float) -> void:
	if board.points.size() < 2:
		return
	_apply_view_transform()

	# 1) Drag-Bewegung (mousemove-Aequivalent)
	board_input.apply_drag_motion()
	if _was_dragging and not board_input.is_dragging():
		audio.reset_pitch()
	_was_dragging = board_input.is_dragging()

	# 1b) Hover-Toene. Nutzt die Geometrie des letzten Ticks: im Ruhezustand
	#     ist sie unveraendert, sonst maximal einen Tick alt.
	board_input.update_hover(voronoi_plain)

	if _resting and not board_input.is_dragging() and not board_input.has_pending_click():
		# Nichts hat sich geaendert: die komplette Neuberechnung entfaellt.
		board_view.voronoi = voronoi_main
		return

	# 2) Geometrie ohne Dummy-Punkte. Nur bewegte Zellen und ihre lokale
	# Umgebung werden aus dem vorherigen Aufbau neu berechnet.
	var plain_changed := _changed_indices(voronoi_plain.points, board.points)
	voronoi_plain = Voronoi.from_points(board.points, BOARD_RECT, voronoi_plain, plain_changed)

	# 3) Klick in Zelle -> Noten; laufender Drag -> Dauertoene
	board_input.consume_click(voronoi_plain)
	if board_input.is_dragging():
		audio.update_drag_tones(voronoi_plain, board_input.dragged_index())

	# 4) Abstandskraefte (pushPoints + updatePointPositions)
	var points_before_relaxation := board.points.duplicate()
	var weights := Relaxation.compute_cell_weights(board, voronoi_plain)
	if board_input.dragged_index() >= 0:
		weights[board_input.dragged_index()] = voronoi_plain.area(board_input.dragged_index())
	Relaxation.push_points(board, config, weights)
	Relaxation.update_point_positions(board)

	# 5) Hauptgeometrie (mit Dummy-Punkten), ebenfalls inkrementell.
	var main_changed := _changed_indices(voronoi_main.points, board.points)
	voronoi_main = Voronoi.from_board(board, BOARD_RECT, 5.0, true,
		voronoi_main, main_changed)

	# 6) Rand-Clamping
	Relaxation.clamp_to_canvas(board, config)
	if board_input.is_dragging():
		var movement_cost := 0.0
		var dragged := board_input.dragged_index()
		for i in range(board.points.size()):
			if i == dragged or i >= points_before_relaxation.size():
				continue
			movement_cost += points_before_relaxation[i].distance_to(board.points[i])
		board.spend_stamina(board_input.dragged_player_color(), movement_cost, config)

	# 7) Farbausbreitung. Waehrend eines Drags laeuft sie im Original
	#    zweimal pro Frame (mousemove und animate). Die Wechsel werden
	#    nacheinander angewendet, damit ein Gebietsverlust nicht in einem
	#    einzigen Tick passiert. Jeder eigene Verlust loest einen Pitch-Down
	#    aus.
	var passes := 2 if board_input.is_dragging() else 1
	for i in range(passes):
		var lost := _color_steps.advance(float(Time.get_ticks_msec()), config.loss_step_ms,
			board, voronoi_main, GameConfig.COLOR_PROPAGATION_ITERATIONS)
		if lost >= 0 and board_input.is_dragging() \
			and lost == board_input.dragged_index():
			audio.pitch_down(lost, voronoi_plain)
			board_input.notify_drag_cell_lost(lost)
	var rescue_state := board_input.update_drag_rescue(float(Time.get_ticks_msec()))
	if rescue_state == 1:
		audio.pitch_up(board_input.dragged_index(), voronoi_plain)
	elif rescue_state == -1:
		audio.reset_pitch()
	_update_game_result()

	# 7b) Nach dem Loslassen breitet sich der Ton als Kaskade aus
	#    (spreadNotes im mouseup des Originals).
	board_input.consume_pending_spread()

	# 8) Drag-Uebernahme-Warnung
	board_input.update_drag_visuals(voronoi_main)

	board_view.voronoi = voronoi_main
	_resting = board.points == _last_points and board.cell_colors == _last_colors and _color_steps.is_idle()
	_last_points = board.points
	_last_colors = board.cell_colors


func _process(delta: float) -> void:
	audio.process()
	_update_blink(delta)
	board_view.highlight_cells = audio.active_highlight_cells()
	board_view.queue_redraw()


## Blink-Puls fuer die Uebernahme-Warnung: je groesser die Gefahr, desto
## kuerzer die Phase. Ohne Warnung ist der Puls aus.
func _update_blink(delta: float) -> void:
	var warn: float = board.drag_warn if board_input.is_dragging() else 0.0
	if warn <= 0.0:
		_blink_phase = 0.0
		board.drag_blink = 0.0
		return
	var period: float = lerpf(GameConfig.BLINK_SLOW_SEC, GameConfig.BLINK_FAST_SEC, warn)
	_blink_phase = fmod(_blink_phase + delta / maxf(period, 0.01), 1.0)
	board.drag_blink = 1.0 - absf(_blink_phase * 2.0 - 1.0)


func _apply_view_transform() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var transform := BoardTransform.for_viewport(viewport_size)
	board_input.update_transform(viewport_size)
	board_view.view_transform = transform


static func _changed_indices(previous: PackedVector2Array, current: PackedVector2Array) -> PackedInt32Array:
	var changed := PackedInt32Array()
	if previous.size() < current.size():
		for i in range(current.size()):
			changed.append(i)
		return changed
	for i in range(current.size()):
		if previous[i].distance_squared_to(current[i]) > 0.0001:
			changed.append(i)
	return changed


func _on_setting_changed(key: String, value: Variant) -> void:

	SettingsStore.save(config)
	wake()
	match key:
		"cutoff":
			AudioSetup.apply_cutoff(config)
		"dummy_points":
			board.use_dummy_points = bool(value)
		"stamina":
			board.stamina_player1 = minf(board.stamina_player1, config.stamina)
			board.stamina_player2 = minf(board.stamina_player2, config.stamina)
	if key.begins_with("halftone_"):
		halftone_overlay.apply()


func _on_notes_spread_requested(cell_index: int, from_pos: Vector2) -> void:
	# Wie im Original wird dafuer der Hauptgraph frisch aufgebaut.
	audio.spread_notes(Voronoi.from_board(board, BOARD_RECT), voronoi_plain, cell_index, from_pos)


func _on_hover_cell_changed(cell_index: int) -> void:
	audio.hover_note(cell_index, voronoi_plain)


func _on_drag_volume_requested(cell_index: int) -> void:
	if voronoi_plain != null:
		audio.update_drag_tones(voronoi_plain, cell_index)


func _on_drag_tones_stop_requested(except_index: int) -> void:
	audio.stop_drag_tones(except_index)


func _on_drag_tone_ramp_down_requested(cell_index: int) -> void:
	audio.ramp_down_drag_tone(cell_index)


func _update_game_result() -> void:
	if not board.game_over or board.winner_color != "" or voronoi_main == null:
		return
	var area1 := Territories.total_area_for_color(board, voronoi_main, GameConfig.COLOR_PLAYER1)
	var area2 := Territories.total_area_for_color(board, voronoi_main, GameConfig.COLOR_PLAYER2)
	if is_equal_approx(area1, area2):
		board.winner_color = ""
	else:
		board.winner_color = GameConfig.COLOR_PLAYER1 if area1 > area2 else GameConfig.COLOR_PLAYER2


func _show_settings() -> void:
	settings_panel.visible = true
	show_settings_button.visible = false


func _hide_settings() -> void:
	settings_panel.visible = false
	show_settings_button.visible = true
