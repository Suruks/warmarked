extends SceneTree

## Headless-проверки чистой логики резолвера/состояния.
## Запуск:
##   "…\godot.windows.opt.tools.64.exe" --headless --path E:\dev\warmarked --script res://tests/headless_test.gd

var _pass := 0
var _fail := 0


func _initialize() -> void:
	print("=== Warmarked headless tests ===")
	test_interleave_blocks_collision()
	test_trap_immobilize_then_snipe()
	test_snipe_slot_gate()
	test_shotgun_knockback_collision()
	test_shotgun_area_2x2()
	test_shotgun_fixed_direction()
	test_snipe_relative()
	test_kill_scoring()
	test_respawn_at_home_row()
	test_respawn_delay_misses_one_full_round()
	test_control_point_majority()
	test_crystal_no_passive()
	test_immobilize_blocks_next_move()
	test_multi_round_income_and_control()
	test_fairy_shield_ally()
	test_shield_nontarget_and_order()
	test_shield_gates_trap()
	test_bullet_blocked_by_unit()
	test_trap_excludes_occupied_and_graves()
	test_trap_fizzle_on_occupied()
	test_trap_lives_one_round()
	test_relative_move_after_knockback()
	test_ambush_ignores_allies()
	test_allies_do_not_block_movement()
	test_respawn_resets_mana()
	test_validator_move_rules()
	test_validator_target_geometry()
	test_validator_mana_gate_and_double_cast()
	test_validator_rejects_foreign_and_dead()
	print("=== Итог: %d PASS, %d FAIL ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# ---------------------------------------------------------------- helpers

func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  PASS  " + label)
	else:
		_fail += 1
		print("  FAIL  " + label)


func _slots() -> Array:
	return [Order.empty(), Order.empty(), Order.empty(), Order.empty()]


func _fresh() -> MatchState:
	var s := MatchState.new()
	s.setup()
	s.round_num = 1
	# развести всех подальше, чтобы не мешали (перекроем по месту в конкретном тесте)
	return s


func _place(s: MatchState, id: int, cell: Vector2i, hp := -1) -> Unit:
	var u := s.get_unit(id)
	u.cell = cell
	if hp >= 0:
		u.hp = hp
	return u


# ---------------------------------------------------------------- tests

func test_interleave_blocks_collision() -> void:
	# A первым; A и B оба идут на (3,3) → A занимает, B блокируется (нет коллизии)
	var s := _fresh()
	var a := _place(s, 0, Vector2i(3, 4))   # A hunter
	var b := _place(s, 3, Vector2i(3, 2))   # B hunter
	var oa := _slots(); oa[0] = Order.make_move(0, [Vector2i(0, -1)] as Array[Vector2i])  # (3,4)->(3,3)
	var ob := _slots(); ob[0] = Order.make_move(3, [Vector2i(0, 1)] as Array[Vector2i])   # (3,2)->(3,3)
	var r := Resolver.new()
	r.resolve(s, oa, ob, Consts.Player.A)
	_check(a.cell == Vector2i(3, 3), "интерливинг: A занял (3,3)")
	_check(b.cell == Vector2i(3, 2), "интерливинг: B заблокирован, остался на (3,2)")


func test_trap_immobilize_then_snipe() -> void:
	var s := _fresh()
	_place(s, 0, Vector2i(3, 4)).mana = Consts.TRAP_MANA + Consts.SNIPE_MANA   # A hunter
	var b := _place(s, 5, Vector2i(1, 4))            # B crystal (полное HP)
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY1, Vector2i(2, 4))   # капкан
	oa[2] = Order.make(0, Consts.Action.ABILITY2, Vector2i(2, 4))   # снайп (слот 3)
	var ob := _slots()
	ob[0] = Order.make_move(5, [Vector2i(1, 0)] as Array[Vector2i]) # (1,4)->(2,4) входит в капкан
	var r := Resolver.new()
	r.resolve(s, oa, ob, Consts.Player.A)
	var expect := Consts.CRYSTAL_HP - Consts.TRAP_DMG - Consts.SNIPE_DMG
	_check(b.hp == expect, "капкан+снайп по обездвиженному: HP %d [%d]" % [expect, b.hp])
	_check(b.immobilize_pending, "капкан выставил обездвиживание")
	_check(b.cell == Vector2i(2, 4), "жертва на клетке капкана")


func test_snipe_slot_gate() -> void:
	var s := _fresh()
	_place(s, 0, Vector2i(3, 4))
	var b := _place(s, 5, Vector2i(3, 6), 10)
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY2, Vector2i(3, 6))  # снайп в слот 1 → физзл
	var r := Resolver.new()
	r.resolve(s, oa, _slots(), Consts.Player.A)
	_check(b.hp == 10, "гейт снайпа: слот 1 физзлит, урона нет [%d]" % b.hp)


func test_shotgun_knockback_collision() -> void:
	var s := _fresh()
	s.board.obstacles = {}                            # чистое поле для предсказуемости
	_place(s, 0, Vector2i(5, 5)).mana = 3             # A hunter (дробь 3)
	var b := _place(s, 4, Vector2i(6, 6), 12)         # B fairy на диагонали у угла
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY3, Vector2i(6, 6))  # дробь по диагонали
	var r := Resolver.new()
	r.resolve(s, oa, _slots(), Consts.Player.A)
	# дробь + отброс в угол (7,7 вне поля) → столкновение
	var expect := 12 - Consts.SHOTGUN_DMG - Consts.COLLISION_DMG
	_check(b.hp == expect, "дробь+столкновение о край: HP %d [%d]" % [expect, b.hp])


func test_kill_scoring() -> void:
	var s := _fresh()
	_place(s, 1, Vector2i(0, 0))                      # увести A fairy
	_place(s, 0, Vector2i(3, 4)).mana = 2             # A hunter (снайп 2)
	var b := _place(s, 4, Vector2i(3, 2), 5)          # B fairy hp5 (линия (3,4)->(3,2) чиста)
	var oa := _slots()
	oa[2] = Order.make(0, Consts.Action.ABILITY2, Vector2i(3, 2))  # снайп 7 в слот 3
	var r := Resolver.new()
	r.resolve(s, oa, _slots(), Consts.Player.A)
	_check(not b.alive, "килл: цель мертва")
	_check(s.score[Consts.Player.A] == Consts.KILL_POINTS, "килл: +3 очка A [%d]" % s.score[Consts.Player.A])
	_check(b.dead_timer == Consts.RESPAWN_DELAY, "килл: таймер респа = 3")
	_check(b.death_cell == Vector2i(3, 2), "килл: клетка смерти запомнена")


func test_respawn_at_home_row() -> void:
	# респ идёт в РОДНУЮ клетку, а не на клетку смерти; стоящий на клетке смерти не наказывается
	var s := _fresh()
	s.round_num = 5
	var dead := s.get_unit(4)                          # B Фея, дом (3,0)
	dead.alive = false
	dead.hp = 0
	dead.cell = Vector2i(3, 3)
	dead.death_cell = Vector2i(3, 3)
	dead.dead_timer = 1
	var camper := _place(s, 0, Vector2i(3, 3), Consts.HUNTER_HP)   # A Охотник на клетке смерти
	var ev := s.begin_round()
	_check(dead.alive and dead.cell == dead.home_cell, "респ: воскрес в родной клетке [%s]" % str(dead.cell))
	_check(dead.hp == dead.max_hp, "респ: полное HP")
	_check(camper.hp == Consts.HUNTER_HP, "респ: стоящий на клетке смерти не получает урона [%d]" % camper.hp)
	_check(_has_type(ev, Consts.EventType.RESPAWN), "респ: событие RESPAWN")

	# дом занят → ближайшая свободная клетка родного ряда
	var s2 := _fresh()
	var dead2 := s2.get_unit(4)
	dead2.alive = false
	dead2.hp = 0
	dead2.cell = Vector2i(6, 6)
	dead2.death_cell = Vector2i(6, 6)
	dead2.dead_timer = 1
	_place(s2, 0, Vector2i(3, 0))                      # чужой юнит занял дом (3,0)
	s2.begin_round()
	_check(dead2.alive and dead2.cell == Vector2i(2, 0),
		"респ: дом занят → соседняя клетка ряда (2,0) [%s]" % str(dead2.cell))


func test_respawn_delay_misses_one_full_round() -> void:
	# убит в раунде N → возвращается в начале N+RESPAWN_DELAY, пропустив (DELAY-1) полных раундов
	var s := _fresh()
	var u := s.get_unit(4)
	u.alive = false
	u.hp = 0
	u.death_cell = Vector2i(3, 3)
	u.cell = Vector2i(3, 3)
	u.dead_timer = Consts.RESPAWN_DELAY
	s.begin_round()
	_check(not u.alive, "респ-кулдаун: в следующем раунде ещё мёртв")
	s.begin_round()
	_check(u.alive, "респ-кулдаун: вернулся через %d раунда" % Consts.RESPAWN_DELAY)


func test_control_point_majority() -> void:
	var s := _fresh()
	# точки: (2,2),(3,3),(4,4)
	_place(s, 0, Vector2i(2, 2))    # A
	_place(s, 1, Vector2i(3, 3))    # A → 2 точки
	_place(s, 2, Vector2i(0, 0))    # A вне точек
	_place(s, 3, Vector2i(4, 4))    # B → 1 точка
	_place(s, 4, Vector2i(6, 6))    # B вне точек
	_place(s, 5, Vector2i(0, 6))    # B вне точек
	var ev: Array = []
	s.score[Consts.Player.A] = 0
	s.score[Consts.Player.B] = 0
	s.score_round(ev)
	_check(s.score[Consts.Player.A] == 1 and s.score[Consts.Player.B] == 0, "точки: строгое большинство A → +1 A")
	# равенство 1:1: увести A с (3,3)
	_place(s, 1, Vector2i(0, 3))    # A уходит с (3,3) → A: (2,2)=1, B: (4,4)=1
	s.score[Consts.Player.A] = 0
	s.score[Consts.Player.B] = 0
	s.score_round(ev)
	_check(s.score[Consts.Player.A] == 0 and s.score[Consts.Player.B] == 0, "точки: равенство 1:1 → очко никому")


func test_crystal_no_passive() -> void:
	# пассивка снята (CRYSTAL_PASSIVE_REDUCTION = 0) → кристалл ест урон полностью
	var s := _fresh()
	var fairy := _place(s, 1, Vector2i(3, 3))      # A fairy кастует вспышку
	var crystal := _place(s, 5, Vector2i(3, 4), 10)  # B crystal рядом
	fairy.mana = Consts.FLASH_MANA
	var oa := _slots()
	oa[0] = Order.make(1, Consts.Action.ABILITY3, Vector2i(3, 3))  # вспышка (радиус 1)
	var r := Resolver.new()
	r.resolve(s, oa, _slots(), Consts.Player.A)
	var expect := 10 - (Consts.FLASH_DMG - Consts.CRYSTAL_PASSIVE_REDUCTION)
	_check(crystal.hp == expect, "кристалл без пассивки: вспышка бьёт полностью, HP %d [%d]" % [expect, crystal.hp])


func test_immobilize_blocks_next_move() -> void:
	var s := _fresh()
	var u := s.get_unit(5)
	u.immobilize_pending = true
	s.begin_round()   # → immobilized становится активным
	_check(u.immobilized, "обездвиживание перенеслось на новый раунд")
	var start := u.cell
	var oa := _slots()
	var ob := _slots()
	ob[0] = Order.make_move(5, [Vector2i(0, -1)] as Array[Vector2i])
	var r := Resolver.new()
	r.resolve(s, oa, ob, Consts.Player.A)
	_check(u.cell == start, "обездвиженный не сдвинулся")


func test_multi_round_income_and_control() -> void:
	# 3 раунда: A держит большинство точек, оба пасуют → +1 A/раунд, мана растёт +1/раунд
	var s := MatchState.new()
	s.setup()
	_place(s, 0, Vector2i(2, 2))   # A → точка
	_place(s, 1, Vector2i(3, 3))   # A → точка
	_place(s, 2, Vector2i(4, 4))   # A → точка (3 из 3)
	_place(s, 3, Vector2i(0, 0))   # B вне точек
	_place(s, 4, Vector2i(6, 6))   # B вне точек
	_place(s, 5, Vector2i(0, 6))   # B вне точек
	var r := Resolver.new()
	for _i in 3:
		s.begin_round()
		var ev := r.resolve(s, Order.empty_slots(), Order.empty_slots(), s.first_player_this_round())
		s.score_round(ev)
	_check(s.score[Consts.Player.A] == 3, "3 раунда контроля большинства → 3 очка A [%d]" % s.score[Consts.Player.A])
	_check(s.score[Consts.Player.B] == 0, "B без большинства → 0 очков [%d]" % s.score[Consts.Player.B])
	_check(s.get_unit(0).mana == 3, "мана: старт 1 + доход в раундах 2,3 = 3 [%d]" % s.get_unit(0).mana)
	_check(s.winner < 0, "победитель ещё не определён (<10)")


func test_fairy_shield_ally() -> void:
	# Фея ставит щит на соседнего союзника; вражеский снайп по нему поглощается
	var s := _fresh()
	var fairy := _place(s, 1, Vector2i(3, 3))   # A fairy
	fairy.mana = Consts.CANCEL_MANA
	var hunter := _place(s, 0, Vector2i(3, 4), Consts.HUNTER_HP)   # A hunter рядом с Феей
	var enemy := _place(s, 3, Vector2i(5, 4))   # B hunter (снайпер), линия (5,4)->(3,4) чиста
	enemy.mana = Consts.SNIPE_MANA
	var oa := _slots()
	oa[0] = Order.make(1, Consts.Action.ABILITY1, Vector2i(3, 4))   # щит на союзника
	var ob := _slots()
	ob[2] = Order.make(3, Consts.Action.ABILITY2, Vector2i(3, 4))   # снайп по нему (слот 3)
	var r := Resolver.new()
	r.resolve(s, oa, ob, Consts.Player.A)
	_check(hunter.hp == Consts.HUNTER_HP, "щит на союзнике поглотил снайп: HP %d [%d]" % [Consts.HUNTER_HP, hunter.hp])
	_check(not hunter.shield_armed, "щит израсходован после поглощения")


func test_bullet_blocked_by_unit() -> void:
	# Снайп нацелен в дальнюю цель, но на линии стоит блокер → пуля попадает в блокера
	var s := _fresh()
	s.board.obstacles = {}                       # чистая линия
	_place(s, 0, Vector2i(0, 4)).mana = 2        # A hunter
	_place(s, 1, Vector2i(0, 0))                 # увести своих
	_place(s, 2, Vector2i(6, 6))
	var blocker := _place(s, 4, Vector2i(2, 4), 12)   # B fairy на пути
	var target := _place(s, 5, Vector2i(4, 4), 10)    # B crystal — задуманная цель
	_place(s, 3, Vector2i(6, 0))
	var oa := _slots()
	oa[2] = Order.make(0, Consts.Action.ABILITY2, Vector2i(4, 4))  # снайп в (4,4)
	var r := Resolver.new()
	r.resolve(s, oa, _slots(), Consts.Player.A)
	_check(blocker.hp == 12 - Consts.SNIPE_DMG, "пуля попала в блокера на пути [%d]" % blocker.hp)
	_check(target.hp == 10, "цель за блокером не задета [%d]" % target.hp)


func test_trap_excludes_occupied_and_graves() -> void:
	var s := _fresh()
	var hunter := _place(s, 0, Vector2i(3, 4))     # A hunter
	_place(s, 5, Vector2i(2, 4))                    # живой враг рядом (радиус 1)
	var dead := _place(s, 3, Vector2i(4, 4))        # могила рядом
	dead.alive = false
	dead.death_cell = Vector2i(4, 4)
	var occ := Targeting.build_occupancy(s)
	var cands := Targeting.candidates(s, hunter, Consts.Action.ABILITY1, hunter.cell, occ)
	_check(not (Vector2i(2, 4) in cands), "капкан: занятая юнитом клетка исключена")
	_check(not (Vector2i(4, 4) in cands), "капкан: могила исключена")
	_check(Vector2i(3, 3) in cands, "капкан: свободная клетка доступна")


func test_trap_fizzle_on_occupied() -> void:
	# занято живым юнитом (сценарий no-retarget) → капкан не ставится
	var s := _fresh()
	_place(s, 0, Vector2i(3, 4)).mana = 1           # A hunter
	_place(s, 5, Vector2i(2, 4))                     # враг стоит на целевой клетке
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY1, Vector2i(2, 4))
	var r := Resolver.new()
	r.resolve(s, oa, _slots(), Consts.Player.A)
	_check(s.traps.size() == 0, "капкан не поставлен в клетку с юнитом [%d]" % s.traps.size())

	# занято могилой → тоже не ставится
	var s2 := _fresh()
	_place(s2, 0, Vector2i(3, 4)).mana = 1
	var dead := _place(s2, 5, Vector2i(2, 4))
	dead.alive = false
	dead.death_cell = Vector2i(2, 4)
	var oa2 := _slots()
	oa2[0] = Order.make(0, Consts.Action.ABILITY1, Vector2i(2, 4))
	Resolver.new().resolve(s2, oa2, _slots(), Consts.Player.A)
	_check(s2.traps.size() == 0, "капкан не поставлен в клетку с могилой [%d]" % s2.traps.size())


func test_trap_lives_one_round() -> void:
	var s := _fresh()                               # round_num = 1
	_place(s, 0, Vector2i(3, 4)).mana = 1           # A hunter
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY1, Vector2i(2, 4))   # капкан на пустую клетку
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(s.traps.size() == 1, "капкан стоит в раунде размещения [%d]" % s.traps.size())
	s.begin_round()                                 # -> раунд 2
	_check(s.traps.size() == 0, "капкан исчез в следующем раунде (живёт 1 раунд) [%d]" % s.traps.size())


func test_relative_move_after_knockback() -> void:
	# Фею отбрасывают Дробью до её хода → её ход применяется от НОВОЙ клетки (относительно)
	var s := _fresh()
	s.board.obstacles = {}
	_place(s, 0, Vector2i(0, 3)).mana = 3            # A hunter (Дробь)
	var fairy := _place(s, 4, Vector2i(1, 4), 12)    # B fairy на диагонали
	# развести остальных
	_place(s, 1, Vector2i(0, 0)); _place(s, 2, Vector2i(6, 6))
	_place(s, 3, Vector2i(6, 0)); _place(s, 5, Vector2i(0, 6))
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY3, Vector2i(1, 4))   # Дробь: отбрасывает Фею на (2,5)
	var ob := _slots()
	ob[0] = Order.make_move(4, [Vector2i(0, -1)] as Array[Vector2i])  # Фея планирует «вверх на 1»
	Resolver.new().resolve(s, oa, ob, Consts.Player.A)
	# A первым: Дробь (0,3)->цель(1,4), отброс dir(1,1) → Фея на (2,5); затем её ход (0,-1) → (2,4)
	_check(fairy.cell == Vector2i(2, 4), "относительный ход после отброса: (2,5)+(0,-1)=(2,4) [%s]" % str(fairy.cell))


func test_shield_nontarget_and_order() -> void:
	# 1) щит — нон-таргет: пустая соседняя клетка теперь валидная цель
	var s := _fresh()
	var fairy := _place(s, 1, Vector2i(3, 3))
	fairy.mana = Consts.CANCEL_MANA
	var occ := Targeting.build_occupancy(s)
	var cands := Targeting.candidates(s, fairy, Consts.Action.ABILITY1, fairy.cell, occ)
	_check(Vector2i(3, 2) in cands, "щит: пустая соседняя клетка — валидная цель (нон-таргет)")

	# 2) порядок важен: щит РАНЬШЕ прихода союзника → физзл (клетка пуста в этот тик)
	var s1 := _fresh()
	_place(s1, 1, Vector2i(3, 3)).mana = Consts.CANCEL_MANA   # A fairy
	var hunter1 := _place(s1, 0, Vector2i(2, 2))    # A hunter, придёт на (3,2) вторым
	var oa1 := _slots()
	oa1[0] = Order.make(1, Consts.Action.ABILITY1, Vector2i(3, 2))       # щит на (3,2)
	oa1[1] = Order.make_move(0, [Vector2i(1, 0)] as Array[Vector2i])     # (2,2)->(3,2)
	Resolver.new().resolve(s1, oa1, _slots(), Consts.Player.A)
	_check(not hunter1.shield_armed, "порядок: щит до прихода — не наложился")

	# 3) правильный порядок: сначала приход, потом щит → наложился
	var s2 := _fresh()
	_place(s2, 1, Vector2i(3, 3)).mana = Consts.CANCEL_MANA
	var hunter2 := _place(s2, 0, Vector2i(2, 2))
	var oa2 := _slots()
	oa2[0] = Order.make_move(0, [Vector2i(1, 0)] as Array[Vector2i])     # (2,2)->(3,2)
	oa2[1] = Order.make(1, Consts.Action.ABILITY1, Vector2i(3, 2))       # щит на (3,2)
	Resolver.new().resolve(s2, oa2, _slots(), Consts.Player.A)
	_check(hunter2.shield_armed, "порядок: щит после прихода — наложился")


func test_shield_gates_trap() -> void:
	# щит гасит капкан ЦЕЛИКОМ: ни урона, ни обездвиживания
	var s := _fresh()
	var crystal := _place(s, 5, Vector2i(1, 4), 10)   # B crystal со щитом
	crystal.shield_armed = true
	s.traps.append({"cell": Vector2i(2, 4), "owner_player": Consts.Player.A,
		"owner_id": 0, "expire_round": s.round_num + Consts.PERSIST_ROUNDS})
	var ob := _slots()
	ob[0] = Order.make_move(5, [Vector2i(1, 0)] as Array[Vector2i])   # (1,4)->(2,4) в капкан
	Resolver.new().resolve(s, _slots(), ob, Consts.Player.A)
	_check(crystal.cell == Vector2i(2, 4), "кристалл дошёл до капкана")
	_check(crystal.hp == 10, "щит погасил урон капкана [%d]" % crystal.hp)
	_check(not crystal.immobilize_pending, "щит погасил и обездвиживание капкана")
	_check(not crystal.shield_armed, "щит израсходован капканом")


func test_shotgun_area_2x2() -> void:
	# Дробь вверх-вправо из (2,3): квадрат (3,2),(3,3),(2,2). Клетка снизу (2,4) НЕ задета.
	var s := _fresh()
	s.board.obstacles = {}
	_place(s, 0, Vector2i(2, 3)).mana = 3          # A hunter (стрелок)
	var d1 := _place(s, 1, Vector2i(3, 2), 20)     # диагональ (A fairy)
	var d2 := _place(s, 3, Vector2i(3, 3), 20)     # право (B hunter)
	var d3 := _place(s, 4, Vector2i(2, 2), 20)     # верх (B fairy)
	var outside := _place(s, 2, Vector2i(2, 4), 20)  # снизу — вне квадрата (A crystal)
	_place(s, 5, Vector2i(6, 6))                    # убрать с дороги
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY3, Vector2i(3, 2))   # цель — диагональ вверх-вправо
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(d1.hp == 15, "дробь: диагональ задета (-5) [%d]" % d1.hp)
	_check(d2.hp == 15, "дробь: клетка справа задета (-5) [%d]" % d2.hp)
	_check(d3.hp == 15, "дробь: клетка сверху задета (-5) [%d]" % d3.hp)
	_check(outside.hp == 20, "дробь: клетка вне квадрата НЕ задета [%d]" % outside.hp)


func test_shotgun_fixed_direction() -> void:
	# нон-таргет: бьёт по offset от текущей позиции, а не по абсолютной target
	var s := _fresh()
	s.board.obstacles = {}
	_place(s, 0, Vector2i(2, 3)).mana = 3
	var e := _place(s, 3, Vector2i(3, 2), 20)   # клетка квадранта для offset (1,-1)
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY3, Vector2i(5, 5), Vector2i(1, -1), true)  # target «мимо», offset фикс
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(e.hp == 15, "дробь бьёт по offset от текущей позиции, не по цели [%d]" % e.hp)


func test_snipe_relative() -> void:
	# снайп нон-таргет: пуля летит по offset от текущей клетки стрелка
	var s := _fresh()
	_place(s, 0, Vector2i(2, 3)).mana = 2
	var e := _place(s, 4, Vector2i(2, 1), 20)   # 2 клетки вверх (offset (0,-2))
	var oa := _slots()
	oa[2] = Order.make(0, Consts.Action.ABILITY2, Vector2i(9, 9), Vector2i(0, -2), true)  # target мимо
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(e.hp == 20 - Consts.SNIPE_DMG, "снайп бьёт по offset от текущей позиции [%d]" % e.hp)


func test_ambush_ignores_allies() -> void:
	# союзник, вошедший рядом с засадой, не получает урона и не тратит её
	var s := _fresh()
	_place(s, 2, Vector2i(3, 3)).mana = Consts.AMBUSH_MANA   # A crystal встаёт в засаду
	var ally := _place(s, 1, Vector2i(1, 4))                 # A fairy подойдёт вплотную
	var oa := _slots()
	oa[0] = Order.make(2, Consts.Action.ABILITY2)                      # засада (без цели)
	oa[1] = Order.make_move(1, [Vector2i(1, 0)] as Array[Vector2i])    # (1,4)->(2,4): рядом с (3,3)
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(ally.cell == Vector2i(2, 4), "засада: союзник дошёл вплотную")
	_check(ally.hp == ally.max_hp, "засада не бьёт союзника [%d]" % ally.hp)
	_check(s.ambushes.size() == 1, "засада не израсходована союзником [%d]" % s.ambushes.size())

	# а вражеский юнит её срабатывает
	var s2 := _fresh()
	_place(s2, 2, Vector2i(3, 3)).mana = Consts.AMBUSH_MANA   # A crystal
	var foe := _place(s2, 5, Vector2i(1, 4))                  # B crystal
	var oa2 := _slots()
	oa2[0] = Order.make(2, Consts.Action.ABILITY2)
	var ob2 := _slots()
	ob2[0] = Order.make_move(5, [Vector2i(1, 0)] as Array[Vector2i])   # (1,4)->(2,4)
	Resolver.new().resolve(s2, oa2, ob2, Consts.Player.A)
	_check(foe.hp == foe.max_hp - Consts.AMBUSH_DMG, "засада бьёт врага [%d]" % foe.hp)
	_check(s2.ambushes.size() == 0, "засада израсходована врагом [%d]" % s2.ambushes.size())


func test_allies_do_not_block_movement() -> void:
	# 1) резолвер: проходим сквозь союзника и встаём за ним
	var s := _fresh()
	s.board.obstacles = {}
	var hunter := _place(s, 0, Vector2i(3, 4))   # A hunter
	_place(s, 1, Vector2i(3, 3))                 # A fairy — прямо на пути
	var oa := _slots()
	oa[0] = Order.make_move(0, [Vector2i(0, -1), Vector2i(0, -1)] as Array[Vector2i])
	Resolver.new().resolve(s, oa, _slots(), Consts.Player.A)
	_check(hunter.cell == Vector2i(3, 2), "ход: прошёл сквозь союзника на (3,2) [%s]" % str(hunter.cell))

	# 2) резолвер: встать НА союзника нельзя — ход упирается
	var s2 := _fresh()
	s2.board.obstacles = {}
	var h2 := _place(s2, 0, Vector2i(3, 4))
	_place(s2, 1, Vector2i(3, 3))
	var oa2 := _slots()
	oa2[0] = Order.make_move(0, [Vector2i(0, -1)] as Array[Vector2i])   # финиш на союзнике
	Resolver.new().resolve(s2, oa2, _slots(), Consts.Player.A)
	_check(h2.cell == Vector2i(3, 4), "ход: остановка на клетке союзника запрещена [%s]" % str(h2.cell))

	# 3) резолвер: враг блокирует полностью (даже как транзит)
	var s3 := _fresh()
	s3.board.obstacles = {}
	var h3 := _place(s3, 0, Vector2i(3, 4))
	_place(s3, 3, Vector2i(3, 3))                # B hunter на пути
	var oa3 := _slots()
	oa3[0] = Order.make_move(0, [Vector2i(0, -1), Vector2i(0, -1)] as Array[Vector2i])
	Resolver.new().resolve(s3, oa3, _slots(), Consts.Player.A)
	_check(h3.cell == Vector2i(3, 4), "ход: враг блокирует проход [%s]" % str(h3.cell))

	# 4) планирование: клетка ЗА союзником достижима, клетка союзника — нет
	var s4 := _fresh()
	s4.board.obstacles = {}
	var h4 := _place(s4, 0, Vector2i(3, 4))
	_place(s4, 1, Vector2i(3, 3))                # союзник
	var cells := Targeting.move_paths(s4, h4.cell, h4.id)
	_check(not cells.has(Vector2i(3, 3)), "план: клетка союзника не пункт назначения")
	_check(cells.has(Vector2i(3, 2)), "план: клетка за союзником достижима")

	# 5) планирование: за врагом — недостижимо
	var s5 := _fresh()
	s5.board.obstacles = {}
	var h5 := _place(s5, 0, Vector2i(3, 4))
	_place(s5, 3, Vector2i(3, 3))                # враг
	var cells5 := Targeting.move_paths(s5, h5.cell, h5.id)
	_check(not cells5.has(Vector2i(3, 2)), "план: за врагом пройти нельзя")


func test_respawn_resets_mana() -> void:
	# банк маны, накопленный до смерти, не переживает респ
	var s := _fresh()
	var u := s.get_unit(4)          # B fairy
	u.alive = false
	u.hp = 0
	u.cell = Vector2i(0, 0)
	u.death_cell = Vector2i(0, 0)
	u.dead_timer = 1
	u.mana = 7
	s.begin_round()
	_check(u.alive and u.hp == u.max_hp, "респ: воскрес с полным HP")
	_check(u.mana == Consts.START_MANA, "респ: мана сброшена к стартовой [%d]" % u.mana)
	_check(u.cell == u.home_cell, "респ: вернулся в родную клетку [%s]" % str(u.cell))


func test_validator_move_rules() -> void:
	var s := _fresh()
	_place(s, 0, Vector2i(3, 4))     # A hunter
	var o := _slots()
	o[0] = Order.make_move(0, [Vector2i(0, -5)] as Array[Vector2i])                     # телепорт
	o[1] = Order.make_move(0, [Vector2i(0, -1), Vector2i(0, -1)] as Array[Vector2i])    # легально (2 шага)
	o[2] = Order.make_move(0, [Vector2i(0, -1), Vector2i(0, -1), Vector2i(0, -1)] as Array[Vector2i])
	o[3] = Order.make_move(0, [Vector2i(1, 1)] as Array[Vector2i])                      # диагональ
	var out := OrderValidator.sanitize(s, o, Consts.Player.A)
	_check(out[0].is_empty(), "валидатор: шаг-телепорт отклонён")
	_check(not out[1].is_empty(), "валидатор: ход из двух орто-шагов принят")
	_check(out[2].is_empty(), "валидатор: ход длиннее MOVE_RANGE отклонён")
	_check(out[3].is_empty(), "валидатор: диагональный шаг отклонён")


func test_validator_target_geometry() -> void:
	var s := _fresh()
	_place(s, 0, Vector2i(3, 4))     # A hunter
	_place(s, 1, Vector2i(2, 4))     # A fairy
	_check(not _san1(s, Order.make(0, Consts.Action.ATTACK, Vector2i(3, 1), Vector2i(0, -3), true)).is_empty(),
		"валидатор: выстрел на 3 клетки принят")
	_check(_san1(s, Order.make(0, Consts.Action.ATTACK, Vector2i(3, 3), Vector2i(0, -1), true)).is_empty(),
		"валидатор: выстрел в упор (дистанция 1) отклонён")
	_check(_san1(s, Order.make(0, Consts.Action.ATTACK, Vector2i(2, 3), Vector2i(-1, -1), true)).is_empty(),
		"валидатор: выстрел по диагонали отклонён")
	_check(_san1(s, Order.make(1, Consts.Action.ATTACK, Vector2i(6, 4), Vector2i(4, 0), true)).is_empty(),
		"валидатор: ближний удар Феи через всю доску отклонён")
	_check(not _san1(s, Order.make(1, Consts.Action.ATTACK, Vector2i(3, 3), Vector2i(1, -1), true)).is_empty(),
		"валидатор: удар Феи по диагонали принят")
	# Лечение вне радиуса 2
	_place(s, 1, Vector2i(2, 4)).mana = Consts.HEAL_MANA
	_check(_san1(s, Order.make(1, Consts.Action.ABILITY2, Vector2i(2, 0), Vector2i(0, -4), true)).is_empty(),
		"валидатор: лечение через всю доску отклонено")


func test_validator_mana_gate_and_double_cast() -> void:
	# один и тот же скилл дважды за раунд — нельзя
	var s := _fresh()
	_place(s, 0, Vector2i(3, 4)).mana = Consts.SNIPE_MANA * 2
	var o := _slots()
	o[2] = Order.make(0, Consts.Action.ABILITY2, Vector2i(3, 2), Vector2i(0, -2), true)
	o[3] = Order.make(0, Consts.Action.ABILITY2, Vector2i(3, 2), Vector2i(0, -2), true)
	var out := OrderValidator.sanitize(s, o, Consts.Player.A)
	_check(not out[2].is_empty(), "валидатор: первый снайп принят")
	_check(out[3].is_empty(), "валидатор: повторный каст того же скилла отклонён")

	# суммарная мана героя за раунд
	var s2 := _fresh()
	_place(s2, 0, Vector2i(3, 4)).mana = Consts.TRAP_MANA   # хватает только на капкан
	var o2 := _slots()
	o2[0] = Order.make(0, Consts.Action.ABILITY1, Vector2i(2, 4), Vector2i(-1, 0), true)   # капкан
	o2[2] = Order.make(0, Consts.Action.ABILITY2, Vector2i(3, 2), Vector2i(0, -2), true)   # снайп
	var out2 := OrderValidator.sanitize(s2, o2, Consts.Player.A)
	_check(not out2[0].is_empty(), "валидатор: капкан по мане прошёл")
	_check(out2[2].is_empty(), "валидатор: снайп сверх суммарной маны отклонён")

	# гейт слотов: снайп только в слотах 3-4
	var s3 := _fresh()
	_place(s3, 0, Vector2i(3, 4)).mana = Consts.SNIPE_MANA
	_check(_san_at(s3, Order.make(0, Consts.Action.ABILITY2, Vector2i(3, 2), Vector2i(0, -2), true), 0).is_empty(),
		"валидатор: снайп вне слотов 3-4 отклонён")


func test_validator_rejects_foreign_and_dead() -> void:
	var s := _fresh()
	var o := _slots()
	o[0] = Order.make_move(3, [Vector2i(0, 1)] as Array[Vector2i])   # приказ юниту игрока B
	_check(OrderValidator.sanitize(s, o, Consts.Player.A)[0].is_empty(), "валидатор: приказ чужому юниту отклонён")
	s.get_unit(0).alive = false
	var o2 := _slots()
	o2[0] = Order.make_move(0, [Vector2i(0, -1)] as Array[Vector2i])
	_check(OrderValidator.sanitize(s, o2, Consts.Player.A)[0].is_empty(), "валидатор: приказ мёртвому юниту отклонён")


# Прогнать один приказ через валидатор в слоте 0 (или указанном) и вернуть результат
func _san1(s: MatchState, o: Order) -> Order:
	return _san_at(s, o, 0)


func _san_at(s: MatchState, o: Order, slot: int) -> Order:
	var arr := _slots()
	arr[slot] = o
	return OrderValidator.sanitize(s, arr, Consts.Player.A)[slot]


func _has_type(events: Array, t: int) -> bool:
	for e in events:
		if e.type == t:
			return true
	return false
