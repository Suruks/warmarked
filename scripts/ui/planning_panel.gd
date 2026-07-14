class_name PlanningPanel
extends Control

## Мобильный планировщик под доской.
##   • Клик по юниту (своему ИЛИ чужому) → в баннере/ряду показываются его скиллы.
##   • Клик по СВОЕМУ скиллу → использование: если нужна цель, кликни клетку на поле.
##   • Чужие скиллы — только просмотр (кнопки заблокированы).
##   • 4 слота (тайминг): использование заполняет активный слот, затем авто-переход к
##     следующему пустому. Ниже — ряд из 8 чипов: мои 4 + 4 соперника (тёмный = запланирован).
##   • Нацеленные скиллы отмечаются мелкими иконками в целевых клетках (board_view.markers).

signal orders_ready(orders: Array)
signal progress_changed(filled: Array)   # какие мои слоты заполнены (для индикации сопернику)

const COL_OPP_EMPTY := Color(0.44, 0.47, 0.54)    # вражеские слоты — светлее (пустой)
const COL_OPP_FILLED := Color(0.26, 0.29, 0.35)   # занятый: темнее пустого, но тоже осветлён
const COL_SLOT_BG := Color(0.46, 0.49, 0.56)   # фон квадратов слотов (светлее тёмной темы кнопок)

# Жёстко заданные позиции (элементы не смещаются по вертикали при смене содержимого)
const SLOT_BIG := 60
const SLOT_SMALL := 28
const SLOT_GAP := 6
const SLOT_PAD := 4      # отступ иконки от края круглого слота (меньше отступ — крупнее иконка)
const HEROICON := 34
const SKILLS_Y := 4
const SKILLS_H := 104
const DESC_Y := 116

# Зависят от Layout.PANEL_W/PANEL_H — растягивается вместе с доской под реальный экран
# (Layout.recompute), поэтому не const: пересчитываются в _build_ui() при каждом begin().
var PANEL_W: float
var PANEL_H: float
var DONE_Y: float    # «Готово» — прижато к низу экрана
var HEROICON_Y: float
var SLOTS_Y: float
var ERR_Y: float
var DESC_H: float    # описание занимает всё место между скиллами и слотами

var state: MatchState
var player: int
var board_view: BoardView

var slot_hero: Array = [-1, -1, -1, -1]
var slot_action: Array = [Consts.Action.EMPTY, Consts.Action.EMPTY, Consts.Action.EMPTY, Consts.Action.EMPTY]
var slot_target: Array = [Vector2i(-1, -1), Vector2i(-1, -1), Vector2i(-1, -1), Vector2i(-1, -1)]
var slot_path: Array = [[], [], [], []]
var slot_cells: Array = [[], [], [], []]   # только для мультиклеточных скиллов (Минное поле): выбранные клетки

var _active: int = 0
var _view_id: int = -1     # чей китбар показан (может быть враг)
var _pending_action: int = Consts.Action.EMPTY   # выбранное, но не подтверждённое действие
var _pending_hero: int = -1
var _pending_cells: Array = []   # накопленные клетки для мультиклеточного нацеливания (Минное поле)
var _drag_id: int = -1           # герой, которого сейчас тащим (ручная прокладка маршрута)
var _drag_path: Array = []       # накопленный маршрут перетаскивания (абсолютные клетки, без origin)
var _hover_route: Array = []     # превью маршрута к наведённой клетке при обычном выборе хода
var _locked_slot: int = -1       # мой недоступный слот (второй игрок пропускает последний)
var _opp_locked_slot: int = -1   # недоступный слот соперника (для индикации)

var _skills_row: HBoxContainer
var _desc_field: RichTextLabel
var _slot_chips: Array = []
var _slot_heroicons: Array = []
var _opp_chips: Array = []
var _opp_filled: Array = [false, false, false, false]   # заполненные слоты соперника (индикация)
var _last_progress = null
var _err_lbl: Label
var _skill_btns: Array = []


func begin(p_state: MatchState, p_player: int, p_board_view: BoardView) -> void:
	state = p_state
	player = p_player
	board_view = p_board_view
	slot_hero = [-1, -1, -1, -1]
	slot_action = [Consts.Action.EMPTY, Consts.Action.EMPTY, Consts.Action.EMPTY, Consts.Action.EMPTY]
	slot_target = [Vector2i(-1, -1), Vector2i(-1, -1), Vector2i(-1, -1), Vector2i(-1, -1)]
	slot_path = [[], [], [], []]
	slot_cells = [[], [], [], []]
	# Второй игрок раунда пропускает последний слот (чередование без двойного хода)
	var me_first := state.first_player_this_round() == player
	_locked_slot = -1 if me_first else Consts.ORDER_SLOTS - 1
	_opp_locked_slot = Consts.ORDER_SLOTS - 1 if me_first else -1
	_active = 0
	_view_id = -1
	_drag_id = -1
	_drag_path = []
	_hover_route = []
	board_view.set_selected_unit(-1)
	if not board_view.cell_clicked.is_connected(_on_cell_clicked):
		board_view.cell_clicked.connect(_on_cell_clicked)
		board_view.drag_started.connect(_on_drag_started)
		board_view.drag_updated.connect(_on_drag_updated)
		board_view.drag_ended.connect(_on_drag_ended)
		board_view.cell_hovered.connect(_on_cell_hovered)
	_build_ui()
	_refresh()


# ------------------------------------------------------------- построение UI

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()
	_slot_chips = []
	_slot_heroicons = []
	_opp_chips = []

	# Панель растягивается вместе с доской (Layout.PANEL_W/PANEL_H пересчитаны под реальный
	# экран) — перечитываем их заново при каждой сборке, а не берём фиксированными на старте.
	PANEL_W = Layout.PANEL_W
	PANEL_H = Layout.PANEL_H
	DONE_Y = PANEL_H - 56
	HEROICON_Y = DONE_Y - 8 - HEROICON
	SLOTS_Y = HEROICON_Y - 4 - SLOT_BIG
	ERR_Y = SLOTS_Y - 26
	DESC_H = ERR_Y - DESC_Y - 8

	# ряд скиллов — по центру, фиксированная позиция
	_skills_row = HBoxContainer.new()
	_skills_row.add_theme_constant_override("separation", 8)
	_skills_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_skills_row.position = Vector2(0, SKILLS_Y)
	_skills_row.size = Vector2(PANEL_W, SKILLS_H)
	add_child(_skills_row)

	# поле описания скилла (между скиллами и слотами)
	_desc_field = RichTextLabel.new()
	_desc_field.bbcode_enabled = true
	_desc_field.scroll_active = false
	_desc_field.clip_contents = true
	_desc_field.add_theme_font_size_override("normal_font_size", 17)
	_desc_field.add_theme_font_size_override("bold_font_size", 19)
	_desc_field.position = Vector2(10, DESC_Y)
	_desc_field.size = Vector2(PANEL_W - 20, DESC_H)
	add_child(_desc_field)

	# слоты (в порядке разрешения: мои крупные + соперника мелкие; под слотом — иконка героя)
	for i in Consts.ORDER_SLOTS:
		var chip := Button.new()
		chip.size = Vector2(SLOT_BIG, SLOT_BIG)
		chip.expand_icon = true
		chip.add_theme_font_size_override("font_size", 20)
		for st in ["normal", "hover", "pressed", "focus"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = COL_SLOT_BG if st != "hover" else COL_SLOT_BG.lightened(0.08)
			sb.set_corner_radius_all(SLOT_BIG / 2)   # круглый слот (радиус = половина стороны)
			# квадратную иконку поджимаем внутрь круга, чтобы углы не торчали за окружность
			sb.content_margin_left = SLOT_PAD
			sb.content_margin_top = SLOT_PAD
			sb.content_margin_right = SLOT_PAD
			sb.content_margin_bottom = SLOT_PAD
			chip.add_theme_stylebox_override(st, sb)
		chip.pressed.connect(_on_my_slot_pressed.bind(i))
		add_child(chip)
		_slot_chips.append(chip)
		var hi := TextureRect.new()
		hi.size = Vector2(HEROICON, HEROICON)
		hi.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hi.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		add_child(hi)
		_slot_heroicons.append(hi)
		# слот-индикатор соперника: круглый (Panel + StyleBoxFlat; ColorRect не умеет скругление)
		var opp := Panel.new()
		opp.size = Vector2(SLOT_SMALL, SLOT_SMALL)
		var osb := StyleBoxFlat.new()
		osb.bg_color = COL_OPP_EMPTY
		osb.set_corner_radius_all(SLOT_SMALL / 2)
		opp.add_theme_stylebox_override("panel", osb)
		add_child(opp)
		_opp_chips.append(opp)
	_layout_slots(state.first_player_this_round() == player)

	_err_lbl = Label.new()
	_err_lbl.add_theme_font_size_override("font_size", 15)
	_err_lbl.add_theme_color_override("font_color", Color(1, 0.5, 0.5))
	_err_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_err_lbl.position = Vector2(10, ERR_Y)
	_err_lbl.size = Vector2(PANEL_W - 20, 44)
	add_child(_err_lbl)

	var done := Button.new()
	done.text = "Готово"
	done.add_theme_font_size_override("font_size", 20)
	done.position = Vector2(10, DONE_Y)
	done.size = Vector2(PANEL_W - 20, 48)
	done.pressed.connect(_on_done)
	add_child(done)


# Раскладка ряда слотов в порядке разрешения, чередуя мои (крупные) и соперника (мелкие).
# Отсутствующие слоты (последний у второго игрока) пропускаются — остальные центрируются.
func _layout_slots(me_first: bool) -> void:
	var seq: Array = []   # [{big:bool, i:int}] — чипы в визуальном порядке
	for i in Consts.ORDER_SLOTS:
		var mine := {"big": true, "i": i}
		var opp := {"big": false, "i": i}
		if me_first:
			if i != _locked_slot: seq.append(mine)
			if i != _opp_locked_slot: seq.append(opp)
		else:
			if i != _opp_locked_slot: seq.append(opp)
			if i != _locked_slot: seq.append(mine)
	# отсутствующие чипы скрываем, чтобы не ловили клики и не занимали место
	if _locked_slot >= 0:
		_slot_chips[_locked_slot].visible = false
		_slot_heroicons[_locked_slot].visible = false
	if _opp_locked_slot >= 0:
		_opp_chips[_opp_locked_slot].visible = false
	var total := (seq.size() - 1) * SLOT_GAP
	for s in seq:
		total += SLOT_BIG if s.big else SLOT_SMALL
	var x := int((PANEL_W - total) / 2)
	for s in seq:
		x = (_place_big(s.i, x) if s.big else _place_small(s.i, x)) + SLOT_GAP


func _place_big(i: int, x: int) -> int:
	_slot_chips[i].position = Vector2(x, SLOTS_Y)
	_slot_heroicons[i].position = Vector2(x + (SLOT_BIG - HEROICON) / 2.0, HEROICON_Y)
	return x + SLOT_BIG


func _place_small(i: int, x: int) -> int:
	_opp_chips[i].position = Vector2(x, SLOTS_Y + (SLOT_BIG - SLOT_SMALL) / 2.0)
	return x + SLOT_SMALL


func _rebuild_skills() -> void:
	for c in _skills_row.get_children():
		c.queue_free()
	_skill_btns = []
	if _view_id < 0:
		_desc_field.text = ""   # герой не выбран → ряд пуст (и «нет действия» скрыта)
		return
	var u := state.get_unit(_view_id)
	var is_own := u.owner == player and u.alive
	# Ход отдельной кнопкой не выводим — он активируется кликом по не ходившему юниту.
	# ABILITY4 — бонусный 4-й слот (модификатор сложности «против ИИ»), есть не у всех бойцов.
	var actions := [Consts.Action.ATTACK, Consts.Action.ABILITY1, Consts.Action.ABILITY2, Consts.Action.ABILITY3]
	if u.skills.size() > Consts.SKILLS_PER_HERO:
		actions.append(Consts.Action.ABILITY4)
	# 6 кнопок (4 умения + атака + «нет действия») чуть теснее в ряду, чем обычные 5, чтобы уместиться.
	_skills_row.add_theme_constant_override("separation", 8 if actions.size() <= 4 else 4)
	for act in actions:
		var ad := HeroDefs.for_action(u.hero_type, act, u.skills, u.mana_discount, u.dmg_bonus)
		var sb := SkillButton.new()
		sb.setup(Icons.action(u.hero_type, act, u.skills), ad.mana, not (is_own and _skill_usable(u, act)))
		sb.hovered.connect(_show_desc.bind(u.hero_type, act, u.skills, u.mana_discount, u.dmg_bonus))
		sb.pressed.connect(_arm.bind(act))
		_skills_row.add_child(sb)
		_skill_btns.append(sb)
	# «Нет действия» — последней, показывается только когда герой выбран
	var nb := SkillButton.new()
	nb.setup(Icons.cancel(), 0, false)
	nb.hovered.connect(_show_desc_noaction)
	nb.pressed.connect(_pass_slot)
	_skills_row.add_child(nb)


func _show_desc(hero_type: int, action: int, skills: Array = [], discounts: Dictionary = {}, dmg_bonuses: Dictionary = {}) -> void:
	var ad := HeroDefs.for_action(hero_type, action, skills, discounts, dmg_bonuses)
	var lines: Array = ["[b]%s[/b]" % ad.name]
	if ad.mana > 0:
		lines.append("Мана: %d" % ad.mana)
	if ad.slot_gate.size() > 0:
		lines.append("Слоты: %s" % str(_gate_human(ad.slot_gate)))
	lines.append(ad.desc)
	_desc_field.text = "\n".join(lines)


func _show_desc_noaction() -> void:
	_desc_field.text = "[b]Нет действия[/b]\nЗанять слот пустышкой.\nСоперник не увидит, что этот слот пуст."


# ------------------------------------------------------------- взаимодействие

func _on_cell_clicked(cell: Vector2i) -> void:
	# 1) есть невыполненное нацеливание и клик по кандидату → подтвердить
	if _pending_hero >= 0 and _pending_action != Consts.Action.EMPTY:
		var pu := state.get_unit(_pending_hero)
		var origin := _origin_for(_pending_hero, _active)
		var cands := Targeting.candidates(state, pu, _pending_action, origin, _planned_occupancy())
		# Отладка: с включённой настройкой любая клетка на доске — допустимая цель
		var free: bool = Settings.allow_impossible_targets and state.board.in_bounds(cell)
		if _pending_skill() == Consts.Skill.MINEFIELD:
			if _pick_mine(cell, cands, free):
				return
		elif cell in cands or free:
			_commit(cell)
			return
	# 2) выбор юнита (свой или чужой) для просмотра скиллов
	var unit := state.unit_at(cell)
	if unit != null:
		_select_view(unit.id)


func _select_view(id: int) -> void:
	_view_id = id
	board_view.set_selected_unit(id)   # подсветить выбранного героя белым
	_clear_pending()
	_refresh()
	# клик по СВОЕМУ не ходившему юниту сразу активирует ход
	var u := state.get_unit(id)
	if u.owner == player and u.alive and not _has_moved(id):
		_arm(Consts.Action.MOVE)


func _arm(action: int) -> void:
	if _view_id < 0:
		return
	var u := state.get_unit(_view_id)
	if u.owner != player or not u.alive or not _skill_usable(u, action):
		return
	_show_desc(u.hero_type, action, u.skills, u.mana_discount, u.dmg_bonus)
	if _needs_target(u, action):
		_pending_hero = _view_id
		_pending_action = action
		_pending_cells = []
		var origin := _origin_for(_view_id, _active)
		board_view.set_highlights(Targeting.candidates(state, u, action, origin, _planned_occupancy()))
	else:
		# способность без цели — сразу в активный слот
		_write_slot(_active, _view_id, action, Vector2i(-1, -1), [])
		_advance_active()
		_clear_pending()
		_refresh()


func _write_slot(i: int, hero: int, action: int, target: Vector2i, path: Array) -> void:
	slot_hero[i] = hero
	slot_action[i] = action
	slot_target[i] = target
	slot_path[i] = path
	slot_cells[i] = []   # обычный слот — не мультиклеточный


# Минное поле: копим клетки по одной. Возвращает true, если клик обработан нацеливанием
# (клетка-кандидат выбрана или проигнорирована); false — клетка не кандидат, пусть отработает выбор юнита.
func _pick_mine(cell: Vector2i, cands: Array, free: bool = false) -> bool:
	var remaining := _minus(cands, _pending_cells)
	var ok: bool = cell in remaining
	if not ok and free and state.board.in_bounds(cell) and not (cell in _pending_cells):
		ok = true   # отладка: любая клетка вне уже выбранных
	if not ok:
		return false
	_pending_cells.append(cell)
	remaining = _minus(cands, _pending_cells)
	# в отладочном режиме не завершаем набор досрочно (свободных клеток ещё много)
	if _pending_cells.size() >= Consts.MINEFIELD_COUNT or (not free and remaining.is_empty()):
		_commit_minefield()
	else:
		board_view.set_highlights(remaining)
		_update_markers()   # показать уже поставленные мины как метки
	return true


func _commit_minefield() -> void:
	slot_hero[_active] = _pending_hero
	slot_action[_active] = _pending_action
	slot_target[_active] = _pending_cells[0]   # первая мина — «цель» слота (метка/проверка «есть цель»)
	slot_path[_active] = []
	slot_cells[_active] = _pending_cells.duplicate()
	_advance_active()
	_clear_pending()
	_refresh()


func _minus(cells: Array, picked: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in cells:
		if not (c in picked):
			out.append(c)
	return out


func _commit(cell: Vector2i) -> void:
	var path: Array = []
	var origin := _origin_for(_pending_hero, _active)
	if _pending_action == Consts.Action.MOVE:
		# дальность хода = move_range() (учёт «Лёгкость»/«Замедление»): та же, что в подсветке кандидатов,
		# иначе цель дальше MOVE_RANGE подсвечена, но путь к ней не находится → пустой ход
		var mr := state.get_unit(_pending_hero).move_range()
		path = Targeting.move_paths(state, origin, _pending_hero, _planned_occupancy(), mr).get(cell, [])
		if path.is_empty() and Settings.allow_impossible_targets and cell != origin:
			path = _impossible_move_path(origin, cell, mr)
	elif _is_path_skill(_pending_skill()):
		# Отступление/Сходить — путь, как ход, но своей дальностью
		var pr := _path_skill_range(_pending_skill())
		path = Targeting.move_paths(state, origin, _pending_hero, _planned_occupancy(), pr).get(cell, [])
		if path.is_empty() and Settings.allow_impossible_targets and cell != origin:
			path = _impossible_move_path(origin, cell, pr)
	_write_slot(_active, _pending_hero, _pending_action, cell, path)
	_advance_active()
	_clear_pending()
	_refresh()


func _clear_pending() -> void:
	_pending_hero = -1
	_pending_action = Consts.Action.EMPTY
	_pending_cells = []
	_hover_route = []
	board_view.clear_highlights()


# ------------------------------------------------------------- маршруты и ручная прокладка

# Свой живой герой на клетке (кого можно тащить), иначе -1
func _own_movable_at(cell: Vector2i) -> int:
	var u := state.unit_at(cell)
	if u != null and u.owner == player and u.alive:
		return u.id
	return -1


# Начали тащить свой токен → выделяем героя и переходим в режим ручной прокладки хода.
func _on_drag_started(cell: Vector2i) -> void:
	var id := _own_movable_at(cell)
	if id < 0:
		return
	_clear_pending()
	_view_id = id
	board_view.set_selected_unit(id)
	_drag_id = id
	_drag_path = []
	var origin := _origin_for(id, _active)
	board_view.set_highlights(Targeting.candidates(state, state.get_unit(id), Consts.Action.MOVE, origin, _planned_occupancy()))
	_refresh()


# Курсор во время перетаскивания: наращиваем/укорачиваем маршрут по правилам drag_step.
func _on_drag_updated(cell: Vector2i) -> void:
	if _drag_id < 0:
		return
	var origin := _origin_for(_drag_id, _active)
	var mr: int = state.get_unit(_drag_id).move_range()
	_drag_path = Targeting.drag_step(state, origin, _drag_id, _planned_occupancy(), mr, _drag_path, cell)
	_update_routes()


# Отпустили токен: непустой маршрут → фиксируем ход в активный слот.
func _on_drag_ended() -> void:
	if _drag_id < 0:
		return
	var id := _drag_id
	var path: Array = _drag_path
	_drag_id = -1
	_drag_path = []
	if path.size() > 0:
		_write_slot(_active, id, Consts.Action.MOVE, path[path.size() - 1], path.duplicate())
		_advance_active()
	_clear_pending()
	_refresh()


# Наведение (без нажатия) при взведённом ходе → превью маршрута к клетке под курсором.
func _on_cell_hovered(cell: Vector2i) -> void:
	if _pending_hero >= 0 and _pending_action == Consts.Action.MOVE:
		var origin := _origin_for(_pending_hero, _active)
		var mr: int = state.get_unit(_pending_hero).move_range()
		var paths := Targeting.move_paths(state, origin, _pending_hero, _planned_occupancy(), mr)
		_hover_route = paths.get(cell, [])
		_update_routes()
	elif not _hover_route.is_empty():
		_hover_route = []
		_update_routes()


# Собрать маршруты для отрисовки: все запланированные ходы + активное превью (перетаскивание/наведение).
func _update_routes() -> void:
	var rs: Array = []
	for i in Consts.ORDER_SLOTS:
		if slot_hero[i] >= 0 and slot_action[i] == Consts.Action.MOVE and slot_path[i].size() > 0:
			rs.append({"origin": _origin_for(slot_hero[i], i), "cells": slot_path[i]})
	if _drag_id >= 0 and _drag_path.size() > 0:
		rs.append({"origin": _origin_for(_drag_id, _active), "cells": _drag_path})
	elif _pending_hero >= 0 and not _hover_route.is_empty():
		rs.append({"origin": _origin_for(_pending_hero, _active), "cells": _hover_route})
	board_view.set_routes(rs)


func _has_moved(hero_id: int) -> bool:
	for i in Consts.ORDER_SLOTS:
		if slot_hero[i] == hero_id and slot_action[i] == Consts.Action.MOVE:
			return true
	return false


func _on_my_slot_pressed(i: int) -> void:
	if i == _locked_slot:
		return   # слот недоступен этот раунд (второй игрок)
	_active = i
	_err_lbl.text = ""
	_clear_pending()
	if slot_hero[i] >= 0:
		# занятый слот → активировать героя этого слота (как клик по нему), можно переиграть
		_view_id = slot_hero[i]
		board_view.set_selected_unit(_view_id)
		_refresh()
		var u := state.get_unit(_view_id)
		if u.owner == player and u.alive and not _has_moved_except(u.id, i):
			_arm(Consts.Action.MOVE)
	else:
		_refresh()   # пустой/пас-слот → просто сменить активный, выбор героя не трогаем


# «Нет действия» — занять активный слот пустышкой (в приказ уходит как пустой)
func _pass_slot() -> void:
	slot_hero[_active] = -1
	slot_action[_active] = Consts.Action.PASS
	slot_target[_active] = Vector2i(-1, -1)
	slot_path[_active] = []
	slot_cells[_active] = []
	_clear_pending()
	_advance_active()
	_refresh()


func _has_moved_except(hero_id: int, except_slot: int) -> bool:
	for i in Consts.ORDER_SLOTS:
		if i != except_slot and slot_hero[i] == hero_id and slot_action[i] == Consts.Action.MOVE:
			return true
	return false


func _advance_active() -> void:
	for i in Consts.ORDER_SLOTS:
		if i != _locked_slot and slot_action[i] == Consts.Action.EMPTY:
			_active = i
			return
	# все доступные заняты -> встать на последний доступный (не заблокированный)
	for i in range(Consts.ORDER_SLOTS - 1, -1, -1):
		if i != _locked_slot:
			_active = i
			return


# ------------------------------------------------------------- обновление вида

func _refresh() -> void:
	_rebuild_skills()
	_update_slots()
	_update_markers()
	_update_ghosts()
	_update_routes()


func _update_slots() -> void:
	for i in Consts.ORDER_SLOTS:
		if i == _locked_slot:
			continue   # слот отсутствует у второго игрока
		var chip: Button = _slot_chips[i]
		chip.icon = null
		chip.text = ""
		if slot_action[i] == Consts.Action.PASS:
			chip.icon = Icons.cancel()
			chip.add_theme_font_size_override("font_size", 20)
		elif slot_hero[i] >= 0 and slot_action[i] != Consts.Action.EMPTY:
			var u := state.get_unit(slot_hero[i])
			var tex := Icons.action(u.hero_type, slot_action[i], u.skills)
			if tex != null:
				chip.icon = tex
				chip.add_theme_font_size_override("font_size", 20)
			else:
				chip.text = "Ход"
				chip.add_theme_font_size_override("font_size", 14)
		else:
			chip.text = str(i + 1)
			chip.add_theme_font_size_override("font_size", 20)   # фикс: не оставлять мелкий шрифт после «Ход»
		chip.modulate = Color(1, 1, 0.55) if i == _active else Color(1, 1, 1)
		# иконка героя под слотом (кто выполняет действие)
		if slot_hero[i] >= 0 and slot_action[i] != Consts.Action.EMPTY:
			_slot_heroicons[i].texture = Icons.hero(state.get_unit(slot_hero[i]).hero_type)
		else:
			_slot_heroicons[i].texture = null
	# слоты соперника (индикация: тёмный = запланирован); отсутствующий слот пропускаем
	for i in Consts.ORDER_SLOTS:
		if i == _opp_locked_slot:
			continue
		_set_opp_color(i, COL_OPP_FILLED if _opp_filled[i] else COL_OPP_EMPTY)
	_emit_progress()


# Индикация соперника: какие его слоты заполнены (приходит по сети / из hotseat-приказов)
func set_opponent_progress(filled: Array) -> void:
	_opp_filled = filled.duplicate()
	if _opp_chips.size() == Consts.ORDER_SLOTS:
		for i in Consts.ORDER_SLOTS:
			_set_opp_color(i, COL_OPP_FILLED if _opp_filled[i] else COL_OPP_EMPTY)


# Перекрасить круглый слот-индикатор соперника (Panel со StyleBoxFlat, а не ColorRect).
func _set_opp_color(i: int, c: Color) -> void:
	var sb: StyleBoxFlat = _opp_chips[i].get_theme_stylebox("panel")
	if sb != null:
		sb.bg_color = c


# Сообщить наружу, какие МОИ слоты заполнены (для отправки сопернику)
func _emit_progress() -> void:
	var filled: Array = []
	for i in Consts.ORDER_SLOTS:
		filled.append(slot_action[i] != Consts.Action.EMPTY)   # PASS тоже «занят»
	if filled != _last_progress:
		_last_progress = filled
		progress_changed.emit(filled)


func _update_markers() -> void:
	var ms: Array = []
	for i in Consts.ORDER_SLOTS:
		if slot_hero[i] < 0 or slot_action[i] == Consts.Action.EMPTY or slot_action[i] == Consts.Action.MOVE:
			continue
		var u := state.get_unit(slot_hero[i])
		# Минное поле — по метке на КАЖДОЙ выбранной клетке
		if _slot_skill(i) == Consts.Skill.MINEFIELD:
			for c in slot_cells[i]:
				ms.append({"cell": c, "hero_type": u.hero_type, "action": slot_action[i],
						"owner": player, "skills": u.skills})
			continue
		var cell: Vector2i
		if _needs_target(u, slot_action[i]):
			if slot_target[i].x < 0:
				continue
			cell = slot_target[i]
		else:
			cell = _origin_for(slot_hero[i], i)   # скилл без цели — метка на кастере
		ms.append({"cell": cell, "hero_type": u.hero_type, "action": slot_action[i],
				"owner": player, "skills": u.skills})
	# Превью текущего нацеливания Минного поля: уже накопленные, но ещё не подтверждённые мины
	if _pending_hero >= 0 and _pending_skill() == Consts.Skill.MINEFIELD:
		var pu := state.get_unit(_pending_hero)
		for c in _pending_cells:
			ms.append({"cell": c, "hero_type": pu.hero_type, "action": _pending_action,
					"owner": player, "skills": pu.skills})
	board_view.set_markers(ms)


# ------------------------------------------------------------- вспомогательное

func _skill_usable(u: Unit, action: int) -> bool:
	# один и тот же приказ нельзя занять дважды за раунд — теперь включая Ход
	if _action_used(u.id, action, _active):
		return false
	if action == Consts.Action.MOVE:
		return true
	if action == Consts.Action.ATTACK:
		return true
	var ad := HeroDefs.for_action(u.hero_type, action, u.skills, u.mana_discount)
	if ad.passive:
		return false   # пассивку нельзя взвести — она работает сама
	if ad.slot_gate.size() > 0 and not (_active in ad.slot_gate):
		return false
	return u.mana - _reserved_for(u.id, _active) >= ad.mana


# Уже занят ли этим действием другой слот того же героя
func _action_used(hero_id: int, action: int, exclude_slot: int) -> bool:
	for i in Consts.ORDER_SLOTS:
		if i == exclude_slot:
			continue
		if slot_hero[i] == hero_id and slot_action[i] == action:
			return true
	return false


# Зарезервированная мана героя по слотам (кроме указанного)
func _reserved_for(hero_id: int, exclude_slot: int) -> int:
	var r := 0
	for i in Consts.ORDER_SLOTS:
		if i == exclude_slot or slot_hero[i] != hero_id:
			continue
		var u := state.get_unit(hero_id)
		r += HeroDefs.for_action(u.hero_type, slot_action[i], u.skills, u.mana_discount).mana
	return r


func _needs_target(unit: Unit, action: int) -> bool:
	if unit == null or action == Consts.Action.EMPTY:
		return false
	return HeroDefs.for_action(unit.hero_type, action, unit.skills, unit.mana_discount).target != HeroDefs.Target.NONE


# Маршрут в клетку, недостижимую при обычном планировании (настройка «невозможные цели»).
# Смысл настройки — запланировать ход, который станет возможным, если противник к разрешению
# сместит своего героя. Поэтому сначала прокладываем путь, считая ВРАЖЕСКИЕ токены прозрачными
# (стены и свои запланированные позиции по-прежнему блокируют): получится тот самый маршрут,
# который откроется после ухода врага. Резолвер всё равно проверит каждый шаг заново и упрётся,
# если враг не сдвинулся. Совсем недостижимую клетку (за стеной/за пределом дальности) отдаём
# прямым L-жестом — приказ запланируется, но при разрешении честно упрётся.
func _impossible_move_path(origin: Vector2i, cell: Vector2i, rng: int) -> Array:
	var p: Array = Targeting.move_paths(state, origin, _pending_hero, _occupancy_ignoring_enemies(), rng).get(cell, [])
	if not p.is_empty():
		return p
	return _direct_path(origin, cell)


# Как _planned_occupancy(), но без вражеских юнитов: они к разрешению могут сместиться.
func _occupancy_ignoring_enemies() -> Dictionary:
	var occ := {}
	for u in state.units_of(player):
		if u.alive:
			occ[_planned_final(u.id)] = {"id": u.id, "owner": u.owner}
	return occ


# Прямой L-образный путь клетками (без origin) в cell: сперва по X, затем по Y.
# Крайний случай для по-настоящему недостижимой клетки (стена/за пределом дальности).
func _direct_path(origin: Vector2i, cell: Vector2i) -> Array:
	var out: Array = []
	var cur := origin
	while cur.x != cell.x:
		cur.x += signi(cell.x - cur.x)
		out.append(cur)
	while cur.y != cell.y:
		cur.y += signi(cell.y - cur.y)
		out.append(cur)
	return out


# Скиллы, несущие относительный путь (как ход): Отступление и Сходить
func _is_path_skill(skill: int) -> bool:
	return skill == Consts.Skill.RETREAT or skill == Consts.Skill.STEP


func _path_skill_range(skill: int) -> int:
	return Consts.RETREAT_RANGE if skill == Consts.Skill.RETREAT else Consts.STEP_RANGE


# Скилл за текущим нацеливаемым действием (или за действием в слоте i)
func _pending_skill() -> int:
	if _pending_hero < 0:
		return -1
	var u := state.get_unit(_pending_hero)
	return HeroDefs.skill_of_action(u.hero_type, _pending_action, u.skills)


func _slot_skill(i: int) -> int:
	if slot_hero[i] < 0:
		return -1
	var u := state.get_unit(slot_hero[i])
	return HeroDefs.skill_of_action(u.hero_type, slot_action[i], u.skills)


func _planned_final(hero_id: int) -> Vector2i:
	return _origin_for(hero_id, Consts.ORDER_SLOTS)


func _planned_occupancy() -> Dictionary:
	var occ := {}
	for u in state.living_units():
		if u.owner != player:
			occ[u.cell] = {"id": u.id, "owner": u.owner}
	for u in state.units_of(player):
		if u.alive:
			occ[_planned_final(u.id)] = {"id": u.id, "owner": u.owner}
	return occ


func _update_ghosts() -> void:
	var gs: Array = []
	for u in state.units_of(player):
		if not u.alive:
			continue
		var pos := _planned_final(u.id)
		if pos != u.cell:
			gs.append({"cell": pos, "owner": u.owner, "type": u.hero_type, "hp": u.hp, "mana": u.mana})
	board_view.set_ghosts(gs)


# Предсказанная позиция героя после слотов [0, upto_slot). Учитывает скиллы, которые
# двигают самого героя — по id скилла, а не по индексу слота (кит настраивается в «Коллекции»).
func _origin_for(hero_id: int, upto_slot: int) -> Vector2i:
	var u := state.get_unit(hero_id)
	var pos: Vector2i = u.cell
	for j in upto_slot:
		if slot_hero[j] != hero_id:
			continue
		var act: int = slot_action[j]
		if act == Consts.Action.MOVE:
			if slot_path[j].size() > 0:
				pos = slot_path[j][slot_path[j].size() - 1]
			continue
		if slot_target[j].x < 0:
			continue
		match HeroDefs.skill_of_action(u.hero_type, act, u.skills):
			Consts.Skill.JUMP:        # приземление ЗА перепрыгнутым
				var dl: Vector2i = slot_target[j] - pos
				pos = slot_target[j] + Vector2i(signi(dl.x), signi(dl.y))
			Consts.Skill.DASH:        # в целевую клетку
				pos = slot_target[j]
			Consts.Skill.ONSLAUGHT:   # занимает клетку отброшенного врага
				pos = slot_target[j]
			Consts.Skill.RETREAT, Consts.Skill.STEP:   # путь-скилл: уходит в конец пути
				pos = slot_target[j]
	return pos


# ------------------------------------------------------------- готово

func _on_done() -> void:
	var reserved := {}
	var seen := {}   # "hero:action" — контроль «один приказ не дважды» (включая Ход)
	for i in Consts.ORDER_SLOTS:
		var hid: int = slot_hero[i]
		if hid < 0 or slot_action[i] == Consts.Action.EMPTY:
			continue
		var u := state.get_unit(hid)
		var ad := HeroDefs.for_action(u.hero_type, slot_action[i], u.skills, u.mana_discount)
		var key := "%d:%d" % [hid, slot_action[i]]   # Ход тоже в контроле дублей
		if seen.has(key):
			_err_lbl.text = "%s: «%s» нельзя занять дважды за раунд" % [u.full_name(), ad.name]
			return
		seen[key] = true
		if ad.slot_gate.size() > 0 and not (i in ad.slot_gate):
			_err_lbl.text = "%s: %s только в слотах %s" % [u.full_name(), ad.name, str(_gate_human(ad.slot_gate))]
			return
		if ad.target != HeroDefs.Target.NONE and slot_target[i].x < 0:
			_err_lbl.text = "Слот %d: не выбрана цель" % (i + 1)
			return
		reserved[hid] = reserved.get(hid, 0) + ad.mana
	for hid in reserved:
		var u := state.get_unit(hid)
		if reserved[hid] > u.mana:
			_err_lbl.text = "%s: не хватает маны (%d > %d)" % [u.full_name(), reserved[hid], u.mana]
			return
	var orders: Array = []
	for i in Consts.ORDER_SLOTS:
		if slot_hero[i] < 0 or slot_action[i] == Consts.Action.EMPTY:
			orders.append(Order.empty())
		elif slot_action[i] == Consts.Action.MOVE:
			# абсолютный путь -> шаги-смещения (относительно запланированной стартовой клетки)
			var steps: Array[Vector2i] = []
			var prev: Vector2i = _origin_for(slot_hero[i], i)
			for c in slot_path[i]:
				steps.append(c - prev)
				prev = c
			orders.append(Order.make_move(slot_hero[i], steps))
		elif _is_path_skill(_slot_skill(i)):
			# Отступление/Сходить — способность, несущая относительный путь (как ход)
			var steps: Array[Vector2i] = []
			var prev: Vector2i = _origin_for(slot_hero[i], i)
			for c in slot_path[i]:
				steps.append(c - prev)
				prev = c
			var o := Order.new(slot_hero[i], slot_action[i])
			o.path = steps
			orders.append(o)
		elif _slot_skill(i) == Consts.Skill.MINEFIELD:
			# Минное поле — офсеты выбранных клеток от планируемой позиции (как «жест», устойчивый к сдвигу)
			var origin: Vector2i = _origin_for(slot_hero[i], i)
			var offs: Array[Vector2i] = []
			for c in slot_cells[i]:
				offs.append(c - origin)
			var o := Order.new(slot_hero[i], slot_action[i])
			o.relative = true
			o.path = offs
			o.offset = offs[0]                  # первая мина — «первичный» офсет (для маркера/дезориентации)
			o.target = slot_cells[i][0]
			orders.append(o)
		else:
			# нон-таргет: смещение цели от планируемой позиции; в резолве применится от ТЕКУЩЕЙ
			var has_t: bool = slot_target[i].x >= 0
			var off: Vector2i = (slot_target[i] - _origin_for(slot_hero[i], i)) if has_t else Vector2i.ZERO
			orders.append(Order.make(slot_hero[i], slot_action[i], slot_target[i], off, has_t))
	# Страховка: всё, что UI считает легальным, обязано пережить серверную санитизацию.
	# Если правила разойдутся, онлайн-игрок иначе молча потеряет действие — лучше ошибка здесь.
	# В отладочном режиме «невозможных целей» проверку пропускаем намеренно (локально приказ
	# отыграется как есть; в онлайне его всё равно отсеет сервер).
	if not Settings.allow_impossible_targets:
		var checked := OrderValidator.sanitize(state, orders, player)
		for i in Consts.ORDER_SLOTS:
			if not orders[i].is_empty() and checked[i].is_empty():
				_err_lbl.text = "Слот %d: приказ отклонён проверкой правил" % (i + 1)
				return
	board_view.clear_highlights()
	board_view.set_markers([])
	board_view.set_routes([])
	board_view.set_selected_unit(-1)
	orders_ready.emit(orders)


func _gate_human(gate: Array) -> Array:
	var out: Array = []
	for g in gate:
		out.append(g + 1)
	return out
