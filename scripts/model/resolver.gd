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
	var cur := unit.cell
	for i in path.size():
		var next: Vector2i = cur + path[i]
		if not state.board.is_passable(next):
			_push(events, state, Consts.EventType.INFO,
				"%s: ход заблокирован на (%d,%d)" % [unit.full_name(), next.x, next.y])
			return
		var occupant := state.unit_at(next)
		if occupant != null and occupant.id != unit.id:
			if occupant.owner != unit.owner:
				_push(events, state, Consts.EventType.INFO,
					"%s: ход заблокирован на (%d,%d)" % [unit.full_name(), next.x, next.y])
				return
			if i == path.size() - 1:
				_push(events, state, Consts.EventType.INFO,
					"%s: на (%d,%d) стоит союзник — негде встать" % [unit.full_name(), next.x, next.y])
				return
			cur = next   # проходим сквозь союзника, клетку не занимаем
			continue
		cur = next
		_enter(state, unit, cur, events, unit.owner, Consts.EventType.MOVE,
			"%s -> (%d,%d)" % [unit.full_name(), cur.x, cur.y])
		if not unit.alive:
			return


# Перемещает юнита на клетку, логирует и проверяет капканы/засады
func _enter(state: MatchState, unit: Unit, cell: Vector2i, events: Array, src_player: int, ev_type: int, text: String) -> void:
	unit.cell = cell
	_push(events, state, ev_type, text, {"actor": unit.id, "to_cell": cell})
	_check_triggers(state, unit, cell, events, src_player)


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
				unit.immobilize_pending = true
				_deal_damage(state, unit, Consts.TRAP_DMG, t.owner_player, events, "капкан")
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
			_deal_damage(state, unit, Consts.AMBUSH_DMG, owner.owner, events, "засада")
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

func _deal_damage(state: MatchState, target: Unit, amount: int, src_player: int, events: Array, label: String) -> void:
	var dmg := amount
	if target.hero_type == Consts.HeroType.CRYSTAL:
		dmg = max(0, dmg - Consts.CRYSTAL_PASSIVE_REDUCTION)
	if dmg <= 0:
		_push(events, state, Consts.EventType.DAMAGE,
			"%s: пассив свёл урон к 0 (%s)" % [target.full_name(), label])
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
	if target.hp <= 0:
		_kill(state, target, src_player, events)


func _kill(state: MatchState, target: Unit, src_player: int, events: Array) -> void:
	target.alive = false
	target.death_cell = target.cell
	target.dead_timer = Consts.RESPAWN_DELAY
	# снять засаду убитого
	var kept: Array = []
	for a in state.ambushes:
		if a.owner_id != target.id:
			kept.append(a)
	state.ambushes = kept
	_push(events, state, Consts.EventType.DEATH,
		"%s погибает на (%d,%d)" % [target.full_name(), target.cell.x, target.cell.y])
	if src_player != target.owner:
		state.add_score(src_player, Consts.KILL_POINTS)
		_push(events, state, Consts.EventType.KILL,
			"+%d очка игроку %s за килл" % [Consts.KILL_POINTS, Consts.player_name(src_player)])


# ---------------------------------------------------------------- базовые атаки

# Эффективная цель: нон-таргет-скиллы целят (текущая_клетка + offset), иначе абсолютная target
func _eff_target(unit: Unit, order: Order) -> Vector2i:
	return (unit.cell + order.offset) if order.relative else order.target


func _do_basic_attack(state: MatchState, unit: Unit, order: Order, events: Array) -> void:
	var et := _eff_target(unit, order)
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
	_deal_damage(state, victim, dmg, unit.owner, events, "атака")


# ---------------------------------------------------------------- способности

func _do_ability(state: MatchState, unit: Unit, order: Order, slot: int, events: Array) -> void:
	var idx := order.action - Consts.Action.ABILITY1  # 0..2
	var skill: int = unit.skills[idx]
	var def := HeroDefs.skill_def(skill)
	if def.slot_gate.size() > 0 and not (slot in def.slot_gate):
		_push(events, state, Consts.EventType.FIZZLE,
			"%s: %s недоступна в этом слоте" % [unit.full_name(), def.name])
		return
	if unit.mana < def.mana:
		_push(events, state, Consts.EventType.FIZZLE,
			"%s: не хватает маны на %s" % [unit.full_name(), def.name])
		return
	unit.mana -= def.mana
	var et := _eff_target(unit, order)
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
		Consts.Skill.CANCEL: _sk_cancel(state, unit, et, events)
		Consts.Skill.HEAL: _sk_heal(state, unit, et, events)
		Consts.Skill.FLASH: _sk_flash(state, unit, events)
		Consts.Skill.JUMP: _sk_jump(state, unit, et, events)
		Consts.Skill.AMBUSH: _sk_ambush(state, unit, events)
		Consts.Skill.DASH: _sk_dash(state, unit, et, events)
		Consts.Skill.ONSLAUGHT: _sk_onslaught(state, unit, et, events)
		Consts.Skill.CRYSTAL_SHOT: _sk_crystal_shot(state, unit, events)
		Consts.Skill.REFLEXES: _sk_reflexes(state, unit, events)


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
	_deal_damage(state, v, Consts.SNIPE_DMG, unit.owner, events, "снайп")


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
		_deal_damage(state, v, Consts.SHOTGUN_DMG, unit.owner, events, "дробь")
		if v.alive:
			_knockback(state, v, _dir_sign(v.cell - unit.cell), unit.owner, events)


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
			_deal_damage(state, v, Consts.FLASH_DMG, unit.owner, events, "вспышка")


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
		_deal_damage(state, jumped, Consts.JUMP_DMG, unit.owner, events, "прыжок")


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
			_deal_damage(state, v, Consts.DASH_DMG, unit.owner, events, "рывок")
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
	_deal_damage(state, victim, Consts.ONSLAUGHT_DMG, unit.owner, events, "натиск")
	if victim.alive:
		_knockback(state, victim, dir, unit.owner, events)
	if state.unit_at(et) == null and state.board.is_passable(et):
		_enter(state, unit, et, events, unit.owner, Consts.EventType.MOVE,
			"%s продвигается на (%d,%d)" % [unit.full_name(), et.x, et.y])


# Отстрел кристаллов — первый юнит на каждой из 4 диагоналей (по своим тоже)
func _sk_crystal_shot(state: MatchState, unit: Unit, events: Array) -> void:
	var hit := false
	for d in Consts.DIRS_DIAG:
		var v := _first_unit_on_ray(state, unit.cell, d)
		if v == null:
			continue
		hit = true
		_deal_damage(state, v, Consts.CRYSTAL_SHOT_DMG, unit.owner, events, "отстрел кристаллов")
	if not hit:
		_push(events, state, Consts.EventType.FIZZLE, "Отстрел кристаллов: на диагоналях пусто")


func _sk_reflexes(state: MatchState, unit: Unit, events: Array) -> void:
	unit.reflexes_armed = true
	_push(events, state, Consts.EventType.REFLEX_ARMED,
		"%s встаёт в стойку рефлексов" % unit.full_name())


# Соседний враг целит в клетку юнита со взведёнными рефлексами: тот отступает на 1 и
# получает ману, а эффект прилетает в опустевшую клетку (no-retarget — цель фиксирована).
# Если отступать некуда, стойка не тратится и удар проходит: зажатого в угол не спасает.
func _check_reflexes(state: MatchState, actor: Unit, cell: Vector2i, events: Array) -> void:
	var v := state.unit_at(cell)
	if v == null or v.owner == actor.owner or not v.reflexes_armed:
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


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


func _cheb(a: Vector2i, b: Vector2i) -> int:
	return max(abs(a.x - b.x), abs(a.y - b.y))
