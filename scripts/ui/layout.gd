class_name Layout
extends RefCounted

## Единственный источник правды по раскладке портретного экрана.
## Раньше эти числа были размазаны магическими литералами по main.gd и planning_panel.gd
## (1200, 42, 44, 8), причём panel_height считался в двух местах независимо.
##
## SCREEN_* обязаны совпадать с display/window/size/* из project.godot — это проверяет
## verify_project_settings() при старте (см. main.gd).

const SCREEN_W := 540
const SCREEN_H := 1200

const BOARD_X := 4
const BOARD_Y := 42                                      # под верхней полосой очков
const BOARD_PX := BoardView.CELL * Consts.BOARD_W        # ширина = высота доски (квадрат)
const BOARD_BOTTOM := BOARD_Y + BoardView.CELL * Consts.BOARD_H

const SCORE_H := 30
const SCORE_TOP_Y := 8                                   # очки соперника — над доской
const SCORE_BOTTOM_Y := BOARD_BOTTOM + 4                 # очки игрока — под доской
const SCORE_PAD := 12                                    # отступ под очками игрока

# Панель эффектов выделенного юнита — между очками и скиллами
const EFFECT_Y := SCORE_BOTTOM_Y + SCORE_H + SCORE_PAD
const EFFECT_H := 56

const PANEL_BOTTOM_MARGIN := 8
const PANEL_TOP := EFFECT_Y + EFFECT_H + 6               # скиллы начинаются под полосой эффектов
const PANEL_W := BOARD_PX
const PANEL_H := SCREEN_H - PANEL_TOP - PANEL_BOTTOM_MARGIN


# Раскладка сверстана под фиксированный портретный вьюпорт. Если его поменяли в project.godot,
# а константы забыли — предупредить, а не молча разъехаться.
static func verify_project_settings() -> void:
	var w: int = ProjectSettings.get_setting("display/window/size/viewport_width", SCREEN_W)
	var h: int = ProjectSettings.get_setting("display/window/size/viewport_height", SCREEN_H)
	if w != SCREEN_W or h != SCREEN_H:
		push_warning("Layout: вьюпорт %dx%d не совпадает с константами %dx%d — раскладка разъедется"
			% [w, h, SCREEN_W, SCREEN_H])
