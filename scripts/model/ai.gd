class_name AI
extends RefCounted

## Жадный эвристический бот (без предвидения залпа соперника). Не играет на равных —
## задача скромнее: «не творить фигню». Бьёт, когда есть кого бить; добивает раненых;
## лезет на точки контроля; ставит защиту/лечит, когда это осмысленно; не сливает ману
## в пустоту (нет цели → слот остаётся пустым, мана копится сама).
##
## Как работает: для каждого слота перебирает все легальные (юнит, действие, цель),
## КАЖДЫЙ вариант реально прогоняет через настоящий Resolver на клоне состояния
## (соперник пассивен — слепое допущение) и берёт максимум по оценке результата.
## Выбранный приказ фиксируется, следующий слот планируется поверх него. Так правила
## считает сам движок (реальный урон/киллы/щиты), а не отдельная копия формул.

const _EPS := 0.5   # действие берём, только если оно ощутимо лучше «оставить слот пустым»

# Веса оценки (крутибельные). Килл доминирует через разницу счёта (KILL_POINTS→+1 очко).
const _W_SCORE := 1000.0
const _W_MY_HP := 8.0
const _W_MY_MANA := 4.0
const _W_ENEMY_HP := 6.0
const _W_ENEMY_MANA := 2.0
const _W_MY_DEAD := 50.0     # ×dead_timer
const _W_ENEMY_DEAD := 150.0
const _W_CONTROL := 300.0    # за КАЖДУЮ удерживаемую точку сверх соперника (это и есть очки/раунд)
const _CP_ON := 30.0         # стоять на точке (сближение)
const _CP_NEAR := 12.0       # градиент притяжения к точке: _CP_NEAR/(1+dist)


# Главный вход: набор из ORDER_SLOTS приказов за игрока player. Не мутирует state.
static func plan(state: MatchState, player: int) -> Array:
	var resolver := Resolver.new()
	var orders := Order.empty_slots()
	for slot in Consts.ORDER_SLOTS:
		# второй игрок раунда не действует в последнем слоте — там приказ всё равно срежется
		if not state.acts_in_slot(player, slot):
			continue
		var work := _project(state, orders, player, resolver)   # позиции/мана после уже выбранных слотов
		var baseline := _score_orders(state, orders, player, resolver)
		var best_order: Order = null
		var best_score := baseline + _EPS
		for u in work.units_of(player):
			if not u.alive:
				continue
			for cand in _unit_candidates(work, u, slot):
				var trial: Array = orders.duplicate()   # мелкая копия: меняем только [slot]
				trial[slot] = cand
				var sane := OrderValidator.sanitize(state, trial, player)
				if sane[slot].is_empty():
					continue   # нелегально по мане/«скилл не дважды»/геометрии
				var sc := _score_orders(state, sane, player, resolver) + _shaping(work, u, cand)
				if sc > best_score:
					best_score = sc
					best_order = sane[slot]
		if best_order != null:
			orders[slot] = best_order
	return OrderValidator.sanitize(state, orders, player)


# --- прогон и оценка -------------------------------------------------------

# Состояние после применения УЖЕ выбранных приказов (соперник пуст): даёт актуальные
# позиции/ману для генерации кандидатов следующего слота.
static func _project(state: MatchState, orders: Array, player: int, resolver: Resolver) -> MatchState:
	var s := state.clone()
	var oa: Array = orders if player == Consts.Player.A else Order.empty_slots()
	var ob: Array = orders if player == Consts.Player.B else Order.empty_slots()
	resolver.resolve(s, oa, ob, player)   # first=player → все мои слоты применяются
	return s


static func _score_orders(state: MatchState, orders: Array, player: int, resolver: Resolver) -> float:
	var s := state.clone()
	var oa: Array = orders if player == Consts.Player.A else Order.empty_slots()
	var ob: Array = orders if player == Consts.Player.B else Order.empty_slots()
	resolver.resolve(s, oa, ob, player)
	return _evaluate(s, player)


static func _evaluate(s: MatchState, me: int) -> float:
	var opp := Consts.other_player(me)
	var v := _W_SCORE * float(s.score[me] - s.score[opp])
	# Материал/ресурс/жизни
	for u in s.units:
		var mine := u.owner == me
		if u.alive:
			if mine:
				v += _W_MY_HP * u.hp + _W_MY_MANA * u.mana
			else:
				v -= _W_ENEMY_HP * u.hp + _W_ENEMY_MANA * u.mana
		else:
			if mine:
				v -= _W_MY_DEAD * maxi(1, u.dead_timer)
			else:
				v += _W_ENEMY_DEAD
	# Контроль территории: считаем РАЗНЫЕ удерживаемые точки (это и есть очко/раунд), а не
	# близость каждого юнита — иначе весь отряд липнет к одной точке. Плюс мягкий градиент,
	# ведущий свободных юнитов к точкам, которые союзник ещё НЕ держит (чтобы расходились).
	var held_me := 0
	var held_opp := 0
	for cp in s.board.control_points:
		var occ := s.unit_at(cp)
		if occ != null:
			if occ.owner == me:
				held_me += 1
			else:
				held_opp += 1
	v += _W_CONTROL * float(held_me - held_opp)
	for u in s.units:
		if u.alive and u.owner == me:
			v += _approach_term(s, u, me)
	return v


# Мягкое притяжение юнита к ближайшей точке, которую МОЙ отряд ещё не держит (на точке —
# максимум). Так юниты не сбиваются в кучу на одной точке, а разбирают разные.
static func _approach_term(s: MatchState, u: Unit, me: int) -> float:
	if s.board.is_control_point(u.cell):
		return _CP_ON
	var best := 0.0
	for cp in s.board.control_points:
		var occ := s.unit_at(cp)
		if occ != null and occ.owner == me:
			continue   # союзник уже держит — веду этого юнита к другой
		var d: int = absi(u.cell.x - cp.x) + absi(u.cell.y - cp.y)
		best = maxf(best, _CP_NEAR / float(1 + d))
	return best


# --- шейпинг защитных стоек (оценка их не видит: соперник в просчёте пассивен) --------

static func _shaping(work: MatchState, u: Unit, cand: Order) -> float:
	if cand.action == Consts.Action.MOVE or cand.action == Consts.Action.ATTACK \
			or cand.action == Consts.Action.EMPTY:
		return 0.0
	var skill := HeroDefs.skill_of_action(u.hero_type, cand.action, u.skills)
	match skill:
		Consts.Skill.MEDITATION:
			return 6.0 if u.mana <= 1 else -8.0
		Consts.Skill.BLOCK, Consts.Skill.HARDENING, Consts.Skill.SHARDS, Consts.Skill.REFLEXES:
			return 18.0 if (_threatened(work, u) and u.hp <= u.max_hp * 0.6) else -12.0
		Consts.Skill.CANCEL:
			var ally := work.unit_at(u.cell + cand.offset)
			if ally == null or ally.owner != u.owner:
				return -30.0
			return 18.0 if (_threatened(work, ally) and ally.hp <= ally.max_hp * 0.6) else -12.0
	return 0.0


# Есть ли живой враг в опасной близости (грубый радиус угрозы).
static func _threatened(s: MatchState, target: Unit) -> bool:
	for e in s.units:
		if e.alive and e.owner != target.owner \
				and absi(e.cell.x - target.cell.x) + absi(e.cell.y - target.cell.y) <= 3:
			return true
	return false


# --- генерация кандидатов для одного юнита в одном слоте ----------------------

static func _unit_candidates(work: MatchState, u: Unit, slot: int) -> Array:
	var out: Array = []
	# Ход
	var paths := Targeting.move_paths(work, u.cell, u.id, {}, u.move_range())
	for dest in paths:
		var steps := _to_steps(u.cell, paths[dest])
		if not steps.is_empty():
			out.append(Order.make_move(u.id, steps))
	# Базовая атака
	for c in Targeting.candidates(work, u, Consts.Action.ATTACK, u.cell):
		out.append(_targeted(u, Consts.Action.ATTACK, c))
	# Способности (3 слота кита, либо 4 у бойца с бонусной способностью — Difficulty)
	for i in u.skills.size():
		var action := Consts.Action.ABILITY1 + i
		var def := HeroDefs.for_action(u.hero_type, action, u.skills, u.mana_discount)
		if def.passive:
			continue
		if def.slot_gate.size() > 0 and not (slot in def.slot_gate):
			continue
		var skill: int = u.skills[i]
		if skill == Consts.Skill.RETREAT or skill == Consts.Skill.STEP:
			var rng: int = Consts.RETREAT_RANGE if skill == Consts.Skill.RETREAT else Consts.STEP_RANGE
			var pp := Targeting.move_paths(work, u.cell, u.id, {}, rng)
			for dest in pp:
				var steps := _to_steps(u.cell, pp[dest])
				if not steps.is_empty():
					var o := Order.new(u.id, action)
					o.path = steps
					out.append(o)
		elif skill == Consts.Skill.MINEFIELD:
			# по одной мине на клетку-кандидат (легально: 1..MINEFIELD_COUNT)
			for c in Targeting.candidates(work, u, action, u.cell):
				var o := Order.new(u.id, action)
				o.relative = true
				o.offset = c - u.cell
				o.path = [c - u.cell] as Array[Vector2i]
				o.target = c
				out.append(o)
		elif def.target == HeroDefs.Target.NONE:
			out.append(Order.new(u.id, action))   # нон-таргет (Вспышка/Засада/стойки и т.п.)
		else:
			for c in Targeting.candidates(work, u, action, u.cell):
				out.append(_targeted(u, action, c))
	return out


# Нацеленный приказ: смещение цели от текущей клетки (как в панели планирования).
static func _targeted(u: Unit, action: int, cell: Vector2i) -> Order:
	return Order.make(u.id, action, cell, cell - u.cell, true)


# Абсолютный путь (клетки без origin) → шаги-смещения (dx,dy), как ждёт резолвер/валидатор.
static func _to_steps(origin: Vector2i, abs_path: Array) -> Array:
	var steps: Array[Vector2i] = []
	var prev := origin
	for c in abs_path:
		steps.append(c - prev)
		prev = c
	return steps
