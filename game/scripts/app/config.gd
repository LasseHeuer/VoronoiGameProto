class_name GameConfig
extends Resource

## Alle Parameter des Spiels an einer Stelle.
##
## Die Defaults entsprechen 1:1 den Werten aus src/index.html und den
## Konstanten aus src/core.js. Einstellbare Werte werden in user://settings.cfg
## gespeichert (siehe settings_store.gd).

# ---------------------------------------------------------------- Brett ----
const BOARD_WIDTH := 900.0
const BOARD_HEIGHT := 600.0
const BOARD_AREA := BOARD_WIDTH * BOARD_HEIGHT

const COLOR_PLAYER1 := "#FF532E"
const COLOR_PLAYER2 := "#37E5FF"

## Farbstufen der Spieler (aus game/assets/spielerfarben.svg). Sie sind die
## drei Landmarken fuer den fliessenden Groessenverlauf jeder Spielerfarbe.
const PLAYER1_STEP_COLORS := [COLOR_PLAYER1, "#FF9945", "#FFCF6A"]
const PLAYER2_STEP_COLORS := [COLOR_PLAYER2, "#37A5FF", "#4354FF"]

## Zelle ohne Spielerfarbe (vor der Farbzuweisung): neutral wie das Brett.
const CELL_EMPTY_COLOR := "#b2b2b2"

# ------------------------------------------------- feste Spielkonstanten ---
const DRAG_RADIUS := 10.0
const REPEL_THRESHOLD := 60.0
const SLOW_FACTOR := 0.2
const MOVE_THRESHOLD := 1.0

const POINT_MARGIN := 30.0
const POINT_SPREAD_FACTOR := 0.2

const DUMMY_SPACING := 50.0
## Der Dummy-Rand liegt mindestens so weit ausserhalb wie der Standard-Rand
## echter Punkte. Andernfalls schneiden Dummy-Halbebenen sichtbar ins Brett.
const DUMMY_MARGIN := 50.0

## Zellen, deren Ton gerade klingt: gelb ueberlegt. Die Deckkraft folgt der
## Lautstaerke des Tons (siehe Synth.active_highlight_cells).
const NOTE_PLAY_COLOR := "#FFE100"
const NOTE_PLAY_ALPHA := 0.45
## Grenze zwischen zwei Zellen derselben Farbe.
const FRAME_COLOR := "#999999"
const SAME_COLOR_FRAME_WIDTH := 1.5
## Grenze zwischen den Territorien: eine dicke Linie in der Teamfarbe, die als
## durchgehende Kontur um das ganze Territorium laeuft und um ihre halbe
## Breite nach innen versetzt ist.
const FRONT_FRAME_WIDTH := 5.0
const POINT_RADIUS := 5.0
## Punkt der Zelle unter dem Mauszeiger. Die Zelle selbst bekommt beim Hover
## eine weisse Umrandung in der Dicke der normalen Zellgrenze.
const POINT_HOVER_COLOR := "#FFFFFF"

## Kurz vor der Uebernahme blinkt die gezogene Zelle. Die Verbindung zur
## groessten gegnerischen Nachbarzelle bleibt als Orientierung sichtbar.
const BLINK_COLOR := "#FFFFFF"
const BLINK_ALPHA := 0.65
## Unter diesem summierten Einflusswert beginnt das Blinken.
const BLINK_WARN_VALUE := 10.0
## Dauer einer Blinkphase (Sekunden) bei kleinster bzw. groesster Chance.
const BLINK_SLOW_SEC := 0.75
const BLINK_FAST_SEC := 0.12

const COLOR_PROPAGATION_ITERATIONS := 12
const BALANCE_TOLERANCE_RATIO := 0.05
const INIT_MAX_ITERATIONS := 100
const NEW_GAME_MAX_ITERATIONS := 50
const RELAX_ITERATIONS_FEW := 10
const RELAX_ITERATIONS_MANY := 30
const RELAX_MANY_THRESHOLD := 50
const RELAX_DAMPING := 0.9
const WEIGHT_INHERITANCE_ITERATIONS := 5

const NOTE_DURATION := 2.0
const NOTE_DISTANCE_FACTOR := 0.003
const NOTE_TAIL := 0.1

const DRAG_BFS_DEPTH := 2
const DRAG_START_VOLUME := 1.0
const DRAG_NEIGHBOR_VOLUME := 0.5
## Hover-Toene: sehr leise und nur mit Mindestabstand (Windspiel).
const HOVER_VOLUME := 0.1
const HOVER_COOLDOWN_SEC := 0.09
const VOICE_ATTACK_MS := 60.0
const VOICE_SMOOTH_SEC := 0.05
const RAMP_DOWN_FREQ_SEC := 0.4
const RAMP_DOWN_FREQ_HZ := 20.0
## Pitch-Shift-Faktor des globalen Audiofilters in der tiefsten Phase.
const PITCH_LOW_SCALE := 0.01
const RAMP_DOWN_GAIN_SEC := 1.0
const PITCH_UP_FREQ_SEC := 0.3

const FREQ_HIGH := 1200.0
const FREQ_LOW := 50.0

const AREA_TEXT_DIVISOR := 10.0
const AREA_TEXT_SIZE := 15

const FALLBACK_FREQ := 220.0

# ------------------------------------------------------- einstellbar -------
@export var waveform: String = "triangle"

@export var attack: float = 0.05
@export var decay: float = 0.2
@export var sustain: float = 0.2
@export var release: float = 0.1
@export var cutoff: float = 500.0

@export var drag_tone_volume: float = 0.2
@export var drag_neighbor_factor: float = 0.25

@export var freq_threshold: float = 0.2
@export var spread_time: float = 0.6
@export var spread_depth: int = 2

@export var cell_count: int = 20

@export var push_factor: float = 0.2
@export var push_radius: float = 40.0
@export var border_margin: float = 50.0
@export var weight_influence: float = 1.0

@export var alternating_moves: bool = true
@export var dummy_points: bool = true
## Flaechenzahlen in den Zellen anzeigen (beim Start aus).
@export var show_cell_numbers: bool = false
## Abstand zwischen zwei Farbwechseln, wenn Zellen verloren gehen (ms).
@export var loss_step_ms: float = 25.0
## Zeit, um eine waehrend des Drags verlorene Zelle zu retten (ms).
@export var loss_rescue_ms: float = 1000.0
## Radius, mit dem die Territoriums-Grenze abgerundet wird (Brettpixel).
@export var corner_radius: float = 8.0
## Gemeinsame Grenzlinien unterhalb dieser Laenge erhalten kein Zahlenlabel.
@export var boundary_label_threshold: float = 10.0

@export var random_seed: int = 0

# ------------------------------------------------------------- Schema ------
## Reihenfolge der Gruppen im Einstellungsmenue.
const SETTING_GROUPS := ["Klang", "Spiel", "Darstellung"]

const SLIDERS := [
	{"key": "attack", "label": "Attack", "min": 0.0, "max": 3.0, "step": 0.01, "group": "Klang"},
	{"key": "decay", "label": "Decay", "min": 0.0, "max": 3.0, "step": 0.01, "group": "Klang"},
	{"key": "sustain", "label": "Sustain", "min": 0.0, "max": 1.0, "step": 0.01, "group": "Klang"},
	{"key": "release", "label": "Release", "min": 0.0, "max": 3.0, "step": 0.01, "group": "Klang"},
	{"key": "cutoff", "label": "Synth Cutoff", "min": 100.0, "max": 1000.0, "step": 1.0, "group": "Klang"},
	{"key": "drag_tone_volume", "label": "Dragtone Volume", "min": 0.0, "max": 1.0, "step": 0.01, "group": "Klang"},
	{"key": "drag_neighbor_factor", "label": "Dragtone Neighbor Factor", "min": 0.0, "max": 1.0, "step": 0.01, "group": "Klang"},
	{"key": "freq_threshold", "label": "Frequenz-Thr", "min": 0.0, "max": 1.0, "step": 0.01, "group": "Klang"},
	{"key": "spread_time", "label": "Neighbor Spread Tone Delay", "min": 0.0, "max": 1.0, "step": 0.001, "group": "Klang"},
	{"key": "spread_depth", "label": "Neighbor Cell Depth", "min": 1, "max": 6, "step": 1, "is_int": true, "group": "Klang"},
	{"key": "cell_count", "label": "Number of Cells", "min": 2, "max": 100, "step": 1, "is_int": true, "group": "Spiel"},
	{"key": "push_factor", "label": "Push Factor", "min": 0.0, "max": 1.0, "step": 0.01, "group": "Spiel"},
	{"key": "push_radius", "label": "Push Radius", "min": 5.0, "max": 150.0, "step": 1.0, "group": "Spiel"},
	{"key": "border_margin", "label": "Border Margin", "min": 5.0, "max": 100.0, "step": 1.0, "group": "Spiel"},
	{"key": "weight_influence", "label": "Weight Influence", "min": 0.0, "max": 1.0, "step": 0.01, "group": "Spiel"},
	{"key": "loss_step_ms", "label": "Verlust-Schritt (ms)", "min": 0.0, "max": 300.0, "step": 5.0, "group": "Spiel"},
	{"key": "loss_rescue_ms", "label": "Rettungszeit (ms)", "min": 0.0, "max": 5000.0, "step": 50.0, "group": "Spiel"},
	{"key": "corner_radius", "label": "Zell-Abrundung", "min": 0.0, "max": 150.0, "step": 0.5, "group": "Darstellung"},
	{"key": "boundary_label_threshold", "label": "Mindest-Grenzlinie", "min": 0.0, "max": 100.0, "step": 1.0, "group": "Darstellung"},
]

const TOGGLES := [
	{"key": "alternating_moves", "label": "Wechselnde Zuege", "group": "Spiel"},
	{"key": "dummy_points", "label": "DummyPoints", "group": "Spiel"},
	{"key": "show_cell_numbers", "label": "Zahlen anzeigen", "group": "Darstellung"},
]

const WAVEFORMS := ["triangle", "sine", "square", "sawtooth"]
## Gruppe der Wellenform-Auswahl im Einstellungsmenue.
const WAVEFORM_GROUP := "Klang"

const DEFAULTS := {
	"waveform": "triangle",
	"attack": 0.05,
	"decay": 0.2,
	"sustain": 0.2,
	"release": 0.1,
	"cutoff": 500.0,
	"drag_tone_volume": 0.2,
	"drag_neighbor_factor": 0.25,
	"freq_threshold": 0.2,
	"spread_time": 0.6,
	"spread_depth": 2,
	"cell_count": 20,
	"push_factor": 0.2,
	"push_radius": 40.0,
	"border_margin": 50.0,
	"weight_influence": 1.0,
	"loss_step_ms": 25.0,
	"loss_rescue_ms": 1000.0,
	"corner_radius": 8.0,
	"alternating_moves": true,
	"dummy_points": true,
	"show_cell_numbers": false,
	"boundary_label_threshold": 10.0,
}

func _init() -> void:
	reset_to_defaults()

func reset_to_defaults() -> void:
	for key in DEFAULTS:
		set(key, DEFAULTS[key])
	random_seed = 0

## Farbstufen der Palette eines Spielers (Stufe 1, 2, 3).
static func step_colors_for(color: String) -> Array:
	if color == COLOR_PLAYER2:
		return PLAYER2_STEP_COLORS
	return PLAYER1_STEP_COLORS

## Spread-Delay in Millisekunden: ms = 50 * 20^t (Paritaet zu getSpreadTimeMs).
func spread_time_ms() -> float:
	return 50.0 * pow(20.0, spread_time)

func spread_time_sec() -> float:
	return spread_time_ms() / 1000.0
