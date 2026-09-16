class_name Turns
extends RefCounted

## Regeln fuer den Zugwechsel (active_color).
##
## Die drei gekoppelten JS-Stellen (mousedown-Farbgate, automatischer
## Farbwechsel waehrend des Drags, Wechsel nach erfolgreichem Drag) sind
## hier als reine Funktionen gebuendelt.

## Darf mit dieser Zelle ein Drag gestartet werden?
static func can_start_drag(board: BoardState, cell_index: int, config: GameConfig) -> bool:
	if not config.alternating_moves:
		return true
	return board.cell_color(cell_index) == board.active_color


## Farbe des jeweils anderen Spielers.
static func toggled_color(color: String) -> String:
	return BoardState.opponent_color(color)


## Automatischer Farbwechsel: die gezogene Zelle hat ihre Farbe gewechselt.
static func should_switch_automatically(board: BoardState, cell_index: int, config: GameConfig, moved_distance: float) -> bool:
	if not config.alternating_moves:
		return false
	if moved_distance <= GameConfig.MOVE_THRESHOLD:
		return false
	var color := board.cell_color(cell_index)
	return color != "" and color != board.active_color
