class_name ScoreHud
extends Control

## Punktestand als Zahl plus zwei Balken mit Anteilsbreite.

const BAR_WIDTH := 300.0
const BAR_HEIGHT := 20.0

@onready var _label: Label = $ScoreLabel
@onready var _bar1: ColorRect = $BarBackground/Bar1
@onready var _bar2: ColorRect = $BarBackground/Bar2


func update_scores(board: BoardState) -> void:
	_label.text = "Player1: %d Player2: %d" % [int(board.score_p1), int(board.score_p2)]
	var ratios := Scoring.bar_ratios(board)
	var width1 := BAR_WIDTH * ratios.x / 100.0
	var width2 := BAR_WIDTH * ratios.y / 100.0
	_bar1.position = Vector2.ZERO
	_bar1.size = Vector2(width1, BAR_HEIGHT)
	_bar2.position = Vector2(width1, 0.0)
	_bar2.size = Vector2(width2, BAR_HEIGHT)
