class_name OrderValidator
extends RefCounted

## Авторитетная проверка легальности приказов. Вызывается СЕРВЕРОМ (MatchSession.submit)
## до того, как приказы попадут в резолвер и будут разосланы клиентам.
##
## Что проверяется здесь (структурная безопасность, которую резолвер НЕ делает сам):
##   • ход/путь-скилл — только единичные орто-шаги, не длиннее дальности (иначе телепорт сквозь стены);
##   • минное поле — форма/число офсетов мин;
##   • «один приказ не дважды за раунд» — включая Ход (герой не ходит в двух слотах);
##   • суммарная мана героя за раунд;
##   • гейт слотов (дублирует резолвер, но дешевле отсечь заранее);
##   • пассивку нельзя активировать.
##
## Что здесь НЕ проверяется:
##   • геометрия цели (форма/дальность смещения) — её авторитетно проверяет резолвер
##     (Resolver._target_geometry_ok) и физзлит нелегальное. Так игрок может запланировать
##     «невозможную» цель (в т.ч. онлайн): приказ доедет до разрешения и просто не сработает;
##   • проходимость, LOS, занятость клеток — это состояние на момент РАЗРЕШЕНИЯ, его считает
##     резолвер: нелегальная по ситуации цель физзлит, как и у честного клиента, чей план
##     разошёлся с реальностью.


# Хватает ли герою маны на всю последовательность его действий за раунд. seq — по слотам 0..N:
# [cost, gain] потраченной/полученной героем маны за этот слот, либо null (герой в слоте не
# действует). Модель ровно как у резолвера: бегущий банк стартует со start_mana, слот тратит cost
# (обязан хватить в этот момент), ПОСЛЕ чего в банк идёт нетто gain-cost — то есть прирост маны
# помогает ПОЗДНИМ слотам, а не своему. Ни разу не ушёл в минус → true.
#
# Единый авторитет по мане: и сервер (_slot_legal ниже), и планировщик (PlanningPanel) считают
# ману этой же моделью — иначе клиент разблокировал бы скилл, который сервер срежет в пустой.
static func mana_sequence_ok(seq: Array, start_mana: int) -> bool:
	var bank := start_mana
	for cg in seq:
		if cg == null:
			continue
		if bank < cg[0]:
			return false
		bank += cg[1] - cg[0]
	return true


# Возвращает НОВЫЙ массив из ORDER_SLOTS приказов: нелегальные заменены на пустые.
static func sanitize(state: MatchState, orders: Array, player: int) -> Array:
	var out: Array = []
	var bank := {}    # hero_id -> текущая мана героя по ходу слотов (бегущий банк, см. mana_sequence_ok)
	var seen := {}    # "hero:action" -> скилл уже занят в другом слоте
	for i in Consts.ORDER_SLOTS:
		var o: Order = orders[i] if i < orders.size() else Order.empty()
		# Второй игрок раунда не действует в последнем слоте — срезаем в пустой приказ.
		var ok := state.acts_in_slot(player, i) and _slot_legal(state, o, player, i, bank, seen)
		out.append(o if ok else Order.empty())
	return out


# Побочный эффект: при легальном приказе двигает бегущий банк маны героя и помечает скилл занятым.
static func _slot_legal(state: MatchState, o: Order, player: int, slot: int, bank: Dictionary, seen: Dictionary) -> bool:
	if o == null or o.is_empty():
		return false
	var u := state.get_unit(o.hero_id)
	if u == null or u.owner != player or not u.alive:
		return false
	if o.action == Consts.Action.MOVE:
		if not _move_legal(o.path, u.move_range()):
			return false
		# Ход, как и скилл, нельзя занять дважды за раунд одному герою.
		var mkey := "%d:%d" % [o.hero_id, Consts.Action.MOVE]
		if seen.has(mkey):
			return false
		seen[mkey] = true
		return true
	if not (o.action in [Consts.Action.ATTACK, Consts.Action.ABILITY1,
			Consts.Action.ABILITY2, Consts.Action.ABILITY3, Consts.Action.ABILITY4]):
		return false

	# «Быстрая перезарядка» снимает дедуп ТОЛЬКО для способностей (не для базовой атаки): такой
	# герой может повторять один скилл в разных слотах. Ход дедупится выше и её не касается.
	var is_ability := o.action != Consts.Action.ATTACK
	var dedup := not (is_ability and u.repeats_abilities())
	var key := "%d:%d" % [o.hero_id, o.action]
	if dedup and seen.has(key):
		return false
	var def := HeroDefs.for_action(u.hero_type, o.action, u.skills, u.mana_discount)
	if def.passive:
		return false   # пассивку нельзя активировать
	if def.slot_gate.size() > 0 and not (slot in def.slot_gate):
		return false
	# Бегущий банк маны героя (лениво стартует с текущей маны). Прирост от Медитации в раннем слоте
	# уже учтён в банке к этому слоту — как и у резолвера, тратящего ману последовательно.
	var mana_now: int = bank.get(o.hero_id, u.mana)
	if mana_now < def.mana:
		return false
	# Отступление и Сходить несут путь (как ход), а не одиночное смещение — валидируем шаги
	var skill := HeroDefs.skill_of_action(u.hero_type, o.action, u.skills)
	if skill == Consts.Skill.RETREAT:
		if not _path_legal(o.path, Consts.RETREAT_RANGE):
			return false
	elif skill == Consts.Skill.STEP:
		if not _path_legal(o.path, Consts.STEP_RANGE):
			return false
	elif skill == Consts.Skill.MINEFIELD:
		# Минное поле несёт список офсетов мин в o.path (как путь — но это НЕ шаги, а цели).
		if not _minefield_legal(o.path):
			return false
	# Геометрию цели (форма/дальность смещения) сервер БОЛЬШЕ НЕ режет: её авторитетно проверяет
	# резолвер (Resolver._target_geometry_ok) и физзлит невозможное. Так игрок может запланировать
	# «невозможную» цель (опция «Разрешить выбирать невозможные цели») и онлайн — приказ доедет до
	# разрешения и просто не сработает, если по-прежнему нелегален. Здесь остаются лишь структурные
	# проверки (шаги хода/пути, мана, дубли, гейт слота, пассивка), которые резолвер не делает.

	if dedup:
		seen[key] = true
	bank[o.hero_id] = mana_now + def.mana_gain - def.mana   # нетто; прирост достаётся ПОЗДНИМ слотам
	return true


# Ход: последовательность единичных орто-шагов, не длиннее эффективной дальности героя.
static func _move_legal(path: Array, max_range: int) -> bool:
	if path.size() > max_range:
		return false
	for d in path:
		if typeof(d) != TYPE_VECTOR2I or not (d in Consts.DIRS4):
			return false
	return true


# Минное поле: 1..MINEFIELD_COUNT офсетов-целей, каждый в радиусе MINEFIELD_RADIUS (манхэттен),
# все различны (нельзя две мины в одну клетку). Проходимость/занятость — на резолве.
static func _minefield_legal(cells: Array) -> bool:
	if cells.size() < 1 or cells.size() > Consts.MINEFIELD_COUNT:
		return false
	var seen := {}
	for off in cells:
		if typeof(off) != TYPE_VECTOR2I:
			return false
		var man: int = absi(off.x) + absi(off.y)
		if man < 1 or man > Consts.MINEFIELD_RADIUS:
			return false
		if seen.has(off):
			return false
		seen[off] = true
	return true


# Путь-способность (Отступление/Сходить): непустой путь орто-шагов, не длиннее max_range.
static func _path_legal(path: Array, max_range: int) -> bool:
	if path.size() < 1 or path.size() > max_range:
		return false
	for d in path:
		if typeof(d) != TYPE_VECTOR2I or not (d in Consts.DIRS4):
			return false
	return true


# Форма и дальность цели. Зеркалит Targeting._basic_attack_cells / _ability_cells.
# Способности диспетчеризуются по id скилла из кита юнита, а не по индексу слота.
# Вызывается резолвером (Resolver._target_geometry_ok) — единый авторитет по геометрии цели.
static func _target_legal(u: Unit, action: int, off: Vector2i) -> bool:
	if action == Consts.Action.ATTACK:
		match u.hero_type:
			Consts.HeroType.HUNTER:    # Выстрел: прямая, 2-3 (Снайпер без движения — любая дальность)
				if u.has_skill(Consts.Skill.SNIPER) and not u.moved_last_round:
					return _ray(off) >= 2
				return _ray(off) >= 2 and _ray(off) <= 3
			Consts.HeroType.FAIRY:     # Удар: любой из 8 соседей
				return _cheb(off) == 1
			Consts.HeroType.CRYSTAL:   # Удар: орто-сосед
				return _man(off) == 1
		return false
	match HeroDefs.skill_of_action(u.hero_type, action, u.skills):
		Consts.Skill.TRAP:        # радиус 2 (манхэттен)
			return _man(off) >= 1 and _man(off) <= Consts.TRAP_RADIUS
		Consts.Skill.SNIPE:       # прямая, SNIPE_MIN..SNIPE_MAX
			return _ray(off) >= Consts.SNIPE_MIN and _ray(off) <= Consts.SNIPE_MAX
		Consts.Skill.SHOTGUN:     # соседняя диагональ
			return absi(off.x) == 1 and absi(off.y) == 1
		Consts.Skill.CANCEL:      # себе или рядом (Chebyshev 1)
			return _cheb(off) <= 1
		Consts.Skill.HEAL:        # радиус 2 (манхэттен)
			return _man(off) <= Consts.HEAL_RADIUS
		Consts.Skill.JUMP:        # через орто-соседа
			return _man(off) == 1
		Consts.Skill.DASH:        # по прямой
			return _ray(off) >= 1
		Consts.Skill.ONSLAUGHT:   # орто-сосед
			return _man(off) == 1
		Consts.Skill.OVERLOAD:    # орто-сосед
			return _man(off) == 1
		Consts.Skill.SWAP:        # соседний (8 сторон)
			return _cheb(off) == 1
		Consts.Skill.PRECISE:     # строго дальность PRECISE_RANGE
			return _man(off) == Consts.PRECISE_RANGE
		Consts.Skill.HUNT_MARK:   # по прямой (орто) линии, 1..HUNT_RANGE
			return _ray(off) >= 1 and _ray(off) <= Consts.HUNT_RANGE
		Consts.Skill.NET:         # в радиусе NET_RANGE
			return _man(off) >= 1 and _man(off) <= Consts.NET_RANGE
		Consts.Skill.BLEED:       # враг в радиусе BLEED_RANGE
			return _man(off) >= 1 and _man(off) <= Consts.BLEED_RANGE
		Consts.Skill.SPARK:       # цель на дальности до SPARK_RANGE
			return _man(off) >= 1 and _man(off) <= Consts.SPARK_RANGE
		Consts.Skill.LIGHTNING:   # цель на дальности до LIGHTNING_RANGE
			return _man(off) >= 1 and _man(off) <= Consts.LIGHTNING_RANGE
		Consts.Skill.DISORIENT:   # враг в радиусе DISORIENT_RANGE
			return _man(off) >= 1 and _man(off) <= Consts.DISORIENT_RANGE
		Consts.Skill.SHACKLES:    # враг в радиусе SHACKLES_RANGE
			return _man(off) >= 1 and _man(off) <= Consts.SHACKLES_RANGE
		Consts.Skill.SLOW:        # враг в радиусе SLOW_RANGE
			return _man(off) >= 1 and _man(off) <= Consts.SLOW_RANGE
		Consts.Skill.MANASTEAL:   # соседний (8 сторон)
			return _cheb(off) == 1
		Consts.Skill.TELEPORT:    # свободная клетка в радиусе TELEPORT_RANGE
			return _man(off) >= 1 and _man(off) <= Consts.TELEPORT_RANGE
		Consts.Skill.REVIVE:      # любая клетка (радиус не ограничен; могила проверяется в резолве)
			return off != Vector2i.ZERO
		Consts.Skill.PUSH:        # орто-сосед
			return _man(off) == 1
		Consts.Skill.SWAP_ALLY:   # соседний (8 сторон)
			return _cheb(off) == 1
		Consts.Skill.KNOCKDOWN:   # прямая, KNOCKDOWN_MIN..KNOCKDOWN_MAX
			return _ray(off) >= Consts.KNOCKDOWN_MIN and _ray(off) <= Consts.KNOCKDOWN_MAX
		Consts.Skill.GUST:        # юнит в радиусе GUST_RANGE (8 сторон)
			return _cheb(off) >= 1 and _cheb(off) <= Consts.GUST_RANGE
		Consts.Skill.HOOK:        # прямая, 1..HOOK_RANGE
			return _ray(off) >= 1 and _ray(off) <= Consts.HOOK_RANGE
		Consts.Skill.CALTROPS:    # клетка в радиусе CALTROPS_RANGE (манхэттен)
			return _man(off) >= 1 and _man(off) <= Consts.CALTROPS_RANGE
	return false


# Длина ОРТОГОНАЛЬНОГО смещения; 0 для нулевого и диагонального (т.е. «не по прямой»).
static func _ray(off: Vector2i) -> int:
	if (off.x == 0) == (off.y == 0):
		return 0
	return absi(off.x) + absi(off.y)


static func _man(off: Vector2i) -> int:
	return absi(off.x) + absi(off.y)


static func _cheb(off: Vector2i) -> int:
	return maxi(absi(off.x), absi(off.y))
