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
## Loslassen und der Verlust-Schutz beim Drag.

const BOARD_RECT := Rect2(0, 0, GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)

@onready var board_view: BoardRenderer = $BoardView
@onready var board_input: BoardInput = $BoardInput
@onready var audio: Synth = $Audio
@onready var settings_panel: SettingsPanel = $SettingsPanel
@onready var show_settings_button: Button = $ShowSettingsButton

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


func _ready() -> void:
	config = GameConfig.new()
	SettingsStore.load_into(config)
	board = BoardState.new()
	board.dummy_points = Territories.generate_dummy_points()
	board.use_dummy_points = config.dummy_points
	rng = DeterministicRng.new(config.random_seed)

	board_view.set_board_state(board, config, null)
	board_input.setup(board, config)
	audio.setup(config, board)
	settings_panel.setup(config)

	settings_panel.value_changed.connect(_on_setting_changed)
	settings_panel.restart_requested.connect(restart)
	settings_panel.hide_requested.connect(_hide_settings)
	show_settings_button.pressed.connect(_show_settings)

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
	board.use_dummy_points = config.dummy_points
	Territories.init_on_new_game(board, config, rng)
	voronoi_plain = Voronoi.from_points(board.points, BOARD_RECT)
	voronoi_main = Voronoi.from_board(board, BOARD_RECT)
	board_view.voronoi = voronoi_main
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

	# 1b) Hover-Toene. Nutzt die Geometrie des letzten Ticks: im Ruhezustand
	#     ist sie unveraendert, sonst maximal einen Tick alt.
	board_input.update_hover(voronoi_plain)

	if _resting and not board_input.is_dragging() and not board_input.has_pending_click():
		# Nichts hat sich geaendert: die komplette Neuberechnung entfaellt.
		board_view.voronoi = voronoi_main
		return

	# 2) Geometrie ohne Dummy-Punkte (frisch, fuer Gewichte und Frequenzen)
	voronoi_plain = Voronoi.from_points(board.points, BOARD_RECT)

	# 3) Klick in Zelle -> Noten; laufender Drag -> Dauertoene
	board_input.consume_click(voronoi_plain)
	if board_input.is_dragging():
		audio.update_drag_tones(voronoi_plain, board_input.dragged_index())

	# 4) Abstandskraefte (pushPoints + updatePointPositions)
	var weights := Relaxation.compute_cell_weights(board, voronoi_plain)
	if board_input.dragged_index() >= 0:
		weights[board_input.dragged_index()] = voronoi_plain.area(board_input.dragged_index())
	Relaxation.push_points(board, config, weights)
	Relaxation.update_point_positions(board)

	# 5) Hauptgeometrie (mit Dummy-Punkten)
	voronoi_main = Voronoi.from_board(board, BOARD_RECT)

	# 6) Rand-Clamping
	Relaxation.clamp_to_canvas(board, config)

	# 6b) Verlust-Schutz: kostet die Position Zellen, geht sie zurueck.
	if board_input.apply_loss_limit(voronoi_main):
		voronoi_main = Voronoi.from_board(board, BOARD_RECT)

	# 7) Farbausbreitung. Waehrend eines Drags laeuft sie im Original
	#    zweimal pro Frame (mousemove und animate). Ohne Verlust-Schutz
	#    werden die Wechsel nur nacheinander angewendet, damit ein
	#    Gebietsverlust nicht in einem einzigen Tick passiert.
	var passes := 2 if board_input.is_dragging() else 1
	for i in range(passes):
		if config.prevent_loss:
			_color_steps.clear()
			Territories.update_colors_by_largest_neighbor(board, voronoi_main, GameConfig.COLOR_PROPAGATION_ITERATIONS)
		else:
			_color_steps.advance(float(Time.get_ticks_msec()), config.loss_step_ms, board, voronoi_main, GameConfig.COLOR_PROPAGATION_ITERATIONS)

	# 7b) Nach dem Loslassen breitet sich der Ton als Kaskade aus
	#    (spreadNotes im mouseup des Originals).
	board_input.consume_pending_spread()

	# 8) Drag-Linien-Daten
	board_input.update_drag_visuals(voronoi_main)

	board_view.voronoi = voronoi_main
	_resting = board.points == _last_points and board.cell_colors == _last_colors and _color_steps.is_idle()
	_last_points = board.points
	_last_colors = board.cell_colors


func _process(_delta: float) -> void:
	audio.process()
	board_view.highlight_cells = audio.active_highlight_cells()
	board_view.queue_redraw()


func _apply_view_transform() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var transform := BoardTransform.for_viewport(viewport_size)
	board_input.update_transform(viewport_size)
	board_view.view_transform = transform


func _on_setting_changed(key: String, value: Variant) -> void:
	SettingsStore.save(config)
	wake()
	match key:
		"cutoff":
			AudioSetup.apply_cutoff(config)
		"dummy_points":
			board.use_dummy_points = bool(value)


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


func _show_settings() -> void:
	settings_panel.visible = true
	show_settings_button.visible = false


func _hide_settings() -> void:
	settings_panel.visible = false
	show_settings_button.visible = true
