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
const COLOR_PLAYER2 := "#438FFF"
## Hintergrundfarbe aus game/assets/spielerfarben.svg (#AEA2B9).
const BACKGROUND_COLOR := "#AEA2B9"

## Farbstufen der Spieler (aus game/assets/spielerfarben.svg). Sie sind die
## drei Landmarken fuer den fliessenden Groessenverlauf jeder Spielerfarbe.
const PLAYER1_STEP_COLORS := [COLOR_PLAYER1, "#FF9945", "#FFCF6A"]
const PLAYER2_STEP_COLORS := [COLOR_PLAYER2, "#37BFFF", "#37E6FF"]

## Zelle ohne Spielerfarbe (vor der Farbzuweisung): dunkles Neutralgrau.
const CELL_EMPTY_COLOR := "#4A505A"

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
## Punkt der Zelle unter dem Mauszeiger. Die Zelle selbst bekommt beim Hover
## eine weisse Umrandung in der Dicke der normalen Zellgrenze.
const POINT_HOVER_COLOR := "#FFFFFF"

## Kurz vor der Uebernahme blinken gefaehrdete Zellen.
const BLINK_COLOR := "#FFFFFF"
const BLINK_ALPHA := 0.65
const BLINK_VALUE_THRESHOLD := 10.0
## Unter diesem summierten Einflusswert beginnt das Blinken.
const BLINK_WARN_VALUE := 10.0
## Dauer einer Blinkphase (Sekunden) bei kleinster bzw. groesster Chance.
const BLINK_SLOW_SEC := 0.75
const BLINK_FAST_SEC := 0.12

const COLOR_PROPAGATION_ITERATIONS := 12

## Einflussverteilung: Startstaerke an der groessten Zelle eines Spielers.
const INFLUENCE_START_STRENGTH := 100.0
## Anteil der Staerke, der ueber eine ideale Grenze weitergegeben wird. Groessere
## Nachbarzellen und laengere gemeinsame Grenzen geben mehr weiter.
const INFLUENCE_TRANSFER_RATE := 0.9
## Unter dieser Staerke gilt eine Zelle als neutral: sie gehoert keinem Spieler
## und bleibt grau.
const INFLUENCE_MIN_STRENGTH := 0.5

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
## Anzahl zusaetzlicher Oktaven fuer alle Zelltoene.
@export var octave_shift: int = 1

@export var drag_tone_volume: float = 0.2
@export var drag_neighbor_factor: float = 0.25

@export var freq_threshold: float = 0.2
@export var spread_time: float = 0.6
@export var spread_depth: int = 2

@export var cell_count: int = 16

@export var push_factor: float = 0.2
@export var push_radius: float = 40.0
@export var border_margin: float = 50.0
@export var weight_influence: float = 1.0

@export var alternating_moves: bool = true
## Ausdauer je Spieler; ein Pixel Drag-Strecke verbraucht einen Punkt.
@export var stamina: float = 1000.0
@export var dummy_points: bool = true
## Flaechenzahlen in den Zellen anzeigen (beim Start aus).
@export var show_cell_numbers: bool = false
## Vererbungswege der aktuellen oder aller Zellen anzeigen.
@export var show_flow: bool = false
## Vererbungswege fuer jede echte Zelle anzeigen.
@export var show_all_flows: bool = false
## Gegenseitige Einflusswerte aller Zellen anzeigen.
@export var show_all_cell_numbers: bool = false
## Abstand zwischen zwei Farbwechseln, wenn Zellen verloren gehen (ms).
@export var loss_step_ms: float = 25.0
## Zeit, um eine waehrend des Drags verlorene Zelle zu retten (ms).
@export var loss_rescue_ms: float = 1000.0
## Radius, mit dem die Territoriums-Grenze abgerundet wird (Brettpixel).
@export var corner_radius: float = 8.0
## Optischer Abstand zwischen Zellfuellungen, ohne Einfluss auf die Geometrie.
@export var cell_gap: float = 0.0
## Gemeinsame Grenzlinien unterhalb dieser Laenge erhalten kein Zahlenlabel.
@export var boundary_label_threshold: float = 10.0
## Radius der Zellpunkte in Brettpixeln.
@export var point_radius: float = 8.0

# -------------------------------------------------------- Halbtonraster -----
## Bildschirmweiter CMYK-Halbton-Effekt ueber dem Spiel. Die Einstellungen
## selbst bleiben ungerastert (siehe view/halftone_overlay.gd).
@export var halftone_enabled: bool = true
## Quelle des Streumusters: "code" erzeugt es beim Start, "asset" laedt die
## PNG-Datei aus game/assets.
@export var halftone_pattern: String = "code"
## Rasterweite: Anzahl der Musterwiederholungen ueber den Bildschirm.
@export var halftone_pattern_scaling: float = 6.0
## Qualitaet der Mehrfachabtastung (hoeher = glatter, aber langsamer).
@export var halftone_sampling_quality: float = 0.5
## Rasterwinkel je Druckfarbe in Grad.
@export var halftone_cyan_rotation: float = 0.0
@export var halftone_magenta_rotation: float = 15.0
@export var halftone_yellow_rotation: float = 30.0
@export var halftone_black_rotation: float = 45.0
## Zusaetzlicher Farbauszug je Druckfarbe in Grad.
@export var halftone_cyan_offset_rotation: float = 0.0
@export var halftone_magenta_offset_rotation: float = 0.0
@export var halftone_yellow_offset_rotation: float = 0.0
@export var halftone_black_offset_rotation: float = 0.0
## Helligkeitsschwelle, unter der Bildpunkte als durchsichtig gelten.
@export var halftone_alpha_threshold: float = 0.5
## Druckdeckkraft je Druckfarbe: 0 = kein Farbauftrag, 1 = volle Deckung.
@export var halftone_cyan_ink: float = 1.0
@export var halftone_magenta_ink: float = 1.0
@export var halftone_yellow_ink: float = 1.0
@export var halftone_black_ink: float = 1.0
## Staerke der Rauschtextur auf der Deckkraft: 0 = gleichmaessiger Auftrag.
## Jede Druckfarbe hat eigene Werte, damit die Kanaele unabhaengig streuen.
@export var halftone_cyan_noise_strength: float = 0.0
@export var halftone_magenta_noise_strength: float = 0.0
@export var halftone_yellow_noise_strength: float = 0.0
@export var halftone_black_noise_strength: float = 0.0
## Wiederholungen der Rauschtextur ueber den Bildschirm, je Druckfarbe.
@export var halftone_cyan_noise_scaling: float = 4.0
@export var halftone_magenta_noise_scaling: float = 4.0
@export var halftone_yellow_noise_scaling: float = 4.0
@export var halftone_black_noise_scaling: float = 4.0

@export var random_seed: int = 0

# ------------------------------------------------------------- Schema ------
## Reihenfolge der Gruppen im Einstellungsmenue.
const SETTING_GROUPS := ["Klang", "Spiel", "Darstellung", "Halbton"]

const SLIDERS := [
	{"key": "attack", "label": "Attack", "min": 0.0, "max": 3.0, "step": 0.01, "group": "Klang"},
	{"key": "decay", "label": "Decay", "min": 0.0, "max": 3.0, "step": 0.01, "group": "Klang"},
	{"key": "sustain", "label": "Sustain", "min": 0.0, "max": 1.0, "step": 0.01, "group": "Klang"},
	{"key": "release", "label": "Release", "min": 0.0, "max": 3.0, "step": 0.01, "group": "Klang"},
	{"key": "cutoff", "label": "Synth Cutoff", "min": 100.0, "max": 1000.0, "step": 1.0, "group": "Klang"},
	{"key": "octave_shift", "label": "Oktaven hoch", "min": 0, "max": 3, "step": 1, "is_int": true, "group": "Klang"},
	{"key": "drag_tone_volume", "label": "Dragtone Volume", "min": 0.0, "max": 1.0, "step": 0.01, "group": "Klang"},
	{"key": "drag_neighbor_factor", "label": "Dragtone Neighbor Factor", "min": 0.0, "max": 1.0, "step": 0.01, "group": "Klang"},
	{"key": "freq_threshold", "label": "Frequenz-Thr", "min": 0.0, "max": 1.0, "step": 0.01, "group": "Klang"},
	{"key": "spread_time", "label": "Neighbor Spread Tone Delay", "min": 0.0, "max": 1.0, "step": 0.001, "group": "Klang"},
	{"key": "spread_depth", "label": "Neighbor Cell Depth", "min": 1, "max": 6, "step": 1, "is_int": true, "group": "Klang"},
	{"key": "cell_count", "label": "Number of Cells", "min": 2, "max": 16, "step": 1, "is_int": true, "group": "Spiel"},
	{"key": "push_factor", "label": "Push Factor", "min": 0.0, "max": 1.0, "step": 0.01, "group": "Spiel"},
	{"key": "push_radius", "label": "Push Radius", "min": 5.0, "max": 150.0, "step": 1.0, "group": "Spiel"},
	{"key": "border_margin", "label": "Border Margin", "min": 5.0, "max": 100.0, "step": 1.0, "group": "Spiel"},
	{"key": "weight_influence", "label": "Weight Influence", "min": 0.0, "max": 1.0, "step": 0.01, "group": "Spiel"},
	{"key": "stamina", "label": "Ausdauer", "min": 100.0, "max": 5000.0, "step": 100.0, "is_int": true, "group": "Spiel"},
	{"key": "loss_step_ms", "label": "Verlust-Schritt (ms)", "min": 0.0, "max": 300.0, "step": 5.0, "group": "Spiel"},
	{"key": "loss_rescue_ms", "label": "Rettungszeit (ms)", "min": 0.0, "max": 5000.0, "step": 50.0, "group": "Spiel"},
	{"key": "corner_radius", "label": "Zell-Abrundung", "min": 0.0, "max": 150.0, "step": 0.5, "group": "Darstellung"},
	{"key": "cell_gap", "label": "Zellabstand", "min": 0.0, "max": 4.0, "step": 0.01, "group": "Darstellung"},
	{"key": "boundary_label_threshold", "label": "Mindest-Grenzlinie", "min": 0.0, "max": 100.0, "step": 1.0, "group": "Darstellung"},
	{"key": "point_radius", "label": "Punktgroesse", "min": 4.0, "max": 20.0, "step": 1.0, "group": "Darstellung"},
	{"key": "halftone_pattern_scaling", "label": "Rasterweite", "min": 0.05, "max": 24.0, "step": 0.01, "group": "Halbton"},
	{"key": "halftone_sampling_quality", "label": "Qualitaet", "min": 0.05, "max": 1.0, "step": 0.05, "group": "Halbton"},
	{"key": "halftone_cyan_rotation", "label": "Cyan Winkel", "min": -180.0, "max": 180.0, "step": 1.0, "group": "Halbton"},
	{"key": "halftone_magenta_rotation", "label": "Magenta Winkel", "min": -180.0, "max": 180.0, "step": 1.0, "group": "Halbton"},
	{"key": "halftone_yellow_rotation", "label": "Gelb Winkel", "min": -180.0, "max": 180.0, "step": 1.0, "group": "Halbton"},
	{"key": "halftone_black_rotation", "label": "Schwarz Winkel", "min": -180.0, "max": 180.0, "step": 1.0, "group": "Halbton"},
	{"key": "halftone_cyan_offset_rotation", "label": "Cyan Auszug", "min": -18.0, "max": 18.0, "step": 0.01, "group": "Halbton"},
	{"key": "halftone_magenta_offset_rotation", "label": "Magenta Auszug", "min": -18.0, "max": 18.0, "step": 0.01, "group": "Halbton"},
	{"key": "halftone_yellow_offset_rotation", "label": "Gelb Auszug", "min": -18.0, "max": 18.0, "step": 0.01, "group": "Halbton"},
	{"key": "halftone_black_offset_rotation", "label": "Schwarz Auszug", "min": -18.0, "max": 18.0, "step": 0.01, "group": "Halbton"},
	{"key": "halftone_alpha_threshold", "label": "Alpha-Schwelle", "min": 0.0, "max": 1.0, "step": 0.01, "group": "Halbton"},
	{"key": "halftone_cyan_ink", "label": "Cyan Deckkraft", "min": 0.0, "max": 1.0, "step": 0.01, "group": "Halbton"},
	{"key": "halftone_magenta_ink", "label": "Magenta Deckkraft", "min": 0.0, "max": 1.0, "step": 0.01, "group": "Halbton"},
	{"key": "halftone_yellow_ink", "label": "Gelb Deckkraft", "min": 0.0, "max": 1.0, "step": 0.01, "group": "Halbton"},
	{"key": "halftone_black_ink", "label": "Schwarz Deckkraft", "min": 0.0, "max": 1.0, "step": 0.01, "group": "Halbton"},
	{"key": "halftone_cyan_noise_scaling", "label": "Cyan Rausch-Weite", "min": 0.05, "max": 24.0, "step": 0.01, "group": "Halbton"},
	{"key": "halftone_cyan_noise_strength", "label": "Cyan Rausch-Staerke", "min": 0.0, "max": 1.0, "step": 0.01, "group": "Halbton"},
	{"key": "halftone_magenta_noise_scaling", "label": "Magenta Rausch-Weite", "min": 0.05, "max": 24.0, "step": 0.01, "group": "Halbton"},
	{"key": "halftone_magenta_noise_strength", "label": "Magenta Rausch-Staerke", "min": 0.0, "max": 1.0, "step": 0.01, "group": "Halbton"},
	{"key": "halftone_yellow_noise_scaling", "label": "Gelb Rausch-Weite", "min": 0.05, "max": 24.0, "step": 0.01, "group": "Halbton"},
	{"key": "halftone_yellow_noise_strength", "label": "Gelb Rausch-Staerke", "min": 0.0, "max": 1.0, "step": 0.01, "group": "Halbton"},
	{"key": "halftone_black_noise_scaling", "label": "Schwarz Rausch-Weite", "min": 0.05, "max": 24.0, "step": 0.01, "group": "Halbton"},
	{"key": "halftone_black_noise_strength", "label": "Schwarz Rausch-Staerke", "min": 0.0, "max": 1.0, "step": 0.01, "group": "Halbton"},
]

const TOGGLES := [
	{"key": "alternating_moves", "label": "Wechselnde Zuege", "group": "Spiel"},
	{"key": "dummy_points", "label": "DummyPoints", "group": "Spiel"},
	{"key": "show_cell_numbers", "label": "Zahlen anzeigen", "group": "Darstellung"},
	{"key": "show_flow", "label": "Flow anzeigen", "group": "Darstellung"},
	{"key": "show_all_flows", "label": "Flows fuer alle Zellen", "group": "Darstellung"},
	{"key": "show_all_cell_numbers", "label": "Zahlen fuer alle Zellen", "group": "Darstellung"},
	{"key": "halftone_enabled", "label": "Halbtonraster", "group": "Halbton"},
]

const WAVEFORMS := ["triangle", "sine", "square", "sawtooth"]
## Musterquellen des Halbton-Effekts: im Code erzeugt oder als PNG-Datei.
const HALFTONE_PATTERNS := ["code", "asset"]

## Auswahlfelder im Einstellungsmenue. "values" sind die gespeicherten Werte,
## "labels" die angezeigten Texte.
const CHOICES := [
	{"key": "waveform", "label": "Wave", "values": WAVEFORMS, "labels": WAVEFORMS,
		"group": "Klang"},
	{"key": "halftone_pattern", "label": "Streumuster", "values": HALFTONE_PATTERNS,
		"labels": ["Im Code", "PNG-Datei"], "group": "Halbton"},
]

const DEFAULTS := {
	"waveform": "triangle",
	"attack": 0.05,
	"decay": 0.2,
	"sustain": 0.2,
	"release": 0.1,
	"cutoff": 500.0,
	"octave_shift": 1,
	"drag_tone_volume": 0.2,
	"drag_neighbor_factor": 0.25,
	"freq_threshold": 0.2,
	"spread_time": 0.6,
	"spread_depth": 2,
	"cell_count": 16,
	"push_factor": 0.2,
	"push_radius": 40.0,
	"border_margin": 50.0,
	"weight_influence": 1.0,
	"stamina": 1000.0,
	"loss_step_ms": 25.0,
	"loss_rescue_ms": 1000.0,
	"corner_radius": 8.0,
	"cell_gap": 0.0,
	"point_radius": 8.0,
	"alternating_moves": true,
	"dummy_points": true,
	"show_cell_numbers": false,
	"show_flow": false,
	"show_all_flows": false,
	"show_all_cell_numbers": false,
	"boundary_label_threshold": 10.0,
	"halftone_enabled": true,
	"halftone_pattern": "code",
	"halftone_pattern_scaling": 6.0,
	"halftone_sampling_quality": 0.5,
	"halftone_cyan_rotation": 0.0,
	"halftone_magenta_rotation": 15.0,
	"halftone_yellow_rotation": 30.0,
	"halftone_black_rotation": 45.0,
	"halftone_cyan_offset_rotation": 0.0,
	"halftone_magenta_offset_rotation": 0.0,
	"halftone_yellow_offset_rotation": 0.0,
	"halftone_black_offset_rotation": 0.0,
	"halftone_alpha_threshold": 0.5,
	"halftone_cyan_ink": 1.0,
	"halftone_magenta_ink": 1.0,
	"halftone_yellow_ink": 1.0,
	"halftone_black_ink": 1.0,
	"halftone_cyan_noise_strength": 0.0,
	"halftone_magenta_noise_strength": 0.0,
	"halftone_yellow_noise_strength": 0.0,
	"halftone_black_noise_strength": 0.0,
	"halftone_cyan_noise_scaling": 4.0,
	"halftone_magenta_noise_scaling": 4.0,
	"halftone_yellow_noise_scaling": 4.0,
	"halftone_black_noise_scaling": 4.0,
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
