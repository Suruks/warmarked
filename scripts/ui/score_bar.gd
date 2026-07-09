class_name ScoreBar
extends Control

## Ряд из total кружков победных очков. Первые filled — закрашены золотом,
## остальные — золотой контур (напоминают о максимуме).

const GOLD := Color("caa63c")
const R := 11.0
const GAP := 10.0

var total := Consts.WIN_SCORE
var filled := 0


func _ready() -> void:
	custom_minimum_size = Vector2(total * (2 * R) + (total - 1) * GAP, 2 * R + 6)


func set_score(f: int) -> void:
	filled = clampi(f, 0, total)
	queue_redraw()


func _draw() -> void:
	var step := 2 * R + GAP
	var w := total * (2 * R) + (total - 1) * GAP
	var x := (size.x - w) * 0.5 + R   # центрируем по ширине
	var y := size.y * 0.5
	for i in total:
		var c := Vector2(x + i * step, y)
		if i < filled:
			draw_circle(c, R, GOLD)
		else:
			draw_arc(c, R, 0, TAU, 24, Color(GOLD.r, GOLD.g, GOLD.b, 0.5), 2.0)
