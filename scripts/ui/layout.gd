class_name Layout
extends RefCounted

## Единственный источник правды по раскладке портретного экрана. Раньше все размеры были
## фиксированы под 540x1200 (см. git-историю); теперь клетка доски и всё, что от неё зависит,
## пересчитываются под РЕАЛЬНЫЙ размер экрана вызовом recompute() — доска и нижняя панель
## (в т.ч. кнопка «Готово») растягиваются, а не остаются приклеенными к фиксированной ширине.
## Дергает recompute() main.gd при старте и на каждый resize/поворот экрана.

# --- Фиксированные отступы (не зависят от размера экрана) ---
const TOP_MARGIN := 56          # верхний отступ экрана боя; справа в нём — кнопка настроек (крупнее
                                 # этого отступа — свисает поверх полосы очков, см. main.gd OPT_TOP_PAD)
const BOARD_X := 4              # левый/правый отступ доски и полос от края раскладки
const BOARD_GAP := 42           # отступ от TOP_MARGIN до верха доски
const SCORE_H := 30
const SCORE_TOP_GAP := 8        # отступ полосы очков соперника от TOP_MARGIN
const SCORE_BOTTOM_GAP := 4     # отступ полосы очков игрока от низа доски
const SCORE_PAD := 12           # отступ под очками игрока
const EFFECT_H := 56
const EFFECT_GAP := 6           # отступ от полосы эффектов до нижней панели
const PANEL_BOTTOM_MARGIN := 8

const MIN_CELL := 50.0          # ниже не сжимаем клетку — экран должен быть совсем крохотным
# Минимум высоты нижней панели, резервируемый ПРИ ПОДБОРЕ КЛЕТКИ (не путать с фактической
# PANEL_H — та почти всегда получается больше, см. ниже). Раньше здесь было 454 (столько и
# была панель при исходных 540x1200) — из-за этого клетка НЕ РОСЛА на экранах, где EXPAND
# расширяет ширину, а высота остаётся ровно 1200 (типичный телефон: экран у него ШИРЕ
# пропорции 540:1200, поэтому EXPAND расширяет именно ширину, а не высоту — выяснено на
# реальном устройстве: 1080x1929 -> canvas 671x1200). При МИНИМАЛЬНОМ 454 высотный бюджет
# был расписан впритык под ровно 1200 при клетке 76 — свободного места для роста не оставалось,
# сколько бы лишней ширины ни было. 380 — фактический минимум, при котором ещё не уходит в
# минус описание умения в панели планирования (см. вывод DESC_H в planning_panel.gd:
# DESC_H = PANEL_H - 312, то есть 380 даёт DESC_H = 68px — работоспособный, а не «в притык»).
const MIN_PANEL_H := 380.0

# --- Динамические (пересчитываются в recompute() под реальный размер экрана) ---
# Литералы ниже — те же значения, что дал бы recompute() при 540x1200 (исходная раскладка);
# независимые литералы, а не выражения друг через друга — так порядок инициализации static var
# ни на что не влияет. Актуализируются вызовом recompute() ещё до первой отрисовки (см. main.gd).
static var cell_size: float = 76.0
static var BOARD_PX: float = 532.0
static var BOARD_Y: float = 98.0
static var BOARD_BOTTOM: float = 630.0
static var SCORE_TOP_Y: float = 64.0
static var SCORE_BOTTOM_Y: float = 634.0
static var EFFECT_Y: float = 676.0
static var PANEL_TOP: float = 738.0
static var PANEL_W: float = 532.0
static var PANEL_H: float = 454.0
static var SCREEN_W: float = 540.0
static var SCREEN_H: float = 1200.0


# Подбирает клетку доски КАК МОЖНО БОЛЬШЕ, но так, чтобы вся раскладка (доска + обвязка)
# целиком влезала и по ширине, и по высоте реального экрана (avail_w x avail_h) — большая
# из двух кандидатных клеток (по ширине/по высоте) не берётся, чтобы не обрезать другую ось.
# Лишнее место по НЕограничивающей оси остаётся — main.gd центрирует раскладку по ширине
# и отдаёт нижней панели высоту (см. _apply_layout), поэтому пустых полос не возникает.
static func recompute(avail_w: float, avail_h: float) -> void:
	var cell_by_w := (avail_w - 2.0 * BOARD_X) / float(Consts.BOARD_W)
	var fixed_v_chrome := TOP_MARGIN + BOARD_GAP + SCORE_H + SCORE_BOTTOM_GAP + SCORE_PAD \
			+ EFFECT_H + EFFECT_GAP + PANEL_BOTTOM_MARGIN + MIN_PANEL_H
	var cell_by_h := (avail_h - fixed_v_chrome) / float(Consts.BOARD_H)
	cell_size = maxf(MIN_CELL, minf(cell_by_w, cell_by_h))

	BOARD_PX = cell_size * Consts.BOARD_W
	BOARD_Y = TOP_MARGIN + BOARD_GAP
	BOARD_BOTTOM = BOARD_Y + cell_size * Consts.BOARD_H
	SCORE_TOP_Y = TOP_MARGIN + SCORE_TOP_GAP
	SCORE_BOTTOM_Y = BOARD_BOTTOM + SCORE_BOTTOM_GAP
	EFFECT_Y = SCORE_BOTTOM_Y + SCORE_H + SCORE_PAD
	PANEL_TOP = EFFECT_Y + EFFECT_H + EFFECT_GAP
	PANEL_W = BOARD_PX
	SCREEN_W = BOARD_PX + 2.0 * BOARD_X
	SCREEN_H = maxf(avail_h, PANEL_TOP + MIN_PANEL_H + PANEL_BOTTOM_MARGIN)
	PANEL_H = SCREEN_H - PANEL_TOP - PANEL_BOTTOM_MARGIN
