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

const COL_OPP_EMPTY := Color(0.22, 0.25, 0.31)
const COL_OPP_FILLED := Color(0.07, 0.08, 0.11)

# Жёстко заданные позиции (элементы не смещаются по вертикали при смене содержимого)
const SLOT_BIG := 60
const SLOT_SMALL := 28
const SLOT_GAP := 6
const HEROICON := 34
const PANEL_W := Layout.PANEL_W
const PANEL_H := Layout.PANEL_H
const SKILLS_Y := 4
const SKILLS_H := 104
const DESC_Y := 116
# слоты действий и «Готово» — прижаты к низу экрана
const DONE_Y := PANEL_H - 56
const HEROICON_Y := DONE_Y - 8 - HEROICON
const SLOTS_Y := HEROICON_Y - 4 - SLOT_BIG
const ERR_Y := SLOTS_Y - 26
const DESC_H := ERR_Y - DESC_Y - 8   # описание занимает всё место между скиллами и слотами

var state: MatchState
var player: int
var board_view: BoardView

var slot_hero: Array = [-1, -1, -1, -1]
var slot_action: Array = [Consts.Action.EMPTY, Consts.Action.EMPTY, Consts.Action.EMPTY, Consts.Action.EMPTY]
var slot_target: Array = [Vector2i(-1, -1), Vector2i(-1, -1), Vector2i(-1, -1), Vector2i(-1, -1)]
var slot_path: Array = [[], [], [], []]

var _active: int = 0
var _view_id: int = -1     # чей китбар показан (может быть враг)
var _pending_action: int = Consts.Action.EMPTY   # выбранное, но не подтверждённое действие
var _pending_hero: int = -1
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
	# Второй игрок раунда пропускает последний слот (чередование без двойного хода)
	var me_first := state.first_player_this_round() == player
	_locked_slot = -1 if me_first else Consts.ORDER_SLOTS - 1
	_opp_locked_slot = Consts.ORDER_SLOTS - 1 if me_first else -1
	_active = 0
	_view_id = -1
	board_view.set_selected_unit(-1)
	if not board_view.cell_clicked.is_connected(_on_cell_clicked):
		board_view.cell_clicked.connect(_on_cell_clicked)
	_build_ui()
	_refresh()


# ------------------------------------------------------------- построение UI

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()
	_slot_chips = []
	_slot_heroicons = []
	_opp_chips = []

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
		chip.pressed.connect(_on_my_slot_pressed.bind(i))
		add_child(chip)
		_slot_chips.append(chip)
		var hi := TextureRect.new()
		hi.size = Vector2(HEROICON, HEROICON)
		hi.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hi.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		add_child(hi)
		_slot_heroicons.append(hi)
		var opp := ColorRect.new()
		opp.size = Vector2(SLOT_SMALL, SLOT_SMALL)
		opp.color = COL_OPP_EMPTY
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
	# Ход отдельной кнопкой не выводим — он активируется кликом по не ходившему юниту
	var actions := [Consts.Action.ATTACK, Consts.Action.ABILITY1, Consts.Action.ABILITY2, Consts.Action.ABILITY3]
	for act in actions:
		var ad := HeroDefs.for_action(u.hero_type, act, u.skills)
		var sb := SkillButton.new()
		sb.setup(Icons.action(u.hero_type, act, u.skills), ad.mana, not (is_own and _skill_usable(u, act)))
		sb.hovered.connect(_show_desc.bind(u.hero_type, act, u.skills))
		sb.pressed.connect(_arm.bind(act))
		_skills_row.add_child(sb)
		_skill_btns.append(sb)
	# «Нет действия» — последней, показывается только когда герой выбран
	var nb := SkillButton.new()
	nb.setup(Icons.cancel(), 0, false)
	nb.hovered.connect(_show_desc_noaction)
	nb.pressed.connect(_pass_slot)
	_skills_row.add_child(nb)


func _show_desc(hero_type: int, action: int, skills: Array = []) -> void:
	var ad := HeroDefs.for_action(hero_type, action, skills)
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
		if cell in cands:
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
	_show_desc(u.hero_type, action, u.skills)
	if _needs_target(u, action):
		_pending_hero = _view_id
		_pending_action = action
		var origin := _origin_for(_view_id, _active)
		board_view.set_highlights(Targeting.candidates(state, u, action, origin, _planned_occupancy()))
	else:
		# способность без цели — сразу в активный слот
		_write_slot(_active, _view_id, action, Vector2i(-1, -1), [])
		_advance_active()
		_clear_pending()
		_refresh()


func _commit(cell: Vector2i) -> void:
	var path: Array = []
	var origin := _origin_for(_pending_hero, _active)
	if _pending_action == Consts.Action.MOVE:
		path = Targeting.move_paths(state, origin, _pending_hero, _planned_occupancy()).get(cell, [])
	elif _is_path_skill(_pending_skill()):
		# Отступление/Сходить — путь, как ход, но своей дальностью
		path = Targeting.move_paths(state, origin, _pending_hero, _planned_occupancy(), _path_skill_range(_pending_skill())).get(cell, [])
	_write_slot(_active, _pending_hero, _pending_action, cell, path)
	_advance_active()
	_clear_pending()
	_refresh()


func _write_slot(i: int, hero: int, action: int, target: Vector2i, path: Array) -> void:
	slot_hero[i] = hero
	slot_action[i] = action
	slot_target[i] = target
	slot_path[i] = path


func _clear_pending() -> void:
	_pending_hero = -1
	_pending_action = Consts.Action.EMPTY
	board_view.clear_highlights()


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
		_opp_chips[i].color = COL_OPP_FILLED if _opp_filled[i] else COL_OPP_EMPTY
	_emit_progress()


# Индикация соперника: какие его слоты заполнены (приходит по сети / из hotseat-приказов)
func set_opponent_progress(filled: Array) -> void:
	_opp_filled = filled.duplicate()
	if _opp_chips.size() == Consts.ORDER_SLOTS:
		for i in Consts.ORDER_SLOTS:
			_opp_chips[i].color = COL_OPP_FILLED if _opp_filled[i] else COL_OPP_EMPTY


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
		var cell: Vector2i
		if _needs_target(u, slot_action[i]):
			if slot_target[i].x < 0:
				continue
			cell = slot_target[i]
		else:
			cell = _origin_for(slot_hero[i], i)   # скилл без цели — метка на кастере
		ms.append({"cell": cell, "hero_type": u.hero_type, "action": slot_action[i],
				"owner": player, "skills": u.skills})
	board_view.set_markers(ms)


# ------------------------------------------------------------- вспомогательное

func _skill_usable(u: Unit, action: int) -> bool:
	if action == Consts.Action.MOVE:
		return true
	# один и тот же скилл нельзя применить дважды за раунд (ходить можно многократно)
	if _action_used(u.id, action, _active):
		return false
	if action == Consts.Action.ATTACK:
		return true
	var ad := HeroDefs.for_action(u.hero_type, action, u.skills)
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
		r += HeroDefs.for_action(u.hero_type, slot_action[i], u.skills).mana
	return r


func _needs_target(unit: Unit, action: int) -> bool:
	if unit == null or action == Consts.Action.EMPTY:
		return false
	return HeroDefs.for_action(unit.hero_type, action, unit.skills).target != HeroDefs.Target.NONE


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
	var seen := {}   # "hero:action" — контроль «один скилл не дважды»
	for i in Consts.ORDER_SLOTS:
		var hid: int = slot_hero[i]
		if hid < 0 or slot_action[i] == Consts.Action.EMPTY:
			continue
		var u := state.get_unit(hid)
		if slot_action[i] != Consts.Action.MOVE:
			var key := "%d:%d" % [hid, slot_action[i]]
			if seen.has(key):
				var nm := HeroDefs.for_action(u.hero_type, slot_action[i], u.skills).name
				_err_lbl.text = "%s: «%s» нельзя применить дважды за раунд" % [u.full_name(), nm]
				return
			seen[key] = true
		var ad := HeroDefs.for_action(u.hero_type, slot_action[i], u.skills)
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
		else:
			# нон-таргет: смещение цели от планируемой позиции; в резолве применится от ТЕКУЩЕЙ
			var has_t: bool = slot_target[i].x >= 0
			var off: Vector2i = (slot_target[i] - _origin_for(slot_hero[i], i)) if has_t else Vector2i.ZERO
			orders.append(Order.make(slot_hero[i], slot_action[i], slot_target[i], off, has_t))
	# Страховка: всё, что UI считает легальным, обязано пережить серверную санитизацию.
	# Если правила разойдутся, онлайн-игрок иначе молча потеряет действие — лучше ошибка здесь.
	var checked := OrderValidator.sanitize(state, orders, player)
	for i in Consts.ORDER_SLOTS:
		if not orders[i].is_empty() and checked[i].is_empty():
			_err_lbl.text = "Слот %d: приказ отклонён проверкой правил" % (i + 1)
			return
	board_view.clear_highlights()
	board_view.set_markers([])
	board_view.set_selected_unit(-1)
	orders_ready.emit(orders)


func _gate_human(gate: Array) -> Array:
	var out: Array = []
	for g in gate:
		out.append(g + 1)
	return out
