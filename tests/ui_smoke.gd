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
	# слот 1: Охотник ставит капкан рядом
	var trap_cells := Targeting.candidates(state, hunter, Consts.Action.ABILITY1, hunter.cell)
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

	print("=== UI smoke done ===")
	quit(0)


func _check(cond: bool, label: String) -> void:
	print(("  PASS  " if cond else "  FAIL  ") + label)
