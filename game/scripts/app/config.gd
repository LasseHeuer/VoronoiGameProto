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

const COLOR_PLAYER1 := "#FF8BA7"
const COLOR_PLAYER2 := "#76FFE8"

# ------------------------------------------------- feste Spielkonstanten ---
const DRAG_RADIUS := 10.0
const REPEL_THRESHOLD := 60.0
const SLOW_FACTOR := 0.2
const MOVE_THRESHOLD := 1.0

const POINT_MARGIN := 30.0
const POINT_SPREAD_FACTOR := 0.2

const DUMMY_SPACING := 50.0
const DUMMY_MARGIN := 30.0

const LUM_MIN := 20.0
const LUM_MAX := 80.0
const ENEMY_MIX_BASE := 0.5

const HIGHLIGHT_FRAME_COLOR := "#FFFFFF"
const HIGHLIGHT_FRAME_WIDTH := 6.0
const FRAME_COLOR := "#999999"
const FRAME_WIDTH := 3.0
const POINT_RADIUS := 5.0

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
const VOICE_ATTACK_MS := 60.0
const VOICE_SMOOTH_SEC := 0.05
const RAMP_DOWN_FREQ_SEC := 0.4
const RAMP_DOWN_FREQ_HZ := 20.0
const RAMP_DOWN_GAIN_SEC := 1.0

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
@export var border_margin: float = 25.0
@export var weight_influence: float = 0.95

@export var alternating_moves: bool = true
@export var dummy_points: bool = true

@export var random_seed: int = 0

# ------------------------------------------------------------- Schema ------
const SLIDERS := [
	{"key": "attack", "label": "Attack", "min": 0.0, "max": 3.0, "step": 0.01},
	{"key": "decay", "label": "Decay", "min": 0.0, "max": 3.0, "step": 0.01},
	{"key": "sustain", "label": "Sustain", "min": 0.0, "max": 1.0, "step": 0.01},
	{"key": "release", "label": "Release", "min": 0.0, "max": 3.0, "step": 0.01},
	{"key": "cutoff", "label": "Synth Cutoff", "min": 100.0, "max": 1000.0, "step": 1.0},
	{"key": "drag_tone_volume", "label": "Dragtone Volume", "min": 0.0, "max": 1.0, "step": 0.01},
	{"key": "drag_neighbor_factor", "label": "Dragtone Neighbor Factor", "min": 0.0, "max": 1.0, "step": 0.01},
	{"key": "freq_threshold", "label": "Frequenz-Thr", "min": 0.0, "max": 1.0, "step": 0.01},
	{"key": "spread_time", "label": "Neighbor Spread Tone Delay", "min": 0.0, "max": 1.0, "step": 0.001},
	{"key": "spread_depth", "label": "Neighbor Cell Depth", "min": 1, "max": 6, "step": 1, "is_int": true},
	{"key": "cell_count", "label": "Number of Cells", "min": 2, "max": 100, "step": 1, "is_int": true},
	{"key": "push_factor", "label": "Push Factor", "min": 0.0, "max": 1.0, "step": 0.01},
	{"key": "push_radius", "label": "Push Radius", "min": 5.0, "max": 150.0, "step": 1.0},
	{"key": "border_margin", "label": "Border Margin", "min": 5.0, "max": 50.0, "step": 1.0},
	{"key": "weight_influence", "label": "Weight Influence", "min": 0.0, "max": 1.0, "step": 0.01},
]

const TOGGLES := [
	{"key": "alternating_moves", "label": "Wechselnde Zuege"},
	{"key": "dummy_points", "label": "DummyPoints"},
]

const WAVEFORMS := ["triangle", "sine", "square", "sawtooth"]

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
	"border_margin": 25.0,
	"weight_influence": 0.95,
	"alternating_moves": true,
	"dummy_points": true,
}

func _init() -> void:
	reset_to_defaults()

func reset_to_defaults() -> void:
	for key in DEFAULTS:
		set(key, DEFAULTS[key])
	random_seed = 0

## Spread-Delay in Millisekunden: ms = 50 * 20^t (Paritaet zu getSpreadTimeMs).
func spread_time_ms() -> float:
	return 50.0 * pow(20.0, spread_time)

func spread_time_sec() -> float:
	return spread_time_ms() / 1000.0
