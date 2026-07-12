class_name Maps
extends RefCounted

## Каталог карт как ASCII (7×7). Каждый матч стартует на случайной карте (индекс выбирает
## СЕРВЕР и рассылает клиентам — иначе детерминированный лок-степ разъедется).
##
## Легенда клетки:
##   1 — спаун первого игрока (A),   2 — спаун второго игрока (B),
##   0 — пусто,   V — победная клетка (точка контроля),   B — блок (препятствие).
## Координаты: x — столбец (0..6, слева направо), y — строка (0..6, сверху вниз).
## У каждой карты должно быть ровно TEAM_SIZE спаунов каждого игрока.

const LAYOUTS: Array = [
	# 0 — базовая (ромб стен, диагональ точек) — та, что была до ротации
	["0202020",
	 "000B000",
	 "00V0000",
	 "0B0V0B0",
	 "0000V00",
	 "000B000",
	 "0101010"],
	# 1 — вертикальные ворота, две точки по центру
	["0202020",
	 "0000000",
	 "000B000",
	 "00V0V00",
	 "000B000",
	 "0000000",
	 "0101010"],
	# 2 — диагональ: углы-блоки, крест из точек, спауны по диагонали
	["BB00200",
	 "B000020",
	 "000V002",
	 "00VBV00",
	 "100V000",
	 "010000B",
	 "00100BB"],
	# 3 — вертикальный коридор точек
	["0002020",
	 "000B002",
	 "000V000",
	 "000V000",
	 "000V000",
	 "100B000",
	 "0101000"],
]


static func count() -> int:
	return LAYOUTS.size()


# Разбор карты по индексу → {obstacles, control_points, spawns_a, spawns_b}.
# Некорректный индекс → карта 0 (матч не роняем).
static func parse(index: int) -> Dictionary:
	var i: int = index if (index >= 0 and index < LAYOUTS.size()) else 0
	var rows: Array = LAYOUTS[i]
	var obstacles := {}
	var control_points: Array[Vector2i] = []
	var spawns_a: Array[Vector2i] = []
	var spawns_b: Array[Vector2i] = []
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var cell := Vector2i(x, y)
			match row[x]:
				"B": obstacles[cell] = true
				"V": control_points.append(cell)
				"1": spawns_a.append(cell)
				"2": spawns_b.append(cell)
	return {
		"obstacles": obstacles,
		"control_points": control_points,
		"spawns_a": spawns_a,
		"spawns_b": spawns_b,
	}
