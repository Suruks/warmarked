class_name SkillButton
extends Control

## Кнопка скилла: иконка + бейдж стоимости маны (синий кружок цифрой) на нижней грани.
## Без тултипа — описание показывается наведением/тапом (сигнал hovered) в отдельном поле.

signal pressed
signal hovered

const W := 84
const BADGE_R := 15.0

var tex: Texture2D
var mana := 0
var is_disabled := false
var _font: Font


func _init() -> void:
	custom_minimum_size = Vector2(W, W + BADGE_R + 2)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_entered.connect(func(): hovered.emit())


func setup(p_tex: Texture2D, p_mana: int, p_disabled: bool) -> void:
	tex = p_tex
	mana = p_mana
	is_disabled = p_disabled
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		hovered.emit()          # тап тоже показывает описание (мобилка)
		if not is_disabled:
			pressed.emit()


func _draw() -> void:
	if _font == null:
		_font = ThemeDB.fallback_font
	var a := 0.35 if is_disabled else 1.0
	if tex != null:
		draw_texture_rect(tex, Rect2(0, 0, W, W), false, Color(1, 1, 1, a))
	else:
		draw_rect(Rect2(0, 0, W, W), Color(0.3, 0.3, 0.3, a))
	if mana > 0:
		var c := Vector2(W * 0.5, W)   # центр бейджа — на нижней грани иконки
		draw_circle(c, BADGE_R, Color(0.18, 0.42, 0.82, a))
		draw_arc(c, BADGE_R, 0, TAU, 24, Color(0.65, 0.82, 1.0, a), 1.5)
		draw_string(_font, Vector2(c.x - BADGE_R, c.y + 6), str(mana),
			HORIZONTAL_ALIGNMENT_CENTER, BADGE_R * 2, 18, Color(1, 1, 1, a))
