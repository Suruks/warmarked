class_name Targeting
extends RefCounted

## Вычисляет клетки-кандидаты для действия из позиции origin.
##
## Занятость клеток передаётся отдельным словарём occ (cell -> {id, owner}), что позволяет
## учитывать УЖЕ ЗАПЛАНИРОВАННЫЕ перемещения своих юнитов (ушедший освобождает клетку,
## пришедший — занимает). Если occ пуст — строится по стартовым позициям раунда.


static func build_occupancy(state: MatchState) -> Dictionary:
	var occ := {}
	for u in state.living_units():
		occ[u.cell] = {"id": u.id, "owner": u.owner}
	return occ


static func _at(occ: Dictionary, cell: Vector2i):
	return occ.get(cell, null)


# Достижимые ходом клетки (орто, <= MOVE_RANGE) и путь к каждой. cell -> Array[Vector2i] путь.
# Союзник — проходим (можно пройти сквозь), но НЕ пункт назначения. Враг — глухая стена.
static func move_paths(state: MatchState, origin: Vector2i, self_id: int, occ: Dictionary = {}, p_range: int = Consts.MOVE_RANGE) -> Dictionary:
	if occ.is_empty():
		occ = build_occupancy(state)
	var board := state.board
	var me := state.get_unit(self_id)
	var my_owner: int = me.owner if me != null else -1
	var result := {}
	var frontier := [origin]
	var came := {origin: []}
	var dist := {origin: 0}
	while frontier.size() > 0:
		var cur: Vector2i = frontier.pop_front()
		if dist[cur] >= p_range:
			continue
		for d in Consts.DIRS4:
			var n: Vector2i = cur + d
			if not board.is_passable(n):
				continue
			var e = occ.get(n, null)
			var blocker: bool = e != null and e.id != self_id
			if blocker and e.owner != my_owner:
				continue          # вражеский юнит не пропускает
			if came.has(n):
				continue
			var path: Array = came[cur].duplicate()
			path.append(n)
			came[n] = path
			dist[n] = dist[cur] + 1
			if not blocker:
				result[n] = path  # на клетке союзника остановиться нельзя, только пройти
			frontier.append(n)
	return result


static func candidates(state: MatchState, unit: Unit, action: int, origin: Vector2i, occ: Dictionary = {}) -> Array[Vector2i]:
	if occ.is_empty():
		occ = build_occupancy(state)
	match action:
		Consts.Action.MOVE:
			var out: Array[Vector2i] = []
			# замедление снижает дальность хода на этапе планирования
			var rng := Consts.MOVE_RANGE - (Consts.SLOW_MOVE_PENALTY if unit.slow_turns > 0 else 0)
			for c in move_paths(state, origin, unit.id, occ, rng).keys():
				out.append(c)
			return out
		Consts.Action.ATTACK:
			return _basic_attack_cells(state, unit, origin)
		Consts.Action.ABILITY1:
			return _ability_cells(state, unit, 0, origin, occ)
		Consts.Action.ABILITY2:
			return _ability_cells(state, unit, 1, origin, occ)
		Consts.Action.ABILITY3:
			return _ability_cells(state, unit, 2, origin, occ)
	return [] as Array[Vector2i]


# Все проходимые клетки в кольце манхэттена [min_r, max_r] от origin — в out.
static func _ring(board: Board, origin: Vector2i, min_r: int, max_r: int, out: Array[Vector2i]) -> void:
	for dy in range(-max_r, max_r + 1):
		for dx in range(-max_r, max_r + 1):
			var m := absi(dx) + absi(dy)
			if m < min_r or m > max_r:
				continue
			var c := origin + Vector2i(dx, dy)
			if board.is_passable(c):
				out.append(c)


# Есть ли враг (по occ — плановая занятость) в одной из 8 соседних клеток origin.
static func _enemy_adjacent(origin: Vector2i, owner: int, occ: Dictionary) -> bool:
	for d in Consts.DIRS8:
		var e = _at(occ, origin + d)
		if e != null and e.owner != owner:
			return true
	return false


static func _basic_attack_cells(state: MatchState, unit: Unit, origin: Vector2i) -> Array[Vector2i]:
	var board := state.board
	var out: Array[Vector2i] = []
	match unit.hero_type:
		Consts.HeroType.HUNTER:
			for d in Consts.DIRS4:
				for r in [2, 3]:
					var c: Vector2i = origin + d * r
					if board.is_passable(c) and board.is_clear_line(origin, c):
						out.append(c)
		Consts.HeroType.FAIRY:
			for d in Consts.DIRS8:
				var c: Vector2i = origin + d
				if board.is_passable(c):
					out.append(c)
		Consts.HeroType.CRYSTAL:
			for d in Consts.DIRS4:
				var c: Vector2i = origin + d
				if board.is_passable(c):
					out.append(c)
	return out


# Кандидаты по id скилла в слоте idx. Скиллы без цели (Вспышка, Засада, Острые шипы,
# Рефлексы, Затвердение, Осколки) кандидатов не имеют — сюда не попадают.
static func _ability_cells(state: MatchState, unit: Unit, idx: int, origin: Vector2i, occ: Dictionary) -> Array[Vector2i]:
	var board := state.board
	var out: Array[Vector2i] = []
	match unit.skills[idx]:
		Consts.Skill.TRAP:  # passable в радиусе 2, НЕ занято юнитом/могилой, не своя клетка
			for dy in range(-Consts.TRAP_RADIUS, Consts.TRAP_RADIUS + 1):
				for dx in range(-Consts.TRAP_RADIUS, Consts.TRAP_RADIUS + 1):
					var c := origin + Vector2i(dx, dy)
					var man := absi(dx) + absi(dy)
					if man >= 1 and man <= Consts.TRAP_RADIUS and board.is_passable(c) \
							and _at(occ, c) == null and not state.grave_at(c):
						out.append(c)
		Consts.Skill.SNIPE:  # прямая 2..7, чистая линия
			for d in Consts.DIRS4:
				for r in range(Consts.SNIPE_MIN, Consts.SNIPE_MAX + 1):
					var c: Vector2i = origin + d * r
					if board.is_passable(c) and board.is_clear_line(origin, c):
						out.append(c)
		Consts.Skill.SHOTGUN:  # диагональная соседняя клетка задаёт квадрант 2x2 поражения
			for d in Consts.DIRS_DIAG:
				var c: Vector2i = origin + d
				if board.is_passable(c):
					out.append(c)
		Consts.Skill.CANCEL:  # рядом или своя клетка (нон-таргет: щит получит союзник,
			# оказавшийся там при разрешении — не зависит от порядка действий)
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var c := origin + Vector2i(dx, dy)
					if board.is_passable(c):
						out.append(c)
		Consts.Skill.HEAL:  # радиус 2 (нон-таргет; лечит союзника, оказавшегося там)
			for dy in range(-Consts.HEAL_RADIUS, Consts.HEAL_RADIUS + 1):
				for dx in range(-Consts.HEAL_RADIUS, Consts.HEAL_RADIUS + 1):
					if absi(dx) + absi(dy) > Consts.HEAL_RADIUS:
						continue
					var c := origin + Vector2i(dx, dy)
					if board.is_passable(c):
						out.append(c)
		Consts.Skill.JUMP:  # орто-сосед с юнитом и свободной клеткой за ним
			for d in Consts.DIRS4:
				var over: Vector2i = origin + d
				var land: Vector2i = origin + d * 2
				if _at(occ, over) != null and board.is_passable(land) and _at(occ, land) == null:
					out.append(over)
		Consts.Skill.DASH:  # свободные клетки по прямой до препятствия
			for d in Consts.DIRS4:
				var c: Vector2i = origin + d
				while board.is_passable(c):
					if _at(occ, c) == null:
						out.append(c)
					c += d
		Consts.Skill.ONSLAUGHT:  # любой орто-сосед: направление фиксируется вслепую
			for d in Consts.DIRS4:
				var c: Vector2i = origin + d
				if board.is_passable(c):
					out.append(c)
		Consts.Skill.PRECISE:  # строго дальность PRECISE_RANGE (манхэттен)
			for dy in range(-Consts.PRECISE_RANGE, Consts.PRECISE_RANGE + 1):
				for dx in range(-Consts.PRECISE_RANGE, Consts.PRECISE_RANGE + 1):
					if absi(dx) + absi(dy) != Consts.PRECISE_RANGE:
						continue
					var c := origin + Vector2i(dx, dy)
					if board.is_passable(c):
						out.append(c)
		Consts.Skill.HUNT_MARK:  # враг в радиусе HUNT_RANGE (манхэттен)
			_ring(board, origin, 1, Consts.HUNT_RANGE, out)
		Consts.Skill.NET:  # цель в радиусе NET_RANGE (манхэттен)
			_ring(board, origin, 1, Consts.NET_RANGE, out)
		Consts.Skill.BLEED:  # враг в радиусе BLEED_RANGE (манхэттен)
			_ring(board, origin, 1, Consts.BLEED_RANGE, out)
		Consts.Skill.SPARK:  # цель на дальности до SPARK_RANGE
			_ring(board, origin, 1, Consts.SPARK_RANGE, out)
		Consts.Skill.DISORIENT:  # враг в радиусе DISORIENT_RANGE
			_ring(board, origin, 1, Consts.DISORIENT_RANGE, out)
		Consts.Skill.SHACKLES:  # враг в радиусе SHACKLES_RANGE
			_ring(board, origin, 1, Consts.SHACKLES_RANGE, out)
		Consts.Skill.SLOW:  # враг в радиусе SLOW_RANGE
			_ring(board, origin, 1, Consts.SLOW_RANGE, out)
		Consts.Skill.MANASTEAL:  # соседний (8 сторон) враг
			for d in Consts.DIRS8:
				var c: Vector2i = origin + d
				if board.is_passable(c):
					out.append(c)
		Consts.Skill.TELEPORT:  # свободная клетка в радиусе TELEPORT_RANGE (манхэттен)
			for dy in range(-Consts.TELEPORT_RANGE, Consts.TELEPORT_RANGE + 1):
				for dx in range(-Consts.TELEPORT_RANGE, Consts.TELEPORT_RANGE + 1):
					var m := absi(dx) + absi(dy)
					if m < 1 or m > Consts.TELEPORT_RANGE:
						continue
					var c := origin + Vector2i(dx, dy)
					if board.is_passable(c) and _at(occ, c) == null and not state.grave_at(c):
						out.append(c)
		Consts.Skill.REVIVE:  # любая могила союзника на доске (радиус не ограничен)
			for du in state.units:
				if not du.alive and du.owner == unit.owner:
					out.append(du.cell)
		Consts.Skill.MINEFIELD:  # центр поля в радиусе MINEFIELD_RANGE (манхэттен)
			_ring(board, origin, 1, Consts.MINEFIELD_RANGE, out)
		Consts.Skill.RETREAT:  # путь до RETREAT_RANGE, только если рядом есть враг
			if _enemy_adjacent(origin, unit.owner, occ):
				for c in move_paths(state, origin, unit.id, occ, Consts.RETREAT_RANGE).keys():
					out.append(c)
		Consts.Skill.OVERLOAD:  # любой орто-сосед (как Натиск — целим вслепую)
			for d in Consts.DIRS4:
				var c: Vector2i = origin + d
				if board.is_passable(c):
					out.append(c)
		Consts.Skill.SWAP:  # соседний (8 сторон) занятый юнитом — с ним и меняемся
			for d in Consts.DIRS8:
				var c: Vector2i = origin + d
				if board.is_passable(c) and _at(occ, c) != null:
					out.append(c)
	return out
