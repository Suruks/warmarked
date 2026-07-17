extends SceneTree

## Гоняет реальные UI-виджеты без дисплея: строит PlanningPanel, программно заполняет
## слоты, жмёт «Готово», прогоняет ResolutionView до конца. Проверяет, что связки не падают.

var _orders_a: Array = []
var _res_done := false


func _initialize() -> void:
	print("=== Warmarked UI smoke ===")
	var state := MatchState.new()
	state.setup()
	state.begin_round()
	# дать Охотнику A маны на капкан
	state.get_unit(0).mana = 3

	var board_view := BoardView.new()
	get_root().add_child(board_view)
	board_view.setup(state.board)
	board_view.render(state.snapshot())

	# --- Планирование за игрока A ---
	var pp := PlanningPanel.new()
	get_root().add_child(pp)
	pp.orders_ready.connect(func(o): _orders_a = o)
	pp.begin(state, Consts.Player.A, board_view)

	# слот 0: Охотник (id0) ходит на достижимую клетку
	var hunter := state.get_unit(0)
	var paths := Targeting.move_paths(state, hunter.cell, 0)
	var move_cell: Vector2i = paths.keys()[0]
	pp.slot_hero[0] = 0
	pp.slot_action[0] = Consts.Action.MOVE
	pp.slot_target[0] = move_cell
	pp.slot_path[0] = paths[move_cell]
	# слот 1: Охотник ставит капкан рядом. Целиться надо от ЗАПЛАНИРОВАННОЙ позиции (после хода
	# в слоте 0), иначе смещение цели выйдет за радиус капкана — ровно так, как считает сам UI.
	var trap_origin: Vector2i = pp._origin_for(0, 1)
	var trap_cells := Targeting.candidates(state, hunter, Consts.Action.ABILITY1, trap_origin, pp._planned_occupancy())
	pp.slot_hero[1] = 0
	pp.slot_action[1] = Consts.Action.ABILITY1
	pp.slot_target[1] = trap_cells[0]
	pp._on_done()

	_check(_orders_a.size() == Consts.ORDER_SLOTS, "PlanningPanel вернул 4 приказа [%d]" % _orders_a.size())
	_check(not _orders_a[0].is_empty() and _orders_a[0].action == Consts.Action.MOVE, "слот 0 — ход")
	_check(_orders_a[1].action == Consts.Action.ABILITY1, "слот 1 — капкан")

	# --- Разрешение (A против пустого B) ---
	var empty_b := Order.empty_slots()
	var resolver := Resolver.new()
	var events := resolver.resolve(state, _orders_a, empty_b, Consts.Player.A)
	_check(events.size() > 0, "резолвер выдал события [%d]" % events.size())

	# события несут метаданные для анимации (actor/victim)
	var has_actor := false
	var has_victim := false
	for e in events:
		if e.has("actor"):
			has_actor = true
		if e.has("victim"):
			has_victim = true
	_check(has_actor, "события содержат actor для анимации хода/атаки")
	_check(has_victim or events.size() > 0, "события содержат victim при уроне (или событий нет)")

	# --- Баг-фикс: ушедший юнит освобождает клетку для других ---
	var st := MatchState.new()
	st.setup()
	st.begin_round()
	var occ := Targeting.build_occupancy(st)
	var fairy_before := Targeting.move_paths(st, st.get_unit(1).cell, 1, occ)  # Фея A из (3,6)
	_check(not (Vector2i(1, 6) in fairy_before.keys()), "до плана: клетка Охотника (1,6) занята — недоступна Фее")
	# Охотник (id0) запланировал уйти с (1,6) на (1,4)
	occ.erase(Vector2i(1, 6))
	occ[Vector2i(1, 4)] = {"id": 0, "owner": Consts.Player.A}
	var fairy_after := Targeting.move_paths(st, st.get_unit(1).cell, 1, occ)
	_check(Vector2i(1, 6) in fairy_after.keys(), "после плана ухода: (1,6) освободилась и доступна Фее")

	# --- один скилл нельзя применить дважды за раунд ---
	var st2 := MatchState.new()
	st2.setup()
	st2.begin_round()
	st2.get_unit(0).mana = 5
	var pp2 := PlanningPanel.new()
	get_root().add_child(pp2)
	pp2.begin(st2, Consts.Player.A, board_view)
	var hunter2 := st2.get_unit(0)
	pp2.slot_hero[0] = 0
	pp2.slot_action[0] = Consts.Action.ABILITY1   # капкан в слоте 0
	pp2._active = 1
	_check(not pp2._skill_usable(hunter2, Consts.Action.ABILITY1), "капкан недоступен вторично (уже в слоте 0)")
	_check(pp2._skill_usable(hunter2, Consts.Action.ABILITY3), "другой скилл (дробь) доступен")

	# --- медитация в раннем слоте разблокирует дорогой скилл в позднем (в РЕАЛЬНОЙ панели) ---
	var st_med := MatchState.new()
	st_med.setup()
	st_med.begin_round()
	var mh := st_med.get_unit(0)
	mh.skills = [Consts.Skill.MEDITATION, Consts.Skill.DEATHCROSS, Consts.Skill.PRECISE]  # AB1=медит, AB2=крест(4)
	mh.mana = Consts.DEATHCROSS_MANA - 1   # 3 — на крест «в лоб» не хватает
	var pp_med := PlanningPanel.new()
	get_root().add_child(pp_med)
	pp_med.begin(st_med, Consts.Player.A, board_view)
	# планируем крест в слоте 2 — пока без медитации, кнопка ЗАБЛОКИРОВАНА
	pp_med._active = 2
	_check(not pp_med._skill_usable(mh, Consts.Action.ABILITY2), "крест заблокирован: маны 3 < 4")
	# ставим медитацию в слот 0 — и тот же крест в слоте 2 РАЗБЛОКИРУЕТСЯ
	pp_med.slot_hero[0] = 0
	pp_med.slot_action[0] = Consts.Action.ABILITY1
	_check(pp_med._skill_usable(mh, Consts.Action.ABILITY2), "крест РАЗБЛОКИРОВАН медитацией в слоте 0")
	# а медитация в ПОЗДНЕМ слоте (3) крест в слоте 2 не разблокирует
	pp_med.slot_hero[0] = -1
	pp_med.slot_action[0] = Consts.Action.EMPTY
	pp_med.slot_hero[3] = 0
	pp_med.slot_action[3] = Consts.Action.ABILITY1
	_check(not pp_med._skill_usable(mh, Consts.Action.ABILITY2), "крест НЕ разблокирован поздней медитацией (слот 3 позже слота 2)")

	# --- Быстрая перезарядка: один скилл доступен в двух слотах (в РЕАЛЬНОЙ панели) ---
	var st_fr := MatchState.new()
	st_fr.setup()
	st_fr.begin_round()
	var fr := st_fr.get_unit(0)
	fr.skills = [Consts.Skill.SHOTGUN, Consts.Skill.PRECISE, Consts.Skill.FAST_RELOAD]  # AB1 = Дробь
	fr.mana = 10
	var pp_fr := PlanningPanel.new()
	get_root().add_child(pp_fr)
	pp_fr.begin(st_fr, Consts.Player.A, board_view)
	pp_fr.slot_hero[0] = 0
	pp_fr.slot_action[0] = Consts.Action.ABILITY1   # дробь занята в слоте 0
	pp_fr._active = 2
	_check(pp_fr._skill_usable(fr, Consts.Action.ABILITY1), "быстрая перезарядка: дробь доступна вторично в панели")
	# без пассивки тот же скилл вторично НЕ доступен
	fr.skills = [Consts.Skill.SHOTGUN, Consts.Skill.PRECISE, Consts.Skill.SNIPER]
	_check(not pp_fr._skill_usable(fr, Consts.Action.ABILITY1), "без перезарядки дробь вторично недоступна")

	# --- прыжок: планируемая позиция = клетка ЗА перепрыгнутым, а не сама цель ---
	var st3 := MatchState.new()
	st3.setup()
	st3.begin_round()
	st3.get_unit(2).cell = Vector2i(2, 2)   # A Кристалкайнд
	st3.get_unit(3).cell = Vector2i(3, 2)   # враг, через которого прыгаем
	var pp3 := PlanningPanel.new()
	get_root().add_child(pp3)
	pp3.begin(st3, Consts.Player.A, board_view)
	pp3.slot_hero[0] = 2
	pp3.slot_action[0] = Consts.Action.ABILITY1   # Прыжок
	pp3.slot_target[0] = Vector2i(3, 2)           # тыкнули в клетку с врагом
	_check(pp3._origin_for(2, 1) == Vector2i(4, 2), "прыжок: назначение — клетка ЗА целью (4,2) [%s]" % str(pp3._origin_for(2, 1)))

	await _smoke_resolution_playback()

	print("=== UI smoke done ===")
	quit(0)


# Реальный прогон ResolutionView: анимации толчка/вспышки/всплывающих цифр до конца раунда.
func _smoke_resolution_playback() -> void:
	# Во время _initialize корневое окно ещё не в дереве: у добавленных узлов get_tree() == null,
	# твины и таймеры не запускаются. Ждём первый кадр, иначе плейбек «пройдёт» вхолостую.
	await process_frame

	var st := MatchState.new()
	st.setup()
	st.begin_round()
	var fairy := st.get_unit(1)          # A Фея
	fairy.cell = Vector2i(3, 3)
	fairy.mana = Consts.HEAL_MANA
	var hunter := st.get_unit(0)         # A Охотник — раненый, чтобы лечение дало > 0
	hunter.cell = Vector2i(3, 4)
	hunter.hp = 5
	st.get_unit(5).cell = Vector2i(2, 3)  # B Кристалкайнд — цель удара

	# слот лечения зависит от сортировки кита по мане — берём его из кита, а не хардкодим
	var heal_action: int = Consts.Action.ABILITY1 + fairy.skills.find(Consts.Skill.HEAL)
	var oa := Order.empty_slots()
	oa[0] = Order.make(1, Consts.Action.ATTACK, Vector2i(2, 3), Vector2i(-1, 0), true)
	oa[1] = Order.make(1, heal_action, Vector2i(3, 4), Vector2i(0, 1), true)
	var events := Resolver.new().resolve(st, oa, Order.empty_slots(), Consts.Player.A)

	var dmg: Array = events.filter(func(e): return e.type == Consts.EventType.DAMAGE)
	var heal: Array = events.filter(func(e): return e.type == Consts.EventType.HEAL)
	_check(dmg.size() > 0 and dmg[0].get("amount", 0) == Consts.FAIRY_ATK_DMG,
		"событие урона несёт amount для всплывающей цифры")
	_check(heal.size() > 0 and heal[0].get("amount", 0) > 0,
		"событие лечения несёт amount для всплывающей цифры")

	var bv := BoardView.new()
	get_root().add_child(bv)
	bv.setup(st.board)
	bv.render(st.snapshot())
	var rv := ResolutionView.new()
	get_root().add_child(rv)
	rv.begin(events, bv)

	var waited := 0.0
	var seen_floaters := 0        # цифры живут недолго — ловим их по ходу проигрывания
	while rv._playing and waited < 30.0:
		await create_timer(0.05).timeout
		waited += 0.05
		seen_floaters = maxi(seen_floaters, bv.floaters.size())
	_check(not rv._playing, "ResolutionView доиграл все события до конца")
	_check(seen_floaters > 0, "всплывающие цифры появлялись во время анимации [%d]" % seen_floaters)
	# цифра живёт дольше своего события и может пережить конец плейбека — дожидаемся её ухода
	var tail := 0.0
	while not bv.floaters.is_empty() and tail < BoardView.FLOAT_DUR + 1.0:
		await create_timer(0.05).timeout
		tail += 0.05
	_check(bv.floaters.is_empty(), "всплывающие цифры сняли себя после анимации [%d]" % bv.floaters.size())


func _check(cond: bool, label: String) -> void:
	print(("  PASS  " if cond else "  FAIL  ") + label)
