extends SceneTree

## Разовый smoke-тест Драконида: базовая атака и 5 способностей резолвятся корректно.

var _pass := 0
var _fail := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fail += 1
		print("  FAIL  %s" % label)


# Матч с Драконидом-A0 в известной позиции. team_a[0] = Драконид со всем китом.
func _mk() -> MatchState:
	var s := MatchState.new()
	var drac := {"type": Consts.HeroType.DRACONID,
		"skills": [Consts.Skill.CLAWS, Consts.Skill.FIRE_BREATH, Consts.Skill.FLIGHT]}
	s.setup([drac, drac, drac], [drac, drac, drac], 0)
	return s


func _dr(s: MatchState) -> Unit:
	return s.get_unit(0)


func _res(s: MatchState, u: Unit, action: int, target: Vector2i) -> void:
	var o := Order.make(u.id, action, target, target - u.cell, true)
	var orders := Order.empty_slots()
	orders[0] = o
	Resolver.new().resolve(s, orders, Order.empty_slots(), Consts.Player.A)


func _initialize() -> void:
	print("=== Draconid smoke ===")
	test_flame()
	test_fire_breath()
	test_wing_sweep()
	test_claws()
	test_roar()
	test_flight()
	test_predator()
	test_predator_no_chase_on_teleport()
	test_dive()
	test_devour()
	test_devour_too_healthy()
	print("=== Итог: %d PASS, %d FAIL ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# Пламя (базовая атака): 3 урона по соседней клетке И следующей за ней.
func test_flame() -> void:
	var s := _mk()
	var u := _dr(s)
	u.cell = Vector2i(1, 3)
	var e1 := s.get_unit(3); e1.cell = Vector2i(2, 3)   # соседняя
	var e2 := s.get_unit(4); e2.cell = Vector2i(3, 3)   # следующая
	var e3 := s.get_unit(5); e3.cell = Vector2i(0, 0)   # в стороне
	_res(s, u, Consts.Action.ATTACK, Vector2i(2, 3))
	_check(e1.hp == e1.max_hp - Consts.DRACONID_ATK_DMG, "пламя: соседняя получила урон [%d]" % e1.hp)
	_check(e2.hp == e2.max_hp - Consts.DRACONID_ATK_DMG, "пламя: следующая получила урон [%d]" % e2.hp)
	_check(e3.hp == e3.max_hp, "пламя: юнит в стороне цел")


# Огненное дыхание: 4 урона ВСЕМ на прямой линии (дальность до 4).
func test_fire_breath() -> void:
	var s := _mk()
	var u := _dr(s)
	u.cell = Vector2i(1, 3)
	u.mana = 5
	var e1 := s.get_unit(3); e1.cell = Vector2i(2, 3)
	var e2 := s.get_unit(4); e2.cell = Vector2i(4, 3)   # дальность 3 — в пределах 4
	var e3 := s.get_unit(5); e3.cell = Vector2i(1, 5)   # не на линии
	_res(s, u, Consts.Action.ABILITY2, Vector2i(2, 3))   # CLAWS(1),FIRE_BREATH(3),FLIGHT(2) -> сорт: CLAWS,FLIGHT,FIRE_BREATH => слот3
	# слоты сортируются по мане: CLAWS(1)=ABILITY1, FLIGHT(2)=ABILITY2, FIRE_BREATH(3)=ABILITY3
	# значит дыхание — ABILITY3; переиграем корректно:
	s = _mk(); u = _dr(s); u.cell = Vector2i(1, 3); u.mana = 5
	e1 = s.get_unit(3); e1.cell = Vector2i(2, 3)
	e2 = s.get_unit(4); e2.cell = Vector2i(4, 3)
	e3 = s.get_unit(5); e3.cell = Vector2i(1, 5)
	_res(s, u, Consts.Action.ABILITY3, Vector2i(2, 3))
	_check(e1.hp == e1.max_hp - Consts.FIRE_BREATH_DMG, "дыхание: первый на линии задет [%d]" % e1.hp)
	_check(e2.hp == e2.max_hp - Consts.FIRE_BREATH_DMG, "дыхание: дальний на линии тоже задет [%d]" % e2.hp)
	_check(e3.hp == e3.max_hp, "дыхание: вне линии цел")
	_check(u.mana == 5 - Consts.FIRE_BREATH_MANA, "дыхание: мана списана [%d]" % u.mana)


# Взмах крыльев: 3 всем соседям + отброс на 1.
func test_wing_sweep() -> void:
	var s := MatchState.new()
	var kit := {"type": Consts.HeroType.DRACONID,
		"skills": [Consts.Skill.WING_SWEEP, Consts.Skill.ROAR, Consts.Skill.FLIGHT]}
	s.setup([kit, kit, kit], [kit, kit, kit], 0)
	# отодвигаем непричастных со спаунов, чтобы не мешали отбросу
	s.get_unit(1).cell = Vector2i(0, 0)
	s.get_unit(2).cell = Vector2i(0, 6)
	s.get_unit(5).cell = Vector2i(6, 0)
	# ряд y=4 полностью проходим — отброс вправо на (4,4) свободен
	var u := s.get_unit(0); u.cell = Vector2i(2, 4); u.mana = 5
	var e1 := s.get_unit(3); e1.cell = Vector2i(3, 4)   # сосед справа
	var e2 := s.get_unit(4); e2.cell = Vector2i(0, 2)   # не сосед
	var idx := u.skills.find(Consts.Skill.WING_SWEEP)
	_res(s, u, Consts.Action.ABILITY1 + idx, u.cell)
	_check(e1.hp == e1.max_hp - Consts.WING_SWEEP_DMG, "взмах: сосед получил урон [%d]" % e1.hp)
	_check(e1.cell == Vector2i(4, 4), "взмах: сосед отброшен на 1 [%s]" % str(e1.cell))
	_check(e2.hp == e2.max_hp, "взмах: несосед цел")


# Когти: 3 урона по дуге из 3 клеток впереди.
func test_claws() -> void:
	var s := _mk()
	var u := _dr(s); u.cell = Vector2i(3, 3); u.mana = 3
	var e1 := s.get_unit(3); e1.cell = Vector2i(4, 3)   # передняя
	var e2 := s.get_unit(4); e2.cell = Vector2i(4, 4)   # диаг-передняя
	var e3 := s.get_unit(5); e3.cell = Vector2i(2, 3)   # позади
	var idx := u.skills.find(Consts.Skill.CLAWS)
	_res(s, u, Consts.Action.ABILITY1 + idx, Vector2i(4, 3))
	_check(e1.hp == e1.max_hp - Consts.CLAWS_DMG, "когти: передняя задета [%d]" % e1.hp)
	_check(e2.hp == e2.max_hp - Consts.CLAWS_DMG, "когти: диаг-передняя задета [%d]" % e2.hp)
	_check(e3.hp == e3.max_hp, "когти: позади цел")


# Рёв: +2 к урону союзникам в радиусе 3 (проверяем через последующий урон).
func test_roar() -> void:
	var s := MatchState.new()
	var kit := {"type": Consts.HeroType.DRACONID,
		"skills": [Consts.Skill.ROAR, Consts.Skill.CLAWS, Consts.Skill.FLIGHT]}
	s.setup([kit, kit, kit], [kit, kit, kit], 0)
	var u := s.get_unit(0); u.cell = Vector2i(3, 3); u.mana = 5
	# Рёв, затем Когти по врагу — урон должен быть CLAWS_DMG + ROAR_BONUS
	var enemy := s.get_unit(3); enemy.cell = Vector2i(4, 3)
	var ri := u.skills.find(Consts.Skill.ROAR)
	var ci := u.skills.find(Consts.Skill.CLAWS)
	var orders := Order.empty_slots()
	orders[ri] = Order.make(u.id, Consts.Action.ABILITY1 + ri, u.cell, Vector2i.ZERO, true)
	orders[ci] = Order.make(u.id, Consts.Action.ABILITY1 + ci, Vector2i(4, 3), Vector2i(4, 3) - u.cell, true)
	# слоты идут по возрастанию: ROAR(2),CLAWS(1) -> CLAWS раньше. Чтобы рёв был ДО когтей,
	# положим их в явные слоты по порядку исполнения (slot index = порядок).
	orders = Order.empty_slots()
	orders[0] = Order.make(u.id, Consts.Action.ABILITY1 + ri, u.cell, Vector2i.ZERO, true)
	orders[1] = Order.make(u.id, Consts.Action.ABILITY1 + ci, Vector2i(4, 3), Vector2i(4, 3) - u.cell, true)
	Resolver.new().resolve(s, orders, Order.empty_slots(), Consts.Player.A)
	_check(u.dmg_buff_round == Consts.ROAR_BONUS, "рёв: бафф на кастере [%d]" % u.dmg_buff_round)
	_check(enemy.hp == enemy.max_hp - (Consts.CLAWS_DMG + Consts.ROAR_BONUS),
		"рёв: последующий урон усилен на +%d [%d]" % [Consts.ROAR_BONUS, enemy.hp])


# Полёт: ход на 3 клетки сквозь врага, приземление на свободную клетку.
func test_flight() -> void:
	var s := _mk()
	var u := _dr(s); u.cell = Vector2i(1, 3); u.mana = 3
	var blocker := s.get_unit(3); blocker.cell = Vector2i(2, 3)   # враг на пути
	# путь: 3 шага вправо (1,3)->(2,3 враг)->(3,3)->(4,3)
	var idx := u.skills.find(Consts.Skill.FLIGHT)
	var o := Order.new(u.id, Consts.Action.ABILITY1 + idx)
	o.path = [Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0)] as Array[Vector2i]
	var orders := Order.empty_slots()
	orders[idx] = o
	Resolver.new().resolve(s, orders, Order.empty_slots(), Consts.Player.A)
	_check(u.cell == Vector2i(4, 3), "полёт: пролетел сквозь врага и приземлился [%s]" % str(u.cell))
	_check(blocker.cell == Vector2i(2, 3), "полёт: враг на месте (пролетели сквозь)")


# Отряд A из драконидов с китом dk, отряд B — базовый кит. Непричастные юниты в углы.
func _mk2(dk: Array) -> MatchState:
	var s := MatchState.new()
	var a := {"type": Consts.HeroType.DRACONID, "skills": dk}
	var b := {"type": Consts.HeroType.DRACONID,
		"skills": [Consts.Skill.CLAWS, Consts.Skill.FLIGHT, Consts.Skill.FIRE_BREATH]}
	s.setup([a, a, a], [b, b, b], 0)
	s.get_unit(1).cell = Vector2i(0, 0)
	s.get_unit(2).cell = Vector2i(6, 0)
	s.get_unit(4).cell = Vector2i(0, 6)
	s.get_unit(5).cell = Vector2i(6, 6)
	return s


# Инстинкт хищника: соседний враг уходит — драконид рвётся следом и кусает.
func test_predator() -> void:
	var s := _mk2([Consts.Skill.PREDATOR_INSTINCT, Consts.Skill.DIVE, Consts.Skill.DEVOUR])
	var drac := s.get_unit(0); drac.cell = Vector2i(2, 2); drac.mana = 3
	var enemy := s.get_unit(3); enemy.cell = Vector2i(3, 2)
	var pi := drac.skills.find(Consts.Skill.PREDATOR_INSTINCT)
	var oa := Order.empty_slots(); oa[0] = Order.new(0, Consts.Action.ABILITY1 + pi)
	var ob := Order.empty_slots(); ob[0] = Order.make_move(3, [Vector2i(1, 0)] as Array[Vector2i])
	Resolver.new().resolve(s, oa, ob, Consts.Player.A)
	_check(enemy.cell == Vector2i(4, 2), "инстинкт: беглец ушёл на (4,2) [%s]" % str(enemy.cell))
	_check(drac.cell == Vector2i(3, 2), "инстинкт: драконид рванул в освободившуюся клетку [%s]" % str(drac.cell))
	_check(enemy.hp == enemy.max_hp - Consts.PREDATOR_DMG, "инстинкт: беглец укушен [%d]" % enemy.hp)


# Инстинкт хищника: добыча улетает далеко (Полёт) — рывок не достаёт, стойка сохраняется.
func test_predator_no_chase_on_teleport() -> void:
	var s := _mk2([Consts.Skill.PREDATOR_INSTINCT, Consts.Skill.DIVE, Consts.Skill.DEVOUR])
	var drac := s.get_unit(0); drac.cell = Vector2i(2, 2); drac.mana = 3
	var enemy := s.get_unit(3); enemy.cell = Vector2i(3, 2); enemy.mana = 3
	var pi := drac.skills.find(Consts.Skill.PREDATOR_INSTINCT)
	var fi := enemy.skills.find(Consts.Skill.FLIGHT)
	var oa := Order.empty_slots(); oa[0] = Order.new(0, Consts.Action.ABILITY1 + pi)
	var of := Order.new(3, Consts.Action.ABILITY1 + fi)
	of.path = [Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0)] as Array[Vector2i]
	var ob := Order.empty_slots(); ob[0] = of
	Resolver.new().resolve(s, oa, ob, Consts.Player.A)
	_check(enemy.cell == Vector2i(6, 2), "инстинкт: добыча улетела на (6,2) [%s]" % str(enemy.cell))
	_check(drac.cell == Vector2i(2, 2), "инстинкт: драконид не сдвинулся (не достал) [%s]" % str(drac.cell))
	_check(drac.predator_armed, "инстинкт: стойка сохранилась (рывок не потрачен)")
	_check(enemy.hp == enemy.max_hp, "инстинкт: добыча цела")


# Пикирование: рывок по прямой + урон всем вокруг точки приземления.
func test_dive() -> void:
	var s := _mk2([Consts.Skill.PREDATOR_INSTINCT, Consts.Skill.DIVE, Consts.Skill.DEVOUR])
	var drac := s.get_unit(0); drac.cell = Vector2i(2, 2); drac.mana = 3
	var e1 := s.get_unit(3); e1.cell = Vector2i(5, 2)   # сосед точки приземления (4,2)
	var e2 := s.get_unit(4); e2.cell = Vector2i(4, 3)   # тоже сосед (4,2)
	var di := drac.skills.find(Consts.Skill.DIVE)
	_res(s, drac, Consts.Action.ABILITY1 + di, Vector2i(4, 2))
	_check(drac.cell == Vector2i(4, 2), "пикирование: приземлился на (4,2) [%s]" % str(drac.cell))
	_check(e1.hp == e1.max_hp - Consts.DIVE_DMG, "пикирование: сосед1 задет [%d]" % e1.hp)
	_check(e2.hp == e2.max_hp - Consts.DIVE_DMG, "пикирование: сосед2 задет [%d]" % e2.hp)


# Пожирание: соседний враг с HP <= порога уничтожается мгновенно.
func test_devour() -> void:
	var s := _mk2([Consts.Skill.PREDATOR_INSTINCT, Consts.Skill.DIVE, Consts.Skill.DEVOUR])
	var drac := s.get_unit(0); drac.cell = Vector2i(2, 2); drac.mana = 4
	var enemy := s.get_unit(3); enemy.cell = Vector2i(3, 2); enemy.hp = Consts.DEVOUR_THRESHOLD
	var de := drac.skills.find(Consts.Skill.DEVOUR)
	var score_before: int = s.score[Consts.Player.A]
	_res(s, drac, Consts.Action.ABILITY1 + de, Vector2i(3, 2))
	_check(not enemy.alive, "пожирание: враг с %d HP уничтожен" % Consts.DEVOUR_THRESHOLD)
	_check(s.score[Consts.Player.A] == score_before + Consts.KILL_POINTS, "пожирание: начислено килл-очко")


# Пожирание: враг с HP выше порога не съедается.
func test_devour_too_healthy() -> void:
	var s := _mk2([Consts.Skill.PREDATOR_INSTINCT, Consts.Skill.DIVE, Consts.Skill.DEVOUR])
	var drac := s.get_unit(0); drac.cell = Vector2i(2, 2); drac.mana = 4
	var enemy := s.get_unit(3); enemy.cell = Vector2i(3, 2); enemy.hp = Consts.DEVOUR_THRESHOLD + 1
	var de := drac.skills.find(Consts.Skill.DEVOUR)
	_res(s, drac, Consts.Action.ABILITY1 + de, Vector2i(3, 2))
	_check(enemy.alive and enemy.hp == Consts.DEVOUR_THRESHOLD + 1, "пожирание: слишком здоровый враг цел [%d]" % enemy.hp)
