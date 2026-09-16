class_name BoardState
extends RefCounted

## Gesamter veraenderlicher Spielzustand.
##
## core/ und sim/ arbeiten ausschliesslich auf diesem Objekt bzw. liefern
## neue Werte dafuer. Keine Node-, Szenen-, Audio- oder UI-Abhaengigkeit.

## Echte Zellen (inkl. gespiegelter Punkte).
var points := PackedVector2Array()
## Geschwindigkeiten (Paritaet zu updatePointPositions; werden nicht
## angetrieben, weil die Abstandskraefte die Punkte direkt verschieben).
var velocities := PackedVector2Array()
## Dummy-Punkte ausserhalb des Bretts.
var dummy_points := PackedVector2Array()
var use_dummy_points := true

## Basisfarbe je Zelle ("" = noch keine Farbe).
var cell_colors := PackedStringArray()

## Aktuell ziehender Spieler (Farbe).
var active_color := ""

var score_p1 := 0.0
var score_p2 := 0.0

## Visualisierungsdaten fuer die Drag-Linien (von input/board_input.gd
## geschrieben, von view/board_renderer.gd gelesen).
var dragged_index := -1
var drag_same_neighbor := -1
var drag_same_neighbor_area := 0.0
var drag_opponent_neighbor := -1
var drag_opponent_neighbor_area := 0.0


func reset_colors() -> void:
	cell_colors = PackedStringArray()
	cell_colors.resize(points.size())
	cell_colors.fill("")


func set_cell_color(index: int, color: String) -> void:
	if index < 0 or index >= cell_colors.size():
		return
	cell_colors[index] = color


func cell_color(index: int) -> String:
	if index < 0 or index >= cell_colors.size():
		return ""
	return cell_colors[index]


func has_color(index: int) -> bool:
	return cell_color(index) != ""


## Farben als Zahlen (0 = keine, 1 = Spieler 1, 2 = Spieler 2). Die
## Simulationsschleifen vergleichen damit Zahlen statt Zeichenketten.
static func color_id(color: String) -> int:
	if color == GameConfig.COLOR_PLAYER1:
		return 1
	if color == GameConfig.COLOR_PLAYER2:
		return 2
	return 0


static func color_for_id(id: int) -> String:
	if id == 1:
		return GameConfig.COLOR_PLAYER1
	if id == 2:
		return GameConfig.COLOR_PLAYER2
	return ""


func color_ids() -> PackedByteArray:
	var ids := PackedByteArray()
	ids.resize(cell_colors.size())
	for i in range(cell_colors.size()):
		ids[i] = color_id(cell_colors[i])
	return ids


func apply_color_ids(ids: PackedByteArray) -> void:
	for i in range(mini(ids.size(), cell_colors.size())):
		cell_colors[i] = color_for_id(ids[i])


func all_points() -> PackedVector2Array:
	if not use_dummy_points:
		return points
	var combined := points.duplicate()
	combined.append_array(dummy_points)
	return combined


## Farbe des jeweils anderen Spielers.
static func opponent_color(color: String) -> String:
	return GameConfig.COLOR_PLAYER2 if color == GameConfig.COLOR_PLAYER1 else GameConfig.COLOR_PLAYER1


func clear_drag_visuals() -> void:
	dragged_index = -1
	drag_same_neighbor = -1
	drag_same_neighbor_area = 0.0
	drag_opponent_neighbor = -1
	drag_opponent_neighbor_area = 0.0
