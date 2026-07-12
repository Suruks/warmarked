class_name Resolver
extends RefCounted

## Детерминированное разрешение раунда. Мутирует MatchState, возвращает список событий
## (каждое несёт snapshot состояния для пошагового плейбека). Чистая логика, без узлов.
##
## Порядок (§4): i=1..4 -> сначала слот[i] первого игрока полностью, потом второго.
## No-retarget: цель — фиксированная клетка; действие бьёт того, кто на ней (друг ИЛИ враг),
## либо физзлит в пустоту.


# Главный вход: orders_a / orders_b — массивы из ORDER_SLOTS штук Order.
func resolve(state: MatchState, orders_a: Array, orders_b: Array, first_player: int) -> Array:
	var events: Array = []
	var second := Consts.other_player(first_player)
	var of := orders_a if first_player == Consts.Player.A else orders_b
	var os := orders_a if second == Consts.Player.A else orders_b
	_push(events, state, Consts.EventType.INFO,
		"Раунд %d — первым ходит игрок %s" % [state.round_num, Consts.player_name(first_player)])
	for i in Consts.ORDER_SLOTS:
		_push(events, state, Consts.EventType.INFO, "— Слот %d —" % (i + 1))
		_resolve_slot(state, of[i], first_player, i, events)
		# Второй игрок не действует в ПОСЛЕДНЕМ слоте: действия строго чередуются, и на стыке
		# раундов никто не ходит дважды подряд (первый доигрывает раунд, второй начинает следующий).
		if i < Consts.ORDER_SLOTS - 1:
			_resolve_slot(state, os[i], second, i, events)
	return events


func _resolve_slot(state: MatchState, order: Order, player: int, slot: int, events: Array) -> void:
	if order == null or order.is_empty():
		return
	var unit := state.get_unit(order.hero_id)
	if unit == null or not unit.alive:
		_push(events, state, Consts.EventType.FIZZLE, "Приказ игрока %s: юнит недоступен (мёртв)" % Consts.player_name(player))
		return
	match order.action:
		Consts.Action.MOVE:
			_do_move(state, unit, order.path, events)
		Consts.Action.ATTACK:
			_do_basic_attack(state, unit, order, events)
		Consts.Action.ABILITY1, Consts.Action.ABILITY2, Consts.Action.ABILITY3:
			_do_ability(state, unit, order, slot, events)


# ---------------------------------------------------------------- движение

func _do_move(state: MatchState, unit: Unit, path: Array, events: Array) -> void:
	# path — шаги-смещения; применяем от ТЕКУЩЕЙ клетки (относительное движение: если юнита
	# отбросило/сместило до его хода, план применяется от новой позиции).
	#
	# Союзники НЕ блокируют движение: сквозь них проходят насквозь, но встать на их клетку
	# нельзя (две фигуры не стоят на одной клетке). Враги блокируют полностью.
	# Транзитные клетки не считаются «входом», поэтому капканы/засады на них не срабатывают.
	if unit.immobilized:
		_push(events, state, Consts.EventType.FIZZLE, "%s обездвижен — ход отменён" % unit.full_name())
		return
	# Замедление: дальность хода снижена — лишние шаги пути отбрасываются
	var p: Array = path
	if unit.slow_turns > 0:
		var cap := Consts.MOVE_RANGE - Consts.SLOW_MOVE_PENALTY
		if p.size() > cap:
			p = p.slice(0, cap)
	_walk_path(state, unit, p, events)


# Проход по относительному пути шагов-смещений (общий для Хода и Отступления).
func _walk_path(state: MatchState, unit: Unit, path: Array, events: Array) -> void:
	var start := unit.cell
	var cur := unit.cell
	for i in path.size():
		var next: Vector2i = cur + path[i]
		if not state.board.is_passable(next):
			_push(events, state, Consts.EventType.INFO,
				"%s: ход заблокирован на (%d,%d)" % [unit.full_name(), next.x, next.y])
			break
		var occupant := state.unit_at(next)
		if occupant != null and occupant.id != unit.id:
			if occupant.owner != unit.owner:
				_push(events, state, Consts.EventType.INFO,
					"%s: ход заблокирован на (%d,%d)" % [unit.full_name(), next.x, next.y])
				break
			if i == path.size() - 1:
				_push(events, state, Consts.EventType.INFO,
					"%s: на (%d,%d) стоит союзник — негде встать" % [unit.full_name(), next.x, next.y])
				break
			cur = next   # проходим сквозь союзника, клетку не занимаем
			continue
		cur = next
		# шаги хода не тикают кровавый след по отдельности — тик один раз за всё перемещение (ниже)
		_enter(state, unit, cur, events, unit.owner, Consts.EventType.MOVE,
			"%s -> (%d,%d)" % [unit.full_name(), cur.x, cur.y], false)
		if not unit.alive:
			return   # погиб в пути (капкан) — тик кровотечения уже неактуален
		if unit.immobilized:   # наступил на капкан посреди пути — застрял здесь, дальше не идёт
			break
	# Кровавый след: одно перемещение-действие = один тик, если юнит реально сдвинулся
	if unit.cell != start:
		_bleed_tick(state, unit, events)


# Перемещает юнита на клетку, логирует и проверяет капканы/засады
# tick_bleed=false для отдельных шагов многоклеточного хода — кровавый след тикает раз за
# ВСЁ перемещение-действие (см. _walk_path), а не за каждую клетку.
func _enter(state: MatchState, unit: Unit, cell: Vector2i, events: Array, src_player: int, ev_type: int, text: String, tick_bleed: bool = true) -> void:
	unit.cell = cell
	_push(events, state, ev_type, text, {"actor": unit.id, "to_cell": cell})
	_check_triggers(state, unit, cell, events, src_player)
	if tick_bleed:
		_bleed_tick(state, unit, events)


# Кровавый след: одно перемещение-действие помеченного юнита наносит ему BLEED_DMG
func _bleed_tick(state: MatchState, unit: Unit, events: Array) -> void:
	if unit.alive and unit.bleed_turns > 0:
		_deal_damage(state, unit, Consts.BLEED_DMG, unit.bleed_owner, events, "кровотечение")


func _check_triggers(state: MatchState, unit: Unit, cell: Vector2i, events: Array, _src_player: int) -> void:
	# Капканы: срабатывают на вход ВРАГА владельца капкана
	for t in state.traps.duplicate():
		if t.cell == cell and t.owner_player != unit.owner:
			state.traps.erase(t)
			_push(events, state, Consts.EventType.TRAP_TRIGGER,
				"Капкан! %s наступает на (%d,%d)" % [unit.full_name(), cell.x, cell.y])
			# щит гасит капкан целиком (и урон, и обездвиживание) — это один эффект
			if unit.shield_armed:
				unit.shield_armed = false
				_push(events, state, Consts.EventType.SHIELD_ABSORB,
					"Щит %s поглотил капкан (урон и обездвиживание)" % unit.full_name())
			else:
				unit.immobilized = true   # замер СРАЗУ: гасит остаток движения в этом же раунде
				_deal_damage(state, unit, Consts.TRAP_DMG, t.owner_player, events, "капкан",
					state.get_unit(t.owner_id))
			if not unit.alive:
				return
	# Засады: срабатывают, когда ВРАЖЕСКИЙ юнит входит рядом с Кристалкайндом
	# (как и капкан — по своим не бьёт; owner.id == unit.id покрыт проверкой владельца)
	for a in state.ambushes.duplicate():
		var owner := state.get_unit(a.owner_id)
		if owner == null or not owner.alive or owner.owner == unit.owner:
			continue
		if _cheb(owner.cell, cell) == 1:
			state.ambushes.erase(a)
			_push(events, state, Consts.EventType.AMBUSH_TRIGGER,
				"Засада %s! %s входит рядом" % [owner.full_name(), unit.full_name()])
			_deal_damage(state, unit, Consts.AMBUSH_DMG, owner.owner, events, "засада", owner)
			if not unit.alive:
				return


# Толчок на 1 клетку в направлении dir; в препятствие/край/юнит -> столкновение (урон)
func _knockback(state: MatchState, unit: Unit, dir: Vector2i, src_player: int, events: Array) -> void:
	if dir == Vector2i.ZERO:
		return
	var dest := unit.cell + dir
	var occupant := state.unit_at(dest)
	if not state.board.is_passable(dest) or occupant != null:
		_push(events, state, Consts.EventType.COLLISION,
			"%s впечатан в препятствие -> %d урона" % [unit.full_name(), Consts.COLLISION_DMG],
			{"victim": unit.id})
		_deal_damage(state, unit, Consts.COLLISION_DMG, src_player, events, "столкновение")
	else:
		_enter(state, unit, dest, events, src_player, Consts.EventType.KNOCKBACK,
			"%s отброшен на (%d,%d)" % [unit.full_name(), dest.x, dest.y])


# ---------------------------------------------------------------- урон / смерть

# src_unit — юнит-источник урона (нужен Осколкам для ответки); для средовых источников
# (столкновение о стену) — null. retaliate=false у самой ответки, чтобы шипы не зациклились.
func _deal_damage(state: MatchState, target: Unit, amount: int, src_player: int, events: Array, label: String,
		src_unit: Unit = null, retaliate: bool = true) -> void:
	var dmg := amount
	# «Охота началась»: урон Охотника по помеченной цели умножается
	if target.hunted and src_unit != null and src_unit.hero_type == Consts.HeroType.HUNTER:
		dmg *= Consts.HUNT_MULT
	if target.hero_type == Consts.HeroType.CRYSTAL:
		dmg = max(0, dmg - Consts.CRYSTAL_PASSIVE_REDUCTION)
	if dmg <= 0:
		_push(events, state, Consts.EventType.DAMAGE,
			"%s: пассив свёл урон к 0 (%s)" % [target.full_name(), label])
		return
	# Затвердение срезает урон на HARDENING_REDUCTION в этом раунде и не тратится (в отличие
	# от разового щита); срезал в ноль -> полностью поглотил
	if target.hardened:
		dmg = max(0, dmg - Consts.HARDENING_REDUCTION)
		if dmg <= 0:
			_push(events, state, Consts.EventType.HARDEN_BLOCK,
				"Затвердение %s поглотило удар (%s)" % [target.full_name(), label])
			return
	if target.shield_armed:
		target.shield_armed = false
		_push(events, state, Consts.EventType.SHIELD_ABSORB,
			"Щит %s поглотил %d урона (%s)" % [target.full_name(), dmg, label])
		return
	target.hp -= dmg
	_push(events, state, Consts.EventType.DAMAGE,
		"%s получает %d (%s) -> HP %d/%d" % [target.full_name(), dmg, label, max(target.hp, 0), target.max_hp],
		{"victim": target.id, "amount": dmg})   # amount — для всплывающей цифры в UI
	# Осколки: враг, реально нанёсший урон, получает ответку (даже если жертва погибла)
	if retaliate and target.shards_armed and src_unit != null and src_unit.alive \
			and src_unit.owner != target.owner:
		_deal_damage(state, src_unit, Consts.SHARDS_DMG, target.owner, events, "осколки", target, false)
	if target.hp <= 0:
		_kill(state, target, src_player, events)


func _kill(state: MatchState, target: Unit, src_player: int, events: Array) -> void:
	target.alive = false
	var died_at := target.cell
	target.death_cell = died_at
	target.dead_timer = Consts.RESPAWN_DELAY
	# Могила — это МАРКЕР ВОСКРЕШЕНИЯ: ставим её в клетку, где герой поднимется, а не туда,
	# где его убили. Оба игрока заранее видят, где и через сколько он вернётся (открытая инфа).
	var rc := state.respawn_cell_for(target)
	target.cell = rc if rc.x >= 0 else died_at
	# снять засаду убитого
	var kept: Array = []
	for a in state.ambushes:
		if a.owner_id != target.id:
			kept.append(a)
	state.ambushes = kept
	_push(events, state, Consts.EventType.DEATH,
		"%s погибает на (%d,%d)" % [target.full_name(), died_at.x, died_at.y])
	if src_player != target.owner:
		state.add_score(src_player, Consts.KILL_POINTS)
		_push(events, state, Consts.EventType.KILL,
			"+%d очка игроку %s за килл" % [Consts.KILL_POINTS, Consts.player_name(src_player)])


# ---------------------------------------------------------------- базовые атаки

# Эффективная цель: смещение цели от текущей клетки. При дезориентации ПЕРВЫЙ направленный
# (ненулевое смещение) скилл/атака юнита разворачивается, флаг снимается (одноразово).
func _eff_target(state: MatchState, unit: Unit, order: Order, events: Array) -> Vector2i:
	var off: Vector2i = order.offset if order.relative else (order.target - unit.cell)
	if unit.disoriented and off != Vector2i.ZERO:
		unit.disoriented = false
		off = -off
		_push(events, state, Consts.EventType.DISORIENT_TRIGGER,
			"%s дезориентирован — направление действия развёрнуто" % unit.full_name())
	return unit.cell + off


func _do_basic_attack(state: MatchState, unit: Unit, order: Order, events: Array) -> void:
	if unit.no_attack_turns > 0:
		_push(events, state, Consts.EventType.FIZZLE,
			"%s скован — базовая атака недоступна" % unit.full_name())
		return
	var et := _eff_target(state, unit, order, events)
	_check_reflexes(state, unit, et, events)   # цель могла увернуться — тогда бьём в пустоту
	var dmg := 0
	var victim: Unit
	match unit.hero_type:
		Consts.HeroType.HUNTER:
			dmg = Consts.HUNTER_ATK_DMG
			victim = _first_unit_on_line(state, unit.cell, et)   # пуля бьёт первого на линии
		Consts.HeroType.FAIRY:
			dmg = Consts.FAIRY_ATK_DMG
			victim = state.unit_at(et)
		Consts.HeroType.CRYSTAL:
			dmg = Consts.CRYSTAL_ATK_DMG
			victim = state.unit_at(et)
	if victim == null:
		_push(events, state, Consts.EventType.FIZZLE,
			"%s бьёт по пустой клетке (%d,%d)" % [unit.full_name(), et.x, et.y])
		return
	_push(events, state, Consts.EventType.ATTACK,
		"%s атакует %s" % [unit.full_name(), victim.full_name()],
		{"actor": unit.id, "target_cell": et})
	_deal_damage(state, victim, dmg, unit.owner, events, "атака", unit)


# ---------------------------------------------------------------- способности

func _do_ability(state: MatchState, unit: Unit, order: Order, slot: int, events: Array) -> void:
	var idx := order.action - Consts.Action.ABILITY1  # 0..2
	var skill: int = unit.skills[idx]
	var def := HeroDefs.skill_def(skill)
	if def.slot_gate.size() > 0 and not (slot in def.slot_gate):
		_push(events, state, Consts.EventType.FIZZLE,
			"%s: %s недоступна в этом слоте" % [unit.full_name(), def.name])
		return
	# Обездвиженный не может применять скиллы, двигающие его самого (Прыжок/Рывок/Натиск) —
	# как и обычный ход, они физзлят. Фиксируем ДО списания маны (иначе штраф за то, что нельзя было).
	if unit.immobilized and _skill_moves_caster(skill):
		_push(events, state, Consts.EventType.FIZZLE,
			"%s обездвижен — %s невозможен" % [unit.full_name(), def.name])
		return
	if unit.mana < def.mana:
		_push(events, state, Consts.EventType.FIZZLE,
			"%s: не хватает маны на %s" % [unit.full_name(), def.name])
		return
	unit.mana -= def.mana
	var et := _eff_target(state, unit, order, events)
	_push(events, state, Consts.EventType.ABILITY,
		"%s использует %s" % [unit.full_name(), def.name],
		{"actor": unit.id, "target_cell": et})
	# Нацеленный скилл соседа даёт жертве шанс на рефлексы — до того, как эффект применится
	if def.target != HeroDefs.Target.NONE:
		_check_reflexes(state, unit, et, events)
	match skill:
		Consts.Skill.TRAP: _sk_trap(state, unit, et, events)
		Consts.Skill.SNIPE: _sk_snipe(state, unit, et, events)
		Consts.Skill.SHOTGUN: _sk_shotgun(state, unit, et, events)
		Consts.Skill.PRECISE: _sk_precise(state, unit, et, events)
		Consts.Skill.HUNT_MARK: _sk_hunt(state, unit, et, events)
		Consts.Skill.RETREAT: _sk_retreat(state, unit, order, events)
		Consts.Skill.NET: _sk_net(state, unit, et, events)
		Consts.Skill.DEATHCROSS: _sk_deathcross(state, unit, events)
		Consts.Skill.MINEFIELD: _sk_minefield(state, unit, et, events)
		Consts.Skill.BLEED: _sk_bleed(state, unit, et, events)
		Consts.Skill.CANCEL: _sk_cancel(state, unit, et, events)
		Consts.Skill.HEAL: _sk_heal(state, unit, et, events)
		Consts.Skill.FLASH: _sk_flash(state, unit, events)
		Consts.Skill.SPARK: _sk_spark(state, unit, et, events)
		Consts.Skill.DISORIENT: _sk_disorient(state, unit, et, events)
		Consts.Skill.MANASTEAL: _sk_manasteal(state, unit, et, events)
		Consts.Skill.SHACKLES: _sk_shackles(state, unit, et, events)
		Consts.Skill.SLOW: _sk_slow(state, unit, et, events)
		Consts.Skill.TELEPORT: _sk_teleport(state, unit, et, events)
		Consts.Skill.REVIVE: _sk_revive(state, unit, et, events)
		Consts.Skill.JUMP: _sk_jump(state, unit, et, events)
		Consts.Skill.AMBUSH: _sk_ambush(state, unit, events)
		Consts.Skill.DASH: _sk_dash(state, unit, et, events)
		Consts.Skill.ONSLAUGHT: _sk_onslaught(state, unit, et, events)
		Consts.Skill.SPIKES: _sk_spikes(state, unit, events)
		Consts.Skill.REFLEXES: _sk_reflexes(state, unit, events)
		Consts.Skill.HARDENING: _sk_hardening(state, unit, events)
		Consts.Skill.SHARDS: _sk_shards(state, unit, events)
		Consts.Skill.OVERLOAD: _sk_overload(state, unit, et, events)
		Consts.Skill.SWAP: _sk_swap(state, unit, et, events)


# Капкан — не ставится в занятую юнитом или могилой клетку
func _sk_trap(state: MatchState, unit: Unit, et: Vector2i, events: Array) -> void:
	if state.unit_at(et) != null or state.grave_at(et):
		_push(events, state, Consts.EventType.FIZZLE,
			"Капкан не поставлен: клетка (%d,%d) занята" % [et.x, et.y])
		return
	state.traps.append({
		"cell": et,
		"owner_player": unit.owner,
		"owner_id": unit.id,
		"expire_round": state.round_num + Consts.PERSIST_ROUNDS,
	})
	_push(events, state, Consts.EventType.TRAP_PLACED,
		"Капкан установлен на (%d,%d)" % [et.x, et.y])


# Снайп — пуля бьёт первого на линии (заблокируется тем, кто встал на пути)
func _sk_snipe(state: MatchState, unit: Unit, et: Vector2i, events: Array) -> void:
	var v := _first_unit_on_line(state, unit.cell, et)
	if v == null:
		_push(events, state, Consts.EventType.FIZZLE, "Снайп в пустоту (%d,%d)" % [et.x, et.y])
		return
	_deal_damage(state, v, Consts.SNIPE_DMG, unit.owner, events, "снайп", unit)


# Дробь — квадрат 2x2 по диагонали (диагональ + две ортогональные к стрелку)
func _sk_shotgun(state: MatchState, unit: Unit, et: Vector2i, events: Array) -> void:
	var dir := _dir_sign(et - unit.cell)
	var cells := [
		unit.cell + dir,                    # диагональная клетка
		unit.cell + Vector2i(dir.x, 0),     # ортогональная по X
		unit.cell + Vector2i(0, dir.y),     # ортогональная по Y
	]
	for c in cells:
		var v := state.unit_at(c)
		if v == null:
			continue
		_deal_damage(state, v, Consts.SHOTGUN_DMG, unit.owner, events, "дробь", unit)
		if v.alive:
			_knockback(state, v, _dir_sign(v.cell - unit.cell), unit.owner, events)


# Меткий выстрел — прямое попадание строго по клетке на дальности PRECISE_RANGE (не перехватывается блокером)
func _sk_precise(state: MatchState, unit: Unit, et: Vector2i, events: Array) -> void:
	if _manhattan(unit.cell, et) != Consts.PRECISE_RANGE:
		_push(events, state, Consts.EventType.FIZZLE, "Меткий выстрел: цель не на дальности %d" % Consts.PRECISE_RANGE)
		return
	var v := state.unit_at(et)
	if v == null:
		_push(events, state, Consts.EventType.FIZZLE, "Меткий выстрел в пустоту (%d,%d)" % [et.x, et.y])
		return
	_deal_damage(state, v, Consts.PRECISE_DMG, unit.owner, events, "меткий выстрел", unit)


# Охота началась — метка на враге: урон Охотника по нему умножается до конца раунда
func _sk_hunt(state: MatchState, unit: Unit, et: Vector2i, events: Array) -> void:
	var v := state.unit_at(et)
	if v == null or v.owner == unit.owner:
		_push(events, state, Consts.EventType.FIZZLE, "Охота началась: на (%d,%d) нет врага" % [et.x, et.y])
		return
	v.hunted = true
	_push(events, state, Consts.EventType.HUNT_MARKED,
		"%s начинает охоту на %s (×%d урона)" % [unit.full_name(), v.full_name(), Consts.HUNT_MULT])


# Отступление — если рядом враг, пройти относительный путь (как ход). Обездвиживание уже
# отсекается в _do_ability (RETREAT в _skill_moves_caster), поэтому здесь только предусловие «враг рядом».
func _sk_retreat(state: MatchState, unit: Unit, order: Order, events: Array) -> void:
	if not _enemy_adjacent(state, unit):
		_push(events, state, Consts.EventType.FIZZLE, "Отступление: рядом нет врага")
		return
	_walk_path(state, unit, order.path, events)


# Ловчая сеть — мгновенно обездвиживает вражескую цель до конца раунда, без урона
func _sk_net(state: MatchState, unit: Unit, et: Vector2i, events: Array) -> void:
	var v := state.unit_at(et)
	if v == null or v.owner == unit.owner:
		_push(events, state, Consts.EventType.FIZZLE, "Ловчая сеть: на (%d,%d) нет врага" % [et.x, et.y])
		return
	v.immobilized = true
	_push(events, state, Consts.EventType.IMMOBILIZE, "%s опутан сетью — обездвижен" % v.full_name())


# Крест смерти — DEATHCROSS_DMG первому ВРАГУ на каждой из 4 ортогональных линий (союзник блокирует луч)
func _sk_deathcross(state: MatchState, unit: Unit, events: Array) -> void:
	var hit := false
	for d in Consts.DIRS4:
		var v := _first_unit_on_ray(state, unit.cell, d)
		if v != null and v.owner != unit.owner:
			hit = true
			_deal_damage(state, v, Consts.DEATHCROSS_DMG, unit.owner, events, "крест смерти", unit)
	if not hit:
		_push(events, state, Consts.EventType.FIZZLE, "Крест смерти: на линиях нет врагов")


# Минное поле — ставит MINEFIELD_COUNT капканов в радиусе MINEFIELD_RADIUS вокруг цели за один слот
func _sk_minefield(state: MatchState, unit: Unit, et: Vector2i, events: Array) -> void:
	var placed := 0
	for dy in range(-Consts.MINEFIELD_RADIUS, Consts.MINEFIELD_RADIUS + 1):
		for dx in range(-Consts.MINEFIELD_RADIUS, Consts.MINEFIELD_RADIUS + 1):
			if placed >= Consts.MINEFIELD_COUNT:
				break
			if absi(dx) + absi(dy) > Consts.MINEFIELD_RADIUS:
				continue
			var c := et + Vector2i(dx, dy)
			if not state.board.is_passable(c) or state.unit_at(c) != null \
					or state.grave_at(c) or _trap_at(state, c):
				continue
			state.traps.append({
				"cell": c, "owner_player": unit.owner, "owner_id": unit.id,
				"expire_round": state.round_num + Consts.PERSIST_ROUNDS,
			})
			placed += 1
			_push(events, state, Consts.EventType.TRAP_PLACED, "Мина на (%d,%d)" % [c.x, c.y])
	if placed == 0:
		_push(events, state, Consts.EventType.FIZZLE, "Минное поле: некуда ставить капканы")


# Кровавый след — метка на враге в радиусе BLEED_RANGE: каждое его перемещение будет бить (см. _enter)
func _sk_bleed(state: MatchState, unit: Unit, et: Vector2i, events: Array) -> void:
	var v := state.unit_at(et)
	if v == null or v.owner == unit.owner:
		_push(events, state, Consts.EventType.FIZZLE, "Кровавый след: на (%d,%d) нет врага" % [et.x, et.y])
		return
	v.bleed_turns = Consts.BLEED_TURNS
	v.bleed_owner = unit.owner
	_push(events, state, Consts.EventType.BLEED_MARKED,
		"%s оставляет кровавый след на %s (%d хода)" % [unit.full_name(), v.full_name(), Consts.BLEED_TURNS])


# Отмена — щит себе или соседнему союзнику
func _sk_cancel(state: MatchState, unit: Unit, et: Vector2i, events: Array) -> void:
	var target := state.unit_at(et)
	if target == null or target.owner != unit.owner:
		_push(events, state, Consts.EventType.FIZZLE,
			"Отмена: нет союзника на (%d,%d)" % [et.x, et.y])
		return
	target.shield_armed = true
	_push(events, state, Consts.EventType.SHIELD_ARMED,
		"%s ставит щит на %s" % [unit.full_name(), target.full_name()])


func _sk_heal(state: MatchState, unit: Unit, et: Vector2i, events: Array) -> void:
	var ally := state.unit_at(et)
	if ally == null or ally.owner != unit.owner:
		_push(events, state, Consts.EventType.FIZZLE, "Лечение: нет союзника на (%d,%d)" % [et.x, et.y])
		return
	var before := ally.hp
	ally.hp = min(ally.max_hp, ally.hp + Consts.HEAL_AMOUNT)
	_push(events, state, Consts.EventType.HEAL,
		"%s лечит %s на %d -> HP %d/%d" % [unit.full_name(), ally.full_name(), ally.hp - before, ally.hp, ally.max_hp],
		{"victim": ally.id, "amount": ally.hp - before})   # может быть 0 при полном HP


func _sk_flash(state: MatchState, unit: Unit, events: Array) -> void:
	for d in Consts.DIRS8:
		var v := state.unit_at(unit.cell + d)
		if v != null:
			_deal_damage(state, v, Consts.FLASH_DMG, unit.owner, events, "вспышка", unit)


# Искра — прямой удар по клетке на дальности 1..SPARK_RANGE
func _sk_spark(state: MatchState, unit: Unit, et: Vector2i, events: Array) -> void:
	var d := _manhattan(unit.cell, et)
	if d < 1 or d > Consts.SPARK_RANGE:
		_push(events, state, Consts.EventType.FIZZLE, "Искра: цель вне дальности")
		return
	var v := state.unit_at(et)
	if v == null:
		_push(events, state, Consts.EventType.FIZZLE, "Искра в пустоту (%d,%d)" % [et.x, et.y])
		return
	_deal_damage(state, v, Consts.SPARK_DMG, unit.owner, events, "искра", unit)


# Дезориентация — метка на враге: его следующий направленный скилл в этом раунде развернётся
func _sk_disorient(state: MatchState, unit: Unit, et: Vector2i, events: Array) -> void:
	var v := state.unit_at(et)
	if v == null or v.owner == unit.owner:
		_push(events, state, Consts.EventType.FIZZLE, "Дезориентация: на (%d,%d) нет врага" % [et.x, et.y])
		return
	v.disoriented = true
	_push(events, state, Consts.EventType.DISORIENT_MARKED,
		"%s дезориентирует %s" % [unit.full_name(), v.full_name()])


# Кража маны — удар по соседнему врагу: похищает ману и наносит урон
func _sk_manasteal(state: MatchState, unit: Unit, et: Vector2i, events: Array) -> void:
	if _cheb(unit.cell, et) != 1:
		_push(events, state, Consts.EventType.FIZZLE, "Кража маны: цель не соседняя")
		return
	var v := state.unit_at(et)
	if v == null or v.owner == unit.owner:
		_push(events, state, Consts.EventType.FIZZLE, "Кража маны: на (%d,%d) нет врага" % [et.x, et.y])
		return
	var stolen: int = min(Consts.MANASTEAL_AMOUNT, v.mana)
	v.mana -= stolen
	unit.mana += stolen
	_push(events, state, Consts.EventType.MANA,
		"%s крадёт %d маны у %s" % [unit.full_name(), stolen, v.full_name()])
	_deal_damage(state, v, Consts.MANASTEAL_DMG, unit.owner, events, "кража маны", unit)


# Оковы — враг в радиусе SHACKLES_RANGE теряет базовую атаку на SHACKLES_TURNS ходов
func _sk_shackles(state: MatchState, unit: Unit, et: Vector2i, events: Array) -> void:
	var v := state.unit_at(et)
	if v == null or v.owner == unit.owner:
		_push(events, state, Consts.EventType.FIZZLE, "Оковы: на (%d,%d) нет врага" % [et.x, et.y])
		return
	v.no_attack_turns = Consts.SHACKLES_TURNS
	_push(events, state, Consts.EventType.SHACKLE_MARKED,
		"%s сковывает %s — %d хода без базовой атаки" % [unit.full_name(), v.full_name(), Consts.SHACKLES_TURNS])


# Замедление — враг в радиусе SLOW_RANGE получает -SLOW_MOVE_PENALTY к дальности хода на SLOW_TURNS ходов
func _sk_slow(state: MatchState, unit: Unit, et: Vector2i, events: Array) -> void:
	var v := state.unit_at(et)
	if v == null or v.owner == unit.owner:
		_push(events, state, Consts.EventType.FIZZLE, "Замедление: на (%d,%d) нет врага" % [et.x, et.y])
		return
	v.slow_turns = Consts.SLOW_TURNS
	_push(events, state, Consts.EventType.SLOW_MARKED,
		"%s замедляет %s" % [unit.full_name(), v.full_name()])


# Телепорт — перемещает фею на свободную клетку в радиусе TELEPORT_RANGE (сквозь всё; вход в клетку,
# поэтому капкан/засада на цели срабатывают, а кровавый след тикает один раз)
func _sk_teleport(state: MatchState, unit: Unit, et: Vector2i, events: Array) -> void:
	if _manhattan(unit.cell, et) < 1 or _manhattan(unit.cell, et) > Consts.TELEPORT_RANGE:
		_push(events, state, Consts.EventType.FIZZLE, "Телепорт: цель вне радиуса")
		return
	if not state.board.is_passable(et) or state.unit_at(et) != null or state.grave_at(et):
		_push(events, state, Consts.EventType.FIZZLE, "Телепорт: клетка (%d,%d) занята" % [et.x, et.y])
		return
	_enter(state, unit, et, events, unit.owner, Consts.EventType.MOVE,
		"%s телепортируется на (%d,%d)" % [unit.full_name(), et.x, et.y])


# Возрождение — поднимает павшего союзника (любая могила на доске) на полном HP в соседней свободной клетке
func _sk_revive(state: MatchState, unit: Unit, et: Vector2i, events: Array) -> void:
	var ally: Unit = null
	for u in state.units:
		if not u.alive and u.cell == et and u.owner == unit.owner:
			ally = u
			break
	if ally == null:
		_push(events, state, Consts.EventType.FIZZLE, "Возрождение: рядом нет павшего союзника")
		return
	# соседняя свободная клетка от могилы (детерминированный обход)
	var dest := Vector2i(-1, -1)
	for d in Consts.DIRS8:
		var c: Vector2i = et + d
		if state.board.is_passable(c) and state.unit_at(c) == null and not state.grave_at(c):
			dest = c
			break
	if dest.x < 0:
		_push(events, state, Consts.EventType.FIZZLE, "Возрождение: негде поставить союзника")
		return
	ally.alive = true
	ally.hp = ally.max_hp
	ally.mana = Consts.START_MANA
	ally.cell = dest
	ally.dead_timer = 0
	ally.death_cell = Vector2i(-1, -1)
	ally.bleed_turns = 0
	ally.no_attack_turns = 0
	ally.slow_turns = 0
	ally.disoriented = false
	_push(events, state, Consts.EventType.RESPAWN,
		"%s воскрешает %s на (%d,%d)" % [unit.full_name(), ally.full_name(), dest.x, dest.y])


func _sk_jump(state: MatchState, unit: Unit, et: Vector2i, events: Array) -> void:
	var dir := _dir_sign(et - unit.cell)
	# только орто-соседняя клетка
	if _manhattan(unit.cell, et) != 1:
		_push(events, state, Consts.EventType.FIZZLE, "Прыжок: цель не соседняя")
		return
	var jumped := state.unit_at(et)
	var land := et + dir
	if jumped == null:
		_push(events, state, Consts.EventType.FIZZLE, "Прыжок: некого перепрыгнуть")
		return
	if not state.board.is_passable(land) or state.unit_at(land) != null:
		_push(events, state, Consts.EventType.FIZZLE, "Прыжок: негде приземлиться")
		return
	_enter(state, unit, land, events, unit.owner, Consts.EventType.MOVE,
		"%s перепрыгивает на (%d,%d)" % [unit.full_name(), land.x, land.y])
	if jumped.owner != unit.owner and jumped.alive:
		_deal_damage(state, jumped, Consts.JUMP_DMG, unit.owner, events, "прыжок", unit)


func _sk_ambush(state: MatchState, unit: Unit, events: Array) -> void:
	state.ambushes.append({
		"owner_id": unit.id,
		"expire_round": state.round_num + Consts.PERSIST_ROUNDS,
	})
	_push(events, state, Consts.EventType.AMBUSH_ARMED, "%s встаёт в засаду" % unit.full_name())


func _sk_dash(state: MatchState, unit: Unit, et: Vector2i, events: Array) -> void:
	var dir := _dir_sign(et - unit.cell)
	if dir.x != 0 and dir.y != 0:
		_push(events, state, Consts.EventType.FIZZLE, "Рывок: только по прямой")
		return
	var steps := _manhattan(unit.cell, et)
	var land := unit.cell
	var c := unit.cell
	for s in steps:
		c += dir
		if not state.board.is_passable(c):
			break
		var v := state.unit_at(c)
		if v != null and v.id != unit.id:
			_deal_damage(state, v, Consts.DASH_DMG, unit.owner, events, "рывок", unit)
		else:
			land = c
	if land != unit.cell:
		_enter(state, unit, land, events, unit.owner, Consts.EventType.MOVE,
			"%s прорывается на (%d,%d)" % [unit.full_name(), land.x, land.y])


# Натиск — урон соседу, отбрасывание, продвижение в освободившуюся клетку.
# Клетка освобождается, если жертву отбросило ИЛИ она погибла (могила не мешает).
func _sk_onslaught(state: MatchState, unit: Unit, et: Vector2i, events: Array) -> void:
	if _manhattan(unit.cell, et) != 1:
		_push(events, state, Consts.EventType.FIZZLE, "Натиск: цель не соседняя")
		return
	var victim := state.unit_at(et)
	if victim == null:
		_push(events, state, Consts.EventType.FIZZLE, "Натиск в пустоту (%d,%d)" % [et.x, et.y])
		return
	var dir := _dir_sign(et - unit.cell)
	_deal_damage(state, victim, Consts.ONSLAUGHT_DMG, unit.owner, events, "натиск", unit)
	if victim.alive:
		_knockback(state, victim, dir, unit.owner, events)
	if state.unit_at(et) == null and state.board.is_passable(et):
		_enter(state, unit, et, events, unit.owner, Consts.EventType.MOVE,
			"%s продвигается на (%d,%d)" % [unit.full_name(), et.x, et.y])


# Острые шипы — урон по 4 диагонально-соседним клеткам (по своим тоже, как Вспышка)
func _sk_spikes(state: MatchState, unit: Unit, events: Array) -> void:
	var hit := false
	for d in Consts.DIRS_DIAG:
		var v := state.unit_at(unit.cell + d)
		if v == null:
			continue
		hit = true
		_deal_damage(state, v, Consts.SPIKES_DMG, unit.owner, events, "острые шипы", unit)
	if not hit:
		_push(events, state, Consts.EventType.FIZZLE, "Острые шипы: по диагоналям рядом пусто")


func _sk_reflexes(state: MatchState, unit: Unit, events: Array) -> void:
	unit.reflexes_armed = true
	_push(events, state, Consts.EventType.REFLEX_ARMED,
		"%s встаёт в стойку рефлексов" % unit.full_name())


# Затвердение — стойка: входящий урон в этом раунде срезается на HARDENING_REDUCTION (см. _deal_damage)
func _sk_hardening(state: MatchState, unit: Unit, events: Array) -> void:
	unit.hardened = true
	_push(events, state, Consts.EventType.HARDEN_ARMED,
		"%s затвердевает — весь урон в этом раунде меньше на %d" % [unit.full_name(), Consts.HARDENING_REDUCTION])


# Осколки — стойка: враг, нанёсший урон в этом раунде, получает ответку (см. _deal_damage)
func _sk_shards(state: MatchState, unit: Unit, events: Array) -> void:
	unit.shards_armed = true
	_push(events, state, Consts.EventType.SHARDS_ARMED,
		"%s покрывается осколками" % unit.full_name())


# Перегрузка — тратит ВСЮ ману (базовая цена уже списана в _do_ability), урон соседу
# 2 за каждую потраченную. Фиксируем ману до удара, чтобы фиксированное число попало и в лог.
func _sk_overload(state: MatchState, unit: Unit, et: Vector2i, events: Array) -> void:
	if _manhattan(unit.cell, et) != 1:
		_push(events, state, Consts.EventType.FIZZLE, "Перегрузка: цель не соседняя")
		return
	var victim := state.unit_at(et)
	if victim == null:
		_push(events, state, Consts.EventType.FIZZLE, "Перегрузка в пустоту (%d,%d)" % [et.x, et.y])
		return
	var spent := Consts.OVERLOAD_MANA + unit.mana   # база (уже вычтена) + весь остаток
	unit.mana = 0
	_deal_damage(state, victim, spent * Consts.OVERLOAD_DMG_PER_MANA, unit.owner, events,
		"перегрузка", unit)


# Обмен местами — телепорт-swap с соседним юнитом (своим/чужим); без входа в клетку,
# поэтому капканы/засады на клетках назначения не срабатывают.
func _sk_swap(state: MatchState, unit: Unit, et: Vector2i, events: Array) -> void:
	if _cheb(unit.cell, et) != 1:
		_push(events, state, Consts.EventType.FIZZLE, "Обмен местами: цель не соседняя")
		return
	var other := state.unit_at(et)
	if other == null:
		_push(events, state, Consts.EventType.FIZZLE, "Обмен местами: некого менять (%d,%d)" % [et.x, et.y])
		return
	var my_cell := unit.cell
	unit.cell = other.cell
	other.cell = my_cell
	_push(events, state, Consts.EventType.MOVE,
		"%s меняется местами с %s" % [unit.full_name(), other.full_name()],
		{"actor": unit.id, "to_cell": unit.cell})
	_push(events, state, Consts.EventType.MOVE,
		"%s перемещён на (%d,%d)" % [other.full_name(), other.cell.x, other.cell.y],
		{"actor": other.id, "to_cell": other.cell})
	# Своп — перемещение обоих: кровавый след тикает каждому помеченному участнику
	_bleed_tick(state, unit, events)
	_bleed_tick(state, other, events)


# Соседний враг целит в клетку юнита со взведёнными рефлексами: тот отступает на 1 и
# получает ману, а эффект прилетает в опустевшую клетку (no-retarget — цель фиксирована).
# Если отступать некуда, стойка не тратится и удар проходит: зажатого в угол не спасает.
func _check_reflexes(state: MatchState, actor: Unit, cell: Vector2i, events: Array) -> void:
	var v := state.unit_at(cell)
	if v == null or v.owner == actor.owner or not v.reflexes_armed:
		return
	if v.immobilized:   # уворот — это движение, обездвиженный не уходит из-под удара
		return
	if _cheb(actor.cell, cell) != 1:
		return
	var dir := _dir_sign(v.cell - actor.cell)
	var dest := v.cell + dir
	if not state.board.is_passable(dest) or state.unit_at(dest) != null:
		_push(events, state, Consts.EventType.FIZZLE,
			"%s: рефлексы не сработали — отступать некуда" % v.full_name())
		return
	v.reflexes_armed = false
	v.mana += Consts.REFLEXES_MANA_GAIN
	_push(events, state, Consts.EventType.REFLEX_DODGE,
		"Рефлексы! %s уходит из-под удара, +%d маны" % [v.full_name(), Consts.REFLEXES_MANA_GAIN])
	_enter(state, v, dest, events, v.owner, Consts.EventType.MOVE,
		"%s отступает на (%d,%d)" % [v.full_name(), dest.x, dest.y])


# ---------------------------------------------------------------- утилиты

func _push(events: Array, state: MatchState, type: int, text: String, extra: Dictionary = {}) -> void:
	var ev := {"type": type, "text": text, "snapshot": state.snapshot()}
	for k in extra:
		ev[k] = extra[k]
	events.append(ev)


func _dir_sign(delta: Vector2i) -> Vector2i:
	return Vector2i(signi(delta.x), signi(delta.y))


# Скиллы, чей эффект перемещает самого кастера (значит, блокируются обездвиживанием)
func _skill_moves_caster(skill: int) -> bool:
	return skill in [Consts.Skill.JUMP, Consts.Skill.DASH, Consts.Skill.ONSLAUGHT,
			Consts.Skill.SWAP, Consts.Skill.RETREAT, Consts.Skill.TELEPORT]


# Первый живой юнит на прямой от from к target (стена/край -> пуля погашена, null).
# Возвращает того, кто встал на пути, иначе юнита в целевой клетке, иначе null.
func _first_unit_on_line(state: MatchState, from: Vector2i, target: Vector2i) -> Unit:
	var delta := target - from
	if delta == Vector2i.ZERO:
		return null
	var step := _dir_sign(delta)
	var cur := from + step
	while state.board.in_bounds(cur) and not state.board.is_obstacle(cur):
		var u := state.unit_at(cur)
		if u != null:
			return u
		if cur == target:
			return null
		cur += step
	return null


# Первый живой юнит на луче из from в направлении step (стена/край гасят луч).
func _first_unit_on_ray(state: MatchState, from: Vector2i, step: Vector2i) -> Unit:
	var cur := from + step
	while state.board.in_bounds(cur) and not state.board.is_obstacle(cur):
		var u := state.unit_at(cur)
		if u != null:
			return u
		cur += step
	return null


func _enemy_adjacent(state: MatchState, unit: Unit) -> bool:
	for d in Consts.DIRS8:
		var u := state.unit_at(unit.cell + d)
		if u != null and u.owner != unit.owner:
			return true
	return false


func _trap_at(state: MatchState, cell: Vector2i) -> bool:
	for t in state.traps:
		if t.cell == cell:
			return true
	return false


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


func _cheb(a: Vector2i, b: Vector2i) -> int:
	return max(abs(a.x - b.x), abs(a.y - b.y))
