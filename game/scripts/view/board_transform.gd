class_name BoardTransform
extends RefCounted

## Bildet das logische Brett (900x600) auf das Fenster ab: gleichmaessig
## skaliert und zentriert (Letterbox). Die Umkehrung wird fuer die
## Mausposition gebraucht.

const BOARD_SIZE := Vector2(GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)
const SIDE_MARGIN := 50.0
const TOP_MARGIN := 50.0
const BOTTOM_MARGIN := 70.0

var scale := 1.0
var offset := Vector2.ZERO


static func for_viewport(viewport_size: Vector2) -> BoardTransform:
	var t := BoardTransform.new()
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return t
	var available := Vector2(
		maxf(viewport_size.x - SIDE_MARGIN * 2.0, 1.0),
		maxf(viewport_size.y - TOP_MARGIN - BOTTOM_MARGIN, 1.0))
	t.scale = minf(available.x / GameConfig.BOARD_WIDTH, available.y / GameConfig.BOARD_HEIGHT)
	var free_space := available - BOARD_SIZE * t.scale
	t.offset = Vector2(SIDE_MARGIN, TOP_MARGIN) + free_space * 0.5
	return t


func to_board(screen_pos: Vector2) -> Vector2:
	if scale <= 0.0:
		return screen_pos
	return (screen_pos - offset) / scale


func to_screen(board_pos: Vector2) -> Vector2:
	return board_pos * scale + offset
