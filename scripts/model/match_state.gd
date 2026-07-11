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


# loadout_* : hero_type -> Array скиллов. Пустой словарь -> кит по умолчанию.
# Киты обоих игроков обязаны быть одинаковыми на сервере и у клиентов (лок-степ).
func setup(loadout_a: Dictionary = {}, loadout_b: Dictionary = {}) -> void:
	board = Board.new()
	units.clear()
	# A внизу (y=6), B зеркально сверху (y=0), симметрия 180°.
	_add_unit(0, Consts.Player.A, Consts.HeroType.HUNTER, Vector2i(1, 6), loadout_a)
	_add_unit(1, Consts.Player.A, Consts.HeroType.FAIRY, Vector2i(3, 6), loadout_a)
	_add_unit(2, Consts.Player.A, Consts.HeroType.CRYSTAL, Vector2i(5, 6), loadout_a)
	_add_unit(3, Consts.Player.B, Consts.HeroType.HUNTER, Vector2i(5, 0), loadout_b)
	_add_unit(4, Consts.Player.B, Consts.HeroType.FAIRY, Vector2i(3, 0), loadout_b)
	_add_unit(5, Consts.Player.B, Consts.HeroType.CRYSTAL, Vector2i(1, 0), loadout_b)


func _add_unit(id: int, owner: int, hero_type: int, cell: Vector2i, lo: Dictionary = {}) -> void:
	var sk: Array = lo.get(hero_type, [])
	units.append(Unit.new(id, owner, hero_type, cell, sk))


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


func add_score(player: int, pts: int) -> void:
	score[player] += pts
	if score[player] >= Consts.WIN_SCORE and winner < 0:
		winner = player


# --- Начало раунда: инкремент, мана, снятие/взвод эффектов, респ, экспирация ---
func begin_round() -> Array:
	round_num += 1
	var events: Array = []
	for u in units:
		u.shield_armed = false
		u.reflexes_armed = false
		u.hardened = false
		u.shards_armed = false
		u.immobilized = false   # капкан замораживает лишь до конца своего раунда — новый раунд свободен
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
	return events


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


func _ev(type: int, text: String, extra: Dictionary = {}) -> Dictionary:
	var ev := {"type": type, "text": text, "snapshot": snapshot()}
	for k in extra:
		ev[k] = extra[k]
	return ev


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
