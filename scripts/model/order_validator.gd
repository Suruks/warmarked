class_name OrderValidator
extends RefCounted

## Авторитетная проверка легальности приказов. Вызывается СЕРВЕРОМ (MatchSession.submit)
## до того, как приказы попадут в резолвер и будут разосланы клиентам.
##
## Что проверяется здесь (то, что резолвер НЕ проверяет сам):
##   • ход — только единичные орто-шаги, не длиннее MOVE_RANGE (иначе телепорт сквозь стены);
##   • геометрия цели — форма и дальность по СМЕЩЕНИЮ (резолвер целит от текущей клетки,
##     поэтому смещение позиционно-независимо и валидируется без знания траектории);
##   • «один приказ не дважды за раунд» — включая Ход (герой не ходит в двух слотах);
##   • суммарная мана героя за раунд;
##   • гейт слотов (дублирует резолвер, но дешевле отсечь заранее).
##
## Что здесь НЕ проверяется: проходимость, LOS, занятость клеток. Это состояние на момент
## РАЗРЕШЕНИЯ, его считает резолвер — нелегальная по ситуации цель просто физзлит, ровно как
## и у честного клиента, чей план разошёлся с реальностью.


# Возвращает НОВЫЙ массив из ORDER_SLOTS приказов: нелегальные заменены на пустые.
static func sanitize(state: MatchState, orders: Array, player: int) -> Array:
	var out: Array = []
	var spent := {}   # hero_id -> уже зарезервировано маны
	var seen := {}    # "hero:action" -> скилл уже занят в другом слоте
	for i in Consts.ORDER_SLOTS:
		var o: Order = orders[i] if i < orders.size() else Order.empty()
		# Второй игрок раунда не действует в последнем слоте — срезаем в пустой приказ.
		var ok := state.acts_in_slot(player, i) and _slot_legal(state, o, player, i, spent, seen)
		out.append(o if ok else Order.empty())
	return out


# Побочный эффект: при легальном приказе резервирует ману и помечает скилл использованным.
static func _slot_legal(state: MatchState, o: Order, player: int, slot: int, spent: Dictionary, seen: Dictionary) -> bool:
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
			Consts.Action.ABILITY2, Consts.Action.ABILITY3]):
		return false

	var key := "%d:%d" % [o.hero_id, o.action]
	if seen.has(key):
		return false
	var def := HeroDefs.for_action(u.hero_type, o.action, u.skills)
	if def.passive:
		return false   # пассивку нельзя активировать
	if def.slot_gate.size() > 0 and not (slot in def.slot_gate):
		return false
	var used: int = spent.get(o.hero_id, 0)
	if used + def.mana > u.mana:
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
	elif def.target != HeroDefs.Target.NONE and not _target_legal(u, o.action, _offset(u, o)):
		return false

	seen[key] = true
	spent[o.hero_id] = used + def.mana
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


# Смещение цели от той клетки, из которой резолвер будет целиться.
static func _offset(u: Unit, o: Order) -> Vector2i:
	return o.offset if o.relative else o.target - u.cell


# Форма и дальность цели. Зеркалит Targeting._basic_attack_cells / _ability_cells.
# Способности диспетчеризуются по id скилла из кита юнита, а не по индексу слота.
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
		Consts.Skill.HUNT_MARK:   # в радиусе HUNT_RANGE
			return _man(off) >= 1 and _man(off) <= Consts.HUNT_RANGE
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
