class_name BoardTransform
extends RefCounted

## Bildet das logische Brett (900x600) auf das Fenster ab: gleichmaessig
## skaliert und zentriert (Letterbox). Die Umkehrung wird fuer die
## Mausposition gebraucht.

const BOARD_SIZE := Vector2(GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)

var scale := 1.0
var offset := Vector2.ZERO


static func for_viewport(viewport_size: Vector2) -> BoardTransform:
	var t := BoardTransform.new()
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return t
	t.scale = minf(viewport_size.x / GameConfig.BOARD_WIDTH, viewport_size.y / GameConfig.BOARD_HEIGHT)
	t.offset = (viewport_size - BOARD_SIZE * t.scale) * 0.5
	return t


func to_board(screen_pos: Vector2) -> Vector2:
	if scale <= 0.0:
		return screen_pos
	return (screen_pos - offset) / scale


func to_screen(board_pos: Vector2) -> Vector2:
	return board_pos * scale + offset
