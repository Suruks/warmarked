class_name MatchState
extends RefCounted

## Всё динамическое состояние матча: доска, юниты, очки, номер раунда, персистентные
## эффекты (капканы/засады). Housekeeping раунда (мана, респ, экспирация) и подсчёт очков.
## Боевое разрешение делает Resolver, но он мутирует именно этот объект.

var board: Board
var units: Array[Unit] = []
var score := {Consts.Player.A: 0, Consts.Player.B: 0}
var round_num: int = 0
var a_first_on_odd: bool = true          # жеребьёвка: A ходит первым в нечётные раунды

# Персистентные эффекты
var traps: Array = []      # [{cell:Vector2i, owner_player:int, owner_id:int, expire_round:int}]
var ambushes: Array = []   # [{owner_id:int, expire_round:int}]

var winner: int = -1       # Consts.Player или -1


# Классы отряда по умолчанию (когда состав не задан).
const _DEFAULT_TYPES := [Consts.HeroType.HUNTER, Consts.HeroType.FAIRY, Consts.HeroType.CRYSTAL]


# team_* : массив из TEAM_SIZE бойцов {type, skills} (классы могут повторяться). Пустой -> отряд
# по умолчанию (Охотник/Фея/Кристалл). Составы обоих игроков обязаны совпадать на сервере и у
# клиентов (лок-степ) — их канонизирует Loadout перед раздачей.
# map_index — карта из Maps (0 = базовая); стартовые клетки берутся из неё.
func setup(team_a: Array = [], team_b: Array = [], map_index: int = 0) -> void:
	board = Board.new(map_index)
	units.clear()
	for i in 3:
		_add_unit(i, Consts.Player.A, _slot(team_a, i), board.spawns_a[i])
		_add_unit(3 + i, Consts.Player.B, _slot(team_b, i), board.spawns_b[i])


# Боец на позиции i: {type, skills} из состава, иначе дефолтный класс с пустым китом (→ дефолт).
func _slot(team: Array, i: int) -> Dictionary:
	var e: Variant = team[i] if i < team.size() else null
	if typeof(e) == TYPE_DICTIONARY and typeof(e.get("type")) == TYPE_INT:
		return {"type": int(e.type), "skills": e.get("skills", [])}
	return {"type": _DEFAULT_TYPES[i], "skills": []}


func _add_unit(id: int, owner: int, slot: Dictionary, cell: Vector2i) -> void:
	var sk: Array = slot.get("skills", []) if typeof(slot.get("skills")) == TYPE_ARRAY else []
	units.append(Unit.new(id, owner, int(slot.type), cell, sk))


func get_unit(id: int) -> Unit:
	for u in units:
		if u.id == id:
			return u
	return null


func unit_at(cell: Vector2i) -> Unit:
	for u in units:
		if u.alive and u.cell == cell:
			return u
	return null


# Есть ли на клетке могила (мёртвый юнит на клетке смерти)
func grave_at(cell: Vector2i) -> bool:
	for u in units:
		if not u.alive and u.cell == cell:
			return true
	return false


func living_units() -> Array[Unit]:
	var out: Array[Unit] = []
	for u in units:
		if u.alive:
			out.append(u)
	return out


func units_of(player: int) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in units:
		if u.owner == player:
			out.append(u)
	return out


func first_player_this_round() -> int:
	# если round_num нечётный, первым ходит A (при a_first_on_odd), иначе инверсия
	if round_num % 2 == 1:
		return Consts.Player.A if a_first_on_odd else Consts.Player.B
	else:
		return Consts.Player.B if a_first_on_odd else Consts.Player.A


# Действует ли игрок в этом слоте. Второй игрок раунда пропускает ПОСЛЕДНИЙ слот — так действия
# строго чередуются и никто не ходит дважды подряд на стыке раундов.
func acts_in_slot(player: int, slot: int) -> bool:
	return not (slot == Consts.ORDER_SLOTS - 1 and player != first_player_this_round())


func add_score(player: int, pts: int) -> void:
	score[player] += pts


# Победа фиксируется только по итогам ВСЕГО раунда (киллы в резолве + контроль точек в
# score_round), а не в момент первого начисления очка: если оба игрока в одном раунде
# независимо набрали WIN_SCORE (например, взаимный размен киллами) — это ничья, а не победа
# того, чьё очко долетело до порога первым.
func _check_winner() -> void:
	if winner >= 0:
		return
	var a_won: bool = score[Consts.Player.A] >= Consts.WIN_SCORE
	var b_won: bool = score[Consts.Player.B] >= Consts.WIN_SCORE
	if a_won and b_won:
		winner = Consts.DRAW
	elif a_won:
		winner = Consts.Player.A
	elif b_won:
		winner = Consts.Player.B


# --- Начало раунда: инкремент, мана, снятие/взвод эффектов, респ, экспирация ---
func begin_round() -> Array:
	round_num += 1
	var events: Array = []
	for u in units:
		u.shield_armed = false
		u.reflexes_armed = false
		u.hardened = false
		u.shards_armed = false
		u.disoriented = false   # дезориентация действует лишь на свой раунд
		u.shell_used = false     # «Кристальный панцирь» — срезка снова доступна
		u.block_amount = 0       # «Блок» — запас поглощения сбрасывается
		# «Снайпер»: движение прошлого раунда — фиксируем и обнуляем счётчик текущего
		u.moved_last_round = u.moved_this_round
		u.moved_this_round = false
		u.immobilized = false   # капкан замораживает лишь до конца своего раунда — новый раунд свободен
		# Эффекты с длительностью держатся через раунды: убывают, а не сбрасываются
		if u.bleed_turns > 0:
			u.bleed_turns -= 1
			if u.bleed_turns == 0:
				u.bleed_owner = -1
		if u.no_attack_turns > 0:
			u.no_attack_turns -= 1
		if u.slow_turns > 0:
			u.slow_turns -= 1
		if u.hunt_turns > 0:
			u.hunt_turns -= 1
		if u.alive and round_num > 1:
			u.mana += 1
	# Респ мёртвых
	for u in units:
		if not u.alive:
			u.dead_timer -= 1
			if u.dead_timer <= 0:
				_try_respawn(u, events)
	# Экспирация капканов/засад
	var kept_traps: Array = []
	for t in traps:
		if t.expire_round >= round_num:
			kept_traps.append(t)
	traps = kept_traps
	var kept_amb: Array = []
	for a in ambushes:
		var owner := get_unit(a.owner_id)
		if a.expire_round >= round_num and owner != null and owner.alive:
			kept_amb.append(a)
	ambushes = kept_amb
	_blessing_heal(events)
	return events


# «Благословение»: каждая живая Фея с этой пассивкой в начале раунда лечит союзников
# в радиусе 1 на BLESSING_HEAL HP (саму себя — нет).
func _blessing_heal(events: Array) -> void:
	for f in units:
		if not (f.alive and f.has_skill(Consts.Skill.BLESSING)):
			continue
		for u in units:
			if u.id == f.id or not u.alive or u.owner != f.owner or u.hp >= u.max_hp:
				continue
			if maxi(absi(u.cell.x - f.cell.x), absi(u.cell.y - f.cell.y)) > 1:
				continue
			var before := u.hp
			u.hp = mini(u.max_hp, u.hp + Consts.BLESSING_HEAL)
			events.append(_ev(Consts.EventType.HEAL,
				"Благословение %s: +%d HP %s" % [f.full_name(), u.hp - before, u.full_name()],
				{"victim": u.id, "amount": u.hp - before}))


# Респ в РОДНОМ ряду, а не на клетке смерти: при коротком кулдауне возвращение под чужие
# стволы превратилось бы в спаун-кемп. Поэтому же исчезла механика урона блокеру.
func _try_respawn(u: Unit, events: Array) -> void:
	var cell := _respawn_cell(u)
	if cell.x < 0:
		u.dead_timer = 0   # свободных клеток нет — повторить попытку в следующем раунде
		events.append(_ev(Consts.EventType.RESPAWN_BLOCKED,
			"Респ %s отложен: в родном ряду нет свободной клетки" % u.full_name()))
		return
	u.alive = true
	u.hp = u.max_hp
	u.mana = Consts.START_MANA   # накопленный до смерти банк не переживает респ — это и есть цена смерти
	u.cell = cell
	u.dead_timer = 0
	u.bleed_turns = 0            # эффекты с длительностью не переживают смерть
	u.bleed_owner = -1
	u.no_attack_turns = 0
	u.slow_turns = 0
	u.hunt_turns = 0
	u.disoriented = false
	events.append(_ev(Consts.EventType.RESPAWN,
		"%s воскрешается на (%d,%d)" % [u.full_name(), cell.x, cell.y]))


# Публичный расчёт клетки воскрешения (нужен резолверу, чтобы поставить туда могилу-маркер).
func respawn_cell_for(u: Unit) -> Vector2i:
	return _respawn_cell(u)


# Родная клетка → ближайшая свободная в родном ряду → ближайшая свободная на доске.
# Обход строго детерминирован: сервер и клиенты обязаны прийти к одной клетке (лок-степ).
func _respawn_cell(u: Unit) -> Vector2i:
	if _free_for_respawn(u.home_cell):
		return u.home_cell
	for d in range(1, Consts.BOARD_W):
		for s in [-1, 1]:
			var c := Vector2i(u.home_cell.x + d * s, u.home_cell.y)
			if _free_for_respawn(c):
				return c
	var best := Vector2i(-1, -1)
	var best_dist := Consts.BOARD_W + Consts.BOARD_H
	for y in Consts.BOARD_H:
		for x in Consts.BOARD_W:
			var c := Vector2i(x, y)
			if not _free_for_respawn(c):
				continue
			var dist: int = absi(c.x - u.home_cell.x) + absi(c.y - u.home_cell.y)
			if dist < best_dist:
				best_dist = dist
				best = c
	return best


# Могилы не мешают: воскресать можно поверх павшего (своего или чужого).
func _free_for_respawn(c: Vector2i) -> bool:
	return board.is_passable(c) and unit_at(c) == null


# --- Подсчёт очков в конце раунда (киллы уже начислены в резолве) ---
func score_round(events: Array) -> void:
	var a := 0
	var b := 0
	for cp in board.control_points:
		var u := unit_at(cp)
		if u != null:
			if u.owner == Consts.Player.A:
				a += 1
			else:
				b += 1
	if a > b:
		add_score(Consts.Player.A, Consts.CONTROL_POINTS_PER_ROUND)
		events.append(_ev(Consts.EventType.SCORE, "Контроль точек: A держит %d:%d -> +%d A" % [a, b, Consts.CONTROL_POINTS_PER_ROUND]))
	elif b > a:
		add_score(Consts.Player.B, Consts.CONTROL_POINTS_PER_ROUND)
		events.append(_ev(Consts.EventType.SCORE, "Контроль точек: B держит %d:%d -> +%d B" % [b, a, Consts.CONTROL_POINTS_PER_ROUND]))
	else:
		events.append(_ev(Consts.EventType.INFO, "Контроль точек: равенство %d:%d, очко никому" % [a, b]))
	_check_winner()
	if winner == Consts.DRAW:
		events.append(_ev(Consts.EventType.SCORE, "Оба игрока набрали %d очков одновременно — ничья" % Consts.WIN_SCORE))


func _ev(type: int, text: String, extra: Dictionary = {}) -> Dictionary:
	var ev := {"type": type, "text": text, "snapshot": snapshot()}
	for k in extra:
		ev[k] = extra[k]
	return ev


# Глубокая копия для просчёта AI: клон можно свободно мутировать Resolver'ом (прогон варианта
# приказов), не задевая реальный матч. Доска статична (резолвер её только читает) — делим ссылку.
func clone() -> MatchState:
	var s := MatchState.new()
	s.board = board
	s.units = [] as Array[Unit]
	for u in units:
		s.units.append(u.clone())
	s.score = {Consts.Player.A: score[Consts.Player.A], Consts.Player.B: score[Consts.Player.B]}
	s.round_num = round_num
	s.a_first_on_odd = a_first_on_odd
	s.winner = winner
	s.traps = []
	for t in traps:
		s.traps.append(t.duplicate(true))
	s.ambushes = []
	for a in ambushes:
		s.ambushes.append(a.duplicate(true))
	return s


func snapshot() -> Dictionary:
	var us: Array = []
	for u in units:
		us.append(u.snapshot())
	var ts: Array = []
	for t in traps:
		ts.append({"cell": t.cell, "owner": t.owner_player})
	var ams: Array = []
	for a in ambushes:
		var owner := get_unit(a.owner_id)
		if owner != null and owner.alive:
			ams.append({"cell": owner.cell, "owner": owner.owner})
	return {
		"units": us,
		"traps": ts,
		"ambushes": ams,
		"score_a": score[Consts.Player.A],
		"score_b": score[Consts.Player.B],
		"round": round_num,
	}
