class_name ColorSteps
extends RefCounted

## Wendet die Farbwechsel der Ausbreitung nacheinander an: ein Wechsel pro
## Intervall statt alle im selben Tick. So ist zu sehen, wie ein Gebiet
## Zelle fuer Zelle an den Gegner faellt.

## Geplante Wechsel ({"cell", "color"}), in Ausbreitungsreihenfolge.
var _steps: Array = []
## Zeit, zu der der naechste Wechsel faellig ist.
var _next_at_ms := 0.0


func is_idle() -> bool:
	return _steps.is_empty()


func clear() -> void:
	_steps.clear()
	_next_at_ms = 0.0


## Wendet den faelligen Wechsel an. Ist die Warteschlange leer, wird zuerst
## der naechste Ausbreitungsschritt berechnet (brettneutrale Rechnung).
## Pro Aufruf wird hoechstens ein Wechsel angewendet; der naechste ist erst
## nach `interval_ms` faellig. Ein Zeitsprung holt also nichts nach, sondern
## haelt den Abstand ein. Gibt true zurueck, wenn eine Farbe geaendert wurde.
func advance(now_ms: float, interval_ms: float, board: BoardState, voronoi: Voronoi, iterations: int) -> bool:
	if _steps.is_empty():
		_steps = Territories.color_change_steps(CellGeometry.from_voronoi(voronoi), board.color_ids(), iterations)
		if _steps.is_empty():
			return false
	if now_ms < _next_at_ms:
		return false
	var interval := maxf(1.0, interval_ms)
	var step: Dictionary = _steps.pop_front()
	board.set_cell_color(step["cell"], BoardState.color_for_id(step["color"]))
	_next_at_ms = maxf(_next_at_ms, now_ms) + interval
	return true
