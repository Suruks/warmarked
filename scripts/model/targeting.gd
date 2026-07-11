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
static func move_paths(state: MatchState, origin: Vector2i, self_id: int, occ: Dictionary = {}) -> Dictionary:
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
		if dist[cur] >= Consts.MOVE_RANGE:
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
			for c in move_paths(state, origin, unit.id, occ).keys():
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
