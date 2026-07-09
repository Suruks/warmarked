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
	test_respawn_block_then_free()
	test_control_point_majority()
	test_crystal_passive_floor()
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
	_place(s, 0, Vector2i(3, 4)).mana = 3            # A hunter (капкан 1 + снайп 2)
	var b := _place(s, 5, Vector2i(1, 4))            # B crystal (hp10)
	var oa := _slots()
	oa[0] = Order.make(0, Consts.Action.ABILITY1, Vector2i(2, 4))   # капкан
	oa[2] = Order.make(0, Consts.Action.ABILITY2, Vector2i(2, 4))   # снайп (слот 3)
	var ob := _slots()
	ob[0] = Order.make_move(5, [Vector2i(1, 0)] as Array[Vector2i]) # (1,4)->(2,4) входит в капкан
	var r := Resolver.new()
	r.resolve(s, oa, ob, Consts.Player.A)
	# crystal passive -1: капкан 4→3, снайп 7→6, итого 9, из 10 → 1 HP
	_check(b.hp == 1, "капкан+снайп по обездвиженному: HP 1 (было 10, −3 −6) [%d]" % b.hp)
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
	# дробь 5 + отброс в угол (7,7 вне поля) → столкновение 4 = 9, из 12 → 3
	_check(b.hp == 3, "дробь+столкновение о край: HP 3 (−5 −4) [%d]" % b.hp)


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


func test_respawn_block_then_free() -> void:
	var s := _fresh()
	s.round_num = 5
	var dead := s.get_unit(4)                          # B fairy
	dead.alive = false
	dead.death_cell = Vector2i(3, 3)
	dead.dead_timer = 1
	dead.hp = 0
	var blocker := _place(s, 0, Vector2i(3, 3), 11)    # A hunter стоит на клетке смерти
	# развести остальных, чтобы не воскресали/не мешали
	var ev := s.begin_round()
	_check(not dead.alive, "блок-респ: цель осталась мёртвой")
	_check(blocker.hp == 11 - Consts.BLOCKER_DMG, "блок-респ: блокер получил 5 [%d]" % blocker.hp)
	_check(_has_type(ev, Consts.EventType.RESPAWN_BLOCKED), "блок-респ: событие RESPAWN_BLOCKED")
	# освободить клетку и повторить
	blocker.cell = Vector2i(0, 0)
	var ev2 := s.begin_round()
	_check(dead.alive and dead.cell == Vector2i(3, 3) and dead.hp == dead.max_hp, "респ: воскрес на клетке смерти с полным HP")
	_check(_has_type(ev2, Consts.EventType.RESPAWN), "респ: событие RESPAWN")


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


func test_crystal_passive_floor() -> void:
	var s := _fresh()
	var fairy := _place(s, 1, Vector2i(3, 3))      # A fairy кастует вспышку
	var crystal := _place(s, 5, Vector2i(3, 4), 10)  # B crystal рядом
	# дадим фее ману на вспышку
	fairy.mana = 5
	var oa := _slots()
	oa[0] = Order.make(1, Consts.Action.ABILITY3, Vector2i(3, 3))  # вспышка (радиус 1)
	var r := Resolver.new()
	r.resolve(s, oa, _slots(), Consts.Player.A)
	_check(crystal.hp == 10 - (Consts.FLASH_DMG - 1), "пассив кристалла: вспышка 4→3 [%d]" % crystal.hp)


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
	fairy.mana = 1
	var hunter := _place(s, 0, Vector2i(3, 4), 11)   # A hunter рядом с Феей
	var enemy := _place(s, 3, Vector2i(5, 4))   # B hunter (снайпер), линия (5,4)->(3,4) чиста
	enemy.mana = 2
	var oa := _slots()
	oa[0] = Order.make(1, Consts.Action.ABILITY1, Vector2i(3, 4))   # щит на союзника
	var ob := _slots()
	ob[2] = Order.make(3, Consts.Action.ABILITY2, Vector2i(3, 4))   # снайп по нему (слот 3)
	var r := Resolver.new()
	r.resolve(s, oa, ob, Consts.Player.A)
	_check(hunter.hp == 11, "щит на союзнике поглотил снайп: HP 11 [%d]" % hunter.hp)
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
	fairy.mana = 1
	var occ := Targeting.build_occupancy(s)
	var cands := Targeting.candidates(s, fairy, Consts.Action.ABILITY1, fairy.cell, occ)
	_check(Vector2i(3, 2) in cands, "щит: пустая соседняя клетка — валидная цель (нон-таргет)")

	# 2) порядок важен: щит РАНЬШЕ прихода союзника → физзл (клетка пуста в этот тик)
	var s1 := _fresh()
	_place(s1, 1, Vector2i(3, 3)).mana = 1          # A fairy
	var hunter1 := _place(s1, 0, Vector2i(2, 2))    # A hunter, придёт на (3,2) вторым
	var oa1 := _slots()
	oa1[0] = Order.make(1, Consts.Action.ABILITY1, Vector2i(3, 2))       # щит на (3,2)
	oa1[1] = Order.make_move(0, [Vector2i(1, 0)] as Array[Vector2i])     # (2,2)->(3,2)
	Resolver.new().resolve(s1, oa1, _slots(), Consts.Player.A)
	_check(not hunter1.shield_armed, "порядок: щит до прихода — не наложился")

	# 3) правильный порядок: сначала приход, потом щит → наложился
	var s2 := _fresh()
	_place(s2, 1, Vector2i(3, 3)).mana = 1
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


func _has_type(events: Array, t: int) -> bool:
	for e in events:
		if e.type == t:
			return true
	return false
