class_name ColorSteps
extends RefCounted

## Wendet die Farbwechsel der Ausbreitung nacheinander an: ein Wechsel pro
## Intervall statt alle im selben Tick. So ist zu sehen, wie ein Gebiet
## Zelle fuer Zelle an den Gegner faellt.

## Geplante Wechsel ({"cell", "color"}), in Ausbreitungsreihenfolge.
var _steps: Array = []
## Zeit, zu der der naechste Wechsel faellig ist.
var _next_at_ms := 0.0
## Ein bereits angewendeter Schritt wartet noch auf sein Intervall.
var _waiting := false


func is_idle() -> bool:
	return _steps.is_empty() and not _waiting


func clear() -> void:
	_steps.clear()
	_next_at_ms = 0.0
	_waiting = false


## Wendet den faelligen Wechsel an. Ist die Warteschlange leer, wird zuerst
## der naechste Ausbreitungsschritt berechnet (brettneutrale Rechnung).
## Pro Aufruf wird hoechstens ein Wechsel angewendet; der naechste ist erst
## nach `interval_ms` faellig. Ein Zeitsprung holt also nichts nach, sondern
## haelt den Abstand ein.
##
## Rueckgabe: Index der Zelle, die dabei die Farbe des aktiven Spielers
## verloren hat (-1, wenn kein Wechsel anstand oder niemand etwas verlor).
func advance(now_ms: float, interval_ms: float, board: BoardState, voronoi: Voronoi, iterations: int) -> int:
	if now_ms < _next_at_ms:
		# Nicht einmal die Kandidaten neu berechnen: beim zweiten Pass des
		# gleichen Frames waere die Geometriearbeit ohnehin vergeblich.
		_waiting = true
		return -1
	_waiting = false
	if _steps.is_empty():
		var candidates := Territories.color_change_steps(
			CellGeometry.from_voronoi(voronoi, true), board.color_ids(), iterations,
			Territories.COLOR_SWITCH_MARGIN_RATIO, board.influence_roots(),
			board.influence_start_strength)
		if candidates.is_empty():
			return -1
		# Nur den aktuell besten Wechsel vormerken. Die restliche Liste wird
		# nach jedem Wechsel neu berechnet; dadurch werden keine veralteten
		# Entscheidungen aus einem frueheren Brettzustand abgearbeitet.
		_steps = [candidates[0]]
	var interval := maxf(1.0, interval_ms)
	var step: Dictionary = _steps.pop_front()
	var cell: int = step["cell"]
	var new_color := BoardState.color_for_id(step["color"])
	var lost := board.cell_color(cell) == board.active_color and new_color != board.active_color
	board.set_cell_color(cell, new_color)
	_steps.clear()
	_next_at_ms = maxf(_next_at_ms, now_ms) + interval
	return cell if lost else -1
